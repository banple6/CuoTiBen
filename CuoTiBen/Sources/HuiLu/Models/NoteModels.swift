import Foundation
import CoreGraphics

struct SourceAnchor: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let sourceID: UUID
    let sourceTitle: String
    let pageIndex: Int?
    let sentenceID: String?
    let outlineNodeID: String?
    let quotedText: String
    let anchorLabel: String

    init(
        id: String = UUID().uuidString,
        sourceID: UUID,
        sourceTitle: String,
        pageIndex: Int?,
        sentenceID: String?,
        outlineNodeID: String?,
        quotedText: String,
        anchorLabel: String
    ) {
        self.id = id
        self.sourceID = sourceID
        self.sourceTitle = sourceTitle
        self.pageIndex = pageIndex
        self.sentenceID = sentenceID
        self.outlineNodeID = outlineNodeID
        self.quotedText = quotedText
        self.anchorLabel = anchorLabel
    }
}

struct KnowledgePoint: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var title: String
    var definition: String
    var shortDefinition: String?
    var aliases: [String]
    var sourceAnchors: [SourceAnchor]
    var relatedKnowledgePointIDs: [String]

    init(
        id: String? = nil,
        title: String,
        definition: String = "",
        shortDefinition: String? = nil,
        aliases: [String] = [],
        sourceAnchors: [SourceAnchor] = [],
        relatedKnowledgePointIDs: [String] = []
    ) {
        self.id = id ?? KnowledgePoint.normalizedID(for: title)
        self.title = title
        self.definition = definition
        self.shortDefinition = shortDefinition
        self.aliases = aliases
        self.sourceAnchors = sourceAnchors
        self.relatedKnowledgePointIDs = relatedKnowledgePointIDs
    }

    static func normalizedID(for title: String) -> String {
        let normalized = title
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\u4e00-\\u9fa5]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return normalized.isEmpty ? UUID().uuidString.lowercased() : normalized
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case definition
        case shortDefinition
        case aliases
        case sourceAnchors
        case relatedKnowledgePointIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        definition = try container.decodeIfPresent(String.self, forKey: .definition) ?? ""
        shortDefinition = try container.decodeIfPresent(String.self, forKey: .shortDefinition)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        sourceAnchors = try container.decodeIfPresent([SourceAnchor].self, forKey: .sourceAnchors) ?? []
        relatedKnowledgePointIDs = try container.decodeIfPresent([String].self, forKey: .relatedKnowledgePointIDs) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(definition, forKey: .definition)
        try container.encodeIfPresent(shortDefinition, forKey: .shortDefinition)
        try container.encode(aliases, forKey: .aliases)
        try container.encode(sourceAnchors, forKey: .sourceAnchors)
        try container.encode(relatedKnowledgePointIDs, forKey: .relatedKnowledgePointIDs)
    }
}

struct InkGeometry: Codable, Equatable, Hashable {
    var normalizedBounds: CGRect
    var pageIndex: Int?
    var pageCount: Int?

    init(normalizedBounds: CGRect, pageIndex: Int? = nil, pageCount: Int? = nil) {
        self.normalizedBounds = normalizedBounds
        self.pageIndex = pageIndex
        self.pageCount = pageCount
    }
}

enum NoteBlockKind: String, Codable, CaseIterable {
    case quote
    case text
    case ink
}

