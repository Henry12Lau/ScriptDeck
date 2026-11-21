import AppKit
import Foundation
import SwiftUI

struct ScriptDragPreview: Equatable {
    var topLeft: CGPoint
    var size: CGSize
}

enum EditorMode: Identifiable, Equatable {
    case add
    case edit(ScriptConfiguration)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let config):
            return "edit-\(config.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .add: return "Add script"
        case .edit: return "Edit script"
        }
    }

    var subtitle: String? {
        switch self {
        case .add: return "Configure a local script to run from ScriptDeck."
        case .edit: return nil
        }
    }

    var submitButtonTitle: String {
        switch self {
        case .add: return "Add script"
        case .edit: return "Save changes"
        }
    }
}

@MainActor
@Observable
final class DashboardViewModel {
    private(set) var scripts: [ScriptConfiguration] = []
    private(set) var now: Date = Date()
    private(set) var isLoaded = false

    var editorMode: EditorMode?
    var pendingRemoval: ScriptConfiguration?
    var selectedScriptForOutput: ScriptConfiguration?
    var storageErrorMessage: String?
    private(set) var draggingScriptID: UUID?
    private(set) var scriptDragPreview: ScriptDragPreview?
    private(set) var scriptDragBlocked = false

    let processManager: ProcessManager

    @ObservationIgnored
    private let store: ScriptStore

    @ObservationIgnored
    private var elapsedTimer: Timer?

    @ObservationIgnored
    private var reorderBaseline: [ScriptConfiguration]?

    @ObservationIgnored
    private var scriptDragSettled = true

    @ObservationIgnored
    private var escapeMonitor: Any?

    @ObservationIgnored
    private let isPreview: Bool

    init(
        store: ScriptStore = ScriptStore(),
        processManager: ProcessManager = ProcessManager(),
        isPreview: Bool = false
    ) {
        self.store = store
        self.processManager = processManager
        self.isPreview = isPreview

        processManager.onStatesChanged = { [weak self] in
            self?.syncElapsedTimer()
        }
    }

    var isQuitting: Bool {
        processManager.isQuitting
    }

    var subtitleText: String {
        guard !scripts.isEmpty else { return "" }
        let orderedStates = scripts.map { processManager.state(for: $0.id) }
        return StatusSummaryFormatter.subtitle(for: orderedStates)
    }

    func runtimeState(for script: ScriptConfiguration) -> ScriptRuntimeState {
        processManager.state(for: script.id)
    }

    func formattedDuration(for script: ScriptConfiguration) -> String {
        let state = runtimeState(for: script)
        return DurationFormatter.format(state.elapsedTime(at: now))
    }

    func loadScriptsIfNeeded() async {
        guard !isPreview, !isLoaded else { return }
        do {
            let loaded = try await store.load()
            scripts = loaded
            isLoaded = true
        } catch {
            isLoaded = true
            storageErrorMessage = error.localizedDescription
        }
    }

    func presentAddSheet() {
        guard !isQuitting else { return }
        editorMode = .add
    }

    func presentEditSheet(for script: ScriptConfiguration) {
        guard !isQuitting else { return }
        guard runtimeState(for: script).status.canEditOrRemove else { return }
        editorMode = .edit(script)
    }

    func presentOutput(for script: ScriptConfiguration) {
        selectedScriptForOutput = script
    }

    func outputSnapshot(for id: UUID) -> (lines: [String], revision: UInt64) {
        processManager.outputSnapshot(for: id)
    }

    func clearOutput(for id: UUID) {
        processManager.clearOutput(for: id)
    }

    func requestRemoval(of script: ScriptConfiguration) {
        guard !isQuitting else { return }
        guard runtimeState(for: script).status.canEditOrRemove else { return }
        pendingRemoval = script
    }

    func confirmRemoval() {
        guard let script = pendingRemoval else { return }
        pendingRemoval = nil
        guard runtimeState(for: script).status.canEditOrRemove else { return }

        let previous = scripts
        scripts.removeAll { $0.id == script.id }
        if selectedScriptForOutput?.id == script.id {
            selectedScriptForOutput = nil
        }
        processManager.removeState(for: script.id)

        persist(scripts, rollbackTo: previous)
    }

    func moveScriptUp(id: UUID) {
        applyOrder(ScriptReorder.movingUp(scripts, id: id))
    }

