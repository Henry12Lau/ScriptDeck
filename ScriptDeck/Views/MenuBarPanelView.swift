import AppKit
import SwiftUI

@MainActor
@Observable
final class MenuBarPanelLayout {
    var maxPanelHeight: CGFloat

    init(maxPanelHeight: CGFloat = NSScreen.main?.visibleFrame.height ?? 800) {
        self.maxPanelHeight = maxPanelHeight
    }
}

struct MenuBarPanelView: View {
    var viewModel: DashboardViewModel
    var layout: MenuBarPanelLayout = MenuBarPanelLayout()
    var onOpenDashboard: () -> Void
    var onQuit: () -> Void
    var onIdealHeight: (CGFloat) -> Void = { _ in }

    @State private var headerHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    @State private var middleMeasured: CGFloat = 0
    @State private var listContentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                header
                hairline
            }
            .reportHeight(MenuBarHeaderHeightKey.self)

            middle

            footer
                .reportHeight(MenuBarFooterHeightKey.self)
        }
        .frame(width: 340, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.windowBackground)
        .preferredColorScheme(.dark)
        .task {
            await viewModel.loadScriptsIfNeeded()
        }
        .onAppear {
            onIdealHeight(panelHeight)
        }
        .onChange(of: panelHeight) { _, newValue in
            onIdealHeight(newValue)
        }
        .onPreferenceChange(MenuBarHeaderHeightKey.self) { headerHeight = $0 }
        .onPreferenceChange(MenuBarFooterHeightKey.self) { footerHeight = $0 }
        .onPreferenceChange(MenuBarMiddleHeightKey.self) { middleMeasured = $0 }
        .onPreferenceChange(MenuBarListContentHeightKey.self) { listContentHeight = $0 }
    }

    @ViewBuilder
    private var middle: some View {
        if !viewModel.isLoaded && viewModel.scripts.isEmpty {
            loadingState
                .reportHeight(MenuBarMiddleHeightKey.self)
        } else if viewModel.scripts.isEmpty {
            emptyState
                .reportHeight(MenuBarMiddleHeightKey.self)
        } else {
            scriptList
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("ScriptDeck")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.primaryText)

            Text(headerSubtitle)
                .font(.system(size: 11))
                .foregroundStyle(headerSubtitleColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerSubtitle: String {
        if !viewModel.scripts.isEmpty {
            return viewModel.subtitleText
        }
        if let message = viewModel.storageErrorMessage, !message.isEmpty {
            return message
        }
        if !viewModel.isLoaded {
            return "Loading scripts…"
        }
        return "No scripts yet"
    }

    private var headerSubtitleColor: Color {
        if viewModel.scripts.isEmpty,
           let message = viewModel.storageErrorMessage,
           !message.isEmpty {
            return Theme.failed
        }
        return Theme.secondaryText
    }

    private var loadingState: some View {
        HStack {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Spacer()
        }
        .padding(.vertical, 18)
    }

    private var emptyState: some View {
        Text("Open ScriptDeck to add a script.")
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 12)
    }

    private var scriptList: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(viewModel.scripts) { script in
                    MenuBarScriptRow(
                        configuration: script,
                        runtimeState: viewModel.runtimeState(for: script),
                        formattedDuration: viewModel.formattedDuration(for: script),
                        isQuitting: viewModel.isQuitting,
                        onStart: { viewModel.start(script) },
                        onStop: { viewModel.stop(script) }
                    )
                }
            }
            .padding(10)
            .fixedSize(horizontal: false, vertical: true)
            .reportHeight(MenuBarListContentHeightKey.self)
        }
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDisabled(listContentFits)
        .frame(height: listViewportHeight, alignment: .top)
    }

    private var resolvedHeaderHeight: CGFloat {
        headerHeight > 1 ? headerHeight : 58
    }

    private var resolvedFooterHeight: CGFloat {
        footerHeight > 1 ? footerHeight : 50
    }

    private var listContentFits: Bool {
        listContentHeight <= listViewportHeight + 1
    }

    /// Shows every row until the panel reaches the screen's visible height.
    private var listViewportHeight: CGFloat {
        let content = listContentHeight > 1 ? listContentHeight : estimatedListContentHeight
        let available = max(0, layout.maxPanelHeight - resolvedHeaderHeight - resolvedFooterHeight)
        return min(content, available)
    }

    private var estimatedListContentHeight: CGFloat {
        let count = CGFloat(viewModel.scripts.count)
        guard count > 0 else { return 0 }
        return 20 + count * 62 + (count - 1) * 6
    }

    private var panelHeight: CGFloat {
        resolvedHeaderHeight + middleHeight + resolvedFooterHeight
    }

    private var middleHeight: CGFloat {
        if viewModel.scripts.isEmpty {
            if middleMeasured > 1 {
                return middleMeasured
            }
            return viewModel.isLoaded ? 36 : 48
        }
        return listViewportHeight
    }

    private var footer: some View {
        VStack(spacing: 0) {
            hairline

            HStack(spacing: 8) {
                Button(action: onOpenDashboard) {
                    Text("Open")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(
                    DeckActionButtonStyle(
                        background: Theme.addButtonBackground,
                        hoverBackground: Theme.addButtonHover,
                        foreground: Theme.primaryText,
                        cornerRadius: 8,
                        borderColor: Theme.subtleBorder,
                        horizontalPadding: 12,
                        minHeight: 28
                    )
                )
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Open ScriptDeck")
                .accessibilityHint("Opens the ScriptDeck window")

                Button(action: onQuit) {
                    Text("Quit")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(
                    DeckActionButtonStyle(
                        background: Theme.quitButtonBackground,
                        hoverBackground: Theme.quitButtonHover,
                        foreground: Theme.quitButtonText,
                        cornerRadius: 8,
                        horizontalPadding: 12,
                        minHeight: 28
                    )
                )
                .frame(maxWidth: .infinity)
                .disabled(viewModel.isQuitting)
                .accessibilityLabel("Quit ScriptDeck")
                .accessibilityHint("Quits ScriptDeck. Running scripts are stopped after confirmation.")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.subtleBorder)
            .frame(height: 1)
    }
}

private extension View {
    func reportHeight<Key: PreferenceKey>(_ key: Key.Type) -> some View where Key.Value == CGFloat {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: key, value: proxy.size.height)
            }
        }
    }
}

