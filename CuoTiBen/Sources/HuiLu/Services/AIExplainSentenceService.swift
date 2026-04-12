import Foundation

struct ExplainSentenceContext: Equatable {
    let title: String
    let sentence: String
    let context: String
    let paragraphTheme: String
    let paragraphRole: String
    let questionPrompt: String
}

struct AIExplainSentenceResult: Equatable {
    typealias GrammarPoint = ProfessorGrammarPoint
    typealias KeyTerm = ProfessorVocabularyItem
    typealias CoreSkeleton = ProfessorCoreSkeleton
    typealias ChunkLayer = ProfessorChunkLayer
    typealias GrammarFocus = ProfessorGrammarFocus

    let originalSentence: String
    let evidenceType: String?
    let sentenceFunction: String
    let coreSkeleton: CoreSkeleton?
    let chunkLayers: [ChunkLayer]
    let grammarFocus: [GrammarFocus]
    let faithfulTranslation: String
    let teachingInterpretation: String
    let naturalChineseMeaning: String
    let sentenceCore: String
    let chunkBreakdown: [String]
    let grammarPoints: [GrammarPoint]
    let vocabularyInContext: [KeyTerm]
    let misreadPoints: [String]
    let examRewritePoints: [String]
    let misreadingTraps: [String]
    let examParaphraseRoutes: [String]
    let simplifiedEnglish: String
    let simplerRewrite: String
    let miniExercise: String?
    let miniCheck: String?
    let hierarchyRebuild: [String]
    let syntacticVariation: String?

    init(
        originalSentence: String,
        evidenceType: String?,
        sentenceFunction: String,
        coreSkeleton: CoreSkeleton?,
        chunkLayers: [ChunkLayer],
        grammarFocus: [GrammarFocus],
        faithfulTranslation: String,
        teachingInterpretation: String,
        naturalChineseMeaning: String,
        sentenceCore: String,
        chunkBreakdown: [String],
        grammarPoints: [GrammarPoint],
        vocabularyInContext: [KeyTerm],
        misreadPoints: [String],
        examRewritePoints: [String],
        misreadingTraps: [String],
        examParaphraseRoutes: [String],
        simplifiedEnglish: String,
        simplerRewrite: String,
        miniExercise: String?,
        miniCheck: String?,
        hierarchyRebuild: [String],
        syntacticVariation: String?
    ) {
        self.originalSentence = originalSentence
        self.evidenceType = evidenceType
        self.sentenceFunction = sentenceFunction
        self.coreSkeleton = coreSkeleton
        self.chunkLayers = chunkLayers
        self.grammarFocus = grammarFocus
        self.faithfulTranslation = faithfulTranslation
        self.teachingInterpretation = teachingInterpretation
        self.naturalChineseMeaning = naturalChineseMeaning
        self.sentenceCore = sentenceCore
        self.chunkBreakdown = chunkBreakdown
        self.grammarPoints = grammarPoints
        self.vocabularyInContext = vocabularyInContext
        self.misreadPoints = misreadPoints
        self.examRewritePoints = examRewritePoints
        self.misreadingTraps = misreadingTraps
        self.examParaphraseRoutes = examParaphraseRoutes
        self.simplifiedEnglish = simplifiedEnglish
        self.simplerRewrite = simplerRewrite
        self.miniExercise = miniExercise
        self.miniCheck = miniCheck
        self.hierarchyRebuild = hierarchyRebuild
        self.syntacticVariation = syntacticVariation
    }

