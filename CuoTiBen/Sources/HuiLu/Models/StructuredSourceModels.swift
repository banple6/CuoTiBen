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

struct ProfessorGrammarFocus: Codable, Equatable, Hashable {
    let phenomenon: String
    let function: String
    let whyItMatters: String

    private enum CodingKeys: String, CodingKey {
        case phenomenon
        case function
        case whyItMatters = "why_it_matters"
    }

    var rendered: String {
        let phenomenonPart = phenomenon.trimmingCharacters(in: .whitespacesAndNewlines)
        let functionPart = function.trimmingCharacters(in: .whitespacesAndNewlines)
        let whyPart = whyItMatters.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = []
        if !phenomenonPart.isEmpty { parts.append(phenomenonPart) }
        if !functionPart.isEmpty { parts.append(functionPart) }
        if !whyPart.isEmpty { parts.append("为什么重要：\(whyPart)") }
        return parts.joined(separator: "｜")
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
        self.faithfulTranslation = !normalizedFaithfulTranslation.isEmpty
            ? normalizedFaithfulTranslation
            : ""
        self.teachingInterpretation = !normalizedTeachingInterpretation.isEmpty
            ? normalizedTeachingInterpretation
            : (!normalizedLegacyMeaning.isEmpty ? normalizedLegacyMeaning : "")
        self.naturalChineseMeaning = !normalizedLegacyMeaning.isEmpty
            ? normalizedLegacyMeaning
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
        faithfulTranslation = trimmedOrEmpty(decodedFaithfulTranslation).isEmpty
            ? ""
            : decodedFaithfulTranslation
        teachingInterpretation = trimmedOrEmpty(decodedTeachingInterpretation).isEmpty
            ? (trimmedOrEmpty(decodedLegacyMeaning).isEmpty ? "" : decodedLegacyMeaning)
            : decodedTeachingInterpretation
        naturalChineseMeaning = trimmedOrEmpty(decodedLegacyMeaning).isEmpty ? teachingInterpretation : decodedLegacyMeaning
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
        if let skeleton = coreSkeleton {
            let rendered = skeleton.rendered.trimmingCharacters(in: .whitespacesAndNewlines)
            if !rendered.isEmpty { return rendered }
        }
        return sentenceCore
    }

    var renderedFaithfulTranslation: String {
        let explicit = purifiedChineseExplanation(faithfulTranslation)
        if !explicit.isEmpty { return explicit }
        return ""
    }

    var renderedTeachingInterpretation: String {
        let explicit = purifiedChineseExplanation(teachingInterpretation)
        if !explicit.isEmpty { return explicit }
        let legacy = purifiedChineseExplanation(naturalChineseMeaning)
        if !legacy.isEmpty { return legacy }
        return ""
    }

    var renderedChunkLayers: [String] {
        if !chunkLayers.isEmpty {
            return chunkLayers.map(\.rendered)
        }
        return chunkBreakdown
    }

