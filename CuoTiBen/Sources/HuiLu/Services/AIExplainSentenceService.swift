import Foundation

enum AIEndpointService: String {
    case sentenceExplain
    case professorAnalysis

    var displayName: String {
        switch self {
        case .sentenceExplain:
            return "AI 句子讲解服务"
        case .professorAnalysis:
            return "AI 全文教授分析服务"
        }
    }
}

enum AIServiceAvailabilityPolicy {
    static func cooldown(for statusCode: Int) -> TimeInterval? {
        switch statusCode {
        case 503, 504:
            return 90
        case 500, 502:
            return 45
        case 429:
            return 30
        default:
            return nil
        }
    }

    static func cooldown(for error: URLError) -> TimeInterval? {
        switch error.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed:
            return 90
        case .networkConnectionLost,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed:
            return 45
        default:
            return nil
        }
    }

    static func userFacingMessage(
        for service: AIEndpointService,
        technicalReason: String?
    ) -> String {
        let normalizedReason = technicalReason?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if normalizedReason.contains("503") ||
            normalizedReason.contains("502") ||
            normalizedReason.contains("timed out") ||
            normalizedReason.contains("could not connect") ||
            normalizedReason.contains("cannot connect") {
            return "\(service.displayName)暂时不可用，请稍后重试。"
        }

        if let technicalReason,
           !technicalReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return technicalReason.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return "\(service.displayName)暂时不可用，请稍后重试。"
    }
}

actor AIServiceAvailabilityGate {
    private struct State {
        var blockedUntil: Date?
        var lastReason: String?
    }

    private var states: [AIEndpointService: State] = [:]

    func blockingMessage(for service: AIEndpointService) -> String? {
        let now = Date()
        guard let state = states[service], let blockedUntil = state.blockedUntil else {
            return nil
        }

        guard blockedUntil > now else {
            states[service] = State(blockedUntil: nil, lastReason: nil)
            return nil
        }

        return AIServiceAvailabilityPolicy.userFacingMessage(
            for: service,
            technicalReason: state.lastReason
        )
    }

    func recordSuccess(for service: AIEndpointService) {
        states[service] = State(blockedUntil: nil, lastReason: nil)
    }

    func recordFailure(
        for service: AIEndpointService,
        technicalReason: String,
        cooldown: TimeInterval?
    ) {
        guard let cooldown, cooldown > 0 else { return }
        states[service] = State(
            blockedUntil: Date().addingTimeInterval(cooldown),
            lastReason: technicalReason
        )
    }
}

let aiServiceAvailabilityGate = AIServiceAvailabilityGate()

struct ExplainSentenceContext: Equatable {
    let title: String
    let sentenceID: String?
    let anchorLabel: String?
    let sentence: String
    let context: String
    let paragraphTheme: String
    let paragraphRole: String
    let questionPrompt: String
}

struct SentenceAnalysisIdentity: Codable, Equatable, Hashable {
    let sourceSentenceID: String
    let sourceSentenceTextHash: String
    let sourceAnchorLabel: String

    init(sentenceID: String, sentenceText: String, anchorLabel: String) {
        self.sourceSentenceID = sentenceID
        self.sourceSentenceTextHash = Self.hash(sentenceText)
        self.sourceAnchorLabel = anchorLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hash(_ text: String) -> String {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return String(hash, radix: 16)
    }
}

enum AnalysisConsistencyGuard {
    static func visibleKeywordOverlap(
        sentenceText: String,
        analysis: AIExplainSentenceResult
    ) -> Double {
        let sourceTokens = normalizedTokenSet(from: sentenceText)
        guard !sourceTokens.isEmpty else { return 1 }

        var analysisTokens = normalizedTokenSet(from: analysis.originalSentence)
        analysisTokens.formUnion(normalizedTokenSet(from: analysis.renderedSentenceCore))
        analysisTokens.formUnion(normalizedTokenSet(from: analysis.chunkLayers.map(\.text).joined(separator: " ")))
        analysisTokens.formUnion(normalizedTokenSet(from: analysis.vocabularyInContext.map(\.term).joined(separator: " ")))

        guard !analysisTokens.isEmpty else { return 0 }
        let overlapCount = sourceTokens.intersection(analysisTokens).count
        return Double(overlapCount) / Double(max(sourceTokens.count, 1))
    }

    static func warnings(
        identity: SentenceAnalysisIdentity,
        sentenceText: String,
        analysis: AIExplainSentenceResult
    ) -> [String] {
        var warnings: [String] = []

        if let payloadIdentity = analysis.analysisIdentity {
            if payloadIdentity.sourceSentenceID != identity.sourceSentenceID {
                warnings.append("sourceSentenceID 不匹配")
            }
            if payloadIdentity.sourceSentenceTextHash != SentenceAnalysisIdentity(
                sentenceID: identity.sourceSentenceID,
                sentenceText: sentenceText,
                anchorLabel: identity.sourceAnchorLabel
            ).sourceSentenceTextHash {
                warnings.append("sourceSentenceTextHash 不匹配")
            }
            if payloadIdentity.sourceAnchorLabel != identity.sourceAnchorLabel.trimmingCharacters(in: .whitespacesAndNewlines) {
                warnings.append("sourceAnchorLabel 不匹配")
            }
        }

        let overlap = visibleKeywordOverlap(sentenceText: sentenceText, analysis: analysis)
        if overlap < 0.12 {
            warnings.append("可见关键词重叠过低(\(String(format: "%.2f", overlap)))")
        }

        return warnings
    }

