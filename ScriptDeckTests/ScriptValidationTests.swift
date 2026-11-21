import XCTest
@testable import ScriptDeck

final class ScriptValidationTests: XCTestCase {
    private let mockChecker = FileSystemChecker(
        fileExists: { path in
            if path == "/tmp/work" { return (true, true) }
            if path == "/tmp/file.txt" { return (true, false) }
            return (false, false)
        }
    )

    func testValidConfigurationPasses() {
        let errors = ScriptValidator.validate(
            name: "My App",
            directory: "/tmp/work",
            command: "npm run dev",
            checker: mockChecker
        )

        XCTAssertTrue(errors.isValid)
    }

    func testInvalidFieldsProduceTargetedErrors() {
        let errors = ScriptValidator.validate(
            name: "   ",
            directory: "/missing/dir",
            command: "  ",
            checker: mockChecker
        )

        XCTAssertFalse(errors.isValid)
        XCTAssertEqual(errors.nameError, "Name is required.")
        XCTAssertEqual(errors.directoryError, "Directory does not exist.")
        XCTAssertEqual(errors.commandError, "Command is required.")
    }

    func testRelativeOrFileDirectoryIsRejected() {
        let relativeErrors = ScriptValidator.validate(
            name: "Rel",
            directory: "relative/dir",
            command: "npm run dev",
            checker: mockChecker
        )
        XCTAssertEqual(relativeErrors.directoryError, "Directory must be an absolute path.")

        let fileErrors = ScriptValidator.validate(
            name: "File",
            directory: "/tmp/file.txt",
            command: "npm run dev",
            checker: mockChecker
        )
        XCTAssertEqual(fileErrors.directoryError, "Path must be a folder.")
    }
}
