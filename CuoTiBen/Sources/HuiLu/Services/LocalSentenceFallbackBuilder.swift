import Foundation

enum LocalSentenceFallbackBuilder {
    static func build(
        context: ExplainSentenceContext,
        requestIdentity: AIRequestIdentity?,
        structuredError: AIStructuredError?,
        meta: AIServiceResponseMeta? = nil
    ) -> AIExplainSentenceResult {
        let normalizedSentence = context.sentence
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let coreSkeleton = roughCoreSkeleton(for: normalizedSentence)
        let chunkLayers = roughChunkLayers(for: normalizedSentence)
        let grammarFocus = roughGrammarFocus(for: normalizedSentence)
        let requestID = structuredError?.requestID ?? requestIdentity?.clientRequestID
        let resolvedMeta = meta ?? .localFallback()
        let fallbackMessage = structuredError?.sentenceFallbackMessage ?? "AI 服务暂时繁忙，已展示本地解析骨架。"

        return AIExplainSentenceResult(
            originalSentence: normalizedSentence,
            evidenceType: nil,
            analysisIdentity: requestIdentity?.responseIdentity,
            sentenceFunction: "句子定位：当前展示的是本地解析骨架，用来先保住句子定位和主干框架。",
            coreSkeleton: coreSkeleton,
            chunkLayers: chunkLayers,
            grammarFocus: grammarFocus,
            faithfulTranslation: "AI 翻译暂不可用，可稍后重试。",
            teachingInterpretation: "AI 精讲暂不可用，当前展示本地解析骨架。",
            naturalChineseMeaning: "AI 精讲暂不可用，当前展示本地解析骨架。",
            sentenceCore: coreSkeleton?.rendered ?? shortened(normalizedSentence),
            chunkBreakdown: chunkLayers.map(\.rendered),
            grammarPoints: grammarFocus.map {
                ProfessorGrammarPoint(name: $0.titleZh, explanation: $0.explanationZh)
            },
            vocabularyInContext: [],
            misreadPoints: roughMisreadingTraps(for: normalizedSentence),
            examRewritePoints: roughExamRoutes(for: normalizedSentence),
            misreadingTraps: roughMisreadingTraps(for: normalizedSentence),
            examParaphraseRoutes: roughExamRoutes(for: normalizedSentence),
            simplifiedEnglish: shortened(normalizedSentence),
            simplerRewrite: shortened(normalizedSentence),
            simplerRewriteTranslation: "待 AI 精讲恢复后，再提供更准确的简化改写说明。",
            miniExercise: nil,
            miniCheck: "重新获取 AI 精讲后可继续检查本句。",
            hierarchyRebuild: chunkLayers.map(\.text),
            syntacticVariation: nil,
            requestID: requestID,
            provider: resolvedMeta.provider,
            model: resolvedMeta.model,
            retryCount: resolvedMeta.retryCount,
            usedCache: resolvedMeta.usedCache,
            usedFallback: true,
            circuitState: resolvedMeta.circuitState,
            errorCode: structuredError?.errorCode,
            fallbackAvailable: true,
            fallbackMessage: fallbackMessage
        )
    }

    private static func roughCoreSkeleton(for sentence: String) -> ProfessorCoreSkeleton? {
        let normalized = sentence
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let tokens = normalized.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return nil }

        let verbs = Set([
            "is", "are", "was", "were", "be", "been", "being",
            "do", "does", "did", "have", "has", "had",
            "make", "makes", "made", "take", "takes", "took",
            "show", "shows", "showed", "suggest", "suggests", "suggested",
            "argue", "argues", "argued", "mean", "means", "meant",
            "become", "becomes", "became", "remain", "remains", "remained",
            "help", "helps", "helped", "allow", "allows", "allowed",
            "lead", "leads", "led", "give", "gives", "gave"
        ])

