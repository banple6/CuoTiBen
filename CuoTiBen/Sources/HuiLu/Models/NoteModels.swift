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

enum CanvasViewportFitMode: String, Codable, CaseIterable {
    case free
    case fitWidth
    case fitPage
}

struct CanvasViewportInsets: Codable, Equatable, Hashable {
    var top: CGFloat
    var leading: CGFloat
    var bottom: CGFloat
    var trailing: CGFloat

    init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    static let notebookDefault = CanvasViewportInsets(top: 32, leading: 20, bottom: 40, trailing: 20)
}

struct CanvasViewportState: Codable, Equatable, Hashable {
    var zoomScale: CGFloat
    var contentOffset: CGPoint
    var visibleRect: CGRect
    var fitMode: CanvasViewportFitMode
    var pageInsets: CanvasViewportInsets

    init(
        zoomScale: CGFloat = 1,
        contentOffset: CGPoint = .zero,
        visibleRect: CGRect = .zero,
        fitMode: CanvasViewportFitMode = .fitWidth,
        pageInsets: CanvasViewportInsets = .notebookDefault
    ) {
        self.zoomScale = zoomScale
        self.contentOffset = contentOffset
        self.visibleRect = visibleRect
        self.fitMode = fitMode
        self.pageInsets = pageInsets
    }
}

enum NotePaperStyle: String, Codable, CaseIterable {
    case lined
    case grid
    case dotted
    case plain
    case cornell
    case readingStudy
    case wrongAnswer
}

struct NotePaperConfiguration: Codable, Equatable, Hashable {
    var size: CGSize
    var style: NotePaperStyle
    var lineSpacing: CGFloat
    var marginInsets: CanvasViewportInsets
    var cornerRadius: CGFloat

    init(
        size: CGSize = CGSize(width: 960, height: 1_360),
        style: NotePaperStyle = .lined,
        lineSpacing: CGFloat = 34,
        marginInsets: CanvasViewportInsets = CanvasViewportInsets(
            top: 64,
            leading: 72,
            bottom: 72,
            trailing: 48
        ),
        cornerRadius: CGFloat = 4
    ) {
        self.size = size
        self.style = style
        self.lineSpacing = lineSpacing
        self.marginInsets = marginInsets
        self.cornerRadius = cornerRadius
    }

    static let notebookDefault = NotePaperConfiguration()
}

enum CanvasLayerKind: String, Codable, CaseIterable {
    case paper
    case backgroundReference
    case ink
    case object
    case overlay
}

enum CanvasElementKind: String, Codable, CaseIterable {
    case inkStroke
    case textObject
    case imageObject
    case quoteObject
    case knowledgeCardObject
    case linkPreviewObject
    case inkSelectionObject
}

enum CanvasElementLayoutRole: String, Codable, CaseIterable {
    case floating
    case flow
    case backgroundReference
    case transient
}

struct CanvasElementMetadata: Codable, Equatable, Hashable {
    var sourceAnchorID: String?
    var linkedKnowledgePointIDs: [String]
    var pageID: UUID?
    var layerID: UUID?
    var isLocked: Bool
    var isVisible: Bool
    var zIndex: Int
    var layoutRole: CanvasElementLayoutRole
    var createdAt: Date
    var updatedAt: Date

