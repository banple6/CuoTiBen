import Foundation
import NaturalLanguage
import PDFKit
import UIKit
import Vision

public struct SourceTextAnchorDraft: Equatable {
    public let anchorID: String
    public let label: String
    public let page: Int?
    public let text: String

    public init(anchorID: String, label: String, page: Int?, text: String) {
        self.anchorID = anchorID
        self.label = label
        self.page = page
        self.text = text
    }
}

public struct SourceTextDraft: Equatable {
    public let rawText: String
    public let anchors: [SourceTextAnchorDraft]
    public let isLikelyEnglish: Bool
    let sentenceDrafts: [SourceSentenceDraft]

    public init(rawText: String, anchors: [SourceTextAnchorDraft], isLikelyEnglish: Bool) {
        self.rawText = rawText
        self.anchors = anchors
        self.isLikelyEnglish = isLikelyEnglish
        self.sentenceDrafts = []
    }

    init(
        rawText: String,
        anchors: [SourceTextAnchorDraft],
        isLikelyEnglish: Bool,
        sentenceDrafts: [SourceSentenceDraft]
    ) {
        self.rawText = rawText
        self.anchors = anchors
        self.isLikelyEnglish = isLikelyEnglish
        self.sentenceDrafts = sentenceDrafts
    }
}

struct SourceSentenceDraft: Equatable {
    let id: String
    let text: String
    let anchorLabel: String
    let geometry: SentenceGeometry

    var page: Int {
        geometry.page
    }
}

public struct DocumentParseResult {
    public var bodyText: String
    public var sectionTitles: [String]
    public var topicTags: [String]
    public var candidateKnowledgePoints: [String]
    public var chunks: [KnowledgeChunk]

    public init(
        bodyText: String,
        sectionTitles: [String],
        topicTags: [String],
        candidateKnowledgePoints: [String],
        chunks: [KnowledgeChunk]
    ) {
        self.bodyText = bodyText
        self.sectionTitles = sectionTitles
        self.topicTags = topicTags
        self.candidateKnowledgePoints = candidateKnowledgePoints
        self.chunks = chunks
    }
}

// MARK: - Chunking Service Protocol
public protocol ChunkingServiceProtocol {
    func parse(document: SourceDocument) async throws -> DocumentParseResult
    func extractSourceDraft(document: SourceDocument) async throws -> SourceTextDraft
    func autoChunk(document: SourceDocument) async throws -> [KnowledgeChunk]
    func mergeChunks(_ chunkIDs: [UUID]) async throws -> KnowledgeChunk
    func splitChunk(chunkID: UUID, atPosition: Int) async throws -> [KnowledgeChunk]
    func updateChunkTitle(chunkID: UUID, newTitle: String) async throws
}

// MARK: - Chunking Service Implementation
/// Extracts body text, sections, source locations, topic tags and candidate knowledge points.
public final class ChunkingService: ChunkingServiceProtocol {
    fileprivate enum ParsedLanguage {
        case chinese
        case english
        case mixed
    }

    private struct ParsedSegment {
        let locator: String
        let position: Int?
        let text: String
        let sentenceDrafts: [SourceSentenceDraft]
    }

    private struct OCRPageDraft {
        let text: String
        let sentenceDrafts: [SourceSentenceDraft]
    }

    private struct OCRLineObservation {
        let text: String
        let boundingBox: CGRect
        let wordRegions: [SentenceWordRegion]
    }

    fileprivate struct LocalizedChunkPayload {
        let title: String
        let content: String
        let tags: [String]
        let candidateKnowledgePoints: [String]
    }

    public init() {}

    public func parse(document: SourceDocument) async throws -> DocumentParseResult {
        try await runOnBackground {
            try self.parseSynchronously(document: document)
        }
    }

    public func extractSourceDraft(document: SourceDocument) async throws -> SourceTextDraft {
        try await runOnBackground {
            let segments = try self.extractSegments(from: document)
            let anchors = segments.enumerated().map { index, segment in
                SourceTextAnchorDraft(
                    anchorID: "anchor_\(index + 1)",
                    label: segment.locator,
                    page: segment.position,
                    text: segment.text
                )
            }
            let rawText = anchors.map(\.text).joined(separator: "\n\n").normalizedWhitespace()
            let language = self.dominantLanguage(for: rawText)

            TextPipelineDiagnostics.log(
                "Draft构建",
                "rawText=\(rawText.count)字符 anchors=\(anchors.count) lang=\(language) sentenceDrafts=\(segments.flatMap(\.sentenceDrafts).count)"
            )

            // 出口质量校验
            let report = TextPipelineValidator.assessQuality(of: rawText)
            if report.isReversed {
                TextPipelineDiagnostics.log(
                    "Draft构建",
                    "rawText 检测到反转，自动修复中",
                    severity: .repaired
                )
                let repairedRawText = TextPipelineValidator.repairReversedText(rawText)
                let repairedAnchors = anchors.map { anchor in
                    let (repairedText, _) = TextPipelineValidator.validateAndRepairIfReversed(anchor.text)
                    return SourceTextAnchorDraft(
                        anchorID: anchor.anchorID,
                        label: anchor.label,
                        page: anchor.page,
                        text: repairedText
                    )
                }
                return SourceTextDraft(
                    rawText: repairedRawText,
                    anchors: repairedAnchors,
                    isLikelyEnglish: language == .english || language == .mixed,
                    sentenceDrafts: segments.flatMap(\.sentenceDrafts)
                )
            }

            return SourceTextDraft(
                rawText: rawText,
                anchors: anchors,
                isLikelyEnglish: language == .english || language == .mixed,
                sentenceDrafts: segments.flatMap(\.sentenceDrafts)
            )
        }
    }

