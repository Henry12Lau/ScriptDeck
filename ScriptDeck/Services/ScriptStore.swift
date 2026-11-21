import Foundation

enum ScriptStoreError: LocalizedError, Equatable {
    case directoryCreationFailed(String)
    case readFailed(String)
    case decodeFailed(String)
    case encodeFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let detail):
            return "Could not create ScriptDeck storage folder: \(detail)"
        case .readFailed(let detail):
            return "Could not read saved scripts: \(detail)"
        case .decodeFailed(let detail):
            return "Saved scripts file is invalid or corrupted: \(detail)"
        case .encodeFailed(let detail):
            return "Could not encode scripts for saving: \(detail)"
        case .writeFailed(let detail):
            return "Could not save scripts: \(detail)"
        }
    }
}

/// Persists script configurations as atomic JSON inside Application Support/ScriptDeck.
/// File permissions are restricted to the local user (0700 dir, 0600 file).
actor ScriptStore {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            self.fileURL = appSupport
                .appendingPathComponent("ScriptDeck", isDirectory: true)
                .appendingPathComponent("scripts.json", isDirectory: false)
        }
    }

    func load() throws -> [ScriptConfiguration] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ScriptStoreError.readFailed(error.localizedDescription)
        }

        if data.isEmpty {
            return []
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode([ScriptConfiguration].self, from: data)
        } catch {
            throw ScriptStoreError.decodeFailed(error.localizedDescription)
        }
    }

    func save(_ scripts: [ScriptConfiguration]) throws {
        let fm = FileManager.default
        let directoryURL = fileURL.deletingLastPathComponent()

        do {
            try fm.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            // Ensure directory permissions remain restricted even if it already existed.
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        } catch {
            throw ScriptStoreError.directoryCreationFailed(error.localizedDescription)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(scripts)
        } catch {
            throw ScriptStoreError.encodeFailed(error.localizedDescription)
        }

        do {
            try data.write(to: fileURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            throw ScriptStoreError.writeFailed(error.localizedDescription)
        }
    }
}
