import CoreGraphics
import Foundation

enum SourceReaderMode: String, Codable, CaseIterable, Identifiable {
    case readingPDF = "reading_pdf"
    case originalPDFAligned = "original_pdf_aligned"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readingPDF:
            return "阅读版 PDF"
        case .originalPDFAligned:
            return "原始 PDF 优先"
        }
    }

    var subtitle: String {
        switch self {
        case .readingPDF:
            return "自动排版成更适合学习的 PDF，句子高亮和点击最稳定。"
        case .originalPDFAligned:
            return "优先显示用户原始 PDF，并尽量把句子高亮对齐到原页位置；无法对齐时自动回退。"
        }
    }
}

struct Source: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let title: String
    let sourceType: String
    let language: String
    let isEnglish: Bool
    let cleanedText: String
    let pageCount: Int
    let segmentCount: Int
    let sentenceCount: Int
    let outlineNodeCount: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case sourceType = "source_type"
        case language
        case isEnglish = "is_english"
        case cleanedText = "cleaned_text"
        case pageCount = "page_count"
        case segmentCount = "segment_count"
        case sentenceCount = "sentence_count"
        case outlineNodeCount = "outline_node_count"
    }
}

struct Segment: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let sourceID: String
    let index: Int
    let text: String
    let anchorLabel: String
    let page: Int?
    let sentenceIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceID = "source_id"
        case index
        case text
        case anchorLabel = "anchor_label"
        case page
        case sentenceIDs = "sentence_ids"
    }
}

struct SentenceRegion: Codable, Equatable, Hashable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(rect: CGRect) {
        self.init(
            x: Double(rect.minX),
            y: Double(rect.minY),
            width: Double(rect.width),
            height: Double(rect.height)
        )
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

enum SentenceGeometrySource: String, Codable, Equatable, Hashable {
    case ocr = "ocr"
    case pdfText = "pdf_text"
}

struct SentenceWordRegion: Codable, Equatable, Hashable {
    let token: String
    let region: SentenceRegion

    private enum CodingKeys: String, CodingKey {
        case token
        case region
    }
}

struct SentenceGeometry: Codable, Equatable, Hashable {
    let page: Int
    let regions: [SentenceRegion]
    let wordRegions: [SentenceWordRegion]
    let source: SentenceGeometrySource

    private enum CodingKeys: String, CodingKey {
        case page
        case regions
        case wordRegions = "word_regions"
        case source
    }

    init(
        page: Int,
        regions: [SentenceRegion],
        wordRegions: [SentenceWordRegion] = [],
        source: SentenceGeometrySource
    ) {
        self.page = page
        self.regions = regions
        self.wordRegions = wordRegions
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        page = try container.decode(Int.self, forKey: .page)
        regions = try container.decode([SentenceRegion].self, forKey: .regions)
        wordRegions = try container.decodeIfPresent([SentenceWordRegion].self, forKey: .wordRegions) ?? []
        source = try container.decode(SentenceGeometrySource.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(page, forKey: .page)
        try container.encode(regions, forKey: .regions)
        if !wordRegions.isEmpty {
            try container.encode(wordRegions, forKey: .wordRegions)
        }
        try container.encode(source, forKey: .source)
    }

    var boundingRect: CGRect {
        regions
            .map(\.cgRect)
            .reduce(into: CGRect.null) { partialResult, rect in
                partialResult = partialResult.union(rect)
            }
    }
}

struct Sentence: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let sourceID: String
    let segmentID: String
    let index: Int
    let localIndex: Int
    let text: String
    let anchorLabel: String
    let page: Int?
    let geometry: SentenceGeometry?

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceID = "source_id"
        case segmentID = "segment_id"
        case index
        case localIndex = "local_index"
        case text
        case anchorLabel = "anchor_label"
        case page
        case geometry
    }

