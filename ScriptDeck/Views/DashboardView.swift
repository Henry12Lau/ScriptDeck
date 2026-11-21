import AppKit
import SwiftUI

enum ScriptListCoordinateSpace {
    static let name = "scriptList"
}

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    @State private var liveRowFrames: [UUID: CGRect] = [:]
    @State private var liveListSize: CGSize = .zero
    @State private var frozenFrames: [CGRect] = []
    @State private var frozenDraggingIndex: Int?
    @State private var frozenListSize: CGSize = .zero
    @State private var grabOffset: CGSize = .zero
    @State private var lastDragPoint: CGPoint = .zero
    @State private var swiftUIDragActive = false
    @State private var dragController = ScriptListDragController()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
                .padding(.top, 28)
                .padding(.horizontal, 28)

            Spacer()
                .frame(height: 24)

            if viewModel.scripts.isEmpty {
                emptyStateView
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
            } else {
                scriptListView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(minWidth: 780, minHeight: 460)
        .background(Theme.windowBackground)
        .preferredColorScheme(.dark)
        .task {
            await viewModel.loadScriptsIfNeeded()
        }
        .sheet(item: $viewModel.editorMode) { mode in
            ScriptEditorView(
                mode: mode,
                onSave: { configuration in
                    switch mode {
                    case .add:
                        viewModel.addScript(configuration)
                    case .edit:
                        viewModel.updateScript(configuration)
                    }
                    viewModel.editorMode = nil
                },
                onCancel: {
                    viewModel.editorMode = nil
                }
            )
        }
        .sheet(item: $viewModel.selectedScriptForOutput) { script in
            ScriptOutputSheetView(
                script: script,
                viewModel: viewModel,
                onClose: {
                    viewModel.selectedScriptForOutput = nil
                }
            )
        }
        .alert(
            removalAlertTitle,
            isPresented: removalAlertBinding,
            presenting: viewModel.pendingRemoval
        ) { _ in
            Button("Cancel", role: .cancel) {
                viewModel.pendingRemoval = nil
            }
            Button("Remove", role: .destructive) {
                viewModel.confirmRemoval()
            }
        } message: { _ in
            Text("This removes the configuration from ScriptDeck.\nThe original script file will not be deleted.")
        }
        .alert(
            "Storage Error",
            isPresented: storageErrorBinding,
            presenting: viewModel.storageErrorMessage
        ) { _ in
            Button("OK", role: .cancel) {
                viewModel.storageErrorMessage = nil
            }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your scripts. One deck.")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)

                if !viewModel.subtitleText.isEmpty {
                    Text(viewModel.subtitleText)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            Spacer()

            if !viewModel.scripts.isEmpty {
                addScriptButton
            }
        }
    }

    private var addScriptButton: some View {
        Button {
            viewModel.presentAddSheet()
        } label: {
            Label("Add script", systemImage: "plus")
                .font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(
            DeckActionButtonStyle(
                background: Theme.addButtonBackground,
                hoverBackground: Theme.addButtonHover,
                foreground: Theme.primaryText,
                cornerRadius: 8,
                borderColor: Theme.subtleBorder,
                horizontalPadding: 14,
                minHeight: 36
            )
        )
        .disabled(viewModel.isQuitting)
    }

    private var scriptListView: some View {
        ScrollView(.vertical) {
            VStack(spacing: 12) {
                ForEach(Array(viewModel.scripts.enumerated()), id: \.element.id) { index, script in
                    ScriptRowView(
                        configuration: script,
                        runtimeState: viewModel.runtimeState(for: script),
                        formattedDuration: viewModel.formattedDuration(for: script),
                        isQuitting: viewModel.isQuitting,
                        showsReorderHandle: viewModel.scripts.count > 1,
                        isDragSource: viewModel.draggingScriptID == script.id,
                        canMoveUp: index > 0,
                        canMoveDown: index < viewModel.scripts.count - 1,
                        onSelect: {
                            viewModel.presentOutput(for: script)
                        },
                        onStart: {
                            viewModel.start(script)
                        },
                        onStop: {
                            viewModel.stop(script)
                        },
                        onEdit: {
                            viewModel.presentEditSheet(for: script)
                        },
                        onRemove: {
                            viewModel.requestRemoval(of: script)
                        },
                        onMoveUp: {
                            viewModel.moveScriptUp(id: script.id)
                        },
                        onMoveDown: {
                            viewModel.moveScriptDown(id: script.id)
                        },
                        onReorderChanged: { value in
                            handleReorderChanged(script.id, value)
                        },
                        onReorderEnded: { value in
                            handleReorderEnded(value)
                        },
                        onReorderInterrupted: {
                            handleReorderInterrupted()
                        }
                    )
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ScriptRowFramesKey.self,
                                value: [script.id: proxy.frame(in: .named(ScriptListCoordinateSpace.name))]
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: ScriptListSizeKey.self, value: proxy.size)
                }
            }
            .background {
                ScriptListWindowFrameReader(controller: dragController)
            }
            .coordinateSpace(name: ScriptListCoordinateSpace.name)
            .overlay(alignment: .topLeading) {
                dragPreview
            }
        }
        .scrollDisabled(viewModel.draggingScriptID != nil)
        .onPreferenceChange(ScriptRowFramesKey.self) { liveRowFrames = $0 }
        .onPreferenceChange(ScriptListSizeKey.self) { liveListSize = $0 }
    }

    @ViewBuilder
    private var dragPreview: some View {
        if let preview = viewModel.scriptDragPreview,
           let id = viewModel.draggingScriptID,
           let script = viewModel.scripts.first(where: { $0.id == id }) {
            ScriptDragFloatingCard(script: script)
                .frame(width: max(preview.size.width, 1), height: max(preview.size.height, 1))
                .scaleEffect(1.015)
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                .offset(x: preview.topLeft.x, y: preview.topLeft.y)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transaction { transaction in
                    transaction.animation = nil
                }
        }
    }

    private func handleReorderChanged(_ scriptID: UUID, _ value: DragGesture.Value) {
        guard !viewModel.scriptDragBlocked else { return }
        swiftUIDragActive = true
        lastDragPoint = value.location
        if viewModel.draggingScriptID == nil {
            beginDrag(scriptID: scriptID, value: value)
        }
        guard viewModel.draggingScriptID == scriptID else { return }
        if let appKitPoint = dragController.currentPointInList() {
            dragController.observe(swift: value.location, appKit: appKitPoint)
        }
        continueDrag(at: value.location)
    }

    private func beginDrag(scriptID: UUID, value: DragGesture.Value) {
        let ids = viewModel.scripts.map(\.id)
        guard let index = ids.firstIndex(of: scriptID) else { return }
        let frames = ids.compactMap { liveRowFrames[$0] }
        guard frames.count == ids.count, frames[index].height > 1 else { return }

        frozenFrames = frames
        frozenDraggingIndex = index
        frozenListSize = liveListSize
        let frame = frames[index]
        grabOffset = CGSize(
            width: value.startLocation.x - frame.minX,
            height: value.startLocation.y - frame.minY
        )
        dragController.onMove = { point in
            guard !swiftUIDragActive else { return }
            continueDrag(at: dragController.convert(point))
        }
        dragController.onFinish = { point in
            guard viewModel.draggingScriptID != nil || viewModel.scriptDragBlocked else { return }
            let resolved = point.map { dragController.convert($0) } ?? lastDragPoint
            finishDrag(at: resolved)
        }
        viewModel.beginScriptDrag(id: scriptID)
        dragController.resetCalibration()
        dragController.begin()
    }

    private func continueDrag(at point: CGPoint) {
        guard !viewModel.scriptDragBlocked,
              let id = viewModel.draggingScriptID,
              let draggingIndex = frozenDraggingIndex,
              frozenFrames.indices.contains(draggingIndex) else { return }
        lastDragPoint = point
        let destination = ScriptReorder.destinationIndex(
            cursorY: point.y,
            frames: frozenFrames,
            draggingIndex: draggingIndex
        )
        viewModel.previewScriptMove(id: id, to: destination)
        viewModel.updateScriptDragPreview(
            topLeft: CGPoint(x: point.x - grabOffset.width, y: point.y - grabOffset.height),
            size: frozenFrames[draggingIndex].size
        )
    }

    private func handleReorderEnded(_ value: DragGesture.Value) {
        swiftUIDragActive = false
        guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
        finishDrag(at: value.location)
    }

    private func handleReorderInterrupted() {
        swiftUIDragActive = false
        Task { @MainActor in
            guard viewModel.draggingScriptID != nil || viewModel.scriptDragBlocked else { return }
            guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
            finishDrag(at: lastDragPoint)
        }
    }

    private func finishDrag(at point: CGPoint) {
        let blocked = viewModel.scriptDragBlocked
        if blocked {
            viewModel.clearScriptDragBlock()
        } else if releaseIsInsideList(point) {
            continueDrag(at: point)
            viewModel.endScriptDrag(committed: true)
        } else {
            viewModel.endScriptDrag(committed: false)
        }
        swiftUIDragActive = false
        dragController.endTracking()
        dragController.resetCalibration()
        frozenFrames = []
        frozenDraggingIndex = nil
        frozenListSize = .zero
        grabOffset = .zero
    }

    private func releaseIsInsideList(_ point: CGPoint) -> Bool {
        guard dragController.isPointerInsideWindow else { return false }
        let size = frozenListSize.width > 1
            ? frozenListSize
            : CGSize(
                width: frozenFrames.map(\.maxX).max() ?? 0,
                height: (frozenFrames.map(\.maxY).max() ?? 0) + 28
            )
        guard size.width > 1, size.height > 1 else { return false }
        let bounds = CGRect(
            x: -48,
            y: -32,
            width: size.width + 96,
            height: size.height + 80
        )
        return bounds.contains(point)
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Spacer()

            Text("No scripts yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.primaryText)

            Text("Add a local script to get started.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)

            addScriptButton
                .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Alert Bindings

    private var removalAlertTitle: String {
        guard let script = viewModel.pendingRemoval else {
            return "Remove script?"
        }
        return "Remove “\(script.name)”?"
    }

    private var removalAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.pendingRemoval = nil
                }
            }
        )
    }

    private var storageErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.storageErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.storageErrorMessage = nil
                }
            }
        )
    }
}

