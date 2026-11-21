import SwiftUI

struct ScriptRowView: View {
    let configuration: ScriptConfiguration
    let runtimeState: ScriptRuntimeState
    let formattedDuration: String
    let isQuitting: Bool
    let showsReorderHandle: Bool
    let isDragSource: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onSelect: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onReorderChanged: (DragGesture.Value) -> Void
    let onReorderEnded: (DragGesture.Value) -> Void
    let onReorderInterrupted: () -> Void

    @State private var isHovered = false
    @State private var isErrorPopoverPresented = false
    @GestureState private var handleIsDragging = false

    private var statusColor: Color {
        Theme.color(for: runtimeState.status)
    }

    private var commandSummary: String {
        CommandSummaryFormatter.summary(for: configuration)
    }

    private var fullCommandTooltip: String {
        CommandSummaryFormatter.tooltip(for: configuration)
    }

    private var activeErrorBanner: (shortText: String, title: String, detail: String)? {
        if let stopError = runtimeState.stopErrorDetail {
            return (
                shortText: "Stop failed",
                title: "Could not stop script",
                detail: stopError
            )
        }
        if runtimeState.status == .failed, let summary = runtimeState.failureSummary {
            return (
                shortText: summary,
                title: summary,
                detail: runtimeState.failureDetail ?? summary
            )
        }
        return nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: RowColumnMetrics.columnSpacing) {
            if showsReorderHandle {
                reorderHandle
            }
            scriptInfoColumn
            statusColumn
            durationColumn
            actionColumn
            moreMenuColumn
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(minHeight: 84)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered && !isDragSource ? Theme.rowHoverBackground : Theme.rowBackground)
        )
        .opacity(isDragSource ? 0.35 : 1)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .contain)
    }

    private var reorderHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.secondaryText)
            .frame(width: 22, height: 36)
            .contentShape(Rectangle())
            .help("Drag to reorder")
            .accessibilityLabel("Reorder \(configuration.name)")
            .highPriorityGesture(reorderGesture)
            .onChange(of: handleIsDragging) { _, active in
                if !active {
                    onReorderInterrupted()
                }
            }
    }

    private var reorderGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(ScriptListCoordinateSpace.name))
            .updating($handleIsDragging) { _, state, _ in
                state = true
            }
            .onChanged(onReorderChanged)
            .onEnded(onReorderEnded)
    }

    // MARK: - Columns

    private var scriptInfoColumn: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)

                    Text(configuration.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Text(commandSummary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to view latest 50 lines of terminal output\n\(fullCommandTooltip)")
        .accessibilityHint("Opens live terminal output for \(configuration.name)")
    }

    private var statusColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(runtimeState.status.displayLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(statusColor)
                .lineLimit(1)

            if let errorInfo = activeErrorBanner {
                Button {
                    isErrorPopoverPresented.toggle()
                } label: {
                    Text(errorInfo.shortText)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .underline(isHovered, color: Theme.secondaryText.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show error details for \(configuration.name): \(errorInfo.shortText)")
                .help("Click to view full error description")
                .popover(isPresented: $isErrorPopoverPresented, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(errorInfo.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.primaryText)

                        Text(errorInfo.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryText)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(width: 320, alignment: .leading)
                    .background(Theme.sheetBackground)
                }
            }
        }
        .frame(width: RowColumnMetrics.statusWidth, alignment: .leading)
    }

    private var durationColumn: some View {
        Text(formattedDuration)
            .font(.system(size: 13).monospacedDigit())
            .foregroundStyle(Theme.secondaryText)
            .lineLimit(1)
            .frame(width: RowColumnMetrics.durationWidth, alignment: .trailing)
            .accessibilityLabel("Duration \(formattedDuration)")
    }

    @ViewBuilder
    private var actionColumn: some View {
        Group {
            switch runtimeState.status {
            case .stopped, .failed:
                Button(action: onStart) {
                    Text("Start")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: RowColumnMetrics.actionWidth, height: RowColumnMetrics.actionHeight)
                }
                .buttonStyle(
                    DeckActionButtonStyle(
                        background: Theme.startButtonBackground,
                        hoverBackground: Theme.startButtonHover,
                        foreground: Theme.startButtonText,
                        cornerRadius: 8
                    )
                )
                .disabled(isQuitting)
                .accessibilityLabel("Start \(configuration.name)")

            case .running:
                Button(action: onStop) {
                    Text("Stop")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: RowColumnMetrics.actionWidth, height: RowColumnMetrics.actionHeight)
                }
                .buttonStyle(
                    DeckActionButtonStyle(
                        background: Theme.stopButtonBackground,
                        hoverBackground: Theme.stopButtonHover,
                        foreground: Theme.stopButtonText,
                        cornerRadius: 8
                    )
                )
                .disabled(isQuitting)
                .accessibilityLabel("Stop \(configuration.name)")

            case .starting, .stopping:
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.stopButtonBackground.opacity(0.55))
                    ProgressView()
                        .controlSize(.small)
                }
                .frame(width: RowColumnMetrics.actionWidth, height: RowColumnMetrics.actionHeight)
                .accessibilityLabel("\(runtimeState.status.displayLabel) \(configuration.name)")
            }
        }
        .frame(width: RowColumnMetrics.actionWidth, height: RowColumnMetrics.actionHeight)
    }

    private var moreMenuColumn: some View {
        Menu {
            Button("View Output…", action: onSelect)

            Divider()

            Button("Move Up", action: onMoveUp)
                .disabled(!canMoveUp)

            Button("Move Down", action: onMoveDown)
                .disabled(!canMoveDown)

            Divider()

            Button("Edit…", action: onEdit)
                .disabled(!runtimeState.status.canEditOrRemove || isQuitting)

            Button("Remove…", role: .destructive, action: onRemove)
                .disabled(!runtimeState.status.canEditOrRemove || isQuitting)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: RowColumnMetrics.moreSize, height: RowColumnMetrics.moreSize)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: RowColumnMetrics.moreSize, height: RowColumnMetrics.moreSize)
        .disabled(isQuitting)
        .accessibilityLabel("More actions for \(configuration.name)")
    }
}