    static func normalizedTokenSet(from text: String) -> Set<String> {
        let separators = CharacterSet.letters.inverted
        let tokens = text
            .lowercased()
            .components(separatedBy: separators)
            .filter { !$0.isEmpty && $0.count >= 2 && !stopwords.contains($0) }
        return Set(tokens)
    }

    private static let stopwords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "from", "into", "their", "there",
        "have", "been", "being", "which", "while", "about", "would", "could", "should",
        "because", "through", "after", "before", "where", "when", "they", "them", "were",
        "your", "than", "then", "such", "very", "more", "most"
    ]
}

struct AIExplainSentenceResult: Codable, Equatable {
    typealias GrammarPoint = ProfessorGrammarPoint
    typealias KeyTerm = ProfessorVocabularyItem
    typealias CoreSkeleton = ProfessorCoreSkeleton
    typealias ChunkLayer = ProfessorChunkLayer
    typealias GrammarFocus = ProfessorGrammarFocus

    let originalSentence: String
    let evidenceType: String?
    let analysisIdentity: SentenceAnalysisIdentity?
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
    let simplerRewriteTranslation: String
    let miniExercise: String?
    let miniCheck: String?
    let hierarchyRebuild: [String]
    let syntacticVariation: String?

    init(
        originalSentence: String,
        evidenceType: String?,
        analysisIdentity: SentenceAnalysisIdentity?,
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
        simplerRewriteTranslation: String,
        miniExercise: String?,
        miniCheck: String?,
        hierarchyRebuild: [String],
        syntacticVariation: String?
    ) {
        self.originalSentence = originalSentence
        self.evidenceType = evidenceType
        self.analysisIdentity = analysisIdentity
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
        self.simplerRewriteTranslation = simplerRewriteTranslation
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
                ? ["faithful_translation", "faithfulTranslation"]
                : ["faithful_translation", "faithfulTranslation"]
        ) ?? ""
        let teachingInterpretation = Self.firstString(
            in: dictionary,
            keys: hasProfessorPayload
                ? ["teaching_interpretation", "teachingInterpretation", "natural_chinese_meaning", "naturalChineseMeaning"]
                : ["teaching_interpretation", "teachingInterpretation", "natural_chinese_meaning", "naturalChineseMeaning"]
        ) ?? ""
        let naturalChineseMeaning = Self.firstString(
            in: dictionary,
            keys: ["natural_chinese_meaning", "naturalChineseMeaning"]
        ) ?? Self.nonEmpty(teachingInterpretation) ?? ""
        let simplerRewrite = rewriteExample ?? ""
        let simplerRewriteTranslation = Self.firstString(
            in: dictionary,
            keys: ["simpler_rewrite_translation", "rewrite_translation"]
        ) ?? ""
        let parsedCoreSkeleton = Self.coreSkeleton(in: dictionary, fallbackSentenceCore: sentenceCore)
        let parsedChunkLayers = Self.chunkLayers(in: dictionary, fallbackChunks: chunkBreakdown)
        let parsedGrammarFocus = Self.grammarFocus(in: dictionary, fallbackGrammarPoints: grammarPoints)
        let resolvedFaithfulTranslation = Self.localizeChineseExplanation(faithfulTranslation)
        let resolvedTeachingInterpretation = Self.resolvedTeachingInterpretation(
            candidate: teachingInterpretation,
            legacyMeaning: naturalChineseMeaning,
            faithfulTranslation: resolvedFaithfulTranslation,
            sentenceFunction: sentenceFunction,
            coreSkeleton: parsedCoreSkeleton,
            chunkLayers: parsedChunkLayers
        )

