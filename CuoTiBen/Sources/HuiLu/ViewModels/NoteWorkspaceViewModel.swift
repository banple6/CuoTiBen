import Foundation
import Combine
import CoreGraphics

enum NoteOutlineFloatingPanelState: String, CaseIterable, Identifiable {
    case expanded
    case compact
    case hidden

    var id: String { rawValue }
}

enum NoteOutlineFloatingPanelMode: String, CaseIterable, Identifiable {
    case structure
    case map

    var id: String { rawValue }

    var title: String {
        switch self {
        case .structure:
            return "结构树"
        case .map:
            return "导图"
        }
    }
}

struct WorkspaceOutlineContext: Equatable {
    let currentNode: OutlineNode?
    let pathNodes: [OutlineNode]
    let nearbyNodes: [OutlineNode]
}

enum CanvasResolvedTool: Equatable {
    case pen
    case pencil
    case ballpoint
    case highlighter
    case eraser
    case lasso
    case text
    case select
}

enum CanvasSelectionMode: String {
    case none
    case object
    case ink
}

enum CanvasSelectionKind: String {
    case textObject
    case imageObject
    case quoteObject
    case knowledgeCardObject
    case linkPreviewObject
    case inkSelection
    case mixed

    init?(elementKind: CanvasElementKind) {
        switch elementKind {
        case .textObject:
            self = .textObject
        case .imageObject:
            self = .imageObject
        case .quoteObject:
            self = .quoteObject
        case .knowledgeCardObject:
            self = .knowledgeCardObject
        case .linkPreviewObject:
            self = .linkPreviewObject
        case .inkStroke, .inkSelectionObject:
            return nil
        }
    }

    var label: String {
        switch self {
        case .textObject:
            return "文本对象"
        case .imageObject:
            return "图片对象"
        case .quoteObject:
            return "引用对象"
        case .knowledgeCardObject:
            return "知识卡"
        case .linkPreviewObject:
            return "链接卡片"
        case .inkSelection:
            return "墨迹选区"
        case .mixed:
            return "多选对象"
        }
    }
}

enum CanvasInteractionMode: String {
    case idle
    case selecting
    case moving
    case resizing
    case editingText
    case lasso
}

enum CanvasTransformHandle: String, CaseIterable, Identifiable {
    case move
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }

    var resizeCorner: ResizeCorner? {
        switch self {
        case .topLeft:
            return .topLeft
        case .topRight:
            return .topRight
        case .bottomLeft:
            return .bottomLeft
        case .bottomRight:
            return .bottomRight
        case .move:
            return nil
        }
    }
}

enum CanvasSelectionState: Equatable {
    case none
    case textObject(UUID)
    case inkSelection
}

enum CanvasViewportGesturePolicy: String {
    case standard
    case selectionAware
    case textEditing
}

@MainActor
final class CanvasToolController: ObservableObject {
    @Published private(set) var currentTool: CanvasResolvedTool = .pen
    @Published private(set) var previousTool: CanvasResolvedTool?
    @Published private(set) var inkOptions = NoteInkToolState()
    @Published private(set) var selectionMode: CanvasSelectionMode = .none

    func sync(workspaceTool: WorkspaceTool, inkState: NoteInkToolState) {
        let resolved = Self.resolve(workspaceTool: workspaceTool, inkState: inkState)
        if currentTool != resolved {
            previousTool = currentTool
            currentTool = resolved
        }
        inkOptions = inkState
        if workspaceTool == .select {
            selectionMode = inkState.kind == .lasso ? .ink : .object
        } else if workspaceTool == .text {
            selectionMode = .object
        } else {
            selectionMode = .none
        }
    }

    private static func resolve(workspaceTool: WorkspaceTool, inkState: NoteInkToolState) -> CanvasResolvedTool {
        switch workspaceTool {
        case .pen:
            return .pen
        case .pencil:
            return .pencil
        case .ballpoint:
            return .ballpoint
        case .highlighter:
            return .highlighter
        case .eraser:
            return .eraser
        case .select:
            return inkState.kind == .lasso ? .lasso : .select
        case .text:
            return .text
        }
    }
}

@MainActor
final class CanvasSelectionController: ObservableObject {
    @Published private(set) var selection: CanvasSelectionState = .none
    @Published private(set) var selectedObjectIDs: [UUID] = []
    @Published private(set) var primarySelectionID: UUID?
    @Published private(set) var selectionBounds: CGRect = .null
    @Published private(set) var activeHandle: CanvasTransformHandle?
    @Published private(set) var interactionMode: CanvasInteractionMode = .idle
    @Published private(set) var selectionKind: CanvasSelectionKind?
    @Published var showsInspector = false

    func sync(from editorSelection: EditorSelection, objects: [CanvasElement], inkBounds: CGRect? = nil) {
        switch editorSelection {
        case .textBlock:
            clearObjectSelection()
            selection = .none
            interactionMode = .idle
        case .none:
            if selectionKind == .textObject || selectionKind == .inkSelection || selectedObjectIDs.isEmpty {
                clear()
            } else {
                selection = .none
                activeHandle = nil
                interactionMode = .idle
            }
        case .textObject(let id):
            guard let element = objects.first(where: { $0.id == id }) else {
                clear()
                return
            }
            selectObject(element)
            selection = .textObject(id)
            interactionMode = .editingText
        case .inkSelection:
            clearObjectSelection()
            selection = .inkSelection
            selectionKind = .inkSelection
            selectionBounds = inkBounds ?? selectionBounds
            interactionMode = .lasso
        }
    }

    func selectObject(_ element: CanvasElement, additive: Bool = false) {
        var nextIDs = additive ? selectedObjectIDs : []
        if !nextIDs.contains(element.id) {
            nextIDs.append(element.id)
        }
        selectedObjectIDs = nextIDs
        primarySelectionID = element.id
        selectionKind = CanvasSelectionKind(elementKind: element.kind)
        selectionBounds = element.effectiveFrame
        activeHandle = nil
        interactionMode = .selecting
        selection = element.kind == .textObject ? .textObject(element.id) : .none
        showsInspector = false
    }

