import SwiftUI
import PDFKit
import UIKit

struct StructuredSourcePDFReader: UIViewRepresentable {
    let document: SourceDocument
    let bundle: StructuredSourceBundle
    let renderMode: SourceReaderMode
    let highlightedSentenceID: String?
    let highlightedWordToken: String?
    let jumpTargetSentenceID: String?
    let jumpTargetSegmentID: String?
    let onSentenceTap: (Sentence) -> Void
    let onWordTap: (Sentence, String) -> Void
    let onJumpHandled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSentenceTap: onSentenceTap,
            onWordTap: onWordTap,
            onJumpHandled: onJumpHandled
        )
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = false
        pdfView.pageShadowsEnabled = false
        pdfView.backgroundColor = .clear
        pdfView.documentView?.backgroundColor = .clear

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.cancelsTouchesInView = false
        pdfView.addGestureRecognizer(tapGesture)

        context.coordinator.pdfView = pdfView
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        context.coordinator.onSentenceTap = onSentenceTap
        context.coordinator.onWordTap = onWordTap
        context.coordinator.onJumpHandled = onJumpHandled
        context.coordinator.update(
            document: document,
            bundle: bundle,
            renderMode: renderMode,
            highlightedSentenceID: highlightedSentenceID,
            highlightedWordToken: highlightedWordToken,
            jumpTargetSentenceID: jumpTargetSentenceID,
            jumpTargetSegmentID: jumpTargetSegmentID,
            in: pdfView
        )
    }
}

extension StructuredSourcePDFReader {
    final class Coordinator: NSObject {
        private enum DisplayStrategy: Equatable {
            case continuous
            case singlePage
        }

        weak var pdfView: PDFView?
        var onSentenceTap: (Sentence) -> Void
        var onWordTap: (Sentence, String) -> Void
        var onJumpHandled: () -> Void

        private var currentBundle: StructuredSourceBundle?
        private var currentSourceDocument: SourceDocument?
        private var renderSignature: String?
        private var renderResult: StructuredSourcePDFDocumentSnapshot?
        private var currentHighlightSentenceID: String?
        private var currentHighlightWordToken: String?
        private var currentHighlightPageIndex: Int?
        private var currentHighlightAnnotations: [HighlightAnnotationKey: PDFAnnotation] = [:]
        private var lastNavigatedSentenceID: String?
        private var lastJumpToken: String?
        private var currentDisplayStrategy: DisplayStrategy?
        private var lastMeasuredViewportWidth: CGFloat = 0

        init(
            onSentenceTap: @escaping (Sentence) -> Void,
            onWordTap: @escaping (Sentence, String) -> Void,
            onJumpHandled: @escaping () -> Void
        ) {
            self.onSentenceTap = onSentenceTap
            self.onWordTap = onWordTap
            self.onJumpHandled = onJumpHandled
        }

