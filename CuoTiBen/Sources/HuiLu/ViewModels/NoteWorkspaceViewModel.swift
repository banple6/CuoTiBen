import Foundation
import Combine

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
    @Published var selectedOutlineNodeID: String? {
        didSet {
            rebuildOutlineContext()
        }
    }
    @Published var highlightedBlockID: UUID?
    @Published var panelState: NoteOutlineFloatingPanelState = .hidden
    @Published var panelMode: NoteOutlineFloatingPanelMode = .structure
    @Published var isDirty = false
    @Published var isSaving = false
    @Published var lastSavedAt: Date?

    init(note: Note) {
        self.note = note
        self.title = note.title
        self.blocks = note.blocks
        self.selectedOutlineNodeID = note.sourceAnchor.outlineNodeID
        self.outlineContext = WorkspaceOutlineContext(
            currentNode: nil,
            pathNodes: [],
            nearbyNodes: []
        )
        self.lastSavedAt = note.updatedAt
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

    func reload(using appViewModel: AppViewModel) {
        if let refreshed = appViewModel.note(with: note.id) {
            note = refreshed
            title = refreshed.title
            blocks = refreshed.blocks
            lastSavedAt = refreshed.updatedAt
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

    func addTextBlock() {
        blocks.append(NoteBlock(kind: .text, text: ""))
        highlightedBlockID = blocks.last?.id
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
        blocks.append(
            NoteBlock(
                kind: .quote,
                text: text,
                linkedSourceAnchorID: note.sourceAnchor.id
            )
        )
        highlightedBlockID = blocks.last?.id
        markDirty()
    }

    func linkKnowledgePoint(_ pointID: String, using appViewModel: AppViewModel, to blockID: UUID) {
        guard let blockIndex = blocks.firstIndex(where: { $0.id == blockID }) else { return }

        if !blocks[blockIndex].linkedKnowledgePointIDs.contains(pointID) {
            blocks[blockIndex].linkedKnowledgePointIDs.append(pointID)
            blocks[blockIndex].updatedAt = Date()
        }

        if let point = appViewModel.knowledgePoint(with: pointID),
           !note.knowledgePoints.contains(where: { $0.id == point.id }) {
            note.knowledgePoints.append(point)
        }

        linkedKnowledgePoints = appViewModel.linkedKnowledgePoints(
            for: Array(Set(note.linkedKnowledgePointIDs + blocks.flatMap(\.linkedKnowledgePointIDs))).sorted()
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
        defer { isSaving = false }

        note.title = normalizedTitle
        note.blocks = normalizedBlocks
        note.updatedAt = Date()

        if let saved = appViewModel.persistWorkspaceNote(note) {
            note = saved
            title = saved.title
            blocks = saved.blocks
            lastSavedAt = saved.updatedAt
            linkedKnowledgePoints = appViewModel.linkedKnowledgePoints(for: saved.linkedKnowledgePointIDs)
            isDirty = false
            return true
        }

        return false
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

    private func markDirty() {
        isDirty = true
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
