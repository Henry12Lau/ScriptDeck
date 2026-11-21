import XCTest
import Darwin
@testable import ScriptDeck

@MainActor
final class ProcessManagerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptDeckProcessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func makeScript(named filename: String, body: String, in directory: URL? = nil) throws -> URL {
        let dir = directory ?? tempDir!
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func waitUntil(
        timeout: TimeInterval = 5.0,
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for condition")
    }

    func testMissingDirectoryTransitionsToFailed() async throws {
        let manager = ProcessManager()
        let config = ScriptConfiguration(
            name: "Missing Dir",
            directory: tempDir.appendingPathComponent("does-not-exist").path,
            command: "echo hi"
        )

        manager.start(config)
        try await waitUntil { manager.state(for: config.id).status == .failed }

        XCTAssertEqual(manager.state(for: config.id).failureSummary, "Directory not found")
    }

    func testNormalCompletionTransitionsToStoppedAndPreservesDuration() async throws {
        let manager = ProcessManager()
        let config = ScriptConfiguration(
            name: "Quick OK",
            directory: tempDir.path,
            command: "/bin/sleep 0.1"
        )

        manager.start(config)
        try await waitUntil { manager.state(for: config.id).status == .stopped }

        let state = manager.state(for: config.id)
        XCTAssertNil(state.failureSummary)
        XCTAssertNotNil(state.lastDuration)
    }

    func testNonZeroExitTransitionsToFailedWithExitCode() async throws {
        let manager = ProcessManager()
        let config = ScriptConfiguration(
            name: "Fail Script",
            directory: tempDir.path,
            command: "exit 7"
        )

        manager.start(config)
        try await waitUntil { manager.state(for: config.id).status == .failed }

        let state = manager.state(for: config.id)
        XCTAssertEqual(state.failureSummary, "Exit code 7")
        XCTAssertNotNil(state.lastDuration)
    }

    func testRelativeCommandInSpacedDirectoryWorks() async throws {
        let spacedDir = tempDir.appendingPathComponent("dir with spaces", isDirectory: true)
        let markerURL = spacedDir.appendingPathComponent("output marker.txt")
        _ = try makeScript(
            named: "my worker.sh",
            body: """
            #!/bin/zsh
            echo "$1" > "\(markerURL.path)"
            exit 0
            """,
            in: spacedDir
        )

        let manager = ProcessManager()
        let config = ScriptConfiguration(
            name: "Spaces",
            directory: spacedDir.path,
            command: "./\"my worker.sh\" \"hello world\""
        )

        manager.start(config)
        try await waitUntil { manager.state(for: config.id).status == .stopped }

        let content = try String(contentsOf: markerURL, encoding: .utf8)
        XCTAssertEqual(content.trimmingCharacters(in: .newlines), "hello world")
    }

