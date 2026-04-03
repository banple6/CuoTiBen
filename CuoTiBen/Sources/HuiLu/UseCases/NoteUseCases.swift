import Foundation

protocol KnowledgePointExtractionServiceProtocol: AnyObject {
    func extract(
        titles: [String],
        suggestedPoints: [KnowledgePoint],
        tags: [String],
        noteTitle: String,
        body: String,
        quote: String
    ) -> [KnowledgePoint]

    func merge(points: [KnowledgePoint]) -> [KnowledgePoint]
}

extension KnowledgePointExtractionService: KnowledgePointExtractionServiceProtocol {}

struct NoteDraftRequest {
    let existingNote: Note?
    let seed: NoteEditorSeed
    let title: String
    let body: String
    let tags: [String]
    let knowledgePointTitles: [String]
    let inkData: Data?
    let inkBlock: NoteBlock?
}

struct NoteAppendRequest {
    let note: Note
    let body: String
    let tags: [String]
    let knowledgePointTitles: [String]
    let inkData: Data?
    let inkBlock: NoteBlock?
}

@MainActor
struct CreateNoteFromSentenceUseCase {
    private let noteRepository: any NoteRepositoryProtocol
    private let knowledgePointRepository: any KnowledgePointRepositoryProtocol
    private let extractionService: any KnowledgePointExtractionServiceProtocol

    init(
        noteRepository: any NoteRepositoryProtocol,
        knowledgePointRepository: any KnowledgePointRepositoryProtocol,
        extractionService: any KnowledgePointExtractionServiceProtocol
    ) {
        self.noteRepository = noteRepository
        self.knowledgePointRepository = knowledgePointRepository
        self.extractionService = extractionService
    }

    func execute(_ request: NoteDraftRequest) throws -> Note {
        let normalizedTags = normalizedItems(from: request.tags)
        let resolvedTitle = request.title.nonEmpty ?? request.existingNote?.title ?? request.seed.suggestedTitle
        let extractedKnowledgePoints = extractionService.extract(
            titles: request.knowledgePointTitles,
            suggestedPoints: request.existingNote?.knowledgePoints ?? request.seed.suggestedKnowledgePoints,
            tags: normalizedTags,
            noteTitle: resolvedTitle,
            body: request.body.nonEmpty ?? request.seed.suggestedBody,
            quote: request.seed.anchor.quotedText
        )

        let blocks = builtBlocks(
            anchor: request.seed.anchor,
            quoteText: request.seed.anchor.quotedText,
            body: request.body,
            inkData: request.inkData,
            inkBlock: request.inkBlock
        )

        let resolvedKnowledgePoints = mergedKnowledgePoints(
            explicit: extractedKnowledgePoints,
            linkedIDs: blocks.flatMap(\.linkedKnowledgePointIDs),
            knowledgePointRepository: knowledgePointRepository,
            extractionService: extractionService
        )

        let now = Date()

        if var existingNote = request.existingNote {
            existingNote.title = resolvedTitle
            existingNote.sourceAnchor = request.seed.anchor
            existingNote.blocks = blocks
            existingNote.tags = normalizedTags
            existingNote.knowledgePoints = resolvedKnowledgePoints
            existingNote.updatedAt = now
            try noteRepository.updateNote(existingNote)
            return existingNote
        }

        var created = try noteRepository.createNote(from: request.seed.sentence, anchor: request.seed.anchor)
        created.title = resolvedTitle
        created.blocks = blocks
        created.tags = normalizedTags
        created.knowledgePoints = resolvedKnowledgePoints
        created.updatedAt = now
        try noteRepository.updateNote(created)
        return created
    }
}

@MainActor
struct CreateNoteFromWordUseCase {
    private let baseUseCase: CreateNoteFromSentenceUseCase

    init(baseUseCase: CreateNoteFromSentenceUseCase) {
        self.baseUseCase = baseUseCase
    }

    func execute(_ request: NoteDraftRequest) throws -> Note {
        let enrichedRequest = NoteDraftRequest(
            existingNote: request.existingNote,
            seed: request.seed,
            title: request.title.nonEmpty ?? request.seed.suggestedTitle,
            body: request.body.nonEmpty ?? request.seed.suggestedBody,
            tags: request.tags + request.seed.suggestedTags,
            knowledgePointTitles: request.knowledgePointTitles + request.seed.suggestedKnowledgePoints.map(\.title),
            inkData: request.inkData,
            inkBlock: request.inkBlock
        )
        return try baseUseCase.execute(enrichedRequest)
    }
}

@MainActor
struct AppendNoteBlockUseCase {
    private let noteRepository: any NoteRepositoryProtocol
    private let knowledgePointRepository: any KnowledgePointRepositoryProtocol
    private let extractionService: any KnowledgePointExtractionServiceProtocol

