import Foundation

@MainActor
protocol NoteRepositoryProtocol: AnyObject {
    @discardableResult
    func createNote(from sentence: Sentence, anchor: SourceAnchor) throws -> Note
    func updateNote(_ note: Note) throws
    func fetchAllNotes() throws -> [Note]
    func fetchNotes(for sourceID: UUID) throws -> [Note]
    func fetchNotes(for knowledgePointID: String) throws -> [Note]
    func deleteNote(_ note: Note) throws
}

@MainActor
protocol SourceRepositoryProtocol: AnyObject {
    func sourceDocument(with id: UUID) -> SourceDocument?
    func sourceDocument(for anchor: SourceAnchor) -> SourceDocument?
    func structuredSource(for sourceID: UUID) -> StructuredSourceBundle?
    func sentence(for anchor: SourceAnchor) -> Sentence?
    func outlineNode(for anchor: SourceAnchor) -> OutlineNode?
    func noteSourceBundle(for note: Note) -> StructuredSourceBundle?
}

@MainActor
protocol KnowledgePointRepositoryProtocol: AnyObject {
    func allKnowledgePoints() -> [KnowledgePoint]
    func linkedKnowledgePoints(for ids: [String]) -> [KnowledgePoint]
    func knowledgePoint(with id: String) -> KnowledgePoint?
    func relatedKnowledgePoints(for point: KnowledgePoint) -> [KnowledgePoint]
}

@MainActor
protocol ReviewRepositoryProtocol: AnyObject {
    @discardableResult
    func addSentenceCard(
        for sentence: Sentence,
        explanation: AIExplainSentenceResult?,
        in document: SourceDocument
    ) -> Card

    @discardableResult
    func addNodeCard(for node: OutlineNode, in document: SourceDocument) -> Card

    @discardableResult
    func addVocabularyCard(for entry: WordExplanationEntry, in document: SourceDocument) -> Card

    func generatedCards(for document: SourceDocument) -> [Card]
}

extension NoteRepository: NoteRepositoryProtocol {}
