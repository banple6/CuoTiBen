import Foundation
import Combine

struct MaterialImportSummary {
    let documents: [SourceDocument]
    let processedPages: Int
    let parsedSectionCount: Int
    let previewChunkCount: Int
    let candidateKnowledgePointCount: Int
}

enum MaterialImportKind {
    case pdf
    case image
    case text
}

/// Main application state manager
@MainActor
final class AppViewModel: ObservableObject {
    private static let sourceReaderModeDefaultsKey = "CuoTiBen.sourceReaderMode"

    @Published var dailyProgress: DailyProgress
    @Published var sourceDocuments: [SourceDocument] {
        didSet {
            invalidateServiceCaches()
        }
    }
    @Published var knowledgeChunks: [KnowledgeChunk] {
        didSet {
            invalidateServiceCaches()
        }
    }
    @Published var reviewQueue: [Card] {
        didSet {
            invalidateServiceCaches()
        }
    }
    @Published var cardDrafts: [Card] {
        didSet {
            invalidateServiceCaches()
        }
    }
    @Published var quickNotes: [StudyNote]
    @Published var notes: [Note] {
        didSet {
            invalidateKnowledgePointCache()
            invalidateServiceCaches()
        }
    }
    @Published var pendingPreviewDocumentID: UUID?
    @Published var structuredSources: [UUID: StructuredSourceBundle] {
        didSet {
            invalidateServiceCaches()
        }
    }
    @Published var workbenchProgress: [UUID: ReviewWorkbenchProgress]
    @Published var structuredSourceLoadingIDs: Set<UUID>
    @Published var structuredSourceErrors: [UUID: String]
    @Published var dailyGoal: Int = 50
    @Published var completedToday: Int = 0
    @Published var totalCardsLearned: Int = 0
    @Published var streakDays: Int = 0
    @Published var sourceReaderMode: SourceReaderMode {
        didSet {
            UserDefaults.standard.set(sourceReaderMode.rawValue, forKey: Self.sourceReaderModeDefaultsKey)
        }
    }

    let importService: ImportService
    private let chunkingService: ChunkingService
    private let cardGenerationService: CardGenerationService
    private let reviewScheduler: ReviewScheduler
    private let noteRepository: NoteRepository
    private let knowledgePointExtractionService: KnowledgePointExtractionService
    lazy var dependencies: DependencyContainer = makeDependencyContainer()
    private var cachedKnowledgePoints: [KnowledgePoint]?
    private var cachedKnowledgePointLookup: [String: KnowledgePoint]?
    private var cachedLearningRecordContextService: LearningRecordContextService?
    private var cachedSourceJumpCoordinator: SourceJumpCoordinator?

    init(
        importService: ImportService? = nil,
        chunkingService: ChunkingService? = nil,
        cardGenerationService: CardGenerationService? = nil,
        reviewScheduler: ReviewScheduler? = nil,
        noteRepository: NoteRepository? = nil,
        knowledgePointExtractionService: KnowledgePointExtractionService? = nil
    ) {
        self.importService = importService ?? ImportService()
        self.chunkingService = chunkingService ?? ChunkingService()
        self.cardGenerationService = cardGenerationService ?? CardGenerationService()
        self.reviewScheduler = reviewScheduler ?? ReviewScheduler()
        self.noteRepository = noteRepository ?? NoteRepository()
        self.knowledgePointExtractionService = knowledgePointExtractionService ?? KnowledgePointExtractionService()

        let sourceDocuments = Self.makeMockSourceDocuments()
        let knowledgeChunks = Self.makeMockKnowledgeChunks(sourceDocuments: sourceDocuments)
        let reviewQueue = Self.makeMockReviewQueue(knowledgeChunks: knowledgeChunks)
        let dailyProgress = Self.makeMockDailyProgress()
        let structuredSources = Self.makeMockStructuredSources(sourceDocuments: sourceDocuments)
        let workbenchProgress = Self.makeMockWorkbenchProgress(
            sourceDocuments: sourceDocuments,
            structuredSources: structuredSources
        )

        self.sourceDocuments = sourceDocuments
        self.knowledgeChunks = knowledgeChunks
        self.reviewQueue = reviewQueue
        self.cardDrafts = reviewQueue.filter(\.isDraft)
        self.quickNotes = []
        self.notes = (try? self.noteRepository.fetchAllNotes()) ?? []
        self.structuredSources = structuredSources
        self.workbenchProgress = workbenchProgress
        self.structuredSourceLoadingIDs = []
        self.structuredSourceErrors = [:]
        self.dailyProgress = dailyProgress
        self.completedToday = dailyProgress.completedToday
        self.totalCardsLearned = dailyProgress.completedToday + 240
        self.streakDays = dailyProgress.streakDays
        self.dailyGoal = max(dailyProgress.pendingReviewsCount, 20)
        self.sourceReaderMode = Self.restoreSourceReaderMode()
    }

    private func makeDependencyContainer() -> DependencyContainer {
        let sourceRepository = AppStateSourceRepository(appViewModel: self)
        let knowledgePointRepository = AppStateKnowledgePointRepository(appViewModel: self)
        let reviewRepository = AppStateReviewRepository(appViewModel: self)
        let learningRecordContextProvider = AppLearningRecordContextProvider(appViewModel: self)
        let sourceJumpRouter = AppStateSourceJumpRouter(appViewModel: self)
        return DependencyContainer(
            noteRepository: noteRepository,
            sourceRepository: sourceRepository,
            knowledgePointRepository: knowledgePointRepository,
            reviewRepository: reviewRepository,
            knowledgePointExtractionService: knowledgePointExtractionService,
            learningRecordContextProvider: learningRecordContextProvider,
            sourceJumpRouter: sourceJumpRouter,
            onNotesChanged: { [weak self] notes in
                self?.notes = notes
            }
        )
    }

    var progressPercentage: Double {
        guard dailyProgress.pendingReviewsCount > 0 else { return 0 }
        return min(
            Double(dailyProgress.completedToday) / Double(dailyProgress.pendingReviewsCount),
            1.0
        )
    }

    func incrementCompleted() {
        completedToday += 1
        totalCardsLearned += 1
        dailyProgress.completedToday += 1
    }

    func resetDailyProgress() {
        completedToday = 0
        dailyProgress.completedToday = 0
    }

    func updateSourceReaderMode(_ mode: SourceReaderMode) {
        sourceReaderMode = mode
    }

    func importMaterials(from urls: [URL], mode: MaterialImportKind) async throws -> MaterialImportSummary {
        let importedDocuments = try await createImportedDocuments(from: urls, mode: mode)
        guard !importedDocuments.isEmpty else {
            throw ImportError.invalidURL("未读取到任何可导入资料")
        }

        let parsingDocuments = importedDocuments.map { document -> SourceDocument in
            var updated = document
            updated.processingStatus = .parsing
            return updated
        }
        sourceDocuments.insert(contentsOf: parsingDocuments, at: 0)

        var successfulDocuments: [SourceDocument] = []
        var processedPages = 0
        var parsedSectionCount = 0
        var previewChunkCount = 0
        var candidateKnowledgePointCount = 0
        var firstError: Error?

        for document in parsingDocuments {
            do {
                let parseResult = try await chunkingService.parse(document: document)
                let readyDocument = finalizeDocument(
                    document,
                    parseResult: parseResult,
                    generatedCards: 0
                )

                replaceSourceDocument(with: readyDocument)
                knowledgeChunks.insert(contentsOf: parseResult.chunks, at: 0)

                processedPages += max(document.pageCount, parseResult.chunks.count, 1)
                parsedSectionCount += max(parseResult.sectionTitles.count, 1)
                previewChunkCount += parseResult.chunks.count
                candidateKnowledgePointCount += parseResult.candidateKnowledgePoints.count
                successfulDocuments.append(readyDocument)

                Task {
                    await loadStructuredSource(for: readyDocument)
                }
            } catch {
                var failedDocument = document
                failedDocument.processingStatus = .failed
                failedDocument.lastProcessingError = error.localizedDescription
                replaceSourceDocument(with: failedDocument)

                if firstError == nil {
                    firstError = error
                }
            }
        }

        guard !successfulDocuments.isEmpty else {
            throw firstError ?? ImportError.copyFailed("导入流程未生成任何可用结果")
        }

        return MaterialImportSummary(
            documents: successfulDocuments,
            processedPages: processedPages,
            parsedSectionCount: parsedSectionCount,
            previewChunkCount: previewChunkCount,
            candidateKnowledgePointCount: candidateKnowledgePointCount
        )
    }

    func chunks(for document: SourceDocument) -> [KnowledgeChunk] {
        knowledgeChunks.filter { $0.sourceDocumentID == document.id }
    }

    func generatedCards(for document: SourceDocument) -> [Card] {
        let chunkIDs = Set(chunks(for: document).map(\.id))
        return reviewQueue.filter { chunkIDs.contains($0.knowledgeChunkID) }
    }

    func structuredSource(for document: SourceDocument) -> StructuredSourceBundle? {
        structuredSources[document.id]
    }