    init(
        noteRepository: any NoteRepositoryProtocol,
        knowledgePointRepository: any KnowledgePointRepositoryProtocol,
        extractionService: any KnowledgePointExtractionServiceProtocol
    ) {
        self.noteRepository = noteRepository
        self.knowledgePointRepository = knowledgePointRepository
        self.extractionService = extractionService
    }

    func execute(_ request: NoteAppendRequest) throws -> Note {
        var updatedNote = request.note
        let normalizedTags = normalizedItems(from: updatedNote.tags + request.tags)

        if let appendedText = request.body.nonEmpty {
            updatedNote.blocks.append(.text(appendedText))
        }

        if let inkData = request.inkData, !inkData.isEmpty {
            if var inkBlock = request.inkBlock {
                inkBlock.inkData = inkData
                updatedNote.blocks.append(inkBlock)
            } else {
                updatedNote.blocks.append(.ink(inkData, linkedSourceAnchorID: updatedNote.sourceAnchor.id))
            }
        }

        let mergedBody = updatedNote.textBlocks
            .compactMap(\.text)
            .joined(separator: "\n\n")

        let extractedKnowledgePoints = extractionService.extract(
            titles: updatedNote.knowledgePoints.map(\.title) + request.knowledgePointTitles,
            suggestedPoints: updatedNote.knowledgePoints,
            tags: normalizedTags,
            noteTitle: updatedNote.title,
            body: mergedBody,
            quote: updatedNote.sourceAnchor.quotedText
        )

        updatedNote.tags = normalizedTags
        updatedNote.knowledgePoints = mergedKnowledgePoints(
            explicit: extractedKnowledgePoints,
            linkedIDs: updatedNote.linkedKnowledgePointIDs,
            knowledgePointRepository: knowledgePointRepository,
            extractionService: extractionService
        )
        updatedNote.updatedAt = Date()
        try noteRepository.updateNote(updatedNote)
        return updatedNote
    }
}

@MainActor
struct LinkKnowledgePointToNoteUseCase {
    private let knowledgePointRepository: any KnowledgePointRepositoryProtocol
    private let extractionService: any KnowledgePointExtractionServiceProtocol

    init(
        knowledgePointRepository: any KnowledgePointRepositoryProtocol,
        extractionService: any KnowledgePointExtractionServiceProtocol
    ) {
        self.knowledgePointRepository = knowledgePointRepository
        self.extractionService = extractionService
    }

    func execute(note: Note, knowledgePointID: String, blockID: UUID? = nil) -> Note {
        var updatedNote = note

        if let blockID,
           let blockIndex = updatedNote.blocks.firstIndex(where: { $0.id == blockID }),
           !updatedNote.blocks[blockIndex].linkedKnowledgePointIDs.contains(knowledgePointID) {
            updatedNote.blocks[blockIndex].linkedKnowledgePointIDs.append(knowledgePointID)
            updatedNote.blocks[blockIndex].updatedAt = Date()
        }

        if let point = knowledgePointRepository.knowledgePoint(with: knowledgePointID),
           !updatedNote.knowledgePoints.contains(where: { $0.id == point.id }) {
            updatedNote.knowledgePoints.append(point)
        }

        updatedNote.knowledgePoints = mergedKnowledgePoints(
            explicit: updatedNote.knowledgePoints,
            linkedIDs: updatedNote.linkedKnowledgePointIDs,
            knowledgePointRepository: knowledgePointRepository,
            extractionService: extractionService
        )
        updatedNote.updatedAt = Date()
        return updatedNote
    }
}

@MainActor
private func builtBlocks(
    anchor: SourceAnchor,
    quoteText: String,
    body: String,
    inkData: Data?,
    inkBlock: NoteBlock?
) -> [NoteBlock] {
    var blocks: [NoteBlock] = [.quote(quoteText)]

    if let body = body.nonEmpty {
        blocks.append(.text(body))
    }

    if let inkData, !inkData.isEmpty {
        if var inkBlock {
            inkBlock.inkData = inkData
            inkBlock.linkedSourceAnchorID = inkBlock.linkedSourceAnchorID ?? anchor.id
            blocks.append(inkBlock)
        } else {
            blocks.append(.ink(inkData, linkedSourceAnchorID: anchor.id))
        }
    }

    return blocks
}

@MainActor
private func mergedKnowledgePoints(
    explicit: [KnowledgePoint],
    linkedIDs: [String],
    knowledgePointRepository: any KnowledgePointRepositoryProtocol,
    extractionService: any KnowledgePointExtractionServiceProtocol
) -> [KnowledgePoint] {
    let linkedPoints = knowledgePointRepository.linkedKnowledgePoints(for: linkedIDs)
    return extractionService.merge(points: explicit + linkedPoints)
}

private func normalizedItems(from items: [String]) -> [String] {
    Array(
        Set(
            items
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    )
    .sorted { $0.localizedCompare($1) == .orderedAscending }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