struct NoteBlock: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var kind: NoteBlockKind
    var text: String?
    var inkData: Data?
    var inkPreviewImageData: Data?
    var recognizedText: String?
    var recognitionConfidence: Double?
    var linkedSourceAnchorID: String?
    var linkedKnowledgePointIDs: [String]
    var inkGeometry: InkGeometry?
    var createdAt: Date
    var updatedAt: Date
    var lastSuggestionAt: Date?
    var lastRecognitionAt: Date?

    init(
        id: UUID = UUID(),
        kind: NoteBlockKind,
        text: String? = nil,
        inkData: Data? = nil,
        inkPreviewImageData: Data? = nil,
        recognizedText: String? = nil,
        recognitionConfidence: Double? = nil,
        linkedSourceAnchorID: String? = nil,
        linkedKnowledgePointIDs: [String] = [],
        inkGeometry: InkGeometry? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastSuggestionAt: Date? = nil,
        lastRecognitionAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.inkData = inkData
        self.inkPreviewImageData = inkPreviewImageData
        self.recognizedText = recognizedText
        self.recognitionConfidence = recognitionConfidence
        self.linkedSourceAnchorID = linkedSourceAnchorID
        self.linkedKnowledgePointIDs = linkedKnowledgePointIDs
        self.inkGeometry = inkGeometry
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSuggestionAt = lastSuggestionAt
        self.lastRecognitionAt = lastRecognitionAt
    }

    static func quote(_ text: String) -> NoteBlock {
        NoteBlock(kind: .quote, text: text)
    }

    static func text(_ text: String) -> NoteBlock {
        NoteBlock(kind: .text, text: text)
    }

    static func ink(
        _ data: Data,
        recognizedText: String? = nil,
        recognitionConfidence: Double? = nil,
        linkedSourceAnchorID: String? = nil,
        linkedKnowledgePointIDs: [String] = [],
        inkGeometry: InkGeometry? = nil,
        inkPreviewImageData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastSuggestionAt: Date? = nil,
        lastRecognitionAt: Date? = nil
    ) -> NoteBlock {
        NoteBlock(
            kind: .ink,
            inkData: data,
            inkPreviewImageData: inkPreviewImageData,
            recognizedText: recognizedText,
            recognitionConfidence: recognitionConfidence,
            linkedSourceAnchorID: linkedSourceAnchorID,
            linkedKnowledgePointIDs: linkedKnowledgePointIDs,
            inkGeometry: inkGeometry,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastSuggestionAt: lastSuggestionAt,
            lastRecognitionAt: lastRecognitionAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case text
        case inkData
        case inkPreviewImageData
        case recognizedText
        case recognitionConfidence
        case linkedSourceAnchorID
        case linkedKnowledgePointIDs
        case inkGeometry
        case createdAt
        case updatedAt
        case lastSuggestionAt
        case lastRecognitionAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(NoteBlockKind.self, forKey: .kind)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        inkData = try container.decodeIfPresent(Data.self, forKey: .inkData)
        inkPreviewImageData = try container.decodeIfPresent(Data.self, forKey: .inkPreviewImageData)
        recognizedText = try container.decodeIfPresent(String.self, forKey: .recognizedText)
        recognitionConfidence = try container.decodeIfPresent(Double.self, forKey: .recognitionConfidence)
        linkedSourceAnchorID = try container.decodeIfPresent(String.self, forKey: .linkedSourceAnchorID)
        linkedKnowledgePointIDs = try container.decodeIfPresent([String].self, forKey: .linkedKnowledgePointIDs) ?? []
        inkGeometry = try container.decodeIfPresent(InkGeometry.self, forKey: .inkGeometry)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        lastSuggestionAt = try container.decodeIfPresent(Date.self, forKey: .lastSuggestionAt)
        lastRecognitionAt = try container.decodeIfPresent(Date.self, forKey: .lastRecognitionAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(inkData, forKey: .inkData)
        try container.encodeIfPresent(inkPreviewImageData, forKey: .inkPreviewImageData)
        try container.encodeIfPresent(recognizedText, forKey: .recognizedText)
        try container.encodeIfPresent(recognitionConfidence, forKey: .recognitionConfidence)
        try container.encodeIfPresent(linkedSourceAnchorID, forKey: .linkedSourceAnchorID)
        try container.encode(linkedKnowledgePointIDs, forKey: .linkedKnowledgePointIDs)
        try container.encodeIfPresent(inkGeometry, forKey: .inkGeometry)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(lastSuggestionAt, forKey: .lastSuggestionAt)
        try container.encodeIfPresent(lastRecognitionAt, forKey: .lastRecognitionAt)
    }
}

struct Note: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var sourceAnchor: SourceAnchor
    var blocks: [NoteBlock]
    var tags: [String]
    var knowledgePoints: [KnowledgePoint]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        sourceAnchor: SourceAnchor,
        blocks: [NoteBlock],
        tags: [String] = [],
        knowledgePoints: [KnowledgePoint] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.sourceAnchor = sourceAnchor
        self.blocks = blocks
        self.tags = tags
        self.knowledgePoints = knowledgePoints
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var quoteBlock: NoteBlock? {
        blocks.first(where: { $0.kind == .quote })
    }

    var textBlocks: [NoteBlock] {
        blocks.filter { $0.kind == .text }
    }

    var inkBlocks: [NoteBlock] {
        blocks.filter { $0.kind == .ink }
    }

    var summary: String {
        let textSummary = textBlocks
            .compactMap(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        if let textSummary {
            return textSummary
        }

        return sourceAnchor.quotedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var linkedKnowledgePointIDs: [String] {
        Array(
            Set(
                knowledgePoints.map(\.id) +
                blocks.flatMap(\.linkedKnowledgePointIDs)
            )
        )
        .sorted()
    }
}

struct NoteEditorSeed: Identifiable {
    let id = UUID()
    let document: SourceDocument
    let sentence: Sentence
    let anchor: SourceAnchor
    let suggestedTitle: String
    let suggestedBody: String
    let suggestedTags: [String]
    let suggestedKnowledgePoints: [KnowledgePoint]
}