    func structuredSource(for sourceID: UUID) -> StructuredSourceBundle? {
        structuredSources[sourceID]
    }

    func reviewWorkbenchProgress(for document: SourceDocument) -> ReviewWorkbenchProgress {
        workbenchProgress[document.id] ?? ReviewWorkbenchProgress(documentID: document.id)
    }

    func englishDocumentsForWorkbench() -> [SourceDocument] {
        sourceDocuments.filter {
            $0.processingStatus == .ready && isEnglishDocument($0)
        }
    }

    func workbenchMastery(for document: SourceDocument) -> Int {
        let progress = reviewWorkbenchProgress(for: document)
        if let bundle = structuredSource(for: document), bundle.source.sentenceCount > 0 {
            return Int((Double(progress.learnedSentenceIDs.count) / Double(bundle.source.sentenceCount)) * 100)
        }

        return min(progress.learnedSentenceIDs.count * 12, 100)
    }

    func workbenchStudiedSentenceCount(for document: SourceDocument) -> Int {
        reviewWorkbenchProgress(for: document).learnedSentenceIDs.count
    }

    func restoreWorkbenchState(for document: SourceDocument) -> ReviewWorkbenchProgress {
        let progress = workbenchProgress[document.id] ?? ReviewWorkbenchProgress(documentID: document.id)
        if workbenchProgress[document.id] == nil {
            workbenchProgress[document.id] = progress
        }
        return progress
    }

    func recordWorkbenchSelection(
        for document: SourceDocument,
        sentence: Sentence?,
        node: OutlineNode?
    ) {
        var progress = workbenchProgress[document.id] ?? ReviewWorkbenchProgress(documentID: document.id)
        progress.lastVisitedAt = Date()
        progress.lastSentenceID = sentence?.id ?? progress.lastSentenceID
        progress.lastSegmentID = sentence?.segmentID ?? node?.primarySegmentID ?? progress.lastSegmentID
        progress.lastOutlineNodeID = node?.id ?? progress.lastOutlineNodeID

        if let sentence {
            progress.lastAnchorLabel = sentence.anchorLabel
            progress.learnedSentenceIDs.insert(sentence.id)
        } else if let node {
            progress.lastAnchorLabel = node.anchor.label
        }

        workbenchProgress[document.id] = progress
    }

    func currentWorkbenchNode(
        for document: SourceDocument,
        sentenceID: String?,
        nodeID: String?
    ) -> OutlineNode? {
        guard let bundle = structuredSource(for: document) else { return nil }
        if let node = bundle.outlineNode(id: nodeID) {
            return node
        }
        return bundle.bestOutlineNode(forSentenceID: sentenceID)
    }

    func isLoadingStructuredSource(for document: SourceDocument) -> Bool {
        structuredSourceLoadingIDs.contains(document.id)
    }

    func structuredSourceError(for document: SourceDocument) -> String? {
        structuredSourceErrors[document.id]
    }

    func loadStructuredSource(for document: SourceDocument, force: Bool = false) async {
        guard document.processingStatus == .ready else { return }
        guard force || structuredSources[document.id] == nil else { return }
        guard !structuredSourceLoadingIDs.contains(document.id) else { return }

        structuredSourceLoadingIDs.insert(document.id)
        structuredSourceErrors[document.id] = nil
        defer { structuredSourceLoadingIDs.remove(document.id) }

        do {
            let draft = try await chunkingService.extractSourceDraft(document: document)
            guard AISourceParsingService.shouldAttemptEnglishParsing(for: draft) || draft.isLikelyEnglish || Self.containsEnglishLetters(draft.rawText) else {
                structuredSourceErrors[document.id] = "当前资料未识别为英语资料，暂不进入英语结构化理解流程。"
                return
            }

            let payload: StructuredSourceParsePayload
            if AISourceParsingService.shouldPreferLocalFallback(for: draft) {
                print("[AppViewModel] use local structured-source fallback for mixed-language document \(document.id)")
                payload = AISourceParsingService.buildLocalFallbackPayload(
                    documentID: document.id,
                    title: document.title,
                    documentType: document.documentType,
                    pageCount: document.pageCount,
                    draft: draft
                )
            } else {
                do {
                    payload = try await AISourceParsingService.parseSource(
                        documentID: document.id,
                        title: document.title,
                        documentType: document.documentType,
                        pageCount: document.pageCount,
                        draft: draft
                    )
                } catch {
                    print("[AppViewModel] structured-source remote parse failed, fallback locally: \(error.localizedDescription)")
                    payload = AISourceParsingService.buildLocalFallbackPayload(
                        documentID: document.id,
                        title: document.title,
                        documentType: document.documentType,
                        pageCount: document.pageCount,
                        draft: draft
                    )
                }
            }
            structuredSources[document.id] = payload.bundle
            mergeStructuredSourcePayload(payload, into: document)
            seedWorkbenchProgressIfNeeded(for: document, with: payload.bundle)
            structuredSourceErrors[document.id] = nil
        } catch {
            structuredSourceErrors[document.id] = error.localizedDescription
        }
    }

    func knowledgeChunk(for card: Card) -> KnowledgeChunk? {
        knowledgeChunks.first { $0.id == card.knowledgeChunkID }
    }

    func sourceDocument(for card: Card) -> SourceDocument? {
        if let chunk = knowledgeChunk(for: card) {
            return sourceDocuments.first { $0.id == chunk.sourceDocumentID }
        }
        return sourceDocuments.first
    }

    func sourceTitle(for card: Card) -> String {
        sourceDocument(for: card)?.title ?? "导入资料"
    }

    func explainSentenceContext(for sentence: Sentence, in document: SourceDocument) -> ExplainSentenceContext {
        guard let bundle = structuredSource(for: document),
              let segment = bundle.segment(id: sentence.segmentID) else {
            return ExplainSentenceContext(
                title: document.title,
                sentence: sentence.text,
                context: sentence.text
            )
        }

        let segmentSentences = bundle.sentences(in: segment)
        let surrounding = segmentSentences.filter {
            abs($0.localIndex - sentence.localIndex) <= 1
        }

        let context = surrounding.map(\.text).joined(separator: " ")

        return ExplainSentenceContext(
            title: document.title,
            sentence: sentence.text,
            context: context.isEmpty ? segment.text : context
        )
    }

    func outlineAnchorSnippet(for node: OutlineNode, in document: SourceDocument) -> String {
        guard let bundle = structuredSource(for: document) else { return "" }

        let linkedSentences = node.sourceSentenceIDs
            .compactMap { bundle.sentence(id: $0)?.text }
            .prefix(2)

        if !linkedSentences.isEmpty {
            return linkedSentences.joined(separator: "\n\n")
        }

        if let sentence = bundle.sentence(id: node.anchor.sentenceID) {
            return sentence.text
        }

        if let segment = bundle.segment(id: node.anchor.segmentID) {
            return segment.text
        }

        return ""
    }

    func sentenceBreadcrumb(for sentence: Sentence, in document: SourceDocument) -> SentenceBreadcrumb {
        let pageLabel = sentence.page.map { "第\($0)页" } ?? "原文定位"
        let sentenceLabel = "第\(sentence.localIndex + 1)句"
        let matchedNode = structuredSource(for: document)?.bestOutlineNode(forSentenceID: sentence.id)
        let outlineLabel = matchedNode?.title ?? "未归类节点"
        let trailLabels = breadcrumbTrail(for: matchedNode, sentence: sentence, in: document)

        return SentenceBreadcrumb(
            pageLabel: pageLabel,
            sentenceLabel: sentenceLabel,
            outlineLabel: outlineLabel,
            trailLabels: trailLabels
        )
    }

    func contextSentences(for sentence: Sentence, in document: SourceDocument) -> [Sentence] {
        guard let bundle = structuredSource(for: document),
              let segment = bundle.segment(id: sentence.segmentID) else {
            return [sentence]
        }

        let segmentSentences = bundle.sentences(in: segment)
        let surrounding = segmentSentences.filter {
            abs($0.localIndex - sentence.localIndex) <= 1
        }

        return surrounding.isEmpty ? [sentence] : surrounding
    }

    func previousSentence(for sentence: Sentence, in document: SourceDocument) -> Sentence? {
        adjacentSentence(for: sentence, in: document, step: -1)
    }

    func nextSentence(for sentence: Sentence, in document: SourceDocument) -> Sentence? {
        adjacentSentence(for: sentence, in: document, step: 1)
    }

    func outlineNodeDetail(for node: OutlineNode, in document: SourceDocument) -> OutlineNodeDetailSnapshot {
        guard let bundle = structuredSource(for: document) else {
            return OutlineNodeDetailSnapshot(
                id: node.id,
                levelLabel: levelLabel(for: node.depth),
                title: node.title,
                summary: node.summary,
                anchorItems: [
                    OutlineNodeAnchorItem(
                        id: "\(node.id)-anchor",
                        label: node.anchor.label,
                        sentenceID: node.anchor.sentenceID,
                        segmentID: node.anchor.segmentID,
                        previewText: ""
                    )
                ],
                keySentences: [],
                keywords: []
            )
        }

        let keySentences = sentencesForNodeDetail(node, in: bundle)
        let anchors = anchorItems(for: node, keySentences: keySentences, in: bundle)
        let keywords = keywordItems(for: node, keySentences: keySentences)

        return OutlineNodeDetailSnapshot(
            id: node.id,
            levelLabel: levelLabel(for: node.depth),
            title: node.title,
            summary: node.summary,
            anchorItems: anchors,
            keySentences: keySentences,
            keywords: keywords
        )
    }

