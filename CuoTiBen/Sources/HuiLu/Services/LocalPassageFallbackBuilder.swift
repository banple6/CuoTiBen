import Foundation

struct LocalPassageFallbackBuildResult {
    let delta: ProfessorAnalysisDelta
    let paragraphProvenances: [String: NodeProvenance]
    let keySentenceIDs: [String]
    let meta: AIServiceResponseMeta
    let message: String
    let structuredError: AIStructuredError?
    let analysisDiagnostics: PassageAnalysisDiagnostics
}

private enum LocalPassageFallbackKind {
    case passageFallback
    case learningMaterialFallback
    case vocabularyNotesFallback
    case questionSheetFallback
    case auxiliaryOnlyFallback
    case insufficientTextFallback

    init(materialMode: MaterialAnalysisMode) {
        switch materialMode {
        case .passageReading:
            self = .passageFallback
        case .learningMaterial:
            self = .learningMaterialFallback
        case .vocabularyNotes:
            self = .vocabularyNotesFallback
        case .questionSheet:
            self = .questionSheetFallback
        case .auxiliaryOnlyMap:
            self = .auxiliaryOnlyFallback
        case .insufficientText:
            self = .insufficientTextFallback
        }
    }

    var structureTitle: String {
        switch self {
        case .passageFallback:
            return "正文结构"
        case .learningMaterialFallback:
            return "学习资料结构"
        case .vocabularyNotesFallback:
            return "词汇讲义结构"
        case .questionSheetFallback:
            return "题目结构"
        case .auxiliaryOnlyFallback:
            return "辅助资料结构"
        case .insufficientTextFallback:
            return "文本不足结构"
        }
    }

    var likelyQuestionTypes: [String] {
        switch self {
        case .passageFallback:
            return ["段落作用题", "主旨概括题", "信息定位题"]
        case .learningMaterialFallback:
            return ["结构梳理题", "信息归类题", "概念定位题"]
        case .vocabularyNotesFallback:
            return ["词义匹配题", "术语定位题", "注释回填题"]
        case .questionSheetFallback:
            return ["题干定位题", "选项筛选题", "证据回指题"]
        case .auxiliaryOnlyFallback:
            return ["资料分类题", "结构归类题", "辅助信息回指题"]
        case .insufficientTextFallback:
            return ["资料补全文字后再分析"]
        }
    }

    var logicPitfalls: [String] {
        switch self {
        case .passageFallback:
            return [
                "不要把段落举例误当作者最终结论",
                "不要把题目辅助信息混进正文主线"
            ]
        case .learningMaterialFallback:
            return [
                "不要把中文说明误当英文正文主线",
                "先区分讲义结构，再决定哪些信息适合精读"
            ]
        case .vocabularyNotesFallback:
            return [
                "不要把词汇注释误当文章段落主线",
                "先建立术语卡片，再回到对应知识点"
            ]
        case .questionSheetFallback:
            return [
                "不要把题干和选项伪装成正文段落",
                "先定位题目结构，再找真正证据"
            ]
        case .auxiliaryOnlyFallback:
            return [
                "不要把辅助资料拼接成虚假的正文主线",
                "先按类型归类，再决定哪些内容需要回到正文核对"
            ]
        case .insufficientTextFallback:
            return [
                "当前正文太短，不能直接推导正文级结构",
                "补充完整正文页后再进入 passage analysis"
            ]
        }
    }
}