    init(sourceSentence: String, dictionary: [String: Any]) {
        let hasProfessorPayload = Self.hasProfessorFieldCoverage(dictionary)
        let rewriteExample = Self.firstString(
            in: dictionary,
            keys: hasProfessorPayload
                ? ["simpler_rewrite", "simplified_english"]
                : ["simpler_rewrite", "simplified_english", "rewrite_example"]
        )
        let explicitExamRewritePoints = Self.stringArray(
            in: dictionary,
            keys: ["exam_rewrite_points", "exam_paraphrase_points"]
        )
        let evidenceType = Self.firstString(in: dictionary, keys: ["evidence_type", "sentence_role"])
        let sentenceCore = Self.firstString(
            in: dictionary,
            keys: hasProfessorPayload ? ["sentence_core", "sentenceCore"] : ["sentence_core", "main_structure", "sentenceCore"]
        ) ?? ""
        let chunkBreakdown = Self.stringArray(in: dictionary, keys: ["chunk_breakdown", "chunks"])
        let grammarPoints = Self.grammarPoints(in: dictionary)
        let vocabularyInContext = Self.vocabularyItems(in: dictionary)
        let misreadingTraps = Self.stringArray(in: dictionary, keys: ["misreading_traps", "misread_points", "common_misread_points", "common_misreadings"])
        let examParaphraseRoutes = Self.stringArray(in: dictionary, keys: ["exam_paraphrase_routes", "exam_rewrite_points", "exam_paraphrase_points"])
        let sentenceFunction = Self.firstString(in: dictionary, keys: ["sentence_function"])
            ?? professorSentenceRolePresentation(for: evidenceType).map { "\($0.label)：\($0.description)" }
            ?? ""
        let faithfulTranslation = Self.firstString(
            in: dictionary,
            keys: hasProfessorPayload
                ? ["faithful_translation", "faithfulTranslation", "translation"]
                : ["faithful_translation", "translation", "natural_chinese_meaning", "naturalChineseMeaning"]
        ) ?? ""
        let teachingInterpretation = Self.firstString(
            in: dictionary,
            keys: hasProfessorPayload
                ? ["teaching_interpretation", "teachingInterpretation", "natural_chinese_meaning", "naturalChineseMeaning"]
                : ["teaching_interpretation", "natural_chinese_meaning", "naturalChineseMeaning", "translation"]
        ) ?? ""
        let naturalChineseMeaning = Self.firstString(
            in: dictionary,
            keys: hasProfessorPayload
                ? ["teaching_interpretation", "natural_chinese_meaning", "naturalChineseMeaning", "faithful_translation"]
                : ["teaching_interpretation", "natural_chinese_meaning", "translation", "naturalChineseMeaning"]
        ) ?? Self.nonEmpty(teachingInterpretation) ?? faithfulTranslation

        self.init(
            originalSentence: Self.firstString(in: dictionary, keys: ["original_sentence", "originalSentence", "sentence"]) ?? sourceSentence,
            evidenceType: evidenceType,
            sentenceFunction: sentenceFunction,
            coreSkeleton: Self.coreSkeleton(in: dictionary, fallbackSentenceCore: sentenceCore),
            chunkLayers: Self.chunkLayers(in: dictionary, fallbackChunks: chunkBreakdown),
            grammarFocus: Self.grammarFocus(in: dictionary, fallbackGrammarPoints: grammarPoints),
            faithfulTranslation: Self.nonEmpty(faithfulTranslation) ?? naturalChineseMeaning,
            teachingInterpretation: Self.nonEmpty(teachingInterpretation) ?? naturalChineseMeaning,
            naturalChineseMeaning: naturalChineseMeaning,
            sentenceCore: sentenceCore,
            chunkBreakdown: chunkBreakdown,
            grammarPoints: grammarPoints,
            vocabularyInContext: vocabularyInContext,
            misreadPoints: misreadingTraps,
            examRewritePoints: examParaphraseRoutes.isEmpty ? explicitExamRewritePoints : examParaphraseRoutes,
            misreadingTraps: misreadingTraps,
            examParaphraseRoutes: examParaphraseRoutes.isEmpty ? explicitExamRewritePoints : examParaphraseRoutes,
            simplifiedEnglish: rewriteExample ?? "",
            simplerRewrite: rewriteExample ?? "",
            miniExercise: Self.firstString(in: dictionary, keys: ["mini_exercise"]),
            miniCheck: Self.firstString(in: dictionary, keys: ["mini_check", "mini_exercise"]),
            hierarchyRebuild: Self.stringArray(in: dictionary, keys: ["hierarchy_rebuild"]),
            syntacticVariation: Self.firstString(in: dictionary, keys: ["syntactic_variation", "rewrite_example"])
        )
    }