        func update(
            document: SourceDocument,
            bundle: StructuredSourceBundle,
            renderMode: SourceReaderMode,
            highlightedSentenceID: String?,
            highlightedWordToken: String?,
            jumpTargetSentenceID: String?,
            jumpTargetSegmentID: String?,
            in pdfView: PDFView
        ) {
            currentBundle = bundle
            currentSourceDocument = document

            let nextSignature = Self.signature(for: bundle, document: document, renderMode: renderMode)
            if renderSignature != nextSignature || renderResult == nil || pdfView.document == nil {
                renderSignature = nextSignature
                renderResult = StructuredSourcePDFDocumentBuilder.makeDocumentSnapshot(
                    sourceDocument: document,
                    bundle: bundle,
                    renderMode: renderMode
                )
                if let pdfDocument = renderResult?.document {
                    configureDisplayStrategy(
                        for: pdfDocument,
                        renderMode: renderMode,
                        in: pdfView
                    )
                    pdfView.document = pdfDocument
                    refreshScaleBounds(in: pdfView)
                    scheduleViewportRefresh(for: pdfDocument, renderMode: renderMode, in: pdfView)
                }
                currentHighlightSentenceID = nil
                currentHighlightWordToken = nil
                currentHighlightAnnotations = [:]
                currentHighlightPageIndex = nil
                lastNavigatedSentenceID = nil
            } else if let pdfDocument = pdfView.document {
                configureDisplayStrategy(
                    for: pdfDocument,
                    renderMode: renderMode,
                    in: pdfView
                )
                refreshScaleBounds(in: pdfView)
                scheduleViewportRefresh(for: pdfDocument, renderMode: renderMode, in: pdfView)
            }

            updateHighlight(
                for: highlightedSentenceID,
                wordToken: highlightedWordToken,
                in: pdfView
            )

            if let jumpTargetSentenceID {
                let jumpToken = "sentence:\(jumpTargetSentenceID)"
                if jumpToken != lastJumpToken {
                    navigateToSentence(id: jumpTargetSentenceID, in: pdfView, animated: true)
                    lastJumpToken = jumpToken
                    deferJumpHandled()
                }
            } else if let jumpTargetSegmentID {
                let jumpToken = "segment:\(jumpTargetSegmentID)"
                if jumpToken != lastJumpToken {
                    navigateToSegment(id: jumpTargetSegmentID, in: pdfView, animated: true)
                    lastJumpToken = jumpToken
                    deferJumpHandled()
                }
            } else {
                lastJumpToken = nil
                if highlightedSentenceID != lastNavigatedSentenceID {
                    navigateToSentence(id: highlightedSentenceID, in: pdfView, animated: false)
                }
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard
                let pdfView,
                let document = pdfView.document,
                let renderResult,
                let bundle = currentBundle
            else {
                return
            }

            let location = gesture.location(in: pdfView)
            guard let page = pdfView.page(for: location, nearest: true) else { return }

            let pagePoint = pdfView.convert(location, to: page)
            let pageIndex = document.index(for: page)

            let anchorsOnPage = renderResult.sentenceAnchors
                .filter { $0.value.pageIndex == pageIndex }
                .sorted { lhs, rhs in
                    lhs.value.primaryRect.minY > rhs.value.primaryRect.minY
                }

            if let wordHit = anchorsOnPage.first(where: { anchor in
                anchor.value.wordAnchors.contains(where: { $0.rect.insetBy(dx: -4, dy: -6).contains(pagePoint) })
            }),
               let sentence = bundle.sentence(id: wordHit.key),
               let matchedWord = wordHit.value.wordAnchors.first(where: { $0.rect.insetBy(dx: -4, dy: -6).contains(pagePoint) }) {
                onWordTap(sentence, matchedWord.token)
                return
            }

            if let hit = anchorsOnPage.first(where: { anchor in
                anchor.value.rects.contains(where: { $0.insetBy(dx: -8, dy: -8).contains(pagePoint) })
            }),
               let sentence = bundle.sentence(id: hit.key) {
                onSentenceTap(sentence)
                return
            }

            let nearest = anchorsOnPage.min { lhs, rhs in
                abs(lhs.value.primaryRect.midY - pagePoint.y) < abs(rhs.value.primaryRect.midY - pagePoint.y)
            }

            if let nearest, abs(nearest.value.primaryRect.midY - pagePoint.y) < 28,
               let sentence = bundle.sentence(id: nearest.key) {
                onSentenceTap(sentence)
            }
        }

        private func deferJumpHandled() {
            DispatchQueue.main.async { [onJumpHandled] in
                onJumpHandled()
            }
        }

        private func updateHighlight(for sentenceID: String?, wordToken: String?, in pdfView: PDFView) {
            guard currentHighlightSentenceID != sentenceID || currentHighlightWordToken != wordToken else { return }

            currentHighlightSentenceID = sentenceID
            currentHighlightWordToken = wordToken
            let previousPageIndex = currentHighlightPageIndex
            var existingAnnotations = currentHighlightAnnotations

            guard
                let sentenceID,
                let renderResult,
                let document = pdfView.document,
                let anchor = renderResult.sentenceAnchors[sentenceID],
                let page = document.page(at: anchor.pageIndex)
            else {
                if let previousPageIndex, let previousPage = documentOrCurrentPage(in: pdfView, pageIndex: previousPageIndex) {
                    existingAnnotations.values.forEach { previousPage.removeAnnotation($0) }
                }
                currentHighlightPageIndex = nil
                currentHighlightAnnotations = [:]
                return
            }

            let normalizedWordToken = Self.normalizedWordToken(wordToken)
            let matchedWordRects = anchor.wordAnchors
                .filter { Self.normalizedWordToken($0.token) == normalizedWordToken }
                .map(\.rect)
            let highlightRects: [CGRect]
            if !matchedWordRects.isEmpty {
                highlightRects = matchedWordRects
            } else if anchor.wordAnchors.isEmpty {
                highlightRects = anchor.rects
            } else {
                highlightRects = anchor.wordAnchors.map(\.rect)
            }
            let isWordOnlyHighlight = normalizedWordToken != nil && !matchedWordRects.isEmpty
            let alpha: CGFloat = isWordOnlyHighlight ? 0.32 : (anchor.wordAnchors.isEmpty ? 0.2 : 0.24)
            let desiredKeys = Set(highlightRects.map { HighlightAnnotationKey(pageIndex: anchor.pageIndex, rect: $0, alpha: alpha) })

            if previousPageIndex != anchor.pageIndex {
                if let previousPageIndex, let previousPage = documentOrCurrentPage(in: pdfView, pageIndex: previousPageIndex) {
                    existingAnnotations.values.forEach { previousPage.removeAnnotation($0) }
                }
                existingAnnotations.removeAll()
            }

            let obsoleteKeys = Set(existingAnnotations.keys).subtracting(desiredKeys)
            for key in obsoleteKeys {
                if let annotation = existingAnnotations.removeValue(forKey: key) {
                    page.removeAnnotation(annotation)
                }
            }

            let missingKeys = desiredKeys.subtracting(existingAnnotations.keys)
            for key in missingKeys {
                let annotation = PDFAnnotation(bounds: key.rect, forType: .square, withProperties: nil)
                let color = UIColor.systemYellow.withAlphaComponent(key.alpha)
                annotation.color = color
                annotation.interiorColor = color
                let border = PDFBorder()
                border.lineWidth = 0
                annotation.border = border
                page.addAnnotation(annotation)
                existingAnnotations[key] = annotation
            }

            currentHighlightPageIndex = anchor.pageIndex
            currentHighlightAnnotations = existingAnnotations
        }

        private func navigateToSentence(id: String?, in pdfView: PDFView, animated: Bool) {
            guard
                let id,
                let renderResult,
                let document = pdfView.document,
                let anchor = renderResult.sentenceAnchors[id],
                let page = document.page(at: anchor.pageIndex)
            else {
                return
            }

            let point = CGPoint(
                x: anchor.primaryRect.minX,
                y: min(page.bounds(for: .mediaBox).maxY - 24, anchor.primaryRect.maxY + 44)
            )
            let destination = PDFDestination(page: page, at: point)

            if animated {
                pdfView.go(to: destination)
            } else {
                pdfView.go(to: destination)
            }

            lastNavigatedSentenceID = id
        }

        private func navigateToSegment(id: String, in pdfView: PDFView, animated: Bool) {
            guard
                let bundle = currentBundle,
                let sentenceID = bundle.sentences.first(where: { $0.segmentID == id })?.id
            else {
                return
            }

            navigateToSentence(id: sentenceID, in: pdfView, animated: animated)
        }

        private static func signature(for bundle: StructuredSourceBundle) -> String {
            let sentenceKey = bundle.sentences.map {
                let geometryKey = $0.geometry.map {
                    "\($0.page):\($0.source.rawValue):\($0.regions.count):\($0.wordRegions.count)"
                } ?? "none"
                return "\($0.id)#\($0.page ?? 0)#\(geometryKey)"
            }
            .joined(separator: "|")
            let segmentKey = bundle.segments.map(\.id).joined(separator: "|")
            return "\(bundle.source.id)#\(bundle.source.title)#\(segmentKey)#\(sentenceKey)"
        }

        private static func signature(
            for bundle: StructuredSourceBundle,
            document: SourceDocument,
            renderMode: SourceReaderMode
        ) -> String {
            "\(signature(for: bundle))#\(document.filePath ?? "none")#\(renderMode.rawValue)"
        }

        private static func normalizedWordToken(_ token: String?) -> String? {
            token?
                .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                .lowercased()
                .nilIfEmpty
        }

        private func documentOrCurrentPage(in pdfView: PDFView, pageIndex: Int) -> PDFPage? {
            pdfView.document?.page(at: pageIndex)
        }

        private func configureDisplayStrategy(
            for document: PDFDocument,
            renderMode: SourceReaderMode,
            in pdfView: PDFView
        ) {
            let viewportWidth = resolvedViewportWidth(in: pdfView)
            let strategy = preferredDisplayStrategy(
                for: document,
                renderMode: renderMode,
                viewportWidth: viewportWidth
            )
            guard strategy != currentDisplayStrategy || abs(lastMeasuredViewportWidth - viewportWidth) > 1 else { return }

            currentDisplayStrategy = strategy
            lastMeasuredViewportWidth = viewportWidth

            switch strategy {
            case .continuous:
                pdfView.usePageViewController(false, withViewOptions: nil)
                pdfView.displayMode = .singlePageContinuous
                pdfView.displayDirection = .vertical
                pdfView.displaysPageBreaks = true
            case .singlePage:
                pdfView.usePageViewController(false, withViewOptions: nil)
                pdfView.displayMode = .singlePage
                pdfView.displayDirection = .vertical
                pdfView.displaysPageBreaks = false
            }
        }

        private func refreshScaleBounds(in pdfView: PDFView) {
            pdfView.autoScales = true

            let fitScale = max(pdfView.scaleFactorForSizeToFit, 0.45)
            if fitScale.isFinite, fitScale > 0 {
                pdfView.minScaleFactor = fitScale * 0.88
                pdfView.maxScaleFactor = max(fitScale * 2.2, pdfView.minScaleFactor + 0.2)
                if pdfView.scaleFactor < pdfView.minScaleFactor || pdfView.scaleFactor > pdfView.maxScaleFactor {
                    pdfView.scaleFactor = fitScale
                }
            }
        }

        private func preferredDisplayStrategy(
            for document: PDFDocument,
            renderMode: SourceReaderMode,
            viewportWidth: CGFloat
        ) -> DisplayStrategy {
            let projectedHeight = projectedContinuousContentHeight(
                for: document,
                viewportWidth: viewportWidth
            )
            let safeLimit = preferredContinuousHeightLimit(for: renderMode)

            if projectedHeight >= safeLimit {
                return .singlePage
            }

            return .continuous
        }

        private func scheduleViewportRefresh(
            for document: PDFDocument,
            renderMode: SourceReaderMode,
            in pdfView: PDFView
        ) {
            DispatchQueue.main.async { [weak self, weak pdfView] in
                guard let self, let pdfView else { return }
                self.configureDisplayStrategy(
                    for: document,
                    renderMode: renderMode,
                    in: pdfView
                )
                self.refreshScaleBounds(in: pdfView)
            }
        }

        private func resolvedViewportWidth(in pdfView: PDFView) -> CGFloat {
            if pdfView.bounds.width > 0 {
                return pdfView.bounds.width
            }

            if let windowWidth = pdfView.window?.bounds.width, windowWidth > 0 {
                return windowWidth
            }

            return UIScreen.main.bounds.width
        }

        private func projectedContinuousContentHeight(
            for document: PDFDocument,
            viewportWidth: CGFloat
        ) -> CGFloat {
            guard viewportWidth > 0, document.pageCount > 0 else { return 0 }

            let pageGap: CGFloat = 16
            var totalHeight: CGFloat = 0

            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                guard bounds.width > 0, bounds.height > 0 else { continue }
                let fitScale = viewportWidth / bounds.width
                totalHeight += (bounds.height * fitScale)
                if index < document.pageCount - 1 {
                    totalHeight += pageGap
                }
            }

            return totalHeight
        }

