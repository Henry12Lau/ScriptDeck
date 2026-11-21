import AppKit
import Darwin
import Foundation

private final class ManagedProcessSession: @unchecked Sendable {
    let id: UUID
    let process: Process
    let pid: pid_t
    let startedAt: Date
    let command: String
    private let outputReader: PTYOutputReader?

    private let lock = NSLock()
    private var _isStoppingByUser = false
    private var _leaderExited = false
    private var exitWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    init(
        id: UUID,
        process: Process,
        pid: pid_t,
        startedAt: Date,
        command: String,
        outputReader: PTYOutputReader? = nil
    ) {
        self.id = id
        self.process = process
        self.pid = pid
        self.startedAt = startedAt
        self.command = command
        self.outputReader = outputReader
    }

    var isStoppingByUser: Bool {
        lock.withLock { _isStoppingByUser }
    }

    var leaderExited: Bool {
        lock.withLock { _leaderExited }
    }

    func markStoppingByUser() {
        lock.withLock {
            _isStoppingByUser = true
        }
    }

    func markLeaderExited() {
        let waiters: [CheckedContinuation<Void, Never>] = lock.withLock {
            _leaderExited = true
            let copy = Array(exitWaiters.values)
            exitWaiters.removeAll()
            return copy
        }
        for waiter in waiters {
            waiter.resume()
        }
        outputReader?.schedulePostExitDrainAndCancel()
    }

    func waitForLeaderExit(until deadline: Date? = nil) async {
        let alreadyExited = lock.withLock { _leaderExited }
        if alreadyExited { return }

        if let deadline, deadline.timeIntervalSinceNow <= 0 {
            return
        }

        let waiterID = UUID()
        await withCheckedContinuation { continuation in
            let shouldResumeImmediately: Bool = lock.withLock {
                if _leaderExited {
                    return true
                }
                exitWaiters[waiterID] = continuation
                return false
            }
            if shouldResumeImmediately {
                continuation.resume()
                return
            }

            if let deadline {
                let delay = max(0, deadline.timeIntervalSinceNow)
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    let timedOutWaiter = self.lock.withLock {
                        self.exitWaiters.removeValue(forKey: waiterID)
                    }
                    timedOutWaiter?.resume()
                }
            }
        }
    }
}

private struct LaunchPreflightFailure: Error {
    let summary: String
    let detail: String
}

/// Manages local script execution via Foundation.Process and ScriptDeckLauncher.
/// UI-observable states are updated strictly on @MainActor; process spawning and
/// termination waiting run off the main thread.
@MainActor
@Observable
final class ProcessManager {
    private(set) var states: [UUID: ScriptRuntimeState] = [:] {
        didSet {
            onStatesChanged?()
        }
    }
    private(set) var isQuitting = false

    @ObservationIgnored
    var onStatesChanged: (@MainActor () -> Void)?

    @ObservationIgnored
    private var activeSessions: [UUID: ManagedProcessSession] = [:]

    @ObservationIgnored
    private var outputBuffers: [UUID: ScriptOutputBuffer] = [:]

    @ObservationIgnored
    private let outputQueue = DispatchQueue(
        label: "com.scriptdeck.pty-output",
        qos: .utility
    )

    @ObservationIgnored
    private let stopGracePeriod: TimeInterval

    @ObservationIgnored
    private let launcherURLProvider: @Sendable () -> URL?

    @ObservationIgnored
    private let processQueue = DispatchQueue(
        label: "com.scriptdeck.process-manager",
        qos: .userInitiated,
        attributes: .concurrent
    )

    init(
        stopGracePeriod: TimeInterval = 5.0,
        launcherURLProvider: (@Sendable () -> URL?)? = nil
    ) {
        self.stopGracePeriod = stopGracePeriod
        self.launcherURLProvider = launcherURLProvider ?? {
            Bundle.main.url(forAuxiliaryExecutable: "ScriptDeckLauncher")
        }
    }

    var hasActiveScripts: Bool {
        states.values.contains { $0.status.isActive }
    }

    var hasRunningScriptsForTimer: Bool {
        states.values.contains { $0.status == .running || $0.status == .stopping }
    }

    func state(for id: UUID) -> ScriptRuntimeState {
        states[id] ?? .initial
    }

    func seedPreviewStates(_ previewStates: [UUID: ScriptRuntimeState]) {
        states = previewStates
    }

