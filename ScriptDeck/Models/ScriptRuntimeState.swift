import Foundation

enum ScriptStatus: String, Equatable, Hashable, Sendable {
    case stopped
    case starting
    case running
    case stopping
    case failed

    var displayLabel: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting: return "Starting…"
        case .running: return "Running"
        case .stopping: return "Stopping…"
        case .failed: return "Failed"
        }
    }

    var isActive: Bool {
        switch self {
        case .starting, .running, .stopping:
            return true
        case .stopped, .failed:
            return false
        }
    }

    var canStart: Bool {
        switch self {
        case .stopped, .failed:
            return true
        case .starting, .running, .stopping:
            return false
        }
    }

    var canStop: Bool {
        self == .running
    }

    var canEditOrRemove: Bool {
        !isActive
    }
}

/// Ephemeral runtime state for a script in memory only.
struct ScriptRuntimeState: Equatable, Sendable {
    var status: ScriptStatus
    var startedAt: Date?
    var lastDuration: TimeInterval?
    var failureSummary: String?
    var failureDetail: String?
    var stopErrorDetail: String?

    init(
        status: ScriptStatus = .stopped,
        startedAt: Date? = nil,
        lastDuration: TimeInterval? = nil,
        failureSummary: String? = nil,
        failureDetail: String? = nil,
        stopErrorDetail: String? = nil
    ) {
        self.status = status
        self.startedAt = startedAt
        self.lastDuration = lastDuration
        self.failureSummary = failureSummary
        self.failureDetail = failureDetail
        self.stopErrorDetail = stopErrorDetail
    }

    static let initial = ScriptRuntimeState()

    func elapsedTime(at now: Date) -> TimeInterval? {
        if status == .running || status == .stopping, let startedAt {
            return max(0, now.timeIntervalSince(startedAt))
        }
        return lastDuration
    }
}

enum DurationFormatter {
    static func format(_ duration: TimeInterval?) -> String {
        guard let duration else { return "—" }
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

enum StatusSummaryFormatter {
    static func subtitle(for states: [ScriptRuntimeState]) -> String {
        guard !states.isEmpty else { return "" }

        var counts: [ScriptStatus: Int] = [:]
        for state in states {
            counts[state.status, default: 0] += 1
        }

        let ordered: [(ScriptStatus, String)] = [
            (.running, "Running"),
            (.starting, "Starting"),
            (.stopping, "Stopping"),
            (.stopped, "Stopped"),
            (.failed, "Failed")
        ]

        let parts: [String] = ordered.compactMap { status, label in
            guard let count = counts[status], count > 0 else { return nil }
            return "\(count) \(label)"
        }

        return parts.joined(separator: " · ")
    }
}