        private func preferredContinuousHeightLimit(for renderMode: SourceReaderMode) -> CGFloat {
            switch renderMode {
            case .readingPDF:
                return 9_600
            case .originalPDFAligned:
                return 10_800
            }
        }
    }
}

private struct HighlightAnnotationKey: Hashable {
    let pageIndex: Int
    let minX: Int
    let minY: Int
    let width: Int
    let height: Int
    let alpha: CGFloat

    init(pageIndex: Int, rect: CGRect, alpha: CGFloat) {
        let normalized = rect.integral
        self.pageIndex = pageIndex
        self.minX = Int(normalized.minX.rounded())
        self.minY = Int(normalized.minY.rounded())
        self.width = Int(normalized.width.rounded())
        self.height = Int(normalized.height.rounded())
        self.alpha = alpha
    }

    var rect: CGRect {
        CGRect(x: minX, y: minY, width: width, height: height)
    }
}

private struct StructuredSourcePDFDocumentSnapshot {
    let document: PDFDocument
    let sentenceAnchors: [String: StructuredSourcePDFAnchor]
    let segmentAnchors: [String: StructuredSourcePDFAnchor]
}

private struct StructuredSourcePDFAnchor {
    let pageIndex: Int
    let rects: [CGRect]
    let wordAnchors: [StructuredSourcePDFWordAnchor]

