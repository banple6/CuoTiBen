import Foundation

struct SourceJumpTarget: Identifiable, Equatable {
    let document: SourceDocument
    let anchor: SourceAnchor

    var id: String {
        "\(document.id.uuidString)-\(anchor.id)"
    }
}

struct SourceJumpCoordinator {
    let sourceDocuments: [SourceDocument]
    let structuredSources: [UUID: StructuredSourceBundle]

    func target(for anchor: SourceAnchor) -> SourceJumpTarget? {
        guard let document = sourceDocuments.first(where: { $0.id == anchor.sourceID }) else {
            return nil
        }

        let normalizedAnchor = normalizedAnchor(for: anchor, in: document)
        return SourceJumpTarget(document: document, anchor: normalizedAnchor)
    }

    func target(for note: Note) -> SourceJumpTarget? {
        target(for: note.sourceAnchor)
            ?? note.knowledgePoints.compactMap { target(for: $0, preferredSourceID: note.sourceAnchor.sourceID) }.first
    }

    func target(for point: KnowledgePoint, preferredSourceID: UUID? = nil) -> SourceJumpTarget? {
        let anchors = uniqueAnchors(point.sourceAnchors)
        if let preferredSourceID,
           let preferred = anchors
            .filter({ $0.sourceID == preferredSourceID })
            .compactMap(target(for:))
            .first {
            return preferred
        }

        return anchors.compactMap(target(for:)).first
    }

    private func normalizedAnchor(for anchor: SourceAnchor, in document: SourceDocument) -> SourceAnchor {
        guard let bundle = structuredSources[document.id] else {
            return anchor
        }

        if let sentence = bundle.sentence(id: anchor.sentenceID) {
            return anchorFromSentence(
                sentence,
                in: document,
                fallbackAnchor: anchor,
                bundle: bundle
            )
        }

        if let node = bundle.outlineNode(id: anchor.outlineNodeID) {
            if let sentence = bundle.sentence(id: node.primarySentenceID ?? node.anchor.sentenceID) {
                var resolved = anchorFromSentence(
                    sentence,
                    in: document,
                    fallbackAnchor: anchor,
                    bundle: bundle
                )
                resolved = SourceAnchor(
                    id: anchor.id,
                    sourceID: resolved.sourceID,
                    sourceTitle: resolved.sourceTitle,
                    pageIndex: resolved.pageIndex ?? node.anchor.page,
                    sentenceID: resolved.sentenceID,
                    outlineNodeID: node.id,
                    quotedText: resolved.quotedText,
                    anchorLabel: resolved.anchorLabel
                )
                return resolved
            }

            return SourceAnchor(
                id: anchor.id,
                sourceID: anchor.sourceID,
                sourceTitle: anchor.sourceTitle,
                pageIndex: node.anchor.page ?? anchor.pageIndex,
                sentenceID: anchor.sentenceID,
                outlineNodeID: node.id,
                quotedText: anchor.quotedText.nonEmpty ?? anchor.anchorLabel,
                anchorLabel: node.anchor.label.nonEmpty ?? anchor.anchorLabel
            )
        }

        if let fallbackSentence = bestSentenceMatch(for: anchor, in: bundle) {
            return anchorFromSentence(
                fallbackSentence,
                in: document,
                fallbackAnchor: anchor,
                bundle: bundle
            )
        }

        return anchor
    }

    private func anchorFromSentence(
        _ sentence: Sentence,
        in document: SourceDocument,
        fallbackAnchor: SourceAnchor,
        bundle: StructuredSourceBundle
    ) -> SourceAnchor {
        let matchedNodeID = fallbackAnchor.outlineNodeID
            ?? bundle.bestOutlineNode(forSentenceID: sentence.id)?.id

        return SourceAnchor(
            id: fallbackAnchor.id,
            sourceID: document.id,
            sourceTitle: document.title,
            pageIndex: sentence.page ?? fallbackAnchor.pageIndex,
            sentenceID: sentence.id,
            outlineNodeID: matchedNodeID,
            quotedText: fallbackAnchor.quotedText.nonEmpty ?? sentence.text,
            anchorLabel: sentence.anchorLabel
        )
    }

    private func bestSentenceMatch(for anchor: SourceAnchor, in bundle: StructuredSourceBundle) -> Sentence? {
        let candidates = bundle.sentences
        guard !candidates.isEmpty else {
            return nil
        }

        let scored = candidates.compactMap { sentence -> (Sentence, Double)? in
            let score = matchScore(for: anchor, sentence: sentence)
            guard score > 0.18 else { return nil }
            return (sentence, score)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }

                let lhsPageDelta = pageDistance(from: anchor.pageIndex, to: lhs.0.page)
                let rhsPageDelta = pageDistance(from: anchor.pageIndex, to: rhs.0.page)
                if lhsPageDelta != rhsPageDelta {
                    return lhsPageDelta < rhsPageDelta
                }

                return lhs.0.index < rhs.0.index
            }
            .first?
            .0
    }

    private func matchScore(for anchor: SourceAnchor, sentence: Sentence) -> Double {
        var score = 0.0

        if let anchorPage = anchor.pageIndex, let sentencePage = sentence.page {
            let delta = abs(anchorPage - sentencePage)
            if delta == 0 {
                score += 0.58
            } else {
                score += max(0.0, 0.24 - (Double(delta) * 0.06))
            }
        }

        if anchor.anchorLabel == sentence.anchorLabel {
            score += 0.9
        }

        let anchorText = anchor.quotedText.normalizedSearchText
        let sentenceText = sentence.text.normalizedSearchText
        if let anchorText, let sentenceText {
            if sentenceText.contains(anchorText) || anchorText.contains(sentenceText) {
                score += 0.85
            }

            let overlap = tokenOverlap(lhs: anchorText, rhs: sentenceText)
            score += overlap * 0.45
        }

        return score
    }

    private func tokenOverlap(lhs: String, rhs: String) -> Double {
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init).filter { $0.count >= 2 })
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init).filter { $0.count >= 2 })

        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else {
            return 0
        }

        let intersection = lhsTokens.intersection(rhsTokens).count
        let union = lhsTokens.union(rhsTokens).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    private func pageDistance(from lhs: Int?, to rhs: Int?) -> Int {
        guard let lhs, let rhs else { return .max }
        return abs(lhs - rhs)
    }

    private func uniqueAnchors(_ anchors: [SourceAnchor]) -> [SourceAnchor] {
        var seen = Set<String>()
        var results: [SourceAnchor] = []

        for anchor in anchors {
            let key = [
                anchor.id,
                anchor.sourceID.uuidString,
                anchor.sentenceID ?? "",
                anchor.outlineNodeID ?? "",
                anchor.anchorLabel
            ].joined(separator: "::")

            guard seen.insert(key).inserted else { continue }
            results.append(anchor)
        }

        return results
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedSearchText: String? {
        nonEmpty?
            .lowercased()
            .replacingOccurrences(
                of: "[^a-z0-9\\u4e00-\\u9fa5]+",
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
    }
}