    private func parseSynchronously(document: SourceDocument) throws -> DocumentParseResult {
        let segments = try extractSegments(from: document)
        let chunks = buildChunks(from: segments, document: document)
        let bodyText = chunks.map(\.content).joined(separator: "\n\n").normalizedWhitespace()

        guard !bodyText.isEmpty else {
            throw ChunkingError.extractionFailed("未提取到有效正文")
        }

        let sectionTitles = deduplicated(chunks.map(\.title)).prefix(6)
        let topicTags = deduplicated(chunks.flatMap(\.tags)).prefix(8)
        let candidateKnowledgePoints = deduplicated(chunks.flatMap(\.candidateKnowledgePoints)).prefix(12)

        return DocumentParseResult(
            bodyText: bodyText,
            sectionTitles: Array(sectionTitles),
            topicTags: Array(topicTags),
            candidateKnowledgePoints: Array(candidateKnowledgePoints),
            chunks: chunks
        )
    }

    public func autoChunk(document: SourceDocument) async throws -> [KnowledgeChunk] {
        try await parse(document: document).chunks
    }

    public func mergeChunks(_ chunkIDs: [UUID]) async throws -> KnowledgeChunk {
        throw ChunkingError.notImplemented("第一版暂不支持知识块合并")
    }

    public func splitChunk(chunkID: UUID, atPosition: Int) async throws -> [KnowledgeChunk] {
        throw ChunkingError.notImplemented("第一版暂不支持知识块拆分")
    }

    public func updateChunkTitle(chunkID: UUID, newTitle: String) async throws {
        throw ChunkingError.notImplemented("第一版暂不支持手动改标题")
    }

    private func extractSegments(from document: SourceDocument) throws -> [ParsedSegment] {
        guard let filePath = document.filePath else {
            throw ChunkingError.noFilePath
        }

        switch document.documentType {
        case .pdf:
            return try extractSegmentsFromPDF(filePath)
        case .image, .scan:
            return try extractSegmentsFromImage(filePath)
        case .text:
            return try extractSegmentsFromText(filePath)
        }
    }

    private func extractSegmentsFromPDF(_ filePath: String) throws -> [ParsedSegment] {
        let url = URL(fileURLWithPath: filePath)
        guard let document = PDFDocument(url: url) else {
            throw ChunkingError.extractionFailed("PDF 无法读取")
        }

        TextPipelineDiagnostics.log("PDF提取", "开始处理PDF: \(document.pageCount)页 path=\(url.lastPathComponent)")

        var segments: [ParsedSegment] = []
        var sourceTextPages = 0
        var ocrPages = 0

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let text = page.string?.normalizedWhitespace() ?? ""
            if !text.isEmpty {
                sourceTextPages += 1
                segments.append(
                    ParsedSegment(
                        locator: "第\(index + 1)页",
                        position: index + 1,
                        text: text,
                        sentenceDrafts: []
                    )
                )
                continue
            }

            ocrPages += 1
            let ocrDraft = try recognizePDFPageText(page, pageNumber: index + 1)
            let recognizedText = ocrDraft.text.normalizedWhitespace()
            guard !recognizedText.isEmpty else { continue }

            segments.append(
                ParsedSegment(
                    locator: "第\(index + 1)页",
                    position: index + 1,
                    text: recognizedText,
                    sentenceDrafts: ocrDraft.sentenceDrafts
                )
            )
        }

        TextPipelineDiagnostics.log(
            "PDF提取",
            "提取完成: \(segments.count)段 源文本页=\(sourceTextPages) OCR页=\(ocrPages)"
        )

        if segments.isEmpty {
            TextPipelineDiagnostics.log("PDF提取", "PDF正文为空", severity: .error)
            throw ChunkingError.extractionFailed("PDF 正文为空")
        }

