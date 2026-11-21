import AppKit
import SwiftUI

/// Menu-bar item that pops a panel of the current scripts.
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let hostingController: NSHostingController<MenuBarPanelView>
    private let viewModel: DashboardViewModel
    private let layout = MenuBarPanelLayout()
    private var reportedPanelHeight: CGFloat?

    /// Set when the popover closes because the status item itself was clicked.
    /// The button action arrives just after that close and would otherwise reopen it.
    private var suppressNextOpen = false
    private var suppressGeneration = 0

    init(
        viewModel: DashboardViewModel,
        openMainWindow: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        hostingController = NSHostingController(
            rootView: MenuBarPanelView(viewModel: viewModel, layout: layout, onOpenDashboard: {}, onQuit: {})
        )
        super.init()

        hostingController.rootView = MenuBarPanelView(
            viewModel: viewModel,
            layout: layout,
            onOpenDashboard: { [weak self] in
                self?.closePopover()
                openMainWindow()
            },
            onQuit: { [weak self] in
                self?.closePopover()
                quit()
            },
            onIdealHeight: { [weak self] height in
                self?.applyPanelHeight(height)
            }
        )
        configureStatusItem()
        configurePopover()
        observeModel()
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover()
            return
        }
        if suppressNextOpen {
            suppressNextOpen = false
            suppressGeneration += 1
            return
        }
        showPopover()
    }

    nonisolated func popoverWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            self.statusItem.button?.isHighlighted = false
            guard let event = NSApp.currentEvent,
                  event.window == self.statusItem.button?.window else {
                return
            }
            self.suppressNextOpen = true
            self.suppressGeneration += 1
            let generation = self.suppressGeneration
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                if self.suppressGeneration == generation {
                    self.suppressNextOpen = false
                }
            }
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        applySymbol(named: "terminal", to: button)
        refreshStatusItem()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.appearance = NSAppearance(named: .darkAqua)
        hostingController.sizingOptions = [.preferredContentSize]
        hostingController.safeAreaRegions = []
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = Theme.windowNSColor.cgColor
        popover.contentViewController = hostingController
        popover.contentSize = NSSize(width: 340, height: 180)
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        updateScreenLimit()
        applyPanelHeight(reportedPanelHeight ?? estimatedPanelHeight)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.isHighlighted = true
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        statusItem.button?.isHighlighted = false
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    private func observeModel() {
        withObservationTracking {
            _ = statusItemSignature
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshStatusItem()
                self?.observeModel()
            }
        }
    }

    private var statusItemSignature: String {
        let rows = viewModel.scripts.map { script in
            let status = viewModel.runtimeState(for: script).status.rawValue
            return "\(script.id.uuidString)|\(script.name)|\(status)"
        }
        return "\(viewModel.isLoaded)|\(rows.joined(separator: ";"))"
    }

    private var activeCount: Int {
        viewModel.scripts.reduce(into: 0) { count, script in
            if viewModel.runtimeState(for: script).status.isActive {
                count += 1
            }
        }
    }

    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        let count = activeCount
        applySymbol(named: count > 0 ? "terminal.fill" : "terminal", to: button)
        button.title = count > 0 ? " \(count)" : ""

        let summary = viewModel.subtitleText
        let label: String
        if !viewModel.isLoaded {
            label = "ScriptDeck"
        } else if viewModel.scripts.isEmpty {
            label = "ScriptDeck, no scripts"
        } else if summary.isEmpty {
            label = "ScriptDeck"
        } else {
            label = "ScriptDeck, \(summary)"
        }
        button.setAccessibilityLabel(label)
        button.toolTip = label.replacingOccurrences(of: ", ", with: " — ")

        if popover.isShown {
            updateScreenLimit()
        }
    }

    private func applySymbol(named symbolName: String, to button: NSStatusBarButton) {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "ScriptDeck") else {
            return
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let symbol = image.withSymbolConfiguration(configuration) ?? image
        symbol.isTemplate = true
        button.image = symbol
    }

    private func updateScreenLimit() {
        let height = screenVisibleHeight
        guard abs(layout.maxPanelHeight - height) > 0.5 else { return }
        layout.maxPanelHeight = height
    }

    private var screenVisibleHeight: CGFloat {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        return max(screen?.visibleFrame.height ?? 800, 180)
    }

    private func applyPanelHeight(_ height: CGFloat) {
        reportedPanelHeight = height
        let clamped = min(max(height, 1), layout.maxPanelHeight)
        let size = NSSize(width: 340, height: clamped)
        guard abs(popover.contentSize.height - size.height) > 0.5 || abs(popover.contentSize.width - size.width) > 0.5 else {
            return
        }
        popover.contentSize = size
    }

    private var estimatedPanelHeight: CGFloat {
        let middle: CGFloat
        if viewModel.scripts.isEmpty {
            middle = viewModel.isLoaded ? 36 : 48
        } else {
            let count = CGFloat(viewModel.scripts.count)
            middle = 20 + count * 62 + max(0, count - 1) * 6
        }
        return min(layout.maxPanelHeight, 58 + middle + 50)
    }
}