private struct MenuBarHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MenuBarFooterHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MenuBarMiddleHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MenuBarListContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MenuBarScriptRow: View {
    let configuration: ScriptConfiguration
    let runtimeState: ScriptRuntimeState
    let formattedDuration: String
    let isQuitting: Bool
    let onStart: () -> Void
    let onStop: () -> Void

    @State private var isHovered = false

    private var statusColor: Color {
        Theme.color(for: runtimeState.status)
    }

    private var statusLine: String {
        let label = runtimeState.status.displayLabel
        guard formattedDuration != "—" else { return label }
        return "\(label) · \(formattedDuration)"
    }

    private var detail: (text: String, color: Color) {
        if runtimeState.stopErrorDetail != nil {
            return ("Stop failed", Theme.failed)
        }
        if runtimeState.status == .failed,
           let summary = runtimeState.failureSummary,
           !summary.isEmpty {
            return (summary, Theme.failed)
        }
        return (CommandSummaryFormatter.summary(for: configuration), Theme.secondaryText)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(configuration.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(statusLine)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(statusColor)
                    .lineLimit(1)

                Text(detail.text)
                    .font(.system(size: 11))
                    .foregroundStyle(detail.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actionControl
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Theme.rowHoverBackground : Theme.rowBackground)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .help(CommandSummaryFormatter.tooltip(for: configuration))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actionControl: some View {
        switch runtimeState.status {
        case .stopped, .failed:
            actionButton(title: "Start", isStart: true, action: onStart)
                .disabled(isQuitting)
                .accessibilityLabel("Start \(configuration.name)")

        case .running:
            actionButton(title: "Stop", isStart: false, action: onStop)
                .disabled(isQuitting)
                .accessibilityLabel("Stop \(configuration.name)")

        case .starting, .stopping:
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.stopButtonBackground.opacity(0.55))
                ProgressView()
                    .controlSize(.small)
            }
            .frame(width: 58, height: 26)
            .accessibilityLabel("\(runtimeState.status.displayLabel) \(configuration.name)")
        }
    }

    private func actionButton(title: String, isStart: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 58, height: 26)
        }
        .buttonStyle(
            DeckActionButtonStyle(
                background: isStart ? Theme.startButtonBackground : Theme.stopButtonBackground,
                hoverBackground: isStart ? Theme.startButtonHover : Theme.stopButtonHover,
                foreground: isStart ? Theme.startButtonText : Theme.stopButtonText,
                cornerRadius: 7
            )
        )
    }
}
