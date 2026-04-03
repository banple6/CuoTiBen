import Foundation

@MainActor
final class NotesFlowCoordinator {
    private let noteRepository: any NoteRepositoryProtocol
    private let sourceRepository: any SourceRepositoryProtocol
    private let knowledgePointRepository: any KnowledgePointRepositoryProtocol
    private let contextProvider: any LearningRecordContextProviding
    private let createNoteFromSentenceUseCase: CreateNoteFromSentenceUseCase
    private let createNoteFromWordUseCase: CreateNoteFromWordUseCase
    private let appendNoteBlockUseCase: AppendNoteBlockUseCase
    private let linkKnowledgePointToNoteUseCase: LinkKnowledgePointToNoteUseCase
    private let extractionService: any KnowledgePointExtractionServiceProtocol
    private let onNotesChanged: @MainActor ([Note]) -> Void

    init(
        noteRepository: any NoteRepositoryProtocol,
        sourceRepository: any SourceRepositoryProtocol,
        knowledgePointRepository: any KnowledgePointRepositoryProtocol,
        contextProvider: any LearningRecordContextProviding,
        createNoteFromSentenceUseCase: CreateNoteFromSentenceUseCase,
        createNoteFromWordUseCase: CreateNoteFromWordUseCase,
        appendNoteBlockUseCase: AppendNoteBlockUseCase,
        linkKnowledgePointToNoteUseCase: LinkKnowledgePointToNoteUseCase,
        extractionService: any KnowledgePointExtractionServiceProtocol,
        onNotesChanged: @escaping @MainActor ([Note]) -> Void
    ) {
        self.noteRepository = noteRepository
        self.sourceRepository = sourceRepository
        self.knowledgePointRepository = knowledgePointRepository
        self.contextProvider = contextProvider
        self.createNoteFromSentenceUseCase = createNoteFromSentenceUseCase
        self.createNoteFromWordUseCase = createNoteFromWordUseCase
        self.appendNoteBlockUseCase = appendNoteBlockUseCase
        self.linkKnowledgePointToNoteUseCase = linkKnowledgePointToNoteUseCase
        self.extractionService = extractionService
        self.onNotesChanged = onNotesChanged
    }

    func note(with id: UUID) -> Note? {
        try? noteRepository.fetchAllNotes().first { $0.id == id }
    }

    func sourceDocument(for note: Note) -> SourceDocument? {
        sourceRepository.sourceDocument(for: note.sourceAnchor)
    }

    func linkedKnowledgePoints(for note: Note) -> [KnowledgePoint] {
        let explicitPoints = note.knowledgePoints
        let resolvedPoints = knowledgePointRepository.linkedKnowledgePoints(for: note.linkedKnowledgePointIDs)
        return extractionService.merge(points: explicitPoints + resolvedPoints)
    }

    func context(for note: Note) -> LearningRecordContext {
        contextProvider.context(forNoteID: note.id)
    }

    func createOrUpdateSentenceNote(_ request: NoteDraftRequest) -> Note? {
        do {
            let note = try createNoteFromSentenceUseCase.execute(request)
            let notes = try noteRepository.fetchAllNotes()
            onNotesChanged(notes)
            return note
        } catch {
            print("[NotesFlowCoordinator] create/update sentence note failed: \(error.localizedDescription)")
            return nil
        }
    }

    func createOrUpdateWordNote(_ request: NoteDraftRequest) -> Note? {
        do {
            let note = try createNoteFromWordUseCase.execute(request)
            let notes = try noteRepository.fetchAllNotes()
            onNotesChanged(notes)
            return note
        } catch {
            print("[NotesFlowCoordinator] create/update word note failed: \(error.localizedDescription)")
            return nil
        }
    }

    func appendBlocks(_ request: NoteAppendRequest) -> Note? {
        do {
            let note = try appendNoteBlockUseCase.execute(request)
            let notes = try noteRepository.fetchAllNotes()
            onNotesChanged(notes)
            return note
        } catch {
            print("[NotesFlowCoordinator] append note blocks failed: \(error.localizedDescription)")
            return nil
        }
    }

    func persistWorkspaceNote(_ note: Note) -> Note? {
        var updated = note
        updated.knowledgePoints = extractionService.merge(
            points: updated.knowledgePoints + knowledgePointRepository.linkedKnowledgePoints(for: updated.linkedKnowledgePointIDs)
        )
        updated.updatedAt = Date()

        do {
            try noteRepository.updateNote(updated)
            let notes = try noteRepository.fetchAllNotes()
            onNotesChanged(notes)
            return updated
        } catch {
            print("[NotesFlowCoordinator] persist workspace note failed: \(error.localizedDescription)")
            return nil
        }
    }

