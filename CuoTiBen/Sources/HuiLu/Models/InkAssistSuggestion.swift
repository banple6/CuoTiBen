import Foundation
import CoreGraphics

struct InkAssistSuggestion: Identifiable, Equatable, Hashable {
    let id: UUID
    let blockID: UUID
    let sourceAnchorID: String?
    let matchedKnowledgePointID: String
    let matchedKnowledgePointTitle: String
    let recognizedText: String
    let recognitionConfidence: Double
    let score: Double
    let normalizedAnchorRect: CGRect
    let createdAt: Date
    let expiresAt: Date

    init(
        id: UUID = UUID(),
        blockID: UUID,
        sourceAnchorID: String?,
        matchedKnowledgePointID: String,
        matchedKnowledgePointTitle: String,
        recognizedText: String,
        recognitionConfidence: Double,
        score: Double,
        normalizedAnchorRect: CGRect,
        createdAt: Date = Date(),
        expiresAt: Date = Date().addingTimeInterval(2.5)
    ) {
        self.id = id
        self.blockID = blockID
        self.sourceAnchorID = sourceAnchorID
        self.matchedKnowledgePointID = matchedKnowledgePointID
        self.matchedKnowledgePointTitle = matchedKnowledgePointTitle
        self.recognizedText = recognizedText
        self.recognitionConfidence = recognitionConfidence
        self.score = score
        self.normalizedAnchorRect = normalizedAnchorRect
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}