        return segments
    }

    private func extractSegmentsFromImage(_ filePath: String) throws -> [ParsedSegment] {
        let url = URL(fileURLWithPath: filePath)
        let ocrDraft = try recognizeImageText(at: url, pageNumber: 1, locator: "图片 1")
        let recognizedText = ocrDraft.text.normalizedWhitespace()

        guard !recognizedText.isEmpty else {
            throw ChunkingError.extractionFailed("图片 OCR 未识别到正文")
        }

        return [
            ParsedSegment(
                locator: "图片 1",
                position: 1,
                text: recognizedText,
                sentenceDrafts: ocrDraft.sentenceDrafts
            )
        ]
    }

    private func extractSegmentsFromText(_ filePath: String) throws -> [ParsedSegment] {
        let url = URL(fileURLWithPath: filePath)
        let content = try readTextFile(at: url).normalizedWhitespace()

        guard !content.isEmpty else {
            throw ChunkingError.extractionFailed("文本内容为空")
        }

        let sections = content
            .components(separatedBy: "\n\n")
            .map { $0.normalizedWhitespace() }
            .filter { !$0.isEmpty }

        if sections.isEmpty {
            return [
                ParsedSegment(locator: "文本 1", position: 1, text: content, sentenceDrafts: [])
            ]
        }

        return sections.enumerated().map { index, section in
            ParsedSegment(locator: "文本段 \(index + 1)", position: index + 1, text: section, sentenceDrafts: [])
        }
    }

    private func readTextFile(at url: URL) throws -> String {
        for encoding in [String.Encoding.utf8, .unicode, .utf16, .utf32] {
            if let text = try? String(contentsOf: url, encoding: encoding) {
                return text
            }
        }

        throw ChunkingError.extractionFailed("文本编码无法识别")
    }

    private func makeOCRRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        return request
    }

    private func recognizeImageText(at url: URL, pageNumber: Int, locator: String) throws -> OCRPageDraft {
        let request = makeOCRRequest()
        do {
            let handler = VNImageRequestHandler(url: url)
            try handler.perform([request])
        } catch {
            throw ChunkingError.extractionFailed(error.localizedDescription)
        }

        return makeOCRPageDraft(
            from: request.results ?? [],
            pageNumber: pageNumber,
            locator: locator
        )
    }

    private func recognizePDFPageText(_ page: PDFPage, pageNumber: Int) throws -> OCRPageDraft {
        let bounds = page.bounds(for: .mediaBox)
        let targetSize = CGSize(
            width: max(bounds.width * 2, 1200),
            height: max(bounds.height * 2, 1600)
        )
        let image = page.thumbnail(of: targetSize, for: .mediaBox)
        guard let cgImage = image.cgImage else {
            throw ChunkingError.extractionFailed("PDF 页面无法转换为 OCR 图像")
        }

        // 根据 PDF 页面旋转角度推断图像方向
        let orientation = Self.visionOrientation(fromPDFPageRotation: page.rotation)

        let request = makeOCRRequest()
        do {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try handler.perform([request])
        } catch {
            throw ChunkingError.extractionFailed(error.localizedDescription)
        }

        let draft = makeOCRPageDraft(
            from: request.results ?? [],
            pageNumber: pageNumber,
            locator: "第\(pageNumber)页"
        )

        TextPipelineDiagnostics.log(
            "OCR提取",
            "第\(pageNumber)页 OCR完成: \(request.results?.count ?? 0)行 \(draft.text.count)字符 rotation=\(page.rotation)° orientation=\(orientation.rawValue)"
        )

        // OCR 输出质量检查
        if !draft.text.isEmpty {
            let (repairedText, wasRepaired) = TextPipelineValidator.validateAndRepairIfReversed(draft.text)
            if wasRepaired {
                TextPipelineDiagnostics.log(
                    "OCR提取",
                    "第\(pageNumber)页 OCR文本疑似反转，已修复",
                    severity: .repaired
                )
                return OCRPageDraft(
                    text: repairedText,
                    sentenceDrafts: draft.sentenceDrafts.map { sentenceDraft in
                        let (repairedSentence, _) = TextPipelineValidator.validateAndRepairIfReversed(sentenceDraft.text)
                        return SourceSentenceDraft(
                            id: sentenceDraft.id,
                            text: repairedSentence,
                            anchorLabel: sentenceDraft.anchorLabel,
                            geometry: sentenceDraft.geometry
                        )
                    }
                )
            }
        }

        return draft
    }

    /// 将 PDF 页面旋转角度转换为 Vision 识别方向
    nonisolated private static func visionOrientation(fromPDFPageRotation rotation: Int) -> CGImagePropertyOrientation {
        switch rotation {
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return .up
        }
    }

    private func makeOCRPageDraft(
        from observations: [VNRecognizedTextObservation],
        pageNumber: Int,
        locator: String
    ) -> OCRPageDraft {
        let lines = observations
            .compactMap { observation -> OCRLineObservation? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let text = candidate.string.normalizedInlineWhitespace()
                guard !text.isEmpty else { return nil }
                return OCRLineObservation(
                    text: text,
                    boundingBox: observation.boundingBox.standardized,
                    wordRegions: extractWordRegions(from: candidate)
                )
            }
            .sorted(by: Self.compareOCRLineOrder(_:_:))

        guard !lines.isEmpty else {
            return OCRPageDraft(text: "", sentenceDrafts: [])
        }

        let pageText = lines.map(\.text).joined(separator: "\n")
        var sentenceDrafts: [SourceSentenceDraft] = []
        var currentTexts: [String] = []
        var currentRects: [CGRect] = []
        var currentWordRegions: [SentenceWordRegion] = []

        func flushCurrentSentence() {
            let sentenceText = currentTexts.joined(separator: " ").normalizedInlineWhitespace()
            guard !sentenceText.isEmpty, !currentRects.isEmpty else {
                currentTexts.removeAll()
                currentRects.removeAll()
                currentWordRegions.removeAll()
                return
            }

            sentenceDrafts.append(
                SourceSentenceDraft(
                    id: "\(locator)-ocr-\(sentenceDrafts.count + 1)",
                    text: sentenceText,
                    anchorLabel: "\(locator) 第\(sentenceDrafts.count + 1)句",
                    geometry: SentenceGeometry(
                        page: pageNumber,
                        regions: currentRects.map { SentenceRegion(rect: $0.standardized) },
                        wordRegions: currentWordRegions,
                        source: .ocr
                    )
                )
            )
            currentTexts.removeAll()
            currentRects.removeAll()
            currentWordRegions.removeAll()
        }

        for line in lines {
            currentTexts.append(line.text)
            currentRects.append(line.boundingBox)
            currentWordRegions.append(contentsOf: line.wordRegions)

            if line.text.looksLikeSentenceTerminal {
                flushCurrentSentence()
            }
        }

        flushCurrentSentence()

        return OCRPageDraft(
            text: pageText,
            sentenceDrafts: sentenceDrafts
        )
    }

    private func buildChunks(from segments: [ParsedSegment], document: SourceDocument) -> [KnowledgeChunk] {
        var chunks: [KnowledgeChunk] = []
        let localizer = ChineseResultLocalizer(documentTitle: document.title)

        for segment in segments {
            let paragraphs = segment.text
                .components(separatedBy: "\n\n")
                .map { $0.normalizedWhitespace() }
                .filter { !$0.isEmpty }

            let units = paragraphs.isEmpty ? [segment.text] : paragraphs

            for (paragraphIndex, paragraph) in units.enumerated() {
                let language = dominantLanguage(for: paragraph)
                let sectionTitle = detectSectionTitle(in: paragraph, fallback: "\(document.title) \(segment.locator)")
                let candidateKnowledgePoints = extractCandidateKnowledgePoints(
                    from: paragraph,
                    sectionTitle: sectionTitle,
                    documentTitle: document.title
                )
                let tags = extractTopicTags(
                    from: paragraph,
                    documentTitle: document.title,
                    sectionTitle: sectionTitle,
                    candidateKnowledgePoints: candidateKnowledgePoints
                )
                let localized = localizer.localizedChunkPayload(
                    language: language,
                    originalText: paragraph,
                    sectionTitle: sectionTitle,
                    candidateKnowledgePoints: candidateKnowledgePoints,
                    tags: tags
                )

                let position = segment.position ?? (paragraphIndex + 1)
                let chunk = KnowledgeChunk(
                    title: localized.title,
                    content: localized.content,
                    sourceDocumentID: document.id,
                    startPosition: position,
                    endPosition: position,
                    sourceLocator: segment.locator,
                    tags: localized.tags,
                    candidateKnowledgePoints: localized.candidateKnowledgePoints
                )
                chunks.append(chunk)
            }
        }

        return chunks
    }

    private func detectSectionTitle(in text: String, fallback: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.normalizedWhitespace() }
            .filter { !$0.isEmpty }

        let titleMaxLength = dominantLanguage(for: text) == .english ? 40 : 22
        if let first = lines.first, first.count <= titleMaxLength, first.containsMeaningfulTitleWord {
            return first
        }

        let knowledgePoints = extractCandidateKnowledgePoints(
            from: text,
            sectionTitle: "",
            documentTitle: fallback
        )
        if let firstPoint = knowledgePoints.first {
            return firstPoint
        }

        return fallback
    }

    private func extractCandidateKnowledgePoints(from text: String, sectionTitle: String, documentTitle: String) -> [String] {
        if dominantLanguage(for: "\(sectionTitle)\n\(text)") == .english {
            return extractEnglishKnowledgePoints(
                from: text,
                sectionTitle: sectionTitle,
                documentTitle: documentTitle
            )
        }

        var points: [String] = []
        if !sectionTitle.isEmpty {
            points.append(sectionTitle)
        }

        let sentences = text.splitIntoSentences()
        let markers = ["是指", "指的是", "包括", "分为", "属于", "用于", "核心是", "本质是", "定义为", "可以看作"]

        for sentence in sentences {
            let cleanedSentence = sentence.cleanedKnowledgeText()
            guard !cleanedSentence.isEmpty else { continue }

            if let marker = markers.first(where: { cleanedSentence.contains($0) }),
               let range = cleanedSentence.range(of: marker) {
                let prefix = String(cleanedSentence[..<range.lowerBound]).cleanedKnowledgeText()
                if prefix.count >= 2 && prefix.count <= 18 {
                    points.append(prefix)
                }
            } else if cleanedSentence.count <= 18 {
                points.append(cleanedSentence)
            }

            if points.count >= 5 {
                break
            }
        }

        return Array(deduplicated(points).prefix(5))
    }

    private func extractEnglishKnowledgePoints(from text: String, sectionTitle: String, documentTitle: String) -> [String] {
        var points: [String] = []

        if !sectionTitle.isEmpty, !sectionTitle.looksLikeGenericEnglishHeading {
            points.append(sectionTitle)
        }

        for sentence in text.splitIntoSentences().prefix(3) {
            points.append(contentsOf: extractEnglishKeywordPhrases(from: sentence))
            if points.count >= 6 {
                break
            }
        }

        if points.count < 3 {
            points.append(contentsOf: extractEnglishKeywordPhrases(from: documentTitle))
        }

        return Array(deduplicated(points).prefix(5))
    }

    private func extractTopicTags(
        from text: String,
        documentTitle: String,
        sectionTitle: String,
        candidateKnowledgePoints: [String]
    ) -> [String] {
        let titleTokens = tokenize(documentTitle) + tokenize(sectionTitle)
        let pointTokens = candidateKnowledgePoints.flatMap(tokenize)
        let englishTerms = dominantLanguage(for: text) == .english
            ? extractEnglishKeywordPhrases(from: text)
            : extractEnglishTerms(from: text)

        let tags = deduplicated(titleTokens + pointTokens + englishTerms)
            .filter { $0.count >= 2 }

        return Array(tags.prefix(6))
    }

    private func tokenize(_ text: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return text
            .components(separatedBy: separators)
            .map { $0.cleanedKnowledgeText() }
            .filter { !$0.isEmpty && $0.count <= 16 && !$0.looksLikeAuthorName }
    }

    private func extractEnglishTerms(from text: String) -> [String] {
        let tokens = text
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                $0.range(of: "^[A-Za-z0-9_+-]{2,}$", options: .regularExpression) != nil &&
                !$0.looksLikeAuthorName &&
                !Self.englishStopwords.contains($0.lowercased())
            }

        return Array(deduplicated(tokens).prefix(4))
    }

    private func extractEnglishKeywordPhrases(from text: String) -> [String] {
        let words = englishWords(in: text)
        guard !words.isEmpty else { return [] }

        var candidates: [String] = []

        for index in words.indices {
            let current = words[index]
            guard isPotentialConceptWord(current) else { continue }

            candidates.append(current)

            if words.indices.contains(index + 1) {
                let next = words[index + 1]
                if isPotentialConceptWord(next) {
                    candidates.append("\(current) \(next)")
                }
            }

            if words.indices.contains(index + 2) {
                let next = words[index + 1]
                let third = words[index + 2]
                if isPotentialConceptWord(next), isPotentialConceptWord(third) {
                    candidates.append("\(current) \(next) \(third)")
                }
            }
        }

        return Array(
            deduplicated(candidates)
                .filter { !$0.looksLikeAuthorName && !$0.looksLikeGenericEnglishHeading }
                .prefix(6)
        )
    }

    private func englishWords(in text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { $0.range(of: "^[A-Za-z][A-Za-z-]{1,}$", options: .regularExpression) != nil }
    }

    private func isPotentialConceptWord(_ word: String) -> Bool {
        let lowered = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        guard lowered.count >= 3 else { return false }
        guard !Self.englishStopwords.contains(lowered) else { return false }
        guard !lowered.looksLikeGenericEnglishHeading else { return false }
        return !word.looksLikeAuthorName
    }

    private func dominantLanguage(for text: String) -> ParsedLanguage {
        let sample = String(text.prefix(1500)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else { return .mixed }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)

        switch recognizer.dominantLanguage {
        case .simplifiedChinese, .traditionalChinese:
            return .chinese
        case .english:
            return .english
        default:
            break
        }

        let englishCharacterCount = sample.unicodeScalars.filter { CharacterSet.letters.contains($0) && $0.value < 128 }.count
        let chineseCharacterCount = sample.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count

        if englishCharacterCount > max(chineseCharacterCount * 2, 20) {
            return .english
        }

        if chineseCharacterCount > max(englishCharacterCount, 8) {
            return .chinese
        }

        return .mixed
    }

    private func runOnBackground<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func deduplicated(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for value in values {
            let cleaned = value.cleanedKnowledgeText()
            guard !cleaned.isEmpty, !seen.contains(cleaned) else { continue }
            seen.insert(cleaned)
            result.append(cleaned)
        }

        return result
    }

    fileprivate static let englishStopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "in", "into", "is",
        "it", "of", "on", "or", "that", "the", "their", "this", "to", "was", "were", "with",
        "without", "we", "our", "these", "those", "than", "then", "there", "which", "while",
        "during", "based", "using", "used", "use", "showed", "shows", "show", "have", "has",
        "had", "after", "before", "between", "among", "also", "can", "may", "might", "should",
        "would", "will", "not"
    ]

    nonisolated private static func compareOCRLineOrder(_ lhs: OCRLineObservation, _ rhs: OCRLineObservation) -> Bool {
        let verticalDistance = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
        if verticalDistance > 0.025 {
            return lhs.boundingBox.midY > rhs.boundingBox.midY
        }

        return lhs.boundingBox.minX < rhs.boundingBox.minX
    }

    private func extractWordRegions(from candidate: VNRecognizedText) -> [SentenceWordRegion] {
        let text = candidate.string as NSString
        let regex = try? NSRegularExpression(pattern: #"[A-Za-z0-9][A-Za-z0-9'\-]*"#)
        let matches = regex?.matches(
            in: candidate.string,
            range: NSRange(location: 0, length: text.length)
        ) ?? []

        return matches.compactMap { match in
            guard
                let stringRange = Range(match.range, in: candidate.string),
                let boxObservation = try? candidate.boundingBox(for: stringRange),
                !boxObservation.boundingBox.isEmpty
            else {
                return nil
            }

            let token = text.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return nil }

            return SentenceWordRegion(
                token: token,
                region: SentenceRegion(rect: boxObservation.boundingBox.standardized)
            )
        }
    }
}

