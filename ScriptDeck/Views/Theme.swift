import SwiftUI

enum Theme {
    static let windowBackground = Color(hex: 0x1B1E26)
    static let rowBackground = Color(hex: 0x252933)
    static let rowHoverBackground = Color(hex: 0x2B303C)
    static let sheetBackground = Color(hex: 0x1F232D)
    static let inputBackground = Color(hex: 0x171A21)
    static let subtleBorder = Color(hex: 0x353B4B)

    static let primaryText = Color(hex: 0xE9EDF5)
    static let secondaryText = Color(hex: 0x969EAF)

    static let running = Color(hex: 0x48D6A0)
    static let stopped = Color(hex: 0x969EAF)
    static let failed = Color(hex: 0xFF8585)
    static let transitional = Color(hex: 0xE8B96A)

    static let startButtonBackground = Color(hex: 0x326DE6)
    static let startButtonHover = Color(hex: 0x3D77EE)
    static let startButtonText = Color.white

    static let stopButtonBackground = Color(hex: 0x374153)
    static let stopButtonHover = Color(hex: 0x434E63)
    static let stopButtonText = Color(hex: 0xE9EDF5)

    static let addButtonBackground = Color(hex: 0x2A2F3B)
    static let addButtonHover = Color(hex: 0x343A49)

    static let quitButtonBackground = Color(hex: 0xD24B4B)
    static let quitButtonHover = Color(hex: 0xDE5A5A)
    static let quitButtonText = Color.white

    static let windowNSColor = NSColor(
        srgbRed: 0x1B / 255.0,
        green: 0x1E / 255.0,
        blue: 0x26 / 255.0,
        alpha: 1.0
    )

    static func color(for status: ScriptStatus) -> Color {
        switch status {
        case .running: return running
        case .stopped: return stopped
        case .failed: return failed
        case .starting, .stopping: return transitional
        }
    }
}

enum RowColumnMetrics {
    static let statusWidth: CGFloat = 112
    static let durationWidth: CGFloat = 82
    static let actionWidth: CGFloat = 72
    static let actionHeight: CGFloat = 32
    static let moreSize: CGFloat = 32
    static let columnSpacing: CGFloat = 16
}

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

struct DeckActionButtonStyle: ButtonStyle {
    let background: Color
    let hoverBackground: Color
    let foreground: Color
    let cornerRadius: CGFloat
    var borderColor: Color? = nil
    var horizontalPadding: CGFloat = 0
    var minHeight: CGFloat? = nil

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: minHeight)
            .foregroundStyle(foreground.opacity(isEnabled ? 1.0 : 0.45))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(resolvedBackground(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor ?? .clear, lineWidth: borderColor == nil ? 0 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1.0) : 0.6)
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private func resolvedBackground(isPressed: Bool) -> Color {
        if !isEnabled {
            return background.opacity(0.6)
        }
        if isPressed || isHovered {
            return hoverBackground
        }
        return background
    }
}
