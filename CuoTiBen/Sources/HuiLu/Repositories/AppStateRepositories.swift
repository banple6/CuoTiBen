import Foundation

@MainActor
protocol LearningRecordContextProviding: AnyObject {
    func context(forSentenceID sentenceID: String) -> LearningRecordContext
    func context(forWord word: String, lemma: String?, sentenceID: String) -> LearningRecordContext
    func context(forNoteID noteID: UUID) -> LearningRecordContext
    func context(forKnowledgePointID knowledgePointID: String) -> LearningRecordContext
}

@MainActor
protocol SourceJumpRouting: AnyObject {
    func target(for anchor: SourceAnchor) -> SourceJumpTarget?
    func target(for note: Note) -> SourceJumpTarget?
    func target(for knowledgePoint: KnowledgePoint, preferredSourceID: UUID?) -> SourceJumpTarget?
}

@MainActor
final class AppStateSourceRepository: SourceRepositoryProtocol {
    private weak var appViewModel: AppViewModel?

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
    }

    func sourceDocument(with id: UUID) -> SourceDocument? {
        appViewModel?.sourceDocument(with: id)
    }

    func sourceDocument(for anchor: SourceAnchor) -> SourceDocument? {
        appViewModel?.sourceDocument(for: anchor)
    }

    func structuredSource(for sourceID: UUID) -> StructuredSourceBundle? {
        appViewModel?.structuredSource(for: sourceID)
    }

    func sentence(for anchor: SourceAnchor) -> Sentence? {
        appViewModel?.sentence(for: anchor)
    }

    func outlineNode(for anchor: SourceAnchor) -> OutlineNode? {
        appViewModel?.outlineNode(for: anchor)
    }

    func noteSourceBundle(for note: Note) -> StructuredSourceBundle? {
        appViewModel?.noteSourceBundle(for: note)
    }
}

@MainActor
final class AppStateKnowledgePointRepository: KnowledgePointRepositoryProtocol {
    private weak var appViewModel: AppViewModel?

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
    }

    func allKnowledgePoints() -> [KnowledgePoint] {
        appViewModel?.allKnowledgePoints() ?? []
    }

    func linkedKnowledgePoints(for ids: [String]) -> [KnowledgePoint] {
        appViewModel?.linkedKnowledgePoints(for: ids) ?? []
    }

    func knowledgePoint(with id: String) -> KnowledgePoint? {
        appViewModel?.knowledgePoint(with: id)
    }

    func relatedKnowledgePoints(for point: KnowledgePoint) -> [KnowledgePoint] {
        appViewModel?.relatedKnowledgePoints(for: point) ?? []
    }
}

@MainActor
final class AppStateReviewRepository: ReviewRepositoryProtocol {
    private weak var appViewModel: AppViewModel?

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
    }

    func addSentenceCard(
        for sentence: Sentence,
        explanation: AIExplainSentenceResult?,
        in document: SourceDocument
    ) -> Card {
        guard let appViewModel else {
            let faithfulTranslation = explanation?.faithfulTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
            return Card(
                type: .questionAnswer,
                frontContent: sentence.text,
                backContent: (faithfulTranslation?.isEmpty == false ? faithfulTranslation : nil) ?? sentence.text,
                keywords: explanation?.keyTerms.map(\.term) ?? [],
                knowledgeChunkID: UUID(),
                difficultyLevel: 3,
                nextReviewAt: Date(),
                isDraft: true
            )
        }
        return appViewModel.addSentenceCard(for: sentence, explanation: explanation, in: document)
    }

    func addNodeCard(for node: OutlineNode, in document: SourceDocument) -> Card {
        guard let appViewModel else {
            return Card(
                type: .questionAnswer,
                frontContent: node.title,
                backContent: node.summary,
                keywords: [],
                knowledgeChunkID: UUID(),
                difficultyLevel: 3,
                nextReviewAt: Date(),
                isDraft: true
            )
        }
        return appViewModel.addNodeCard(for: node, in: document)
    }

    func addVocabularyCard(for entry: WordExplanationEntry, in document: SourceDocument) -> Card {
        guard let appViewModel else {
            return Card(
                type: .questionAnswer,
                frontContent: entry.term,
                backContent: entry.sentenceMeaning,
                keywords: [entry.term],
                knowledgeChunkID: UUID(),
                difficultyLevel: 2,
                nextReviewAt: Date(),
                isDraft: true
            )
        }
        return appViewModel.addVocabularyCard(for: entry, in: document)
    }

    func generatedCards(for document: SourceDocument) -> [Card] {
        appViewModel?.generatedCards(for: document) ?? []
    }
}

@MainActor
final class AppLearningRecordContextProvider: LearningRecordContextProviding {
    private weak var appViewModel: AppViewModel?

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
    }

    func context(forSentenceID sentenceID: String) -> LearningRecordContext {
        appViewModel?.learningRecordContext(forSentenceID: sentenceID)
            ?? .empty(for: .sentence(sentenceID: sentenceID))
    }

    func context(forWord word: String, lemma: String?, sentenceID: String) -> LearningRecordContext {
        appViewModel?.learningRecordContext(forWord: word, lemma: lemma, sentenceID: sentenceID)
            ?? .empty(for: .word(term: word, lemma: lemma, sentenceID: sentenceID))
    }

    func context(forNoteID noteID: UUID) -> LearningRecordContext {
        appViewModel?.learningRecordContext(forNoteID: noteID)
            ?? .empty(for: .note(noteID: noteID))
    }

    func context(forKnowledgePointID knowledgePointID: String) -> LearningRecordContext {
        appViewModel?.learningRecordContext(forKnowledgePointID: knowledgePointID)
            ?? .empty(for: .knowledgePoint(knowledgePointID: knowledgePointID))
    }
}

@MainActor
final class AppStateSourceJumpRouter: SourceJumpRouting {
    private weak var appViewModel: AppViewModel?

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
    }

    func target(for anchor: SourceAnchor) -> SourceJumpTarget? {
        appViewModel?.sourceJumpTarget(for: anchor)
    }

    func target(for note: Note) -> SourceJumpTarget? {
        appViewModel?.sourceJumpTarget(for: note)
    }

    func target(for knowledgePoint: KnowledgePoint, preferredSourceID: UUID?) -> SourceJumpTarget? {
        appViewModel?.sourceJumpTarget(for: knowledgePoint, preferredSourceID: preferredSourceID)
    }
}
