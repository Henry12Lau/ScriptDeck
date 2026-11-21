import SwiftUI

/// Mock fixtures strictly for SwiftUI Previews.
/// Never imported into production user state and never launches real processes.
enum PreviewFixtures {
    static let dataSyncID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let oddsWatcherID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let reportBuilderID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    static let modelPipelineID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    static let mixedScripts: [ScriptConfiguration] = [
        ScriptConfiguration(
            id: dataSyncID,
            name: "Data sync",
            directory: "/Users/me/project",
            command: ".venv/bin/python3 sync.py"
        ),
        ScriptConfiguration(
            id: oddsWatcherID,
            name: "Web Frontend",
            directory: "/Users/me/web-app",
            command: "npm run dev"
        ),
        ScriptConfiguration(
            id: reportBuilderID,
            name: "Report builder",
            directory: "/Users/me/project",
            command: "python3 report.py"
        ),
        ScriptConfiguration(
            id: modelPipelineID,
            name: "Model pipeline",
            directory: "/Users/me/project",
            command: "./run-model.sh"
        )
    ]

    static var mixedStates: [UUID: ScriptRuntimeState] {
        let now = Date()
        return [
            dataSyncID: ScriptRuntimeState(
                status: .running,
                startedAt: now.addingTimeInterval(-(24 * 60 + 18))
            ),
            oddsWatcherID: ScriptRuntimeState(
                status: .running,
                startedAt: now.addingTimeInterval(-(3600 + 12 * 60 + 6))
            ),
            reportBuilderID: ScriptRuntimeState(
                status: .stopped,
                lastDuration: nil
            ),
            modelPipelineID: ScriptRuntimeState(
                status: .failed,
                lastDuration: 2 * 60 + 41,
                failureSummary: "Exit code 1",
                failureDetail: "The command exited with non-zero status code 1."
            )
        ]
    }

    static var transitionalStates: [UUID: ScriptRuntimeState] {
        let now = Date()
        return [
            dataSyncID: ScriptRuntimeState(status: .starting),
            oddsWatcherID: ScriptRuntimeState(
                status: .stopping,
                startedAt: now.addingTimeInterval(-95)
            ),
            reportBuilderID: ScriptRuntimeState(status: .stopped),
            modelPipelineID: ScriptRuntimeState(
                status: .failed,
                failureSummary: "Directory not found",
                failureDetail: "The folder does not exist:\n/Users/me/missing-project"
            )
        ]
    }

    static let longScripts: [ScriptConfiguration] = [
        ScriptConfiguration(
            id: dataSyncID,
            name: "Extremely Long Enterprise Synchronization Pipeline Worker That Should Truncate Cleanly",
            directory: "/Users/developer/Documents/Very Long Workspace Folder Name",
            command: "/Users/developer/Library/Application Support/python-3.12-venv/bin/python3 submodules/etl_pipeline/scripts/nightly_incremental_sync.py --config configs/production_cluster.json"
        ),
        ScriptConfiguration(
            id: oddsWatcherID,
            name: "Another Very Long Node Service Name For Narrow Window Testing",
            directory: "/Users/developer/projects/realtime-stream-processor",
            command: "npm run dev -- --port 4040 --host 0.0.0.0"
        )
    ]

    static var longStates: [UUID: ScriptRuntimeState] {
        [
            dataSyncID: ScriptRuntimeState(status: .running, startedAt: Date().addingTimeInterval(-325)),
            oddsWatcherID: ScriptRuntimeState(
                status: .failed,
                lastDuration: 14,
                failureSummary: "Exit code 127",
                failureDetail: "Command not found (exit code 127):\nnpm run dev -- --port 4040"
            )
        ]
    }
}

#Preview("1. Empty") {
    DashboardView(
        viewModel: .preview(scripts: [], states: [:])
    )
    .frame(width: 960, height: 620)
}

#Preview("2. Mixed States") {
    DashboardView(
        viewModel: .preview(
            scripts: PreviewFixtures.mixedScripts,
            states: PreviewFixtures.mixedStates
        )
    )
    .frame(width: 960, height: 620)
}

#Preview("3. Starting & Stopping") {
    DashboardView(
        viewModel: .preview(
            scripts: PreviewFixtures.mixedScripts,
            states: PreviewFixtures.transitionalStates
        )
    )
    .frame(width: 960, height: 620)
}

#Preview("4. Long Names & Paths") {
    DashboardView(
        viewModel: .preview(
            scripts: PreviewFixtures.longScripts,
            states: PreviewFixtures.longStates
        )
    )
    .frame(width: 960, height: 620)
}

#Preview("5. Add Script Form") {
    ScriptEditorView(
        mode: .add,
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("6. Validation Failure") {
    ScriptEditorView(
        mode: .add,
        initialValidationErrors: ScriptValidationErrors(
            nameError: "Name is required.",
            directoryError: "Directory does not exist.",
            commandError: "Command is required."
        ),
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("8. Menu Bar") {
    MenuBarPanelView(
        viewModel: .preview(
            scripts: PreviewFixtures.mixedScripts,
            states: PreviewFixtures.mixedStates
        ),
        onOpenDashboard: {},
        onQuit: {}
    )
}

#Preview("9. Menu Bar Empty") {
    MenuBarPanelView(
        viewModel: .preview(scripts: [], states: [:]),
        onOpenDashboard: {},
        onQuit: {}
    )
}

#Preview("7. Minimum Window Size") {
    DashboardView(
        viewModel: .preview(
            scripts: PreviewFixtures.longScripts,
            states: PreviewFixtures.longStates
        )
    )
    .frame(width: 780, height: 460)
}
