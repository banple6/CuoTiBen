import Foundation

struct KnowledgePointMatch {
    let point: KnowledgePoint
    let score: Double
}

final class KnowledgePointMatcher {
    func bestMatch(
        recognizedText: String,
        sourceAnchor: SourceAnchor?,
        knowledgePoints: [KnowledgePoint]
    ) -> KnowledgePointMatch? {
        let normalizedText = normalize(recognizedText)
        guard !normalizedText.isEmpty else { return nil }

        let matches = knowledgePoints.compactMap { point -> KnowledgePointMatch? in
            let score = score(point: point, text: normalizedText, sourceAnchor: sourceAnchor)
            guard score >= 0.72 else { return nil }
            return KnowledgePointMatch(point: point, score: score)
        }

        return matches.max(by: { $0.score < $1.score })
    }
}

private extension KnowledgePointMatcher {
    func score(point: KnowledgePoint, text: String, sourceAnchor: SourceAnchor?) -> Double {
        let normalizedTitle = normalize(point.title)
        let aliasScores = point.aliases.map { candidateScore(candidate: normalize($0), text: text) }
        let shortDefinitionScore = candidateScore(
            candidate: normalize(point.shortDefinition ?? ""),
            text: text
        ) * 0.78
        let definitionScore = candidateScore(
            candidate: normalize(point.definition),
            text: text
        ) * 0.62

        var best = max(
            candidateScore(candidate: normalizedTitle, text: text),
            aliasScores.max() ?? 0,
            shortDefinitionScore,
            definitionScore
        )

        if let sourceAnchor {
            let context = normalize([
                sourceAnchor.sourceTitle,
                sourceAnchor.quotedText,
                sourceAnchor.anchorLabel
            ].joined(separator: " "))
            if context.contains(normalizedTitle) || point.aliases.contains(where: { context.contains(normalize($0)) }) {
                best += 0.05
            }
        }

        return min(best, 1.0)
    }

    func candidateScore(candidate: String, text: String) -> Double {
        guard !candidate.isEmpty, !text.isEmpty else { return 0 }
        if candidate == text {
            return 1.0
        }
        if candidate.contains(text) {
            let ratio = Double(text.count) / Double(max(candidate.count, 1))
            return 0.78 + min(ratio * 0.18, 0.18)
        }
        if text.contains(candidate) {
            let ratio = Double(candidate.count) / Double(max(text.count, 1))
            return 0.74 + min(ratio * 0.16, 0.16)
        }

        let overlap = tokenOverlap(lhs: candidate, rhs: text)
        return overlap * 0.82
    }

    func tokenOverlap(lhs: String, rhs: String) -> Double {
        let lhsTokens = Set(tokens(from: lhs))
        let rhsTokens = Set(tokens(from: rhs))
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }
        let intersection = lhsTokens.intersection(rhsTokens).count
        let union = lhsTokens.union(rhsTokens).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    func tokens(from value: String) -> [String] {
        if value.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil {
            return value
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map { String($0).lowercased() }
                .filter { !$0.isEmpty }
        }

        let characters = Array(value)
        guard characters.count >= 2 else { return [value] }
        return (0..<(characters.count - 1)).map { index in
            String(characters[index...index + 1])
        }
    }

    func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