    var translation: String { Self.nonEmpty(faithfulTranslation) ?? naturalChineseMeaning }
    var mainStructure: String { sentenceCore }
    var keyTerms: [KeyTerm] { vocabularyInContext }
    var rewriteExample: String { simplifiedEnglish }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var localFallbackAnalysis: ProfessorSentenceAnalysis {
        ProfessorSentenceAnalysis(
            originalSentence: originalSentence,
            sentenceFunction: sentenceFunction,
            coreSkeleton: coreSkeleton,
            chunkLayers: chunkLayers,
            grammarFocus: grammarFocus,
            faithfulTranslation: faithfulTranslation,
            teachingInterpretation: teachingInterpretation,
            naturalChineseMeaning: naturalChineseMeaning,
            sentenceCore: sentenceCore,
            chunkBreakdown: chunkBreakdown,
            grammarPoints: grammarPoints,
            vocabularyInContext: vocabularyInContext,
            misreadPoints: misreadPoints,
            examRewritePoints: examRewritePoints,
            misreadingTraps: misreadingTraps,
            examParaphraseRoutes: examParaphraseRoutes,
            simplifiedEnglish: simplifiedEnglish,
            simplerRewrite: simplerRewrite,
            miniExercise: miniExercise,
            miniCheck: miniCheck,
            hierarchyRebuild: hierarchyRebuild,
            syntacticVariation: syntacticVariation,
            evidenceType: evidenceType
        )
    }

    var renderedSentenceFunction: String { localFallbackAnalysis.renderedSentenceFunction }
    var renderedSentenceCore: String { localFallbackAnalysis.renderedSentenceCore }
    var renderedFaithfulTranslation: String { localFallbackAnalysis.renderedFaithfulTranslation }
    var renderedTeachingInterpretation: String { localFallbackAnalysis.renderedTeachingInterpretation }
    var renderedChunkLayers: [String] { localFallbackAnalysis.renderedChunkLayers }
    var renderedGrammarFocus: [String] { localFallbackAnalysis.renderedGrammarFocus }
    var renderedMisreadingTraps: [String] { localFallbackAnalysis.renderedMisreadingTraps }
    var renderedExamParaphraseRoutes: [String] { localFallbackAnalysis.renderedExamParaphraseRoutes }
    var renderedSimplerRewrite: String { localFallbackAnalysis.renderedSimplerRewrite }
    var renderedMiniCheck: String? { localFallbackAnalysis.renderedMiniCheck }

    static func looksLikePayload(_ dictionary: [String: Any]) -> Bool {
        let professorKeys = [
            "original_sentence",
            "evidence_type",
            "sentence_function",
            "core_skeleton",
            "chunk_layers",
            "grammar_focus",
            "faithful_translation",
            "teaching_interpretation",
            "natural_chinese_meaning",
            "vocabulary_in_context",
            "contextual_vocabulary",
            "misreading_traps",
            "common_misreadings",
            "exam_paraphrase_routes",
            "exam_paraphrase_points",
            "simpler_rewrite",
            "mini_check",
            "sentence_core",
            "chunk_breakdown",
            "grammar_points"
        ]
        let legacyKeys = ["translation", "main_structure", "rewrite_example"]

        let professorCount = professorKeys.reduce(into: 0) { partialResult, key in
            if dictionary[key] != nil {
                partialResult += 1
            }
        }

        if professorCount >= 2 {
            return true
        }

        return legacyKeys.contains { dictionary[$0] != nil }
    }

    private static func hasProfessorFieldCoverage(_ dictionary: [String: Any]) -> Bool {
        let keys = [
            "evidence_type",
            "sentence_function",
            "core_skeleton",
            "chunk_layers",
            "grammar_focus",
            "faithful_translation",
            "teaching_interpretation",
            "natural_chinese_meaning",
            "contextual_vocabulary",
            "misreading_traps",
            "common_misreadings",
            "exam_paraphrase_routes",
            "exam_paraphrase_points",
            "simpler_rewrite",
            "mini_check",
            "sentence_core",
            "chunk_breakdown",
            "grammar_points"
        ]

        let score = keys.reduce(into: 0) { partialResult, key in
            if dictionary[key] != nil {
                partialResult += 1
            }
        }

        return score >= 2
    }