    func wordExplanation(
        for term: String,
        meaningHint: String? = nil,
        sentence: Sentence? = nil,
        in document: SourceDocument
    ) -> WordExplanationEntry {
        let normalized = normalizedLookupKey(for: term)
        if let seeded = Self.mockWordLibrary[normalized] {
            return mergeWordExplanation(
                seeded,
                fallbackMeaning: meaningHint,
                sentence: sentence
            )
        }

        let contextualMeaning = meaningHint?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? "本句中表示与 \(term.lowercased()) 相关的核心含义。"
        let example = sentence?.text.nonEmpty ?? "\(term) often appears in academic English contexts."

        return WordExplanationEntry(
            id: normalized,
            term: term,
            phonetic: "/\(normalized)/",
            partOfSpeech: inferredPartOfSpeech(for: normalized),
            sentenceMeaning: contextualMeaning,
            commonMeanings: [
                "\(term) 的常见基础义项",
                "\(term) 在学术语境中的引申义"
            ],
            collocations: [
                "\(term) analysis",
                "\(term) process"
            ],
            examples: [example],
            sourceSentence: sentence
        )
    }

    func addQuickNote(title: String, body: String, document: SourceDocument) {
        quickNotes.insert(
            StudyNote(
                sourceDocumentID: document.id,
                title: title,
                body: body
            ),
            at: 0
        )
    }

    func refreshNotes() {
        notes = (try? noteRepository.fetchAllNotes()) ?? notes
    }

    func sourceAnchor(for sentence: Sentence, in document: SourceDocument) -> SourceAnchor {
        let matchedNode = structuredSource(for: document)?.bestOutlineNode(forSentenceID: sentence.id)
        return SourceAnchor(
            sourceID: document.id,
            sourceTitle: document.title,
            pageIndex: sentence.page,
            sentenceID: sentence.id,
            outlineNodeID: matchedNode?.id,
            quotedText: sentence.text,
            anchorLabel: sentence.anchorLabel
        )
    }

    func sentenceNoteSeed(
        for sentence: Sentence,
        explanation: AIExplainSentenceResult?,
        in document: SourceDocument
    ) -> NoteEditorSeed {
        let anchor = sourceAnchor(for: sentence, in: document)
        let suggestedBody = [
            explanation?.translation,
            explanation?.mainStructure
        ]
        .compactMap { $0?.nonEmpty }
        .joined(separator: "\n\n")

        let suggestedKnowledgePoints = knowledgePointExtractionService.extract(
            titles: explanation?.grammarPoints.map(\.name) ?? [],
            suggestedPoints: explanation?.grammarPoints.map {
                KnowledgePoint(
                    title: $0.name,
                    definition: $0.explanation
                )
            } ?? [],
            tags: (explanation?.keyTerms.map(\.term) ?? []) + ["句子讲解"],
            noteTitle: "句子笔记：\(anchor.anchorLabel)",
            body: suggestedBody,
            quote: sentence.text
        )

        return NoteEditorSeed(
            document: document,
            sentence: sentence,
            anchor: anchor,
            suggestedTitle: "句子笔记：\(anchor.anchorLabel)",
            suggestedBody: suggestedBody,
            suggestedTags: (explanation?.keyTerms.map(\.term) ?? []) + ["句子讲解"],
            suggestedKnowledgePoints: suggestedKnowledgePoints
        )
    }

    func wordNoteSeed(
        for entry: WordExplanationEntry,
        in document: SourceDocument
    ) -> NoteEditorSeed? {
        guard let sentence = entry.sourceSentence else { return nil }
        let anchor = sourceAnchor(for: sentence, in: document)
        let suggestedKnowledgePoints = knowledgePointExtractionService.extract(
            titles: [entry.term],
            suggestedPoints: [
                KnowledgePoint(
                    title: entry.term,
                    definition: entry.sentenceMeaning
                )
            ],
            tags: [entry.partOfSpeech, "单词讲解", entry.term],
            noteTitle: "单词笔记：\(entry.term)",
            body: [
                entry.sentenceMeaning,
                entry.collocations.isEmpty ? nil : "常见搭配：\(entry.collocations.joined(separator: "、"))"
            ]
            .compactMap { $0?.nonEmpty }
            .joined(separator: "\n\n"),
            quote: sentence.text
        )

        return NoteEditorSeed(
            document: document,
            sentence: sentence,
            anchor: anchor,
            suggestedTitle: "单词笔记：\(entry.term)",
            suggestedBody: [
                entry.sentenceMeaning,
                entry.collocations.isEmpty ? nil : "常见搭配：\(entry.collocations.joined(separator: "、"))"
            ]
            .compactMap { $0?.nonEmpty }
            .joined(separator: "\n\n"),
            suggestedTags: [entry.partOfSpeech, "单词讲解", entry.term],
            suggestedKnowledgePoints: suggestedKnowledgePoints
        )
    }

    func noteEditorSeed(for note: Note) -> NoteEditorSeed? {
        guard let document = sourceDocument(for: note.sourceAnchor) else { return nil }
        let sentence = sentence(for: note.sourceAnchor) ?? makeSyntheticSentence(for: note, in: document)
        let noteBody = note.textBlocks
            .compactMap(\.text)
            .joined(separator: "\n\n")

        return NoteEditorSeed(
            document: document,
            sentence: sentence,
            anchor: note.sourceAnchor,
            suggestedTitle: note.title,
            suggestedBody: noteBody,
            suggestedTags: note.tags,
            suggestedKnowledgePoints: knowledgePointExtractionService.extract(
                titles: note.knowledgePoints.map(\.title),
                suggestedPoints: note.knowledgePoints,
                tags: note.tags,
                noteTitle: note.title,
                body: noteBody,
                quote: note.sourceAnchor.quotedText
            )
        )
    }

    @discardableResult
    func persistWorkspaceNote(_ note: Note) -> Note? {
        dependencies.notesFlowCoordinator.persistWorkspaceNote(note)
    }

    func noteSourceBundle(for note: Note) -> StructuredSourceBundle? {
        structuredSources[note.sourceAnchor.sourceID]
    }

    func linkedKnowledgePoints(for ids: [String]) -> [KnowledgePoint] {
        let lookup = knowledgePointLookup()
        return ids.compactMap { lookup[$0] }
    }

    @discardableResult
    func saveNote(
        existingNote: Note? = nil,
        seed: NoteEditorSeed,
        title: String,
        body: String,
        tags: [String],
        knowledgePointTitles: [String],
        inkData: Data?,
        inkBlock: NoteBlock? = nil
    ) -> Note? {
        let request = NoteDraftRequest(
            existingNote: existingNote,
            seed: seed,
            title: title,
            body: body,
            tags: tags,
            knowledgePointTitles: knowledgePointTitles,
            inkData: inkData,
            inkBlock: inkBlock
        )
        if seed.suggestedTags.contains("单词讲解") || seed.suggestedTitle.hasPrefix("单词笔记") {
            return dependencies.notesFlowCoordinator.createOrUpdateWordNote(request)
        }
        return dependencies.notesFlowCoordinator.createOrUpdateSentenceNote(request)
    }

    @discardableResult
    func appendBlocks(
        to note: Note,
        body: String,
        tags: [String],
        knowledgePointTitles: [String],
        inkData: Data?,
        inkBlock: NoteBlock? = nil
    ) -> Note? {
        dependencies.notesFlowCoordinator.appendBlocks(
            NoteAppendRequest(
                note: notes.first(where: { $0.id == note.id }) ?? note,
                body: body,
                tags: tags,
                knowledgePointTitles: knowledgePointTitles,
                inkData: inkData,
                inkBlock: inkBlock
            )
        )
    }

    func deleteNote(_ note: Note) {
        do {
            try noteRepository.deleteNote(note)
            notes = (try? noteRepository.fetchAllNotes()) ?? notes.filter { $0.id != note.id }
        } catch {
            print("[AppViewModel] delete note failed: \(error.localizedDescription)")
        }
    }

    func notes(for sourceID: UUID) -> [Note] {
        notes.filter { $0.sourceAnchor.sourceID == sourceID }
    }

    func note(with id: UUID) -> Note? {
        notes.first { $0.id == id }
    }

    func sourceDocument(with id: UUID) -> SourceDocument? {
        sourceDocuments.first { $0.id == id }
    }

    func notes(for knowledgePointID: String) -> [Note] {
        notes.filter { note in
            note.knowledgePoints.contains(where: { $0.id == knowledgePointID })
        }
    }