        self.init(
            originalSentence: Self.firstString(in: dictionary, keys: ["original_sentence", "originalSentence", "sentence"]) ?? sourceSentence,
            evidenceType: evidenceType,
            analysisIdentity: nil,
            sentenceFunction: sentenceFunction,
            coreSkeleton: parsedCoreSkeleton,
            chunkLayers: parsedChunkLayers,
            grammarFocus: parsedGrammarFocus,
            faithfulTranslation: Self.nonEmpty(resolvedFaithfulTranslation) ?? "",
            teachingInterpretation: resolvedTeachingInterpretation,
            naturalChineseMeaning: Self.nonEmpty(naturalChineseMeaning) ?? resolvedTeachingInterpretation,
            sentenceCore: sentenceCore,
            chunkBreakdown: chunkBreakdown,
            grammarPoints: grammarPoints,
            vocabularyInContext: vocabularyInContext,
            misreadPoints: misreadingTraps,
            examRewritePoints: examParaphraseRoutes.isEmpty ? explicitExamRewritePoints : examParaphraseRoutes,
            misreadingTraps: misreadingTraps,
            examParaphraseRoutes: examParaphraseRoutes.isEmpty ? explicitExamRewritePoints : examParaphraseRoutes,
            simplifiedEnglish: simplerRewrite,
            simplerRewrite: simplerRewrite,
            simplerRewriteTranslation: Self.resolvedRewriteTranslation(
                candidate: simplerRewriteTranslation,
                rewrite: simplerRewrite,
                faithfulTranslation: resolvedFaithfulTranslation,
                coreSkeleton: parsedCoreSkeleton,
                chunkLayers: parsedChunkLayers
            ),
            miniExercise: Self.firstString(in: dictionary, keys: ["mini_exercise"]),
            miniCheck: Self.firstString(in: dictionary, keys: ["mini_check", "mini_exercise"]),
            hierarchyRebuild: Self.stringArray(in: dictionary, keys: ["hierarchy_rebuild"]),
            syntacticVariation: Self.firstString(in: dictionary, keys: ["syntactic_variation", "rewrite_example"])
        )
    }

    var translation: String { Self.nonEmpty(faithfulTranslation) ?? "" }
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
            simplerRewriteTranslation: simplerRewriteTranslation,
            miniExercise: miniExercise,
            miniCheck: miniCheck,
            hierarchyRebuild: hierarchyRebuild,
            syntacticVariation: syntacticVariation,
            evidenceType: evidenceType
        )
    }

    func attachingIdentity(_ identity: SentenceAnalysisIdentity) -> AIExplainSentenceResult {
        AIExplainSentenceResult(
            originalSentence: originalSentence,
            evidenceType: evidenceType,
            analysisIdentity: identity,
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
            simplerRewriteTranslation: simplerRewriteTranslation,
            miniExercise: miniExercise,
            miniCheck: miniCheck,
            hierarchyRebuild: hierarchyRebuild,
            syntacticVariation: syntacticVariation
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
    var renderedSimplerRewriteTranslation: String { localFallbackAnalysis.renderedSimplerRewriteTranslation }
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
            "simpler_rewrite_translation",
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
            "simpler_rewrite_translation",
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
            let subject = sanitizeCoreSkeletonField(firstString(in: payload, keys: ["subject"]) ?? "")
            let predicate = sanitizeCoreSkeletonField(firstString(in: payload, keys: ["predicate"]) ?? "")
            let complement = sanitizeCoreSkeletonField(firstString(in: payload, keys: ["complement_or_object", "complementOrObject", "object"]) ?? "")
            let combined = [subject, predicate, complement].joined(separator: " ")

            if let compatible = parseCompatibleCoreSkeleton(from: combined) {
                return compatible
            }

            if !subject.isEmpty || !predicate.isEmpty || !complement.isEmpty {
                return CoreSkeleton(subject: subject, predicate: predicate, complementOrObject: complement)
            }
        }

        let core = sanitizeCoreSkeletonField(fallbackSentenceCore)
        guard !core.isEmpty else { return nil }

        if let compatible = parseCompatibleCoreSkeleton(from: core) {
            return compatible
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
                let titleZh = firstString(in: payload, keys: ["title_zh", "titleZh"]) ?? ""
                let explanationZh = firstString(in: payload, keys: ["explanation_zh", "explanationZh"]) ?? ""
                let whyZh = firstString(in: payload, keys: ["why_it_matters_zh", "whyItMattersZh"]) ?? ""
                let exampleEn = firstString(in: payload, keys: ["example_en", "exampleEn"]) ?? ""
                guard !phenomenon.isEmpty || !function.isEmpty || !why.isEmpty || !titleZh.isEmpty || !explanationZh.isEmpty || !whyZh.isEmpty else {
                    return nil
                }
                return localizedGrammarFocus(
                    phenomenon: phenomenon,
                    function: function,
                    whyItMatters: why,
                    titleZh: titleZh,
                    explanationZh: explanationZh,
                    whyItMattersZh: whyZh,
                    exampleEn: exampleEn
                )
            }
            if !items.isEmpty {
                return items
            }
        }

        return fallbackGrammarPoints.map {
            localizedGrammarFocus(
                phenomenon: $0.name,
                function: $0.explanation,
                whyItMatters: "这个结构如果挂错范围或读错修饰对象，整句主干就会被带偏。",
                titleZh: "",
                explanationZh: "",
                whyItMattersZh: "",
                exampleEn: ""
            )
        }
    }

    private static func parseBracketCoreSkeleton(from text: String) -> CoreSkeleton? {
        let normalized = sanitizeCoreSkeletonField(text)
        guard !normalized.isEmpty else { return nil }

        guard let regex = try? NSRegularExpression(pattern: #"\[([A-Za-z_\s-]+):\s*([^\]]+)\]"#) else {
            return nil
        }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let matches = regex.matches(in: normalized, range: range)
        guard !matches.isEmpty else { return nil }

        var subjectParts: [String] = []
        var predicateParts: [String] = []
        var complementParts: [String] = []

        for match in matches {
            guard
                let labelRange = Range(match.range(at: 1), in: normalized),
                let valueRange = Range(match.range(at: 2), in: normalized)
            else {
                continue
            }

            let label = normalized[labelRange].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = sanitizeCoreSkeletonField(String(normalized[valueRange]))
            guard !value.isEmpty else { continue }

            switch label {
            case "subject", "subj", "subject phrase":
                subjectParts.append(value)
            case "predicate", "verb", "main verb", "verb phrase":
                predicateParts.append(value)
            case "object", "object clause", "complement", "predicate complement", "object complement", "complement clause":
                complementParts.append(value)
            default:
                if label.contains("subject") {
                    subjectParts.append(value)
                } else if label.contains("predicate") || label.contains("verb") {
                    predicateParts.append(value)
                } else if label.contains("object") || label.contains("complement") || label.contains("clause") {
                    complementParts.append(value)
                }
            }
        }

        guard !subjectParts.isEmpty || !predicateParts.isEmpty || !complementParts.isEmpty else {
            return nil
        }

        return CoreSkeleton(
            subject: subjectParts.joined(separator: "；"),
            predicate: predicateParts.joined(separator: "；"),
            complementOrObject: complementParts.joined(separator: "；")
        )
    }

    private static func parseCompatibleCoreSkeleton(from text: String) -> CoreSkeleton? {
        let normalized = sanitizeCoreSkeletonField(text)
        guard !normalized.isEmpty else { return nil }

        if let bracketSkeleton = parseBracketCoreSkeleton(from: normalized) {
            return bracketSkeleton
        }

        let segments = normalized
            .replacingOccurrences(of: "\n", with: "｜")
            .replacingOccurrences(of: "／", with: "｜")
            .replacingOccurrences(of: "/", with: "｜")
            .split(separator: "｜")
            .map(String.init)

        var subject = ""
        var predicate = ""
        var complement = ""

        for segment in segments {
            let trimmed = sanitizeCoreSkeletonField(segment)
            if segment.contains("主语：") || segment.contains("主语:") {
                subject = sanitizeCoreSkeletonField(trimmed.replacingOccurrences(of: "主语：", with: "").replacingOccurrences(of: "主语:", with: ""))
            } else if segment.contains("谓语：") || segment.contains("谓语:") {
                predicate = sanitizeCoreSkeletonField(trimmed.replacingOccurrences(of: "谓语：", with: "").replacingOccurrences(of: "谓语:", with: ""))
            } else if segment.contains("核心补足：") || segment.contains("核心补足:") || segment.contains("宾语：") || segment.contains("补语：") || segment.contains("表语：") {
                complement = sanitizeCoreSkeletonField(
                    trimmed
                        .replacingOccurrences(of: "核心补足：", with: "")
                        .replacingOccurrences(of: "核心补足:", with: "")
                        .replacingOccurrences(of: "宾语：", with: "")
                        .replacingOccurrences(of: "宾语:", with: "")
                        .replacingOccurrences(of: "补语：", with: "")
                        .replacingOccurrences(of: "补语:", with: "")
                        .replacingOccurrences(of: "表语：", with: "")
                        .replacingOccurrences(of: "表语:", with: "")
                )
            }
        }

        guard !subject.isEmpty || !predicate.isEmpty || !complement.isEmpty else {
            return nil
        }

        return CoreSkeleton(subject: subject, predicate: predicate, complementOrObject: complement)
    }

    private static func sanitizeCoreSkeletonField(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let stripped = trimmed.replacingOccurrences(
            of: #"\[[A-Za-z_\s-]+:\s*([^\]]+)\]"#,
            with: "$1",
            options: .regularExpression
        )
        let cleaned = stripped
            .replacingOccurrences(
                of: #"^(主语|谓语|核心补足|宾语|补语|表语|subject|predicate|object|complement)\s*[：:]\s*"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeMixedGrammarChinese(_ text: String) -> String {
        let replacements: [(String, String)] = [
            ("temporal clause", "时间状语从句"),
            ("time clause", "时间状语从句"),
            ("reduced relative clause", "压缩定语从句"),
            ("relative clause", "定语从句"),
            ("object clause", "宾语从句"),
            ("modal verb", "情态动词"),
            ("postpositive modifier", "后置修饰"),
            ("passive voice", "被动结构"),
            ("concessive frame", "让步框架"),
            ("framing phrase", "前置框架"),
            ("conditional frame", "条件框架"),
            ("participle phrase", "分词短语"),
            ("infinitive phrase", "不定式短语"),
            ("non-finite", "非谓语结构"),
            ("adverbial clause", "状语从句"),
            ("subject clause", "主语从句"),
            ("predicative clause", "表语从句"),
            ("appositive clause", "同位语从句")
        ]

        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (raw, zh) in replacements {
            normalized = normalized.replacingOccurrences(of: raw, with: zh, options: [.caseInsensitive, .regularExpression])
        }
        normalized = normalized.replacingOccurrences(
            of: #"([A-Za-z]+)\s*引导的"#,
            with: #"由原句里的“$1 …”引出的"#,
            options: .regularExpression
        )
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func grammarTemplate(for raw: String) -> (title: String, explanation: String, function: String, why: String)? {
        let normalized = normalizeMixedGrammarChinese(raw)
        let lower = normalized.lowercased()

        if normalized.contains("时间状语从句") || lower.contains("after") || lower.contains("before") || lower.contains("when ") || lower.contains("once") {
            return (
                title: "时间状语从句",
                explanation: "这是用来交代时间背景的状语从句，说明事情在什么时间条件下发生。",
                function: "它在这句里先搭时间背景，再把真正要成立的判断交给主句。",
                why: "时间框架一旦错挂，背景信息就会被错读成核心判断。"
            )
        }
        if normalized.contains("压缩定语从句") {
            return (
                title: "压缩定语从句",
                explanation: "这是把完整关系从句压缩成更短修饰块的写法，本质上仍在补前面名词的信息。",
                function: "它在这里负责压缩对前面名词的限定说明，不是在另起一个主句。",
                why: "如果把这层误当成主干谓语，整句结构就会被拆坏。"
            )
        }
        if normalized.contains("宾语从句") {
            return (
                title: "宾语从句",
                explanation: "这是跟在谓语后面、充当核心内容的从句，常回答“认为什么”“说明什么”。",
                function: "它在这句里承接前面的谓语，真正承载作者要表达的内容对象。",
                why: "宾语从句一旦挂错，学生会把说法来源和作者判断混在一起。"
            )
        }
        if normalized.contains("情态动词") || lower.contains("might") || lower.contains("could") || lower.contains("would") || lower.contains("should") {
            return (
                title: "情态动词",
                explanation: "情态动词本身不增加新事实，而是在调节语气强弱，表示可能、推测、限制或建议。",
                function: "它在这句里控制作者判断的把握程度，不让语气走成绝对断言。",
                why: "情态一旦忽略，题目里的态度强弱和作者把握程度就会读偏。"
            )
        }
        if normalized.contains("后置修饰") || normalized.contains("定语从句") {
            return (
                title: normalized.contains("后置修饰") ? "后置修饰" : "定语从句",
                explanation: "这是补在中心名词后面的限定信息，读的时候要先找清楚它修饰谁。",
                function: "它在这里负责给前面的名词补限定范围，不是在推进新的主句判断。",
                why: "修饰对象一旦挂错，枝叶就会被误当成主干。"
            )
        }
        if normalized.contains("非谓语") || lower.contains("participle") || lower.contains("infinitive") {
            return (
                title: "非谓语结构",
                explanation: "这是把完整动作压缩成信息块的写法，常用来补目的、原因、伴随或修饰关系。",
                function: "它在这句里负责压缩附加信息，不能被当成新的完整谓语。",
                why: "如果把非谓语误判成主句谓语，整句主干会被直接拆坏。"
            )
        }
        if normalized.contains("被动结构") {
            return (
                title: "被动结构",
                explanation: "被动结构会把动作承受者顶到前面，真正的施动者可能后移甚至省略。",
                function: "它在这句里改变了信息出场顺序，强调的是谁被作用，而不是谁主动发出动作。",
                why: "如果被动方向没看清，细节关系和因果关系就很容易整体读反。"
            )
        }
        if normalized.contains("否定") {
            return (
                title: "否定范围",
                explanation: "这里要看清否定词到底压在哪一层信息上，而不是看到 not 就结束。",
                function: "它在本句里限制判断成立的范围，决定作者否定的是动作、比较项还是条件层。",
                why: "否定范围一旦看错，题目选项的态度和细节判断会整体反向。"
            )
        }
        if normalized.contains("让步框架") {
            return (
                title: "让步框架",
                explanation: "让步框架会先承认一个条件、反方声音或看似成立的情况，再回到自己的真正判断。",
                function: "它在这里先让一步，真正想成立的判断通常落在后面的主句。",
                why: "学生最容易把让步内容错当成作者最终立场。"
            )
        }

        return nil
    }

    private static func localizedGrammarFocus(
        phenomenon: String,
        function: String,
        whyItMatters: String,
        titleZh: String,
        explanationZh: String,
        whyItMattersZh: String,
        exampleEn: String
    ) -> GrammarFocus {
        let template = grammarTemplate(for: phenomenon)
        let normalizedFunction = localizeChineseExplanation(normalizeMixedGrammarChinese(function))
        let normalizedWhy = localizeChineseExplanation(normalizeMixedGrammarChinese(whyItMatters))
        let explicitTitle = localizeChineseDisplayText(titleZh)
        let fallbackTitle = template?.title ?? localizeChineseDisplayText(normalizeMixedGrammarChinese(phenomenon))
        let localizedTitle = explicitTitle.isEmpty ? (fallbackTitle.isEmpty ? "关键语法点" : fallbackTitle) : explicitTitle
        let explicitExplanation = localizeChineseExplanation(explanationZh)
        let localizedExplanation = (!explicitExplanation.isEmpty && !looksLikeGrammarRoleDescription(explicitExplanation))
            ? explicitExplanation
            : (template?.explanation ?? "这是本句里最值得先抓的一层结构。")
        let localizedFunction = normalizedFunction.isEmpty
            ? (template?.function ?? "它在这句里负责限定主干、补充范围或交代背景。")
            : normalizedFunction
        let explicitWhy = localizeChineseExplanation(whyItMattersZh)
        let localizedWhy = explicitWhy.isEmpty
            ? (normalizedWhy.isEmpty ? (template?.why ?? "这个结构一旦挂错，主干和命题改写都会跟着读偏。") : normalizedWhy)
            : explicitWhy

        return GrammarFocus(
            phenomenon: phenomenon.isEmpty ? localizedTitle : phenomenon,
            function: localizedFunction,
            whyItMatters: localizedWhy,
            titleZh: localizedTitle,
            explanationZh: localizedExplanation,
            whyItMattersZh: localizedWhy,
            exampleEn: exampleEn
        )
    }

    private static func looksLikeGrammarRoleDescription(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        return normalized.contains("本句")
            || normalized.contains("在这句")
            || normalized.contains("先抓")
            || normalized.contains("不要把")
            || normalized.contains("阅读时")
    }

    private static func localizeChineseDisplayText(_ text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }

        if let range = normalized.range(of: "：") ?? normalized.range(of: ":") {
            let head = normalized[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let body = localizeChineseExplanation(String(normalized[range.upperBound...]))
            if !body.isEmpty {
                return head.isEmpty ? body : "\(head)：\(body)"
            }
        }

        return localizeChineseExplanation(normalized)
    }

    private static func localizeChineseExplanation(_ text: String) -> String {
        let normalized = normalizeMixedGrammarChinese(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }

        let chineseCount = normalized.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
        let latinCount = normalized.unicodeScalars.filter {
            ($0.value >= 0x41 && $0.value <= 0x5A) || ($0.value >= 0x61 && $0.value <= 0x7A)
        }.count

        if chineseCount >= max(8, latinCount * 2) {
            return normalized
        }

        let recovered = normalized
            .components(separatedBy: CharacterSet(charactersIn: "\n"))
            .flatMap { line in
                line.split(whereSeparator: { "。！？；".contains($0) }).map(String.init)
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { clause in
                let clauseChinese = clause.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
                let clauseLatin = clause.unicodeScalars.filter {
                    ($0.value >= 0x41 && $0.value <= 0x5A) || ($0.value >= 0x61 && $0.value <= 0x7A)
                }.count
                return clauseChinese >= 8 && clauseChinese > clauseLatin
            }

        return recovered.joined(separator: "。")
    }

    private static func resolvedTeachingInterpretation(
        candidate: String,
        legacyMeaning: String,
        faithfulTranslation: String,
        sentenceFunction: String,
        coreSkeleton: CoreSkeleton?,
        chunkLayers: [ChunkLayer]
    ) -> String {
        let normalizedFaithful = normalizedChineseComparisonKey(faithfulTranslation)
        let normalizedCandidate = localizeChineseExplanation(candidate)
        if !normalizedCandidate.isEmpty, normalizedChineseComparisonKey(normalizedCandidate) != normalizedFaithful {
            return normalizedCandidate
        }

        let normalizedLegacy = localizeChineseExplanation(legacyMeaning)
        if !normalizedLegacy.isEmpty, normalizedChineseComparisonKey(normalizedLegacy) != normalizedFaithful {
            return normalizedLegacy
        }

        return buildTeachingInterpretationFallback(
            sentenceFunction: sentenceFunction,
            coreSkeleton: coreSkeleton,
            chunkLayers: chunkLayers,
            faithfulTranslation: faithfulTranslation
        )
    }

    private static func resolvedRewriteTranslation(
        candidate: String,
        rewrite: String,
        faithfulTranslation: String,
        coreSkeleton: CoreSkeleton?,
        chunkLayers: [ChunkLayer]
    ) -> String {
        let normalizedCandidate = localizeChineseExplanation(candidate)
        if !normalizedCandidate.isEmpty,
           normalizedChineseComparisonKey(normalizedCandidate) != normalizedChineseComparisonKey(faithfulTranslation) {
            return normalizedCandidate
        }

        guard !rewrite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }

        var parts: [String] = []
        let normalizedFaithful = localizeChineseExplanation(faithfulTranslation)
        if !normalizedFaithful.isEmpty {
            parts.append("这条改写仍在说：\(normalizedFaithful)")
        }

        let roles = chunkLayers.map { normalizeMixedGrammarChinese($0.role) }
        if roles.contains(where: { $0.contains("前置") || $0.contains("条件") || $0.contains("让步") || $0.contains("后置") }) {
            parts.append("它保留了原句主干判断，把外围框架和修饰层压缩成更直接的主句表达。")
        } else {
            parts.append("它保留原意，只把句法改成更直接的主谓表达。")
        }

        if let coreSkeleton, coreSkeleton.isMeaningful {
            let stableCore = [
                coreSkeleton.subject.isEmpty ? nil : "主语：\(coreSkeleton.subject)",
                coreSkeleton.predicate.isEmpty ? nil : "谓语：\(coreSkeleton.predicate)",
                coreSkeleton.complementOrObject.isEmpty ? nil : "核心补足：\(coreSkeleton.complementOrObject)"
            ]
            .compactMap { $0 }
            .joined(separator: "｜")
            if !stableCore.isEmpty {
                parts.append("主干没有变，抓住“\(stableCore)”就能看出改写没有换义。")
            }
        }

        return parts.joined(separator: " ")
    }

    private static func buildTeachingInterpretationFallback(
        sentenceFunction: String,
        coreSkeleton: CoreSkeleton?,
        chunkLayers: [ChunkLayer],
        faithfulTranslation: String
    ) -> String {
        var parts: [String] = []
        let functionHead = localizeChineseDisplayText(sentenceFunction)
        if !functionHead.isEmpty {
            parts.append("老师先会把这句当成“\(functionHead)”来看。")
        }

        if let coreSkeleton, coreSkeleton.isMeaningful {
            let stableCore = [
                coreSkeleton.subject.isEmpty ? nil : "主语“\(coreSkeleton.subject)”",
                coreSkeleton.predicate.isEmpty ? nil : "谓语“\(coreSkeleton.predicate)”",
                coreSkeleton.complementOrObject.isEmpty ? nil : "核心补足“\(coreSkeleton.complementOrObject)”"
            ]
            .compactMap { $0 }
            .joined(separator: "、")
            if !stableCore.isEmpty {
                parts.append("板书时先锁定 \(stableCore)，其余成分都往这个主干上挂。")
            }
        }

        let roleHints = chunkLayers
            .map { normalizeMixedGrammarChinese($0.role) }
            .filter { !$0.isEmpty }
        if roleHints.contains(where: { $0.contains("前置") || $0.contains("条件") || $0.contains("让步") }) {
            parts.append("读的时候不要被句首框架带走，真正判断一般落在后面的主句主干。")
        } else if roleHints.contains(where: { $0.contains("后置") || $0.contains("补充") }) {
            parts.append("其余语块主要是在补限定范围和修饰关系，不要把枝叶误抬成主干。")
        }

        let faithful = localizeChineseExplanation(faithfulTranslation)
        if !faithful.isEmpty {
            parts.append("先把“\(faithful)”这个基本意思抓稳，再回头分层看修饰关系。")
        }

        return parts.joined(separator: " ")
    }

    private static func normalizedChineseComparisonKey(_ text: String) -> String {
        localizeChineseExplanation(text)
            .lowercased()
            .replacingOccurrences(of: #"[^\p{Han}a-z0-9]+"#, with: "", options: .regularExpression)
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
            return AIServiceAvailabilityPolicy.userFacingMessage(
                for: .sentenceExplain,
                technicalReason: message
            )
        case .transport(let message):
            return AIServiceAvailabilityPolicy.userFacingMessage(
                for: .sentenceExplain,
                technicalReason: message
            )
        }
    }
}

enum AIExplainSentenceService {
    private static let baseURLStorageKey = "huiLu.aiBackendBaseURL"
    private static let defaultBaseURL = "http://47.94.227.58"
    private static let preferredAIPort = 3000
    private static let explainSentenceTimeout: TimeInterval = 75
    private static let aiRequestPolicy = AIRequestPolicy.default
    private static let sentenceAnalysisCacheStore = SentenceAnalysisCacheStore()
    private static let requestSingleFlight = AIRequestSingleFlight<AIExplainSentenceResult>()

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
        case 408, 421, 425, 429:
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
        case .networkConnectionLost:
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

    private static func validatedContext(for context: ExplainSentenceContext) -> ExplainSentenceContext {
        let (validatedSentence, sentenceRepaired) = TextPipelineValidator.validateAndRepairIfReversed(context.sentence)
        let (validatedContext, _) = TextPipelineValidator.validateAndRepairIfReversed(context.context)

        if sentenceRepaired {
            TextPipelineDiagnostics.log(
                "句子分析",
                "发送前检测到反转句子，已修复: \"\(String(context.sentence.prefix(40)))…\"",
                severity: .repaired
            )
        }

        return ExplainSentenceContext(
            title: context.title,
            sentenceID: context.sentenceID,
            anchorLabel: context.anchorLabel,
            sentence: validatedSentence,
            context: validatedContext,
            paragraphTheme: context.paragraphTheme,
            paragraphRole: context.paragraphRole,
            questionPrompt: context.questionPrompt
        )
    }

    private static func logSentenceExplainCacheHit(_ source: SentenceAnalysisCacheStore.CacheSource) {
        let message: String
        switch source {
        case .memory:
            message = "[AI][SentenceExplain] memory cache hit"
        case .disk:
            message = "[AI][SentenceExplain] disk cache hit"
        }

        TextPipelineDiagnostics.log("AI", message, severity: .info)
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
        let validatedExplainContext = validatedContext(for: context)
        return try await performFetchExplanationRequest(
            for: validatedExplainContext,
            baseURL: overrideBaseURL
        )
    }

    static func fetchExplanationWithCache(
        for context: ExplainSentenceContext,
        baseURL overrideBaseURL: String? = nil,
        forceRefresh: Bool = false
    ) async throws -> AIExplainSentenceResult {
        let validatedExplainContext = validatedContext(for: context)
        let requestKey = SentenceAnalysisCacheStore.cacheKey(
            for: validatedExplainContext,
            baseURL: overrideBaseURL ?? storedBaseURL
        )
        let allowDiskCache = aiRequestPolicy.enableSentenceExplainDiskCache

        if !forceRefresh,
           let cacheHit = await sentenceAnalysisCacheStore.lookup(
               forKey: requestKey,
               allowDisk: allowDiskCache
           ) {
            logSentenceExplainCacheHit(cacheHit.source)
            return cacheHit.result
        }

        return try await requestSingleFlight.run(
            key: requestKey,
            onJoin: {
                TextPipelineDiagnostics.log(
                    "AI",
                    "[AI][SentenceExplain] single-flight join",
                    severity: .info
                )
            }
        ) {
            if !forceRefresh,
               let cacheHit = await sentenceAnalysisCacheStore.lookup(
                   forKey: requestKey,
                   allowDisk: allowDiskCache
               ) {
                logSentenceExplainCacheHit(cacheHit.source)
                return cacheHit.result
            }

            let result = try await performFetchExplanationRequest(
                for: validatedExplainContext,
                baseURL: overrideBaseURL
            )
            await sentenceAnalysisCacheStore.store(
                result,
                forKey: requestKey,
                persistToDisk: allowDiskCache
            )
            return result
        }
    }

    private static func performFetchExplanationRequest(
        for context: ExplainSentenceContext,
        baseURL overrideBaseURL: String?
    ) async throws -> AIExplainSentenceResult {
        if let blockingMessage = await aiServiceAvailabilityGate.blockingMessage(for: .sentenceExplain) {
            TextPipelineDiagnostics.log(
                "AI",
                "[AI][SentenceExplain] service gate open",
                severity: .warning
            )
            throw AIExplainSentenceServiceError.requestFailed(blockingMessage)
        }

        let endpointURLs = endpointCandidates(
            path: "ai/explain-sentence",
            overrideBaseURL: overrideBaseURL
        )
        guard !endpointURLs.isEmpty else {
            throw AIExplainSentenceServiceError.missingBaseURL
        }

        let requestData = try JSONEncoder().encode(
            ExplainSentenceRequest(
                title: context.title,
                sentence: context.sentence,
                context: context.context,
                paragraphTheme: context.paragraphTheme,
                paragraphRole: context.paragraphRole,
                questionPrompt: context.questionPrompt
            )
        )

        return try await performFetchExplanation(
            for: context,
            requestData: requestData,
            endpointURLs: endpointURLs
        )
    }

    private static func performFetchExplanation(
        for context: ExplainSentenceContext,
        requestData: Data,
        endpointURLs: [URL]
    ) async throws -> AIExplainSentenceResult {
        var lastError: Error?

        for (index, endpointURL) in endpointURLs.enumerated() {
            for attempt in 0..<2 {
                var request = URLRequest(url: endpointURL)
                request.httpMethod = "POST"
                request.timeoutInterval = explainSentenceTimeout
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
                        await aiServiceAvailabilityGate.recordFailure(
                            for: .sentenceExplain,
                            technicalReason: bodySnippet.isEmpty ? "HTTP \(httpResponse.statusCode)" : "HTTP \(httpResponse.statusCode): \(bodySnippet)",
                            cooldown: AIServiceAvailabilityPolicy.cooldown(for: httpResponse.statusCode)
                        )

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

                    var decoded = try decodeResponseEnvelope(
                        from: data,
                        sourceSentence: context.sentence
                    )

                    if let identity = currentIdentity(for: context),
                       let payload = decoded.data {
                        let attached = payload.attachingIdentity(identity)
                        let warnings = AnalysisConsistencyGuard.warnings(
                            identity: identity,
                            sentenceText: context.sentence,
                            analysis: attached
                        )

                        if !warnings.isEmpty {
                            TextPipelineDiagnostics.log(
                                "句子分析",
                                "丢弃不一致分析结果：\(warnings.joined(separator: "；")) sentence=\(identity.sourceSentenceID)",
                                severity: .warning
                            )
                            throw AIExplainSentenceServiceError.requestFailed("返回结果与当前句不一致")
                        }

                        decoded = ExplainSentenceResponseEnvelope(
                            success: decoded.success,
                            data: attached,
                            error: decoded.error
                        )
                    }

                    if decoded.success, let result = decoded.data {
                        await aiServiceAvailabilityGate.recordSuccess(for: .sentenceExplain)
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
                    await aiServiceAvailabilityGate.recordFailure(
                        for: .sentenceExplain,
                        technicalReason: error.localizedDescription,
                        cooldown: AIServiceAvailabilityPolicy.cooldown(for: error)
                    )
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

    private static func currentIdentity(for context: ExplainSentenceContext) -> SentenceAnalysisIdentity? {
        guard let sentenceID = context.sentenceID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sentenceID.isEmpty,
              let anchorLabel = context.anchorLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !anchorLabel.isEmpty else {
            return nil
        }

        return SentenceAnalysisIdentity(
            sentenceID: sentenceID,
            sentenceText: context.sentence,
            anchorLabel: anchorLabel
        )
    }
}