    init(
        sourceAnchorID: String? = nil,
        linkedKnowledgePointIDs: [String] = [],
        pageID: UUID? = nil,
        layerID: UUID? = nil,
        isLocked: Bool = false,
        isVisible: Bool = true,
        zIndex: Int = 0,
        layoutRole: CanvasElementLayoutRole = .floating,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.sourceAnchorID = sourceAnchorID
        self.linkedKnowledgePointIDs = linkedKnowledgePointIDs
        self.pageID = pageID
        self.layerID = layerID
        self.isLocked = isLocked
        self.isVisible = isVisible
        self.zIndex = zIndex
        self.layoutRole = layoutRole
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct InkStrokeObject: Codable, Equatable, Hashable {
    var drawingData: Data
    var previewImageData: Data?
    var recognizedText: String?
    var confidence: Double?
    var geometry: InkGeometry?

    init(
        drawingData: Data,
        previewImageData: Data? = nil,
        recognizedText: String? = nil,
        confidence: Double? = nil,
        geometry: InkGeometry? = nil
    ) {
        self.drawingData = drawingData
        self.previewImageData = previewImageData
        self.recognizedText = recognizedText
        self.confidence = confidence
        self.geometry = geometry
    }
}

struct CanvasImageObject: Codable, Equatable, Hashable {
    var imageData: Data?
    var remoteURL: String?
    var caption: String?
}

struct CanvasQuoteObject: Codable, Equatable, Hashable {
    var text: String
    var sourceAnchorID: String?
    var citation: String?
    var textStyle: BlockTextStyle?
    var textColor: BlockTextColor?
    var highlightStyle: BlockHighlight?
    var fontSizePreset: BlockFontSize?
}

struct CanvasKnowledgeCardObject: Codable, Equatable, Hashable {
    var title: String
    var summary: String
    var linkedKnowledgePointIDs: [String]
}

struct CanvasLinkPreviewObject: Codable, Equatable, Hashable {
    var title: String
    var url: String
    var summary: String?
}

struct InkSelectionObject: Codable, Equatable, Hashable {
    var selectedStrokeBounds: CGRect
    var selectedStrokeCount: Int
}

struct CanvasElement: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var kind: CanvasElementKind
    var frame: CGRect
    var rotation: CGFloat
    var metadata: CanvasElementMetadata
    var inkStroke: InkStrokeObject?
    var textObject: CanvasTextObject?
    var imageObject: CanvasImageObject?
    var quoteObject: CanvasQuoteObject?
    var knowledgeCardObject: CanvasKnowledgeCardObject?
    var linkPreviewObject: CanvasLinkPreviewObject?
    var inkSelectionObject: InkSelectionObject?

    init(
        id: UUID = UUID(),
        kind: CanvasElementKind,
        frame: CGRect,
        rotation: CGFloat = 0,
        metadata: CanvasElementMetadata = CanvasElementMetadata(),
        inkStroke: InkStrokeObject? = nil,
        textObject: CanvasTextObject? = nil,
        imageObject: CanvasImageObject? = nil,
        quoteObject: CanvasQuoteObject? = nil,
        knowledgeCardObject: CanvasKnowledgeCardObject? = nil,
        linkPreviewObject: CanvasLinkPreviewObject? = nil,
        inkSelectionObject: InkSelectionObject? = nil
    ) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.rotation = rotation
        self.metadata = metadata
        self.inkStroke = inkStroke
        self.textObject = textObject
        self.imageObject = imageObject
        self.quoteObject = quoteObject
        self.knowledgeCardObject = knowledgeCardObject
        self.linkPreviewObject = linkPreviewObject
        self.inkSelectionObject = inkSelectionObject
    }

    var effectiveFrame: CGRect {
        textObject?.frame ?? frame
    }

    var resolvedZIndex: Int {
        metadata.zIndex
    }

    var isVisibleObject: Bool {
        metadata.isVisible
    }

    var isFloatingObject: Bool {
        metadata.layoutRole == .floating
    }

    var isFlowObject: Bool {
        metadata.layoutRole == .flow
    }

    func withFrame(_ newFrame: CGRect) -> CanvasElement {
        var copy = self
        copy.frame = newFrame
        copy.metadata.updatedAt = Date()
        if var textObject = copy.textObject {
            textObject.x = newFrame.origin.x
            textObject.y = newFrame.origin.y
            textObject.width = newFrame.width
            textObject.height = newFrame.height
            textObject.updatedAt = copy.metadata.updatedAt
            copy.textObject = textObject
        }
        return copy
    }

    func withText(_ newText: String) -> CanvasElement {
        var copy = self
        copy.metadata.updatedAt = Date()
        switch kind {
        case .textObject:
            if var textObject = copy.textObject {
                textObject.text = newText
                textObject.updatedAt = copy.metadata.updatedAt
                copy.textObject = textObject
            }
        case .quoteObject:
            if var quoteObject = copy.quoteObject {
                quoteObject.text = newText
                copy.quoteObject = quoteObject
            }
        default:
            break
        }
        return copy
    }