    var displayedCoreSkeleton: ProfessorCoreSkeleton {
        if let coreSkeleton {
            return coreSkeleton
        }

        let segments = sentenceCore.split(separator: "｜").map(String.init)
        var subject = ""
        var predicate = ""
        var complement = ""

        for segment in segments {
            if segment.contains("主语：") {
                subject = segment.replacingOccurrences(of: "主语：", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if segment.contains("谓语：") {
                predicate = segment.replacingOccurrences(of: "谓语：", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if segment.contains("核心补足：") {
                complement = segment.replacingOccurrences(of: "核心补足：", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return ProfessorCoreSkeleton(
            subject: subject,
            predicate: predicate,
            complementOrObject: complement
        )
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
        if !grammarFocus.isEmpty {
            return purifiedChineseList(grammarFocus.map(\.rendered), limit: 3)
        }
        return purifiedChineseList(grammarPoints.map { "\($0.name)：\($0.explanation)" }, limit: 3)
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
            parts.append("译意：\(faithful)")
        }

        let roles = displayedChunkLayers.map(\.role)
        if roles.contains(where: { $0.contains("前置") || $0.contains("条件") || $0.contains("让步") || $0.contains("后置") }) {
            parts.append("简化时把外围框架和修饰层压缩掉，保留了原句主干判断。")
        } else {
            parts.append("简化时保留原意，把句子改成更直接的主谓表达。")
        }

        return parts.joined(separator: " ")
    }

    var renderedMiniCheck: String? {
        let trimmed = miniCheck?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? miniExercise : trimmed
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
    if isChineseDominant(trimmed) {
        return trimmed
    }

    let recovered = purifiedChineseSentences(from: trimmed)
    guard !recovered.isEmpty else { return "" }
    return recovered.joined(separator: "。")
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

        return StructuredSourceBundle(
            source: source,
            segments: segments,
            sentences: sentences,
            outline: mergedOutline,
            passageOverview: (overview?.mergingFallback(passageOverview)) ?? passageOverview,
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
            let questionNodes = linkedQuestions.enumerated().map { offset, link in
                let localSentenceIDs = link.supportingSentenceIDs.filter {
                    sentenceSegmentIndex[$0] == card.segmentID
                }
                let anchorSentenceID = localSentenceIDs.first ?? card.coreSentenceID
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
                    sourceSentenceIDs: localSentenceIDs,
                    children: []
                )
            }
            let supportingSentenceNodes = sentences
                .filter { sentence in
                    sentence.id == card.coreSentenceID || sentenceCardIndex[sentence.id]?.isKeySentence == true
                }
                .prefix(2)
                .map { sentence in
                    let analysis = sentenceCardIndex[sentence.id]?.analysis
                    return OutlineNode(
                        id: "support_\(sentence.id)",
                        sourceID: sourceID,
                        parentID: "para_\(card.segmentID)",
                        depth: 2,
                        order: sentence.index,
                        nodeType: .supportingSentence,
                        title: pedagogicalSentenceNodeTitle(sentence: sentence, analysis: analysis),
                        summary: pedagogicalSentenceNodeSummary(sentence: sentence, analysis: analysis),
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

            let focusSummary = pedagogicalFocusSummary(card: card, linkedQuestions: linkedQuestions)
            let focusNode = OutlineNode(
                id: "focus_\(card.segmentID)",
                sourceID: sourceID,
                parentID: "para_\(card.segmentID)",
                depth: 2,
                order: card.paragraphIndex * 10,
                nodeType: .teachingFocus,
                title: pedagogicalFocusTitle(card: card),
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
                title: pedagogicalParagraphTitle(card: card),
                summary: pedagogicalParagraphSummary(card: card, linkedQuestions: linkedQuestions),
                anchor: OutlineAnchor(
                    segmentID: card.segmentID,
                    sentenceID: card.coreSentenceID,
                    page: sentences.first?.page,
                    label: card.anchorLabel
                ),
                sourceSegmentIDs: [card.segmentID],
                sourceSentenceIDs: sentences.map(\.id),
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
            title: "文章主题与问题意识",
            summary: pedagogicalRootSummary(overview: overview),
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

    private static func pedagogicalRootSummary(overview: PassageOverview?) -> String {
        guard let overview else { return "正文教学树" }
        let theme = trimmedOrEmpty(overview.displayedArticleTheme)
        let question = trimmedOrEmpty(overview.displayedAuthorCoreQuestion)
        let progression = trimmedOrEmpty(overview.displayedProgressionPath)
        let questionType = trimmedOrEmpty(overview.displayedLikelyQuestionTypes.first ?? "")
        let logicPitfall = trimmedOrEmpty(overview.displayedLogicPitfalls.first ?? "")

        let parts = [theme, question, progression, questionType.isEmpty ? "" : "高频题型：\(questionType)", logicPitfall.isEmpty ? "" : "逻辑易错：\(logicPitfall)"]
            .filter { !$0.isEmpty }

        return parts.isEmpty ? "正文教学树" : parts.joined(separator: "｜")
    }

    private static func pedagogicalParagraphTitle(card: ParagraphTeachingCard) -> String {
        let theme = trimmedOrEmpty(card.displayedTheme)
        let shortTheme = theme.count > 22 ? String(theme.prefix(22)) + "…" : theme
        if !shortTheme.isEmpty {
            return "第\(card.paragraphIndex + 1)段｜\(card.argumentRole.displayName)｜\(shortTheme)"
        }
        return "第\(card.paragraphIndex + 1)段｜\(card.argumentRole.displayName)"
    }

    private static func pedagogicalParagraphSummary(
        card: ParagraphTeachingCard,
        linkedQuestions: [QuestionEvidenceLink]
    ) -> String {
        var parts: [String] = []

        let theme = trimmedOrEmpty(card.displayedTheme)
        if !theme.isEmpty {
            parts.append(theme)
        }

        let relation = trimmedOrEmpty(card.displayedRelationToPrevious)
        if !relation.isEmpty {
            parts.append("和上一段：\(relation)")
        }

        let examValue = trimmedOrEmpty(card.displayedExamValue)
        if !examValue.isEmpty {
            parts.append("题型价值：\(examValue)")
        }

        if let blindSpot = card.displayedStudentBlindSpot, !blindSpot.isEmpty {
            parts.append("学生易偏：\(blindSpot)")
        }

        if let linkedQuestion = linkedQuestions.first {
            let trap = trimmedOrEmpty(linkedQuestion.trapType)
            let evidence = trimmedOrEmpty(linkedQuestion.paraphraseEvidence.first ?? "")
            let hint = [trap, evidence].filter { !$0.isEmpty }.joined(separator: "｜")
            if !hint.isEmpty {
                parts.append("对应考点：\(hint)")
            }
        }

        return pedagogicalList(parts, fallback: [theme, examValue], limit: 4).joined(separator: "；")
    }

    private static func pedagogicalFocusTitle(card: ParagraphTeachingCard) -> String {
        if let first = card.displayedTeachingFocuses.first, !trimmedOrEmpty(first).isEmpty {
            let focus = trimmedOrEmpty(first)
            let shortFocus = focus.count > 24 ? String(focus.prefix(24)) + "…" : focus
            return "教学重点｜\(shortFocus)"
        }
        return "教学重点"
    }

    private static func pedagogicalFocusSummary(
        card: ParagraphTeachingCard,
        linkedQuestions: [QuestionEvidenceLink]
    ) -> String {
        var parts = [
            trimmedOrEmpty(card.examValue),
            trimmedOrEmpty(card.studentBlindSpot ?? "")
        ].filter { !$0.isEmpty }

        parts.append(contentsOf: pedagogicalList(card.displayedTeachingFocuses, fallback: [], limit: 3))

        if let blindSpot = card.studentBlindSpot?.trimmingCharacters(in: .whitespacesAndNewlines), !blindSpot.isEmpty {
            parts.append("易偏点：\(blindSpot)")
        }

        if let firstQuestion = linkedQuestions.first {
            let evidence = trimmedOrEmpty(firstQuestion.paraphraseEvidence.first ?? "")
            let trap = trimmedOrEmpty(firstQuestion.trapType)
            let questionHint = [trap, evidence].filter { !$0.isEmpty }.joined(separator: "｜")
            if !questionHint.isEmpty {
                parts.append("对应考点：\(questionHint)")
            }
        }

        if parts.isEmpty {
            parts.append(card.examValue)
        }

        return pedagogicalList(parts, fallback: [card.examValue], limit: 4).joined(separator: "；")
    }

    private static func pedagogicalSentenceNodeTitle(
        sentence: Sentence,
        analysis: ProfessorSentenceAnalysis?
    ) -> String {
        if let analysis {
            let core = trimmedOrEmpty(analysis.renderedSentenceCore)
            if !core.isEmpty {
                let function = trimmedOrEmpty(analysis.renderedSentenceFunction)
                if !function.isEmpty {
                    let functionHead = function
                        .split(separator: "：", maxSplits: 1)
                        .first
                        .map(String.init)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !functionHead.isEmpty {
                        return "\(functionHead)｜\(core)"
                    }
                }
                return core
            }
        }
        return String(sentence.text.prefix(60))
    }

    private static func pedagogicalSentenceNodeSummary(
        sentence: Sentence,
        analysis: ProfessorSentenceAnalysis?
    ) -> String {
        guard let analysis else { return sentence.text }

        let parts = [
            trimmedOrEmpty(analysis.renderedSentenceFunction),
            trimmedOrEmpty(analysis.renderedSentenceCore),
            trimmedOrEmpty(analysis.renderedMisreadingTraps.first ?? ""),
            trimmedOrEmpty(analysis.renderedExamParaphraseRoutes.first ?? ""),
            trimmedOrEmpty(analysis.renderedChunkLayers.first ?? "")
        ].compactMap { $0 }.filter { !$0.isEmpty }

        return parts.isEmpty ? sentence.text : parts.joined(separator: "｜")
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
        var parts: [String] = []
        let question = trimmedOrEmpty(link.questionText)
        let evidence = trimmedOrEmpty(link.paraphraseEvidence.first ?? "")
        let answerKey = trimmedOrEmpty(link.answerKeySnippet ?? "")

        if !question.isEmpty {
            parts.append("题干：\(question)")
        }
        if !evidence.isEmpty {
            parts.append("证据：\(evidence)")
        }
        if !answerKey.isEmpty {
            parts.append("答案线索：\(answerKey)")
        }

        return parts.joined(separator: "｜")
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
