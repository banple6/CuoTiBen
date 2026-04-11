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

    let originalSentence: String
    let naturalChineseMeaning: String
    let sentenceCore: String
    let chunkBreakdown: [String]
    let grammarPoints: [GrammarPoint]
    let vocabularyInContext: [KeyTerm]
    let misreadPoints: [String]
    let examRewritePoints: [String]
    let simplifiedEnglish: String
    let miniExercise: String?
    let hierarchyRebuild: [String]
    let syntacticVariation: String?

    init(
        originalSentence: String,
        naturalChineseMeaning: String,
        sentenceCore: String,
        chunkBreakdown: [String],
        grammarPoints: [GrammarPoint],
        vocabularyInContext: [KeyTerm],
        misreadPoints: [String],
        examRewritePoints: [String],
        simplifiedEnglish: String,
        miniExercise: String?,
        hierarchyRebuild: [String],
        syntacticVariation: String?
    ) {
        self.originalSentence = originalSentence
        self.naturalChineseMeaning = naturalChineseMeaning
        self.sentenceCore = sentenceCore
        self.chunkBreakdown = chunkBreakdown
        self.grammarPoints = grammarPoints
        self.vocabularyInContext = vocabularyInContext
        self.misreadPoints = misreadPoints
        self.examRewritePoints = examRewritePoints
        self.simplifiedEnglish = simplifiedEnglish
        self.miniExercise = miniExercise
        self.hierarchyRebuild = hierarchyRebuild
        self.syntacticVariation = syntacticVariation
    }

    init(sourceSentence: String, dictionary: [String: Any]) {
        let rewriteExample = Self.firstString(in: dictionary, keys: ["simplified_english", "rewrite_example"])
        let explicitExamRewritePoints = Self.stringArray(in: dictionary, keys: ["exam_rewrite_points"])

        self.init(
            originalSentence: Self.firstString(in: dictionary, keys: ["original_sentence", "originalSentence", "sentence"]) ?? sourceSentence,
            naturalChineseMeaning: Self.firstString(in: dictionary, keys: ["natural_chinese_meaning", "translation", "naturalChineseMeaning"]) ?? "",
            sentenceCore: Self.firstString(in: dictionary, keys: ["sentence_core", "main_structure", "sentenceCore"]) ?? "",
            chunkBreakdown: Self.stringArray(in: dictionary, keys: ["chunk_breakdown", "chunks"]),
            grammarPoints: Self.grammarPoints(in: dictionary),
            vocabularyInContext: Self.vocabularyItems(in: dictionary),
            misreadPoints: Self.stringArray(in: dictionary, keys: ["misread_points", "common_misread_points"]),
            examRewritePoints: explicitExamRewritePoints.isEmpty
                ? (rewriteExample.map { ["可把这句改写版当作命题同义替换的线索：\($0)"] } ?? [])
                : explicitExamRewritePoints,
            simplifiedEnglish: rewriteExample ?? "",
            miniExercise: Self.firstString(in: dictionary, keys: ["mini_exercise"]),
            hierarchyRebuild: Self.stringArray(in: dictionary, keys: ["hierarchy_rebuild"]),
            syntacticVariation: Self.firstString(in: dictionary, keys: ["syntactic_variation", "rewrite_example"])
        )
    }

    var translation: String { naturalChineseMeaning }
    var mainStructure: String { sentenceCore }
    var keyTerms: [KeyTerm] { vocabularyInContext }
    var rewriteExample: String { simplifiedEnglish }

    var localFallbackAnalysis: ProfessorSentenceAnalysis {
        ProfessorSentenceAnalysis(
            originalSentence: originalSentence,
            naturalChineseMeaning: naturalChineseMeaning,
            sentenceCore: sentenceCore,
            chunkBreakdown: chunkBreakdown,
            grammarPoints: grammarPoints,
            vocabularyInContext: vocabularyInContext,
            misreadPoints: misreadPoints,
            examRewritePoints: examRewritePoints,
            simplifiedEnglish: simplifiedEnglish,
            miniExercise: miniExercise,
            hierarchyRebuild: hierarchyRebuild,
            syntacticVariation: syntacticVariation
        )
    }

    static func looksLikePayload(_ dictionary: [String: Any]) -> Bool {
        [
            "original_sentence",
            "natural_chinese_meaning",
            "sentence_core",
            "translation",
            "main_structure",
            "rewrite_example"
        ].contains { dictionary[$0] != nil }
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
        guard let rawItems = (dictionary["vocabulary_in_context"] ?? dictionary["key_terms"]) as? [Any] else {
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

    private static func decodeResponseEnvelope(
        from data: Data,
        sourceSentence: String
    ) throws -> ExplainSentenceResponseEnvelope {
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
        let baseURLString = normalizeBaseURL(overrideBaseURL ?? storedBaseURL)
        guard !baseURLString.isEmpty else {
            throw AIExplainSentenceServiceError.missingBaseURL
        }

        guard let endpointURL = URL(string: "\(baseURLString)/ai/explain-sentence") else {
            throw AIExplainSentenceServiceError.invalidBaseURL
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

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ExplainSentenceRequest(
                title: validatedExplainContext.title,
                sentence: validatedExplainContext.sentence,
                context: validatedExplainContext.context,
                paragraphTheme: validatedExplainContext.paragraphTheme,
                paragraphRole: validatedExplainContext.paragraphRole,
                questionPrompt: validatedExplainContext.questionPrompt
            )
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIExplainSentenceServiceError.invalidServerResponse
            }

            let decoded = try decodeResponseEnvelope(
                from: data,
                sourceSentence: validatedExplainContext.sentence
            )

            if httpResponse.statusCode == 200, decoded.success, let result = decoded.data {
                return result
            }

            if let message = decoded.error, !message.isEmpty {
                throw AIExplainSentenceServiceError.requestFailed(message)
            }

            throw AIExplainSentenceServiceError.invalidServerResponse
        } catch let error as AIExplainSentenceServiceError {
            throw error
        } catch let error as URLError {
            throw AIExplainSentenceServiceError.transport(error.localizedDescription)
        } catch {
            print("[AIExplainSentenceService] decode failed: \(error)")
            throw AIExplainSentenceServiceError.invalidServerResponse
        }
    }
}