    func withTextStyle(
        textStyle: BlockTextStyle? = nil,
        textColor: BlockTextColor? = nil,
        highlightStyle: BlockHighlight? = nil,
        fontSizePreset: BlockFontSize? = nil,
        textAlignment: CanvasTextAlignment? = nil
    ) -> CanvasElement {
        var copy = self
        copy.metadata.updatedAt = Date()

        if var textObject = copy.textObject {
            if let textStyle { textObject.textStyle = textStyle }
            if let textColor { textObject.textColor = textColor }
            if let highlightStyle { textObject.highlightStyle = highlightStyle }
            if let fontSizePreset { textObject.fontSizePreset = fontSizePreset }
            if let textAlignment { textObject.textAlignment = textAlignment }
            textObject.updatedAt = copy.metadata.updatedAt
            copy.textObject = textObject
        }

        if var quoteObject = copy.quoteObject {
            if let textStyle { quoteObject.textStyle = textStyle }
            if let textColor { quoteObject.textColor = textColor }
            if let highlightStyle { quoteObject.highlightStyle = highlightStyle }
            if let fontSizePreset { quoteObject.fontSizePreset = fontSizePreset }
            copy.quoteObject = quoteObject
        }

        return copy
    }

    func withMetadata(_ transform: (inout CanvasElementMetadata) -> Void) -> CanvasElement {
        var copy = self
        transform(&copy.metadata)
        copy.metadata.updatedAt = Date()
        if var textObject = copy.textObject {
            textObject.pageID = copy.metadata.pageID
            textObject.layerID = copy.metadata.layerID
            textObject.isLocked = copy.metadata.isLocked
            textObject.isHidden = !copy.metadata.isVisible
            textObject.zIndex = copy.metadata.zIndex
            textObject.updatedAt = copy.metadata.updatedAt
            copy.textObject = textObject
        }
        return copy
    }
}

struct CanvasLayer: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var kind: CanvasLayerKind
    var isVisible: Bool
    var isLocked: Bool
    var zIndex: Int
    var elements: [CanvasElement]

    init(
        id: UUID = UUID(),
        name: String,
        kind: CanvasLayerKind,
        isVisible: Bool = true,
        isLocked: Bool = false,
        zIndex: Int = 0,
        elements: [CanvasElement] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.zIndex = zIndex
        self.elements = elements
    }
}

struct NotePage: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var index: Int
    var size: CGSize
    var paper: NotePaperConfiguration
    var layers: [CanvasLayer]

    init(
        id: UUID = UUID(),
        index: Int,
        size: CGSize = NotePaperConfiguration.notebookDefault.size,
        paper: NotePaperConfiguration = .notebookDefault,
        layers: [CanvasLayer] = []
    ) {
        self.id = id
        self.index = index
        self.size = size
        self.paper = paper
        self.layers = layers
    }
}