    func resetStateIfInactive(for id: UUID) {
        guard !state(for: id).status.isActive else { return }
        states[id] = .initial
    }

    func removeState(for id: UUID) {
        guard !state(for: id).status.isActive else { return }
        states.removeValue(forKey: id)
        outputBuffers.removeValue(forKey: id)
    }

    func outputSnapshot(for id: UUID) -> (lines: [String], revision: UInt64) {
        outputBuffers[id]?.snapshot() ?? ([], 0)
    }

    func clearOutput(for id: UUID) {
        outputBuffers[id]?.clear()
    }

    private func obtainOutputBuffer(for id: UUID) -> ScriptOutputBuffer {
        if let existing = outputBuffers[id] {
            return existing
        }
        let created = ScriptOutputBuffer(maxLines: 50)
        outputBuffers[id] = created
        return created
    }

    func beginQuitShutdown() {
        isQuitting = true
    }

    func start(_ configuration: ScriptConfiguration) {
        let id = configuration.id
        guard !isQuitting else { return }
        guard state(for: id).status.canStart, activeSessions[id] == nil else { return }

        states[id] = ScriptRuntimeState(
            status: .starting,
            startedAt: nil,
            lastDuration: nil,
            failureSummary: nil,
            failureDetail: nil,
            stopErrorDetail: nil
        )

        let launcherProvider = self.launcherURLProvider
        let queue = self.processQueue
        let outputQueue = self.outputQueue
        let outputBuffer = obtainOutputBuffer(for: id)
        outputBuffer.clear()

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            do {
                let launcherURL = try Self.preflightCheck(
                    configuration: configuration,
                    launcherProvider: launcherProvider
                )

                let pty = try Self.openPTY()
                let slaveHandle = FileHandle(fileDescriptor: pty.slaveFD, closeOnDealloc: false)
                let ptyReader = PTYOutputReader(
                    masterFD: pty.masterFD,
                    buffer: outputBuffer,
                    queue: outputQueue
                )

                let process = Process()
                process.executableURL = launcherURL
                process.arguments = ["/bin/zsh", "-lc", configuration.command]
                process.currentDirectoryURL = URL(
                    fileURLWithPath: configuration.directory,
                    isDirectory: true
                )
                process.environment = Self.buildLaunchEnvironment()

                // Non-interactive stdin; capture live PTY stdout/stderr into an in-memory 50-line buffer.
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = slaveHandle
                process.standardError = slaveHandle

                let sessionBox = SessionHolder()

                process.terminationHandler = { [weak self] terminatedProcess in
                    let finishedAt = Date()
                    if let session = sessionBox.session {
                        session.markLeaderExited()
                        Task { @MainActor [weak self] in
                            self?.handleProcessTermination(
                                id: id,
                                session: session,
                                reason: terminatedProcess.terminationReason,
                                status: terminatedProcess.terminationStatus,
                                finishedAt: finishedAt
                            )
                        }
                    }
                }

                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    queue.async {
                        do {
                            try process.run()
                            Darwin.close(pty.slaveFD)
                            let pid = process.processIdentifier
                            let session = ManagedProcessSession(
                                id: id,
                                process: process,
                                pid: pid,
                                startedAt: Date(),
                                command: configuration.command,
                                outputReader: ptyReader
                            )
                            sessionBox.session = session
                            continuation.resume()
                        } catch {
                            Darwin.close(pty.slaveFD)
                            ptyReader.cancel()
                            continuation.resume(throwing: error)
                        }
                    }
                }

                guard let session = sessionBox.session else { return }

                await MainActor.run {
                    // Only register if terminationHandler hasn't already fired and cleared it.
                    if !session.leaderExited {
                        self.activeSessions[id] = session
                        self.states[id] = ScriptRuntimeState(
                            status: .running,
                            startedAt: session.startedAt,
                            lastDuration: nil,
                            failureSummary: nil,
                            failureDetail: nil,
                            stopErrorDetail: nil
                        )

                        if self.isQuitting {
                            self.stop(id: id)
                        }
                    } else {
                        // Process exited extremely quickly before MainActor registration.
                        let reason = process.terminationReason
                        let status = process.terminationStatus
                        self.handleFastExit(
                            id: id,
                            session: session,
                            reason: reason,
                            status: status
                        )
                    }
                }
            } catch let failure as LaunchPreflightFailure {
                await MainActor.run {
                    self.activeSessions.removeValue(forKey: id)
                    self.states[id] = ScriptRuntimeState(
                        status: .failed,
                        startedAt: nil,
                        lastDuration: nil,
                        failureSummary: failure.summary,
                        failureDetail: failure.detail,
                        stopErrorDetail: nil
                    )
                }
            } catch {
                await MainActor.run {
                    self.activeSessions.removeValue(forKey: id)
                    self.states[id] = ScriptRuntimeState(
                        status: .failed,
                        startedAt: nil,
                        lastDuration: nil,
                        failureSummary: "Launch failed",
                        failureDetail: error.localizedDescription,
                        stopErrorDetail: nil
                    )
                }
            }
        }
    }

    func stop(id: UUID) {
        guard state(for: id).status.canStop else { return }
        guard let session = activeSessions[id] else { return }

        session.markStoppingByUser()
        let current = state(for: id)
        states[id] = ScriptRuntimeState(
            status: .stopping,
            startedAt: current.startedAt,
            lastDuration: current.lastDuration,
            failureSummary: nil,
            failureDetail: nil,
            stopErrorDetail: nil
        )

        let gracePeriod = self.stopGracePeriod
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let outcome = await Self.terminateSessionGroup(session, gracePeriod: gracePeriod)

            await MainActor.run {
                let finishedAt = Date()
                let duration = max(0, finishedAt.timeIntervalSince(session.startedAt))

                switch outcome {
                case .stopped:
                    self.activeSessions.removeValue(forKey: id)
                    self.states[id] = ScriptRuntimeState(
                        status: .stopped,
                        startedAt: nil,
                        lastDuration: duration,
                        failureSummary: nil,
                        failureDetail: nil,
                        stopErrorDetail: nil
                    )
                case .failed(let message):
                    if session.leaderExited {
                        self.activeSessions.removeValue(forKey: id)
                        self.states[id] = ScriptRuntimeState(
                            status: .failed,
                            startedAt: nil,
                            lastDuration: duration,
                            failureSummary: "Stop failed",
                            failureDetail: message,
                            stopErrorDetail: nil
                        )
                    } else {
                        // Do not pretend the script stopped if it is still running.
                        self.states[id] = ScriptRuntimeState(
                            status: .running,
                            startedAt: session.startedAt,
                            lastDuration: nil,
                            failureSummary: nil,
                            failureDetail: nil,
                            stopErrorDetail: message
                        )
                    }
                }
            }
        }
    }

    func stopAllForQuit() async {
        beginQuitShutdown()

        // Snapshot scripts currently running, and wait briefly if any are still starting.
        while states.values.contains(where: { $0.status == .starting }) {
            try? await Task.sleep(for: .milliseconds(50))
        }

        let runningIDs = states.compactMap { id, state in
            state.status == .running ? id : nil
        }

        for id in runningIDs {
            stop(id: id)
        }

        while hasActiveScripts {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func handleFastExit(
        id: UUID,
        session: ManagedProcessSession,
        reason: Process.TerminationReason,
        status: Int32
    ) {
        // Avoid double-processing if handleProcessTermination already ran on MainActor.
        guard states[id]?.status == .starting else { return }
        handleProcessTermination(
            id: id,
            session: session,
            reason: reason,
            status: status,
            finishedAt: Date()
        )
    }

    private func handleProcessTermination(
        id: UUID,
        session: ManagedProcessSession,
        reason: Process.TerminationReason,
        status: Int32,
        finishedAt: Date
    ) {
        // User-initiated stop finalizes state inside stop() after confirming the entire process group exited.
        if session.isStoppingByUser {
            return
        }

        // Only update if this session is still the latest active session for id.
        if let active = activeSessions[id], active !== session {
            return
        }

        activeSessions.removeValue(forKey: id)
        let duration = max(0, finishedAt.timeIntervalSince(session.startedAt))

        switch reason {
        case .exit:
            if status == 0 {
                states[id] = ScriptRuntimeState(
                    status: .stopped,
                    startedAt: nil,
                    lastDuration: duration,
                    failureSummary: nil,
                    failureDetail: nil,
                    stopErrorDetail: nil
                )
            } else {
                states[id] = ScriptRuntimeState(
                    status: .failed,
                    startedAt: nil,
                    lastDuration: duration,
                    failureSummary: "Exit code \(status)",
                    failureDetail: Self.exitFailureDetail(
                        code: status,
                        command: session.command
                    ),
                    stopErrorDetail: nil
                )
            }
        case .uncaughtSignal:
            states[id] = ScriptRuntimeState(
                status: .failed,
                startedAt: nil,
                lastDuration: duration,
                failureSummary: "Signal \(status)",
                failureDetail: "Process terminated by uncaught signal \(status).",
                stopErrorDetail: nil
            )
        @unknown default:
            states[id] = ScriptRuntimeState(
                status: .failed,
                startedAt: nil,
                lastDuration: duration,
                failureSummary: "Exit code \(status)",
                failureDetail: "Process exited unexpectedly with status \(status).",
                stopErrorDetail: nil
            )
        }
    }

    // MARK: - Non-MainActor Helpers

    private nonisolated static func preflightCheck(
        configuration: ScriptConfiguration,
        launcherProvider: @Sendable () -> URL?
    ) throws -> URL {
        guard let launcherURL = launcherProvider(),
              FileManager.default.isExecutableFile(atPath: launcherURL.path) else {
            throw LaunchPreflightFailure(
                summary: "Launcher helper missing",
                detail: "ScriptDeckLauncher helper executable could not be found in the application bundle."
            )
        }

        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: configuration.directory, isDirectory: &isDirectory) else {
            throw LaunchPreflightFailure(
                summary: "Directory not found",
                detail: "The folder does not exist:\n\(configuration.directory)"
            )
        }
        guard isDirectory.boolValue else {
            throw LaunchPreflightFailure(
                summary: "Invalid directory",
                detail: "The directory path is not a folder:\n\(configuration.directory)"
            )
        }

        if configuration.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LaunchPreflightFailure(
                summary: "Empty command",
                detail: "No command was configured to run."
            )
        }

        guard Darwin.access("/bin/zsh", X_OK) == 0 else {
            throw LaunchPreflightFailure(
                summary: "Shell unavailable",
                detail: "/bin/zsh is missing or not executable."
            )
        }

        return launcherURL
    }

    nonisolated static func buildLaunchEnvironment(
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        defaultBrowserPathProvider: () -> String? = resolveDefaultBrowserApplicationPath
    ) -> [String: String] {
        var env = baseEnvironment
        let defaultPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let existingPaths = (env["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }

        var combined = existingPaths
        for path in defaultPaths where !combined.contains(path) {
            combined.append(path)
        }
        env["PATH"] = combined.joined(separator: ":")

        // Dev servers like Vite and react-dev-utils prefer Google Chrome via AppleScript
        // on macOS when BROWSER is unset; pin BROWSER to the macOS default HTTPS browser.
        let existingBrowser = (env["BROWSER"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if existingBrowser.isEmpty, let defaultBrowserPath = defaultBrowserPathProvider() {
            env["BROWSER"] = defaultBrowserPath
        }

        return env
    }

    nonisolated static func resolveDefaultBrowserApplicationPath() -> String? {
        guard let httpsURL = URL(string: "https://"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: httpsURL) else {
            return nil
        }
        return appURL.path
    }

    private nonisolated static func exitFailureDetail(code: Int32, command: String) -> String {
        if code == 126 {
            return "Permission denied or command not executable (exit code 126):\n\(command)"
        }
        if code == 127 {
            return "Command not found (exit code 127):\n\(command)"
        }
        return "The command exited with non-zero status code \(code)."
    }

    private enum StopOutcome {
        case stopped
        case failed(String)
    }

    private nonisolated static func terminateSessionGroup(
        _ session: ManagedProcessSession,
        gracePeriod: TimeInterval
    ) async -> StopOutcome {
        let pid = session.pid
        let ownPGID = getpgrp()

        // Allow a brief microsecond window for ScriptDeckLauncher's setpgid(0, 0)
        // if Stop was clicked right as the process launched.
        var pgid = getpgid(pid)
        var attempts = 0
        while pgid == ownPGID && attempts < 20 && !session.leaderExited {
            try? await Task.sleep(for: .milliseconds(5))
            pgid = getpgid(pid)
            attempts += 1
        }

        let hasIsolatedGroup = (pgid == pid && pgid > 0 && pgid != ownPGID)
        let targetID: pid_t = hasIsolatedGroup ? -pgid : pid

        // Step 1: Send SIGTERM to the isolated process group (or pid fallback).
        if kill(targetID, SIGTERM) != 0 {
            let err = errno
            if err != ESRCH {
                return .failed("Failed to send SIGTERM: \(String(cString: strerror(err)))")
            }
            // Already exited before SIGTERM.
            await session.waitForLeaderExit()
            return .stopped
        }

        // Step 2: Wait up to gracePeriod (default 5s) for leader and all group members to exit.
        let deadline = Date().addingTimeInterval(gracePeriod)
        await session.waitForLeaderExit(until: deadline)

        // If leader exited and we have an isolated group, wait for any lingering children
        // in that process group up to the remaining grace period before escalating.
        if hasIsolatedGroup {
            while Date() < deadline && isGroupAlive(pgid: pgid) {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }

        let needsKill = !session.leaderExited || (hasIsolatedGroup && isGroupAlive(pgid: pgid))
        if needsKill {
            // Step 3: Escalate to SIGKILL for the process group.
            if kill(targetID, SIGKILL) != 0 {
                let err = errno
                if err != ESRCH {
                    return .failed("Failed to send SIGKILL: \(String(cString: strerror(err)))")
                }
            }

            let killDeadline = Date().addingTimeInterval(1.0)
            await session.waitForLeaderExit(until: killDeadline)
            while Date() < killDeadline && (hasIsolatedGroup && isGroupAlive(pgid: pgid)) {
                try? await Task.sleep(for: .milliseconds(25))
            }

            if !session.leaderExited && kill(pid, 0) == 0 {
                return .failed("Process did not terminate after SIGKILL.")
            }
        }

        await session.waitForLeaderExit(until: Date().addingTimeInterval(1.0))
        return .stopped
    }

    private nonisolated static func isGroupAlive(pgid: pid_t) -> Bool {
        if kill(-pgid, 0) == 0 {
            return true
        }
        return errno != ESRCH
    }

    private nonisolated static func openPTY() throws -> (masterFD: Int32, slaveFD: Int32) {
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        var windowSize = winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)

        guard Darwin.openpty(&masterFD, &slaveFD, nil, nil, &windowSize) == 0 else {
            let err = errno
            throw LaunchPreflightFailure(
                summary: "Failed to allocate terminal PTY",
                detail: "openpty failed: \(String(cString: strerror(err)))"
            )
        }

        _ = Darwin.fcntl(masterFD, F_SETFD, FD_CLOEXEC)
        let flags = Darwin.fcntl(masterFD, F_GETFL, 0)
        if flags >= 0 {
            _ = Darwin.fcntl(masterFD, F_SETFL, flags | O_NONBLOCK)
        }

        return (masterFD, slaveFD)
    }
}

private final class PTYOutputReader: @unchecked Sendable {
    private let masterFD: Int32
    private let buffer: ScriptOutputBuffer
    private let queue: DispatchQueue
    private let readSource: DispatchSourceRead
    private let lock = NSLock()
    private var isCancelled = false

    init(masterFD: Int32, buffer: ScriptOutputBuffer, queue: DispatchQueue) {
        self.masterFD = masterFD
        self.buffer = buffer
        self.queue = queue

        let source = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: queue)
        self.readSource = source

        source.setEventHandler { [weak self] in
            self?.drainAvailableBytes()
        }

        source.setCancelHandler {
            Darwin.close(masterFD)
        }

        source.resume()
    }

    deinit {
        cancel()
    }

    func schedulePostExitDrainAndCancel() {
        queue.asyncAfter(deadline: .now() + .milliseconds(150)) { [weak self] in
            guard let self else { return }
            self.drainAvailableBytes()
            self.cancel()
        }
    }

    func cancel() {
        let shouldCancel = lock.withLock { () -> Bool in
            guard !isCancelled else { return false }
            isCancelled = true
            return true
        }
        if shouldCancel {
            readSource.cancel()
        }
    }

    private func drainAvailableBytes() {
        let currentlyCancelled = lock.withLock { isCancelled }
        guard !currentlyCancelled else { return }

        var chunk = [UInt8](repeating: 0, count: 8192)
        while true {
            let bytesRead = Darwin.read(masterFD, &chunk, chunk.count)
            if bytesRead > 0 {
                buffer.append(data: Data(chunk[0..<bytesRead]))
            } else if bytesRead == 0 {
                cancel()
                break
            } else {
                let err = errno
                if err == EINTR {
                    continue
                }
                if err == EAGAIN || err == EWOULDBLOCK {
                    break
                }
                // EIO occurs naturally on macOS when the last slave descriptor closes.
                cancel()
                break
            }
        }
    }
}

private final class SessionHolder: @unchecked Sendable {
    var session: ManagedProcessSession?
}