    func refreshSelection(from objects: [CanvasElement], inkBounds: CGRect? = nil) {
        if selectionKind == .inkSelection {
            if let inkBounds {
                selectionBounds = inkBounds
            }
            return
        }

        let selectedElements = selectedObjectIDs.compactMap { id in
            objects.first(where: { $0.id == id })
        }

        guard !selectedElements.isEmpty else {
            clear()
            return
        }

        let unionRect = selectedElements.dropFirst().reduce(selectedElements[0].effectiveFrame) { partial, element in
            partial.union(element.effectiveFrame)
        }
        let kinds = Set(selectedElements.compactMap { CanvasSelectionKind(elementKind: $0.kind) })
        selectionBounds = unionRect
        selectionKind = kinds.count == 1 ? kinds.first : .mixed
        if let primarySelectionID, !selectedElements.contains(where: { $0.id == primarySelectionID }) {
            self.primarySelectionID = selectedElements.first?.id
        }
        if let primarySelectionID,
           let primary = selectedElements.first(where: { $0.id == primarySelectionID }),
           primary.kind == .textObject {
            selection = .textObject(primarySelectionID)
        } else {
            selection = .none
        }
    }

    func updateSelectionBounds(_ rect: CGRect?) {
        selectionBounds = rect ?? .null
    }

    func beginInteraction(_ mode: CanvasInteractionMode, handle: CanvasTransformHandle?) {
        interactionMode = mode
        activeHandle = handle
    }

    func endInteraction() {
        activeHandle = nil
        interactionMode = primarySelectionID == nil ? .idle : .selecting
    }

    func contains(_ id: UUID) -> Bool {
        selectedObjectIDs.contains(id)
    }

    func clear() {
        clearObjectSelection()
        selection = .none
        selectionBounds = .null
        selectionKind = nil
        activeHandle = nil
        interactionMode = .idle
        showsInspector = false
    }

    var selectedTextObjectID: UUID? {
        if case .textObject(let id) = selection {
            return id
        }
        return nil
    }

    private func clearObjectSelection() {
        selectedObjectIDs = []
        primarySelectionID = nil
    }
}

@MainActor
final class CanvasViewportController: ObservableObject {
    @Published private(set) var state: CanvasViewportState
    @Published private(set) var minimumZoomScale: CGFloat
    @Published private(set) var maximumZoomScale: CGFloat
    @Published private(set) var gesturePolicy: CanvasViewportGesturePolicy
    @Published private(set) var showsZoomHUD = true

    init(
        state: CanvasViewportState,
        minimumZoomScale: CGFloat = 0.75,
        maximumZoomScale: CGFloat = 3,
        gesturePolicy: CanvasViewportGesturePolicy = .standard
    ) {
        self.state = state
        self.minimumZoomScale = minimumZoomScale
        self.maximumZoomScale = maximumZoomScale
        self.gesturePolicy = gesturePolicy
    }

    func update(
        zoomScale: CGFloat,
        contentOffset: CGPoint,
        visibleRect: CGRect,
        fitMode: CanvasViewportFitMode? = nil
    ) {
        state.zoomScale = zoomScale
        state.contentOffset = contentOffset
        state.visibleRect = visibleRect
        if let fitMode {
            state.fitMode = fitMode
        }
    }

    func updatePageInsets(_ insets: CanvasViewportInsets) {
        state.pageInsets = insets
    }

    func updateScaleRange(min: CGFloat, max: CGFloat) {
        minimumZoomScale = min
        maximumZoomScale = max
    }

    func updateGesturePolicy(_ policy: CanvasViewportGesturePolicy) {
        gesturePolicy = policy
    }

    var zoomHUDLabel: String {
        "\(Int((state.zoomScale * 100).rounded()))%"
    }
}

protocol CanvasCommand {
    var label: String { get }
    func execute(in vm: NoteWorkspaceViewModel)
    func undo(in vm: NoteWorkspaceViewModel)
}

@MainActor
final class CanvasHistoryController: ObservableObject {
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private var undoStack: [any CanvasCommand] = []
    private var redoStack: [any CanvasCommand] = []
    private var savedUndoDepth = 0

    func perform(_ command: any CanvasCommand, in vm: NoteWorkspaceViewModel) {
        command.execute(in: vm)
        undoStack.append(command)
        redoStack.removeAll()
        publishState()
    }

    func undo(in vm: NoteWorkspaceViewModel) {
        guard let command = undoStack.popLast() else { return }
        command.undo(in: vm)
        redoStack.append(command)
        publishState()
    }

    func redo(in vm: NoteWorkspaceViewModel) {
        guard let command = redoStack.popLast() else { return }
        command.execute(in: vm)
        undoStack.append(command)
        publishState()
    }

    func markSaved() {
        savedUndoDepth = undoStack.count
        publishState()
    }

    var hasUnpersistedChanges: Bool {
        undoStack.count != savedUndoDepth
    }

    private func publishState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}

struct InsertCanvasObjectAction: CanvasCommand {
    let element: CanvasElement
    var label: String { "InsertCanvasObjectAction" }

    func execute(in vm: NoteWorkspaceViewModel) {
        vm.applyUpsertCanvasElement(element)
    }

    func undo(in vm: NoteWorkspaceViewModel) {
        vm.applyDeleteCanvasElement(id: element.id)
    }
}

struct DeleteCanvasObjectAction: CanvasCommand {
    let element: CanvasElement
    var label: String { "DeleteCanvasObjectAction" }

    func execute(in vm: NoteWorkspaceViewModel) {
        vm.applyDeleteCanvasElement(id: element.id)
    }

    func undo(in vm: NoteWorkspaceViewModel) {
        vm.applyUpsertCanvasElement(element)
    }
}

struct MoveCanvasObjectAction: CanvasCommand {
    let objectID: UUID
    let fromFrame: CGRect
    let toFrame: CGRect
    var label: String { "MoveCanvasObjectAction" }

    func execute(in vm: NoteWorkspaceViewModel) {
        vm.applyCanvasElementFrame(id: objectID, frame: toFrame)
    }

    func undo(in vm: NoteWorkspaceViewModel) {
        vm.applyCanvasElementFrame(id: objectID, frame: fromFrame)
    }
}

struct ResizeCanvasObjectAction: CanvasCommand {
    let objectID: UUID
    let fromRect: CGRect
    let toRect: CGRect
    var label: String { "ResizeCanvasObjectAction" }

    func execute(in vm: NoteWorkspaceViewModel) {
        vm.applyCanvasElementFrame(id: objectID, frame: toRect)
    }

    func undo(in vm: NoteWorkspaceViewModel) {
        vm.applyCanvasElementFrame(id: objectID, frame: fromRect)
    }
}

struct UpdateCanvasObjectStyleAction: CanvasCommand {
    let objectID: UUID
    let from: CanvasElement
    let to: CanvasElement
    var label: String { "UpdateCanvasObjectStyleAction" }

    func execute(in vm: NoteWorkspaceViewModel) {
        vm.applyReplaceCanvasElement(to)
    }

