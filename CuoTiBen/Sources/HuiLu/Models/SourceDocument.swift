import Foundation

// MARK: - Source Document Type
/// Represents the type of imported material
public enum SourceDocumentType: String, Codable, CaseIterable {
    case pdf = "PDF"
    case image = "Image"
    case text = "Text"
    case scan = "Scan"
    
    public var displayName: String {
        switch self {
        case .pdf: return "文档文件"
        case .image: return "相册截图"
        case .text: return "文本笔记"
        case .scan: return "拍照扫描"
        }
    }

    public var icon: String {
        switch self {
        case .pdf: return "doc.text.fill"
        case .image: return "photo.fill"
        case .text: return "text.alignleft"
        case .scan: return "doc.viewfinder"
        }
    }
}

public enum DocumentProcessingStatus: String, Codable, CaseIterable {
    case imported = "已导入"
    case parsing = "解析中"
    case ready = "已就绪"
    case failed = "失败"

    public var displayName: String {
        rawValue
    }

    public var icon: String {
        switch self {
        case .imported: return "tray.full.fill"
        case .parsing: return "wand.and.stars"
        case .ready: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Source Document Model
/// Represents an imported learning material
public struct SourceDocument: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var documentType: SourceDocumentType
    public var importDate: Date
    public var pageCount: Int
    public var filePath: String? // Local file path
    public var subjectID: UUID?
    public var thumbnailData: Data?
    public var processingStatus: DocumentProcessingStatus
    public var extractedText: String
    public var sectionTitles: [String]
    public var topicTags: [String]
    public var candidateKnowledgePoints: [String]
    public var chunkCount: Int
    public var generatedCardCount: Int
    public var lastProcessingError: String?
    
    public init(
        id: UUID = UUID(),
        title: String,
        documentType: SourceDocumentType,
        importDate: Date = Date(),
        pageCount: Int = 0,
        filePath: String? = nil,
        subjectID: UUID? = nil,
        thumbnailData: Data? = nil,
        processingStatus: DocumentProcessingStatus = .imported,
        extractedText: String = "",
        sectionTitles: [String] = [],
        topicTags: [String] = [],
        candidateKnowledgePoints: [String] = [],
        chunkCount: Int = 0,
        generatedCardCount: Int = 0,
        lastProcessingError: String? = nil
    ) {
        self.id = id
        self.title = title
        self.documentType = documentType
        self.importDate = importDate
        self.pageCount = pageCount
        self.filePath = filePath
        self.subjectID = subjectID
        self.thumbnailData = thumbnailData
        self.processingStatus = processingStatus
        self.extractedText = extractedText
        self.sectionTitles = sectionTitles
        self.topicTags = topicTags
        self.candidateKnowledgePoints = candidateKnowledgePoints
        self.chunkCount = chunkCount
        self.generatedCardCount = generatedCardCount
        self.lastProcessingError = lastProcessingError
    }
}