// MARK: - Chunking Errors
public enum ChunkingError: LocalizedError {
    case noFilePath
    case unsupportedFormat(String)
    case extractionFailed(String)
    case notImplemented(String)

    public var errorDescription: String? {
        switch self {
        case .noFilePath:
            return "源文件路径不存在"
        case .unsupportedFormat(let format):
            return "不支持的文件格式：\(format)"
        case .extractionFailed(let reason):
            return "文本提取失败：\(reason)"
        case .notImplemented(let feature):
            return "功能尚未实现：\(feature)"
        }
    }
}

private extension String {
    func normalizedWhitespace() -> String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func splitIntoSentences() -> [String] {
        components(separatedBy: CharacterSet(charactersIn: "。！？；.!?;:\n"))
            .map { $0.cleanedKnowledgeText() }
            .filter { !$0.isEmpty }
    }

    func normalizedInlineWhitespace() -> String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cleanedKnowledgeText() -> String {
        trimmingCharacters(in: CharacterSet(charactersIn: " \n\t，。！？；：“”‘’()（）[]【】<>《》-•·"))
    }

    var containsMeaningfulTitleWord: Bool {
        count >= 2 && !allSatisfy(\.isNumber)
    }

    var looksLikeSentenceTerminal: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return false }
        return ".!?。！？".contains(last)
    }

    var looksLikeAuthorName: Bool {
        let tokens = components(separatedBy: CharacterSet(charactersIn: " -"))
            .filter { !$0.isEmpty }

        guard tokens.count >= 2 && tokens.count <= 4 else { return false }
        return tokens.allSatisfy {
            $0.range(of: "^[A-Z][a-z]{1,}$", options: .regularExpression) != nil
        }
    }

    var looksLikeGenericEnglishHeading: Bool {
        let lowered = lowercased().normalizedWhitespace()
        return Self.genericEnglishHeadings.contains(lowered)
    }

    private static let genericEnglishHeadings: Set<String> = [
        "abstract", "appendix", "article", "background", "conclusion", "conclusions",
        "discussion", "figure", "figures", "introduction", "keywords", "method", "methods",
        "original article", "references", "result", "results", "summary", "table", "tables"
    ]
}

