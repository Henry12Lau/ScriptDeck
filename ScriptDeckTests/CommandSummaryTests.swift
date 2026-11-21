import XCTest
@testable import ScriptDeck

final class CommandSummaryTests: XCTestCase {
    func testSummaryTrimsWhitespace() {
        let config = ScriptConfiguration(
            name: "Web App",
            directory: "/Users/me/web-app",
            command: "  npm run dev  "
        )

        XCTAssertEqual(CommandSummaryFormatter.summary(for: config), "npm run dev")
    }

    func testTooltipIncludesDirectoryAndCommand() {
        let config = ScriptConfiguration(
            name: "Web App",
            directory: "/Users/me/My Project",
            command: "npm run dev -- --port 3000"
        )

        XCTAssertEqual(
            CommandSummaryFormatter.tooltip(for: config),
            "/Users/me/My Project\nnpm run dev -- --port 3000"
        )
    }
}