    func undo(in vm: NoteWorkspaceViewModel) {
        vm.applyReplaceCanvasElement(from)
    }
}

struct ReorderCanvasObjectAction: CanvasCommand {
    let objectID: UUID
    let fromZIndex: Int
    let toZIndex: Int
    var label: String { "ReorderCanvasObjectAction" }

    func execute(in vm: NoteWorkspaceViewModel) {
        vm.applyCanvasElementZIndex(id: objectID, zIndex: toZIndex)
    }

    func undo(in vm: NoteWorkspaceViewModel) {
        vm.applyCanvasElementZIndex(id: objectID, zIndex: fromZIndex)
    }
}

struct InsertInkStrokeAction: CanvasCommand {
    let previousBlock: NoteBlock?
    let nextBlock: NoteBlock?
    var label: String { "InsertInkStrokeAction" }

    func execute(in vm: NoteWorkspaceViewModel) {
        vm.applyInkBlockState(nextBlock)
    }

    func undo(in vm: NoteWorkspaceViewModel) {
        vm.applyInkBlockState(previousBlock)
    }
}

struct DeleteInkSelectionAction: CanvasCommand {
    let previousBlock: NoteBlock?
    let nextBlock: NoteBlock?
    var label: String { "DeleteInkSelectionAction" }

    func execute(in vm: NoteWorkspaceViewModel) {
        vm.applyInkBlockState(nextBlock)
    }

    func undo(in vm: NoteWorkspaceViewModel) {
        vm.applyInkBlockState(previousBlock)
    }
}

struct UpdatePaperConfigAction: CanvasCommand {
    let from: NotePaperConfiguration
    let to: NotePaperConfiguration
    var label: String { "UpdatePaperConfigAction" }

    func execute(in vm: NoteWorkspaceViewModel) {
        vm.applyPaperConfiguration(to)
    }

    func undo(in vm: NoteWorkspaceViewModel) {
        vm.applyPaperConfiguration(from)
    }
}

@MainActor
final class NoteWorkspaceViewModel: ObservableObject {
    @Published private(set) var note: Note
    @Published private(set) var sourceDocument: SourceDocument?
    @Published private(set) var structuredSource: StructuredSourceBundle? {
        didSet {
            rebuildOutlineContext()
        }
    }
    @Published private(set) var linkedKnowledgePoints: [KnowledgePoint] = []
    @Published private(set) var candidateKnowledgePoints: [KnowledgePoint] = []
    @Published private(set) var outlineContext: WorkspaceOutlineContext
    @Published var title: String
    @Published var blocks: [NoteBlock]
    @Published var textObjects: [CanvasTextObject]
    @Published var canvasObjectElements: [CanvasElement]
    @Published var selectedOutlineNodeID: String? {
        didSet {
            rebuildOutlineContext()
        }
    }
    @Published var highlightedBlockID: UUID?
    @Published var editingTextBlockID: UUID?
    @Published var panelState: NoteOutlineFloatingPanelState = .hidden
    @Published var panelMode: NoteOutlineFloatingPanelMode = .structure
    @Published var isDirty = false
    @Published var isSaving = false
    @Published var lastSavedAt: Date?

    let toolController = CanvasToolController()
    let selectionController = CanvasSelectionController()
    let viewportController: CanvasViewportController
    let historyController = CanvasHistoryController()

    private var autosaveTask: Task<Void, Never>?

    init(note: Note) {
        let initialCanvasElements = Self.resolvedCanvasObjectElements(for: note)
        self.note = note
        self.title = note.title
        self.blocks = note.blocks
        self.textObjects = note.textObjects
        self.canvasObjectElements = initialCanvasElements
        self.selectedOutlineNodeID = note.sourceAnchor.outlineNodeID
        self.viewportController = CanvasViewportController(state: note.document?.viewport ?? CanvasViewportState())
        self.outlineContext = WorkspaceOutlineContext(
            currentNode: nil,
            pathNodes: [],
            nearbyNodes: []
        )
        self.lastSavedAt = note.updatedAt
        self.historyController.markSaved()
        syncLegacyContentFromCanvasElements()
        selectionController.refreshSelection(from: canvasObjectElements)
        rebuildOutlineContext()
    }

    var sourceAnchor: SourceAnchor {
        note.sourceAnchor
    }

