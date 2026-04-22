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

struct SourceHygieneSnapshot: Codable, Equatable, Hashable {
    let score: Double
    let reversedRepaired: Bool
    let hasMixedContamination: Bool
    let chineseRatio: Double
    let englishRatio: Double
    let ocrConfidence: Double
    let flags: [String]

    private enum CodingKeys: String, CodingKey {
        case score
        case reversedRepaired = "reversed_repaired"
        case hasMixedContamination = "has_mixed_contamination"
        case chineseRatio = "chinese_ratio"
        case englishRatio = "english_ratio"
        case ocrConfidence = "ocr_confidence"
        case flags
    }

    var isReliableForTeachingMainline: Bool {
        score >= 0.58 &&
        !hasMixedContamination &&
        englishRatio >= 0.42 &&
        !flags.contains("polluted") &&
        !flags.contains("chinese_explanation") &&
        !flags.contains("bilingual_note") &&
        !flags.contains("bilingual_annotation") &&
        !flags.contains("instructional") &&
        !flags.contains("auxiliary_source") &&
        !flags.contains("noise")
    }

    static let clean = SourceHygieneSnapshot(
        score: 1,
        reversedRepaired: false,
        hasMixedContamination: false,
        chineseRatio: 0,
        englishRatio: 1,
        ocrConfidence: 1,
        flags: []
    )
}

