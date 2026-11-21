import AppKit
import SwiftUI

struct ScriptOutputSheetView: View {
    let script: ScriptConfiguration
    let viewModel: DashboardViewModel
    let onClose: () -> Void

    @State private var lines: [String] = []
    @State private var revision: UInt64 = 0
    @State private var didCopy = false

    private let bottomAnchorID = "script-output-bottom"

    private var runtimeState: ScriptRuntimeState {
        viewModel.runtimeState(for: script)
    }

    private var formattedDuration: String {
        viewModel.formattedDuration(for: script)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            terminalView
            footerView
        }
        .padding(22)
        .frame(minWidth: 660, idealWidth: 720, minHeight: 440, idealHeight: 480)
        .background(Theme.sheetBackground)
        .task(id: script.id) {
            refreshSnapshot(force: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                if Task.isCancelled { break }
                refreshSnapshot(force: false)
            }
        }
    }

    private var headerView: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text(script.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)

                    statusBadge
                }

                Text(script.command)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(script.command)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 5) {
                Text(formattedDuration)
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)

                Text("\(lines.count) / 50 lines")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.color(for: runtimeState.status))
                .frame(width: 7, height: 7)

            Text(runtimeState.status.displayLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.color(for: runtimeState.status))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.rowBackground)
        )
    }

    private var terminalView: some View {
        Group {
            if lines.isEmpty {
                VStack(spacing: 8) {
                    Text(runtimeState.status.isActive ? "Waiting for output…" : "No output recorded.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)

                    Text("ScriptDeck keeps only the latest 50 lines in memory.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText.opacity(0.75))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                Text(line.isEmpty ? " " : line)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Theme.primaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(bottomAnchorID)
                        }
                        .padding(14)
                        .textSelection(.enabled)
                    }
                    .onAppear {
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                    .onChange(of: revision) { _, _ in
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.inputBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private var footerView: some View {
        HStack(spacing: 10) {
            Button(didCopy ? "Copied" : "Copy") {
                copyOutput()
            }
            .buttonStyle(
                DeckActionButtonStyle(
                    background: Theme.addButtonBackground,
                    hoverBackground: Theme.addButtonHover,
                    foreground: Theme.primaryText,
                    cornerRadius: 8,
                    borderColor: Theme.subtleBorder,
                    horizontalPadding: 14,
                    minHeight: 32
                )
            )
            .font(.system(size: 12.5, weight: .medium))
            .disabled(lines.isEmpty)

            Button("Clear") {
                viewModel.clearOutput(for: script.id)
                refreshSnapshot(force: true)
            }
            .buttonStyle(
                DeckActionButtonStyle(
                    background: Theme.addButtonBackground,
                    hoverBackground: Theme.addButtonHover,
                    foreground: Theme.primaryText,
                    cornerRadius: 8,
                    borderColor: Theme.subtleBorder,
                    horizontalPadding: 14,
                    minHeight: 32
                )
            )
            .font(.system(size: 12.5, weight: .medium))
            .disabled(lines.isEmpty)

            Spacer()

            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)
                .buttonStyle(
                    DeckActionButtonStyle(
                        background: Theme.stopButtonBackground,
                        hoverBackground: Theme.stopButtonHover,
                        foreground: Theme.stopButtonText,
                        cornerRadius: 8,
                        horizontalPadding: 16,
                        minHeight: 32
                    )
                )
                .font(.system(size: 12.5, weight: .semibold))
        }
    }

    private func refreshSnapshot(force: Bool) {
        let snapshot = viewModel.outputSnapshot(for: script.id)
        if force || snapshot.revision != revision {
            lines = snapshot.lines
            revision = snapshot.revision
        }
    }

    private func copyOutput() {
        let content = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopy = false
        }
    }
}