private struct ChineseResultLocalizer {
    let documentTitle: String

    func localizedChunkPayload(
        language: ChunkingService.ParsedLanguage,
        originalText: String,
        sectionTitle: String,
        candidateKnowledgePoints: [String],
        tags: [String]
    ) -> ChunkingService.LocalizedChunkPayload {
        guard language == .english || language == .mixed else {
            return ChunkingService.LocalizedChunkPayload(
                title: cleanedOrFallback(sectionTitle, fallback: documentTitle),
                content: originalText.normalizedWhitespace(),
                tags: Array(deduplicated(tags).prefix(6)),
                candidateKnowledgePoints: Array(deduplicated(candidateKnowledgePoints).prefix(5))
            )
        }

        let localizedTitle = cleanedOrFallback(localizePhrase(sectionTitle), fallback: fallbackTitle())
        let localizedPoints = localizedKnowledgePoints(
            from: candidateKnowledgePoints,
            sourceText: originalText,
            localizedTitle: localizedTitle
        )
        let localizedTags = localizedTags(
            from: tags,
            localizedPoints: localizedPoints,
            localizedTitle: localizedTitle
        )
        let localizedContent = localizedSummary(
            for: originalText,
            localizedTitle: localizedTitle,
            localizedPoints: localizedPoints
        )

        return ChunkingService.LocalizedChunkPayload(
            title: localizedTitle,
            content: localizedContent,
            tags: localizedTags,
            candidateKnowledgePoints: localizedPoints
        )
    }

