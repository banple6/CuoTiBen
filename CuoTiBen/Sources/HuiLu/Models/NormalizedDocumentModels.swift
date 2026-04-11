import Foundation
import CoreGraphics

// MARK: - PP-StructureV3 归一化数据模型
// 后端将 PP-StructureV3 的原始输出转换为此格式返回给 iOS 客户端

// MARK: - NormalizedDocument（顶级容器）

struct NormalizedDocument: Codable, Equatable, Sendable {
    let documentID: String
    let metadata: DocumentMetadata
    let pages: [NormalizedPage]
    let blocks: [NormalizedBlock]
    let paragraphs: [NormalizedParagraph]
    let structureCandidates: [StructureCandidate]

    private enum CodingKeys: String, CodingKey {
        case documentID = "document_id"
        case metadata, pages, blocks, paragraphs
        case structureCandidates = "structure_candidates"
    }
}

// MARK: - 文档元数据

struct DocumentMetadata: Codable, Equatable, Sendable {
    let title: String
    let fileType: String
    let pageCount: Int
    let totalBlocks: Int
    let totalParagraphs: Int
    let dominantLanguage: String   // "en" / "zh" / "mixed"
    let englishRatio: Double       // 0.0-1.0
    let parseEngine: String        // "pp_structurev3"
    let parseVersion: String
    let parseDurationMs: Int

    private enum CodingKeys: String, CodingKey {
        case title
        case fileType = "file_type"
        case pageCount = "page_count"
        case totalBlocks = "total_blocks"
        case totalParagraphs = "total_paragraphs"
        case dominantLanguage = "dominant_language"
        case englishRatio = "english_ratio"
        case parseEngine = "parse_engine"
        case parseVersion = "parse_version"
        case parseDurationMs = "parse_duration_ms"
    }
}

// MARK: - 页面

struct NormalizedPage: Codable, Equatable, Sendable {
    let page: Int
    let width: Double
    let height: Double
    let blockIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case page, width, height
        case blockIDs = "block_ids"
    }
}

// MARK: - 归一化块

struct NormalizedBlock: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let page: Int
    let order: Int
    let bbox: BoundingBox
    let blockType: NormalizedBlockType
    let zoneRole: DocumentZoneRole
    let subType: String?
    let text: String
    let language: BlockLanguage
    let confidence: Double          // 0.0-1.0
    let paragraphStart: Bool
    let paragraphEnd: Bool
    let source: String              // "pp_structurev3"

    private enum CodingKeys: String, CodingKey {
        case id, page, order, bbox
        case blockType = "block_type"
        case zoneRole = "zone_role"
        case subType = "sub_type"
        case text, language, confidence
        case paragraphStart = "paragraph_start"
        case paragraphEnd = "paragraph_end"
        case source
    }

    /// 是否适合进入结构树
    var isTreeNodeEligible: Bool {
        guard zoneRole == .passage else { return false }
        switch blockType {
        case .title, .heading, .subheading, .englishBody:
            return confidence >= 0.35
        case .questionStem, .optionList, .glossary,
             .chineseExplanation, .bilingualNote:
            return false
        case .pageHeader, .pageFooter, .reference, .noise:
            return false
        }
    }

    /// 是否为英语主体内容
    var isEnglishPrimary: Bool {
        guard zoneRole == .passage else { return false }
        switch blockType {
        case .title, .heading, .subheading, .englishBody:
            return language == .english || language == .mixed
        default:
            return false
        }
    }
}

// MARK: - 块类型（与 BlockContentType 对齐，用于后端→客户端传输）

enum NormalizedBlockType: String, Codable, CaseIterable, Sendable {
    case title = "title"
    case heading = "heading"
    case subheading = "subheading"
    case englishBody = "english_body"
    case chineseExplanation = "chinese_explanation"
    case bilingualNote = "bilingual_note"
    case questionStem = "question_stem"
    case optionList = "option_list"
    case glossary = "glossary"
    case pageHeader = "page_header"
    case pageFooter = "page_footer"
    case reference = "reference"
    case noise = "noise"