struct Segment: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let sourceID: String
    let index: Int
    let text: String
    let anchorLabel: String
    let page: Int?
    let sentenceIDs: [String]
    let provenance: NodeProvenance
    let hygiene: SourceHygieneSnapshot

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceID = "source_id"
        case index
        case text
        case anchorLabel = "anchor_label"
        case page
        case sentenceIDs = "sentence_ids"
        case provenance
        case hygiene
    }

    init(
        id: String,
        sourceID: String,
        index: Int,
        text: String,
        anchorLabel: String,
        page: Int?,
        sentenceIDs: [String],
        provenance: NodeProvenance = .unknown,
        hygiene: SourceHygieneSnapshot = .clean
    ) {
        self.id = id
        self.sourceID = sourceID
        self.index = index
        self.text = text
        self.anchorLabel = anchorLabel
        self.page = page
        self.sentenceIDs = sentenceIDs
        self.provenance = provenance
        self.hygiene = hygiene
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sourceID = try container.decode(String.self, forKey: .sourceID)
        index = try container.decode(Int.self, forKey: .index)
        text = try container.decode(String.self, forKey: .text)
        anchorLabel = try container.decode(String.self, forKey: .anchorLabel)
        page = try container.decodeIfPresent(Int.self, forKey: .page)
        sentenceIDs = try container.decodeIfPresent([String].self, forKey: .sentenceIDs) ?? []
        provenance = try container.decodeIfPresent(NodeProvenance.self, forKey: .provenance)
            ?? NodeProvenance(
                sourceSegmentID: id,
                sourceSentenceID: sentenceIDs.first,
                sourceKind: .unknown,
                consistencyScore: 0.5
            )
        hygiene = try container.decodeIfPresent(SourceHygieneSnapshot.self, forKey: .hygiene) ?? .clean
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sourceID, forKey: .sourceID)
        try container.encode(index, forKey: .index)
        try container.encode(text, forKey: .text)
        try container.encode(anchorLabel, forKey: .anchorLabel)
        try container.encodeIfPresent(page, forKey: .page)
        try container.encode(sentenceIDs, forKey: .sentenceIDs)
        try container.encode(provenance, forKey: .provenance)
        try container.encode(hygiene, forKey: .hygiene)
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
    let provenance: NodeProvenance
    let hygiene: SourceHygieneSnapshot

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
        case provenance
        case hygiene
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
        geometry: SentenceGeometry? = nil,
        provenance: NodeProvenance = .unknown,
        hygiene: SourceHygieneSnapshot = .clean
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
        self.provenance = provenance
        self.hygiene = hygiene
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
        provenance = try container.decodeIfPresent(NodeProvenance.self, forKey: .provenance)
            ?? NodeProvenance(
                sourceSegmentID: segmentID,
                sourceSentenceID: id,
                sourceKind: .unknown,
                consistencyScore: 0.5
            )
        hygiene = try container.decodeIfPresent(SourceHygieneSnapshot.self, forKey: .hygiene) ?? .clean
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
        try container.encode(provenance, forKey: .provenance)
        try container.encode(hygiene, forKey: .hygiene)
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
            geometry: geometry,
            provenance: provenance,
            hygiene: hygiene
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

    var teachingDescription: String {
        switch self {
        case .background:
            return "这一段先交代理解前提，重点不是直接给答案，而是限定后文讨论从什么背景出发。"
        case .support:
            return "这一段在替核心判断补理由、补限制或补展开，做题时要把细节重新挂回主判断。"
        case .objection:
            return "这一段先让步或摆出异议，再转回真正立场；最容易把让步内容误当作者结论。"
        case .transition:
            return "这一段的关键是论证换挡，帮助你看清作者是从背景走向判断，还是从观点转到例证。"
        case .evidence:
            return "这一段主要提供事实、例子或数据。考试常把例子本身和它支撑的判断混写成干扰项。"
        case .conclusion:
            return "这一段负责收束判断，最值得用于主旨题、标题题和作者态度题。"
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

struct ProfessorCoreSkeleton: Codable, Equatable, Hashable {
    let subject: String
    let predicate: String
    let complementOrObject: String

    private enum CodingKeys: String, CodingKey {
        case subject
        case predicate
        case complementOrObject = "complement_or_object"
    }

    var rendered: String {
        let subjectPart = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let predicatePart = predicate.trimmingCharacters(in: .whitespacesAndNewlines)
        let complementPart = complementOrObject.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = []
        if !subjectPart.isEmpty { parts.append("主语：\(subjectPart)") }
        if !predicatePart.isEmpty { parts.append("谓语：\(predicatePart)") }
        if !complementPart.isEmpty { parts.append("核心补足：\(complementPart)") }
        return parts.joined(separator: "｜")
    }

    var isMeaningful: Bool {
        !trimmedOrEmpty(subject).isEmpty || !trimmedOrEmpty(predicate).isEmpty || !trimmedOrEmpty(complementOrObject).isEmpty
    }
}

struct ProfessorChunkLayer: Codable, Equatable, Hashable {
    let text: String
    let role: String
    let attachesTo: String
    let gloss: String

    private enum CodingKeys: String, CodingKey {
        case text
        case role
        case attachesTo = "attaches_to"
        case gloss
    }

    var rendered: String {
        let rolePart = role.trimmingCharacters(in: .whitespacesAndNewlines)
        let textPart = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachesPart = attachesTo.trimmingCharacters(in: .whitespacesAndNewlines)
        let glossPart = gloss.trimmingCharacters(in: .whitespacesAndNewlines)

        var base = rolePart.isEmpty ? textPart : "\(rolePart)：\(textPart)"
        if !attachesPart.isEmpty && attachesPart != "主句主干" && attachesPart != "核心信息" {
            base += "｜挂到：\(attachesPart)"
        }
        if !glossPart.isEmpty {
            base += "｜\(glossPart)"
        }
        return base
    }
}

struct ProfessorChunkLayerDisplayItem: Equatable, Hashable {
    let text: String
    let role: String
    let attachesTo: String
    let gloss: String
}

struct ProfessorGrammarFocusDisplayItem: Equatable, Hashable {
    let title: String
    let whatItIs: String
    let functionInSentence: String
    let whyItMatters: String
    let exampleEN: String?
    let terminologyTag: String?
}

struct ProfessorGrammarFocus: Codable, Equatable, Hashable {
    let phenomenon: String
    let function: String
    let whyItMatters: String
    let titleZh: String
    let explanationZh: String
    let whyItMattersZh: String
    let exampleEn: String

    private enum CodingKeys: String, CodingKey {
        case phenomenon
        case function
        case whyItMatters = "why_it_matters"
        case titleZh = "title_zh"
        case explanationZh = "explanation_zh"
        case whyItMattersZh = "why_it_matters_zh"
        case exampleEn = "example_en"
    }

    init(
        phenomenon: String,
        function: String,
        whyItMatters: String,
        titleZh: String = "",
        explanationZh: String = "",
        whyItMattersZh: String = "",
        exampleEn: String = ""
    ) {
        self.phenomenon = phenomenon
        self.function = function
        self.whyItMatters = whyItMatters
        self.titleZh = titleZh
        self.explanationZh = explanationZh
        self.whyItMattersZh = whyItMattersZh
        self.exampleEn = exampleEn
    }

    var rendered: String {
        let item = displayItem

        var parts: [String] = []
        if !item.title.isEmpty { parts.append(item.title) }
        if !item.whatItIs.isEmpty { parts.append("这是什么：\(item.whatItIs)") }
        if !item.functionInSentence.isEmpty { parts.append("在本句里：\(item.functionInSentence)") }
        if !item.whyItMatters.isEmpty { parts.append("为什么重要：\(item.whyItMatters)") }
        return parts.joined(separator: "｜")
    }

    var displayItem: ProfessorGrammarFocusDisplayItem {
        localizedGrammarFocusDisplayItem(
            phenomenon: phenomenon,
            function: function,
            whyItMatters: whyItMatters,
            titleZh: titleZh,
            explanationZh: explanationZh,
            whyItMattersZh: whyItMattersZh,
            exampleEn: exampleEn
        )
    }
}

struct SentenceRolePresentation: Equatable, Hashable {
    let label: String
    let description: String
}

func professorSentenceRolePresentation(for raw: String?) -> SentenceRolePresentation? {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty else {
        return nil
    }

    switch raw {
    case "core_claim":
        return SentenceRolePresentation(
            label: "核心判断句",
            description: "这句承担作者真正要成立的判断。做题时优先盯主干，不要被前后修饰和背景信息带偏。"
        )
    case "supporting_evidence":
        return SentenceRolePresentation(
            label: "支撑证据句",
            description: "这句的任务是替上一层判断补事实、补例证或补论据。不能只记细节，要回到它支撑的观点。"
        )
    case "background_info":
        return SentenceRolePresentation(
            label: "背景信息句",
            description: "这句主要交代场景、前提或历史背景，不是作者最后要你选的结论。"
        )
    case "counter_argument":
        return SentenceRolePresentation(
            label: "让步/反方句",
            description: "这句常先承认一种看法，真正立场多半落在它之后，最容易把让步内容错当答案。"
        )
    case "transition_signal":
        return SentenceRolePresentation(
            label: "推进信号句",
            description: "这句的价值在于提示作者怎样换挡，适合判断段落关系、论证方向和结构推进。"
        )
    case "conclusion_marker":
        return SentenceRolePresentation(
            label: "结论收束句",
            description: "这句在回收前文信息，常是主旨题、标题题和作者态度题最该回看的位置。"
        )
    default:
        return SentenceRolePresentation(label: "句子定位", description: raw)
    }
}

struct ProfessorSentenceAnalysis: Codable, Equatable, Hashable {
    let originalSentence: String
    let sentenceFunction: String
    let coreSkeleton: ProfessorCoreSkeleton?
    let chunkLayers: [ProfessorChunkLayer]
    let grammarFocus: [ProfessorGrammarFocus]
    let faithfulTranslation: String
    let teachingInterpretation: String
    let naturalChineseMeaning: String
    let sentenceCore: String
    let chunkBreakdown: [String]
    let grammarPoints: [ProfessorGrammarPoint]
    let vocabularyInContext: [ProfessorVocabularyItem]
    let misreadPoints: [String]
    let examRewritePoints: [String]
    let misreadingTraps: [String]
    let examParaphraseRoutes: [String]
    let simplifiedEnglish: String
    let simplerRewrite: String
    let simplerRewriteTranslation: String
    let miniExercise: String?
    let miniCheck: String?
    let hierarchyRebuild: [String]
    let syntacticVariation: String?
    let evidenceType: String?
    let isAIGenerated: Bool

    private enum CodingKeys: String, CodingKey {
        case originalSentence = "original_sentence"
        case sentenceFunction = "sentence_function"
        case coreSkeleton = "core_skeleton"
        case chunkLayers = "chunk_layers"
        case grammarFocus = "grammar_focus"
        case faithfulTranslation = "faithful_translation"
        case teachingInterpretation = "teaching_interpretation"
        case naturalChineseMeaning = "natural_chinese_meaning"
        case sentenceCore = "sentence_core"
        case chunkBreakdown = "chunk_breakdown"
        case grammarPoints = "grammar_points"
        case vocabularyInContext = "vocabulary_in_context"
        case misreadPoints = "misread_points"
        case examRewritePoints = "exam_rewrite_points"
        case misreadingTraps = "misreading_traps"
        case examParaphraseRoutes = "exam_paraphrase_routes"
        case simplifiedEnglish = "simplified_english"
        case simplerRewrite = "simpler_rewrite"
        case simplerRewriteTranslation = "simpler_rewrite_translation"
        case miniExercise = "mini_exercise"
        case miniCheck = "mini_check"
        case hierarchyRebuild = "hierarchy_rebuild"
        case syntacticVariation = "syntactic_variation"
        case evidenceType = "evidence_type"
        case isAIGenerated = "is_ai_generated"
    }

    init(
        originalSentence: String,
        sentenceFunction: String = "",
        coreSkeleton: ProfessorCoreSkeleton? = nil,
        chunkLayers: [ProfessorChunkLayer] = [],
        grammarFocus: [ProfessorGrammarFocus] = [],
        faithfulTranslation: String = "",
        teachingInterpretation: String = "",
        naturalChineseMeaning: String,
        sentenceCore: String,
        chunkBreakdown: [String],
        grammarPoints: [ProfessorGrammarPoint],
        vocabularyInContext: [ProfessorVocabularyItem],
        misreadPoints: [String],
        examRewritePoints: [String],
        misreadingTraps: [String] = [],
        examParaphraseRoutes: [String] = [],
        simplifiedEnglish: String,
        simplerRewrite: String = "",
        simplerRewriteTranslation: String = "",
        miniExercise: String?,
        miniCheck: String? = nil,
        hierarchyRebuild: [String],
        syntacticVariation: String?,
        evidenceType: String? = nil,
        isAIGenerated: Bool = false
    ) {
        self.originalSentence = originalSentence
        self.sentenceFunction = sentenceFunction
        self.coreSkeleton = coreSkeleton
        self.chunkLayers = chunkLayers
        self.grammarFocus = grammarFocus
        let normalizedFaithfulTranslation = trimmedOrEmpty(faithfulTranslation)
        let normalizedTeachingInterpretation = trimmedOrEmpty(teachingInterpretation)
        let normalizedLegacyMeaning = trimmedOrEmpty(naturalChineseMeaning)
        let reliableFaithful = reliableFaithfulTranslation(normalizedFaithfulTranslation)
        let reliableLegacyFaithful = reliableFaithfulTranslation(normalizedLegacyMeaning)
        let explicitTeachingInterpretation = purifiedChineseExplanation(normalizedTeachingInterpretation)
        let explicitLegacyMeaning = purifiedChineseExplanation(normalizedLegacyMeaning)

        self.faithfulTranslation = !reliableFaithful.isEmpty
            ? reliableFaithful
            : reliableLegacyFaithful
        self.teachingInterpretation = !explicitTeachingInterpretation.isEmpty
            ? explicitTeachingInterpretation
            : (!explicitLegacyMeaning.isEmpty ? explicitLegacyMeaning : "")
        self.naturalChineseMeaning = !explicitLegacyMeaning.isEmpty
            ? explicitLegacyMeaning
            : (!self.teachingInterpretation.isEmpty ? self.teachingInterpretation : self.faithfulTranslation)
        self.sentenceCore = sentenceCore
        self.chunkBreakdown = chunkBreakdown
        self.grammarPoints = grammarPoints
        self.vocabularyInContext = vocabularyInContext
        self.misreadPoints = misreadPoints
        self.examRewritePoints = examRewritePoints
        self.misreadingTraps = misreadingTraps.isEmpty ? misreadPoints : misreadingTraps
        self.examParaphraseRoutes = examParaphraseRoutes.isEmpty ? examRewritePoints : examParaphraseRoutes
        self.simplifiedEnglish = simplifiedEnglish
        self.simplerRewrite = simplerRewrite.isEmpty ? simplifiedEnglish : simplerRewrite
        self.simplerRewriteTranslation = trimmedOrEmpty(simplerRewriteTranslation)
        self.miniExercise = miniExercise
        self.miniCheck = (miniCheck?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? miniCheck : miniExercise
        self.hierarchyRebuild = hierarchyRebuild
        self.syntacticVariation = syntacticVariation
        self.evidenceType = evidenceType
        self.isAIGenerated = isAIGenerated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        originalSentence = try container.decode(String.self, forKey: .originalSentence)
        sentenceFunction = try container.decodeIfPresent(String.self, forKey: .sentenceFunction) ?? ""
        coreSkeleton = try container.decodeIfPresent(ProfessorCoreSkeleton.self, forKey: .coreSkeleton)
        chunkLayers = try container.decodeIfPresent([ProfessorChunkLayer].self, forKey: .chunkLayers) ?? []
        grammarFocus = try container.decodeIfPresent([ProfessorGrammarFocus].self, forKey: .grammarFocus) ?? []
        let decodedFaithfulTranslation = try container.decodeIfPresent(String.self, forKey: .faithfulTranslation) ?? ""
        let decodedTeachingInterpretation = try container.decodeIfPresent(String.self, forKey: .teachingInterpretation) ?? ""
        let decodedLegacyMeaning = try container.decodeIfPresent(String.self, forKey: .naturalChineseMeaning) ?? ""
        let explicitFaithful = reliableFaithfulTranslation(decodedFaithfulTranslation)
        let explicitLegacyFaithful = reliableFaithfulTranslation(decodedLegacyMeaning)
        faithfulTranslation = !explicitFaithful.isEmpty ? explicitFaithful : explicitLegacyFaithful

        let explicitTeaching = purifiedChineseExplanation(decodedTeachingInterpretation)
        let explicitLegacyMeaning = purifiedChineseExplanation(decodedLegacyMeaning)
        teachingInterpretation = !explicitTeaching.isEmpty
            ? explicitTeaching
            : explicitLegacyMeaning
        naturalChineseMeaning = !explicitLegacyMeaning.isEmpty ? explicitLegacyMeaning : teachingInterpretation
        sentenceCore = try container.decode(String.self, forKey: .sentenceCore)
        chunkBreakdown = try container.decode([String].self, forKey: .chunkBreakdown)
        grammarPoints = try container.decode([ProfessorGrammarPoint].self, forKey: .grammarPoints)
        vocabularyInContext = try container.decode([ProfessorVocabularyItem].self, forKey: .vocabularyInContext)
        misreadPoints = try container.decode([String].self, forKey: .misreadPoints)
        examRewritePoints = try container.decode([String].self, forKey: .examRewritePoints)
        misreadingTraps = try container.decodeIfPresent([String].self, forKey: .misreadingTraps) ?? misreadPoints
        examParaphraseRoutes = try container.decodeIfPresent([String].self, forKey: .examParaphraseRoutes) ?? examRewritePoints
        simplifiedEnglish = try container.decode(String.self, forKey: .simplifiedEnglish)
        simplerRewrite = try container.decodeIfPresent(String.self, forKey: .simplerRewrite) ?? simplifiedEnglish
        simplerRewriteTranslation = try container.decodeIfPresent(String.self, forKey: .simplerRewriteTranslation) ?? ""
        miniExercise = try container.decodeIfPresent(String.self, forKey: .miniExercise)
        miniCheck = try container.decodeIfPresent(String.self, forKey: .miniCheck) ?? miniExercise
        hierarchyRebuild = try container.decode([String].self, forKey: .hierarchyRebuild)
        syntacticVariation = try container.decodeIfPresent(String.self, forKey: .syntacticVariation)
        evidenceType = try container.decodeIfPresent(String.self, forKey: .evidenceType)
        isAIGenerated = try container.decodeIfPresent(Bool.self, forKey: .isAIGenerated) ?? false
    }

    var renderedSentenceFunction: String {
        let explicit = purifiedChineseDisplayText(sentenceFunction)
        if !explicit.isEmpty { return explicit }
        if let role = professorSentenceRolePresentation(for: evidenceType) {
            return "\(role.label)：\(role.description)"
        }
        return ""
    }

    var renderedSentenceCore: String {
        if let skeleton = displayedStableCoreSkeleton {
            let rendered = skeleton.rendered.trimmingCharacters(in: .whitespacesAndNewlines)
            if !rendered.isEmpty { return rendered }
        }

        let normalized = preferredPedagogicalText(sentenceCore, fallback: "", kind: .sentenceCore)
        if !normalized.isEmpty && !containsLegacyCoreSkeletonMarkup(sentenceCore) {
            return normalized
        }

        return "当前结果里主干拆分不稳定，建议先看语块切分和教学解读。"
    }

    var renderedFaithfulTranslation: String {
        let explicit = reliableFaithfulTranslation(faithfulTranslation)
        if !explicit.isEmpty { return explicit }

        let fallback = reliableFaithfulTranslation(naturalChineseMeaning)
        if !fallback.isEmpty { return fallback }

        return ""
    }

    var renderedTeachingInterpretation: String {
        let explicit = purifiedChineseExplanation(teachingInterpretation)
        let faithful = renderedFaithfulTranslation
        if !explicit.isEmpty, normalizedChineseComparisonKey(explicit) != normalizedChineseComparisonKey(faithful) {
            return explicit
        }

        let legacy = purifiedChineseExplanation(naturalChineseMeaning)
        if !legacy.isEmpty, normalizedChineseComparisonKey(legacy) != normalizedChineseComparisonKey(faithful) {
            return legacy
        }

        return pedagogicalTeachingInterpretationFallback(
            sentenceFunction: renderedSentenceFunction,
            coreSkeleton: displayedStableCoreSkeleton,
            chunkLayers: displayedChunkLayers,
            faithfulTranslation: faithful
        )
    }

    var needsLocalRepair: Bool {
        let missingTeaching = !hasReliableTeachingInterpretation
        let unstableCore = displayedStableCoreSkeleton == nil &&
            renderedSentenceCore.contains("当前结果里主干拆分不稳定")
        return missingTeaching || unstableCore
    }

    var hasReliableFaithfulTranslation: Bool {
        !renderedFaithfulTranslation.isEmpty
    }

    var hasReliableTeachingInterpretation: Bool {
        let explicit = purifiedChineseExplanation(teachingInterpretation)
        guard !explicit.isEmpty else { return false }
        let faithful = renderedFaithfulTranslation
        if faithful.isEmpty { return true }
        return normalizedChineseComparisonKey(explicit) != normalizedChineseComparisonKey(faithful)
    }

    func isCompatible(with sentenceText: String) -> Bool {
        let normalizedOriginal = normalizedEnglishSentenceComparisonKey(originalSentence)
        let normalizedSentence = normalizedEnglishSentenceComparisonKey(sentenceText)

        guard !normalizedSentence.isEmpty else { return true }
        guard !normalizedOriginal.isEmpty else { return true }
        if normalizedOriginal == normalizedSentence { return true }

        return englishSentenceTokenOverlap(normalizedOriginal, normalizedSentence) >= 0.58
    }

    func shouldPreferSentenceExplain(for sentenceText: String) -> Bool {
        !isCompatible(with: sentenceText) ||
        !hasReliableFaithfulTranslation ||
        !hasReliableTeachingInterpretation ||
        !isAIGenerated
    }

    var renderedChunkLayers: [String] {
        if !chunkLayers.isEmpty {
            return chunkLayers.map(\.rendered)
        }
        return chunkBreakdown
    }

    var displayedCoreSkeleton: ProfessorCoreSkeleton {
        displayedStableCoreSkeleton ?? ProfessorCoreSkeleton(
            subject: "",
            predicate: "",
            complementOrObject: ""
        )
    }

    var displayedStableCoreSkeleton: ProfessorCoreSkeleton? {
        if let normalizedExplicit = normalizeCompatibleCoreSkeleton(from: coreSkeleton) {
            return normalizedExplicit
        }
        return parseCompatibleCoreSkeleton(from: sentenceCore)
    }

    var displayedChunkLayers: [ProfessorChunkLayerDisplayItem] {
        if !chunkLayers.isEmpty {
            return chunkLayers.map {
                ProfessorChunkLayerDisplayItem(
                    text: $0.text,
                    role: $0.role,
                    attachesTo: $0.attachesTo,
                    gloss: $0.gloss
                )
            }
        }

        return chunkBreakdown.compactMap { item in
            let trimmed = trimmedOrEmpty(item)
            guard !trimmed.isEmpty else { return nil }

            let parts = trimmed.components(separatedBy: "｜")
            let head = parts.first.map(trimmedOrEmpty) ?? ""
            let gloss = parts.dropFirst().map(trimmedOrEmpty).filter { !$0.isEmpty }.joined(separator: "｜")

            if let split = head.range(of: "：") {
                let role = trimmedOrEmpty(String(head[..<split.lowerBound]))
                let text = trimmedOrEmpty(String(head[split.upperBound...]))
                return ProfessorChunkLayerDisplayItem(
                    text: text,
                    role: role,
                    attachesTo: "",
                    gloss: gloss
                )
            }

            return ProfessorChunkLayerDisplayItem(
                text: head,
                role: "语块",
                attachesTo: "",
                gloss: gloss
            )
        }
    }

    var renderedGrammarFocus: [String] {
        displayedGrammarFocusCards.map {
            [
                $0.title,
                $0.whatItIs.isEmpty ? "" : "这是什么：\($0.whatItIs)",
                $0.functionInSentence.isEmpty ? "" : "在本句里：\($0.functionInSentence)",
                $0.whyItMatters.isEmpty ? "" : "为什么重要：\($0.whyItMatters)"
            ]
                .filter { !$0.isEmpty }
                .joined(separator: "｜")
        }
    }

    var displayedGrammarFocusCards: [ProfessorGrammarFocusDisplayItem] {
        if !grammarFocus.isEmpty {
            return grammarFocus
                .map(\.displayItem)
                .filter { !$0.title.isEmpty || !$0.whatItIs.isEmpty || !$0.functionInSentence.isEmpty || !$0.whyItMatters.isEmpty }
                .uniqued(on: { "\($0.title)|\($0.whatItIs)|\($0.functionInSentence)|\($0.whyItMatters)" })
                .prefix(3)
                .map { $0 }
        }

        return grammarPoints.compactMap { point in
            let item = localizedGrammarFocusDisplayItem(
                phenomenon: point.name,
                function: point.explanation,
                whyItMatters: pedagogicalWhyGrammarPointMatters(name: point.name),
                titleZh: "",
                explanationZh: "",
                whyItMattersZh: "",
                exampleEn: ""
            )
            return item.title.isEmpty && item.whatItIs.isEmpty && item.functionInSentence.isEmpty && item.whyItMatters.isEmpty ? nil : item
        }
        .uniqued(on: { "\($0.title)|\($0.whatItIs)|\($0.functionInSentence)|\($0.whyItMatters)" })
        .prefix(3)
        .map { $0 }
    }

    var renderedMisreadingTraps: [String] {
        purifiedChineseList(!misreadingTraps.isEmpty ? misreadingTraps : misreadPoints, limit: 4)
    }

    var renderedExamParaphraseRoutes: [String] {
        purifiedChineseList(!examParaphraseRoutes.isEmpty ? examParaphraseRoutes : examRewritePoints, limit: 4)
    }

    var renderedSimplerRewrite: String {
        let trimmed = simplerRewrite.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? simplifiedEnglish : trimmed
    }

    var renderedSimplerRewriteTranslation: String {
        let explicit = purifiedChineseExplanation(simplerRewriteTranslation)
        if !explicit.isEmpty { return explicit }

        let faithful = renderedFaithfulTranslation
        let rewrite = renderedSimplerRewrite.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rewrite.isEmpty else { return "" }

        var parts: [String] = []
        if !faithful.isEmpty {
            parts.append("这条改写仍在说：\(faithful)")
        }

        let roles = displayedChunkLayers.map(\.role)
        if roles.contains(where: { $0.contains("前置") || $0.contains("条件") || $0.contains("让步") || $0.contains("后置") }) {
            parts.append("它保留了原句主干判断，把外围框架和修饰层压缩成更直接的主句表达。")
        } else {
            parts.append("它保留原意，只把句法改成更直接的主谓表达。")
        }

        if let skeleton = displayedStableCoreSkeleton, skeleton.isMeaningful {
            let stableCore = truncatedPedagogicalText(skeleton.rendered, limit: 22)
            if !stableCore.isEmpty {
                parts.append("主干没有变，抓住“\(stableCore)”就能看出改写没有换义。")
            }
        }

        return parts.joined(separator: " ")
    }

    var renderedMiniCheck: String? {
        let trimmed = miniCheck?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? miniExercise : trimmed
    }
}

struct ProfessorSentenceCard: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let sentenceID: String
    let segmentID: String
    let isKeySentence: Bool
    let analysis: ProfessorSentenceAnalysis
}

struct ParagraphTeachingCard: Identifiable, Codable, Equatable, Hashable {
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

struct QuestionEvidenceLink: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let questionText: String
    let supportParagraphIDs: [String]
    let supportingSentenceIDs: [String]
    let paraphraseEvidence: [String]
    let trapType: String
    let answerKeySnippet: String?
}

struct PassageOverview: Codable, Equatable, Hashable {
    let articleTheme: String
    let authorCoreQuestion: String
    let progressionPath: String
    let likelyQuestionTypes: [String]
    let logicPitfalls: [String]
    let paragraphFunctionMap: [String]
    let syntaxHighlights: [String]
    let readingTraps: [String]
    let vocabularyHighlights: [String]
}

extension ParagraphTeachingCard {
    var displayedTheme: String {
        preferredPedagogicalText(theme, fallback: "", kind: .paragraphTheme)
    }

    var displayedRelationToPrevious: String {
        preferredPedagogicalText(relationToPrevious, fallback: "", kind: .relation)
    }

    var displayedExamValue: String {
        preferredPedagogicalText(examValue, fallback: "", kind: .examValue)
    }

    var displayedTeachingFocuses: [String] {
        purifiedChineseList(teachingFocuses, limit: 4)
    }

    var displayedStudentBlindSpot: String? {
        let purified = purifiedChineseDisplayText(studentBlindSpot ?? "")
        return purified.isEmpty ? nil : purified
    }
}

extension PassageOverview {
    var displayedArticleTheme: String {
        preferredPedagogicalText(articleTheme, fallback: "", kind: .overviewTheme)
    }

    var displayedAuthorCoreQuestion: String {
        preferredPedagogicalText(authorCoreQuestion, fallback: "", kind: .overviewQuestion)
    }

    var displayedProgressionPath: String {
        preferredPedagogicalText(progressionPath, fallback: "", kind: .overviewProgression)
    }

    var displayedLikelyQuestionTypes: [String] {
        purifiedChineseList(likelyQuestionTypes, limit: 5)
    }

    var displayedLogicPitfalls: [String] {
        purifiedChineseList(logicPitfalls, limit: 5)
    }

    var displayedParagraphFunctionMap: [String] {
        purifiedChineseList(paragraphFunctionMap, limit: 8)
    }

    var displayedSyntaxHighlights: [String] {
        purifiedChineseList(syntaxHighlights, limit: 5)
    }

    var displayedReadingTraps: [String] {
        purifiedChineseList(readingTraps, limit: 5)
    }
}

private enum PedagogicalTextKind {
    case faithfulTranslation
    case teachingInterpretation
    case naturalMeaning
    case sentenceCore
    case paragraphTheme
    case overviewTheme
    case overviewQuestion
    case overviewProgression
    case relation
    case examValue
    case generic
}

private func trimmedOrEmpty(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func isChineseDominant(_ value: String) -> Bool {
    let trimmed = trimmedOrEmpty(value)
    guard !trimmed.isEmpty else { return false }

    let chineseCount = trimmed.unicodeScalars.filter { scalar in
        scalar.value >= 0x4E00 && scalar.value <= 0x9FFF
    }.count
    let latinCount = trimmed.unicodeScalars.filter { scalar in
        (scalar.value >= 0x41 && scalar.value <= 0x5A) ||
        (scalar.value >= 0x61 && scalar.value <= 0x7A)
    }.count

    if chineseCount == 0 { return false }
    return chineseCount >= max(8, latinCount * 2)
}

private func purifiedChineseDisplayText(_ value: String) -> String {
    let trimmed = trimmedOrEmpty(value)
    guard !trimmed.isEmpty else { return "" }

    if let range = trimmed.range(of: "：") ?? trimmed.range(of: ":") {
        let head = trimmedOrEmpty(String(trimmed[..<range.lowerBound]))
        let body = purifiedChineseExplanation(String(trimmed[range.upperBound...]))
        if !body.isEmpty {
            return head.isEmpty ? body : "\(head)：\(body)"
        }
    }

    return purifiedChineseExplanation(trimmed)
}

private func purifiedChineseSentences(from value: String) -> [String] {
    let normalized = trimmedOrEmpty(value)
    guard !normalized.isEmpty else { return [] }

    return normalized
        .components(separatedBy: CharacterSet(charactersIn: "\n"))
        .flatMap { line in
            line.split(whereSeparator: { "。！？；".contains($0) }).map(String.init)
        }
        .map(trimmedOrEmpty)
        .filter { segment in
            guard !segment.isEmpty else { return false }
            let chineseCount = segment.unicodeScalars.filter { scalar in
                scalar.value >= 0x4E00 && scalar.value <= 0x9FFF
            }.count
            let latinCount = segment.unicodeScalars.filter { scalar in
                (scalar.value >= 0x41 && scalar.value <= 0x5A) ||
                (scalar.value >= 0x61 && scalar.value <= 0x7A)
            }.count
            return chineseCount >= 8 && chineseCount > latinCount
        }
}

private func purifiedChineseExplanation(_ value: String) -> String {
    let trimmed = trimmedOrEmpty(value)
    guard !trimmed.isEmpty else { return "" }
    let sanitized = sanitizedPedagogicalChinese(trimmed)
    if isChineseDominant(sanitized), !containsChinesePedagogicalLeakage(sanitized) {
        return sanitized
    }

    let recovered = purifiedChineseSentences(from: sanitized)
    guard !recovered.isEmpty else { return "" }
    return recovered.joined(separator: "。")
}

private func reliableFaithfulTranslation(_ value: String) -> String {
    let explicit = purifiedChineseExplanation(value)
    guard !explicit.isEmpty else { return "" }
    guard looksLikeFaithfulTranslation(explicit) else { return "" }
    return explicit
}

private func looksLikeFaithfulTranslation(_ value: String) -> Bool {
    let normalized = purifiedChineseExplanation(value)
    guard !normalized.isEmpty, isChineseDominant(normalized) else { return false }

    let rejectMarkers = [
        "句意可以理解为",
        "这句话真正要",
        "真正要抓",
        "重点在于",
        "先抓",
        "不要把",
        "阅读时",
        "做题时",
        "放在本段里",
        "老师会",
        "板书时",
        "其余信息都在",
        "主句主干"
    ]

    return !rejectMarkers.contains { normalized.contains($0) }
}

private func normalizedEnglishSentenceComparisonKey(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: #"[^\p{Latin}0-9]+"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func englishSentenceTokenOverlap(_ lhs: String, _ rhs: String) -> Double {
    let lhsTokens = Set(lhs.split(separator: " ").map(String.init).filter { $0.count >= 2 })
    let rhsTokens = Set(rhs.split(separator: " ").map(String.init).filter { $0.count >= 2 })
    guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 1 }
    let overlap = lhsTokens.intersection(rhsTokens).count
    return Double(overlap) / Double(max(lhsTokens.count, rhsTokens.count))
}

private func purifiedChineseList(_ values: [String], limit: Int) -> [String] {
    var ordered: [String] = []
    var seen: Set<String> = []

    for value in values {
        let normalized = purifiedChineseDisplayText(value)
        guard !normalized.isEmpty else { continue }
        let key = normalized.lowercased()
        guard seen.insert(key).inserted else { continue }
        ordered.append(normalized)
        if ordered.count >= limit {
            break
        }
    }

    return ordered
}

private func normalizedChineseComparisonKey(_ value: String) -> String {
    purifiedChineseExplanation(value)
        .lowercased()
        .replacingOccurrences(of: #"[^\p{Han}a-z0-9]+"#, with: "", options: .regularExpression)
}

private func pedagogicalTeachingInterpretationFallback(
    sentenceFunction: String,
    coreSkeleton: ProfessorCoreSkeleton?,
    chunkLayers: [ProfessorChunkLayerDisplayItem],
    faithfulTranslation: String
) -> String {
    var parts: [String] = []
    let functionHead = purifiedChineseDisplayText(sentenceFunction)
    if !functionHead.isEmpty {
        parts.append("老师先会把这句当成“\(functionHead)”来看。")
    }

    if let coreSkeleton, coreSkeleton.isMeaningful {
        let stableCore = [
            coreSkeleton.subject.isEmpty ? nil : "主语“\(coreSkeleton.subject)”",
            coreSkeleton.predicate.isEmpty ? nil : "谓语“\(coreSkeleton.predicate)”",
            coreSkeleton.complementOrObject.isEmpty ? nil : "核心补足“\(coreSkeleton.complementOrObject)”"
        ]
        .compactMap { $0 }
        .joined(separator: "、")
        if !stableCore.isEmpty {
            parts.append("板书时先锁定 \(stableCore)，其余信息都往这个主干上挂。")
        }
    }

    let roleHints = chunkLayers.map(\.role)
    if roleHints.contains(where: { $0.contains("前置") || $0.contains("条件") || $0.contains("让步") }) {
        parts.append("读的时候不要被句首框架带走，真正判断一般落在后面的主句主干。")
    } else if roleHints.contains(where: { $0.contains("后置") || $0.contains("补充") }) {
        parts.append("其余语块主要是在补限定范围和修饰关系，不要把枝叶误抬成主干。")
    }

    let faithful = purifiedChineseExplanation(faithfulTranslation)
    if !faithful.isEmpty {
        parts.append("先把“\(faithful)”这个基本意思抓稳，再回头分层看修饰关系。")
    }

    return parts.joined(separator: " ")
}

private struct LocalizedGrammarTemplate {
    let title: String
    let whatItIs: String
    let functionInSentence: String
    let whyItMatters: String
}

private func localizedGrammarTemplate(for raw: String) -> LocalizedGrammarTemplate? {
    let lower = raw.lowercased()
    let normalized = trimmedOrEmpty(raw)

    if normalized.contains("时间状语从句") || lower.contains("temporal clause") || lower.contains("adverbial clause") || lower.contains("after") || lower.contains("before") || lower.contains("when ") || lower.contains("once") {
        return LocalizedGrammarTemplate(
            title: "时间状语从句",
            whatItIs: "这是用来交代时间背景的状语从句，说明事情在什么时间条件下发生。",
            functionInSentence: "它在这句里先搭时间背景，再把真正要成立的判断交给主句。",
            whyItMatters: "时间框架一旦错挂，学生就会把背景信息错当核心判断。"
        )
    }
    if normalized.contains("压缩定语从句") || normalized.contains("省略关系从句") || lower.contains("reduced relative clause") {
        return LocalizedGrammarTemplate(
            title: "压缩定语从句",
            whatItIs: "这是把完整关系从句压缩成更短修饰块的写法，本质上仍在补前面名词的信息。",
            functionInSentence: "它在这里负责压缩对前面名词的限定说明，不是在另起一个主句。",
            whyItMatters: "如果把这层误当成主干谓语，就会把整句结构拆坏。"
        )
    }
    if normalized.contains("宾语从句") || lower.contains("object clause") {
        return LocalizedGrammarTemplate(
            title: "宾语从句",
            whatItIs: "这是跟在谓语后面、充当核心内容的从句，常回答“认为什么”“说明什么”。",
            functionInSentence: "它在这句里承接前面的谓语，真正承载作者要表达的内容对象。",
            whyItMatters: "宾语从句一旦挂错，学生会把说法来源和作者判断混在一起。"
        )
    }
    if normalized.contains("情态动词") || lower.contains("modal verb") || lower.contains("might") || lower.contains("may ") || lower.contains("could") || lower.contains("would") || lower.contains("should") {
        return LocalizedGrammarTemplate(
            title: "情态动词",
            whatItIs: "情态动词本身不增加新事实，而是在调节语气强弱，表示可能、推测、限制或建议。",
            functionInSentence: "它在这句里控制作者判断的把握程度，不让语气走成绝对断言。",
            whyItMatters: "情态一旦忽略，题目里的态度强弱和作者把握程度就会读偏。"
        )
    }
    if normalized.contains("后置修饰") || lower.contains("postpositive modifier") {
        return LocalizedGrammarTemplate(
            title: "后置修饰",
            whatItIs: "后置修饰是放在中心名词后面补信息的结构，读的时候要先找清楚它修饰谁。",
            functionInSentence: "它在这里负责给前面的名词补限定范围，不是在推进新的主句判断。",
            whyItMatters: "后置修饰挂错对象，是长难句里最常见的误读来源。"
        )
    }
    if normalized.contains("定语从句") || lower.contains("relative clause") {
        return LocalizedGrammarTemplate(
            title: "定语从句",
            whatItIs: "定语从句是在给前面的名词补限定信息，告诉你“哪一个”“什么样的”。",
            functionInSentence: "它在这里继续限定前面的名词，不是作者另起一层新的判断。",
            whyItMatters: "修饰对象一旦看错，枝叶就会被误当成主干。"
        )
    }
    if normalized.contains("非谓语") || lower.contains("non-finite") || lower.contains("participle") || lower.contains("infinitive") {
        return LocalizedGrammarTemplate(
            title: "非谓语结构",
            whatItIs: "非谓语是把完整动作压缩成信息块的写法，常用来补目的、原因、伴随或修饰关系。",
            functionInSentence: "它在这句里负责压缩附加信息，不能被当成新的完整谓语。",
            whyItMatters: "把非谓语误判成主句谓语，会直接拆错主干。"
        )
    }
    if normalized.contains("被动") || lower.contains("passive voice") {
        return LocalizedGrammarTemplate(
            title: "被动结构",
            whatItIs: "被动结构会把动作承受者顶到前面，真正的施动者则可能后移甚至省略。",
            functionInSentence: "它在这句里改变了信息出场顺序，强调的是谁被作用而不是谁发出动作。",
            whyItMatters: "如果被动方向没看清，因果和细节关系很容易整体反过来。"
        )
    }
    if normalized.contains("否定") || lower.contains("negation") {
        return LocalizedGrammarTemplate(
            title: "否定范围",
            whatItIs: "否定范围指的是否定词到底压在哪一层信息上，而不是看到 not 就结束。",
            functionInSentence: "它在这句里限制判断成立的范围，决定作者否定的是动作、比较项还是限定条件。",
            whyItMatters: "否定范围错一层，题目选项往往会整句反向。"
        )
    }
    if normalized.contains("让步") || lower.contains("concession") {
        return LocalizedGrammarTemplate(
            title: "让步框架",
            whatItIs: "让步框架会先承认一个条件、反方声音或看似成立的情况，再回到自己的真正判断。",
            functionInSentence: "它在这里先让一步，真正想成立的判断通常落在后面的主句。",
            whyItMatters: "学生最容易把让步内容错当成作者最终立场。"
        )
    }
    if normalized.contains("前置框架") || lower.contains("framing phrase") {
        return LocalizedGrammarTemplate(
            title: "前置框架",
            whatItIs: "前置框架是先放在句首的背景交代层，用来限定主句判断成立的场景、时间或角度。",
            functionInSentence: "它在这里先定阅读坐标，再把真正判断交给后面的主句。",
            whyItMatters: "如果把前置框架误读成主干，整句重点就会跑偏。"
        )
    }
    if normalized.contains("条件") || lower.contains("conditional") {
        return LocalizedGrammarTemplate(
            title: "条件框架",
            whatItIs: "条件框架只是在交代结论成立所需要的前提，并不是作者已经直接成立的判断。",
            functionInSentence: "它在这里负责限定判断成立的前提，真正结论仍在主句主干里。",
            whyItMatters: "如果条件和结论混读，细节题和推断题都会失焦。"
        )
    }
    if normalized.contains("同位语从句") || lower.contains("appositive clause") {
        return LocalizedGrammarTemplate(
            title: "同位语从句",
            whatItIs: "同位语从句是在解释前面抽象名词具体内容的从句，常跟在 idea、fact、claim 一类词后面。",
            functionInSentence: "它在这里补出前面抽象名词的真实内容，不是另起一个平行判断。",
            whyItMatters: "如果把它误读成主句，就会把作者观点和被解释内容混成一层。"
        )
    }

    return nil
}

private func normalizeMixedGrammarChinese(_ text: String) -> String {
    var normalized = trimmedOrEmpty(text)
    guard !normalized.isEmpty else { return "" }

    let replacements: [(String, String)] = [
        ("temporal clause", "时间状语从句"),
        ("time clause", "时间状语从句"),
        ("reduced relative clause", "压缩定语从句"),
        ("relative clause", "定语从句"),
        ("object clause", "宾语从句"),
        ("modal verb", "情态动词"),
        ("postpositive modifier", "后置修饰"),
        ("passive voice", "被动结构"),
        ("concessive frame", "让步框架"),
        ("framing phrase", "前置框架"),
        ("conditional frame", "条件框架"),
        ("participle phrase", "分词短语"),
        ("infinitive phrase", "不定式短语"),
        ("non-finite", "非谓语结构"),
        ("adverbial clause", "状语从句"),
        ("subject clause", "主语从句"),
        ("predicative clause", "表语从句"),
        ("appositive clause", "同位语从句")
    ]

    for (raw, zh) in replacements {
        normalized = normalized.replacingOccurrences(of: raw, with: zh, options: [.caseInsensitive, .regularExpression])
    }

    normalized = normalized.replacingOccurrences(
        of: #"([A-Za-z]+)\s*引导的"#,
        with: #"由原句里的“$1 …”引出的"#,
        options: .regularExpression
    )

    return normalized
}

private func sanitizedPedagogicalChinese(_ text: String) -> String {
    var normalized = normalizeMixedGrammarChinese(text)
    normalized = normalized.replacingOccurrences(
        of: #"\[[A-Za-z_\s-]+:\s*[^\]]+\]"#,
        with: "",
        options: .regularExpression
    )
    normalized = normalized.replacingOccurrences(
        of: #"\s+"#,
        with: " ",
        options: .regularExpression
    )
    return trimmedOrEmpty(normalized)
}

private func containsChinesePedagogicalLeakage(_ text: String) -> Bool {
    let trimmed = trimmedOrEmpty(text)
    guard !trimmed.isEmpty else { return false }
    if containsLegacyCoreSkeletonMarkup(trimmed) { return true }
    if trimmed.range(of: #"[A-Za-z]{2,}\s*引导"#, options: .regularExpression) != nil { return true }
    return trimmed.range(of: #"[A-Za-z]{8,}(?:\s+[A-Za-z]{2,})+"#, options: .regularExpression) != nil
}

private func looksLikeMixedGrammarExplanation(_ text: String) -> Bool {
    let trimmed = sanitizedPedagogicalChinese(text)
    guard !trimmed.isEmpty else { return false }
    let chineseCount = (trimmed.matchingStrings(pattern: #"[\u4e00-\u9fff]"#)).count
    let latinCount = (trimmed.matchingStrings(pattern: #"[A-Za-z]"#)).count
    if latinCount == 0 { return false }
    if trimmed.range(of: #"[A-Za-z]{2,}\s+[A-Za-z]{2,}"#, options: .regularExpression) != nil { return true }
    if trimmed.range(of: #"[A-Za-z]{2,}\s*引导"#, options: .regularExpression) != nil { return true }
    return latinCount > 6 && chineseCount < latinCount * 2
}

private func grammarTerminologyTag(from raw: String, exampleEn: String) -> String? {
    let explicitExample = trimmedOrEmpty(exampleEn)
    if !explicitExample.isEmpty {
        return explicitExample.count > 22 ? String(explicitExample.prefix(22)) + "…" : explicitExample
    }

    let normalized = trimmedOrEmpty(raw)
    guard normalized.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil else { return nil }

    let matches = normalized.matchingStrings(pattern: #"[A-Za-z][A-Za-z\s_-]{1,24}"#)
    let first = matches.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !first.isEmpty else { return nil }
    return first.count > 22 ? String(first.prefix(22)) + "…" : first
}

private func defaultGrammarWhatItIs(title: String) -> String {
    if let template = localizedGrammarTemplate(for: title) {
        return template.whatItIs
    }
    return "这是本句里最值得先抓的一层结构，读的时候要把它放回主干关系里理解。"
}

private func defaultGrammarFunctionDescription(title: String) -> String {
    if let template = localizedGrammarTemplate(for: title) {
        return template.functionInSentence
    }
    return "它在这句里负责限定主干、补充范围或交代背景，不能脱离主句单独理解。"
}

private func looksLikeGrammarRoleDescription(_ text: String) -> Bool {
    let trimmed = trimmedOrEmpty(text)
    guard !trimmed.isEmpty else { return false }
    return trimmed.contains("本句") || trimmed.contains("在这句") || trimmed.contains("先抓") || trimmed.contains("不要把") || trimmed.contains("阅读时")
}

private func localizedGrammarFocusDisplayItem(
    phenomenon: String,
    function: String,
    whyItMatters: String,
    titleZh: String,
    explanationZh: String,
    whyItMattersZh: String,
    exampleEn: String
) -> ProfessorGrammarFocusDisplayItem {
    let template = localizedGrammarTemplate(for: phenomenon)
    let localizedTitle = purifiedChineseDisplayText(titleZh)
        .nonEmpty
        ?? template?.title
        ?? purifiedChineseDisplayText(sanitizedPedagogicalChinese(phenomenon)).nonEmpty
        ?? "关键语法点"

    let explicitWhatItIs = purifiedChineseExplanation(explanationZh).nonEmpty
    let preferredWhatItIs = (explicitWhatItIs != nil && !looksLikeGrammarRoleDescription(explicitWhatItIs ?? ""))
        ? explicitWhatItIs
        : template?.whatItIs
        ?? purifiedChineseExplanation(sanitizedPedagogicalChinese(phenomenon)).nonEmpty
    let localizedWhatItIs = (preferredWhatItIs != nil && !looksLikeMixedGrammarExplanation(preferredWhatItIs ?? ""))
        ? preferredWhatItIs!
        : defaultGrammarWhatItIs(title: localizedTitle)

    let preferredFunction = purifiedChineseExplanation(sanitizedPedagogicalChinese(function)).nonEmpty
        ?? template?.functionInSentence
    let localizedFunction = (preferredFunction != nil && !looksLikeMixedGrammarExplanation(preferredFunction ?? ""))
        ? preferredFunction!
        : defaultGrammarFunctionDescription(title: localizedTitle)

    let preferredWhy = purifiedChineseExplanation(whyItMattersZh).nonEmpty
        ?? purifiedChineseExplanation(sanitizedPedagogicalChinese(whyItMatters)).nonEmpty
    let localizedWhy = (preferredWhy != nil && !looksLikeMixedGrammarExplanation(preferredWhy ?? ""))
        ? preferredWhy!
        : (template?.whyItMatters ?? "这个结构一旦挂错，主干、修饰范围和命题改写都会跟着读偏。")

    return ProfessorGrammarFocusDisplayItem(
        title: localizedTitle,
        whatItIs: localizedWhatItIs,
        functionInSentence: localizedFunction,
        whyItMatters: localizedWhy,
        exampleEN: trimmedOrEmpty(exampleEn).nonEmpty,
        terminologyTag: grammarTerminologyTag(from: phenomenon, exampleEn: exampleEn)
    )
}

private func normalizeCompatibleCoreSkeleton(from skeleton: ProfessorCoreSkeleton?) -> ProfessorCoreSkeleton? {
    guard let skeleton else { return nil }

    let subject = sanitizedCoreSkeletonField(skeleton.subject)
    let predicate = sanitizedCoreSkeletonField(skeleton.predicate)
    let complement = sanitizedCoreSkeletonField(skeleton.complementOrObject)

    if let parsed = parseCompatibleCoreSkeleton(from: [subject, predicate, complement].joined(separator: " ")) {
        return parsed
    }

    let normalized = ProfessorCoreSkeleton(
        subject: subject,
        predicate: predicate,
        complementOrObject: complement
    )

    return normalized.isMeaningful ? normalized : nil
}

private func parseCompatibleCoreSkeleton(from raw: String) -> ProfessorCoreSkeleton? {
    let normalized = sanitizedPedagogicalChinese(raw)
    guard !normalized.isEmpty else { return nil }

    var subject = ""
    var predicate = ""
    var complement = ""

    let separators = normalized
        .replacingOccurrences(of: "\n", with: "｜")
        .replacingOccurrences(of: "／", with: "｜")
        .replacingOccurrences(of: "/", with: "｜")
        .split(separator: "｜")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    for segment in separators {
        if segment.contains("主语：") || segment.contains("主语:") {
            subject = sanitizedCoreSkeletonField(
                segment
                    .replacingOccurrences(of: "主语：", with: "")
                    .replacingOccurrences(of: "主语:", with: "")
            )
        } else if segment.contains("谓语：") || segment.contains("谓语:") {
            predicate = sanitizedCoreSkeletonField(
                segment
                    .replacingOccurrences(of: "谓语：", with: "")
                    .replacingOccurrences(of: "谓语:", with: "")
            )
        } else if segment.contains("核心补足：") || segment.contains("核心补足:") || segment.contains("宾语：") || segment.contains("补语：") || segment.contains("表语：") {
            complement = sanitizedCoreSkeletonField(
                segment
                    .replacingOccurrences(of: "核心补足：", with: "")
                    .replacingOccurrences(of: "核心补足:", with: "")
                    .replacingOccurrences(of: "宾语：", with: "")
                    .replacingOccurrences(of: "宾语:", with: "")
                    .replacingOccurrences(of: "补语：", with: "")
                    .replacingOccurrences(of: "补语:", with: "")
                    .replacingOccurrences(of: "表语：", with: "")
                    .replacingOccurrences(of: "表语:", with: "")
            )
        }
    }

    if !subject.isEmpty || !predicate.isEmpty || !complement.isEmpty {
        return ProfessorCoreSkeleton(subject: subject, predicate: predicate, complementOrObject: complement)
    }

    let bracketMatches = normalized.matchingGroups(pattern: #"\[([A-Za-z_\s-]+):\s*([^\]]+)\]"#)
    guard !bracketMatches.isEmpty else { return nil }

    var subjectParts: [String] = []
    var predicateParts: [String] = []
    var complementParts: [String] = []

    for groups in bracketMatches {
        guard groups.count >= 3 else { continue }
        let label = groups[1].lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let value = sanitizedCoreSkeletonField(groups[2])
        guard !value.isEmpty else { continue }

        switch label {
        case "subject", "subj", "subject phrase":
            subjectParts.append(value)
        case "predicate", "verb", "main verb", "verb phrase":
            predicateParts.append(value)
        case "object", "object clause", "complement", "predicate complement", "object complement", "complement clause":
            complementParts.append(value)
        default:
            if label.contains("subject") {
                subjectParts.append(value)
            } else if label.contains("predicate") || label.contains("verb") {
                predicateParts.append(value)
            } else if label.contains("object") || label.contains("complement") || label.contains("clause") {
                complementParts.append(value)
            }
        }
    }

    let parsed = ProfessorCoreSkeleton(
        subject: subjectParts.joined(separator: "；"),
        predicate: predicateParts.joined(separator: "；"),
        complementOrObject: complementParts.joined(separator: "；")
    )

    return parsed.isMeaningful ? parsed : nil
}

private func sanitizedCoreSkeletonField(_ value: String) -> String {
    let trimmed = trimmedOrEmpty(value)
    guard !trimmed.isEmpty else { return "" }
    let stripped = trimmed.replacingOccurrences(
        of: #"\[[A-Za-z_\s-]+:\s*([^\]]+)\]"#,
        with: "$1",
        options: .regularExpression
    )
    let cleaned = stripped
        .replacingOccurrences(of: #"^(主语|谓语|核心补足|宾语|补语|表语)\s*[：:]\s*"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    return trimmedOrEmpty(cleaned)
}

private func containsLegacyCoreSkeletonMarkup(_ value: String) -> Bool {
    trimmedOrEmpty(value).range(of: #"\[[A-Za-z_\s-]+:\s*[^\]]+\]"#, options: .regularExpression) != nil
}

private func pedagogicalWhyGrammarPointMatters(name: String) -> String {
    if let template = localizedGrammarTemplate(for: name) {
        return template.whyItMatters
    }
    return "这个结构决定信息挂接关系，读错会直接影响主干判断和题目定位。"
}

private func truncatedPedagogicalText(_ value: String, limit: Int) -> String {
    let trimmed = trimmedOrEmpty(value)
    guard !trimmed.isEmpty else { return "" }
    guard trimmed.count > limit else { return trimmed }
    return String(trimmed.prefix(max(0, limit - 1))) + "…"
}

private extension Array {
    func uniqued<Key: Hashable>(on keyPath: (Element) -> Key) -> [Element] {
        var seen: Set<Key> = []
        return filter { seen.insert(keyPath($0)).inserted }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func matchingStrings(pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: self) else { return nil }
            return String(self[matchRange])
        }
    }

    func matchingGroups(pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: range).map { match in
            (0..<match.numberOfRanges).compactMap { index in
                guard let groupRange = Range(match.range(at: index), in: self) else { return nil }
                return String(self[groupRange])
            }
        }
    }
}

private func pedagogicalList(_ preferred: [String], fallback: [String], limit: Int = 6) -> [String] {
    var ordered: [String] = []
    var seen: Set<String> = []

    for item in preferred + fallback {
        let normalized = trimmedOrEmpty(item)
        guard !normalized.isEmpty else { continue }
        let key = normalized.lowercased()
        guard seen.insert(key).inserted else { continue }
        ordered.append(normalized)
        if ordered.count >= limit {
            break
        }
    }

    return ordered
}

private func pedagogicalTextScore(_ value: String, kind: PedagogicalTextKind) -> Int {
    let trimmed = trimmedOrEmpty(value)
    guard !trimmed.isEmpty else { return 0 }

    let lower = trimmed.lowercased()
    var score = min(trimmed.count, 120)

    switch kind {
    case .faithfulTranslation:
        if !isChineseDominant(trimmed) { score -= 32 }
        if lower.contains("本段") || lower.contains("作者") || lower.contains("真正") || lower.contains("重点") {
            score -= 18
        }
        if lower.contains("意思是") || lower.contains("可以译为") || lower.contains("译作") {
            score += 10
        }
    case .teachingInterpretation:
        if !isChineseDominant(trimmed) { score -= 32 }
        if lower.contains("真正重点") || lower.contains("真正要你抓") || lower.contains("不要把") || lower.contains("先抓") {
            score += 12
        }
        if lower.contains("逐词翻译") {
            score -= 8
        }
    case .naturalMeaning:
        if !isChineseDominant(trimmed) { score -= 28 }
        if lower.contains("这句话服务于本段") { score -= 24 }
        if lower.contains("不要平均翻译") { score -= 18 }
        if lower.contains("自然意思是") || lower.contains("真正想说的是") { score += 12 }
    case .sentenceCore:
        if lower.hasPrefix("先抓主干") { score -= 30 }
        if lower.contains("主语") { score += 18 }
        if lower.contains("谓语") { score += 18 }
        if lower.contains("宾语") || lower.contains("补语") { score += 12 }
    case .paragraphTheme:
        if !isChineseDominant(trimmed) { score -= 24 }
        if lower.hasPrefix("第") && lower.contains("承担") { score -= 28 }
        if lower.contains("围绕") || lower.contains("真正要说明") { score += 10 }
    case .overviewTheme:
        if !isChineseDominant(trimmed) { score -= 24 }
        if lower.contains("文章核心围绕") { score -= 20 }
        if lower.contains("本文真正讨论") || lower.contains("作者真正关注") { score += 14 }
    case .overviewQuestion:
        if !isChineseDominant(trimmed) { score -= 24 }
        if lower.contains("作者真正要回答的问题可以概括为") { score -= 16 }
        if lower.contains("作者真正追问的是") || lower.contains("核心问题是") { score += 12 }
    case .overviewProgression:
        if !isChineseDominant(trimmed) { score -= 20 }
        if lower.contains("→") { score += 8 }
        if lower.contains("先") && lower.contains("再") { score += 10 }
    case .relation:
        if !isChineseDominant(trimmed) { score -= 20 }
        if lower == "承接上文" { score -= 40 }
        if lower.contains("转折") || lower.contains("推进") || lower.contains("限定") { score += 10 }
    case .examValue:
        if !isChineseDominant(trimmed) { score -= 20 }
        if lower.contains("常见于") { score += 6 }
        if lower.contains("陷阱") || lower.contains("题型") { score += 10 }
    case .generic:
        break
    }

    return score
}

private func preferredPedagogicalText(
    _ preferred: String,
    fallback: String,
    kind: PedagogicalTextKind
) -> String {
    let preferredTrimmed = trimmedOrEmpty(preferred)
    let fallbackTrimmed = trimmedOrEmpty(fallback)

    let preferredScore = pedagogicalTextScore(preferredTrimmed, kind: kind)
    let fallbackScore = pedagogicalTextScore(fallbackTrimmed, kind: kind)

    if preferredScore == 0 { return fallbackTrimmed }
    if fallbackScore == 0 { return preferredTrimmed }
    return preferredScore >= fallbackScore ? preferredTrimmed : fallbackTrimmed
}

extension ProfessorSentenceAnalysis {
    func mergingFallback(_ fallback: ProfessorSentenceAnalysis?) -> ProfessorSentenceAnalysis {
        guard let fallback else { return self }

        return ProfessorSentenceAnalysis(
            originalSentence: preferredPedagogicalText(originalSentence, fallback: fallback.originalSentence, kind: .generic),
            sentenceFunction: preferredPedagogicalText(sentenceFunction, fallback: fallback.sentenceFunction, kind: .generic),
            coreSkeleton: coreSkeleton ?? fallback.coreSkeleton,
            chunkLayers: chunkLayers.isEmpty ? fallback.chunkLayers : chunkLayers,
            grammarFocus: grammarFocus.isEmpty ? fallback.grammarFocus : grammarFocus,
            faithfulTranslation: preferredPedagogicalText(
                faithfulTranslation,
                fallback: fallback.faithfulTranslation,
                kind: .faithfulTranslation
            ),
            teachingInterpretation: preferredPedagogicalText(
                teachingInterpretation,
                fallback: fallback.teachingInterpretation,
                kind: .teachingInterpretation
            ),
            naturalChineseMeaning: preferredPedagogicalText(
                naturalChineseMeaning,
                fallback: fallback.naturalChineseMeaning,
                kind: .teachingInterpretation
            ),
            sentenceCore: preferredPedagogicalText(sentenceCore, fallback: fallback.sentenceCore, kind: .sentenceCore),
            chunkBreakdown: pedagogicalList(chunkBreakdown, fallback: fallback.chunkBreakdown, limit: 6),
            grammarPoints: grammarPoints.isEmpty ? fallback.grammarPoints : grammarPoints,
            vocabularyInContext: vocabularyInContext.isEmpty ? fallback.vocabularyInContext : vocabularyInContext,
            misreadPoints: pedagogicalList(misreadPoints, fallback: fallback.misreadPoints, limit: 4),
            examRewritePoints: pedagogicalList(examRewritePoints, fallback: fallback.examRewritePoints, limit: 4),
            misreadingTraps: pedagogicalList(misreadingTraps, fallback: fallback.misreadingTraps, limit: 4),
            examParaphraseRoutes: pedagogicalList(examParaphraseRoutes, fallback: fallback.examParaphraseRoutes, limit: 4),
            simplifiedEnglish: preferredPedagogicalText(simplifiedEnglish, fallback: fallback.simplifiedEnglish, kind: .generic),
            simplerRewrite: preferredPedagogicalText(simplerRewrite, fallback: fallback.simplerRewrite, kind: .generic),
            simplerRewriteTranslation: preferredPedagogicalText(
                simplerRewriteTranslation,
                fallback: fallback.simplerRewriteTranslation,
                kind: .teachingInterpretation
            ),
            miniExercise: preferredPedagogicalText(miniExercise ?? "", fallback: fallback.miniExercise ?? "", kind: .generic).isEmpty
                ? nil
                : preferredPedagogicalText(miniExercise ?? "", fallback: fallback.miniExercise ?? "", kind: .generic),
            miniCheck: preferredPedagogicalText(miniCheck ?? "", fallback: fallback.miniCheck ?? "", kind: .generic).isEmpty
                ? nil
                : preferredPedagogicalText(miniCheck ?? "", fallback: fallback.miniCheck ?? "", kind: .generic),
            hierarchyRebuild: pedagogicalList(hierarchyRebuild, fallback: fallback.hierarchyRebuild, limit: 5),
            syntacticVariation: preferredPedagogicalText(
                syntacticVariation ?? "",
                fallback: fallback.syntacticVariation ?? "",
                kind: .generic
            ).isEmpty ? nil : preferredPedagogicalText(
                syntacticVariation ?? "",
                fallback: fallback.syntacticVariation ?? "",
                kind: .generic
            ),
            evidenceType: preferredPedagogicalText(evidenceType ?? "", fallback: fallback.evidenceType ?? "", kind: .generic).isEmpty
                ? nil
                : preferredPedagogicalText(evidenceType ?? "", fallback: fallback.evidenceType ?? "", kind: .generic),
            isAIGenerated: isAIGenerated || fallback.isAIGenerated
        )
    }
}

extension ParagraphTeachingCard {
    func mergingFallback(_ fallback: ParagraphTeachingCard?) -> ParagraphTeachingCard {
        guard let fallback else { return self }

        return ParagraphTeachingCard(
            id: id,
            segmentID: segmentID,
            paragraphIndex: paragraphIndex,
            anchorLabel: preferredPedagogicalText(anchorLabel, fallback: fallback.anchorLabel, kind: .generic),
            theme: preferredPedagogicalText(theme, fallback: fallback.theme, kind: .paragraphTheme),
            argumentRole: isAIGenerated ? argumentRole : fallback.argumentRole,
            coreSentenceID: coreSentenceID ?? fallback.coreSentenceID,
            keywords: pedagogicalList(keywords, fallback: fallback.keywords, limit: 6),
            relationToPrevious: preferredPedagogicalText(relationToPrevious, fallback: fallback.relationToPrevious, kind: .relation),
            examValue: preferredPedagogicalText(examValue, fallback: fallback.examValue, kind: .examValue),
            teachingFocuses: pedagogicalList(teachingFocuses, fallback: fallback.teachingFocuses, limit: 4),
            studentBlindSpot: preferredPedagogicalText(
                studentBlindSpot ?? "",
                fallback: fallback.studentBlindSpot ?? "",
                kind: .generic
            ).isEmpty ? nil : preferredPedagogicalText(
                studentBlindSpot ?? "",
                fallback: fallback.studentBlindSpot ?? "",
                kind: .generic
            ),
            isAIGenerated: isAIGenerated || fallback.isAIGenerated
        )
    }
}

extension PassageOverview {
    func mergingFallback(_ fallback: PassageOverview?) -> PassageOverview {
        guard let fallback else { return self }

        return PassageOverview(
            articleTheme: preferredPedagogicalText(articleTheme, fallback: fallback.articleTheme, kind: .overviewTheme),
            authorCoreQuestion: preferredPedagogicalText(
                authorCoreQuestion,
                fallback: fallback.authorCoreQuestion,
                kind: .overviewQuestion
            ),
            progressionPath: preferredPedagogicalText(
                progressionPath,
                fallback: fallback.progressionPath,
                kind: .overviewProgression
            ),
            likelyQuestionTypes: pedagogicalList(likelyQuestionTypes, fallback: fallback.likelyQuestionTypes, limit: 6),
            logicPitfalls: pedagogicalList(logicPitfalls, fallback: fallback.logicPitfalls, limit: 6),
            paragraphFunctionMap: pedagogicalList(paragraphFunctionMap, fallback: fallback.paragraphFunctionMap, limit: 10),
            syntaxHighlights: pedagogicalList(syntaxHighlights, fallback: fallback.syntaxHighlights, limit: 6),
            readingTraps: pedagogicalList(readingTraps, fallback: fallback.readingTraps, limit: 6),
            vocabularyHighlights: pedagogicalList(vocabularyHighlights, fallback: fallback.vocabularyHighlights, limit: 8)
        )
    }
}

struct DocumentZoningSummary: Codable, Equatable, Hashable {
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
    let provenance: NodeProvenance
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
        case provenance
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
        provenance: NodeProvenance = .unknown,
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
        self.provenance = provenance
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
        provenance = try container.decodeIfPresent(NodeProvenance.self, forKey: .provenance)
            ?? NodeProvenance(
                sourceSegmentID: sourceSegmentIDs.first ?? anchor.segmentID,
                sourceSentenceID: sourceSentenceIDs.first ?? anchor.sentenceID,
                sourceKind: .unknown,
                consistencyScore: 0.5
            )
        children = try container.decodeIfPresent([OutlineNode].self, forKey: .children) ?? []
    }

    var primarySegmentID: String? {
        provenance.sourceSegmentID ?? sourceSegmentIDs.first ?? anchor.segmentID
    }

    var primarySentenceID: String? {
        provenance.sourceSentenceID ?? sourceSentenceIDs.first ?? anchor.sentenceID
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
    let passageMap: PassageMap?
    let mindMapAdmissionResult: MindMapAdmissionResult?
    let passageAnalysisDiagnostics: PassageAnalysisDiagnostics?

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
        lhs.zoningSummary == rhs.zoningSummary &&
        lhs.passageMap == rhs.passageMap &&
        lhs.mindMapAdmissionResult == rhs.mindMapAdmissionResult &&
        lhs.passageAnalysisDiagnostics == rhs.passageAnalysisDiagnostics
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
        ),
        passageMap: PassageMap? = nil,
        mindMapAdmissionResult: MindMapAdmissionResult? = nil,
        passageAnalysisDiagnostics: PassageAnalysisDiagnostics? = nil
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
        self.passageMap = passageMap
        self.mindMapAdmissionResult = mindMapAdmissionResult
        self.passageAnalysisDiagnostics = passageAnalysisDiagnostics
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

    func displayedSentenceCard(id: String?) -> ProfessorSentenceCard? {
        guard let id else { return nil }
        let rebuiltCard = { NormalizedDocumentConverter.rebuildSentenceCard(sentenceID: id, in: self) }
        guard let existing = sentenceCard(id: id) else {
            return rebuiltCard()
        }
        if let sentence = sentence(id: id),
           !existing.analysis.isCompatible(with: sentence.text) {
            return rebuiltCard() ?? existing
        }
        guard existing.analysis.needsLocalRepair else { return existing }
        return rebuiltCard() ?? existing
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

        let matched = _cachedFlatNodes
            .filter { node in
                node.sourceSentenceIDs.contains(id) || node.anchor.sentenceID == id
            }
            .sorted {
                if $0.provenance.consistencyScore != $1.provenance.consistencyScore {
                    return $0.provenance.consistencyScore > $1.provenance.consistencyScore
                }
                if $0.depth != $1.depth {
                    return $0.depth > $1.depth
                }

                return $0.coverageSpan < $1.coverageSpan
            }
            .first
        if let matched {
            return matched
        }

        guard let sentence = sentence(id: id) else { return nil }
        return bestOutlineNode(forSegmentID: sentence.segmentID)
    }

    func bestOutlineNode(forSegmentID id: String?) -> OutlineNode? {
        guard let id else { return nil }

        return _cachedFlatNodes
            .filter { node in
                node.sourceSegmentIDs.contains(id) || node.anchor.segmentID == id
            }
            .sorted {
                if $0.provenance.consistencyScore != $1.provenance.consistencyScore {
                    return $0.provenance.consistencyScore > $1.provenance.consistencyScore
                }
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

    var hasProfessorAnalysis: Bool {
        paragraphTeachingCards.contains(where: \.isAIGenerated) ||
        professorSentenceCards.contains(where: { $0.analysis.isAIGenerated })
    }

    /// 用 AI 生成的教授级分析内容替换启发式占位内容
    func enrichedWithAIAnalysis(
        overview: PassageOverview?,
        paragraphCards: [ParagraphTeachingCard],
        sentenceCards: [ProfessorSentenceCard],
        passageAnalysisDiagnostics: PassageAnalysisDiagnostics? = nil
    ) -> StructuredSourceBundle {
        let aiParagraphIndex = Dictionary(
            paragraphCards.map { ($0.segmentID, $0) },
            uniquingKeysWith: { _, new in new }
        )
        var mergedParagraphCards = self.paragraphTeachingCards.map { existing in
            aiParagraphIndex[existing.segmentID]?.mergingFallback(existing) ?? existing
        }
        let existingParagraphIDs = Set(mergedParagraphCards.map(\.segmentID))
        mergedParagraphCards.append(
            contentsOf: paragraphCards.filter { !existingParagraphIDs.contains($0.segmentID) }
        )
        mergedParagraphCards.sort { $0.paragraphIndex < $1.paragraphIndex }

        let aiSentenceIndex = Dictionary(
            sentenceCards.map { ($0.sentenceID, $0) },
            uniquingKeysWith: { _, new in new }
        )
        var mergedSentenceCards = self.professorSentenceCards.map { existing in
            guard let aiCard = aiSentenceIndex[existing.sentenceID] else { return existing }
            return ProfessorSentenceCard(
                id: existing.id,
                sentenceID: existing.sentenceID,
                segmentID: existing.segmentID,
                isKeySentence: existing.isKeySentence || aiCard.isKeySentence,
                analysis: aiCard.analysis.mergingFallback(existing.analysis)
            )
        }
        let existingSentenceIDs = Set(mergedSentenceCards.map(\.sentenceID))
        mergedSentenceCards.append(
            contentsOf: sentenceCards.filter { !existingSentenceIDs.contains($0.sentenceID) }
        )
        mergedSentenceCards.sort { $0.sentenceID < $1.sentenceID }

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
            overview: (overview?.mergingFallback(passageOverview)) ?? passageOverview,
            questionLinks: questionLinks
        )

        let provisionalBundle = StructuredSourceBundle(
            source: source,
            segments: segments,
            sentences: sentences,
            outline: mergedOutline,
            passageOverview: (overview?.mergingFallback(passageOverview)) ?? passageOverview,
            paragraphTeachingCards: mergedParagraphCards,
            professorSentenceCards: mergedSentenceCards,
            questionLinks: questionLinks,
            zoningSummary: zoningSummary,
            passageAnalysisDiagnostics: passageAnalysisDiagnostics ?? self.passageAnalysisDiagnostics
        )
        let passageMap = MindMapAdmissionService.buildPassageMap(from: provisionalBundle)
        let admissionResult = MindMapAdmissionService.admit(bundle: provisionalBundle, passageMap: passageMap)

        return StructuredSourceBundle(
            source: provisionalBundle.source,
            segments: provisionalBundle.segments,
            sentences: provisionalBundle.sentences,
            outline: provisionalBundle.outline,
            passageOverview: provisionalBundle.passageOverview,
            paragraphTeachingCards: provisionalBundle.paragraphTeachingCards,
            professorSentenceCards: provisionalBundle.professorSentenceCards,
            questionLinks: provisionalBundle.questionLinks,
            zoningSummary: provisionalBundle.zoningSummary,
            passageMap: passageMap.withDiagnostics(admissionResult.diagnostics),
            mindMapAdmissionResult: admissionResult,
            passageAnalysisDiagnostics: provisionalBundle.passageAnalysisDiagnostics
        )
    }

    /// 重建教学大纲树
    private static func rebuildOutline(
        sourceID: String,
        segments: [Segment],
        sentencesBySegment: [String: [Sentence]],
        paragraphCards: [ParagraphTeachingCard],
        sentenceCardIndex: [String: ProfessorSentenceCard],
        overview: PassageOverview?,
        questionLinks: [QuestionEvidenceLink]
    ) -> [OutlineNode] {
        let questionHintsBySegment = Dictionary(
            grouping: questionLinks.flatMap { link in
                link.supportParagraphIDs.map { ($0, link) }
            },
            by: { $0.0 }
        )
        let sentenceSegmentIndex = Dictionary(
            uniqueKeysWithValues: sentencesBySegment.values
                .flatMap { $0 }
                .map { ($0.id, $0.segmentID) }
        )

        let paragraphNodes: [OutlineNode] = paragraphCards.map { card in
            let sentences = sentencesBySegment[card.segmentID] ?? []
            let linkedQuestions = (questionHintsBySegment[card.segmentID] ?? []).map(\.1)
            let paragraphSegment = segments.first(where: { $0.id == card.segmentID })
            let proposedParagraphTitle = pedagogicalParagraphTitle(card: card)
            let proposedParagraphSummary = pedagogicalParagraphSummary(card: card, linkedQuestions: linkedQuestions)
            let validatedParagraph = AnchorConsistencyValidator.validatedParagraphNodeContent(
                card: card,
                sentences: sentences,
                proposedTitle: proposedParagraphTitle,
                proposedSummary: proposedParagraphSummary
            )
            let questionNodes = linkedQuestions.enumerated().map { offset, link in
                let localSentenceIDs = link.supportingSentenceIDs.filter {
                    sentenceSegmentIndex[$0] == card.segmentID
                }
                let anchorSentenceID = localSentenceIDs.first ?? validatedParagraph.anchorSentenceID
                return OutlineNode(
                    id: "question_\(card.segmentID)_\(link.id)",
                    sourceID: sourceID,
                    parentID: "para_\(card.segmentID)",
                    depth: 2,
                    order: card.paragraphIndex * 100 + offset + 20,
                    nodeType: .questionLink,
                    title: "题目联动｜\(pedagogicalQuestionNodeTitle(link: link))",
                    summary: pedagogicalQuestionNodeSummary(link: link),
                    anchor: OutlineAnchor(
                        segmentID: card.segmentID,
                        sentenceID: anchorSentenceID,
                        page: sentences.first?.page,
                        label: card.anchorLabel
                    ),
                    sourceSegmentIDs: [card.segmentID],
                    sourceSentenceIDs: anchorSentenceID.map { [$0] } ?? [],
                    provenance: NodeProvenance(
                        sourceSegmentID: card.segmentID,
                        sourceSentenceID: anchorSentenceID,
                        sourceKind: .question,
                        consistencyScore: localSentenceIDs.isEmpty ? 0.58 : 0.76
                    ),
                    children: []
                )
            }
            let supportingSentenceNodes = sentences
                .filter { sentence in
                    sentence.id == validatedParagraph.anchorSentenceID || sentenceCardIndex[sentence.id]?.isKeySentence == true
                }
                .prefix(2)
                .map { sentence in
                    let analysis = sentenceCardIndex[sentence.id]?.analysis
                    let validatedSentence = AnchorConsistencyValidator.validatedSentenceNodeContent(
                        sentence: sentence,
                        analysis: analysis,
                        proposedTitle: pedagogicalSentenceNodeTitle(sentence: sentence, analysis: analysis),
                        proposedSummary: pedagogicalSentenceNodeSummary(sentence: sentence, analysis: analysis)
                    )
                    return OutlineNode(
                        id: "support_\(sentence.id)",
                        sourceID: sourceID,
                        parentID: "para_\(card.segmentID)",
                        depth: 2,
                        order: sentence.index,
                        nodeType: .supportingSentence,
                        title: validatedSentence.title,
                        summary: validatedSentence.summary,
                        anchor: OutlineAnchor(
                            segmentID: sentence.segmentID,
                            sentenceID: sentence.id,
                            page: sentence.page,
                            label: sentence.anchorLabel
                        ),
                        sourceSegmentIDs: [sentence.segmentID],
                        sourceSentenceIDs: [sentence.id],
                        provenance: NodeProvenance(
                            sourceSegmentID: sentence.segmentID,
                            sourceSentenceID: sentence.id,
                            sourceKind: sentence.provenance.sourceKind,
                            consistencyScore: validatedSentence.consistencyScore
                        ),
                        children: []
                    )
                }

            let validatedFocus = AnchorConsistencyValidator.validatedFocusNodeContent(
                card: card,
                sentences: sentences,
                proposedTitle: pedagogicalFocusTitle(card: card),
                proposedSummary: pedagogicalFocusSummary(card: card, linkedQuestions: linkedQuestions)
            )
            let focusNode = OutlineNode(
                id: "focus_\(card.segmentID)",
                sourceID: sourceID,
                parentID: "para_\(card.segmentID)",
                depth: 2,
                order: card.paragraphIndex * 10,
                nodeType: .teachingFocus,
                title: validatedFocus.title,
                summary: validatedFocus.summary,
                anchor: OutlineAnchor(
                    segmentID: card.segmentID,
                    sentenceID: validatedFocus.anchorSentenceID,
                    page: sentences.first?.page,
                    label: card.anchorLabel
                ),
                sourceSegmentIDs: [card.segmentID],
                sourceSentenceIDs: validatedFocus.anchorSentenceID.map { [$0] } ?? [],
                provenance: NodeProvenance(
                    sourceSegmentID: card.segmentID,
                    sourceSentenceID: validatedFocus.anchorSentenceID,
                    sourceKind: paragraphSegment?.provenance.sourceKind ?? .passageBody,
                    consistencyScore: validatedFocus.consistencyScore
                ),
                children: []
            )

            return OutlineNode(
                id: "para_\(card.segmentID)",
                sourceID: sourceID,
                parentID: "passage_root",
                depth: 1,
                order: card.paragraphIndex,
                nodeType: .paragraphTheme,
                title: validatedParagraph.title,
                summary: validatedParagraph.summary,
                anchor: OutlineAnchor(
                    segmentID: card.segmentID,
                    sentenceID: validatedParagraph.anchorSentenceID,
                    page: sentences.first?.page,
                    label: card.anchorLabel
                ),
                sourceSegmentIDs: [card.segmentID],
                sourceSentenceIDs: validatedParagraph.anchorSentenceID.map { [$0] } ?? [],
                provenance: NodeProvenance(
                    sourceSegmentID: card.segmentID,
                    sourceSentenceID: validatedParagraph.anchorSentenceID,
                    sourceKind: paragraphSegment?.provenance.sourceKind ?? .passageBody,
                    consistencyScore: validatedParagraph.consistencyScore
                ),
                children: [focusNode] + questionNodes + supportingSentenceNodes
            )
        }

        let rootNode = OutlineNode(
            id: "passage_root",
            sourceID: sourceID,
            parentID: nil,
            depth: 0,
            order: 0,
            nodeType: .passageRoot,
            title: pedagogicalRootTitle(overview: overview),
            summary: pedagogicalRootSummary(overview: overview),
            anchor: OutlineAnchor(
                segmentID: segments.first?.id,
                sentenceID: nil,
                page: segments.first?.page,
                label: segments.first?.anchorLabel ?? "原文"
            ),
            sourceSegmentIDs: segments.map(\.id),
            sourceSentenceIDs: [],
            provenance: NodeProvenance(
                sourceSegmentID: segments.first?.id,
                sourceSentenceID: segments.first.flatMap { sentencesBySegment[$0.id]?.first?.id },
                sourceKind: segments.first?.provenance.sourceKind ?? .passageBody,
                consistencyScore: 0.9
            ),
            children: paragraphNodes
        )

        return [rootNode]
    }

    private static func pedagogicalRootTitle(overview: PassageOverview?) -> String {
        let theme = truncatedPedagogicalText(overview?.displayedArticleTheme ?? "", limit: 22)
        return theme.isEmpty ? "文章主题与问题意识" : theme
    }

    private static func pedagogicalRootSummary(overview: PassageOverview?) -> String {
        guard let overview else { return "正文思维导图" }
        let question = trimmedOrEmpty(overview.displayedAuthorCoreQuestion)
        let progression = trimmedOrEmpty(overview.displayedProgressionPath)
        let summary = question.isEmpty
            ? (progression.isEmpty ? "先看主题，再顺着段落分支定位关键句。" : truncatedPedagogicalText(progression, limit: 52))
            : "核心问题：\(truncatedPedagogicalText(question, limit: 28))"
        return truncatedPedagogicalText(summary, limit: 60)
    }

    private static func pedagogicalParagraphTitle(card: ParagraphTeachingCard) -> String {
        let theme = trimmedOrEmpty(card.displayedTheme)
        let shortTheme = truncatedPedagogicalText(theme, limit: 16)
        if !shortTheme.isEmpty {
            return "第\(card.paragraphIndex + 1)段｜\(shortTheme)"
        }
        return "第\(card.paragraphIndex + 1)段｜\(card.argumentRole.displayName)"
    }

    private static func pedagogicalParagraphSummary(
        card: ParagraphTeachingCard,
        linkedQuestions _: [QuestionEvidenceLink]
    ) -> String {
        let primaryFocus = truncatedPedagogicalText(card.displayedTeachingFocuses.first ?? "", limit: 20)
        let blindSpot = truncatedPedagogicalText(card.displayedStudentBlindSpot ?? "", limit: 20)
        let examValue = truncatedPedagogicalText(card.displayedExamValue, limit: 18)

        let summary = [
            !primaryFocus.isEmpty ? "先抓：\(primaryFocus)" : "",
            primaryFocus.isEmpty && !blindSpot.isEmpty ? "别读偏：\(blindSpot)" : "",
            primaryFocus.isEmpty && blindSpot.isEmpty && !examValue.isEmpty ? "命题点：\(examValue)" : ""
        ].first(where: { !$0.isEmpty }) ?? "段落教学节点"
        return truncatedPedagogicalText(summary, limit: 50)
    }

    private static func pedagogicalFocusTitle(card: ParagraphTeachingCard) -> String {
        if let first = card.displayedTeachingFocuses.first, !trimmedOrEmpty(first).isEmpty {
            let focus = trimmedOrEmpty(first)
            let shortFocus = truncatedPedagogicalText(focus, limit: 18)
            return "教学重点｜\(shortFocus)"
        }
        return "教学重点"
    }

    private static func pedagogicalFocusSummary(
        card: ParagraphTeachingCard,
        linkedQuestions _: [QuestionEvidenceLink]
    ) -> String {
        let primaryFocus = truncatedPedagogicalText(card.displayedTeachingFocuses.first ?? "", limit: 24)
        let blindSpot = truncatedPedagogicalText(card.displayedStudentBlindSpot ?? "", limit: 18)
        let examValue = truncatedPedagogicalText(card.displayedExamValue, limit: 18)
        let summary = !primaryFocus.isEmpty
            ? "先抓：\(primaryFocus)"
            : (!blindSpot.isEmpty ? "别读偏：\(blindSpot)" : (examValue.isEmpty ? "本段最值得先学的一点" : "命题点：\(examValue)"))
        return truncatedPedagogicalText(summary, limit: 40)
    }

    private static func pedagogicalSentenceNodeTitle(
        sentence: Sentence,
        analysis: ProfessorSentenceAnalysis?
    ) -> String {
        if let analysis {
            if let role = professorSentenceRolePresentation(for: analysis.evidenceType)?.label,
               !trimmedOrEmpty(role).isEmpty {
                return "第\(sentence.localIndex + 1)句｜\(truncatedPedagogicalText(role, limit: 8))"
            }

            let functionHead = analysis.renderedSentenceFunction
                .split(separator: "：", maxSplits: 1)
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !functionHead.isEmpty {
                return "第\(sentence.localIndex + 1)句｜\(truncatedPedagogicalText(functionHead, limit: 8))"
            }
        }
        return "第\(sentence.localIndex + 1)句关键句"
    }

    private static func pedagogicalSentenceNodeSummary(
        sentence: Sentence,
        analysis: ProfessorSentenceAnalysis?
    ) -> String {
        guard let analysis else { return truncatedPedagogicalText(sentence.text, limit: 36) }

        let faithful = truncatedPedagogicalText(trimmedOrEmpty(analysis.renderedFaithfulTranslation), limit: 28)
        let teaching = truncatedPedagogicalText(trimmedOrEmpty(analysis.renderedTeachingInterpretation), limit: 28)
        let trap = truncatedPedagogicalText(trimmedOrEmpty(analysis.renderedMisreadingTraps.first ?? ""), limit: 20)
        let summary = [
            !faithful.isEmpty ? faithful : "",
            faithful.isEmpty && !teaching.isEmpty ? teaching : "",
            faithful.isEmpty && teaching.isEmpty && !trap.isEmpty ? "易错：\(trap)" : ""
        ].first(where: { !$0.isEmpty }) ?? truncatedPedagogicalText(sentence.text, limit: 36)
        return truncatedPedagogicalText(summary, limit: 36)
    }

    private static func pedagogicalQuestionNodeTitle(link: QuestionEvidenceLink) -> String {
        let trap = trimmedOrEmpty(link.trapType)
        if !trap.isEmpty {
            return trap
        }

        return trimmedOrEmpty(link.questionText)
            .split(separator: "\n")
            .first
            .map(String.init)?
            .prefix(18)
            .description ?? "考题证据"
    }

    private static func pedagogicalQuestionNodeSummary(link: QuestionEvidenceLink) -> String {
        let evidence = truncatedPedagogicalText(trimmedOrEmpty(link.paraphraseEvidence.first ?? ""), limit: 24)
        let answerKey = truncatedPedagogicalText(trimmedOrEmpty(link.answerKeySnippet ?? ""), limit: 20)
        let question = truncatedPedagogicalText(trimmedOrEmpty(link.questionText), limit: 22)

        let parts = [
            evidence.isEmpty ? "" : "证据：\(evidence)",
            answerKey.isEmpty ? "" : "答案线索：\(answerKey)",
            question.isEmpty ? "" : "题干：\(question)"
        ].filter { !$0.isEmpty }

        return truncatedPedagogicalText(parts.first ?? "题目联动线索", limit: 32)
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