    init(pageIndex: Int, rect: CGRect) {
        self.pageIndex = pageIndex
        self.rects = [rect]
        self.wordAnchors = []
    }

    init(pageIndex: Int, rects: [CGRect], wordAnchors: [StructuredSourcePDFWordAnchor] = []) {
        self.pageIndex = pageIndex
        self.rects = rects
        self.wordAnchors = wordAnchors
    }

    var primaryRect: CGRect {
        let sourceRects = wordAnchors.isEmpty ? rects : wordAnchors.map(\.rect)
        return sourceRects.reduce(into: CGRect.null) { partialResult, rect in
            partialResult = partialResult.union(rect)
        }
    }
}

private struct StructuredSourcePDFWordAnchor {
    let token: String
    let rect: CGRect
}

private enum StructuredSourcePDFDocumentBuilder {
    static func makeDocumentSnapshot(
        sourceDocument: SourceDocument,
        bundle: StructuredSourceBundle,
        renderMode: SourceReaderMode
    ) -> StructuredSourcePDFDocumentSnapshot {
        if renderMode == .originalPDFAligned,
           sourceDocument.documentType == .pdf,
           let filePath = sourceDocument.filePath,
           let originalPDF = PDFDocument(url: URL(fileURLWithPath: filePath)),
           let alignedSnapshot = buildOriginalPDFSnapshot(document: originalPDF, bundle: bundle) {
            return alignedSnapshot
        }

        return buildReadingPDFSnapshot(bundle: bundle)
    }