    var displayName: String {
        switch self {
        case .title:                return "标题"
        case .heading:              return "一级标题"
        case .subheading:           return "二级标题"
        case .englishBody:          return "英文正文"
        case .chineseExplanation:   return "中文说明"
        case .bilingualNote:        return "双语注释"
        case .questionStem:         return "题干"
        case .optionList:           return "选项列表"
        case .glossary:             return "词汇注解"
        case .pageHeader:           return "页眉"
        case .pageFooter:           return "页脚"
        case .reference:            return "参考文献"
        case .noise:                return "噪声"
        }
    }
}

// MARK: - 块语言

enum BlockLanguage: String, Codable, Sendable {
    case english = "en"
    case chinese = "zh"
    case mixed = "mixed"
    case unknown = "unknown"
}

enum DocumentZoneRole: String, Codable, Sendable, CaseIterable {
    case passage = "passage"
    case metaInstruction = "meta_instruction"
    case question = "question"
    case answerKey = "answer_key"
    case vocabularySupport = "vocabulary_support"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .passage: return "正文"
        case .metaInstruction: return "讲义说明"
        case .question: return "题目区"
        case .answerKey: return "答案区"
        case .vocabularySupport: return "词汇支持"
        case .unknown: return "未归类"
        }
    }
}

// MARK: - 边界框

struct BoundingBox: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

// MARK: - 归一化段落（跨块/跨页合并后的段落）

struct NormalizedParagraph: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let blockIDs: [String]          // 组成此段落的块 ID
    let page: Int                   // 起始页
    let endPage: Int                // 结束页
    let text: String                // 合并后的文本
    let language: BlockLanguage
    let zoneRole: DocumentZoneRole
    let crossPage: Bool             // 是否跨页
    let order: Int                  // 阅读顺序

    private enum CodingKeys: String, CodingKey {
        case id
        case blockIDs = "block_ids"
        case page
        case endPage = "end_page"
        case text, language
        case zoneRole = "zone_role"
        case crossPage = "cross_page"
        case order
    }

    var isPassageParagraph: Bool {
        zoneRole == .passage
    }
}

// MARK: - 结构候选节点（由后端预生成，客户端再过滤）

struct StructureCandidate: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let parentID: String?
    let depth: Int
    let order: Int
    let title: String
    let summary: String?
    let blockIDs: [String]
    let paragraphIDs: [String]
    let confidence: Double
    let candidateType: CandidateType

    private enum CodingKeys: String, CodingKey {
        case id
        case parentID = "parent_id"
        case depth, order, title, summary
        case blockIDs = "block_ids"
        case paragraphIDs = "paragraph_ids"
        case confidence
        case candidateType = "candidate_type"
    }

    enum CandidateType: String, Codable, Sendable {
        case heading = "heading"
        case section = "section"
        case paragraph = "paragraph"
    }
}

// MARK: - 后端 API 响应封装

struct DocumentParseResponse: Codable, Sendable {
    let schemaVersion: String?
    let success: Bool
    let jobID: String?
    let status: ParseJobStatus?
    let document: NormalizedDocument?
    let error: String?
    let qualityReason: String?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case success
        case jobID = "job_id"
        case status, document, error
        case qualityReason = "quality_reason"
    }
}

enum ParseJobStatus: String, Codable, Sendable {
    case pending = "pending"
    case parsing = "parsing"
    case normalizing = "normalizing"
    case completed = "completed"
    case failed = "failed"
    case timedOut = "timed_out"

    var displayName: String {
        switch self {
        case .pending:      return "排队中"
        case .parsing:      return "正在解析"
        case .normalizing:  return "正在归一化"
        case .completed:    return "完成"
        case .failed:       return "失败"
        case .timedOut:     return "超时"
        }
    }
}