    private func localizedKnowledgePoints(
        from points: [String],
        sourceText: String,
        localizedTitle: String
    ) -> [String] {
        var localized = points
            .map(localizePhrase)
            .filter { !$0.isEmpty && !Self.genericChineseLabels.contains($0) }

        if localized.count < 3 {
            localized.append(contentsOf: localizedKeywords(from: sourceText))
        }

        if localized.isEmpty, !localizedTitle.isEmpty, !Self.genericChineseLabels.contains(localizedTitle) {
            localized.append(localizedTitle)
        }

        if localized.count < 3 {
            localized.append(contentsOf: tokenizeChineseTerms(from: documentTitle))
        }

        return Array(deduplicated(localized).prefix(5))
    }

    private func localizedTags(
        from tags: [String],
        localizedPoints: [String],
        localizedTitle: String
    ) -> [String] {
        var values = tags.map(localizePhrase)
        values.append(contentsOf: localizedPoints)
        values.append(localizedTitle)
        values.append(contentsOf: tokenizeChineseTerms(from: documentTitle))

        return Array(
            deduplicated(values)
                .filter { !$0.isEmpty }
                .prefix(6)
        )
    }

    private func localizedSummary(
        for originalText: String,
        localizedTitle: String,
        localizedPoints: [String]
    ) -> String {
        if let first = localizedPoints.first {
            let remaining = Array(localizedPoints.dropFirst().prefix(2))
            if remaining.isEmpty {
                return "该段主要介绍\(first)的核心内容。"
            }

            return "该段主要围绕\(first)、\(remaining.joined(separator: "、"))展开。"
        }

        if !localizedTitle.isEmpty {
            return "该段内容与\(localizedTitle)相关，已完成中文整理。"
        }

        if !documentTitle.isEmpty {
            return "该段来自《\(documentTitle)》的英文资料，已整理为中文结果。"
        }

        return "该段为英文资料内容，已完成中文整理。"
    }