    var sourceHint: String {
        [sourceAnchor.sourceTitle, sourceAnchor.anchorLabel]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " · ")
    }

    var notebookContextLine: String {
        let nodeLabel = outlineContext.currentNode?.title ?? "未绑定节点"
        let pageLabel = sourceAnchor.pageIndex.map { "第\($0)页" } ?? "原文定位"
        return "\(pageLabel) · \(sourceAnchor.anchorLabel) · \(nodeLabel)"
    }

    var saveStatusText: String {
        if isSaving {
            return "保存中"
        }
        return isDirty ? "未保存" : "已保存"
    }

    var paperConfiguration: NotePaperConfiguration {
        note.document?.paper ?? note.resolvedDocument.paper
    }

    var primarySelectedCanvasElement: CanvasElement? {
        selectionController.primarySelectionID.flatMap { id in
            canvasElement(with: id)
        }
    }

    private static func resolvedCanvasObjectElements(for note: Note) -> [CanvasElement] {
        let document = note.document ?? note.resolvedDocument
        return document.firstLayer(kind: .object)?.elements.sorted { $0.resolvedZIndex < $1.resolvedZIndex } ?? []
    }

    private var resolvedPageID: UUID {
        note.document?.primaryPage?.id
            ?? note.resolvedDocument.primaryPage?.id
            ?? UUID()
    }

    private var resolvedObjectLayerID: UUID {
        note.document?.firstLayer(kind: .object)?.id
            ?? note.resolvedDocument.firstLayer(kind: .object)?.id
            ?? UUID()
    }

    private func nextObjectZIndex(for layoutRole: CanvasElementLayoutRole) -> Int {
        let matching = canvasObjectElements
            .filter { $0.metadata.layoutRole == layoutRole }
            .map(\.resolvedZIndex)
        return (matching.max() ?? -1) + 1
    }

    private func nextFlowFrame(defaultHeight: CGFloat = 88) -> CGRect {
        let flowElements = canvasObjectElements
            .filter { $0.isFlowObject && $0.isVisibleObject }
            .sorted { $0.effectiveFrame.maxY < $1.effectiveFrame.maxY }

        let nextY = (flowElements.last?.effectiveFrame.maxY ?? 120) + 24
        return CGRect(x: 72, y: nextY, width: 720, height: defaultHeight)
    }

    func reload(using appViewModel: AppViewModel) {
        if let refreshed = appViewModel.note(with: note.id) {
            note = refreshed
            title = refreshed.title
            blocks = refreshed.blocks
            textObjects = refreshed.textObjects
            canvasObjectElements = Self.resolvedCanvasObjectElements(for: refreshed)
                .sorted { $0.resolvedZIndex < $1.resolvedZIndex }
            lastSavedAt = refreshed.updatedAt
            if let viewport = refreshed.document?.viewport {
                viewportController.update(
                    zoomScale: viewport.zoomScale,
                    contentOffset: viewport.contentOffset,
                    visibleRect: viewport.visibleRect,
                    fitMode: viewport.fitMode
                )
            }
            syncLegacyContentFromCanvasElements()
            selectionController.refreshSelection(from: canvasObjectElements)
        }

        sourceDocument = appViewModel.sourceDocument(for: note.sourceAnchor)
        structuredSource = appViewModel.noteSourceBundle(for: note)

        let mergedIDs = note.linkedKnowledgePointIDs
        linkedKnowledgePoints = appViewModel.linkedKnowledgePoints(for: mergedIDs)
        candidateKnowledgePoints = appViewModel.allKnowledgePoints()

        if selectedOutlineNodeID == nil {
            selectedOutlineNodeID = note.sourceAnchor.outlineNodeID
                ?? structuredSource?.bestOutlineNode(forSentenceID: note.sourceAnchor.sentenceID)?.id
        } else {
            rebuildOutlineContext()
        }
    }

    func updateTitle(_ newValue: String) {
        title = newValue
        markDirty()
    }

    func updateTextBlock(id: UUID, text: String) {
        if let element = canvasElement(with: id) {
            let updated = element.withText(text)
            applyReplaceCanvasElement(updated)
            return
        }
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[index].text = text
        blocks[index].updatedAt = Date()
        markDirty()
    }

    func updateInkBlock(_ block: NoteBlock) {
        guard let index = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        blocks[index] = block
        blocks[index].updatedAt = Date()
        markDirty()
    }

    /// Sync ink data from the live PKCanvasView into the blocks array.
    /// Call this before saving — the PKCanvasView is the source of truth for ink while open.
    func syncInkFromBridge(_ bridge: InkActionBridge) {
        guard let data = bridge.currentDrawingData() else { return }
        let bounds = bridge.currentDrawingBounds()
        let previousBlock = blocks.first(where: { $0.kind == .ink })

        if bounds.isEmpty {
            guard previousBlock != nil else { return }
            historyController.perform(
                DeleteInkSelectionAction(previousBlock: previousBlock, nextBlock: nil),
                in: self
            )
            return
        }

        var nextBlock = previousBlock ?? NoteBlock(kind: .ink, linkedSourceAnchorID: sourceAnchor.id)
        nextBlock.inkData = data
        nextBlock.inkGeometry = InkGeometry(
            normalizedBounds: bounds,
            pageIndex: previousBlock?.inkGeometry?.pageIndex,
            pageCount: previousBlock?.inkGeometry?.pageCount
        )
        nextBlock.updatedAt = Date()

        guard previousBlock != nextBlock else { return }
        historyController.perform(
            InsertInkStrokeAction(previousBlock: previousBlock, nextBlock: nextBlock),
            in: self
        )
    }

    /// Mark as dirty without triggering redundant body re-renders.
    func markInkDirty() {
        if !isDirty { isDirty = true }
    }

    func addTextBlock() {
        let frame = nextFlowFrame(defaultHeight: 84)
        let element = CanvasElement(
            kind: .textObject,
            frame: frame,
            metadata: CanvasElementMetadata(
                sourceAnchorID: sourceAnchor.id,
                pageID: resolvedPageID,
                layerID: resolvedObjectLayerID,
                zIndex: nextObjectZIndex(for: .flow),
                layoutRole: .flow
            ),
            textObject: CanvasTextObject(
                text: "",
                x: frame.origin.x,
                y: frame.origin.y,
                width: frame.width,
                height: frame.height,
                zIndex: nextObjectZIndex(for: .flow),
                pageID: resolvedPageID,
                layerID: resolvedObjectLayerID
            )
        )
        historyController.perform(InsertCanvasObjectAction(element: element), in: self)
        highlightedBlockID = element.id
        editingTextBlockID = element.id
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Canvas Text Object CRUD
    // ═══════════════════════════════════════════════════════════

    /// Create a new text object at the given paper-space position. Returns the new object's ID.
    @discardableResult
    func createTextObject(at point: CGPoint, width: CGFloat = 260) -> UUID {
        let nextZ = nextObjectZIndex(for: .floating)
        let obj = CanvasTextObject(
            text: "",
            x: point.x,
            y: point.y,
            width: width,
            zIndex: nextZ,
            pageID: resolvedPageID,
            layerID: resolvedObjectLayerID
        )
        let element = CanvasElement(
            id: obj.id,
            kind: .textObject,
            frame: obj.frame,
            metadata: CanvasElementMetadata(
                sourceAnchorID: sourceAnchor.id,
                pageID: resolvedPageID,
                layerID: resolvedObjectLayerID,
                zIndex: nextZ,
                layoutRole: .floating
            ),
            textObject: obj
        )
        historyController.perform(InsertCanvasObjectAction(element: element), in: self)
        return element.id
    }

    func moveCanvasObject(id: UUID, to point: CGPoint) {
        guard let element = canvasElement(with: id) else { return }
        let fromFrame = element.effectiveFrame
        let toFrame = CGRect(origin: point, size: fromFrame.size)
        guard fromFrame != toFrame else { return }
        historyController.perform(
            MoveCanvasObjectAction(objectID: id, fromFrame: fromFrame, toFrame: toFrame),
            in: self
        )
    }

    func resizeCanvasObject(id: UUID, to frame: CGRect) {
        guard let element = canvasElement(with: id) else { return }
        let fromFrame = element.effectiveFrame
        guard fromFrame != frame else { return }
        historyController.perform(
            ResizeCanvasObjectAction(objectID: id, fromRect: fromFrame, toRect: frame),
            in: self
        )
    }

    func deleteCanvasObject(id: UUID) {
        guard let element = canvasElement(with: id) else { return }
        historyController.perform(DeleteCanvasObjectAction(element: element), in: self)
    }

    func updateTextObject(id: UUID, text: String) {
        guard let element = canvasElement(with: id) else { return }
        applyReplaceCanvasElement(element.withText(text))
    }

    func moveTextObject(id: UUID, to point: CGPoint) {
        guard let object = textObject(with: id) else { return }
        let fromFrame = object.frame
        let toFrame = CGRect(origin: point, size: fromFrame.size)
        guard fromFrame != toFrame else { return }
        historyController.perform(MoveCanvasObjectAction(objectID: id, fromFrame: fromFrame, toFrame: toFrame), in: self)
    }

    func resizeTextObject(id: UUID, x: CGFloat? = nil, y: CGFloat? = nil, width: CGFloat, height: CGFloat) {
        guard let object = textObject(with: id) else { return }
        let fromRect = object.frame
        let toRect = CGRect(
            x: x ?? object.x,
            y: y ?? object.y,
            width: max(width, object.minWidth),
            height: max(height, object.minHeight)
        )
        guard fromRect != toRect else { return }
        historyController.perform(
            ResizeCanvasObjectAction(objectID: id, fromRect: fromRect, toRect: toRect),
            in: self
        )
    }

    func updateTextObjectStyle(
        id: UUID,
        textStyle: BlockTextStyle? = nil,
        textColor: BlockTextColor? = nil,
        highlightStyle: BlockHighlight? = nil,
        fontSizePreset: BlockFontSize? = nil,
        textAlignment: CanvasTextAlignment? = nil
    ) {
        guard let element = canvasElement(with: id) else { return }
        let updated = element.withTextStyle(
            textStyle: textStyle,
            textColor: textColor,
            highlightStyle: highlightStyle,
            fontSizePreset: fontSizePreset,
            textAlignment: textAlignment
        )
        guard updated != element else { return }
        historyController.perform(
            UpdateCanvasObjectStyleAction(objectID: id, from: element, to: updated),
            in: self
        )
    }

    func deleteTextObject(id: UUID) {
        guard let element = canvasElement(with: id) else { return }
        historyController.perform(DeleteCanvasObjectAction(element: element), in: self)
    }

    func textObject(with id: UUID) -> CanvasTextObject? {
        canvasElement(with: id)?.textObject ?? textObjects.first { $0.id == id }
    }

    var editingBlock: NoteBlock? {
        guard let id = editingTextBlockID else { return nil }
        return blocks.first(where: { $0.id == id })
    }

    func updateBlockStyle(id: UUID, textStyle: BlockTextStyle?, textColor: BlockTextColor?, highlightStyle: BlockHighlight?, fontSizePreset: BlockFontSize?) {
        if let element = canvasElement(with: id) {
            let updated = element.withTextStyle(
                textStyle: textStyle,
                textColor: textColor,
                highlightStyle: highlightStyle,
                fontSizePreset: fontSizePreset
            )
            applyReplaceCanvasElement(updated)
            return
        }
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[index].textStyle = textStyle
        blocks[index].textColor = textColor
        blocks[index].highlightStyle = highlightStyle
        blocks[index].fontSizePreset = fontSizePreset
        blocks[index].updatedAt = Date()
        markDirty()
    }

    func addInkBlock() {
        blocks.append(
            NoteBlock(
                kind: .ink,
                linkedSourceAnchorID: note.sourceAnchor.id
            )
        )
        highlightedBlockID = blocks.last?.id
        markDirty()
    }

    func ensureInkBlock() {
        if let existing = blocks.last(where: { $0.kind == .ink }) {
            highlightedBlockID = existing.id
            return
        }

        addInkBlock()
    }

    func addQuoteBlockFromSource() {
        let text = note.sourceAnchor.quotedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let frame = nextFlowFrame(defaultHeight: 84)
        let element = CanvasElement(
            kind: .quoteObject,
            frame: frame,
            metadata: CanvasElementMetadata(
                sourceAnchorID: note.sourceAnchor.id,
                pageID: resolvedPageID,
                layerID: resolvedObjectLayerID,
                zIndex: nextObjectZIndex(for: .flow),
                layoutRole: .flow
            ),
            quoteObject: CanvasQuoteObject(
                text: text,
                sourceAnchorID: note.sourceAnchor.id,
                citation: sourceAnchor.anchorLabel
            )
        )
        historyController.perform(InsertCanvasObjectAction(element: element), in: self)
        highlightedBlockID = element.id
    }

    /// Insert an arbitrary quote excerpt into the note
    func insertQuote(text: String, anchorID: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let frame = nextFlowFrame(defaultHeight: 84)
        let element = CanvasElement(
            kind: .quoteObject,
            frame: frame,
            metadata: CanvasElementMetadata(
                sourceAnchorID: anchorID ?? note.sourceAnchor.id,
                pageID: resolvedPageID,
                layerID: resolvedObjectLayerID,
                zIndex: nextObjectZIndex(for: .flow),
                layoutRole: .flow
            ),
            quoteObject: CanvasQuoteObject(
                text: trimmed,
                sourceAnchorID: anchorID ?? note.sourceAnchor.id,
                citation: sourceAnchor.anchorLabel
            )
        )
        historyController.perform(InsertCanvasObjectAction(element: element), in: self)
        highlightedBlockID = element.id
    }

    @discardableResult
    func createImageObject(
        imageData: Data? = nil,
        remoteURL: String? = nil,
        caption: String? = nil,
        at point: CGPoint,
        size: CGSize = CGSize(width: 280, height: 200)
    ) -> UUID {
        let nextZ = nextObjectZIndex(for: .floating)
        let frame = CGRect(origin: point, size: size)
        let element = CanvasElement(
            kind: .imageObject,
            frame: frame,
            metadata: CanvasElementMetadata(
                sourceAnchorID: sourceAnchor.id,
                pageID: resolvedPageID,
                layerID: resolvedObjectLayerID,
                zIndex: nextZ,
                layoutRole: .floating
            ),
            imageObject: CanvasImageObject(
                imageData: imageData,
                remoteURL: remoteURL,
                caption: caption
            )
        )
        historyController.perform(InsertCanvasObjectAction(element: element), in: self)
        return element.id
    }

    @discardableResult
    func createKnowledgeCardObject(
        title: String,
        summary: String,
        linkedKnowledgePointIDs: [String] = [],
        at point: CGPoint,
        size: CGSize = CGSize(width: 320, height: 180)
    ) -> UUID {
        let nextZ = nextObjectZIndex(for: .floating)
        let frame = CGRect(origin: point, size: size)
        let element = CanvasElement(
            kind: .knowledgeCardObject,
            frame: frame,
            metadata: CanvasElementMetadata(
                sourceAnchorID: sourceAnchor.id,
                linkedKnowledgePointIDs: linkedKnowledgePointIDs,
                pageID: resolvedPageID,
                layerID: resolvedObjectLayerID,
                zIndex: nextZ,
                layoutRole: .floating
            ),
            knowledgeCardObject: CanvasKnowledgeCardObject(
                title: title,
                summary: summary,
                linkedKnowledgePointIDs: linkedKnowledgePointIDs
            )
        )
        historyController.perform(InsertCanvasObjectAction(element: element), in: self)
        return element.id
    }

    func updateKnowledgeCardObject(
        id: UUID,
        title: String? = nil,
        summary: String? = nil,
        linkedKnowledgePointIDs: [String]? = nil
    ) {
        guard var element = canvasElement(with: id),
              var card = element.knowledgeCardObject else { return }
        if let title {
            card.title = title
        }
        if let summary {
            card.summary = summary
        }
        if let linkedKnowledgePointIDs {
            let normalizedIDs = Array(Set(linkedKnowledgePointIDs)).sorted()
            card.linkedKnowledgePointIDs = normalizedIDs
            element = element.withMetadata { metadata in
                metadata.linkedKnowledgePointIDs = normalizedIDs
            }
        }
        element.knowledgeCardObject = card
        applyReplaceCanvasElement(element)
    }

    func updateImageObject(
        id: UUID,
        imageData: Data? = nil,
        remoteURL: String? = nil,
        caption: String? = nil
    ) {
        guard let element = canvasElement(with: id),
              var image = element.imageObject else { return }
        if let imageData {
            image.imageData = imageData
        }
        if let remoteURL {
            image.remoteURL = remoteURL
        }
        if let caption {
            image.caption = caption
        }
        var updated = element
        updated.imageObject = image
        updated.metadata.updatedAt = Date()
        applyReplaceCanvasElement(updated)
    }

    func reorderCanvasObject(id: UUID, toZIndex zIndex: Int) {
        guard let element = canvasElement(with: id) else { return }
        guard element.resolvedZIndex != zIndex else { return }
        historyController.perform(
            ReorderCanvasObjectAction(objectID: id, fromZIndex: element.resolvedZIndex, toZIndex: zIndex),
            in: self
        )
    }

    func updatePaperStyle(_ style: NotePaperStyle) {
        var next = paperConfiguration
        next.style = style
        historyController.perform(
            UpdatePaperConfigAction(from: paperConfiguration, to: next),
            in: self
        )
    }

    func updatePaperConfiguration(_ configuration: NotePaperConfiguration) {
        guard configuration != paperConfiguration else { return }
        historyController.perform(
            UpdatePaperConfigAction(from: paperConfiguration, to: configuration),
            in: self
        )
    }

    func linkKnowledgePoint(_ pointID: String, using appViewModel: AppViewModel, to blockID: UUID) {
        if let element = canvasElement(with: blockID) {
            var updated = element.withMetadata { metadata in
                if !metadata.linkedKnowledgePointIDs.contains(pointID) {
                    metadata.linkedKnowledgePointIDs.append(pointID)
                    metadata.linkedKnowledgePointIDs.sort()
                }
            }
            if var knowledgeCard = updated.knowledgeCardObject,
               !knowledgeCard.linkedKnowledgePointIDs.contains(pointID) {
                knowledgeCard.linkedKnowledgePointIDs.append(pointID)
                knowledgeCard.linkedKnowledgePointIDs.sort()
                updated.knowledgeCardObject = knowledgeCard
            }
            applyReplaceCanvasElement(updated)
        } else if let blockIndex = blocks.firstIndex(where: { $0.id == blockID }) {
            if !blocks[blockIndex].linkedKnowledgePointIDs.contains(pointID) {
                blocks[blockIndex].linkedKnowledgePointIDs.append(pointID)
                blocks[blockIndex].linkedKnowledgePointIDs.sort()
                blocks[blockIndex].updatedAt = Date()
            }
        } else {
            return
        }

        if let point = appViewModel.knowledgePoint(with: pointID),
           !note.knowledgePoints.contains(where: { $0.id == point.id }) {
            note.knowledgePoints.append(point)
        }

        linkedKnowledgePoints = appViewModel.linkedKnowledgePoints(
            for: allLinkedKnowledgePointIDs
        )
        markDirty()
    }

    func sourceAnchor(for block: NoteBlock) -> SourceAnchor {
        if let linkedAnchorID = block.linkedSourceAnchorID,
           let resolved = linkedSourceAnchor(with: linkedAnchorID) {
            return resolved
        }

        return note.sourceAnchor
    }

    func focus(on nodeID: String?) {
        selectedOutlineNodeID = nodeID
        highlightedBlockID = relatedBlockID(for: nodeID)
    }

    func clearHighlight() {
        highlightedBlockID = nil
    }

    @discardableResult
    func save(using appViewModel: AppViewModel) -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        autosaveTask?.cancel()
        defer { isSaving = false }

        note = persistableNoteSnapshot()

        if let saved = appViewModel.persistWorkspaceNote(note) {
            note = saved
            title = saved.title
            blocks = saved.blocks
            textObjects = saved.textObjects
            lastSavedAt = saved.updatedAt
            linkedKnowledgePoints = appViewModel.linkedKnowledgePoints(for: saved.linkedKnowledgePointIDs)
            isDirty = false
            viewportController.update(
                zoomScale: saved.document?.viewport.zoomScale ?? viewportController.state.zoomScale,
                contentOffset: saved.document?.viewport.contentOffset ?? viewportController.state.contentOffset,
                visibleRect: saved.document?.viewport.visibleRect ?? viewportController.state.visibleRect,
                fitMode: saved.document?.viewport.fitMode
            )
            historyController.markSaved()
            return true
        }

        return false
    }

    func scheduleAutosave(
        using appViewModel: AppViewModel,
        bridge: InkActionBridge? = nil,
        delayNanoseconds: UInt64 = 1_200_000_000
    ) {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled, let self else { return }
            if let bridge {
                self.syncInkFromBridge(bridge)
            }
            guard self.isDirty else { return }
            _ = self.save(using: appViewModel)
        }
    }

    func syncCanvasTool(workspaceTool: WorkspaceTool, inkState: NoteInkToolState) {
        toolController.sync(workspaceTool: workspaceTool, inkState: inkState)
        let gesturePolicy: CanvasViewportGesturePolicy
        switch workspaceTool {
        case .text:
            gesturePolicy = .textEditing
        case .select:
            gesturePolicy = .selectionAware
        case .pen, .pencil, .ballpoint, .highlighter, .eraser:
            gesturePolicy = .standard
        }
        viewportController.updateGesturePolicy(gesturePolicy)
    }

    func syncCanvasSelection(_ selection: EditorSelection) {
        selectionController.sync(from: selection, objects: canvasObjectElements)
    }

    func selectCanvasObject(id: UUID, additive: Bool = false) {
        guard let element = canvasElement(with: id) else { return }
        selectionController.selectObject(element, additive: additive)
    }

    func clearCanvasSelection() {
        selectionController.clear()
    }

    func updateCanvasSelectionPreview(_ rect: CGRect?) {
        selectionController.updateSelectionBounds(rect)
    }

    func beginCanvasInteraction(handle: CanvasTransformHandle?, mode: CanvasInteractionMode) {
        selectionController.beginInteraction(mode, handle: handle)
    }

    func endCanvasInteraction() {
        selectionController.endInteraction()
    }

    var documentSnapshot: NoteDocument {
        NoteDocument.derived(
            noteID: note.id,
            title: normalizedTitle,
            sourceAnchor: sourceAnchor,
            blocks: normalizedBlocks,
            textObjects: normalizedTextObjects,
            objectElements: normalizedCanvasObjectElements,
            baseDocument: note.document,
            createdAt: note.createdAt,
            updatedAt: Date(),
            viewport: viewportController.state
        )
    }

    func persistableNoteSnapshot() -> Note {
        var snapshot = note
        snapshot.title = normalizedTitle
        snapshot.blocks = normalizedBlocks
        snapshot.textObjects = normalizedTextObjects
        snapshot.document = documentSnapshot
        snapshot.updatedAt = Date()
        return snapshot
    }

    private var normalizedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? note.title : trimmed
    }

    private var normalizedBlocks: [NoteBlock] {
        blocks.filter { block in
            switch block.kind {
            case .quote:
                return !(block.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            case .text:
                return !(block.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    || !(block.inkData?.isEmpty ?? true)
            case .ink:
                return !(block.inkData?.isEmpty ?? true)
            }
        }
    }

    /// Filters out text objects that the user left completely empty.
    private var normalizedTextObjects: [CanvasTextObject] {
        textObjects.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var normalizedCanvasObjectElements: [CanvasElement] {
        canvasObjectElements.filter { element in
            switch element.kind {
            case .textObject:
                return !(element.textObject?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            case .quoteObject:
                return !(element.quoteObject?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            case .imageObject, .knowledgeCardObject, .linkPreviewObject, .inkStroke, .inkSelectionObject:
                return true
            }
        }
    }

    private var allLinkedKnowledgePointIDs: [String] {
        Array(
            Set(
                note.knowledgePoints.map(\.id) +
                blocks.flatMap(\.linkedKnowledgePointIDs) +
                canvasObjectElements.flatMap(\.metadata.linkedKnowledgePointIDs) +
                canvasObjectElements.compactMap(\.knowledgeCardObject).flatMap(\.linkedKnowledgePointIDs)
            )
        )
        .sorted()
    }

    private func relatedBlockID(for nodeID: String?) -> UUID? {
        guard let nodeID else {
            return blocks.first?.id
        }

        if let sentenceID = structuredSource?.outlineNode(id: nodeID)?.primarySentenceID,
           sentenceID == note.sourceAnchor.sentenceID,
           let quoteBlock = blocks.first(where: { $0.kind == .quote }) {
            return quoteBlock.id
        }

        if let quoteBlock = blocks.first(where: { $0.kind == .quote }) {
            return quoteBlock.id
        }

        return blocks.first?.id
    }

    fileprivate func markDirty() {
        if !isDirty { isDirty = true }
    }

    fileprivate func canvasElement(with id: UUID) -> CanvasElement? {
        canvasObjectElements.first { $0.id == id }
    }

    fileprivate func applyUpsertCanvasElement(_ element: CanvasElement) {
        let normalized = normalizedCanvasElement(element)
        if let idx = canvasObjectElements.firstIndex(where: { $0.id == normalized.id }) {
            canvasObjectElements[idx] = normalized
        } else {
            canvasObjectElements.append(normalized)
        }
        canvasObjectElements.sort { lhs, rhs in
            if lhs.resolvedZIndex != rhs.resolvedZIndex {
                return lhs.resolvedZIndex < rhs.resolvedZIndex
            }
            return lhs.metadata.createdAt < rhs.metadata.createdAt
        }
        syncLegacyContentFromCanvasElements()
        selectionController.refreshSelection(from: canvasObjectElements)
        markDirty()
    }

    fileprivate func applyReplaceCanvasElement(_ element: CanvasElement) {
        guard canvasElement(with: element.id) != nil else {
            applyUpsertCanvasElement(element)
            return
        }
        applyUpsertCanvasElement(element)
    }

    fileprivate func applyDeleteCanvasElement(id: UUID) {
        let beforeCount = canvasObjectElements.count
        canvasObjectElements.removeAll { $0.id == id }
        guard canvasObjectElements.count != beforeCount else { return }
        if highlightedBlockID == id {
            highlightedBlockID = nil
        }
        if editingTextBlockID == id {
            editingTextBlockID = nil
        }
        syncLegacyContentFromCanvasElements()
        selectionController.refreshSelection(from: canvasObjectElements)
        markDirty()
    }

    fileprivate func applyCanvasElementFrame(id: UUID, frame: CGRect) {
        guard let element = canvasElement(with: id) else { return }
        applyReplaceCanvasElement(element.withFrame(frame))
    }

    fileprivate func applyCanvasElementZIndex(id: UUID, zIndex: Int) {
        guard let element = canvasElement(with: id) else { return }
        let updated = element.withMetadata { metadata in
            metadata.zIndex = zIndex
        }
        applyReplaceCanvasElement(updated)
    }

    fileprivate func applyInsertTextObject(_ object: CanvasTextObject) {
        if let idx = textObjects.firstIndex(where: { $0.id == object.id }) {
            textObjects[idx] = object
        } else {
            textObjects.append(object)
            textObjects.sort { $0.zIndex < $1.zIndex }
        }
        markDirty()
    }

    fileprivate func applyReplaceTextObject(_ object: CanvasTextObject) {
        guard let idx = textObjects.firstIndex(where: { $0.id == object.id }) else { return }
        textObjects[idx] = object
        markDirty()
    }

    fileprivate func applyDeleteTextObject(id: UUID) {
        textObjects.removeAll { $0.id == id }
        markDirty()
    }

    fileprivate func applyTextObjectFrame(id: UUID, origin: CGPoint?, size: CGSize?) {
        guard let idx = textObjects.firstIndex(where: { $0.id == id }) else { return }
        if let origin {
            textObjects[idx].x = origin.x
            textObjects[idx].y = origin.y
        }
        if let size {
            textObjects[idx].width = max(size.width, textObjects[idx].minWidth)
            textObjects[idx].height = max(size.height, textObjects[idx].minHeight)
        }
        textObjects[idx].updatedAt = Date()
        markDirty()
    }

    fileprivate func applyInkBlockState(_ block: NoteBlock?) {
        if let idx = blocks.firstIndex(where: { $0.kind == .ink }) {
            if let block {
                blocks[idx] = block
            } else {
                blocks.remove(at: idx)
            }
        } else if let block {
            blocks.append(block)
        }
        markDirty()
    }

    fileprivate func applyPaperConfiguration(_ configuration: NotePaperConfiguration) {
        var document = note.document ?? note.resolvedDocument
        document.paper = configuration
        if var primaryPage = document.primaryPage {
            primaryPage.paper = configuration
            primaryPage.size = configuration.size
            document.pages = [primaryPage]
        }
        note.document = document
        viewportController.updatePageInsets(configuration.marginInsets)
        markDirty()
    }

    private func normalizedCanvasElement(_ element: CanvasElement) -> CanvasElement {
        element.withMetadata { metadata in
            if metadata.pageID == nil {
                metadata.pageID = resolvedPageID
            }
            if metadata.layerID == nil {
                metadata.layerID = resolvedObjectLayerID
            }
        }
    }

    private func syncLegacyContentFromCanvasElements() {
        let sortedElements = canvasObjectElements
            .filter(\.isVisibleObject)
            .sorted { lhs, rhs in
                if lhs.resolvedZIndex != rhs.resolvedZIndex {
                    return lhs.resolvedZIndex < rhs.resolvedZIndex
                }
                return lhs.metadata.createdAt < rhs.metadata.createdAt
            }

        let legacyFlowBlocks = sortedElements.compactMap(noteBlock(from:))
        let inkBlocks = blocks.filter { $0.kind == .ink }
        blocks = legacyFlowBlocks + inkBlocks

        textObjects = sortedElements.compactMap(floatingTextObject(from:))

        if let editingTextBlockID, !blocks.contains(where: { $0.id == editingTextBlockID }) {
            self.editingTextBlockID = nil
        }

        note.blocks = blocks
        note.textObjects = textObjects
    }

    private func noteBlock(from element: CanvasElement) -> NoteBlock? {
        guard element.isFlowObject else { return nil }

        switch element.kind {
        case .textObject:
            guard let payload = element.textObject else { return nil }
            let trimmed = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return NoteBlock(
                id: element.id,
                kind: .text,
                text: trimmed,
                linkedSourceAnchorID: element.metadata.sourceAnchorID,
                linkedKnowledgePointIDs: element.metadata.linkedKnowledgePointIDs,
                createdAt: element.metadata.createdAt,
                updatedAt: element.metadata.updatedAt,
                textStyle: payload.textStyle,
                textColor: payload.textColor,
                highlightStyle: payload.highlightStyle,
                fontSizePreset: payload.fontSizePreset
            )
        case .quoteObject:
            guard let payload = element.quoteObject else { return nil }
            let trimmed = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return NoteBlock(
                id: element.id,
                kind: .quote,
                text: trimmed,
                linkedSourceAnchorID: payload.sourceAnchorID ?? element.metadata.sourceAnchorID,
                linkedKnowledgePointIDs: element.metadata.linkedKnowledgePointIDs,
                createdAt: element.metadata.createdAt,
                updatedAt: element.metadata.updatedAt,
                textStyle: payload.textStyle,
                textColor: payload.textColor,
                highlightStyle: payload.highlightStyle,
                fontSizePreset: payload.fontSizePreset
            )
        case .imageObject, .knowledgeCardObject, .linkPreviewObject, .inkStroke, .inkSelectionObject:
            return nil
        }
    }

    private func floatingTextObject(from element: CanvasElement) -> CanvasTextObject? {
        guard element.kind == .textObject, element.isFloatingObject, let payload = element.textObject else {
            return nil
        }

        var object = payload
        object.x = element.effectiveFrame.origin.x
        object.y = element.effectiveFrame.origin.y
        object.width = element.effectiveFrame.width
        object.height = element.effectiveFrame.height
        object.rotation = element.rotation
        object.zIndex = element.resolvedZIndex
        object.pageID = element.metadata.pageID
        object.layerID = element.metadata.layerID
        object.isLocked = element.metadata.isLocked
        object.isHidden = !element.metadata.isVisible
        object.updatedAt = element.metadata.updatedAt
        return object
    }

    private func linkedSourceAnchor(with id: String) -> SourceAnchor? {
        if note.sourceAnchor.id == id {
            return note.sourceAnchor
        }

        return linkedKnowledgePoints
            .flatMap(\.sourceAnchors)
            .first(where: { $0.id == id })
            ?? note.knowledgePoints
            .flatMap(\.sourceAnchors)
            .first(where: { $0.id == id })
    }

    private func rebuildOutlineContext() {
        guard let structuredSource else {
            outlineContext = WorkspaceOutlineContext(
                currentNode: nil,
                pathNodes: [],
                nearbyNodes: []
            )
            return
        }

        let currentNode = structuredSource.outlineNode(id: selectedOutlineNodeID)
            ?? structuredSource.bestOutlineNode(forSentenceID: sourceAnchor.sentenceID)
            ?? structuredSource.outlineNode(id: sourceAnchor.outlineNodeID)

        let pathIDs = Set(
            structuredSource.ancestorNodeIDs(for: currentNode?.id) + [currentNode?.id].compactMap { $0 }
        )
        let flattened = structuredSource.flattenedOutlineNodes()
        let pathNodes = flattened.filter { pathIDs.contains($0.id) }
            .sorted {
                if $0.depth != $1.depth {
                    return $0.depth < $1.depth
                }
                return $0.order < $1.order
            }

        let siblingNodes: [OutlineNode]
        if let currentNode {
            siblingNodes = flattened.filter {
                $0.parentID == currentNode.parentID && $0.id != currentNode.id
            }
            .sorted { $0.order < $1.order }
        } else {
            siblingNodes = Array(flattened.prefix(5))
        }

        let children = currentNode?.children.sorted { $0.order < $1.order } ?? []
        let nearby = Array(siblingNodes.prefix(2)) + Array(children.prefix(4))

        outlineContext = WorkspaceOutlineContext(
            currentNode: currentNode,
            pathNodes: pathNodes,
            nearbyNodes: nearby
        )
    }
}
