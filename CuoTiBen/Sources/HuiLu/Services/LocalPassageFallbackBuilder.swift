import Foundation

struct LocalPassageFallbackBuildResult {
    let delta: ProfessorAnalysisDelta
    let paragraphProvenances: [String: NodeProvenance]
    let keySentenceIDs: [String]
    let meta: AIServiceResponseMeta
    let message: String
    let structuredError: AIStructuredError?
}

enum LocalPassageFallbackBuilder {
    static func build(
        document: SourceDocument,
        bundle: StructuredSourceBundle,
        structuredError: AIStructuredError?,
        meta: AIServiceResponseMeta? = nil
    ) -> LocalPassageFallbackBuildResult {
        let bodySegments = candidateSegments(in: bundle)
        let paragraphCards = bodySegments.enumerated().map { offset, segment in
            makeParagraphCard(
                segment: segment,
                paragraphIndex: offset,
                bundle: bundle
            )
        }

        let overview = PassageOverview(
            articleTheme: fallbackArticleTheme(document: document, segments: bodySegments),
            authorCoreQuestion: "AI 地图分析暂不可用，当前先展示本地结构骨架。",
            progressionPath: fallbackProgressionPath(segmentCount: paragraphCards.count),
            likelyQuestionTypes: [
                "段落作用题",
                "主旨概括题",
                "信息定位题"
            ],
            logicPitfalls: [
                "不要把段落举例误当作者最终结论",
                "不要把题目辅助信息混进正文主线"
            ],
            paragraphFunctionMap: paragraphCards.map {
                "\($0.anchorLabel)：\($0.argumentRole.displayName)"
            },
            syntaxHighlights: [],
            readingTraps: [
                "先看段落角色，再看细节证据。"
            ],
            vocabularyHighlights: []
        )

        let keySentenceIDs = Array(paragraphCards.compactMap(\.coreSentenceID).prefix(6))
        let paragraphProvenances = Dictionary(
            uniqueKeysWithValues: bodySegments.map { segment in
                (
                    segment.id,
                    NodeProvenance(
                        sourceSegmentID: segment.id,
                        sourceSentenceID: segment.sentenceIDs.first,
                        sourceKind: .passageBody,
                        consistencyScore: 0.82
                    )
                )
            }
        )

        let delta = ProfessorAnalysisDelta(
            schemaVersion: ProfessorAnalysisCacheStore.analysisSchemaVersion,
            storedAt: Date(),
            passageOverview: overview,
            paragraphCards: paragraphCards,
            sentenceCards: []
        )

        let resolvedError = structuredError
        let resolvedMessage = resolvedError?.passageFallbackMessage
            ?? "AI 地图分析暂不可用，已展示本地结构骨架。"

        return LocalPassageFallbackBuildResult(
            delta: delta,
            paragraphProvenances: paragraphProvenances,
            keySentenceIDs: keySentenceIDs,
            meta: meta ?? .localFallback(),
            message: resolvedMessage,
            structuredError: resolvedError
        )
    }

    private static func candidateSegments(in bundle: StructuredSourceBundle) -> [Segment] {
        let primary = bundle.segments.filter { segment in
            segment.provenance.sourceKind == .passageBody
        }
        if !primary.isEmpty {
            return primary.prefix(4).map { $0 }
        }

        return bundle.segments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(4)
            .map { $0 }
    }

    private static func makeParagraphCard(
        segment: Segment,
        paragraphIndex: Int,
        bundle: StructuredSourceBundle
    ) -> ParagraphTeachingCard {
        let sentences = bundle.sentences(in: segment)
        let firstSentence = sentences.first
        return ParagraphTeachingCard(
            id: "local_fallback_\(segment.id)",
            segmentID: segment.id,
            paragraphIndex: paragraphIndex,
            anchorLabel: segment.anchorLabel,
            theme: paragraphTheme(for: segment),
            argumentRole: paragraphRole(for: paragraphIndex, segment: segment),
            coreSentenceID: firstSentence?.id,
            keywords: [],
            relationToPrevious: paragraphRelation(for: paragraphIndex),
            examValue: "先看本段在全文推进里的位置，再决定是否进入句子精讲。",
            teachingFocuses: [
                "先锁定本段角色",
                "再决定是否深挖核心句"
            ],
            studentBlindSpot: "容易把段落细节和段落作用混为一谈。",
            isAIGenerated: false
        )
    }

    private static func paragraphTheme(for segment: Segment) -> String {
        let normalized = segment.text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.count > 46 ? String(normalized.prefix(46)) : normalized
    }

    private static func paragraphRole(for index: Int, segment: Segment) -> ParagraphArgumentRole {
        let lowercased = segment.text.lowercased()
        if index == 0 { return .background }
        if lowercased.contains("however") || lowercased.contains("but") || lowercased.contains("yet") {
            return .objection
        }
        if lowercased.contains("for example") || lowercased.contains("for instance") || lowercased.contains("according to") {
            return .evidence
        }
        return .support
    }

    private static func paragraphRelation(for index: Int) -> String {
        switch index {
        case 0:
            return "先交代文章背景和切入点。"
        case 1:
            return "承接上一段，开始推进作者判断。"
        default:
            return "继续补充论证或收束前文判断。"
        }
    }

    private static func fallbackArticleTheme(document: SourceDocument, segments: [Segment]) -> String {
        if let first = segments.first {
            return paragraphTheme(for: first)
        }
        return document.title
    }

    private static func fallbackProgressionPath(segmentCount: Int) -> String {
        guard segmentCount > 1 else {
            return "当前材料较短，先看这一段如何提出核心信息。"
        }
        return "先看背景切入，再看中段支撑，最后回到全文判断。"
    }
}