    func linkKnowledgePoint(_ pointID: String, to note: Note, blockID: UUID? = nil) -> Note {
        linkKnowledgePointToNoteUseCase.execute(note: note, knowledgePointID: pointID, blockID: blockID)
    }
}

@MainActor
final class SourceLearningCoordinator: WorkspaceActionDispatcher {
    private let sourceRepository: any SourceRepositoryProtocol
    private let knowledgePointRepository: any KnowledgePointRepositoryProtocol
    private let contextProvider: any LearningRecordContextProviding
    private let sourceJumpRouter: any SourceJumpRouting

    init(
        sourceRepository: any SourceRepositoryProtocol,
        knowledgePointRepository: any KnowledgePointRepositoryProtocol,
        contextProvider: any LearningRecordContextProviding,
        sourceJumpRouter: any SourceJumpRouting
    ) {
        self.sourceRepository = sourceRepository
        self.knowledgePointRepository = knowledgePointRepository
        self.contextProvider = contextProvider
        self.sourceJumpRouter = sourceJumpRouter
    }

    func route(for anchor: SourceAnchor) -> WorkspaceRoute? {
        sourceJumpRouter.target(for: anchor).map(WorkspaceRoute.sourceJump)
    }

    func route(for note: Note) -> WorkspaceRoute? {
        sourceJumpRouter.target(for: note).map(WorkspaceRoute.sourceJump)
    }

    func route(for knowledgePoint: KnowledgePoint, preferredSourceID: UUID? = nil) -> WorkspaceRoute? {
        sourceJumpRouter.target(for: knowledgePoint, preferredSourceID: preferredSourceID)
            .map(WorkspaceRoute.sourceJump)
    }

    func context(for note: Note) -> WorkspaceContext {
        let anchor = note.sourceAnchor
        return WorkspaceContext(
            sourceDocument: sourceRepository.sourceDocument(for: anchor),
            structuredSource: sourceRepository.noteSourceBundle(for: note),
            note: note,
            sourceAnchor: anchor,
            sentence: sourceRepository.sentence(for: anchor),
            outlineNode: sourceRepository.outlineNode(for: anchor),
            knowledgePoint: note.knowledgePoints.first,
            learningRecordContext: contextProvider.context(forNoteID: note.id)
        )
    }

    func context(for anchor: SourceAnchor) -> WorkspaceContext {
        let sentence = sourceRepository.sentence(for: anchor)
        let context: LearningRecordContext?
        if let sentenceID = anchor.sentenceID {
            context = contextProvider.context(forSentenceID: sentenceID)
        } else if let outlineNodeID = anchor.outlineNodeID {
            context = contextProvider.context(forKnowledgePointID: outlineNodeID)
        } else {
            context = nil
        }

        return WorkspaceContext(
            sourceDocument: sourceRepository.sourceDocument(for: anchor),
            structuredSource: sourceRepository.structuredSource(for: anchor.sourceID),
            note: nil,
            sourceAnchor: anchor,
            sentence: sentence,
            outlineNode: sourceRepository.outlineNode(for: anchor),
            knowledgePoint: nil,
            learningRecordContext: context
        )
    }

    func linkedKnowledgePoints(for ids: [String]) -> [KnowledgePoint] {
        knowledgePointRepository.linkedKnowledgePoints(for: ids)
    }

    func knowledgePoint(with id: String) -> KnowledgePoint? {
        knowledgePointRepository.knowledgePoint(with: id)
    }
}

@MainActor
final class ReviewFlowCoordinator {
    private let reviewRepository: any ReviewRepositoryProtocol
    private let sourceRepository: any SourceRepositoryProtocol

    init(
        reviewRepository: any ReviewRepositoryProtocol,
        sourceRepository: any SourceRepositoryProtocol
    ) {
        self.reviewRepository = reviewRepository
        self.sourceRepository = sourceRepository
    }

    func generateCard(for note: Note) -> Card? {
        guard let document = sourceRepository.sourceDocument(for: note.sourceAnchor) else {
            return nil
        }

        if let sentence = sourceRepository.sentence(for: note.sourceAnchor) {
            return reviewRepository.addSentenceCard(for: sentence, explanation: nil, in: document)
        }

        if let node = sourceRepository.outlineNode(for: note.sourceAnchor) {
            return reviewRepository.addNodeCard(for: node, in: document)
        }

        return nil
    }
}