    private func localizePhrase(_ value: String) -> String {
        let cleaned = value.normalizedWhitespace().cleanedKnowledgeText()
        guard !cleaned.isEmpty else { return "" }
        guard !cleaned.containsChinese else { return cleaned }
        guard !cleaned.looksLikeAuthorName else { return "" }

        let lowered = cleaned.lowercased()
        if let translated = Self.phraseDictionary[lowered] {
            return translated
        }

        if let tableMatch = lowered.firstMatch(of: #"table\s+(\d+)"#) {
            return "表\(tableMatch)"
        }

        if let figureMatch = lowered.firstMatch(of: #"figure\s+(\d+)"#) {
            return "图\(figureMatch)"
        }

        if let chapterMatch = lowered.firstMatch(of: #"chapter\s+(\d+)"#) {
            return "第\(chapterMatch)章"
        }

        if let pageMatch = lowered.firstMatch(of: #"page\s+(\d+)"#) {
            return "第\(pageMatch)页"
        }

        let tokens = cleaned
            .components(separatedBy: CharacterSet(charactersIn: " -_/"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var translatedTokens: [String] = []

        for token in tokens {
            let loweredToken = token.lowercased()
            let singular = Self.singularize(loweredToken)

            if let translated = Self.wordDictionary[loweredToken] ?? Self.wordDictionary[singular] {
                translatedTokens.append(translated)
            } else if token.range(of: "^[A-Z0-9]{2,6}$", options: .regularExpression) != nil {
                translatedTokens.append(token)
            }
        }

        if translatedTokens.isEmpty {
            return ""
        }

        return translatedTokens.joined()
    }

    private func localizedKeywords(from text: String) -> [String] {
        let words = text
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .filter { $0.range(of: "^[a-z][a-z-]{2,}$", options: .regularExpression) != nil }
            .filter { !Self.stopwords.contains($0) }

        var localized: [String] = []

        for index in words.indices {
            let current = Self.singularize(words[index])
            if let translated = Self.wordDictionary[current], !Self.genericChineseLabels.contains(translated) {
                localized.append(translated)
            }

            if words.indices.contains(index + 1) {
                let combined = "\(Self.singularize(words[index])) \(Self.singularize(words[index + 1]))"
                let translated = localizePhrase(combined)
                if !translated.isEmpty && !Self.genericChineseLabels.contains(translated) {
                    localized.append(translated)
                }
            }
        }

        return Array(deduplicated(localized).prefix(5))
    }

    private func tokenizeChineseTerms(from text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: " -_/（）()[]【】,.，。;；:："))
            .map { $0.normalizedWhitespace().cleanedKnowledgeText() }
            .filter { !$0.isEmpty && ($0.containsChinese || $0.count <= 10) }
            .filter { !Self.genericChineseLabels.contains($0) }
    }