    init(
        id: String,
        sourceID: String,
        segmentID: String,
        index: Int,
        localIndex: Int,
        text: String,
        anchorLabel: String,
        page: Int?,
        geometry: SentenceGeometry? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.segmentID = segmentID
        self.index = index
        self.localIndex = localIndex
        self.text = text
        self.anchorLabel = anchorLabel
        self.page = page
        self.geometry = geometry
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sourceID = try container.decode(String.self, forKey: .sourceID)
        segmentID = try container.decode(String.self, forKey: .segmentID)
        index = try container.decode(Int.self, forKey: .index)
        localIndex = try container.decode(Int.self, forKey: .localIndex)
        text = try container.decode(String.self, forKey: .text)
        anchorLabel = try container.decode(String.self, forKey: .anchorLabel)
        page = try container.decodeIfPresent(Int.self, forKey: .page)
        geometry = try container.decodeIfPresent(SentenceGeometry.self, forKey: .geometry)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sourceID, forKey: .sourceID)
        try container.encode(segmentID, forKey: .segmentID)
        try container.encode(index, forKey: .index)
        try container.encode(localIndex, forKey: .localIndex)
        try container.encode(text, forKey: .text)
        try container.encode(anchorLabel, forKey: .anchorLabel)
        try container.encodeIfPresent(page, forKey: .page)
        try container.encodeIfPresent(geometry, forKey: .geometry)
    }

    func withGeometry(_ geometry: SentenceGeometry?) -> Sentence {
        Sentence(
            id: id,
            sourceID: sourceID,
            segmentID: segmentID,
            index: index,
            localIndex: localIndex,
            text: text,
            anchorLabel: anchorLabel,
            page: page,
            geometry: geometry
        )
    }
}

enum PedagogicalNodeType: String, Codable, CaseIterable, Hashable {
    case passageRoot = "passage_root"
    case paragraphTheme = "paragraph_theme"
    case teachingFocus = "teaching_focus"
    case supportingSentence = "supporting_sentence"
    case questionLink = "question_link"
    case vocabularySupport = "vocabulary_support"
    case metaInstruction = "meta_instruction"
    case answerKey = "answer_key"

    var displayName: String {
        switch self {
        case .passageRoot: return "文章主题"
        case .paragraphTheme: return "段落主旨"
        case .teachingFocus: return "教学重点"
        case .supportingSentence: return "支撑句"
        case .questionLink: return "题目联动"
        case .vocabularySupport: return "词汇支持"
        case .metaInstruction: return "讲义说明"
        case .answerKey: return "答案区"
        }
    }
}

enum ParagraphArgumentRole: String, Codable, CaseIterable, Hashable {
    case background = "background"
    case support = "support"
    case objection = "objection"
    case transition = "transition"
    case evidence = "evidence"
    case conclusion = "conclusion"

    var displayName: String {
        switch self {
        case .background: return "背景铺垫"
        case .support: return "观点支撑"
        case .objection: return "转折/异议"
        case .transition: return "承接推进"
        case .evidence: return "举例论据"
        case .conclusion: return "结论收束"
        }
    }
}

struct ProfessorGrammarPoint: Codable, Equatable, Hashable {
    let name: String
    let explanation: String
}

struct ProfessorVocabularyItem: Codable, Equatable, Hashable {
    let term: String
    let meaning: String
}

struct ProfessorSentenceAnalysis: Codable, Equatable, Hashable {
    let originalSentence: String
    let naturalChineseMeaning: String
    let sentenceCore: String
    let chunkBreakdown: [String]
    let grammarPoints: [ProfessorGrammarPoint]
    let vocabularyInContext: [ProfessorVocabularyItem]
    let misreadPoints: [String]
    let examRewritePoints: [String]
    let simplifiedEnglish: String
    let miniExercise: String?
    let hierarchyRebuild: [String]
    let syntacticVariation: String?
    let evidenceType: String?
    let isAIGenerated: Bool

    private enum CodingKeys: String, CodingKey {
        case originalSentence = "original_sentence"
        case naturalChineseMeaning = "natural_chinese_meaning"
        case sentenceCore = "sentence_core"
        case chunkBreakdown = "chunk_breakdown"
        case grammarPoints = "grammar_points"
        case vocabularyInContext = "vocabulary_in_context"
        case misreadPoints = "misread_points"
        case examRewritePoints = "exam_rewrite_points"
        case simplifiedEnglish = "simplified_english"
        case miniExercise = "mini_exercise"
        case hierarchyRebuild = "hierarchy_rebuild"
        case syntacticVariation = "syntactic_variation"
        case evidenceType = "evidence_type"
        case isAIGenerated = "is_ai_generated"
    }