struct NoteDocument: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var noteID: UUID
    var title: String
    var paper: NotePaperConfiguration
    var viewport: CanvasViewportState
    var pages: [NotePage]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        noteID: UUID,
        title: String,
        paper: NotePaperConfiguration = .notebookDefault,
        viewport: CanvasViewportState = CanvasViewportState(),
        pages: [NotePage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.noteID = noteID
        self.title = title
        self.paper = paper
        self.viewport = viewport
        self.pages = pages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var primaryPage: NotePage? {
        pages.sorted { $0.index < $1.index }.first
    }

    func firstLayer(kind: CanvasLayerKind) -> CanvasLayer? {
        primaryPage?.layers.first(where: { $0.kind == kind })
    }

    static func derived(
        noteID: UUID,
        title: String,
        sourceAnchor: SourceAnchor,
        blocks: [NoteBlock],
        textObjects: [CanvasTextObject],
        objectElements: [CanvasElement]? = nil,
        baseDocument: NoteDocument? = nil,
        createdAt: Date,
        updatedAt: Date,
        viewport: CanvasViewportState? = nil
    ) -> NoteDocument {
        let paper = baseDocument?.paper ?? .notebookDefault
        let page = makePrimaryPage(
            noteID: noteID,
            sourceAnchor: sourceAnchor,
            blocks: blocks,
            textObjects: textObjects,
            objectElements: objectElements,
            basePage: baseDocument?.primaryPage,
            paper: paper
        )

        return NoteDocument(
            id: baseDocument?.id ?? UUID(),
            noteID: noteID,
            title: title,
            paper: paper,
            viewport: viewport ?? baseDocument?.viewport ?? CanvasViewportState(),
            pages: [page],
            createdAt: baseDocument?.createdAt ?? createdAt,
            updatedAt: updatedAt
        )
    }

    private static func makePrimaryPage(
        noteID: UUID,
        sourceAnchor: SourceAnchor,
        blocks: [NoteBlock],
        textObjects: [CanvasTextObject],
        objectElements: [CanvasElement]?,
        basePage: NotePage?,
        paper: NotePaperConfiguration
    ) -> NotePage {
        let pageID = basePage?.id ?? UUID()
        let paperLayer = CanvasLayer(
            id: basePage?.layers.first(where: { $0.kind == .paper })?.id ?? UUID(),
            name: "Paper",
            kind: .paper,
            zIndex: 0
        )
        let backgroundLayer = CanvasLayer(
            id: basePage?.layers.first(where: { $0.kind == .backgroundReference })?.id ?? UUID(),
            name: "Reference",
            kind: .backgroundReference,
            zIndex: 10,
            elements: referenceElements(
                sourceAnchor: sourceAnchor,
                pageID: pageID,
                layerID: basePage?.layers.first(where: { $0.kind == .backgroundReference })?.id
            )
        )
        let inkLayerID = basePage?.layers.first(where: { $0.kind == .ink })?.id ?? UUID()
        let objectLayerID = basePage?.layers.first(where: { $0.kind == .object })?.id ?? UUID()
        let overlayLayer = CanvasLayer(
            id: basePage?.layers.first(where: { $0.kind == .overlay })?.id ?? UUID(),
            name: "Overlay",
            kind: .overlay,
            zIndex: 40
        )

        let inkLayer = CanvasLayer(
            id: inkLayerID,
            name: "Ink",
            kind: .ink,
            zIndex: 20,
            elements: inkElements(from: blocks, pageID: pageID, layerID: inkLayerID)
        )
        let objectLayer = CanvasLayer(
            id: objectLayerID,
            name: "Objects",
            kind: .object,
            zIndex: 30,
            elements: Self.objectElements(
                from: blocks,
                textObjects: textObjects,
                explicitObjectElements: objectElements,
                existingElements: basePage?.layers.first(where: { $0.kind == .object })?.elements ?? [],
                sourceAnchor: sourceAnchor,
                pageID: pageID,
                layerID: objectLayerID
            )
        )

        return NotePage(
            id: pageID,
            index: 0,
            size: paper.size,
            paper: paper,
            layers: [paperLayer, backgroundLayer, inkLayer, objectLayer, overlayLayer]
        )
    }

    private static func referenceElements(
        sourceAnchor: SourceAnchor,
        pageID: UUID,
        layerID: UUID?
    ) -> [CanvasElement] {
        let quote = sourceAnchor.quotedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quote.isEmpty else { return [] }

        let element = CanvasElement(
            id: UUID(),
            kind: .quoteObject,
            frame: CGRect(x: 72, y: 84, width: 720, height: 88),
            metadata: CanvasElementMetadata(
                sourceAnchorID: sourceAnchor.id,
                pageID: pageID,
                layerID: layerID,
                isVisible: false,
                zIndex: 0,
                layoutRole: .backgroundReference
            ),
            quoteObject: CanvasQuoteObject(
                text: quote,
                sourceAnchorID: sourceAnchor.id,
                citation: sourceAnchor.anchorLabel.nonEmpty
            )
        )
        return [element]
    }

    private static func inkElements(
        from blocks: [NoteBlock],
        pageID: UUID,
        layerID: UUID
    ) -> [CanvasElement] {
        blocks.compactMap { block in
            guard block.kind == .ink, let inkData = block.inkData, !inkData.isEmpty else { return nil }
            let frame = block.inkGeometry?.normalizedBounds.isNull == false
                ? (block.inkGeometry?.normalizedBounds ?? CGRect(x: 0, y: 0, width: 960, height: 1_360))
                : CGRect(x: 0, y: 0, width: 960, height: 1_360)

            return CanvasElement(
                id: block.id,
                kind: .inkStroke,
                frame: frame,
                metadata: CanvasElementMetadata(
                    sourceAnchorID: block.linkedSourceAnchorID,
                    linkedKnowledgePointIDs: block.linkedKnowledgePointIDs,
                    pageID: pageID,
                    layerID: layerID,
                    zIndex: 0,
                    layoutRole: .floating,
                    createdAt: block.createdAt,
                    updatedAt: block.updatedAt
                ),
                inkStroke: InkStrokeObject(
                    drawingData: inkData,
                    previewImageData: block.inkPreviewImageData,
                    recognizedText: block.recognizedText,
                    confidence: block.recognitionConfidence,
                    geometry: block.inkGeometry
                )
            )
        }
    }

    private static func objectElements(
        from blocks: [NoteBlock],
        textObjects: [CanvasTextObject],
        explicitObjectElements: [CanvasElement]?,
        existingElements: [CanvasElement],
        sourceAnchor: SourceAnchor,
        pageID: UUID,
        layerID: UUID
    ) -> [CanvasElement] {
        if let explicitObjectElements {
            return explicitObjectElements
                .map { element in
                    element.withMetadata { metadata in
                        metadata.pageID = pageID
                        metadata.layerID = layerID
                    }
                }
                .sorted { $0.resolvedZIndex < $1.resolvedZIndex }
        }

        var elements: [CanvasElement] = []
        var flowIndex = 0
        let flowOriginY: CGFloat = 132
        let flowSpacing: CGFloat = 112

        for block in blocks {
            let trimmedText = block.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmedText.isEmpty else { continue }

            switch block.kind {
            case .quote:
                if trimmedText == sourceAnchor.quotedText.trimmingCharacters(in: .whitespacesAndNewlines) {
                    continue
                }

                let y = flowOriginY + CGFloat(flowIndex) * flowSpacing
                flowIndex += 1
                elements.append(
                    CanvasElement(
                        id: block.id,
                        kind: .quoteObject,
                        frame: CGRect(x: 72, y: y, width: 720, height: 84),
                        metadata: CanvasElementMetadata(
                            sourceAnchorID: block.linkedSourceAnchorID,
                            linkedKnowledgePointIDs: block.linkedKnowledgePointIDs,
                            pageID: pageID,
                            layerID: layerID,
                            zIndex: flowIndex,
                            layoutRole: .flow,
                            createdAt: block.createdAt,
                            updatedAt: block.updatedAt
                        ),
                        quoteObject: CanvasQuoteObject(
                            text: trimmedText,
                            sourceAnchorID: block.linkedSourceAnchorID,
                            citation: sourceAnchor.anchorLabel.nonEmpty,
                            textStyle: block.textStyle,
                            textColor: block.textColor,
                            highlightStyle: block.highlightStyle,
                            fontSizePreset: block.fontSizePreset
                        )
                    )
                )
            case .text:
                let y = flowOriginY + CGFloat(flowIndex) * flowSpacing
                flowIndex += 1
                let payload = CanvasTextObject(
                    id: block.id,
                    text: trimmedText,
                    x: 72,
                    y: y,
                    width: 720,
                    height: 84,
                    zIndex: flowIndex,
                    textStyle: block.textStyle,
                    textColor: block.textColor,
                    highlightStyle: block.highlightStyle,
                    fontSizePreset: block.fontSizePreset,
                    pageID: pageID,
                    layerID: layerID,
                    createdAt: block.createdAt,
                    updatedAt: block.updatedAt
                )

                elements.append(
                    CanvasElement(
                        id: block.id,
                        kind: .textObject,
                        frame: payload.frame,
                        metadata: CanvasElementMetadata(
                            sourceAnchorID: block.linkedSourceAnchorID,
                            linkedKnowledgePointIDs: block.linkedKnowledgePointIDs,
                            pageID: pageID,
                            layerID: layerID,
                            zIndex: flowIndex,
                            layoutRole: .flow,
                            createdAt: block.createdAt,
                            updatedAt: block.updatedAt
                        ),
                        textObject: payload
                    )
                )
            case .ink:
                continue
            }
        }

        let floatingElements = textObjects
            .filter { !$0.isHidden }
            .map { object in
                CanvasElement(
                    id: object.id,
                    kind: .textObject,
                    frame: object.frame,
                    rotation: object.rotation,
                    metadata: CanvasElementMetadata(
                        pageID: object.pageID ?? pageID,
                        layerID: object.layerID ?? layerID,
                        isLocked: object.isLocked,
                        isVisible: !object.isHidden,
                        zIndex: object.zIndex,
                        layoutRole: .floating,
                        createdAt: object.createdAt,
                        updatedAt: object.updatedAt
                    ),
                    textObject: object
                )
            }

        let preservedElements = existingElements
            .filter { existing in
                switch existing.kind {
                case .imageObject, .knowledgeCardObject, .linkPreviewObject:
                    return true
                case .textObject, .quoteObject, .inkStroke, .inkSelectionObject:
                    return false
                }
            }
            .map { element in
                element.withMetadata { metadata in
                    metadata.pageID = pageID
                    metadata.layerID = layerID
                }
            }

        return (elements + floatingElements + preservedElements).sorted { $0.metadata.zIndex < $1.metadata.zIndex }
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
    var pageID: UUID?
    var layerID: UUID?
    var isLocked: Bool = false
    var isHidden: Bool = false
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
        pageID: UUID? = nil,
        layerID: UUID? = nil,
        isLocked: Bool = false,
        isHidden: Bool = false,
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
        self.pageID = pageID
        self.layerID = layerID
        self.isLocked = isLocked
        self.isHidden = isHidden
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

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case x
        case y
        case width
        case height
        case rotation
        case zIndex
        case textStyle
        case textColor
        case highlightStyle
        case fontSizePreset
        case textAlignment
        case pageID
        case layerID
        case isLocked
        case isHidden
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        x = try container.decodeIfPresent(CGFloat.self, forKey: .x) ?? 0
        y = try container.decodeIfPresent(CGFloat.self, forKey: .y) ?? 0
        width = try container.decodeIfPresent(CGFloat.self, forKey: .width) ?? 260
        height = try container.decodeIfPresent(CGFloat.self, forKey: .height) ?? 44
        rotation = try container.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
        zIndex = try container.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0
        textStyle = try container.decodeIfPresent(BlockTextStyle.self, forKey: .textStyle)
        textColor = try container.decodeIfPresent(BlockTextColor.self, forKey: .textColor)
        highlightStyle = try container.decodeIfPresent(BlockHighlight.self, forKey: .highlightStyle)
        fontSizePreset = try container.decodeIfPresent(BlockFontSize.self, forKey: .fontSizePreset)
        textAlignment = try container.decodeIfPresent(CanvasTextAlignment.self, forKey: .textAlignment) ?? .leading
        pageID = try container.decodeIfPresent(UUID.self, forKey: .pageID)
        layerID = try container.decodeIfPresent(UUID.self, forKey: .layerID)
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(zIndex, forKey: .zIndex)
        try container.encodeIfPresent(textStyle, forKey: .textStyle)
        try container.encodeIfPresent(textColor, forKey: .textColor)
        try container.encodeIfPresent(highlightStyle, forKey: .highlightStyle)
        try container.encodeIfPresent(fontSizePreset, forKey: .fontSizePreset)
        try container.encode(textAlignment, forKey: .textAlignment)
        try container.encodeIfPresent(pageID, forKey: .pageID)
        try container.encodeIfPresent(layerID, forKey: .layerID)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encode(isHidden, forKey: .isHidden)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
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
    var document: NoteDocument?
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
        document: NoteDocument? = nil,
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
        self.document = document
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

    var resolvedDocument: NoteDocument {
        NoteDocument.derived(
            noteID: id,
            title: title,
            sourceAnchor: sourceAnchor,
            blocks: blocks,
            textObjects: textObjects,
            baseDocument: document,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
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
        let hasDocumentElements = document?.pages.contains { page in
            page.layers.contains { layer in
                layer.elements.contains { $0.metadata.isVisible }
            }
        } ?? false

        return hasTitle || hasText || hasInk || hasQuote || hasTags || hasKnowledge || hasTextObjects || hasDocumentElements
    }

    // MARK: - Backward-compatible Codable

    private enum CodingKeys: String, CodingKey {
        case id, title, sourceAnchor, blocks, textObjects, document, tags, knowledgePoints, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        sourceAnchor = try c.decode(SourceAnchor.self, forKey: .sourceAnchor)
        blocks = try c.decode([NoteBlock].self, forKey: .blocks)
        textObjects = try c.decodeIfPresent([CanvasTextObject].self, forKey: .textObjects) ?? []
        document = try c.decodeIfPresent(NoteDocument.self, forKey: .document)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        knowledgePoints = try c.decodeIfPresent([KnowledgePoint].self, forKey: .knowledgePoints) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

private extension String {
    var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
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