    private static func buildOriginalPDFSnapshot(
        document: PDFDocument,
        bundle: StructuredSourceBundle
    ) -> StructuredSourcePDFDocumentSnapshot? {
        var sentenceAnchors: [String: StructuredSourcePDFAnchor] = [:]
        var usedAnchorKeys: Set<String> = []

        for sentence in bundle.sentences {
            if let geometryAnchor = anchorFromGeometry(for: sentence, in: document) {
                sentenceAnchors[sentence.id] = geometryAnchor
                continue
            }

            guard let match = locateSentenceAnchor(
                for: sentence,
                in: document,
                usedAnchorKeys: &usedAnchorKeys
            ) else {
                continue
            }
            sentenceAnchors[sentence.id] = match
        }

        guard !sentenceAnchors.isEmpty else { return nil }

        var segmentAnchors: [String: StructuredSourcePDFAnchor] = [:]
        for segment in bundle.segments {
            guard
                let firstSentenceID = bundle.sentences(in: segment).first?.id,
                let anchor = sentenceAnchors[firstSentenceID]
            else {
                continue
            }

            segmentAnchors[segment.id] = anchor
        }

        return StructuredSourcePDFDocumentSnapshot(
            document: document,
            sentenceAnchors: sentenceAnchors,
            segmentAnchors: segmentAnchors
        )
    }