    init(
        originalSentence: String,
        naturalChineseMeaning: String,
        sentenceCore: String,
        chunkBreakdown: [String],
        grammarPoints: [ProfessorGrammarPoint],
        vocabularyInContext: [ProfessorVocabularyItem],
        misreadPoints: [String],
        examRewritePoints: [String],
        simplifiedEnglish: String,
        miniExercise: String?,
        hierarchyRebuild: [String],
        syntacticVariation: String?,
        evidenceType: String? = nil,
        isAIGenerated: Bool = false
    ) {
        self.originalSentence = originalSentence
        self.naturalChineseMeaning = naturalChineseMeaning
        self.sentenceCore = sentenceCore
        self.chunkBreakdown = chunkBreakdown
        self.grammarPoints = grammarPoints
        self.vocabularyInContext = vocabularyInContext
        self.misreadPoints = misreadPoints
        self.examRewritePoints = examRewritePoints
        self.simplifiedEnglish = simplifiedEnglish
        self.miniExercise = miniExercise
        self.hierarchyRebuild = hierarchyRebuild
        self.syntacticVariation = syntacticVariation
        self.evidenceType = evidenceType
        self.isAIGenerated = isAIGenerated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        originalSentence = try container.decode(String.self, forKey: .originalSentence)
        naturalChineseMeaning = try container.decode(String.self, forKey: .naturalChineseMeaning)
        sentenceCore = try container.decode(String.self, forKey: .sentenceCore)
        chunkBreakdown = try container.decode([String].self, forKey: .chunkBreakdown)
        grammarPoints = try container.decode([ProfessorGrammarPoint].self, forKey: .grammarPoints)
        vocabularyInContext = try container.decode([ProfessorVocabularyItem].self, forKey: .vocabularyInContext)
        misreadPoints = try container.decode([String].self, forKey: .misreadPoints)
        examRewritePoints = try container.decode([String].self, forKey: .examRewritePoints)
        simplifiedEnglish = try container.decode(String.self, forKey: .simplifiedEnglish)
        miniExercise = try container.decodeIfPresent(String.self, forKey: .miniExercise)
        hierarchyRebuild = try container.decode([String].self, forKey: .hierarchyRebuild)
        syntacticVariation = try container.decodeIfPresent(String.self, forKey: .syntacticVariation)
        evidenceType = try container.decodeIfPresent(String.self, forKey: .evidenceType)
        isAIGenerated = try container.decodeIfPresent(Bool.self, forKey: .isAIGenerated) ?? false
    }
}

struct ProfessorSentenceCard: Identifiable, Equatable, Hashable {
    let id: String
    let sentenceID: String
    let segmentID: String
    let isKeySentence: Bool
    let analysis: ProfessorSentenceAnalysis
}

struct ParagraphTeachingCard: Identifiable, Equatable, Hashable {
    let id: String
    let segmentID: String
    let paragraphIndex: Int
    let anchorLabel: String
    let theme: String
    let argumentRole: ParagraphArgumentRole
    let coreSentenceID: String?
    let keywords: [String]
    let relationToPrevious: String
    let examValue: String
    let teachingFocuses: [String]
    let studentBlindSpot: String?
    let isAIGenerated: Bool

    init(
        id: String,
        segmentID: String,
        paragraphIndex: Int,
        anchorLabel: String,
        theme: String,
        argumentRole: ParagraphArgumentRole,
        coreSentenceID: String?,
        keywords: [String],
        relationToPrevious: String,
        examValue: String,
        teachingFocuses: [String],
        studentBlindSpot: String? = nil,
        isAIGenerated: Bool = false
    ) {
        self.id = id
        self.segmentID = segmentID
        self.paragraphIndex = paragraphIndex
        self.anchorLabel = anchorLabel
        self.theme = theme
        self.argumentRole = argumentRole
        self.coreSentenceID = coreSentenceID
        self.keywords = keywords
        self.relationToPrevious = relationToPrevious
        self.examValue = examValue
        self.teachingFocuses = teachingFocuses
        self.studentBlindSpot = studentBlindSpot
        self.isAIGenerated = isAIGenerated
    }
}

struct QuestionEvidenceLink: Identifiable, Equatable, Hashable {
    let id: String
    let questionText: String
    let supportParagraphIDs: [String]
    let supportingSentenceIDs: [String]
    let paraphraseEvidence: [String]
    let trapType: String
    let answerKeySnippet: String?
}

struct PassageOverview: Equatable, Hashable {
    let articleTheme: String
    let authorCoreQuestion: String
    let progressionPath: String
    let paragraphFunctionMap: [String]
    let syntaxHighlights: [String]
    let readingTraps: [String]
    let vocabularyHighlights: [String]
}

