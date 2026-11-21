import XCTest
@testable import ScriptDeck

final class ScriptConfigurationTests: XCTestCase {
    func testCodableRoundTripPreservesAllFields() throws {
        let id = UUID()
        let config = ScriptConfiguration(
            id: id,
            name: "Web Frontend",
            directory: "/Users/me/my project",
            command: "npm run dev"
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ScriptConfiguration.self, from: data)

        XCTAssertEqual(decoded, config)
    }

    func testLegacyConfigurationMigratesCleanly() throws {
        let id = UUID()
        let legacyJSON = """
        {
          "id": "\(id.uuidString)",
          "name": "Legacy Worker",
          "executablePath": "/Users/me/my project/.venv/bin/python3",
          "arguments": ["/Users/me/my project/sync.py", "--interval", "60"],
          "workingDirectory": "/Users/me/my project",
          "environment": {}
        }
        """

        let decoded = try JSONDecoder().decode(ScriptConfiguration.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.name, "Legacy Worker")
        XCTAssertEqual(decoded.directory, "/Users/me/my project")
        XCTAssertEqual(
            decoded.command,
            "'/Users/me/my project/.venv/bin/python3' '/Users/me/my project/sync.py' --interval 60"
        )
    }

    func testDurationFormatterFormatsZeroAndHours() {
        XCTAssertEqual(DurationFormatter.format(nil), "—")
        XCTAssertEqual(DurationFormatter.format(0), "00:00:00")
        XCTAssertEqual(DurationFormatter.format(65), "00:01:05")
        XCTAssertEqual(DurationFormatter.format(3661), "01:01:01")
    }

    func testStatusSummaryOrderingAndZeroOmission() {
        XCTAssertEqual(StatusSummaryFormatter.subtitle(for: []), "")

        let states = [
            ScriptRuntimeState(status: .failed),
            ScriptRuntimeState(status: .running),
            ScriptRuntimeState(status: .stopped),
            ScriptRuntimeState(status: .running),
            ScriptRuntimeState(status: .starting)
        ]

        XCTAssertEqual(
            StatusSummaryFormatter.subtitle(for: states),
            "2 Running · 1 Starting · 1 Stopped · 1 Failed"
        )
    }

    func testManualReorderMovesScriptBeforeTargetAndStepsByOne() {
        let scripts = [
            ScriptConfiguration(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "A", directory: "/a", command: "a"),
            ScriptConfiguration(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "B", directory: "/b", command: "b"),
            ScriptConfiguration(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "C", directory: "/c", command: "c"),
            ScriptConfiguration(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "D", directory: "/d", command: "d")
        ]
        let ids = scripts.map(\.id)

        let movedBefore = ScriptReorder.moving(scripts, id: ids[0], before: ids[2]).map(\.name)
        XCTAssertEqual(movedBefore, ["B", "A", "C", "D"])

        let movedToFront = ScriptReorder.moving(scripts, id: ids[3], before: ids[0]).map(\.name)
        XCTAssertEqual(movedToFront, ["D", "A", "B", "C"])

        XCTAssertEqual(ScriptReorder.moving(scripts, id: ids[1], before: ids[1]).map(\.name), ["A", "B", "C", "D"])
        XCTAssertEqual(ScriptReorder.movingUp(scripts, id: ids[0]).map(\.name), ["A", "B", "C", "D"])
        XCTAssertEqual(ScriptReorder.movingDown(scripts, id: ids[3]).map(\.name), ["A", "B", "C", "D"])
        XCTAssertEqual(ScriptReorder.movingUp(scripts, id: ids[2]).map(\.name), ["A", "C", "B", "D"])
        XCTAssertEqual(ScriptReorder.movingDown(scripts, id: ids[1]).map(\.name), ["A", "C", "B", "D"])

        XCTAssertEqual(ScriptReorder.moving(scripts, id: ids[0], to: 3).map(\.name), ["B", "C", "D", "A"])
        XCTAssertEqual(ScriptReorder.moving(scripts, id: ids[3], to: 0).map(\.name), ["D", "A", "B", "C"])
        XCTAssertEqual(ScriptReorder.moving(scripts, id: ids[1], to: 99).map(\.name), ["A", "C", "D", "B"])
        XCTAssertEqual(ScriptReorder.moving(scripts, id: ids[0], to: 0).map(\.name), ["A", "B", "C", "D"])

        let frames = [
            CGRect(x: 0, y: 0, width: 700, height: 80),
            CGRect(x: 0, y: 92, width: 700, height: 80),
            CGRect(x: 0, y: 184, width: 700, height: 80),
            CGRect(x: 0, y: 276, width: 700, height: 80)
        ]
        XCTAssertEqual(ScriptReorder.destinationIndex(cursorY: 400, frames: frames, draggingIndex: 0), 3)
        XCTAssertEqual(ScriptReorder.destinationIndex(cursorY: 320, frames: frames, draggingIndex: 0), 3)
        XCTAssertEqual(ScriptReorder.destinationIndex(cursorY: 300, frames: frames, draggingIndex: 0), 2)
        XCTAssertEqual(ScriptReorder.destinationIndex(cursorY: 10, frames: frames, draggingIndex: 2), 0)
        XCTAssertEqual(ScriptReorder.destinationIndex(cursorY: 200, frames: frames, draggingIndex: 3), 2)
    }
}