    func allKnowledgePoints() -> [KnowledgePoint] {
        if let cachedKnowledgePoints {
            return cachedKnowledgePoints
        }

        let merged = knowledgePointExtractionService.merge(points: notes.flatMap(\.knowledgePoints))
        cachedKnowledgePoints = merged
        cachedKnowledgePointLookup = Dictionary(uniqueKeysWithValues: merged.map { ($0.id, $0) })
        return merged
    }

    func learningRecordContext(forSentenceID sentenceID: String) -> LearningRecordContext {
        learningRecordContextService.context(forSentenceID: sentenceID)
    }

    func learningRecordContext(forWord word: String, lemma: String? = nil, sentenceID: String) -> LearningRecordContext {
        learningRecordContextService.context(forWord: word, lemma: lemma, sentenceID: sentenceID)
    }

    func learningRecordContext(forNoteID noteID: UUID) -> LearningRecordContext {
        learningRecordContextService.context(forNoteID: noteID)
    }

    func learningRecordContext(forKnowledgePointID knowledgePointID: String) -> LearningRecordContext {
        learningRecordContextService.context(forKnowledgePointID: knowledgePointID)
    }

    func sourceJumpTarget(for anchor: SourceAnchor) -> SourceJumpTarget? {
        sourceJumpCoordinator.target(for: anchor)
    }

    func sourceJumpTarget(for note: Note) -> SourceJumpTarget? {
        sourceJumpCoordinator.target(for: note)
    }

    func sourceJumpTarget(for knowledgePoint: KnowledgePoint, preferredSourceID: UUID? = nil) -> SourceJumpTarget? {
        sourceJumpCoordinator.target(for: knowledgePoint, preferredSourceID: preferredSourceID)
    }

    func knowledgePoint(with id: String) -> KnowledgePoint? {
        knowledgePointLookup()[id]
    }