        let verbIndex = tokens.firstIndex(where: { verbs.contains($0.lowercased()) }) ?? min(1, tokens.count - 1)
        let subject = tokens.prefix(verbIndex).joined(separator: " ")
        let predicate = tokens[verbIndex]
        let complement = tokens.dropFirst(verbIndex + 1).prefix(10).joined(separator: " ")

        return ProfessorCoreSkeleton(
            subject: subject.isEmpty ? String(tokens.first ?? "") : subject,
            predicate: predicate,
            complementOrObject: complement
        )
    }

    private static func roughChunkLayers(for sentence: String) -> [ProfessorChunkLayer] {
        let pieces = sentence
            .split(whereSeparator: { ",;:".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if pieces.isEmpty {
            return [
                ProfessorChunkLayer(
                    text: shortened(sentence),
                    role: "核心信息",
                    attachesTo: "主句主干",
                    gloss: "先保留一句的主干位置，等待 AI 精讲补齐。"
                )
            ]
        }

        return pieces.enumerated().map { index, piece in
            let role: String
            switch index {
            case 0 where pieces.count > 1:
                role = "前置框架"
            case pieces.count - 1 where pieces.count > 1:
                role = "后置修饰"
            default:
                role = "核心信息"
            }

            return ProfessorChunkLayer(
                text: piece,
                role: role,
                attachesTo: role == "核心信息" ? "主句主干" : "核心信息",
                gloss: "本地骨架先把语块拆开，方便你先看清信息层次。"
            )
        }
    }

    private static func roughGrammarFocus(for sentence: String) -> [ProfessorGrammarFocus] {
        var items: [ProfessorGrammarFocus] = [
            ProfessorGrammarFocus(
                phenomenon: "句子主干",
                function: "先锁定主语、谓语和核心补足，不要一上来就被长修饰带走。",
                whyItMatters: "阅读题常把修饰层和主干判断混在一起，先抓主干才能稳住句意。",
                titleZh: "先抓主干",
                explanationZh: "先锁定主语、谓语和核心补足，不要一上来就被长修饰带走。",
                whyItMattersZh: "阅读题常把修饰层和主干判断混在一起，先抓主干才能稳住句意。",
                exampleEn: shortened(sentence)
            )
        ]

        let lowercased = sentence.lowercased()
        if lowercased.contains("that ") || lowercased.contains("which ") || lowercased.contains("who ") {
            items.append(
                ProfessorGrammarFocus(
                    phenomenon: "从句挂接",
                    function: "句中可能有定语从句或内容从句，本地骨架先提醒你看清它挂在谁身上。",
                    whyItMatters: "如果从句挂错对象，整句重心就会读偏。",
                    titleZh: "从句挂接",
                    explanationZh: "句中可能有定语从句或内容从句，本地骨架先提醒你看清它挂在谁身上。",
                    whyItMattersZh: "如果从句挂错对象，整句重心就会读偏。",
                    exampleEn: shortened(sentence)
                )
            )
        }

        return items
    }

    private static func roughMisreadingTraps(for sentence: String) -> [String] {
        var traps = ["先看主干，再看修饰层，不要把长定语或插入语误当主句。"]
        let lowercased = sentence.lowercased()
        if lowercased.contains("but") || lowercased.contains("however") || lowercased.contains("although") {
            traps.append("注意转折或让步后的真正落点，不要把铺垫部分误当作者结论。")
        }
        if lowercased.contains("not") || lowercased.contains("never") || lowercased.contains("no ") {
            traps.append("注意否定范围，不要把否定只挂在局部词上。")
        }
        return traps
    }

    private static func roughExamRoutes(for sentence: String) -> [String] {
        [
            "题目可能会把这句改写成更短的判断句，考你是否抓到主干。",
            "题目可能会把修饰层和主结论拆开，考你是否看清它们的挂接关系。"
        ]
    }

    private static func shortened(_ sentence: String) -> String {
        let normalized = sentence
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.count > 140 ? String(normalized.prefix(140)) : normalized
    }
}