    private func fallbackTitle() -> String {
        if documentTitle.containsChinese {
            return documentTitle.cleanedKnowledgeText()
        }

        return localizePhrase(documentTitle)
    }

    private func cleanedOrFallback(_ value: String, fallback: String) -> String {
        let cleaned = value.normalizedWhitespace().cleanedKnowledgeText()
        if !cleaned.isEmpty {
            return cleaned
        }

        return fallback.normalizedWhitespace().cleanedKnowledgeText()
    }

    private func deduplicated(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for value in values {
            let cleaned = value.normalizedWhitespace().cleanedKnowledgeText()
            guard !cleaned.isEmpty, !seen.contains(cleaned) else { continue }
            seen.insert(cleaned)
            result.append(cleaned)
        }

        return result
    }

    private static func singularize(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s") else { return word }
        return String(word.dropLast())
    }

    private static let genericChineseLabels: Set<String> = [
        "原始论文", "原始文章", "方法", "结果", "摘要", "讨论", "结论",
        "关键词", "图", "表", "章节", "部分", "总结", "概述"
    ]

    private static let stopwords: Set<String> = ChunkingService.englishStopwords.union([
        "article", "articles", "author", "authors", "copyright", "journal",
        "paper", "study", "studies", "table", "tables", "figure", "figures"
    ])

    private static let phraseDictionary: [String: String] = [
        "abstract": "摘要",
        "appendix": "附录",
        "background": "研究背景",
        "case report": "病例报告",
        "clinical study": "临床研究",
        "comparison group": "对照组",
        "conclusion": "结论",
        "conclusions": "结论",
        "control group": "对照组",
        "data analysis": "数据分析",
        "discussion": "讨论",
        "experimental group": "实验组",
        "findings": "研究发现",
        "figure": "图",
        "figures": "图",
        "introduction": "引言",
        "keywords": "关键词",
        "main outcome measures": "主要结局指标",
        "materials and methods": "材料与方法",
        "method": "方法",
        "methods": "方法",
        "objective": "研究目的",
        "objectives": "研究目的",
        "original article": "原始论文",
        "overview": "概述",
        "participant": "受试者",
        "participants": "受试者",
        "patient": "患者",
        "patients": "患者",
        "purpose": "研究目的",
        "references": "参考文献",
        "result": "结果",
        "results": "结果",
        "review article": "综述文章",
        "sample": "样本",
        "samples": "样本",
        "statistical analysis": "统计分析",
        "study design": "研究设计",
        "summary": "总结",
        "table": "表"
    ]

    private static let wordDictionary: [String: String] = [
        "algorithm": "算法",
        "analysis": "分析",
        "answer": "答案",
        "application": "应用",
        "article": "文章",
        "attention": "注意力",
        "bone": "骨",
        "care": "护理",
        "chapter": "章节",
        "choice": "选择",
        "clinical": "临床",
        "computer": "计算机",
        "concept": "概念",
        "control": "对照",
        "data": "数据",
        "database": "数据库",
        "definition": "定义",
        "diagnosis": "诊断",
        "discussion": "讨论",
        "effect": "效果",
        "effective": "有效",
        "effects": "效果",
        "english": "英语",
        "evaluation": "评估",
        "example": "示例",
        "examples": "示例",
        "exam": "考试",
        "exercise": "练习",
        "figure": "图",
        "fracture": "骨折",
        "foundation": "基础",
        "group": "组",
        "guide": "导学",
        "hip": "髋部",
        "hospital": "医院",
        "image": "图像",
        "information": "信息",
        "intervention": "干预",
        "introduction": "引言",
        "judgment": "判断",
        "knowledge": "知识",
        "language": "语言",
        "learning": "学习",
        "management": "管理",
        "material": "资料",
        "method": "方法",
        "model": "模型",
        "network": "网络",
        "neural": "神经",
        "note": "笔记",
        "nursing": "护理",
        "objective": "目标",
        "order": "顺序",
        "outcome": "结局",
        "page": "页",
        "patient": "患者",
        "platform": "平台",
        "point": "要点",
        "practice": "练习",
        "prevention": "预防",
        "problem": "问题",
        "procedure": "流程",
        "proof": "证明",
        "question": "问题",
        "radius": "桡骨",
        "reading": "阅读",
        "result": "结果",
        "review": "复习",
        "sample": "样本",
        "score": "评分",
        "section": "章节",
        "speaking": "口语",
        "study": "研究",
        "summary": "总结",
        "system": "系统",
        "table": "表",
        "theorem": "定理",
        "treatment": "治疗",
        "vocabulary": "词汇",
        "wrist": "腕部",
        "writing": "写作"
    ]
}

private extension String {
    var containsChinese: Bool {
        unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    func firstMatch(of pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, range: range), match.numberOfRanges > 1 else {
            return nil
        }

        guard let captureRange = Range(match.range(at: 1), in: self) else {
            return nil
        }

        return String(self[captureRange])
    }
}