    func testStopTerminatesChildProcessGroupAndMarksStopped() async throws {
        let childPIDFile = tempDir.appendingPathComponent("child.pid")
        let scriptURL = try makeScript(
            named: "parent.sh",
            body: """
            #!/bin/zsh
            /bin/sleep 60 &
            echo $! > "\(childPIDFile.path)"
            wait
            """
        )

        let manager = ProcessManager(stopGracePeriod: 1.0)
        let config = ScriptConfiguration(
            name: "Parent + Child",
            directory: tempDir.path,
            command: "\"\(scriptURL.path)\""
        )

        manager.start(config)
        try await waitUntil {
            guard manager.state(for: config.id).status == .running,
                  let text = try? String(contentsOf: childPIDFile, encoding: .utf8) else {
                return false
            }
            return pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
        }

        let pidString = try String(contentsOf: childPIDFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let childPID = try XCTUnwrap(pid_t(pidString))
        XCTAssertEqual(kill(childPID, 0), 0, "Child process should be running before Stop")

        manager.stop(id: config.id)
        try await waitUntil(timeout: 5.0) { manager.state(for: config.id).status == .stopped }

        XCTAssertNil(manager.state(for: config.id).failureSummary)
        XCTAssertEqual(kill(childPID, 0), -1)
        XCTAssertEqual(errno, ESRCH, "Child process in process group should be terminated")
    }

    func testStopEscalatesToSIGKILLWhenSigtermIsIgnored() async throws {
        let readyFile = tempDir.appendingPathComponent("trapped.ready")
        let scriptURL = try makeScript(
            named: "ignore_sigterm.sh",
            body: """
            #!/bin/zsh
            trap '' TERM
            /usr/bin/touch "\(readyFile.path)"
            while true; do
              /bin/sleep 1
            done
            """
        )

        let manager = ProcessManager(stopGracePeriod: 0.4)
        let config = ScriptConfiguration(
            name: "Stubborn",
            directory: tempDir.path,
            command: "\"\(scriptURL.path)\""
        )

        manager.start(config)
        try await waitUntil {
            manager.state(for: config.id).status == .running &&
            FileManager.default.fileExists(atPath: readyFile.path)
        }

        manager.stop(id: config.id)
        try await waitUntil(timeout: 5.0) { manager.state(for: config.id).status == .stopped }
        XCTAssertNil(manager.state(for: config.id).failureSummary)
    }

    func testStopDoesNotAffectUnrelatedExternalProcess() async throws {
        let externalProcess = Process()
        externalProcess.executableURL = URL(fileURLWithPath: "/bin/sleep")
        externalProcess.arguments = ["60"]
        externalProcess.standardInput = FileHandle.nullDevice
        externalProcess.standardOutput = FileHandle.nullDevice
        externalProcess.standardError = FileHandle.nullDevice
        try externalProcess.run()
        defer {
            if externalProcess.isRunning {
                externalProcess.terminate()
            }
        }

        let manager = ProcessManager(stopGracePeriod: 1.0)
        let config = ScriptConfiguration(
            name: "Managed Sleep",
            directory: tempDir.path,
            command: "/bin/sleep 60"
        )

        manager.start(config)
        try await waitUntil { manager.state(for: config.id).status == .running }

        manager.stop(id: config.id)
        try await waitUntil { manager.state(for: config.id).status == .stopped }

        XCTAssertTrue(externalProcess.isRunning, "External process outside ScriptDeck must remain untouched")
    }

    func testHeavyStdoutStderrScriptRunsAndStopsCleanly() async throws {
        let readyFile = tempDir.appendingPathComponent("noisy.ready")
        let scriptURL = try makeScript(
            named: "noisy.sh",
            body: """
            #!/bin/zsh
            /usr/bin/touch "\(readyFile.path)"
            i=0
            while [ $i -lt 5000 ]; do
              i=$((i + 1))
              printf 'STDOUT %d\\n' "$i"
              printf 'STDERR %d\\n' "$i" >&2
            done
            /bin/sleep 30
            """
        )

        let manager = ProcessManager(stopGracePeriod: 1.0)
        let config = ScriptConfiguration(
            name: "Noisy",
            directory: tempDir.path,
            command: "\"\(scriptURL.path)\""
        )

        manager.start(config)
        try await waitUntil {
            manager.state(for: config.id).status == .running &&
            FileManager.default.fileExists(atPath: readyFile.path)
        }

        // Duplicate start while running should be ignored.
        manager.start(config)
        XCTAssertEqual(manager.state(for: config.id).status, .running)

        manager.stop(id: config.id)
        try await waitUntil { manager.state(for: config.id).status == .stopped }
    }

    func testConcurrentScriptsAndStopAllForQuit() async throws {
        let manager = ProcessManager(stopGracePeriod: 1.0)
        let config1 = ScriptConfiguration(name: "W1", directory: tempDir.path, command: "/bin/sleep 30")
        let config2 = ScriptConfiguration(name: "W2", directory: tempDir.path, command: "/bin/sleep 30")

        manager.start(config1)
        manager.start(config2)

        try await waitUntil {
            manager.state(for: config1.id).status == .running &&
            manager.state(for: config2.id).status == .running
        }

        await manager.stopAllForQuit()

        XCTAssertTrue(manager.isQuitting)
        XCTAssertFalse(manager.hasActiveScripts)
        XCTAssertEqual(manager.state(for: config1.id).status, .stopped)
        XCTAssertEqual(manager.state(for: config2.id).status, .stopped)
    }

    func testPTYOutputCapturesLatest50LinesAndPreservesAfterExit() async throws {
        let manager = ProcessManager(stopGracePeriod: 1.0)
        let config = ScriptConfiguration(
            name: "Bounded Output",
            directory: tempDir.path,
            command: "i=1; while [ $i -le 80 ]; do echo \"Line $i\"; i=$((i + 1)); done"
        )

        manager.start(config)
        try await waitUntil(timeout: 5.0) {
            manager.state(for: config.id).status == .stopped &&
            manager.outputSnapshot(for: config.id).lines.last == "Line 80"
        }

        let snapshot = manager.outputSnapshot(for: config.id)
        XCTAssertEqual(snapshot.lines.count, 50)
        XCTAssertEqual(snapshot.lines.first, "Line 31")
        XCTAssertEqual(snapshot.lines.last, "Line 80")
    }

    func testPTYOutputStreamsLiveBeforeExitAndCanBeCleared() async throws {
        let manager = ProcessManager(stopGracePeriod: 1.0)
        let config = ScriptConfiguration(
            name: "Live Stream",
            directory: tempDir.path,
            command: "echo 'READY_LINE'; /bin/sleep 30"
        )

        manager.start(config)
        try await waitUntil(timeout: 5.0) {
            manager.state(for: config.id).status == .running &&
            manager.outputSnapshot(for: config.id).lines.contains("READY_LINE")
        }

        manager.clearOutput(for: config.id)
        XCTAssertTrue(manager.outputSnapshot(for: config.id).lines.isEmpty)

        manager.stop(id: config.id)
        try await waitUntil(timeout: 5.0) { manager.state(for: config.id).status == .stopped }
    }

    func testBuildLaunchEnvironmentSetsDefaultBrowserWhenUnset() {
        let env = ProcessManager.buildLaunchEnvironment(
            baseEnvironment: ["PATH": "/usr/bin"],
            defaultBrowserPathProvider: { "/Applications/Firefox.app" }
        )

        XCTAssertEqual(env["BROWSER"], "/Applications/Firefox.app")
        XCTAssertTrue((env["PATH"] ?? "").contains("/opt/homebrew/bin"))
    }

    func testBuildLaunchEnvironmentPreservesExplicitBrowser() {
        let env = ProcessManager.buildLaunchEnvironment(
            baseEnvironment: ["PATH": "/usr/bin", "BROWSER": "none"],
            defaultBrowserPathProvider: { "/Applications/Firefox.app" }
        )

        XCTAssertEqual(env["BROWSER"], "none")
    }
}