    private static func locateSentenceAnchor(
        for sentence: Sentence,
        in document: PDFDocument,
        usedAnchorKeys: inout Set<String>
    ) -> StructuredSourcePDFAnchor? {
        let expectedPageIndex = max((sentence.page ?? 1) - 1, 0)

        for candidate in searchCandidates(for: sentence.text) {
            let selections = document.findString(candidate, withOptions: [.caseInsensitive])
            let rankedMatches = selections.compactMap { selection -> (anchor: StructuredSourcePDFAnchor, score: Int, key: String)? in
                guard let page = selection.pages.first else { return nil }
                let pageIndex = document.index(for: page)
                let rect = selection.bounds(for: page)
                guard !rect.isEmpty else { return nil }
                let anchor = StructuredSourcePDFAnchor(pageIndex: pageIndex, rect: rect.insetBy(dx: -4, dy: -4))
                let pageDistance = abs(pageIndex - expectedPageIndex)
                let uniquenessPenalty = usedAnchorKeys.contains(anchorKey(for: anchor)) ? 100 : 0
                let score = pageDistance * 10 + uniquenessPenalty
                return (anchor, score, anchorKey(for: anchor))
            }
            .sorted { $0.score < $1.score }

            if let best = rankedMatches.first(where: { !usedAnchorKeys.contains($0.key) }) ?? rankedMatches.first {
                usedAnchorKeys.insert(best.key)
                return best.anchor
            }
        }

        return nil
    }

    private static func anchorFromGeometry(
        for sentence: Sentence,
        in document: PDFDocument
    ) -> StructuredSourcePDFAnchor? {
        guard
            let geometry = sentence.geometry,
            !geometry.regions.isEmpty
        else {
            return nil
        }

        let pageIndex = max(geometry.page - 1, 0)
        guard let page = document.page(at: pageIndex) else { return nil }

        let pageBounds = page.bounds(for: .mediaBox)
        let pageRects = geometry.regions
            .map(\.cgRect)
            .map { normalizedRect in
                CGRect(
                    x: pageBounds.minX + (normalizedRect.minX * pageBounds.width),
                    y: pageBounds.minY + (normalizedRect.minY * pageBounds.height),
                    width: normalizedRect.width * pageBounds.width,
                    height: normalizedRect.height * pageBounds.height
                )
            }
        guard !pageRects.isEmpty else { return nil }

        let expandedRects = pageRects
            .filter { !$0.isEmpty }
            .map { $0.insetBy(dx: -6, dy: -6) }

        let expandedWordAnchors = geometry.wordRegions
            .map { wordRegion -> StructuredSourcePDFWordAnchor in
                let normalizedRect = wordRegion.region.cgRect
                let rect = CGRect(
                    x: pageBounds.minX + (normalizedRect.minX * pageBounds.width),
                    y: pageBounds.minY + (normalizedRect.minY * pageBounds.height),
                    width: normalizedRect.width * pageBounds.width,
                    height: normalizedRect.height * pageBounds.height
                )
                return StructuredSourcePDFWordAnchor(
                    token: wordRegion.token,
                    rect: rect.insetBy(dx: -2, dy: -4)
                )
            }
            .filter { !$0.rect.isEmpty }

        guard !expandedRects.isEmpty else { return nil }

        return StructuredSourcePDFAnchor(
            pageIndex: pageIndex,
            rects: expandedRects,
            wordAnchors: expandedWordAnchors
        )
    }

    private static func searchCandidates(for sentence: String) -> [String] {
        let trimmed = sentence
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return [] }

        var candidates = [trimmed]

        if trimmed.count > 90 {
            candidates.append(String(trimmed.prefix(90)))
        }

