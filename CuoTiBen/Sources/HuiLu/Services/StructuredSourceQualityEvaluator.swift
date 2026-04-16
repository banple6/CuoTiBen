import Foundation

struct StructuredSourceQualityReport {
    let sentenceCount: Int
    let segmentCount: Int
    let outlineNodeCount: Int
    let hasRootSummary: Bool
    let nonGenericChildTitleCount: Int

    var isAcceptableForLocalOnly: Bool {
        sentenceCount >= 6 &&
        segmentCount >= 2 &&
        outlineNodeCount >= 2 &&
        hasRootSummary &&
        nonGenericChildTitleCount >= 1
    }

    var isTooWeakForLocalOnly: Bool {
        !isAcceptableForLocalOnly
    }

    var debugSummary: String {
        "sentences=\(sentenceCount) segments=\(segmentCount) outline=\(outlineNodeCount) rootSummary=\(hasRootSummary) meaningfulTitles=\(nonGenericChildTitleCount)"
    }
}

enum StructuredSourceQualityEvaluator {
    static func evaluate(_ payload: StructuredSourceParsePayload) -> StructuredSourceQualityReport {
        let bundle = payload.bundle
        let flattenedNodes = bundle.flattenedOutlineNodes()
        let rootNode = flattenedNodes.first(where: { $0.depth == 0 }) ?? bundle.outline.first
        let hasRootSummary = !(rootNode?.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let nonGenericChildTitleCount = flattenedNodes.filter {
            $0.depth > 0 && !isGenericTitle($0.title)
        }.count

        return StructuredSourceQualityReport(
            sentenceCount: bundle.sentences.count,
            segmentCount: bundle.segments.count,
            outlineNodeCount: flattenedNodes.count,
            hasRootSummary: hasRootSummary,
            nonGenericChildTitleCount: nonGenericChildTitleCount
        )
    }

    private static func isGenericTitle(_ value: String) -> Bool {
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return true }

        if normalized.range(
            of: #"^(section|part|chapter|paragraph|node)\b|^第?\s*\d+\s*(段|节|部分)?$"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        let genericTitles: Set<String> = [
            "资料总览", "资料节点", "正文", "引言", "结论", "背景", "分析", "总结",
            "section", "part", "chapter", "paragraph", "node"
        ]
        return genericTitles.contains(normalized)
    }
}