struct DocumentZoningSummary: Equatable, Hashable {
    let passageParagraphCount: Int
    let questionParagraphCount: Int
    let answerKeyParagraphCount: Int
    let vocabularyParagraphCount: Int
    let metaInstructionParagraphCount: Int
}

struct OutlineAnchor: Codable, Equatable, Hashable {
    let segmentID: String?
    let sentenceID: String?
    let page: Int?
    let label: String

    private enum CodingKeys: String, CodingKey {
        case segmentID = "segment_id"
        case sentenceID = "sentence_id"
        case page
        case label
    }
}

struct OutlineNode: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let sourceID: String
    let parentID: String?
    let depth: Int
    let order: Int
    let nodeType: PedagogicalNodeType
    let title: String
    let summary: String
    let anchor: OutlineAnchor
    let sourceSegmentIDs: [String]
    let sourceSentenceIDs: [String]
    let children: [OutlineNode]

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceID = "source_id"
        case parentID = "parent_id"
        case depth
        case order
        case nodeType = "node_type"
        case title
        case summary
        case anchor
        case sourceSegmentIDs = "source_segment_ids"
        case sourceSentenceIDs = "source_sentence_ids"
        case children
    }

    init(
        id: String,
        sourceID: String,
        parentID: String?,
        depth: Int,
        order: Int,
        nodeType: PedagogicalNodeType = .teachingFocus,
        title: String,
        summary: String,
        anchor: OutlineAnchor,
        sourceSegmentIDs: [String],
        sourceSentenceIDs: [String],
        children: [OutlineNode]
    ) {
        self.id = id
        self.sourceID = sourceID
        self.parentID = parentID
        self.depth = depth
        self.order = order
        self.nodeType = nodeType
        self.title = title
        self.summary = summary
        self.anchor = anchor
        self.sourceSegmentIDs = sourceSegmentIDs
        self.sourceSentenceIDs = sourceSentenceIDs
        self.children = children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sourceID = try container.decode(String.self, forKey: .sourceID)
        parentID = try container.decodeIfPresent(String.self, forKey: .parentID)
        depth = try container.decode(Int.self, forKey: .depth)
        order = try container.decode(Int.self, forKey: .order)
        nodeType = try container.decodeIfPresent(PedagogicalNodeType.self, forKey: .nodeType) ?? .teachingFocus
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        anchor = try container.decode(OutlineAnchor.self, forKey: .anchor)
        sourceSegmentIDs = try container.decodeIfPresent([String].self, forKey: .sourceSegmentIDs) ?? []
        sourceSentenceIDs = try container.decodeIfPresent([String].self, forKey: .sourceSentenceIDs) ?? []
        children = try container.decodeIfPresent([OutlineNode].self, forKey: .children) ?? []
    }

    var primarySegmentID: String? {
        sourceSegmentIDs.first ?? anchor.segmentID
    }

    var primarySentenceID: String? {
        sourceSentenceIDs.first ?? anchor.sentenceID
    }
}

struct StructuredSourceBundle: Equatable {
    let source: Source
    let segments: [Segment]
    let sentences: [Sentence]
    let outline: [OutlineNode]
    let passageOverview: PassageOverview?
    let paragraphTeachingCards: [ParagraphTeachingCard]
    let professorSentenceCards: [ProfessorSentenceCard]
    let questionLinks: [QuestionEvidenceLink]
    let zoningSummary: DocumentZoningSummary

    // 缓存索引（惰性构建，一次性）
    private let _cachedFlatNodes: [OutlineNode]
    private let _sentenceIndex: [String: Sentence]
    private let _segmentIndex: [String: Segment]
    private let _sentenceCardIndex: [String: ProfessorSentenceCard]
    private let _paragraphCardIndex: [String: ParagraphTeachingCard]

    static func == (lhs: StructuredSourceBundle, rhs: StructuredSourceBundle) -> Bool {
        lhs.source == rhs.source &&
        lhs.segments == rhs.segments &&
        lhs.sentences == rhs.sentences &&
        lhs.outline == rhs.outline &&
        lhs.passageOverview == rhs.passageOverview &&
        lhs.paragraphTeachingCards == rhs.paragraphTeachingCards &&
        lhs.professorSentenceCards == rhs.professorSentenceCards &&
        lhs.questionLinks == rhs.questionLinks &&
        lhs.zoningSummary == rhs.zoningSummary
    }