        if trimmed.count > 60 {
            candidates.append(String(trimmed.prefix(60)))
        }

        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }

    private static func anchorKey(for anchor: StructuredSourcePDFAnchor) -> String {
        let rect = anchor.primaryRect.integral
        return "\(anchor.pageIndex)#\(Int(rect.minX))#\(Int(rect.minY))#\(Int(rect.width))#\(Int(rect.height))"
    }

    private static func buildReadingPDFSnapshot(bundle: StructuredSourceBundle) -> StructuredSourcePDFDocumentSnapshot {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let leftMargin: CGFloat = 44
        let rightMargin: CGFloat = 44
        let topMargin: CGFloat = 56
        let bottomMargin: CGFloat = 44
        let contentWidth = pageRect.width - leftMargin - rightMargin
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        var sentenceAnchors: [String: StructuredSourcePDFAnchor] = [:]
        var segmentAnchors: [String: StructuredSourcePDFAnchor] = [:]

        let groupedSegments = Dictionary(grouping: bundle.segments) { segment in
            segment.page ?? bundle.sentences(in: segment).first?.page ?? 1
        }

        let sortedPages = groupedSegments.keys.sorted()

        let data = renderer.pdfData { context in
            var currentGeneratedPageIndex = -1
            var cursorY = topMargin

            func beginPage(sourcePage: Int) {
                context.beginPage()
                currentGeneratedPageIndex += 1
                cursorY = topMargin

                let titleAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                    .foregroundColor: UIColor.black.withAlphaComponent(0.78)
                ]
                let metaAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: UIColor.systemBlue.withAlphaComponent(0.78)
                ]

                let title = bundle.source.title as NSString
                title.draw(
                    in: CGRect(x: leftMargin, y: 20, width: contentWidth * 0.7, height: 20),
                    withAttributes: titleAttributes
                )

                let pageLabel = "资料第\(sourcePage)页 · PDF 阅读" as NSString
                pageLabel.draw(
                    in: CGRect(x: leftMargin + (contentWidth * 0.58), y: 22, width: contentWidth * 0.42, height: 16),
                    withAttributes: metaAttributes
                )

                let separatorPath = UIBezierPath(
                    roundedRect: CGRect(x: leftMargin, y: 42, width: contentWidth, height: 1),
                    cornerRadius: 0.5
                )
                UIColor.systemBlue.withAlphaComponent(0.08).setFill()
                separatorPath.fill()
            }

            func ensureSpace(_ requiredHeight: CGFloat, sourcePage: Int) {
                if currentGeneratedPageIndex == -1 || cursorY + requiredHeight > pageRect.height - bottomMargin {
                    beginPage(sourcePage: sourcePage)
                }
            }

            func drawSegmentHeader(
                style: StructuredSourcePDFSegmentStyle,
                segment: Segment,
                sourcePage: Int,
                isContinuation: Bool
            ) {
                let chipText = isContinuation ? "\(style.displayName) · 续" : style.displayName
                let chipAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                    .foregroundColor: style.accentColor
                ]
                let chipSize = (chipText as NSString).size(withAttributes: chipAttributes)
                let chipRect = CGRect(x: leftMargin, y: cursorY, width: chipSize.width + 18, height: 22)

                let chipPath = UIBezierPath(roundedRect: chipRect, cornerRadius: 11)
                style.accentColor.withAlphaComponent(0.11).setFill()
                chipPath.fill()
                (chipText as NSString).draw(
                    in: CGRect(x: chipRect.minX + 9, y: chipRect.minY + 5, width: chipRect.width - 18, height: 12),
                    withAttributes: chipAttributes
                )

                cursorY += 28

                let anchorText = segment.anchorLabel as NSString
                let anchorAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: style.accentColor.withAlphaComponent(0.88)
                ]
                let anchorRect = CGRect(x: leftMargin, y: cursorY, width: contentWidth, height: 16)
                anchorText.draw(in: anchorRect, withAttributes: anchorAttributes)

                if segmentAnchors[segment.id] == nil {
                    let interactiveRect = CGRect(x: leftMargin - 6, y: cursorY - 6, width: contentWidth + 12, height: 28)
                    segmentAnchors[segment.id] = StructuredSourcePDFAnchor(
                        pageIndex: currentGeneratedPageIndex,
                        rect: convertToPDFSpace(interactiveRect, pageHeight: pageRect.height)
                    )
                }

                cursorY += 26
            }

            if sortedPages.isEmpty {
                beginPage(sourcePage: 1)
            }

            for sourcePage in sortedPages {
                let segments = groupedSegments[sourcePage]?.sorted(by: { $0.index < $1.index }) ?? []

                for segment in segments {
                    let sentences = bundle.sentences(in: segment)
                    let style = StructuredSourcePDFSegmentStyle(segment: segment, sentences: sentences)
                    var drewHeader = false

                    if !drewHeader {
                        ensureSpace(72, sourcePage: sourcePage)
                        drawSegmentHeader(style: style, segment: segment, sourcePage: sourcePage, isContinuation: false)
                        drewHeader = true
                    }

                    for sentence in sentences {
                        let textRect = measureTextRect(
                            text: sentence.text,
                            font: style.font,
                            x: leftMargin,
                            y: cursorY,
                            width: contentWidth
                        )
                        let requiredHeight = textRect.height + 16

                        if cursorY + requiredHeight > pageRect.height - bottomMargin {
                            beginPage(sourcePage: sourcePage)
                            drawSegmentHeader(style: style, segment: segment, sourcePage: sourcePage, isContinuation: true)
                        }

                        let drawingRect = measureTextRect(
                            text: sentence.text,
                            font: style.font,
                            x: leftMargin,
                            y: cursorY,
                            width: contentWidth
                        )

                        let sentenceRect = CGRect(
                            x: leftMargin - 6,
                            y: drawingRect.minY - 6,
                            width: contentWidth + 12,
                            height: drawingRect.height + 12
                        )

                        let selectionPath = UIBezierPath(roundedRect: sentenceRect, cornerRadius: 12)
                        UIColor.white.withAlphaComponent(0.92).setFill()
                        selectionPath.fill()

                        let textAttributes: [NSAttributedString.Key: Any] = [
                            .font: style.font,
                            .foregroundColor: UIColor.black.withAlphaComponent(0.8)
                        ]
                        (sentence.text as NSString).draw(
                            with: drawingRect,
                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                            attributes: textAttributes,
                            context: nil
                        )

                        sentenceAnchors[sentence.id] = StructuredSourcePDFAnchor(
                            pageIndex: currentGeneratedPageIndex,
                            rect: convertToPDFSpace(sentenceRect, pageHeight: pageRect.height)
                        )

                        cursorY = sentenceRect.maxY + 10
                    }

                    cursorY += 10
                }
            }
        }

        let pdfDocument = PDFDocument(data: data) ?? PDFDocument()

        return StructuredSourcePDFDocumentSnapshot(
            document: pdfDocument,
            sentenceAnchors: sentenceAnchors,
            segmentAnchors: segmentAnchors
        )
    }

    private static func measureTextRect(
        text: String,
        font: UIFont,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat
    ) -> CGRect {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )

        return CGRect(x: x, y: y, width: width, height: ceil(rect.height))
    }

    private static func convertToPDFSpace(_ uiRect: CGRect, pageHeight: CGFloat) -> CGRect {
        CGRect(
            x: uiRect.minX,
            y: pageHeight - uiRect.maxY,
            width: uiRect.width,
            height: uiRect.height
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct StructuredSourcePDFSegmentStyle {
    let displayName: String
    let accentColor: UIColor
    let font: UIFont

    init(segment: Segment, sentences: [Sentence]) {
        let combinedText = ([segment.text] + sentences.map(\.text)).joined(separator: " ")
        let uppercasedRatio = Self.uppercasedRatio(in: combinedText)

        if combinedText.lowercased().contains("directions") || combinedText.lowercased().contains("read the passage") {
            displayName = "题干说明"
            accentColor = .systemOrange
            font = .systemFont(ofSize: 15, weight: .semibold)
        } else if uppercasedRatio > 0.42 || combinedText.count < 60 {
            displayName = "标题导语"
            accentColor = .systemTeal
            font = .systemFont(ofSize: 18, weight: .bold)
        } else {
            displayName = "正文段落"
            accentColor = .systemBlue
            font = .systemFont(ofSize: 15, weight: .medium)
        }
    }

    private static func uppercasedRatio(in text: String) -> Double {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return 0 }
        let uppercaseCount = letters.filter { CharacterSet.uppercaseLetters.contains($0) }.count
        return Double(uppercaseCount) / Double(letters.count)
    }
}