    private static func firstString(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let string = normalizedString(from: value) {
                return string
            }
        }
        return nil
    }

    private static func stringArray(in dictionary: [String: Any], keys: [String]) -> [String] {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let array = value as? [Any] {
                let normalized = array.compactMap { normalizedString(from: $0) }
                if !normalized.isEmpty {
                    return normalized
                }
            }
            if let string = normalizedString(from: value) {
                return [string]
            }
        }
        return []
    }

    private static func grammarPoints(in dictionary: [String: Any]) -> [GrammarPoint] {
        guard let rawItems = dictionary["grammar_points"] as? [Any] else {
            return []
        }

        return rawItems.compactMap { item in
            if let payload = item as? [String: Any] {
                let name = firstString(in: payload, keys: ["name", "title"]) ?? ""
                let explanation = firstString(in: payload, keys: ["explanation", "meaning", "detail"]) ?? ""
                guard !name.isEmpty || !explanation.isEmpty else { return nil }
                return GrammarPoint(name: name, explanation: explanation)
            }

            if let string = normalizedString(from: item) {
                return GrammarPoint(name: string, explanation: "")
            }

            return nil
        }
    }

    private static func vocabularyItems(in dictionary: [String: Any]) -> [KeyTerm] {
        guard let rawItems = (
            dictionary["vocabulary_in_context"]
            ?? dictionary["contextual_vocabulary"]
            ?? dictionary["key_terms"]
        ) as? [Any] else {
            return []
        }

        return rawItems.compactMap { item in
            if let payload = item as? [String: Any] {
                let term = firstString(in: payload, keys: ["term", "word"]) ?? ""
                let meaning = firstString(in: payload, keys: ["meaning", "explanation", "gloss"]) ?? ""
                guard !term.isEmpty || !meaning.isEmpty else { return nil }
                return KeyTerm(term: term, meaning: meaning)
            }

            if let string = normalizedString(from: item) {
                return KeyTerm(term: string, meaning: "")
            }

            return nil
        }
    }

    private static func coreSkeleton(in dictionary: [String: Any], fallbackSentenceCore: String) -> CoreSkeleton? {
        if let payload = dictionary["core_skeleton"] as? [String: Any] {
            let subject = firstString(in: payload, keys: ["subject"]) ?? ""
            let predicate = firstString(in: payload, keys: ["predicate"]) ?? ""
            let complement = firstString(in: payload, keys: ["complement_or_object", "complementOrObject", "object"]) ?? ""
            if !subject.isEmpty || !predicate.isEmpty || !complement.isEmpty {
                return CoreSkeleton(subject: subject, predicate: predicate, complementOrObject: complement)
            }
        }

        let core = fallbackSentenceCore.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !core.isEmpty else { return nil }

        let segments = core.split(separator: "｜").map(String.init)
        var subject = ""
        var predicate = ""
        var complement = ""

        for segment in segments {
            if segment.contains("主语：") {
                subject = segment.replacingOccurrences(of: "主语：", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if segment.contains("谓语：") {
                predicate = segment.replacingOccurrences(of: "谓语：", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if segment.contains("核心补足：") {
                complement = segment.replacingOccurrences(of: "核心补足：", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if !subject.isEmpty || !predicate.isEmpty || !complement.isEmpty {
            return CoreSkeleton(subject: subject, predicate: predicate, complementOrObject: complement)
        }
        return nil
    }

    private static func chunkLayers(in dictionary: [String: Any], fallbackChunks: [String]) -> [ChunkLayer] {
        if let rawItems = dictionary["chunk_layers"] as? [Any] {
            let items = rawItems.compactMap { item -> ChunkLayer? in
                guard let payload = item as? [String: Any] else { return nil }
                let text = firstString(in: payload, keys: ["text"]) ?? ""
                let role = firstString(in: payload, keys: ["role"]) ?? ""
                let attachesTo = firstString(in: payload, keys: ["attaches_to", "attachesTo"]) ?? ""
                let gloss = firstString(in: payload, keys: ["gloss"]) ?? ""
                guard !text.isEmpty || !role.isEmpty || !attachesTo.isEmpty || !gloss.isEmpty else { return nil }
                return ChunkLayer(text: text, role: role, attachesTo: attachesTo, gloss: gloss)
            }
            if !items.isEmpty {
                return items
            }
        }

        return fallbackChunks.compactMap { item in
            let parts = item.split(separator: "：", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let role = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let text = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let attachesTo = role == "核心信息" ? "主句主干" : "核心信息"
                return ChunkLayer(text: text, role: role, attachesTo: attachesTo, gloss: "")
            }
            let text = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return ChunkLayer(text: text, role: "语块", attachesTo: "核心信息", gloss: "")
        }
    }

    private static func grammarFocus(in dictionary: [String: Any], fallbackGrammarPoints: [GrammarPoint]) -> [GrammarFocus] {
        if let rawItems = dictionary["grammar_focus"] as? [Any] {
            let items = rawItems.compactMap { item -> GrammarFocus? in
                guard let payload = item as? [String: Any] else { return nil }
                let phenomenon = firstString(in: payload, keys: ["phenomenon"]) ?? ""
                let function = firstString(in: payload, keys: ["function"]) ?? ""
                let why = firstString(in: payload, keys: ["why_it_matters", "whyItMatters"]) ?? ""
                guard !phenomenon.isEmpty || !function.isEmpty || !why.isEmpty else { return nil }
                return GrammarFocus(phenomenon: phenomenon, function: function, whyItMatters: why)
            }
            if !items.isEmpty {
                return items
            }
        }

        return fallbackGrammarPoints.map {
            GrammarFocus(
                phenomenon: $0.name,
                function: $0.explanation,
                whyItMatters: "这个结构如果挂错范围或读错修饰对象，整句主干就会被带偏。"
            )
        }
    }

    private static func normalizedString(from value: Any) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }
}

private struct ExplainSentenceRequest: Encodable {
    let title: String
    let sentence: String
    let context: String
    let paragraphTheme: String
    let paragraphRole: String
    let questionPrompt: String

    private enum CodingKeys: String, CodingKey {
        case title, sentence, context
        case paragraphTheme = "paragraph_theme"
        case paragraphRole = "paragraph_role"
        case questionPrompt = "question_prompt"
    }
}

private struct ExplainSentenceResponseEnvelope {
    let success: Bool
    let data: AIExplainSentenceResult?
    let error: String?
}

enum AIExplainSentenceServiceError: LocalizedError {
    case missingBaseURL
    case invalidBaseURL
    case invalidServerResponse
    case requestFailed(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "AI 服务地址未配置。"
        case .invalidBaseURL:
            return "AI 服务地址格式不正确。"
        case .invalidServerResponse:
            return "服务器返回的数据格式不正确。"
        case .requestFailed(let message):
            return message
        case .transport(let message):
            return message
        }
    }
}

enum AIExplainSentenceService {
    private static let baseURLStorageKey = "huiLu.aiBackendBaseURL"
    private static let defaultBaseURL = "http://47.94.227.58"
    private static let preferredAIPort = 3000

    static var storedBaseURL: String {
        let stored = UserDefaults.standard.string(forKey: baseURLStorageKey) ?? ""
        let normalizedStored = normalizeBaseURL(stored)
        if !normalizedStored.isEmpty {
            return normalizedStored
        }
        return defaultBaseURL
    }

    static func saveBaseURL(_ value: String) {
        UserDefaults.standard.set(normalizeBaseURL(value), forKey: baseURLStorageKey)
    }

    static func normalizeBaseURL(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func endpointCandidates(
        path: String,
        overrideBaseURL: String? = nil,
        preferredPort: Int? = preferredAIPort
    ) -> [URL] {
        let normalizedBaseURL = normalizeBaseURL(overrideBaseURL ?? storedBaseURL)
        guard !normalizedBaseURL.isEmpty else { return [] }

        return candidateBaseURLs(
            normalizedBaseURL: normalizedBaseURL,
            preferredPort: preferredPort
        ).compactMap { baseURLString in
            guard let baseURL = URL(string: baseURLString) else { return nil }
            return baseURL.appendingPathComponent(path)
        }
    }

    static func shouldRetryEndpoint(statusCode: Int) -> Bool {
        switch statusCode {
        case 404, 405, 408, 421, 425, 429, 500, 502, 503, 504:
            return true
        default:
            return false
        }
    }

    static func shouldRetrySameEndpoint(statusCode: Int) -> Bool {
        switch statusCode {
        case 408, 421, 425, 429, 500, 502, 503, 504:
            return true
        default:
            return false
        }
    }

    static func shouldRetryEndpoint(for error: URLError) -> Bool {
        switch error.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    static func shouldRetrySameEndpoint(for error: URLError) -> Bool {
        switch error.code {
        case .timedOut,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    private static func candidateBaseURLs(
        normalizedBaseURL: String,
        preferredPort: Int?
    ) -> [String] {
        guard let components = URLComponents(string: normalizedBaseURL),
              components.scheme != nil,
              components.host != nil
        else {
            return [normalizedBaseURL]
        }

        var results: [String] = []

        func append(_ candidate: URLComponents) {
            guard let url = candidate.url else { return }
            let normalized = normalizeBaseURL(url.absoluteString)
            guard !normalized.isEmpty, !results.contains(normalized) else { return }
            results.append(normalized)
        }

        append(components)

        if let preferredPort, components.port != preferredPort {
            var preferred = components
            preferred.port = preferredPort
            append(preferred)
        }

        return results
    }

    static func retryDelayNanoseconds(for attemptIndex: Int) -> UInt64 {
        let clamped = min(max(attemptIndex, 0), 2)
        return UInt64(350_000_000 * (clamped + 1))
    }

    private static func decodeResponseEnvelope(
        from data: Data,
        sourceSentence: String
    ) throws -> ExplainSentenceResponseEnvelope {
        let isWhitespaceOnly = data.allSatisfy { byte in
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        }

        guard !data.isEmpty, !isWhitespaceOnly else {
            throw AIExplainSentenceServiceError.invalidServerResponse
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw AIExplainSentenceServiceError.invalidServerResponse
        }

        let success = dictionary["success"] as? Bool ?? AIExplainSentenceResult.looksLikePayload(dictionary)
        let error = (dictionary["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (dictionary["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let payload = dictionary["data"] as? [String: Any], AIExplainSentenceResult.looksLikePayload(payload) {
            return ExplainSentenceResponseEnvelope(
                success: success,
                data: AIExplainSentenceResult(sourceSentence: sourceSentence, dictionary: payload),
                error: error
            )
        }

        if AIExplainSentenceResult.looksLikePayload(dictionary) {
            return ExplainSentenceResponseEnvelope(
                success: success,
                data: AIExplainSentenceResult(sourceSentence: sourceSentence, dictionary: dictionary),
                error: error
            )
        }

        return ExplainSentenceResponseEnvelope(success: success, data: nil, error: error)
    }

    static func fetchExplanation(
        for context: ExplainSentenceContext,
        baseURL overrideBaseURL: String? = nil
    ) async throws -> AIExplainSentenceResult {
        let endpointURLs = endpointCandidates(
            path: "ai/explain-sentence",
            overrideBaseURL: overrideBaseURL
        )
        guard !endpointURLs.isEmpty else {
            throw AIExplainSentenceServiceError.missingBaseURL
        }

        // 发送前检测句子文本是否反转，如有则自动修复
        let (validatedSentence, sentenceRepaired) = TextPipelineValidator.validateAndRepairIfReversed(context.sentence)
        let (validatedContext, _) = TextPipelineValidator.validateAndRepairIfReversed(context.context)

        if sentenceRepaired {
            TextPipelineDiagnostics.log(
                "句子分析",
                "发送前检测到反转句子，已修复: \"\(String(context.sentence.prefix(40)))…\"",
                severity: .repaired
            )
        }

        let validatedExplainContext = ExplainSentenceContext(
            title: context.title,
            sentence: validatedSentence,
            context: validatedContext,
            paragraphTheme: context.paragraphTheme,
            paragraphRole: context.paragraphRole,
            questionPrompt: context.questionPrompt
        )

        let requestData = try JSONEncoder().encode(
            ExplainSentenceRequest(
                title: validatedExplainContext.title,
                sentence: validatedExplainContext.sentence,
                context: validatedExplainContext.context,
                paragraphTheme: validatedExplainContext.paragraphTheme,
                paragraphRole: validatedExplainContext.paragraphRole,
                questionPrompt: validatedExplainContext.questionPrompt
            )
        )

        var lastError: Error?

        for (index, endpointURL) in endpointURLs.enumerated() {
            for attempt in 0..<2 {
                var request = URLRequest(url: endpointURL)
                request.httpMethod = "POST"
                request.timeoutInterval = 25
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = requestData

                do {
                    try Task.checkCancellation()
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIExplainSentenceServiceError.invalidServerResponse
                    }

                    if shouldRetrySameEndpoint(statusCode: httpResponse.statusCode), attempt == 0 {
                        TextPipelineDiagnostics.log(
                            "句子分析",
                            "AI 端点瞬时失败，准备重试: \(endpointURL.absoluteString) status=\(httpResponse.statusCode)",
                            severity: .warning
                        )
                            try await Task.sleep(nanoseconds: retryDelayNanoseconds(for: attempt))
                            continue
                        }

                    guard (200 ..< 300).contains(httpResponse.statusCode) else {
                        let bodySnippet = String(data: data.prefix(500), encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                        if shouldRetryEndpoint(statusCode: httpResponse.statusCode), index < endpointURLs.count - 1 {
                            let nextURL = endpointURLs[index + 1].absoluteString
                            TextPipelineDiagnostics.log(
                                "句子分析",
                                "AI 端点不可用，切换候选地址: \(endpointURL.absoluteString) -> \(nextURL) status=\(httpResponse.statusCode)",
                                severity: .warning
                            )
                            lastError = AIExplainSentenceServiceError.requestFailed(
                                bodySnippet.isEmpty ? "HTTP \(httpResponse.statusCode)" : "HTTP \(httpResponse.statusCode): \(bodySnippet)"
                            )
                            break
                        }

                        throw AIExplainSentenceServiceError.requestFailed(
                            bodySnippet.isEmpty ? "HTTP \(httpResponse.statusCode)" : "HTTP \(httpResponse.statusCode): \(bodySnippet)"
                        )
                    }

                    let decoded = try decodeResponseEnvelope(
                        from: data,
                        sourceSentence: validatedExplainContext.sentence
                    )

                    if decoded.success, let result = decoded.data {
                        return result
                    }

                    if let message = decoded.error, !message.isEmpty {
                        throw AIExplainSentenceServiceError.requestFailed(message)
                    }

                    throw AIExplainSentenceServiceError.invalidServerResponse
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as URLError {
                    if error.code == .cancelled || Task.isCancelled {
                        throw CancellationError()
                    }
                    if shouldRetrySameEndpoint(for: error), attempt == 0 {
                        TextPipelineDiagnostics.log(
                            "句子分析",
                            "AI 端点连接瞬断，准备重试: \(endpointURL.absoluteString) error=\(error.localizedDescription)",
                            severity: .warning
                        )
                        try await Task.sleep(nanoseconds: retryDelayNanoseconds(for: attempt))
                        continue
                    }
                    if shouldRetryEndpoint(for: error), index < endpointURLs.count - 1 {
                        let nextURL = endpointURLs[index + 1].absoluteString
                        TextPipelineDiagnostics.log(
                            "句子分析",
                            "AI 端点连接失败，切换候选地址: \(endpointURL.absoluteString) -> \(nextURL) error=\(error.localizedDescription)",
                            severity: .warning
                        )
                        lastError = AIExplainSentenceServiceError.transport(error.localizedDescription)
                        break
                    }
                    throw AIExplainSentenceServiceError.transport(error.localizedDescription)
                } catch let error as AIExplainSentenceServiceError {
                    if case .invalidServerResponse = error, index < endpointURLs.count - 1 {
                        let nextURL = endpointURLs[index + 1].absoluteString
                        TextPipelineDiagnostics.log(
                            "句子分析",
                            "AI 端点响应异常，切换候选地址: \(endpointURL.absoluteString) -> \(nextURL)",
                            severity: .warning
                        )
                        lastError = error
                        break
                    }
                    throw error
                } catch {
                    print("[AIExplainSentenceService] decode failed: \(error)")
                    if index < endpointURLs.count - 1 {
                        lastError = error
                        break
                    }
                    throw AIExplainSentenceServiceError.invalidServerResponse
                }
            }
        }

        if let error = lastError as? AIExplainSentenceServiceError {
            throw error
        }
        throw AIExplainSentenceServiceError.invalidServerResponse
    }
}
