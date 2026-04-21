import Foundation

enum SourceContentKind: String, Codable, CaseIterable, Equatable, Hashable {
    case passageBody = "passage_body"
    case question = "question"
    case answerKey = "answer_key"
    case vocabularySupport = "vocabulary_support"
    case chineseInstruction = "chinese_instruction"
    case bilingualNote = "bilingual_note"
    case noise = "noise"
    case unknown = "unknown"

    // 兼容旧缓存/旧结构字段
    case passageHeading = "passage_heading"
    case synthetic = "synthetic"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch rawValue {
        case "passage_body":
            self = .passageBody
        case "question", "question_support":
            self = .question
        case "answer_key", "answer_support":
            self = .answerKey
        case "vocabulary_support":
            self = .vocabularySupport
        case "chinese_instruction", "chinese_explanation":
            self = .chineseInstruction
        case "bilingual_note", "bilingual_annotation":
            self = .bilingualNote
        case "noise", "polluted":
            self = .noise
        case "passage_heading":
            self = .passageHeading
        case "synthetic":
            self = .synthetic
        default:
            self = .unknown
        }
    }

    var displayName: String {
        switch self {
        case .passageBody:
            return "英文正文"
        case .question:
            return "题目块"
        case .answerKey:
            return "答案区"
        case .vocabularySupport:
            return "词汇支持"
        case .chineseInstruction:
            return "中文说明"
        case .bilingualNote:
            return "双语注释"
        case .noise:
            return "污染块"
        case .unknown:
            return "未知来源"
        case .passageHeading:
            return "正文标题"
        case .synthetic:
            return "本地补全"
        }
    }

    var isAllowedForMainlineSource: Bool {
        self == .passageBody
    }

    var defaultsToAuxiliary: Bool {
        switch self {
        case .question, .answerKey, .vocabularySupport, .chineseInstruction, .bilingualNote:
            return true
        case .passageBody, .noise, .unknown, .passageHeading, .synthetic:
            return false
        }
    }
}

enum NodeGeneratedFrom: String, Codable, CaseIterable, Equatable, Hashable {
    case paragraphCard = "paragraph_card"
    case sentenceCard = "sentence_card"
    case questionLink = "question_link"
    case localFallback = "local_fallback"
    case aiPassageAnalysis = "ai_passage_analysis"
    case aiSentenceAnalysis = "ai_sentence_analysis"
    case normalizedDocument = "normalized_document"
    case unknown = "unknown"
}

struct NodeProvenance: Codable, Equatable, Hashable {
    let sourceSegmentID: String?
    let sourceSentenceID: String?
    let sourceBlockID: String?
    let sourcePage: Int?
    let sourceKind: SourceContentKind
    let generatedFrom: NodeGeneratedFrom
    let hygieneScore: Double
    let consistencyScore: Double
    let rejectedReason: String?

    private enum CodingKeys: String, CodingKey {
        case sourceSegmentID = "source_segment_id"
        case sourceSentenceID = "source_sentence_id"
        case sourceBlockID = "source_block_id"
        case sourcePage = "source_page"
        case sourceKind = "source_kind"
        case generatedFrom = "generated_from"
        case hygieneScore = "hygiene_score"
        case consistencyScore = "consistency_score"
        case rejectedReason = "rejected_reason"
    }

    init(
        sourceSegmentID: String?,
        sourceSentenceID: String?,
        sourceBlockID: String? = nil,
        sourcePage: Int? = nil,
        sourceKind: SourceContentKind,
        generatedFrom: NodeGeneratedFrom = .unknown,
        hygieneScore: Double = 0.5,
        consistencyScore: Double,
        rejectedReason: String? = nil
    ) {
        self.sourceSegmentID = sourceSegmentID
        self.sourceSentenceID = sourceSentenceID
        self.sourceBlockID = sourceBlockID
        self.sourcePage = sourcePage
        self.sourceKind = sourceKind
        self.generatedFrom = generatedFrom
        self.hygieneScore = hygieneScore
        self.consistencyScore = consistencyScore
        self.rejectedReason = rejectedReason
    }

    static let unknown = NodeProvenance(
        sourceSegmentID: nil,
        sourceSentenceID: nil,
        sourceBlockID: nil,
        sourcePage: nil,
        sourceKind: .unknown,
        generatedFrom: .unknown,
        hygieneScore: 0.5,
        consistencyScore: 0.5,
        rejectedReason: "来源未知，暂不进入主导图。"
    )

    var isMainlineEligible: Bool {
        sourceKind.isAllowedForMainlineSource &&
        hygieneScore >= 0.6 &&
        consistencyScore >= 0.75 &&
        sourceSegmentID != nil
    }

    func withRejectedReason(_ reason: String?) -> NodeProvenance {
        NodeProvenance(
            sourceSegmentID: sourceSegmentID,
            sourceSentenceID: sourceSentenceID,
            sourceBlockID: sourceBlockID,
            sourcePage: sourcePage,
            sourceKind: sourceKind,
            generatedFrom: generatedFrom,
            hygieneScore: hygieneScore,
            consistencyScore: consistencyScore,
            rejectedReason: reason
        )
    }
}
