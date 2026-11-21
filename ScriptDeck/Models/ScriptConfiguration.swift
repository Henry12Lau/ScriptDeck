import CoreGraphics
import Foundation

/// Persistent user configuration for a single local script.
/// Never stores runtime process handles, PIDs, or running state.
struct ScriptConfiguration: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var name: String
    var directory: String
    var command: String

    init(
        id: UUID = UUID(),
        name: String,
        directory: String,
        command: String
    ) {
        self.id = id
        self.name = name
        self.directory = directory
        self.command = command
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case directory
        case command
        // Legacy keys for backward-compatible decoding
        case executablePath
        case arguments
        case workingDirectory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)

        if let dir = try container.decodeIfPresent(String.self, forKey: .directory) {
            directory = dir
        } else {
            directory = try container.decode(String.self, forKey: .workingDirectory)
        }

        if let cmd = try container.decodeIfPresent(String.self, forKey: .command) {
            command = cmd
        } else {
            let executablePath = try container.decode(String.self, forKey: .executablePath)
            let arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
            command = CommandSummaryFormatter.shellCommand(executablePath: executablePath, arguments: arguments)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(directory, forKey: .directory)
        try container.encode(command, forKey: .command)
    }
}

/// Formats display-only command summaries and hover tooltips.
enum CommandSummaryFormatter {
    static func summary(for configuration: ScriptConfiguration) -> String {
        configuration.command.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func tooltip(for configuration: ScriptConfiguration) -> String {
        let dir = configuration.directory.trimmingCharacters(in: .whitespacesAndNewlines)
        let cmd = configuration.command.trimmingCharacters(in: .whitespacesAndNewlines)
        if dir.isEmpty {
            return cmd
        }
        return "\(dir)\n\(cmd)"
    }

    static func shellCommand(executablePath: String, arguments: [String]) -> String {
        ([executablePath] + arguments).map { token in
            if token.isEmpty { return "''" }
            if token.contains(where: { $0.isWhitespace || $0 == "'" || $0 == "\"" }) {
                let escaped = token.replacingOccurrences(of: "'", with: "'\\''")
                return "'\(escaped)'"
            }
            return token
        }.joined(separator: " ")
    }
}

/// Reorders saved scripts. The resulting array order is the display order.
enum ScriptReorder {
    /// `index` is the final position in the array, including the last slot.
    static func moving(_ scripts: [ScriptConfiguration], id: UUID, to index: Int) -> [ScriptConfiguration] {
        guard let from = scripts.firstIndex(where: { $0.id == id }) else { return scripts }
        let destination = min(max(index, 0), scripts.count - 1)
        guard from != destination else { return scripts }
        var updated = scripts
        let script = updated.remove(at: from)
        updated.insert(script, at: destination)
        return updated
    }

    /// Index where `draggingIndex` should land, using frozen row frames from drag start.
    /// Passing the midpoint of another row moves past it. The dragged row's own frame is ignored,
    /// so the last slot is reachable once the pointer is below the last other row's midpoint.
    static func destinationIndex(cursorY: CGFloat, frames: [CGRect], draggingIndex: Int) -> Int {
        guard !frames.isEmpty else { return 0 }
        var index = 0
        for (offset, frame) in frames.enumerated() where offset != draggingIndex {
            if cursorY > frame.midY {
                index += 1
            }
        }
        return min(index, frames.count - 1)
    }

    static func moving(_ scripts: [ScriptConfiguration], id: UUID, before targetID: UUID) -> [ScriptConfiguration] {
        guard id != targetID,
              let from = scripts.firstIndex(where: { $0.id == id }),
              let to = scripts.firstIndex(where: { $0.id == targetID }) else {
            return scripts
        }
        let destination = from < to ? to - 1 : to
        return moving(scripts, id: id, to: destination)
    }

    static func movingUp(_ scripts: [ScriptConfiguration], id: UUID) -> [ScriptConfiguration] {
        guard let index = scripts.firstIndex(where: { $0.id == id }), index > 0 else {
            return scripts
        }
        return moving(scripts, id: id, before: scripts[index - 1].id)
    }

    static func movingDown(_ scripts: [ScriptConfiguration], id: UUID) -> [ScriptConfiguration] {
        guard let index = scripts.firstIndex(where: { $0.id == id }), index + 1 < scripts.count else {
            return scripts
        }
        var updated = scripts
        updated.swapAt(index, index + 1)
        return updated
    }
}