    init(
        source: Source,
        segments: [Segment],
        sentences: [Sentence],
        outline: [OutlineNode],
        passageOverview: PassageOverview? = nil,
        paragraphTeachingCards: [ParagraphTeachingCard] = [],
        professorSentenceCards: [ProfessorSentenceCard] = [],
        questionLinks: [QuestionEvidenceLink] = [],
        zoningSummary: DocumentZoningSummary = DocumentZoningSummary(
            passageParagraphCount: 0,
            questionParagraphCount: 0,
            answerKeyParagraphCount: 0,
            vocabularyParagraphCount: 0,
            metaInstructionParagraphCount: 0
        )
    ) {
        self.source = source
        self.segments = segments
        self.sentences = sentences
        self.outline = outline
        self.passageOverview = passageOverview
        self.paragraphTeachingCards = paragraphTeachingCards
        self.professorSentenceCards = professorSentenceCards
        self.questionLinks = questionLinks
        self.zoningSummary = zoningSummary
        self._cachedFlatNodes = Self.flattenSafe(nodes: outline, maxDepth: 20)
        self._sentenceIndex = Dictionary(sentences.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self._segmentIndex = Dictionary(segments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self._sentenceCardIndex = Dictionary(professorSentenceCards.map { ($0.sentenceID, $0) }, uniquingKeysWith: { first, _ in first })
        self._paragraphCardIndex = Dictionary(paragraphTeachingCards.map { ($0.segmentID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func sentences(in segment: Segment) -> [Sentence] {
        let sentenceIDSet = Set(segment.sentenceIDs)
        return sentences.filter { sentenceIDSet.contains($0.id) }
    }

    func sentence(id: String?) -> Sentence? {
        guard let id else { return nil }
        return _sentenceIndex[id]
    }

    func segment(id: String?) -> Segment? {
        guard let id else { return nil }
        return _segmentIndex[id]
    }

    func sentenceCard(id: String?) -> ProfessorSentenceCard? {
        guard let id else { return nil }
        return _sentenceCardIndex[id]
    }

    func paragraphCard(forSegmentID id: String?) -> ParagraphTeachingCard? {
        guard let id else { return nil }
        return _paragraphCardIndex[id]
    }

    func outlineNode(id: String?) -> OutlineNode? {
        guard let id else { return nil }
        return _cachedFlatNodes.first { $0.id == id }
    }

    func bestOutlineNode(forSentenceID id: String?) -> OutlineNode? {
        guard let id else { return nil }

        return _cachedFlatNodes
            .filter { node in
                node.sourceSentenceIDs.contains(id) || node.anchor.sentenceID == id
            }
            .sorted {
                if $0.depth != $1.depth {
                    return $0.depth > $1.depth
                }

                return $0.coverageSpan < $1.coverageSpan
            }
            .first
    }

    func bestOutlineNode(forSegmentID id: String?) -> OutlineNode? {
        guard let id else { return nil }

        return _cachedFlatNodes
            .filter { node in
                node.sourceSegmentIDs.contains(id) || node.anchor.segmentID == id
            }
            .sorted {
                if $0.depth != $1.depth {
                    return $0.depth > $1.depth
                }

                return $0.coverageSpan < $1.coverageSpan
            }
            .first
    }

    func ancestorNodeIDs(for nodeID: String?) -> [String] {
        guard let nodeID else { return [] }

        let parentMap = Dictionary(uniqueKeysWithValues: _cachedFlatNodes.map { ($0.id, $0.parentID) })
        var results: [String] = []
        var current = nodeID
        var visited: Set<String> = []

        while let parentID = parentMap[current], let unwrappedParentID = parentID {
            guard !visited.contains(unwrappedParentID) else { break }
            results.append(unwrappedParentID)
            visited.insert(unwrappedParentID)
            current = unwrappedParentID
        }

        return results
    }

    func outlineNodes(forSegmentIDs ids: Set<String>) -> [OutlineNode] {
        guard !ids.isEmpty else { return [] }
        return _cachedFlatNodes.filter { node in
            !Set(node.sourceSegmentIDs).isDisjoint(with: ids) ||
            (node.anchor.segmentID.map { ids.contains($0) } ?? false)
        }
    }

    func flattenedOutlineNodes() -> [OutlineNode] {
        _cachedFlatNodes
    }

    /// 用 AI 生成的教授级分析内容替换启发式占位内容
    func enrichedWithAIAnalysis(
        overview: PassageOverview?,
        paragraphCards: [ParagraphTeachingCard],
        sentenceCards: [ProfessorSentenceCard]
    ) -> StructuredSourceBundle {
        // 段落卡：用 AI 版本替换匹配的段落，保留未覆盖的
        let aiParagraphIndex = Dictionary(
            paragraphCards.map { ($0.segmentID, $0) },
            uniquingKeysWith: { _, new in new }
        )
        let mergedParagraphCards = self.paragraphTeachingCards.map { existing in
            aiParagraphIndex[existing.segmentID] ?? existing
        }

        // 句子卡：用 AI 版本替换匹配的句子，保留未覆盖的
        let aiSentenceIndex = Dictionary(
            sentenceCards.map { ($0.sentenceID, $0) },
            uniquingKeysWith: { _, new in new }
        )
        let mergedSentenceCards = self.professorSentenceCards.map { existing in
            aiSentenceIndex[existing.sentenceID] ?? existing
        }

        // 重建教学树大纲，使用更新后的段落卡和句子卡内容
        let sentencesBySegment = Dictionary(
            grouping: sentences,
            by: { $0.segmentID }
        )
        let sentenceCardIndex = Dictionary(
            mergedSentenceCards.map { ($0.sentenceID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let mergedOutline = Self.rebuildOutline(
            sourceID: source.id,
            segments: segments,
            sentencesBySegment: sentencesBySegment,
            paragraphCards: mergedParagraphCards,
            sentenceCardIndex: sentenceCardIndex,
            overview: overview ?? passageOverview
        )

        return StructuredSourceBundle(
            source: source,
            segments: segments,
            sentences: sentences,
            outline: mergedOutline,
            passageOverview: overview ?? passageOverview,
            paragraphTeachingCards: mergedParagraphCards,
            professorSentenceCards: mergedSentenceCards,
            questionLinks: questionLinks,
            zoningSummary: zoningSummary
        )
    }

    /// 重建教学大纲树
    private static func rebuildOutline(
        sourceID: String,
        segments: [Segment],
        sentencesBySegment: [String: [Sentence]],
        paragraphCards: [ParagraphTeachingCard],
        sentenceCardIndex: [String: ProfessorSentenceCard],
        overview: PassageOverview?
    ) -> [OutlineNode] {
        let paragraphNodes: [OutlineNode] = paragraphCards.map { card in
            let sentences = sentencesBySegment[card.segmentID] ?? []
            let supportingSentenceNodes = sentences
                .filter { sentence in
                    sentence.id == card.coreSentenceID || sentenceCardIndex[sentence.id]?.isKeySentence == true
                }
                .prefix(2)
                .map { sentence in
                    OutlineNode(
                        id: "support_\(sentence.id)",
                        sourceID: sourceID,
                        parentID: "para_\(card.segmentID)",
                        depth: 2,
                        order: sentence.index,
                        nodeType: .supportingSentence,
                        title: String(sentence.text.prefix(60)),
                        summary: sentenceCardIndex[sentence.id]?.analysis.sentenceCore ?? sentence.text,
                        anchor: OutlineAnchor(
                            segmentID: sentence.segmentID,
                            sentenceID: sentence.id,
                            page: sentence.page,
                            label: sentence.anchorLabel
                        ),
                        sourceSegmentIDs: [sentence.segmentID],
                        sourceSentenceIDs: [sentence.id],
                        children: []
                    )
                }

            let focusSummary = card.teachingFocuses.joined(separator: "；")
                .isEmpty ? card.examValue : card.teachingFocuses.joined(separator: "；")
            let focusNode = OutlineNode(
                id: "focus_\(card.segmentID)",
                sourceID: sourceID,
                parentID: "para_\(card.segmentID)",
                depth: 2,
                order: card.paragraphIndex * 10,
                nodeType: .teachingFocus,
                title: "教学重点",
                summary: focusSummary,
                anchor: OutlineAnchor(
                    segmentID: card.segmentID,
                    sentenceID: card.coreSentenceID,
                    page: sentences.first?.page,
                    label: card.anchorLabel
                ),
                sourceSegmentIDs: [card.segmentID],
                sourceSentenceIDs: card.coreSentenceID.map { [$0] } ?? [],
                children: []
            )

            return OutlineNode(
                id: "para_\(card.segmentID)",
                sourceID: sourceID,
                parentID: "passage_root",
                depth: 1,
                order: card.paragraphIndex,
                nodeType: .paragraphTheme,
                title: "第\(card.paragraphIndex + 1)段：\(card.argumentRole.displayName)",
                summary: card.theme,
                anchor: OutlineAnchor(
                    segmentID: card.segmentID,
                    sentenceID: card.coreSentenceID,
                    page: sentences.first?.page,
                    label: card.anchorLabel
                ),
                sourceSegmentIDs: [card.segmentID],
                sourceSentenceIDs: sentences.map(\.id),
                children: [focusNode] + supportingSentenceNodes
            )
        }

        let rootNode = OutlineNode(
            id: "passage_root",
            sourceID: sourceID,
            parentID: nil,
            depth: 0,
            order: 0,
            nodeType: .passageRoot,
            title: "文章主题",
            summary: overview?.progressionPath ?? "正文教学树",
            anchor: OutlineAnchor(
                segmentID: segments.first?.id,
                sentenceID: nil,
                page: segments.first?.page,
                label: segments.first?.anchorLabel ?? "原文"
            ),
            sourceSegmentIDs: segments.map(\.id),
            sourceSentenceIDs: [],
            children: paragraphNodes
        )

        return [rootNode]
    }

    /// 带深度限制的安全展平，防止循环引用导致无限递归
    private static func flattenSafe(nodes: [OutlineNode], maxDepth: Int, currentDepth: Int = 0) -> [OutlineNode] {
        guard currentDepth < maxDepth else { return [] }
        return nodes.flatMap { [$0] + flattenSafe(nodes: $0.children, maxDepth: maxDepth, currentDepth: currentDepth + 1) }
    }
}

private extension OutlineNode {
    var coverageSpan: Int {
        Swift.max(Swift.max(sourceSentenceIDs.count, sourceSegmentIDs.count), 1)
    }
}

struct SentenceBreadcrumb: Equatable {
    let pageLabel: String
    let sentenceLabel: String
    let outlineLabel: String
    let trailLabels: [String]
}

struct OutlineNodeAnchorItem: Identifiable, Equatable, Hashable {
    let id: String
    let label: String
    let sentenceID: String?
    let segmentID: String?
    let previewText: String
}

struct OutlineNodeKeyword: Identifiable, Equatable, Hashable {
    let id: String
    let term: String
    let hint: String
}

struct OutlineNodeDetailSnapshot: Identifiable, Equatable {
    let id: String
    let levelLabel: String
    let title: String
    let summary: String
    let anchorItems: [OutlineNodeAnchorItem]
    let keySentences: [Sentence]
    let keywords: [OutlineNodeKeyword]
}

struct WordExplanationEntry: Identifiable, Equatable, Hashable {
    let id: String
    let term: String
    let phonetic: String
    let partOfSpeech: String
    let sentenceMeaning: String
    let commonMeanings: [String]
    let collocations: [String]
    let examples: [String]
    let sourceSentence: Sentence?
}

struct StudyNote: Identifiable, Equatable, Hashable {
    let id: UUID
    let sourceDocumentID: UUID
    let title: String
    let body: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        sourceDocumentID: UUID,
        title: String,
        body: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceDocumentID = sourceDocumentID
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }
}

struct ReviewWorkbenchProgress: Equatable {
    let documentID: UUID
    var lastVisitedAt: Date
    var lastSentenceID: String?
    var lastSegmentID: String?
    var lastOutlineNodeID: String?
    var learnedSentenceIDs: Set<String>
    var lastAnchorLabel: String

    init(
        documentID: UUID,
        lastVisitedAt: Date = Date(),
        lastSentenceID: String? = nil,
        lastSegmentID: String? = nil,
        lastOutlineNodeID: String? = nil,
        learnedSentenceIDs: Set<String> = [],
        lastAnchorLabel: String = "尚未开始"
    ) {
        self.documentID = documentID
        self.lastVisitedAt = lastVisitedAt
        self.lastSentenceID = lastSentenceID
        self.lastSegmentID = lastSegmentID
        self.lastOutlineNodeID = lastOutlineNodeID
        self.learnedSentenceIDs = learnedSentenceIDs
        self.lastAnchorLabel = lastAnchorLabel
    }
}
