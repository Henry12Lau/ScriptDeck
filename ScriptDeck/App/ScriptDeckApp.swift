import SwiftUI

@main
struct ScriptDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("ScriptDeck", id: "main") {
            DashboardView(viewModel: appDelegate.viewModel)
                .onAppear {
                    appDelegate.reopenMainWindow = {
                        openWindow(id: "main")
                    }
                }
        }
        .defaultSize(width: 960, height: 620)
        .windowResizability(.contentMinSize)
    }
}
