import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = DashboardViewModel()
    var reopenMainWindow: (() -> Void)?

    private var isQuitPromptPresented = false
    private var isQuittingInProgress = false
    private var windowObserver: NSObjectProtocol?
    private var statusBarController: StatusBarController?
    private var closeMonitors: [ObjectIdentifier: MainWindowCloseMonitor] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)

        for window in NSApp.windows {
            configureMainWindow(window)
        }

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            Task { @MainActor [weak self] in
                self?.configureMainWindow(window)
            }
        }

        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            statusBarController = StatusBarController(
                viewModel: viewModel,
                openMainWindow: { [weak self] in
                    self?.showMainWindow()
                },
                quit: { [weak self] in
                    self?.quitFromMenuBar()
                }
            )
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isQuittingInProgress {
            return .terminateLater
        }

        guard viewModel.processManager.hasActiveScripts else {
            return .terminateNow
        }

        if isQuitPromptPresented {
            return .terminateLater
        }

        isQuitPromptPresented = true
        NSApp.activate(ignoringOtherApps: true)
        showMainWindow()

        Task { @MainActor [weak self] in
            guard let self else {
                NSApp.reply(toApplicationShouldTerminate: false)
                return
            }

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Stop scripts and quit?"
            alert.informativeText = "Quitting will stop all scripts started by ScriptDeck."

            let stopAndQuitButton = alert.addButton(withTitle: "Stop & Quit")
            stopAndQuitButton.hasDestructiveAction = true

            let cancelButton = alert.addButton(withTitle: "Cancel")
            cancelButton.keyEquivalent = "\u{1b}"

            let response: NSApplication.ModalResponse
            if let window = self.mainWindow(), window.isVisible {
                response = await alert.beginSheetModal(for: window)
            } else {
                response = alert.runModal()
            }

            self.isQuitPromptPresented = false

            if response == .alertFirstButtonReturn {
                self.isQuittingInProgress = true
                await self.viewModel.stopAllForQuit()
                NSApp.reply(toApplicationShouldTerminate: true)
            } else {
                NSApp.reply(toApplicationShouldTerminate: false)
            }
        }

        return .terminateLater
    }

    private func mainWindow() -> NSWindow? {
        NSApp.windows.first { window in
            !(window is NSPanel) && (window.identifier?.rawValue == "main" || window.title == "ScriptDeck")
        }
    }

    func showMainWindow() {
        let didLeaveBackground = leaveBackground()
        NSApp.activate(ignoringOtherApps: true)
        presentMainWindow()
        // Switching back from accessory can swallow the first activate.
        if didLeaveBackground {
            DispatchQueue.main.async { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.presentMainWindow()
            }
        }
    }

    func quitFromMenuBar() {
        NSApp.terminate(nil)
    }

    private func presentMainWindow() {
        if let window = mainWindow() {
            configureMainWindow(window)
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        } else {
            reopenMainWindow?()
        }
    }

    /// Hides the window and leaves the Dock so ScriptDeck keeps running from the menu bar.
    private func enterBackground(hiding window: NSWindow) {
        window.orderOut(nil)
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @discardableResult
    private func leaveBackground() -> Bool {
        guard NSApp.activationPolicy() != .regular else { return false }
        NSApp.setActivationPolicy(.regular)
        return true
    }

    private func configureMainWindow(_ window: NSWindow) {
        guard !(window is NSPanel) else { return }
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.windowNSColor
        window.titlebarAppearsTransparent = false
        window.minSize = NSSize(width: 780, height: 460)
        window.isReleasedWhenClosed = false
        installCloseMonitor(on: window)
    }

    private func installCloseMonitor(on window: NSWindow) {
        if window.delegate is MainWindowCloseMonitor {
            return
        }
        let monitor = MainWindowCloseMonitor(forwarded: window.delegate) { [weak self] window in
            self?.enterBackground(hiding: window)
        }
        closeMonitors[ObjectIdentifier(window)] = monitor
        window.delegate = monitor
    }
}

/// Keeps SwiftUI's window delegate, but turns the close button into "hide and keep running".
@MainActor
private final class MainWindowCloseMonitor: NSObject, NSWindowDelegate {
    weak var forwarded: (any NSWindowDelegate)?
    var onHide: (NSWindow) -> Void

    init(forwarded: (any NSWindowDelegate)?, onHide: @escaping (NSWindow) -> Void) {
        self.forwarded = forwarded
        self.onHide = onHide
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let forwarded, forwarded.responds(to: #selector(NSWindowDelegate.windowShouldClose(_:))) {
            if forwarded.windowShouldClose?(sender) == false {
                return false
            }
        }
        onHide(sender)
        return false
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) {
            return true
        }
        return forwarded?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if super.responds(to: aSelector) {
            return nil
        }
        return forwarded
    }
}