    func relatedKnowledgePoints(for point: KnowledgePoint) -> [KnowledgePoint] {
        let allPoints = knowledgePointLookup()
        let cooccurringIDs = Set(
            notes(for: point.id)
                .flatMap(\.knowledgePoints)
                .map(\.id)
                .filter { $0 != point.id }
        )

        return cooccurringIDs
            .compactMap { allPoints[$0] }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    func sourceDocument(for anchor: SourceAnchor) -> SourceDocument? {
        sourceDocuments.first { $0.id == anchor.sourceID }
    }

    func sentence(for anchor: SourceAnchor) -> Sentence? {
        structuredSources[anchor.sourceID]?.sentence(id: anchor.sentenceID)
    }

    func outlineNode(for anchor: SourceAnchor) -> OutlineNode? {
        structuredSources[anchor.sourceID]?.outlineNode(id: anchor.outlineNodeID)
    }

    @discardableResult
    func addVocabularyCard(for entry: WordExplanationEntry, in document: SourceDocument) -> Card {
        let chunk = createChunk(
            title: "词汇：\(entry.term)",
            content: entry.sentenceMeaning,
            locator: document.documentType == .pdf ? "资料词汇卡" : "词汇整理",
            sourceDocumentID: document.id,
            tags: [entry.partOfSpeech, "词汇学习"],
            knowledgePoints: entry.commonMeanings
        )

        let card = Card(
            type: .questionAnswer,
            frontContent: "\(entry.term) 在当前语境中的意思是什么？",
            backContent: "\(entry.sentenceMeaning)\n\n常见搭配：\(entry.collocations.joined(separator: "、"))",
            keywords: [entry.term, entry.partOfSpeech],
            knowledgeChunkID: chunk.id,
            difficultyLevel: 2,
            nextReviewAt: Date(),
            isDraft: true
        )

        insertDraftCard(card)
        updateGeneratedCardCount(generatedCards(for: document).count, for: document.id)
        return card
    }

    @discardableResult
    func addSentenceCard(
        for sentence: Sentence,
        explanation: AIExplainSentenceResult?,
        in document: SourceDocument
    ) -> Card {
        let chunk = createChunk(
            title: "句子精讲",
            content: explanation?.translation ?? sentence.text,
            locator: sentence.anchorLabel,
            sourceDocumentID: document.id,
            tags: (explanation?.keyTerms.map(\.term) ?? []).prefix(3).map { $0 },
            knowledgePoints: explanation?.grammarPoints.map(\.name) ?? []
        )

        let back = [
            explanation?.translation,
            explanation?.mainStructure
        ]
        .compactMap { $0?.nonEmpty }
        .joined(separator: "\n\n")

        let card = Card(
            type: .questionAnswer,
            frontContent: sentence.text,
            backContent: back.nonEmpty ?? "请结合原文上下文复述句子含义。",
            keywords: explanation?.keyTerms.map(\.term) ?? ["句子精讲"],
            knowledgeChunkID: chunk.id,
            difficultyLevel: 3,
            nextReviewAt: Date(),
            isDraft: true
        )

        insertDraftCard(card)
        updateGeneratedCardCount(generatedCards(for: document).count, for: document.id)
        return card
    }

    @discardableResult
    func addNodeCard(for node: OutlineNode, in document: SourceDocument) -> Card {
        let snapshot = outlineNodeDetail(for: node, in: document)
        let chunk = createChunk(
            title: node.title,
            content: node.summary,
            locator: node.anchor.label,
            sourceDocumentID: document.id,
            tags: snapshot.keywords.prefix(4).map(\.term),
            knowledgePoints: [node.title]
        )

        let card = Card(
            type: .questionAnswer,
            frontContent: "结构节点“\(node.title)”的核心意思是什么？",
            backContent: node.summary,
            keywords: snapshot.keywords.prefix(4).map(\.term),
            knowledgeChunkID: chunk.id,
            difficultyLevel: 3,
            nextReviewAt: Date(),
            isDraft: true
        )

        insertDraftCard(card)
        updateGeneratedCardCount(generatedCards(for: document).count, for: document.id)
        return card
    }

    func explainSentenceContext(for card: Card) -> ExplainSentenceContext? {
        let chunk = knowledgeChunk(for: card)
        let sourceTitle = sourceTitle(for: card)
        let sentenceCandidates = [
            card.frontContent,
            chunk?.content,
            card.backContent
        ].compactMap { candidate -> String? in
            guard let candidate else { return nil }
            let normalized = candidate
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.containsEnglishLetters(normalized) else { return nil }
            return normalized
        }

        guard let sentence = sentenceCandidates.first else {
            return nil
        }

        let context = [
            chunk?.content,
            card.backContent,
            sourceDocument(for: card)?.extractedText
        ]
        .compactMap { value in
            let normalized = (value ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? nil : normalized
        }
        .joined(separator: "\n\n")

        return ExplainSentenceContext(
            title: sourceTitle,
            sentence: sentence,
            context: context
        )
    }

    func generateDraftCards(for document: SourceDocument) async throws -> Int {
        let currentDocument = sourceDocuments.first(where: { $0.id == document.id }) ?? document
        let existingCards = generatedCards(for: currentDocument)

        if !existingCards.isEmpty {
            updateGeneratedCardCount(existingCards.count, for: currentDocument.id)
            return existingCards.count
        }

        let documentChunks = chunks(for: currentDocument)
        guard !documentChunks.isEmpty else {
            throw CardGenerationError.parsingFailed("请先完成结构化预览，再生成卡片。")
        }

        var generatedDrafts: [Card] = []
        for chunk in documentChunks {
            generatedDrafts.append(contentsOf: try await cardGenerationService.generateCards(from: chunk))
        }

        guard !generatedDrafts.isEmpty else {
            throw CardGenerationError.parsingFailed("当前资料没有生成可用卡片，请先检查结构化预览。")
        }

        reviewQueue.insert(contentsOf: generatedDrafts, at: 0)
        cardDrafts.insert(contentsOf: generatedDrafts.filter(\.isDraft), at: 0)
        updateGeneratedCardCount(generatedDrafts.count, for: currentDocument.id)

        dailyProgress.pendingReviewsCount += generatedDrafts.count
        dailyProgress.estimatedDurationMinutes += max(1, generatedDrafts.count / 6)
        dailyGoal = max(dailyGoal, dailyProgress.pendingReviewsCount)

        return generatedDrafts.count
    }

    func submitReviewResult(_ result: ReviewResult, for card: Card) async {
        guard let index = reviewQueue.firstIndex(where: { $0.id == card.id }) else { return }

        var updatedCard = reviewQueue[index]
        updatedCard.lastReviewedAt = Date()
        updatedCard.nextReviewAt = reviewScheduler.scheduleNextReview(for: updatedCard, result: result)
        updatedCard.isDraft = false

        switch result {
        case .known:
            updatedCard.difficultyLevel = max(1, updatedCard.difficultyLevel - 1)
        case .vague:
            updatedCard.errorCount += 1
        case .unknown:
            updatedCard.errorCount += 1
            updatedCard.difficultyLevel = min(5, updatedCard.difficultyLevel + 1)
        }

        reviewQueue[index] = updatedCard
        if let draftIndex = cardDrafts.firstIndex(where: { $0.id == updatedCard.id }) {
            cardDrafts[draftIndex] = updatedCard
        }

        dailyProgress.completedToday += 1
        dailyProgress.pendingReviewsCount = max(dailyProgress.pendingReviewsCount - 1, 0)
        completedToday = dailyProgress.completedToday
        totalCardsLearned += 1
    }

    private func createImportedDocuments(from urls: [URL], mode: MaterialImportKind) async throws -> [SourceDocument] {
        switch mode {
        case .pdf:
            var documents: [SourceDocument] = []
            for url in urls {
                documents.append(try await importService.importPDF(at: url))
            }
            return documents
        case .image:
            return try await importService.importImages(from: urls)
        case .text:
            var documents: [SourceDocument] = []
            for url in urls {
                documents.append(try await importService.importText(at: url))
            }
            return documents
        }
    }

    private func finalizeDocument(
        _ document: SourceDocument,
        parseResult: DocumentParseResult,
        generatedCards: Int
    ) -> SourceDocument {
        var updated = document
        updated.processingStatus = .ready
        updated.extractedText = parseResult.bodyText
        updated.sectionTitles = parseResult.sectionTitles
        updated.topicTags = parseResult.topicTags
        updated.candidateKnowledgePoints = parseResult.candidateKnowledgePoints
        updated.chunkCount = parseResult.chunks.count
        updated.generatedCardCount = generatedCards
        updated.lastProcessingError = nil
        return updated
    }

    private func replaceSourceDocument(with document: SourceDocument) {
        guard let index = sourceDocuments.firstIndex(where: { $0.id == document.id }) else { return }
        sourceDocuments[index] = document
    }

    private func updateGeneratedCardCount(_ count: Int, for documentID: UUID) {
        guard let index = sourceDocuments.firstIndex(where: { $0.id == documentID }) else { return }
        sourceDocuments[index].generatedCardCount = count
    }

    private func mergeStructuredSourcePayload(
        _ payload: StructuredSourceParsePayload,
        into document: SourceDocument
    ) {
        guard let index = sourceDocuments.firstIndex(where: { $0.id == document.id }) else { return }

        var updated = sourceDocuments[index]
        updated.extractedText = payload.bundle.source.cleanedText.isEmpty
            ? updated.extractedText
            : payload.bundle.source.cleanedText
        updated.sectionTitles = mergeDocumentMetadataValues(
            primary: payload.sectionTitles,
            fallback: updated.sectionTitles,
            limit: 6
        )
        updated.topicTags = mergeDocumentMetadataValues(
            primary: payload.topicTags,
            fallback: updated.topicTags,
            limit: 8
        )
        updated.candidateKnowledgePoints = mergeDocumentMetadataValues(
            primary: payload.candidateKnowledgePoints,
            fallback: updated.candidateKnowledgePoints,
            limit: 12
        )
        updated.pageCount = max(updated.pageCount, payload.bundle.source.pageCount)
        updated.lastProcessingError = nil
        sourceDocuments[index] = updated
    }

    private func mergeDocumentMetadataValues(
        primary: [String],
        fallback: [String],
        limit: Int
    ) -> [String] {
        var groups: [[String]] = []

        for value in primary + fallback {
            let cleaned = cleanedDocumentMetadataValue(value)
            guard !cleaned.isEmpty else { continue }

            if let index = groups.firstIndex(where: { group in
                group.contains { candidate in
                    let lhs = normalizedDocumentMetadataKey(candidate)
                    let rhs = normalizedDocumentMetadataKey(cleaned)
                    return lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs) || documentMetadataOverlap(lhs, rhs) >= 0.74
                }
            }) {
                groups[index].append(cleaned)
            } else {
                groups.append([cleaned])
            }
        }

        return groups
            .map(preferredDocumentMetadataLabel)
            .filter { !$0.isEmpty }
            .prefix(limit)
            .map { $0 }
    }

    private func cleanedDocumentMetadataValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"^[\s\dIVXivx一二三四五六七八九十]+[.、):：\-]?\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^(section|part|chapter|paragraph)\s+\d+[:：\-]?\s*"#, with: "", options: .regularExpression)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func normalizedDocumentMetadataKey(_ value: String) -> String {
        cleanedDocumentMetadataValue(value)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\u4e00-\\u9fff]+", with: " ", options: .regularExpression)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { token in
                if token.count > 4 && token.hasSuffix("ies") {
                    return String(token.dropLast(3)) + "y"
                }
                if token.count > 4 && token.hasSuffix("s") && !token.hasSuffix("ss") {
                    return String(token.dropLast())
                }
                return token
            }
            .joined(separator: " ")
    }

    private func documentMetadataOverlap(_ lhs: String, _ rhs: String) -> Double {
        let lhsSet = Set(lhs.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        let rhsSet = Set(rhs.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })

        guard !lhsSet.isEmpty, !rhsSet.isEmpty else { return 0 }
        let intersection = lhsSet.intersection(rhsSet).count
        let union = lhsSet.union(rhsSet).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    private func preferredDocumentMetadataLabel(_ values: [String]) -> String {
        values
            .map(cleanedDocumentMetadataValue)
            .filter { !$0.isEmpty }
            .sorted { lhs, rhs in
                let lhsChinese = lhs.containsChineseCharacters ? 1 : 0
                let rhsChinese = rhs.containsChineseCharacters ? 1 : 0
                if lhsChinese != rhsChinese {
                    return lhsChinese > rhsChinese
                }

                if lhs.count != rhs.count {
                    return abs(lhs.count - 10) < abs(rhs.count - 10)
                }

                return lhs < rhs
            }
            .first ?? ""
    }

    private var learningRecordContextService: LearningRecordContextService {
        if let cachedLearningRecordContextService {
            return cachedLearningRecordContextService
        }

        let service = LearningRecordContextService(
            sourceDocuments: sourceDocuments,
            structuredSources: structuredSources,
            knowledgeChunks: knowledgeChunks,
            notes: notes,
            knowledgePoints: allKnowledgePoints(),
            reviewQueue: reviewQueue,
            cardDrafts: cardDrafts
        )
        cachedLearningRecordContextService = service
        return service
    }

    private var sourceJumpCoordinator: SourceJumpCoordinator {
        if let cachedSourceJumpCoordinator {
            return cachedSourceJumpCoordinator
        }

        let coordinator = SourceJumpCoordinator(
            sourceDocuments: sourceDocuments,
            structuredSources: structuredSources
        )
        cachedSourceJumpCoordinator = coordinator
        return coordinator
    }

    private static func containsEnglishLetters(_ text: String) -> Bool {
        text.range(of: "[A-Za-z]", options: .regularExpression) != nil
    }

    private func adjacentSentence(for sentence: Sentence, in document: SourceDocument, step: Int) -> Sentence? {
        guard let bundle = structuredSource(for: document) else { return nil }
        let orderedSentences = bundle.sentences.sorted { lhs, rhs in
            if lhs.index != rhs.index {
                return lhs.index < rhs.index
            }

            return lhs.localIndex < rhs.localIndex
        }

        guard let currentIndex = orderedSentences.firstIndex(where: { $0.id == sentence.id }) else {
            return nil
        }

        let targetIndex = currentIndex + step
        guard orderedSentences.indices.contains(targetIndex) else { return nil }
        return orderedSentences[targetIndex]
    }

    private func sentencesForNodeDetail(_ node: OutlineNode, in bundle: StructuredSourceBundle) -> [Sentence] {
        let directSentences = node.sourceSentenceIDs.compactMap { bundle.sentence(id: $0) }
        if !directSentences.isEmpty {
            return Array(directSentences.prefix(4))
        }

        if let sentence = bundle.sentence(id: node.anchor.sentenceID) {
            return [sentence]
        }

        if let segment = bundle.segment(id: node.anchor.segmentID) {
            return Array(bundle.sentences(in: segment).prefix(3))
        }

        return []
    }

    private func anchorItems(
        for node: OutlineNode,
        keySentences: [Sentence],
        in bundle: StructuredSourceBundle
    ) -> [OutlineNodeAnchorItem] {
        var results: [OutlineNodeAnchorItem] = []
        var seenIDs = Set<String>()

        for sentence in keySentences {
            guard seenIDs.insert(sentence.id).inserted else { continue }
            results.append(
                OutlineNodeAnchorItem(
                    id: sentence.id,
                    label: sentence.anchorLabel,
                    sentenceID: sentence.id,
                    segmentID: sentence.segmentID,
                    previewText: sentence.text
                )
            )
        }

        if results.isEmpty,
           let segment = bundle.segment(id: node.primarySegmentID ?? node.anchor.segmentID) {
            results.append(
                OutlineNodeAnchorItem(
                    id: segment.id,
                    label: segment.anchorLabel,
                    sentenceID: nil,
                    segmentID: segment.id,
                    previewText: segment.text
                )
            )
        }

        if results.isEmpty {
            results.append(
                OutlineNodeAnchorItem(
                    id: "\(node.id)-anchor",
                    label: node.anchor.label,
                    sentenceID: node.anchor.sentenceID,
                    segmentID: node.anchor.segmentID,
                    previewText: node.summary
                )
            )
        }

        return results
    }

    private func keywordItems(for node: OutlineNode, keySentences: [Sentence]) -> [OutlineNodeKeyword] {
        let sourceText = ([node.title, node.summary] + keySentences.map(\.text)).joined(separator: " ")
        let terms = extractedKeywordTerms(from: sourceText, limit: 6)
        let keywords = terms.map { term in
            OutlineNodeKeyword(
                id: normalizedLookupKey(for: term),
                term: term,
                hint: Self.mockWordLibrary[normalizedLookupKey(for: term)]?.sentenceMeaning ?? "点击查看该词在当前节点中的用法"
            )
        }

        if !keywords.isEmpty {
            return keywords
        }

        return node.title
            .split(separator: " ")
            .map(String.init)
            .prefix(3)
            .map {
                OutlineNodeKeyword(
                    id: normalizedLookupKey(for: $0),
                    term: $0,
                    hint: "点击查看该词在当前节点中的用法"
                )
            }
    }

    private func levelLabel(for depth: Int) -> String {
        switch max(depth, 0) {
        case 0:
            return "一级节点"
        case 1:
            return "二级节点"
        default:
            return "三级及以下"
        }
    }

    private func inferredPartOfSpeech(for term: String) -> String {
        if term.hasSuffix("ly") {
            return "副词"
        }
        if term.hasSuffix("tion") || term.hasSuffix("ment") || term.hasSuffix("ness") {
            return "名词"
        }
        if term.hasSuffix("ed") || term.hasSuffix("ing") {
            return "动词"
        }
        return "核心词"
    }

    private func normalizedLookupKey(for term: String) -> String {
        term
            .lowercased()
            .replacingOccurrences(of: "[^a-z]", with: "", options: .regularExpression)
    }

    private func mergeWordExplanation(
        _ seeded: WordExplanationEntry,
        fallbackMeaning: String?,
        sentence: Sentence?
    ) -> WordExplanationEntry {
        WordExplanationEntry(
            id: seeded.id,
            term: seeded.term,
            phonetic: seeded.phonetic,
            partOfSpeech: seeded.partOfSpeech,
            sentenceMeaning: fallbackMeaning?.nonEmpty ?? seeded.sentenceMeaning,
            commonMeanings: seeded.commonMeanings,
            collocations: seeded.collocations,
            examples: sentence.map { [$0.text] } ?? seeded.examples,
            sourceSentence: sentence ?? seeded.sourceSentence
        )
    }

    private func extractedKeywordTerms(from text: String, limit: Int) -> [String] {
        let tokens = text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { token in
                let normalized = token.lowercased()
                return normalized.count >= 4 &&
                    Self.containsEnglishLetters(normalized) &&
                    !Self.stopWords.contains(normalized)
            }

        var counts: [String: Int] = [:]
        for token in tokens {
            counts[token.lowercased(), default: 0] += 1
        }

        return counts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key < rhs.key
            }
            .map(\.key)
            .prefix(limit)
            .map { $0.capitalized }
    }

    private func breadcrumbTrail(
        for node: OutlineNode?,
        sentence: Sentence,
        in document: SourceDocument
    ) -> [String] {
        guard let node, let bundle = structuredSource(for: document) else {
            return [sentence.page.map { "第\($0)页" } ?? "原文定位", "第\(sentence.localIndex + 1)句"]
        }

        let ancestorTitles = bundle
            .ancestorNodeIDs(for: node.id)
            .reversed()
            .compactMap { bundle.outlineNode(id: $0)?.title.nonEmpty }

        return ancestorTitles + [node.title, "第\(sentence.localIndex + 1)句"]
    }

    private func createChunk(
        title: String,
        content: String,
        locator: String,
        sourceDocumentID: UUID,
        tags: [String],
        knowledgePoints: [String]
    ) -> KnowledgeChunk {
        let chunk = KnowledgeChunk(
            title: title,
            content: content,
            sourceDocumentID: sourceDocumentID,
            sourceLocator: locator,
            tags: tags,
            candidateKnowledgePoints: knowledgePoints,
            manualAdjusted: true
        )
        knowledgeChunks.insert(chunk, at: 0)
        return chunk
    }

    private func insertDraftCard(_ card: Card) {
        reviewQueue.insert(card, at: 0)
        cardDrafts.insert(card, at: 0)
        dailyProgress.pendingReviewsCount += 1
        dailyGoal = max(dailyGoal, dailyProgress.pendingReviewsCount)
    }

    private func normalizedItems(from values: [String]) -> [String] {
        let splitValues = values.flatMap { value in
            value.split(separator: ",").map(String.init)
        }

        var seen = Set<String>()
        return splitValues
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { item in
                guard !item.isEmpty else { return false }
                let lookup = item.lowercased()
                guard !seen.contains(lookup) else { return false }
                seen.insert(lookup)
                return true
            }
    }

    private func mergedKnowledgePoints(explicit: [KnowledgePoint], linkedIDs: [String]) -> [KnowledgePoint] {
        let knownLookup = knowledgePointLookup()
        let explicitLookup = Dictionary(uniqueKeysWithValues: explicit.map { ($0.id, $0) })
        let mergedIDs = Array(Set(explicit.map(\.id) + linkedIDs)).sorted()

        return mergedIDs.compactMap { id in
            explicitLookup[id] ?? knownLookup[id]
        }
    }

    private func knowledgePointLookup() -> [String: KnowledgePoint] {
        if let cachedKnowledgePointLookup {
            return cachedKnowledgePointLookup
        }

        let merged = allKnowledgePoints()
        let lookup = Dictionary(uniqueKeysWithValues: merged.map { ($0.id, $0) })
        cachedKnowledgePointLookup = lookup
        return lookup
    }

    private func invalidateKnowledgePointCache() {
        cachedKnowledgePoints = nil
        cachedKnowledgePointLookup = nil
    }

    private func invalidateServiceCaches() {
        cachedLearningRecordContextService = nil
        cachedSourceJumpCoordinator = nil
    }

    private func seedWorkbenchProgressIfNeeded(for document: SourceDocument, with bundle: StructuredSourceBundle) {
        guard workbenchProgress[document.id] == nil else { return }
        let firstSentence = bundle.sentences.first
        workbenchProgress[document.id] = ReviewWorkbenchProgress(
            documentID: document.id,
            lastVisitedAt: document.importDate,
            lastSentenceID: firstSentence?.id,
            lastSegmentID: firstSentence?.segmentID,
            lastOutlineNodeID: bundle.bestOutlineNode(forSentenceID: firstSentence?.id)?.id,
            learnedSentenceIDs: Set([firstSentence?.id].compactMap { $0 }),
            lastAnchorLabel: firstSentence?.anchorLabel ?? "尚未开始"
        )
    }

    private func isEnglishDocument(_ document: SourceDocument) -> Bool {
        if let structured = structuredSource(for: document) {
            return structured.source.isEnglish
        }

        return Self.containsEnglishLetters(document.extractedText) ||
            document.title.lowercased().contains("english") ||
            document.topicTags.contains { $0.contains("英语") }
    }

    private func makeSyntheticSentence(for note: Note, in document: SourceDocument) -> Sentence {
        let fallbackSegmentID = structuredSource(for: document)?.segments.first?.id ?? "segment-\(document.id.uuidString)"
        return Sentence(
            id: note.sourceAnchor.sentenceID ?? "note-\(note.id.uuidString)",
            sourceID: document.id.uuidString,
            segmentID: fallbackSegmentID,
            index: 0,
            localIndex: 0,
            text: note.sourceAnchor.quotedText,
            anchorLabel: note.sourceAnchor.anchorLabel,
            page: note.sourceAnchor.pageIndex
        )
    }

    private static let stopWords: Set<String> = [
        "that", "this", "with", "from", "have", "were", "been", "before", "after", "about",
        "their", "would", "could", "should", "into", "through", "there", "which", "while",
        "where", "when", "what", "policy", "changes", "research", "because", "these", "those",
        "committee", "necessary", "implemented"
    ]

    private static let mockWordLibrary: [String: WordExplanationEntry] = [
        "committee": WordExplanationEntry(
            id: "committee",
            term: "committee",
            phonetic: "/kəˈmɪti/",
            partOfSpeech: "名词",
            sentenceMeaning: "委员会；负责集体讨论和决策的小组。",
            commonMeanings: ["委员会", "专项评审小组"],
            collocations: ["ethics committee", "committee decision", "committee members"],
            examples: ["The committee concluded that more evidence was needed."],
            sourceSentence: nil
        ),
        "concluded": WordExplanationEntry(
            id: "concluded",
            term: "concluded",
            phonetic: "/kənˈkluːdɪd/",
            partOfSpeech: "动词",
            sentenceMeaning: "得出结论；在分析后形成正式判断。",
            commonMeanings: ["得出结论", "结束", "推断"],
            collocations: ["concluded that", "study concluded", "concluded from"],
            examples: ["The report concluded that the policy was premature."],
            sourceSentence: nil
        ),
        "further": WordExplanationEntry(
            id: "further",
            term: "further",
            phonetic: "/ˈfɜːrðər/",
            partOfSpeech: "形容词/副词",
            sentenceMeaning: "进一步的；在现有基础上继续推进。",
            commonMeanings: ["进一步的", "更深层的", "此外"],
            collocations: ["further research", "further analysis", "further discussion"],
            examples: ["Further research is required before implementation."],
            sourceSentence: nil
        ),
        "research": WordExplanationEntry(
            id: "research",
            term: "research",
            phonetic: "/rɪˈsɜːrtʃ/",
            partOfSpeech: "名词",
            sentenceMeaning: "研究；通过系统方法获得新证据或结论。",
            commonMeanings: ["研究", "调查", "学术探索"],
            collocations: ["conduct research", "research findings", "further research"],
            examples: ["The research supports a more cautious policy approach."],
            sourceSentence: nil
        ),
        "policy": WordExplanationEntry(
            id: "policy",
            term: "policy",
            phonetic: "/ˈpɑːləsi/",
            partOfSpeech: "名词",
            sentenceMeaning: "政策；组织或政府采取的正式行动方案。",
            commonMeanings: ["政策", "方针", "制度安排"],
            collocations: ["public policy", "policy changes", "policy decision"],
            examples: ["Policy changes should be based on stronger evidence."],
            sourceSentence: nil
        ),
        "implemented": WordExplanationEntry(
            id: "implemented",
            term: "implemented",
            phonetic: "/ˈɪmplɪˌmentɪd/",
            partOfSpeech: "动词",
            sentenceMeaning: "被实施；正式落地执行。",
            commonMeanings: ["实施", "执行", "落地推进"],
            collocations: ["be implemented", "fully implemented", "implemented policy"],
            examples: ["The new measures were not implemented immediately."],
            sourceSentence: nil
        ),
        "algorithms": WordExplanationEntry(
            id: "algorithms",
            term: "Algorithms",
            phonetic: "/ˈælɡəˌrɪðəmz/",
            partOfSpeech: "名词",
            sentenceMeaning: "算法；解决问题的一套规则或步骤。",
            commonMeanings: ["算法", "运算规则", "处理流程"],
            collocations: ["machine learning algorithms", "search algorithms", "core algorithms"],
            examples: ["Algorithms can shape what information users see online."],
            sourceSentence: nil
        ),
        "become": WordExplanationEntry(
            id: "become",
            term: "Become",
            phonetic: "/bɪˈkʌm/",
            partOfSpeech: "动词",
            sentenceMeaning: "变得；逐步进入某种状态。",
            commonMeanings: ["变成", "变得", "开始成为"],
            collocations: ["become important", "become more likely", "become part of"],
            examples: ["Invisible infrastructure can become central to daily life."],
            sourceSentence: nil
        ),
        "both": WordExplanationEntry(
            id: "both",
            term: "Both",
            phonetic: "/boʊθ/",
            partOfSpeech: "限定词/代词",
            sentenceMeaning: "两者都；强调两个对象同时成立。",
            commonMeanings: ["两者都", "双方都"],
            collocations: ["both sides", "both of them", "both A and B"],
            examples: ["Both dimensions of infrastructure shape the reading passage."],
            sourceSentence: nil
        )
    ]

    private static func makeMockStructuredSources(sourceDocuments: [SourceDocument]) -> [UUID: StructuredSourceBundle] {
        guard let document = sourceDocuments.first else { return [:] }

        let sourceID = document.id.uuidString
        let segments = [
            Segment(
                id: "seg_intro",
                sourceID: sourceID,
                index: 0,
                text: "Directions: Read the passage and answer the questions carefully.",
                anchorLabel: "第1页 第1段",
                page: 1,
                sentenceIDs: ["sen_intro_1"]
            ),
            Segment(
                id: "seg_body_1",
                sourceID: sourceID,
                index: 1,
                text: "Invisible infrastructure has become essential to modern life. Both digital systems and physical networks shape how people move, communicate, and make decisions.",
                anchorLabel: "第1页 第2段",
                page: 1,
                sentenceIDs: ["sen_body_1", "sen_body_2"]
            ),
            Segment(
                id: "seg_body_2",
                sourceID: sourceID,
                index: 2,
                text: "Algorithms increasingly guide attention, while transport networks quietly determine what choices are practical. Understanding both layers helps readers see why infrastructure is never neutral.",
                anchorLabel: "第1页 第3段",
                page: 1,
                sentenceIDs: ["sen_body_3", "sen_body_4"]
            ),
            Segment(
                id: "seg_body_3",
                sourceID: sourceID,
                index: 3,
                text: "For students, the key is to trace how the author moves from definition to implication. Once that structure becomes visible, long sentences become easier to decode.",
                anchorLabel: "第2页 第1段",
                page: 2,
                sentenceIDs: ["sen_body_5", "sen_body_6"]
            )
        ]

        let sentences = [
            Sentence(id: "sen_intro_1", sourceID: sourceID, segmentID: "seg_intro", index: 0, localIndex: 0, text: "Directions: Read the passage and answer the questions carefully.", anchorLabel: "第1页 第1句", page: 1),
            Sentence(id: "sen_body_1", sourceID: sourceID, segmentID: "seg_body_1", index: 1, localIndex: 0, text: "Invisible infrastructure has become essential to modern life.", anchorLabel: "第1页 第2句", page: 1),
            Sentence(id: "sen_body_2", sourceID: sourceID, segmentID: "seg_body_1", index: 2, localIndex: 1, text: "Both digital systems and physical networks shape how people move, communicate, and make decisions.", anchorLabel: "第1页 第3句", page: 1),
            Sentence(id: "sen_body_3", sourceID: sourceID, segmentID: "seg_body_2", index: 3, localIndex: 0, text: "Algorithms increasingly guide attention, while transport networks quietly determine what choices are practical.", anchorLabel: "第1页 第4句", page: 1),
            Sentence(id: "sen_body_4", sourceID: sourceID, segmentID: "seg_body_2", index: 4, localIndex: 1, text: "Understanding both layers helps readers see why infrastructure is never neutral.", anchorLabel: "第1页 第5句", page: 1),
            Sentence(id: "sen_body_5", sourceID: sourceID, segmentID: "seg_body_3", index: 5, localIndex: 0, text: "For students, the key is to trace how the author moves from definition to implication.", anchorLabel: "第2页 第1句", page: 2),
            Sentence(id: "sen_body_6", sourceID: sourceID, segmentID: "seg_body_3", index: 6, localIndex: 1, text: "Once that structure becomes visible, long sentences become easier to decode.", anchorLabel: "第2页 第2句", page: 2)
        ]

        let outline = [
            OutlineNode(
                id: "node_root",
                sourceID: sourceID,
                parentID: nil,
                depth: 0,
                order: 0,
                title: "隐形基础设施的双重维度",
                summary: "作者先界定隐形基础设施的概念，再说明数字系统和物理网络如何同时影响现代生活。",
                anchor: OutlineAnchor(segmentID: "seg_body_1", sentenceID: "sen_body_1", page: 1, label: "第1页 第2句"),
                sourceSegmentIDs: ["seg_body_1", "seg_body_2"],
                sourceSentenceIDs: ["sen_body_1", "sen_body_2", "sen_body_3", "sen_body_4"],
                children: [
                    OutlineNode(
                        id: "node_digital",
                        sourceID: sourceID,
                        parentID: "node_root",
                        depth: 1,
                        order: 0,
                        title: "数字系统如何塑造注意力",
                        summary: "算法通过决定人们首先看见什么，悄悄影响理解和选择。",
                        anchor: OutlineAnchor(segmentID: "seg_body_2", sentenceID: "sen_body_3", page: 1, label: "第1页 第4句"),
                        sourceSegmentIDs: ["seg_body_2"],
                        sourceSentenceIDs: ["sen_body_3"],
                        children: []
                    ),
                    OutlineNode(
                        id: "node_physical",
                        sourceID: sourceID,
                        parentID: "node_root",
                        depth: 1,
                        order: 1,
                        title: "物理网络限定现实选择",
                        summary: "交通等物理网络决定哪些选择真正可行，因此基础设施并非中立背景。",
                        anchor: OutlineAnchor(segmentID: "seg_body_2", sentenceID: "sen_body_4", page: 1, label: "第1页 第5句"),
                        sourceSegmentIDs: ["seg_body_2"],
                        sourceSentenceIDs: ["sen_body_4"],
                        children: []
                    ),
                    OutlineNode(
                        id: "node_strategy",
                        sourceID: sourceID,
                        parentID: "node_root",
                        depth: 1,
                        order: 2,
                        title: "阅读策略：追踪定义到影响",
                        summary: "学生需要顺着作者从定义推进到含义的路径阅读，这样长句解析会更容易。",
                        anchor: OutlineAnchor(segmentID: "seg_body_3", sentenceID: "sen_body_5", page: 2, label: "第2页 第1句"),
                        sourceSegmentIDs: ["seg_body_3"],
                        sourceSentenceIDs: ["sen_body_5", "sen_body_6"],
                        children: []
                    )
                ]
            )
        ]

        let bundle = StructuredSourceBundle(
            source: Source(
                id: sourceID,
                title: document.title,
                sourceType: document.documentType.rawValue.lowercased(),
                language: "en",
                isEnglish: true,
                cleanedText: sentences.map(\.text).joined(separator: " "),
                pageCount: document.pageCount,
                segmentCount: segments.count,
                sentenceCount: sentences.count,
                outlineNodeCount: 4
            ),
            segments: segments,
            sentences: sentences,
            outline: outline
        )

        return [document.id: bundle]
    }

    private static func makeMockWorkbenchProgress(
        sourceDocuments: [SourceDocument],
        structuredSources: [UUID: StructuredSourceBundle]
    ) -> [UUID: ReviewWorkbenchProgress] {
        guard let document = sourceDocuments.first,
              let bundle = structuredSources[document.id] else {
            return [:]
        }

        return [
            document.id: ReviewWorkbenchProgress(
                documentID: document.id,
                lastVisitedAt: Date().addingTimeInterval(-60 * 42),
                lastSentenceID: "sen_body_2",
                lastSegmentID: "seg_body_1",
                lastOutlineNodeID: bundle.bestOutlineNode(forSentenceID: "sen_body_2")?.id,
                learnedSentenceIDs: Set(["sen_body_1", "sen_body_2", "sen_body_3"]),
                lastAnchorLabel: "第1页 第3句"
            )
        ]
    }

    private static func makeMockSourceDocuments() -> [SourceDocument] {
        [
            SourceDocument(
                title: "考研英语阅读精讲",
                documentType: .pdf,
                importDate: Date().addingTimeInterval(-86_400 * 2),
                pageCount: 42,
                filePath: "/mock/english-reading.pdf",
                processingStatus: .ready,
                extractedText: "阅读理解讲义正文",
                sectionTitles: ["长难句拆解", "题干定位", "干扰项分析"],
                topicTags: ["英语阅读", "长难句", "题干定位"],
                candidateKnowledgePoints: ["长难句拆解", "题干定位", "中心句判断"],
                chunkCount: 6,
                generatedCardCount: 18
            ),
            SourceDocument(
                title: "政治高频考点截图",
                documentType: .image,
                importDate: Date().addingTimeInterval(-86_400 * 5),
                pageCount: 12,
                filePath: "/mock/politics-notes.png",
                processingStatus: .ready,
                extractedText: "政治高频考点 OCR 正文",
                sectionTitles: ["宏观经济指标", "供给侧改革"],
                topicTags: ["政治", "宏观经济", "改革"],
                candidateKnowledgePoints: ["宏观经济指标", "供给侧改革", "财政政策"],
                chunkCount: 4,
                generatedCardCount: 12
            ),
            SourceDocument(
                title: "机器学习基础笔记",
                documentType: .pdf,
                importDate: Date().addingTimeInterval(-86_400 * 1),
                pageCount: 36,
                filePath: "/mock/ml-foundations.pdf",
                processingStatus: .parsing,
                extractedText: "",
                sectionTitles: ["概率分布", "偏差方差"],
                topicTags: ["机器学习", "概率", "偏差方差"],
                candidateKnowledgePoints: ["概率分布", "偏差方差权衡"],
                chunkCount: 2,
                generatedCardCount: 0
            ),
            SourceDocument(
                title: "错题回顾文本整理",
                documentType: .text,
                importDate: Date().addingTimeInterval(-86_400 * 8),
                pageCount: 1,
                filePath: "/mock/python-review.txt",
                processingStatus: .imported,
                extractedText: "",
                sectionTitles: [],
                topicTags: ["文本笔记"],
                candidateKnowledgePoints: [],
                chunkCount: 0,
                generatedCardCount: 0
            )
    ]
}

    private static func makeMockKnowledgeChunks(sourceDocuments: [SourceDocument]) -> [KnowledgeChunk] {
        guard let firstSource = sourceDocuments.first else { return [] }
        let englishChunkID = UUID()
        let economicsChunkID = UUID()
        let memoryChunkID = UUID()

        return [
            KnowledgeChunk(
                id: englishChunkID,
                title: "政策研究长难句",
                content: "The committee concluded that further research was necessary before any policy changes could be implemented. The author uses this sentence to show that the committee remained cautious about making immediate reforms without stronger evidence.",
                sourceDocumentID: firstSource.id,
                startPosition: 6,
                endPosition: 6,
                sourceLocator: "第 6 页",
                tags: ["英语阅读", "长难句"],
                candidateKnowledgePoints: ["宾语从句", "政策语境表达"]
            ),
            KnowledgeChunk(
                id: economicsChunkID,
                title: "机会成本",
                content: "机会成本是为了选择某个方案而放弃的最佳替代方案价值。",
                sourceDocumentID: sourceDocuments.dropFirst().first?.id ?? firstSource.id,
                startPosition: 2,
                endPosition: 2,
                sourceLocator: "第 2 页",
                tags: ["经济学"],
                candidateKnowledgePoints: ["机会成本"]
            ),
            KnowledgeChunk(
                id: memoryChunkID,
                title: "主动回忆",
                content: "长期记忆形成依赖于主动回忆的重复提取。",
                sourceDocumentID: sourceDocuments.dropFirst().first?.id ?? firstSource.id,
                startPosition: 3,
                endPosition: 3,
                sourceLocator: "第 3 页",
                tags: ["记忆"],
                candidateKnowledgePoints: ["主动回忆"]
            )
        ]
    }

    private static func makeMockReviewQueue(knowledgeChunks: [KnowledgeChunk]) -> [Card] {
        let englishChunkID = knowledgeChunks.first?.id ?? UUID()
        let economicsChunkID = knowledgeChunks.dropFirst().first?.id ?? UUID()
        let memoryChunkID = knowledgeChunks.dropFirst(2).first?.id ?? UUID()

        return [
            Card(
                type: .questionAnswer,
                frontContent: "The committee concluded that further research was necessary before any policy changes could be implemented.",
                backContent: "委员会认为，在实施任何政策调整之前，还需要进一步研究。",
                keywords: ["英语阅读", "长难句", "政策语境"],
                knowledgeChunkID: englishChunkID,
                difficultyLevel: 3,
                errorCount: 1,
                nextReviewAt: Date()
            ),
            Card(
                type: .fillInBlank,
                frontContent: "长期记忆形成依赖于 ______ 的重复提取。",
                backContent: "主动回忆",
                keywords: ["记忆", "主动回忆"],
                knowledgeChunkID: memoryChunkID,
                difficultyLevel: 2,
                nextReviewAt: Date().addingTimeInterval(3_600)
            ),
            Card(
                type: .trueFalseChoice,
                frontContent: "判断正误：边际效用会随着连续消费同一商品而持续上升。",
                backContent: "正确答案：错误\n边际效用递减规律表示满足感会逐渐下降。",
                keywords: ["边际效用", "经济学"],
                knowledgeChunkID: economicsChunkID,
                options: ["正确", "错误"],
                correctOption: "错误",
                difficultyLevel: 4,
                errorCount: 2,
                nextReviewAt: Date().addingTimeInterval(7_200),
                isDraft: true
            ),
            Card(
                type: .questionAnswer,
                frontContent: "海马体在记忆中的主要作用是什么？",
                backContent: "海马体参与情景记忆与空间记忆的形成，并帮助短时信息转入长期记忆。",
                keywords: ["神经科学", "记忆", "海马体"],
                knowledgeChunkID: memoryChunkID,
                difficultyLevel: 3,
                errorCount: 1,
                nextReviewAt: Date().addingTimeInterval(10_800)
            )
        ]
    }

    private static func makeMockDailyProgress() -> DailyProgress {
        DailyProgress(
            pendingReviewsCount: 18,
            estimatedDurationMinutes: 12,
            completedToday: 7,
            streakDays: 6,
            weeklyAccuracy: 0.82,
            highErrorChunks: [
                KnowledgeChunkSummary(
                    id: UUID(),
                    title: "宏观经济指标",
                    sourceTitle: "政治高频考点截图",
                    errorFrequency: 4
                ),
                KnowledgeChunkSummary(
                    id: UUID(),
                    title: "英语长难句拆解",
                    sourceTitle: "考研英语阅读精讲",
                    errorFrequency: 3
                ),
                KnowledgeChunkSummary(
                    id: UUID(),
                    title: "概率分布理解",
                    sourceTitle: "机器学习基础笔记",
                    errorFrequency: 2
                )
            ]
        )
    }
}

private extension AppViewModel {
    static func restoreSourceReaderMode() -> SourceReaderMode {
        guard
            let rawValue = UserDefaults.standard.string(forKey: sourceReaderModeDefaultsKey),
            let mode = SourceReaderMode(rawValue: rawValue)
        else {
            return .readingPDF
        }

        return mode
    }
}

private extension String {
    var containsChineseCharacters: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
    }

    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
