import Foundation

// MARK: - Knowledge Chunk Model
/// Represents a knowledge block extracted from a source document
/// This is the smallest trainable unit from raw materials
public struct KnowledgeChunk: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var content: String
    public var sourceDocumentID: UUID
    public var startPosition: Int? // Page number or position in original doc
    public var endPosition: Int?
    public var sourceLocator: String?
    public var tags: [String]
    public var candidateKnowledgePoints: [String]
    public var manualAdjusted: Bool // Whether user manually adjusted this chunk
    public var createdAt: Date
    
    public init(
        id: UUID = UUID(),
        title: String,
        content: String,
        sourceDocumentID: UUID,
        startPosition: Int? = nil,
        endPosition: Int? = nil,
        sourceLocator: String? = nil,
        tags: [String] = [],
        candidateKnowledgePoints: [String] = [],
        manualAdjusted: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.sourceDocumentID = sourceDocumentID
        self.startPosition = startPosition
        self.endPosition = endPosition
        self.sourceLocator = sourceLocator
        self.tags = tags
        self.candidateKnowledgePoints = candidateKnowledgePoints
        self.manualAdjusted = manualAdjusted
        self.createdAt = createdAt
    }
}
