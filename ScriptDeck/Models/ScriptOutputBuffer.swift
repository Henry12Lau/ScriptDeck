import Foundation

/// Thread-safe, bounded ring buffer holding at most `maxLines` lines of terminal output.
/// Strips ANSI escape sequences and handles carriage-return overwrites cleanly.
final class ScriptOutputBuffer: @unchecked Sendable {
    let maxLines: Int
    let maxLineLength: Int

    private let lock = NSLock()
    private var completedLines: [String] = []
    private var currentLine: String = ""
    private var pendingCR = false
    private var pendingUTF8 = Data()
    private var escapeState: EscapeParseState = .normal
    private var _revision: UInt64 = 0

    private enum EscapeParseState {
        case normal
        case esc
        case csi
        case osc
        case oscEsc
    }

    init(maxLines: Int = 50, maxLineLength: Int = 2048) {
        self.maxLines = maxLines
        self.maxLineLength = maxLineLength
    }

    var revision: UInt64 {
        lock.withLock { _revision }
    }

    func snapshot() -> (lines: [String], revision: UInt64) {
        lock.withLock {
            var result = completedLines
            if !currentLine.isEmpty {
                result.append(currentLine)
            }
            if result.count > maxLines {
                result = Array(result.suffix(maxLines))
            }
            return (result, _revision)
        }
    }

    func clear() {
        lock.withLock {
            completedLines.removeAll()
            currentLine = ""
            pendingCR = false
            pendingUTF8.removeAll()
            escapeState = .normal
            _revision &+= 1
        }
    }

    func append(data: Data) {
        guard !data.isEmpty else { return }

        lock.withLock {
            var combined = pendingUTF8
            combined.append(data)
            pendingUTF8.removeAll()

            // Hold back any incomplete trailing UTF-8 sequence (at most 3 bytes).
            let validCount = Self.completeUTF8PrefixLength(in: combined)
            if validCount < combined.count {
                pendingUTF8 = combined.subdata(in: validCount..<combined.count)
            }
            guard validCount > 0 else { return }

            let slice = combined.subdata(in: 0..<validCount)
            let text = String(decoding: slice, as: UTF8.self)
            processTextLocked(text)
            _revision &+= 1
        }
    }

    private func processTextLocked(_ text: String) {
        for scalar in text.unicodeScalars {
            switch escapeState {
            case .normal:
                if scalar.value == 0x1B { // ESC
                    if pendingCR {
                        currentLine = ""
                        pendingCR = false
                    }
                    escapeState = .esc
                    continue
                }
                handleNormalScalarLocked(scalar)

            case .esc:
                switch scalar.value {
                case 0x5B: // '[' -> CSI
                    escapeState = .csi
                case 0x5D: // ']' -> OSC
                    escapeState = .osc
                case 0x20...0x2F:
                    // nF escape sequence; keep waiting for final byte
                    break
                default:
                    escapeState = .normal
                }

            case .csi:
                // CSI ends at final byte 0x40...0x7E
                if scalar.value >= 0x40 && scalar.value <= 0x7E {
                    escapeState = .normal
                }

            case .osc:
                if scalar.value == 0x07 { // BEL terminates OSC
                    escapeState = .normal
                } else if scalar.value == 0x1B {
                    escapeState = .oscEsc
                }

            case .oscEsc:
                if scalar.value == 0x5C { // '\' (ST) terminates OSC
                    escapeState = .normal
                } else {
                    escapeState = .osc
                }
            }
        }
    }

    private func handleNormalScalarLocked(_ scalar: UnicodeScalar) {
        if scalar.value == 0x0A { // '\n'
            pendingCR = false
            commitCurrentLineLocked()
            return
        }

        if scalar.value == 0x0D { // '\r'
            pendingCR = true
            return
        }

        if pendingCR {
            // Standalone '\r' not followed by '\n': overwrite current line.
            currentLine = ""
            pendingCR = false
        }

        if scalar.value == 0x08 { // '\b' backspace
            if !currentLine.isEmpty {
                currentLine.removeLast()
            }
            return
        }

        // Ignore other non-printable ASCII control chars except tab.
        if scalar.value < 0x20 && scalar.value != 0x09 {
            return
        }

        if currentLine.count < maxLineLength {
            currentLine.unicodeScalars.append(scalar)
        }
    }

    private func commitCurrentLineLocked() {
        completedLines.append(currentLine)
        if completedLines.count > maxLines {
            completedLines.removeFirst(completedLines.count - maxLines)
        }
        currentLine = ""
    }

    private static func completeUTF8PrefixLength(in data: Data) -> Int {
        let count = data.count
        guard count > 0 else { return 0 }

        // Walk backwards up to 3 bytes to check if the tail is an incomplete multi-byte UTF-8 char.
        var i = count - 1
        let lowerBound = max(0, count - 4)
        while i >= lowerBound {
            let byte = data[i]
            if (byte & 0x80) == 0 {
                // Single-byte ASCII ends cleanly at count.
                return count
            }
            if (byte & 0xC0) == 0xC0 {
                // Lead byte found at index i.
                let expectedLen: Int
                if (byte & 0xE0) == 0xC0 { expectedLen = 2 }
                else if (byte & 0xF0) == 0xE0 { expectedLen = 3 }
                else if (byte & 0xF8) == 0xF0 { expectedLen = 4 }
                else { return count }

                let available = count - i
                return available < expectedLen ? i : count
            }
            i -= 1
        }
        return count
    }
}