    func moveScriptDown(id: UUID) {
        applyOrder(ScriptReorder.movingDown(scripts, id: id))
    }

    func beginScriptDrag(id: UUID) {
        guard !isQuitting, !scriptDragBlocked else { return }
        scriptDragSettled = false
        reorderBaseline = scripts
        draggingScriptID = id
        installEscapeMonitor()
    }

    func updateScriptDragPreview(topLeft: CGPoint, size: CGSize) {
        guard draggingScriptID != nil else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scriptDragPreview = ScriptDragPreview(topLeft: topLeft, size: size)
        }
    }

    func previewScriptMove(id: UUID, to index: Int) {
        guard !isQuitting, draggingScriptID == id, !scriptDragBlocked else { return }
        let updated = ScriptReorder.moving(scripts, id: id, to: index)
        guard updated != scripts else { return }
        if reorderBaseline == nil {
            reorderBaseline = scripts
        }
        withAnimation(Self.reorderAnimation) {
            scripts = updated
        }
    }

    func endScriptDrag(committed: Bool) {
        guard !scriptDragSettled else { return }
        scriptDragSettled = true
        let baseline = reorderBaseline
        reorderBaseline = nil
        draggingScriptID = nil
        scriptDragPreview = nil
        removeEscapeMonitor()
        guard let baseline else { return }
        if committed, scripts != baseline {
            persist(scripts, rollbackTo: baseline)
        } else if scripts != baseline {
            withAnimation(Self.reorderAnimation) {
                scripts = baseline
            }
        }
    }

    func cancelScriptDragFromEscape() {
        guard draggingScriptID != nil || !scriptDragSettled else { return }
        scriptDragBlocked = true
        endScriptDrag(committed: false)
    }

    func clearScriptDragBlock() {
        scriptDragBlocked = false
    }

    func addScript(_ configuration: ScriptConfiguration) {
        let previous = scripts
        scripts.append(configuration)
        persist(scripts, rollbackTo: previous)
    }

    func updateScript(_ configuration: ScriptConfiguration) {
        guard runtimeState(for: configuration).status.canEditOrRemove else { return }
        guard let index = scripts.firstIndex(where: { $0.id == configuration.id }) else { return }

        let previous = scripts
        scripts[index] = configuration
        if selectedScriptForOutput?.id == configuration.id {
            selectedScriptForOutput = configuration
        }
        processManager.resetStateIfInactive(for: configuration.id)
        persist(scripts, rollbackTo: previous)
    }

    func start(_ script: ScriptConfiguration) {
        processManager.start(script)
        now = Date()
        syncElapsedTimer()
    }

    func stop(_ script: ScriptConfiguration) {
        processManager.stop(id: script.id)
        syncElapsedTimer()
    }

    func stopAllForQuit() async {
        await processManager.stopAllForQuit()
        syncElapsedTimer()
    }

    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated {
                self?.cancelScriptDragFromEscape()
            }
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    private static let reorderAnimation = Animation.smooth(duration: 0.22, extraBounce: 0)

    private func applyOrder(_ updated: [ScriptConfiguration]) {
        guard !isQuitting, updated != scripts else { return }
        let previous = scripts
        withAnimation(Self.reorderAnimation) {
            scripts = updated
        }
        persist(scripts, rollbackTo: previous)
    }

    private func persist(_ updated: [ScriptConfiguration], rollbackTo previous: [ScriptConfiguration]) {
        guard !isPreview else { return }
        Task {
            do {
                try await store.save(updated)
            } catch {
                await MainActor.run {
                    if self.scripts == updated {
                        self.scripts = previous
                    }
                    self.storageErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func syncElapsedTimer() {
        let needsTimer = processManager.hasRunningScriptsForTimer
        if needsTimer {
            if elapsedTimer == nil {
                now = Date()
                let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.now = Date()
                    }
                }
                timer.tolerance = 0.2
                elapsedTimer = timer
            }
        } else {
            elapsedTimer?.invalidate()
            elapsedTimer = nil
        }
    }

    static func preview(
        scripts: [ScriptConfiguration],
        states: [UUID: ScriptRuntimeState]
    ) -> DashboardViewModel {
        let manager = ProcessManager()
        manager.seedPreviewStates(states)
        let vm = DashboardViewModel(processManager: manager, isPreview: true)
        vm.scripts = scripts
        vm.isLoaded = true
        return vm
    }
}
