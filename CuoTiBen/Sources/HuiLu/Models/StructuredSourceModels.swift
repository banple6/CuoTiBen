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

    func sentences(in segment: Segment) -> [Sentence] {
        let sentenceIDSet = Set(segment.sentenceIDs)
        return sentences.filter { sentenceIDSet.contains($0.id) }
    }

    func sentence(id: String?) -> Sentence? {
        guard let id else { return nil }
        return sentences.first { $0.id == id }
    }

    func segment(id: String?) -> Segment? {
        guard let id else { return nil }
        return segments.first { $0.id == id }
    }

    func outlineNode(id: String?) -> OutlineNode? {
        guard let id else { return nil }
        return flattenedOutlineNodes().first { $0.id == id }
    }

    func bestOutlineNode(forSentenceID id: String?) -> OutlineNode? {
        guard let id else { return nil }

        return flattenedOutlineNodes()
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

        return flattenedOutlineNodes()
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

        let nodes = flattenedOutlineNodes()
        let parentMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.parentID) })
        var results: [String] = []
        var current = nodeID

        while let parentID = parentMap[current], let unwrappedParentID = parentID {
            results.append(unwrappedParentID)
            current = unwrappedParentID
        }

        return results
    }

    func outlineNodes(forSegmentIDs ids: Set<String>) -> [OutlineNode] {
        guard !ids.isEmpty else { return [] }
        return flattenedOutlineNodes().filter { node in
            !Set(node.sourceSegmentIDs).isDisjoint(with: ids) ||
            (node.anchor.segmentID.map { ids.contains($0) } ?? false)
        }
    }

    func flattenedOutlineNodes() -> [OutlineNode] {
        flatten(nodes: outline)
    }

    private func flatten(nodes: [OutlineNode]) -> [OutlineNode] {
        nodes.flatMap { [$0] + flatten(nodes: $0.children) }
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
