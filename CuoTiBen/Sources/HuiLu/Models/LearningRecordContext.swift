import Foundation

enum LearningRecordEntryPoint: Equatable, Hashable {
    case sentence(sentenceID: String)
    case word(term: String, lemma: String?, sentenceID: String)
    case note(noteID: UUID)
    case knowledgePoint(knowledgePointID: String)
}

struct LearningRecordSentenceItem: Identifiable, Equatable {
    let sentence: Sentence
    let anchor: SourceAnchor
    let sourceDocumentID: UUID
    let sourceTitle: String

    var id: String { sentence.id }
}

struct LearningRecordCardItem: Identifiable, Equatable {
    let card: Card
    let sourceDocumentID: UUID?
    let sourceTitle: String
    let chunkTitle: String
    let chunkSummary: String
    let anchorLabel: String?
    let sourceAnchor: SourceAnchor?

    var id: UUID { card.id }
}

struct LearningRecordContext: Equatable {
    let entryPoint: LearningRecordEntryPoint
    let primarySentence: Sentence?
    let primaryNote: Note?
    let primaryKnowledgePoint: KnowledgePoint?
    let primarySourceAnchor: SourceAnchor?
    let relatedNotes: [Note]
    let relatedKnowledgePoints: [KnowledgePoint]
    let relatedSentences: [LearningRecordSentenceItem]
    let relatedCards: [LearningRecordCardItem]
    let relatedSourceAnchors: [SourceAnchor]

    static func empty(for entryPoint: LearningRecordEntryPoint) -> LearningRecordContext {
        LearningRecordContext(
            entryPoint: entryPoint,
            primarySentence: nil,
            primaryNote: nil,
            primaryKnowledgePoint: nil,
            primarySourceAnchor: nil,
            relatedNotes: [],
            relatedKnowledgePoints: [],
            relatedSentences: [],
            relatedCards: [],
            relatedSourceAnchors: []
        )
    }

    var isEmpty: Bool {
        relatedNotes.isEmpty &&
        relatedKnowledgePoints.isEmpty &&
        relatedSentences.isEmpty &&
        relatedCards.isEmpty &&
        relatedSourceAnchors.isEmpty
    }
}