private struct ScriptDragFloatingCard: View {
    let script: ScriptConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(script.name)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
            Text(CommandSummaryFormatter.summary(for: script))
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.rowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.startButtonBackground.opacity(0.85), lineWidth: 1)
        )
    }
}

private struct ScriptRowFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ScriptListSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 1, next.height > 1 {
            value = next
        }
    }
}

@MainActor
private final class ScriptListDragController {
    var onMove: ((CGPoint) -> Void)?
    var onFinish: ((CGPoint?) -> Void)?
    nonisolated(unsafe) private var monitor: Any?
    private weak var listView: NSView?
    private var anchorSwift = CGPoint.zero
    private var anchorAppKit = CGPoint.zero
    private var firstSwift = CGPoint.zero
    private var firstAppKit = CGPoint.zero
    private var scale = CGSize(width: 1, height: 1)
    private var hasCalibrationSample = false

    var isPointerInsideWindow: Bool {
        guard let window = listView?.window else { return true }
        return window.frame.contains(NSEvent.mouseLocation)
    }

    func attach(_ view: NSView) {
        listView = view
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func observe(swift: CGPoint, appKit: CGPoint) {
        if hasCalibrationSample {
            let deltaSwiftY = swift.y - firstSwift.y
            let deltaAppKitY = appKit.y - firstAppKit.y
            if abs(deltaSwiftY) > 16, abs(deltaAppKitY) > 16, let snapped = snappedScale(deltaSwiftY / deltaAppKitY) {
                scale.height = snapped
            }
            let deltaSwiftX = swift.x - firstSwift.x
            let deltaAppKitX = appKit.x - firstAppKit.x
            if abs(deltaSwiftX) > 16, abs(deltaAppKitX) > 16, let snapped = snappedScale(deltaSwiftX / deltaAppKitX) {
                scale.width = snapped
            }
        } else {
            firstSwift = swift
            firstAppKit = appKit
            hasCalibrationSample = true
        }
        anchorSwift = swift
        anchorAppKit = appKit
    }

    func convert(_ appKit: CGPoint) -> CGPoint {
        guard hasCalibrationSample else { return appKit }
        return CGPoint(
            x: anchorSwift.x + (appKit.x - anchorAppKit.x) * scale.width,
            y: anchorSwift.y + (appKit.y - anchorAppKit.y) * scale.height
        )
    }

    func resetCalibration() {
        anchorSwift = .zero
        anchorAppKit = .zero
        firstSwift = .zero
        firstAppKit = .zero
        scale = CGSize(width: 1, height: 1)
        hasCalibrationSample = false
    }

    func currentPointInList() -> CGPoint? {
        guard let listView, let window = listView.window else { return nil }
        return pointInList(window.convertPoint(fromScreen: NSEvent.mouseLocation))
    }

    func begin() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let isMouseUp = event.type == .leftMouseUp
            let point = MainActor.assumeIsolated { self?.pointInList(event.locationInWindow) }
            if isMouseUp {
                MainActor.assumeIsolated {
                    self?.endTracking()
                }
                Task { @MainActor in
                    self?.onFinish?(point)
                }
            } else if let point {
                MainActor.assumeIsolated {
                    self?.onMove?(point)
                }
            }
            return event
        }
    }

    func endTracking() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private func snappedScale(_ raw: CGFloat) -> CGFloat? {
        guard abs(abs(raw) - 1) < 0.35 else { return nil }
        return raw < 0 ? -1 : 1
    }

    private func pointInList(_ windowPoint: CGPoint) -> CGPoint? {
        guard let listView, listView.window != nil, listView.bounds.height > 1 else { return nil }
        let local = listView.convert(windowPoint, from: nil)
        return CGPoint(
            x: local.x - listView.bounds.minX,
            y: local.y - listView.bounds.minY
        )
    }
}

private struct ScriptListWindowFrameReader: NSViewRepresentable {
    let controller: ScriptListDragController

    func makeNSView(context: Context) -> ScriptListFrameView {
        let view = ScriptListFrameView()
        view.onLayout = { [weak view] in
            guard let view else { return }
            controller.attach(view)
        }
        return view
    }

    func updateNSView(_ nsView: ScriptListFrameView, context: Context) {
        nsView.onLayout = { [weak nsView] in
            guard let nsView else { return }
            controller.attach(nsView)
        }
        controller.attach(nsView)
    }
}

private final class ScriptListFrameView: NSView {
    override var isFlipped: Bool { true }

    var onLayout: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onLayout?()
    }

    override func layout() {
        super.layout()
        onLayout?()
    }
}