enum LocalPassageFallbackBuilder {
    static func build(
        document: SourceDocument,
        bundle: StructuredSourceBundle,
        diagnostics: PassageAnalysisDiagnostics,
        structuredError: AIStructuredError?,
        meta: AIServiceResponseMeta? = nil
    ) -> LocalPassageFallbackBuildResult {
        let fallbackKind = LocalPassageFallbackKind(materialMode: diagnostics.materialMode)
        let fallbackSegments = candidateSegments(in: bundle, kind: fallbackKind)
        let paragraphCards = fallbackSegments.enumerated().map { offset, segment in
            makeParagraphCard(
                segment: segment,
                paragraphIndex: offset,
                bundle: bundle,
                kind: fallbackKind
            )
        }

        let resolvedMessage = resolvedMessage(
            diagnostics: diagnostics,
            structuredError: structuredError
        )
        let overview = PassageOverview(
            articleTheme: fallbackArticleTheme(document: document, segments: fallbackSegments, kind: fallbackKind),
            authorCoreQuestion: resolvedMessage,
            progressionPath: fallbackProgressionPath(kind: fallbackKind, segmentCount: paragraphCards.count),
            likelyQuestionTypes: fallbackKind.likelyQuestionTypes,
            logicPitfalls: fallbackKind.logicPitfalls,
            paragraphFunctionMap: paragraphCards.map {
                "\($0.anchorLabel)：\($0.argumentRole.displayName)"
            },
            syntaxHighlights: [],
            readingTraps: [resolvedMessage],
            vocabularyHighlights: []
        )

        let keySentenceIDs = Array(paragraphCards.compactMap { $0.coreSentenceID }.prefix(6))
        let paragraphProvenances = Dictionary<String, NodeProvenance>(
            uniqueKeysWithValues: fallbackSegments.map { segment in
                (
                    segment.id,
                    NodeProvenance(
                        sourceSegmentID: segment.id,
                        sourceSentenceID: segment.sentenceIDs.first,
                        sourcePage: segment.page,
                        sourceKind: segment.provenance.sourceKind,
                        generatedFrom: .localFallback,
                        hygieneScore: segment.hygiene.score,
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
            sentenceCards: [],
            passageAnalysisDiagnostics: diagnostics
        )

        return LocalPassageFallbackBuildResult(
            delta: delta,
            paragraphProvenances: paragraphProvenances,
            keySentenceIDs: keySentenceIDs,
            meta: meta ?? AIServiceResponseMeta.localFallback(),
            message: resolvedMessage,
            structuredError: structuredError,
            analysisDiagnostics: diagnostics
        )
    }

    private static func candidateSegments(
        in bundle: StructuredSourceBundle,
        kind: LocalPassageFallbackKind
    ) -> [Segment] {
        let preferred: [Segment]
        switch kind {
        case .passageFallback:
            preferred = bundle.segments.filter { $0.provenance.sourceKind == .passageBody }
        case .learningMaterialFallback:
            preferred = bundle.segments.filter {
                $0.provenance.sourceKind == .chineseInstruction
                || $0.provenance.sourceKind == .passageHeading
                || $0.provenance.sourceKind == .bilingualNote
            }
        case .vocabularyNotesFallback:
            preferred = bundle.segments.filter {
                $0.provenance.sourceKind == .vocabularySupport
                || $0.provenance.sourceKind == .bilingualNote
                || $0.provenance.sourceKind == .chineseInstruction
            }
        case .questionSheetFallback:
            preferred = bundle.segments.filter {
                $0.provenance.sourceKind == .question
                || $0.provenance.sourceKind == .answerKey
            }
        case .auxiliaryOnlyFallback:
            preferred = bundle.segments.filter { $0.provenance.sourceKind != .passageBody }
        case .insufficientTextFallback:
            preferred = []
        }

        let fallback = bundle.segments.filter { !$0.text.normalizedFallbackText.isEmpty }
        let resolved = (preferred.isEmpty ? fallback : preferred)
            .filter { !$0.text.normalizedFallbackText.isEmpty }
            .sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.id < rhs.id
            }
        return Array(resolved.prefix(4))
    }

    private static func makeParagraphCard(
        segment: Segment,
        paragraphIndex: Int,
        bundle: StructuredSourceBundle,
        kind: LocalPassageFallbackKind
    ) -> ParagraphTeachingCard {
        let sentences = bundle.sentences(in: segment)
        let firstSentence = sentences.first
        return ParagraphTeachingCard(
            id: "local_fallback_\(segment.id)",
            segmentID: segment.id,
            paragraphIndex: paragraphIndex,
            anchorLabel: segment.anchorLabel,
            theme: paragraphTheme(for: segment, kind: kind),
            argumentRole: paragraphRole(for: paragraphIndex, segment: segment, kind: kind),
            coreSentenceID: firstSentence?.id,
            keywords: [],
            relationToPrevious: paragraphRelation(for: paragraphIndex, kind: kind),
            examValue: examValue(for: kind),
            teachingFocuses: teachingFocuses(for: kind),
            studentBlindSpot: studentBlindSpot(for: kind),
            isAIGenerated: false
        )
    }

    private static func paragraphTheme(
        for segment: Segment,
        kind: LocalPassageFallbackKind
    ) -> String {
        let normalized = segment.text.normalizedFallbackText
        guard !normalized.isEmpty else { return kind.structureTitle }
        switch kind {
        case .passageFallback:
            return normalized.count > 46 ? String(normalized.prefix(46)) : normalized
        default:
            return "\(segment.provenance.sourceKind.displayName)：\(normalized.count > 34 ? String(normalized.prefix(34)) : normalized)"
        }
    }

    private static func paragraphRole(
        for index: Int,
        segment: Segment,
        kind: LocalPassageFallbackKind
    ) -> ParagraphArgumentRole {
        switch kind {
        case .passageFallback:
            let lowercased = segment.text.lowercased()
            if index == 0 { return .background }
            if lowercased.contains("however") || lowercased.contains("but") || lowercased.contains("yet") {
                return .objection
            }
            if lowercased.contains("for example") || lowercased.contains("for instance") || lowercased.contains("according to") {
                return .evidence
            }
            return .support
        case .learningMaterialFallback, .insufficientTextFallback:
            return index == 0 ? .background : .support
        case .vocabularyNotesFallback:
            return .evidence
        case .questionSheetFallback:
            return index == 0 ? .transition : .evidence
        case .auxiliaryOnlyFallback:
            return index == 0 ? .background : .support
        }
    }

    private static func paragraphRelation(
        for index: Int,
        kind: LocalPassageFallbackKind
    ) -> String {
        switch kind {
        case .passageFallback:
            switch index {
            case 0:
                return "先交代文章背景和切入点。"
            case 1:
                return "承接上一段，开始推进作者判断。"
            default:
                return "继续补充论证或收束前文判断。"
            }
        case .learningMaterialFallback:
            return index == 0 ? "先建立讲义主题，再补充说明和例外信息。" : "继续补充讲义说明或辅助知识点。"
        case .vocabularyNotesFallback:
            return index == 0 ? "先给术语或双语注释定锚点。" : "继续补充词义、例句或使用提醒。"
        case .questionSheetFallback:
            return index == 0 ? "先交代题干范围，再看选项和答案线索。" : "继续补充题目证据或答案提示。"
        case .auxiliaryOnlyFallback:
            return index == 0 ? "先建立辅助资料分类，再看各类信息之间的对应关系。" : "继续补充辅助资料的归类和用途。"
        case .insufficientTextFallback:
            return "当前文本不足，先保留结构锚点。"
        }
    }

    private static func examValue(for kind: LocalPassageFallbackKind) -> String {
        switch kind {
        case .passageFallback:
            return "先看本段在全文推进里的位置，再决定是否进入句子精讲。"
        case .learningMaterialFallback:
            return "先按讲义结构整理信息，再决定哪些段落值得进一步精读。"
        case .vocabularyNotesFallback:
            return "先建立术语或双语注释对应关系，再回到正文阅读。"
        case .questionSheetFallback:
            return "先识别题干、选项和答案线索，再回到证据句。"
        case .auxiliaryOnlyFallback:
            return "先按辅助资料类型建立结构，再决定哪些部分需要正文支持。"
        case .insufficientTextFallback:
            return "当前文本不足，先提示补充完整正文页。"
        }
    }

    private static func teachingFocuses(for kind: LocalPassageFallbackKind) -> [String] {
        switch kind {
        case .passageFallback:
            return ["先锁定本段角色", "再决定是否深挖核心句"]
        case .learningMaterialFallback:
            return ["先按学习资料结构阅读", "当前不进入正文级 passage analysis"]
        case .vocabularyNotesFallback:
            return ["先整理词汇或双语注释", "当前不进入正文级 passage analysis"]
        case .questionSheetFallback:
            return ["先辨认题干与选项结构", "当前不进入正文级 passage analysis"]
        case .auxiliaryOnlyFallback:
            return ["先按辅助资料分类整理", "当前不进入正文级 passage analysis"]
        case .insufficientTextFallback:
            return ["当前正文不足", "补充完整正文页后再尝试正文精读"]
        }
    }

    private static func studentBlindSpot(for kind: LocalPassageFallbackKind) -> String {
        switch kind {
        case .passageFallback:
            return "容易把段落细节和段落作用混为一谈。"
        case .learningMaterialFallback:
            return "容易把讲义说明或中文解析误判成英文正文主线。"
        case .vocabularyNotesFallback:
            return "容易把词汇注释和双语说明误判成正文段落。"
        case .questionSheetFallback:
            return "容易把题干、选项和答案线索误判成正文论证。"
        case .auxiliaryOnlyFallback:
            return "容易把辅助资料混拼成看似完整的正文结构。"
        case .insufficientTextFallback:
            return "当前正文过短，容易误把碎片文本当成完整文章。"
        }
    }

    private static func fallbackArticleTheme(
        document: SourceDocument,
        segments: [Segment],
        kind: LocalPassageFallbackKind
    ) -> String {
        if kind == .passageFallback, let first = segments.first {
            let snippet = first.text.normalizedFallbackText
            return snippet.count > 46 ? String(snippet.prefix(46)) : snippet
        }
        return kind.structureTitle
    }

    private static func fallbackProgressionPath(
        kind: LocalPassageFallbackKind,
        segmentCount: Int
    ) -> String {
        guard segmentCount > 0 else {
            return kind == .insufficientTextFallback
                ? "当前未形成稳定正文段落，先保留结构骨架。"
                : "当前材料先按本地结构骨架展示。"
        }

        switch kind {
        case .passageFallback:
            return segmentCount > 1
                ? "先看背景切入，再看中段支撑，最后回到全文判断。"
                : "当前材料较短，先看这一段如何提出核心信息。"
        case .learningMaterialFallback:
            return "先看讲义说明，再看补充注释和辅助知识点。"
        case .vocabularyNotesFallback:
            return "先看词汇或双语注释，再回到对应知识点。"
        case .questionSheetFallback:
            return "先看题干和选项，再定位答案线索。"
        case .auxiliaryOnlyFallback:
            return "先按辅助资料分类，再看各类辅助信息之间的对应关系。"
        case .insufficientTextFallback:
            return "当前文本不足，先保留结构锚点，等待补充正文页。"
        }
    }

    private static func resolvedMessage(
        diagnostics: PassageAnalysisDiagnostics,
        structuredError: AIStructuredError?
    ) -> String {
        if diagnostics.materialMode.shouldRequestRemote {
            return structuredError?.passageFallbackMessage ?? diagnostics.fallbackMessage
        }
        return diagnostics.fallbackMessage + " 如果需要正文精读，请导入完整英文文章正文页。"
    }
}

private extension String {
    var normalizedFallbackText: String {
        replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
