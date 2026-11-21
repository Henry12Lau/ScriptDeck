import Foundation

struct ScriptValidationErrors: Equatable {
    var nameError: String?
    var directoryError: String?
    var commandError: String?

    var isValid: Bool {
        nameError == nil &&
        directoryError == nil &&
        commandError == nil
    }
}

struct FileSystemChecker: Sendable {
    var fileExists: @Sendable (String) -> (exists: Bool, isDirectory: Bool)

    static let live = FileSystemChecker(
        fileExists: { path in
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            return (exists, isDir.boolValue)
        }
    )
}

enum ScriptValidator {
    static func validate(
        name: String,
        directory: String,
        command: String,
        checker: FileSystemChecker = .live
    ) -> ScriptValidationErrors {
        var errors = ScriptValidationErrors()

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.nameError = "Name is required."
        }

        let cleanDir = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanDir.isEmpty {
            errors.directoryError = "Directory is required."
        } else if !cleanDir.hasPrefix("/") {
            errors.directoryError = "Directory must be an absolute path."
        } else {
            let status = checker.fileExists(cleanDir)
            if !status.exists {
                errors.directoryError = "Directory does not exist."
            } else if !status.isDirectory {
                errors.directoryError = "Path must be a folder."
            }
        }

        if command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.commandError = "Command is required."
        }

        return errors
    }
}
