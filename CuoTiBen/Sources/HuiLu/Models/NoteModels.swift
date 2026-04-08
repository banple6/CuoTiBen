import Foundation
import CoreGraphics
import SwiftUI

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

// ═══════════════════════════════════════════════════════════════
// MARK: - Canvas Text Object (free-form text on the paper)
// ═══════════════════════════════════════════════════════════════

/// Text alignment for free-form canvas text objects.
enum CanvasTextAlignment: String, Codable, CaseIterable, Identifiable {
    case leading, center, trailing
    var id: String { rawValue }

    var label: String {
        switch self { case .leading: return "左"; case .center: return "中"; case .trailing: return "右" }
    }
    var icon: String {
        switch self { case .leading: return "text.alignleft"; case .center: return "text.aligncenter"; case .trailing: return "text.alignright" }
    }
    var swiftUIAlignment: TextAlignment {
        switch self { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing }
    }
    var nsAlignment: NSTextAlignment {
        switch self { case .leading: return .left; case .center: return .center; case .trailing: return .right }
    }
}

/// A free-form text object placed at an arbitrary (x, y) position on the note canvas.
/// Coordinates are in the paper content coordinate system (not screen pixels).
struct CanvasTextObject: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var text: String
    var x: CGFloat                           // paper-space origin x
    var y: CGFloat                           // paper-space origin y
    var width: CGFloat                       // object width (user-resizable)
    var height: CGFloat                      // auto-grows with content; user can also resize
    var rotation: CGFloat = 0               // radians; reserved for future use
    var zIndex: Int = 0                      // stacking order among text objects
    var textStyle: BlockTextStyle?
    var textColor: BlockTextColor?
    var highlightStyle: BlockHighlight?
    var fontSizePreset: BlockFontSize?
    var textAlignment: CanvasTextAlignment = .leading
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        text: String = "",
        x: CGFloat,
        y: CGFloat,
        width: CGFloat = 260,
        height: CGFloat = 44,
        rotation: CGFloat = 0,
        zIndex: Int = 0,
        textStyle: BlockTextStyle? = nil,
        textColor: BlockTextColor? = nil,
        highlightStyle: BlockHighlight? = nil,
        fontSizePreset: BlockFontSize? = nil,
        textAlignment: CanvasTextAlignment = .leading,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
        self.zIndex = zIndex
        self.textStyle = textStyle
        self.textColor = textColor
        self.highlightStyle = highlightStyle
        self.fontSizePreset = fontSizePreset
        self.textAlignment = textAlignment
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Resolved styles (with defaults)

    var resolvedTextStyle: BlockTextStyle { textStyle ?? .classicSerif }
    var resolvedTextColor: BlockTextColor { textColor ?? .inkBlack }
    var resolvedHighlight: BlockHighlight { highlightStyle ?? .none }
    var resolvedFontSize: BlockFontSize { fontSizePreset ?? .medium }
    var resolvedAlignment: CanvasTextAlignment { textAlignment }
    var minWidth: CGFloat { 80 }
    var minHeight: CGFloat { 32 }

    var frame: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
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

    // Block-level style (V1). nil = use default for the block kind.
    var textStyle: BlockTextStyle?
    var textColor: BlockTextColor?
    var highlightStyle: BlockHighlight?
    var fontSizePreset: BlockFontSize?

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
        lastRecognitionAt: Date? = nil,
        textStyle: BlockTextStyle? = nil,
        textColor: BlockTextColor? = nil,
        highlightStyle: BlockHighlight? = nil,
        fontSizePreset: BlockFontSize? = nil
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
        self.textStyle = textStyle
        self.textColor = textColor
        self.highlightStyle = highlightStyle
        self.fontSizePreset = fontSizePreset
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

    // MARK: - Resolved style (with kind-based defaults)

    var resolvedTextStyle: BlockTextStyle {
        textStyle ?? BlockStyleMapping.defaultTextStyle(for: kind)
    }

    var resolvedTextColor: BlockTextColor {
        textColor ?? BlockStyleMapping.defaultTextColor(for: kind)
    }

    var resolvedHighlight: BlockHighlight {
        highlightStyle ?? BlockStyleMapping.defaultHighlight(for: kind)
    }

    var resolvedFontSize: BlockFontSize {
        fontSizePreset ?? BlockStyleMapping.defaultFontSize(for: kind)
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
        case textStyle
        case textColor
        case highlightStyle
        case fontSizePreset
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
        textStyle = try container.decodeIfPresent(BlockTextStyle.self, forKey: .textStyle)
        textColor = try container.decodeIfPresent(BlockTextColor.self, forKey: .textColor)
        highlightStyle = try container.decodeIfPresent(BlockHighlight.self, forKey: .highlightStyle)
        fontSizePreset = try container.decodeIfPresent(BlockFontSize.self, forKey: .fontSizePreset)
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
        try container.encodeIfPresent(textStyle, forKey: .textStyle)
        try container.encodeIfPresent(textColor, forKey: .textColor)
        try container.encodeIfPresent(highlightStyle, forKey: .highlightStyle)
        try container.encodeIfPresent(fontSizePreset, forKey: .fontSizePreset)
    }
}

struct Note: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var sourceAnchor: SourceAnchor
    var blocks: [NoteBlock]
    var textObjects: [CanvasTextObject]
    var tags: [String]
    var knowledgePoints: [KnowledgePoint]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        sourceAnchor: SourceAnchor,
        blocks: [NoteBlock],
        textObjects: [CanvasTextObject] = [],
        tags: [String] = [],
        knowledgePoints: [KnowledgePoint] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.sourceAnchor = sourceAnchor
        self.blocks = blocks
        self.textObjects = textObjects
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

    /// A note has meaningful content if the user actually wrote something.
    /// Empty drafts (just an ID + default title + no blocks) are NOT meaningful.
    var hasMeaningfulContent: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasTitle = !trimmedTitle.isEmpty

        let hasText = blocks.contains { block in
            block.kind == .text &&
            !(block.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }

        let hasInk = blocks.contains { block in
            block.kind == .ink && !(block.inkData?.isEmpty ?? true)
        }

        let hasQuote = blocks.contains { block in
            block.kind == .quote &&
            !(block.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }

        let hasTags = !tags.isEmpty
        let hasKnowledge = !knowledgePoints.isEmpty
        let hasTextObjects = textObjects.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return hasTitle || hasText || hasInk || hasQuote || hasTags || hasKnowledge || hasTextObjects
    }

    // MARK: - Backward-compatible Codable

    private enum CodingKeys: String, CodingKey {
        case id, title, sourceAnchor, blocks, textObjects, tags, knowledgePoints, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        sourceAnchor = try c.decode(SourceAnchor.self, forKey: .sourceAnchor)
        blocks = try c.decode([NoteBlock].self, forKey: .blocks)
        textObjects = try c.decodeIfPresent([CanvasTextObject].self, forKey: .textObjects) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        knowledgePoints = try c.decodeIfPresent([KnowledgePoint].self, forKey: .knowledgePoints) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
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
