import Foundation

@MainActor
final class DependencyContainer {
    let noteRepository: any NoteRepositoryProtocol
    let sourceRepository: any SourceRepositoryProtocol
    let knowledgePointRepository: any KnowledgePointRepositoryProtocol
    let reviewRepository: any ReviewRepositoryProtocol

    let knowledgePointExtractionService: any KnowledgePointExtractionServiceProtocol
    let learningRecordContextProvider: any LearningRecordContextProviding
    let sourceJumpRouter: any SourceJumpRouting

    let createNoteFromSentenceUseCase: CreateNoteFromSentenceUseCase
    let createNoteFromWordUseCase: CreateNoteFromWordUseCase
    let appendNoteBlockUseCase: AppendNoteBlockUseCase
    let linkKnowledgePointToNoteUseCase: LinkKnowledgePointToNoteUseCase

    let notesFlowCoordinator: NotesFlowCoordinator
    let sourceLearningCoordinator: SourceLearningCoordinator
    let reviewFlowCoordinator: ReviewFlowCoordinator

    init(
        noteRepository: any NoteRepositoryProtocol,
        sourceRepository: any SourceRepositoryProtocol,
        knowledgePointRepository: any KnowledgePointRepositoryProtocol,
        reviewRepository: any ReviewRepositoryProtocol,
        knowledgePointExtractionService: any KnowledgePointExtractionServiceProtocol,
        learningRecordContextProvider: any LearningRecordContextProviding,
        sourceJumpRouter: any SourceJumpRouting,
        onNotesChanged: @escaping @MainActor ([Note]) -> Void
    ) {
        self.noteRepository = noteRepository
        self.sourceRepository = sourceRepository
        self.knowledgePointRepository = knowledgePointRepository
        self.reviewRepository = reviewRepository
        self.knowledgePointExtractionService = knowledgePointExtractionService
        self.learningRecordContextProvider = learningRecordContextProvider
        self.sourceJumpRouter = sourceJumpRouter

        let createNoteFromSentenceUseCase = CreateNoteFromSentenceUseCase(
            noteRepository: noteRepository,
            knowledgePointRepository: knowledgePointRepository,
            extractionService: knowledgePointExtractionService
        )
        let createNoteFromWordUseCase = CreateNoteFromWordUseCase(baseUseCase: createNoteFromSentenceUseCase)
        let appendNoteBlockUseCase = AppendNoteBlockUseCase(
            noteRepository: noteRepository,
            knowledgePointRepository: knowledgePointRepository,
            extractionService: knowledgePointExtractionService
        )
        let linkKnowledgePointToNoteUseCase = LinkKnowledgePointToNoteUseCase(
            knowledgePointRepository: knowledgePointRepository,
            extractionService: knowledgePointExtractionService
        )

        self.createNoteFromSentenceUseCase = createNoteFromSentenceUseCase
        self.createNoteFromWordUseCase = createNoteFromWordUseCase
        self.appendNoteBlockUseCase = appendNoteBlockUseCase
        self.linkKnowledgePointToNoteUseCase = linkKnowledgePointToNoteUseCase

        self.notesFlowCoordinator = NotesFlowCoordinator(
            noteRepository: noteRepository,
            sourceRepository: sourceRepository,
            knowledgePointRepository: knowledgePointRepository,
            contextProvider: learningRecordContextProvider,
            createNoteFromSentenceUseCase: createNoteFromSentenceUseCase,
            createNoteFromWordUseCase: createNoteFromWordUseCase,
            appendNoteBlockUseCase: appendNoteBlockUseCase,
            linkKnowledgePointToNoteUseCase: linkKnowledgePointToNoteUseCase,
            extractionService: knowledgePointExtractionService,
            onNotesChanged: onNotesChanged
        )
        self.sourceLearningCoordinator = SourceLearningCoordinator(
            sourceRepository: sourceRepository,
            knowledgePointRepository: knowledgePointRepository,
            contextProvider: learningRecordContextProvider,
            sourceJumpRouter: sourceJumpRouter
        )
        self.reviewFlowCoordinator = ReviewFlowCoordinator(
            reviewRepository: reviewRepository,
            sourceRepository: sourceRepository
        )
    }
}
