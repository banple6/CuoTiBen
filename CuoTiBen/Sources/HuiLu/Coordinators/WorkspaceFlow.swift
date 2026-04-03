import Foundation

struct WorkspaceContext {
    var sourceDocument: SourceDocument?
    var structuredSource: StructuredSourceBundle?
    var note: Note?
    var sourceAnchor: SourceAnchor?
    var sentence: Sentence?
    var outlineNode: OutlineNode?
    var knowledgePoint: KnowledgePoint?
    var learningRecordContext: LearningRecordContext?

    static let empty = WorkspaceContext()
}

enum WorkspaceRoute: Equatable {
    case sourceJump(SourceJumpTarget)
    case noteDetail(UUID)
    case noteWorkspace(UUID)
    case knowledgePoint(String)
    case review(SourceJumpTarget)
}

@MainActor
protocol WorkspaceActionDispatcher: AnyObject {
    func route(for anchor: SourceAnchor) -> WorkspaceRoute?
    func route(for note: Note) -> WorkspaceRoute?
    func route(for knowledgePoint: KnowledgePoint, preferredSourceID: UUID?) -> WorkspaceRoute?
    func context(for note: Note) -> WorkspaceContext
    func context(for anchor: SourceAnchor) -> WorkspaceContext
}
