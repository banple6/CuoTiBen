import Foundation

// MARK: - 教授级全文教学分析服务
// 调用后端 /ai/analyze-passage 批量获取 AI 教学分析
// 一次调用产出：文章总览 + 段落教学卡 + 关键句教授卡

enum ProfessorAnalysisService {

    private static let maxProfessorParagraphs = 4
    private static let preferredParagraphChars = 460
    private static let minimumParagraphChars = 180
    private static let hardParagraphChars = 700
    private static let maxParagraphSentences = 4
    private static let maxProfessorKeySentences = 6
    private static let analyzePassageTimeout: TimeInterval = 45

    private struct ParagraphAnalysisGroup {
        let requestIndex: Int
        let text: String
        let segmentIDs: [String]
        let segmentIndexes: [Int]
        let anchorLabels: [String]
        let sentenceIDs: [String]
        let charCount: Int
        let pageRange: ClosedRange<Int>?
    }

    private struct MutableParagraphGroup {
        var segments: [Segment] = []
        var sentenceIDs: [String] = []
        var charCount: Int = 0
        var pages: [Int] = []

        var isEmpty: Bool { segments.isEmpty }
        var segmentIDs: [String] { segments.map(\.id) }
        var segmentIndexes: [Int] { segments.map(\.index) }
        var anchorLabels: [String] { segments.map(\.anchorLabel) }
        var sentenceCount: Int { sentenceIDs.count }
        var pageRange: ClosedRange<Int>? {
            guard let first = pages.min(), let last = pages.max() else { return nil }
            return first ... last
        }

        mutating func append(_ segment: Segment) {
            segments.append(segment)
            sentenceIDs.append(contentsOf: segment.sentenceIDs)
            charCount += segment.text.count
            if let page = segment.page {
                pages.append(page)
            }
        }

        func finalized(requestIndex: Int) -> ParagraphAnalysisGroup {
            ParagraphAnalysisGroup(
                requestIndex: requestIndex,
                text: segments.map(\.text).joined(separator: "\n\n"),
                segmentIDs: segmentIDs,
                segmentIndexes: segmentIndexes,
                anchorLabels: anchorLabels,
                sentenceIDs: sentenceIDs,
                charCount: charCount,
                pageRange: pageRange
            )
        }
    }

    // MARK: - 请求/响应模型

    struct ParagraphInput: Encodable {
        let index: Int
        let text: String
    }

    struct KeySentenceInput: Encodable {
        let ref: String
        let text: String
        let paragraph_index: Int
    }

    struct AnalyzePassageRequest: Encodable {
        let title: String
        let paragraphs: [ParagraphInput]
        let key_sentences: [KeySentenceInput]
        let client_request_id: String
    }

    struct AnalyzePassageResponse: Decodable {
        let success: Bool?
        let data: AnalyzePassageData?
        let error_code: String?
        let message: String?
        let request_id: String?
        let retryable: Bool?
        let fallback_available: Bool?
        let used_cache: Bool?
        let used_fallback: Bool?
        let retry_count: Int?
    }

    struct AnalyzePassageData: Decodable {
        let passage_overview: PassageOverviewDTO?
        let paragraph_cards: [ParagraphCardDTO]?
        let key_sentence_refs: [String]?
        let quality_warnings: [String]?
        let elapsed_ms: Int?
        let request_id: String?
        let used_cache: Bool?
        let used_fallback: Bool?
        let retry_count: Int?
    }

    struct PassageOverviewDTO: Decodable {
        let article_theme: String?
        let author_core_question: String?
        let progression_path: String?
        let likely_question_types: [String]?
        let logic_pitfalls: [String]?
        let paragraph_function_map: [String]?
        let syntax_highlights: [String]?
        let reading_traps: [String]?
        let vocabulary_highlights: [String]?
    }

    struct ParagraphCardDTO: Decodable {
        let paragraph_index: Int?
        let theme: String?
        let argument_role: String?
        let core_sentence_local_index: Int?
        let keywords: [String]?
        let relation_to_previous: String?
        let exam_value: String?
        let teaching_focuses: [String]?
        let student_blind_spot: String?
    }

    struct GrammarPointDTO: Decodable {
        let name: String?
        let explanation: String?
    }

    struct VocabularyDTO: Decodable {
        let term: String?
        let meaning: String?
    }

    // MARK: - 错误类型

    enum AnalysisError: LocalizedError {
        case missingBaseURL
        case invalidBaseURL
        case invalidServerResponse
        case requestFailed(AIServiceFailureContext)
        case noContent

        var errorDescription: String? {
            switch self {
            case .missingBaseURL: return "未配置后端地址"
            case .invalidBaseURL: return "后端地址格式错误"
            case .invalidServerResponse: return "服务器响应格式异常"
            case .requestFailed(let failure):
                return failure.userFacingMessage
            case .noContent: return "后端未返回分析内容"
            }
        }
    }

    // MARK: - 公开接口

    /// 从 StructuredSourceBundle 中提取段落和关键句，调用后端批量分析，返回增强后的 Bundle
    static func enrichBundle(
        _ bundle: StructuredSourceBundle,
        title: String,
        overrideBaseURL: String? = nil
    ) async throws -> StructuredSourceBundle {
        if let blockingMessage = await aiServiceAvailabilityGate.blockingMessage(for: .professorAnalysis) {
            TextPipelineDiagnostics.log(
                "AI",
                "[AI][ProfessorAnalysis] service gate open",
                severity: .warning
            )
            throw AnalysisError.requestFailed(
                AIServiceFailureContext(
                    message: blockingMessage,
                    errorCode: "GEMINI_UPSTREAM_503",
                    requestID: nil,
                    retryable: true,
                    fallbackAvailable: true,
                    usedCache: false,
                    usedFallback: true,
                    retryCount: 0
                )
            )
        }

        let endpointURLs = AIExplainSentenceService.endpointCandidates(
            path: "ai/analyze-passage",
            overrideBaseURL: overrideBaseURL
        )
        guard !endpointURLs.isEmpty else { throw AnalysisError.missingBaseURL }

        // 从 bundle 构建请求
        let paragraphGroups = buildParagraphAnalysisGroups(from: bundle)
        let paragraphInputs = paragraphGroups.map {
            ParagraphInput(index: $0.requestIndex, text: $0.text)
        }

        // 选取关键句（每段核心句 + 所有 isKeySentence  + 超长句）
        let keySentenceInputs = selectKeySentences(from: bundle, paragraphGroups: paragraphGroups)

        TextPipelineDiagnostics.log(
            "AI",
            "[AI][ProfessorAnalysis] 开始批量教学分析: paragraphs=\(paragraphInputs.count)/segments=\(bundle.segments.count) keySentences=\(keySentenceInputs.count) title=\(title)",
            severity: .info
        )

        let clientRequestID = "ios-passage-\(UUID().uuidString.lowercased())"
        let requestBody = AnalyzePassageRequest(
            title: title,
            paragraphs: paragraphInputs,
            key_sentences: keySentenceInputs,
            client_request_id: clientRequestID
        )

        let requestData = try JSONEncoder().encode(requestBody)
        var payload: AnalyzePassageData?
        var lastError: Error?

        for (index, url) in endpointURLs.enumerated() {
            for attempt in 0..<2 {
                var request = URLRequest(url: url, timeoutInterval: analyzePassageTimeout)
                request.httpMethod = "POST"
                request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
                request.httpBody = requestData

                do {
                    try Task.checkCancellation()
                    let (data, httpResponse) = try await URLSession.shared.data(for: request)

                    guard let http = httpResponse as? HTTPURLResponse else {
                        throw AnalysisError.invalidServerResponse
                    }

                    if !(200 ..< 300).contains(http.statusCode) {
                        let errorEnvelope = try? JSONDecoder().decode(AnalyzePassageResponse.self, from: data)
                        let bodySnippet = String(data: data.prefix(500), encoding: .utf8) ?? ""
                        let failure = AIServiceFailureContext(
                            message: errorEnvelope?.message ?? "AI 服务暂时繁忙，已展示本地教授式骨架，可稍后重试。",
                            errorCode: errorEnvelope?.error_code ?? "GEMINI_UPSTREAM_503",
                            requestID: errorEnvelope?.request_id,
                            retryable: errorEnvelope?.retryable ?? AIExplainSentenceService.shouldRetryEndpoint(statusCode: http.statusCode),
                            fallbackAvailable: errorEnvelope?.fallback_available ?? true,
                            usedCache: errorEnvelope?.used_cache ?? false,
                            usedFallback: errorEnvelope?.used_fallback ?? true,
                            retryCount: errorEnvelope?.retry_count ?? attempt
                        )
                        await aiServiceAvailabilityGate.recordFailure(
                            for: .professorAnalysis,
                            technicalReason: bodySnippet.isEmpty ? "HTTP \(http.statusCode)" : "HTTP \(http.statusCode): \(bodySnippet)",
                            cooldown: AIServiceAvailabilityPolicy.cooldown(for: http.statusCode)
                        )
                        TextPipelineDiagnostics.log(
                            "AI",
                            "[AI][ProfessorAnalysis] 后端返回 HTTP \(http.statusCode): \(bodySnippet)",
                            severity: .error
                        )

                        if AIExplainSentenceService.shouldRetrySameEndpoint(statusCode: http.statusCode), attempt == 0 {
                            TextPipelineDiagnostics.log(
                                "AI",
                                "[AI][ProfessorAnalysis] 端点瞬时失败，准备重试: \(url.absoluteString) status=\(http.statusCode) request_id=\(failure.requestID ?? "nil")",
                                severity: .warning
                            )
                            try await Task.sleep(nanoseconds: AIExplainSentenceService.retryDelayNanoseconds(for: attempt))
                            continue
                        }

                        if AIExplainSentenceService.shouldRetryEndpoint(statusCode: http.statusCode), index < endpointURLs.count - 1 {
                            let nextURL = endpointURLs[index + 1].absoluteString
                            TextPipelineDiagnostics.log(
                                "AI",
                                "[AI][ProfessorAnalysis] 切换候选地址: \(url.absoluteString) -> \(nextURL) status=\(http.statusCode) request_id=\(failure.requestID ?? "nil")",
                                severity: .warning
                            )
                            lastError = AnalysisError.requestFailed(failure)
                            break
                        }

                        throw AnalysisError.requestFailed(failure)
                    }

                    let response = try JSONDecoder().decode(AnalyzePassageResponse.self, from: data)

                    guard let data = response.data else {
                        if let message = response.message {
                            throw AnalysisError.requestFailed(
                                AIServiceFailureContext(
                                    message: message,
                                    errorCode: response.error_code,
                                    requestID: response.request_id,
                                    retryable: response.retryable ?? false,
                                    fallbackAvailable: response.fallback_available ?? true,
                                    usedCache: response.used_cache ?? false,
                                    usedFallback: response.used_fallback ?? false,
                                    retryCount: response.retry_count ?? attempt
                                )
                            )
                        }
                        throw AnalysisError.noContent
                    }

                    await aiServiceAvailabilityGate.recordSuccess(for: .professorAnalysis)
                    payload = data
                    break
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as URLError {
                    if error.code == .cancelled || Task.isCancelled {
                        throw CancellationError()
                    }
                    await aiServiceAvailabilityGate.recordFailure(
                        for: .professorAnalysis,
                        technicalReason: error.localizedDescription,
                        cooldown: AIServiceAvailabilityPolicy.cooldown(for: error)
                    )
                    if AIExplainSentenceService.shouldRetrySameEndpoint(for: error), attempt == 0 {
                        TextPipelineDiagnostics.log(
                            "AI",
                            "[AI][ProfessorAnalysis] 端点连接瞬断，准备重试: \(url.absoluteString) error=\(error.localizedDescription)",
                            severity: .warning
                        )
                        try await Task.sleep(nanoseconds: AIExplainSentenceService.retryDelayNanoseconds(for: attempt))
                        continue
                    }
                    if AIExplainSentenceService.shouldRetryEndpoint(for: error), index < endpointURLs.count - 1 {
                        let nextURL = endpointURLs[index + 1].absoluteString
                        TextPipelineDiagnostics.log(
                            "AI",
                            "[AI][ProfessorAnalysis] 端点连接失败，切换候选地址: \(url.absoluteString) -> \(nextURL) error=\(error.localizedDescription)",
                            severity: .warning
                        )
                        lastError = AnalysisError.requestFailed(
                            AIServiceFailureContext(
                                message: AIServiceAvailabilityPolicy.userFacingMessage(
                                    for: .professorAnalysis,
                                    technicalReason: error.localizedDescription
                                ),
                                errorCode: error.code == .timedOut ? "GEMINI_TIMEOUT" : "BACKEND_ROUTE_ERROR",
                                requestID: nil,
                                retryable: true,
                                fallbackAvailable: true,
                                usedCache: false,
                                usedFallback: true,
                                retryCount: attempt
                            )
                        )
                        break
                    }
                    throw AnalysisError.requestFailed(
                        AIServiceFailureContext(
                            message: AIServiceAvailabilityPolicy.userFacingMessage(
                                for: .professorAnalysis,
                                technicalReason: error.localizedDescription
                            ),
                            errorCode: error.code == .timedOut ? "GEMINI_TIMEOUT" : "BACKEND_ROUTE_ERROR",
                            requestID: nil,
                            retryable: true,
                            fallbackAvailable: true,
                            usedCache: false,
                            usedFallback: true,
                            retryCount: attempt
                        )
                    )
                } catch let error as AnalysisError {
                    if case .invalidServerResponse = error, index < endpointURLs.count - 1 {
                        let nextURL = endpointURLs[index + 1].absoluteString
                        TextPipelineDiagnostics.log(
                            "AI",
                            "[AI][ProfessorAnalysis] 端点响应异常，切换候选地址: \(url.absoluteString) -> \(nextURL)",
                            severity: .warning
                        )
                        lastError = error
                        break
                    }
                    throw error
                } catch {
                    if index < endpointURLs.count - 1 {
                        lastError = error
                        break
                    }
                    throw AnalysisError.invalidServerResponse
                }
            }

            if payload != nil {
                break
            }
        }

        guard let payload else {
            if let error = lastError as? AnalysisError {
                throw error
            }
            throw AnalysisError.noContent
        }

        if let warnings = payload.quality_warnings, !warnings.isEmpty {
            TextPipelineDiagnostics.log(
                "AI",
                "[AI][ProfessorAnalysis] 质量警告: \(warnings.joined(separator: "; "))",
                severity: .warning
            )
        }

        TextPipelineDiagnostics.log(
            "AI",
            "[AI][ProfessorAnalysis] 分析完成: paragraphCards=\(payload.paragraph_cards?.count ?? 0) keySentenceRefs=\(payload.key_sentence_refs?.count ?? 0) elapsed=\(payload.elapsed_ms ?? 0)ms request_id=\(payload.request_id ?? "nil") retry_count=\(payload.retry_count ?? 0) used_cache=\(payload.used_cache ?? false) used_fallback=\(payload.used_fallback ?? false) client_request_id=\(clientRequestID)",
            severity: .info
        )

        // 转换为本地模型并合并到 bundle
        let aiOverview = convertOverview(payload.passage_overview)
        let aiParagraphCards = convertParagraphCards(
            payload.paragraph_cards ?? [],
            paragraphGroups: paragraphGroups,
            segments: bundle.segments,
            sentences: bundle.sentences
        )
        return bundle.enrichedWithAIAnalysis(
            overview: aiOverview,
            paragraphCards: aiParagraphCards,
            sentenceCards: []
        )
    }

    // MARK: - 关键句选取

    private static func selectKeySentences(
        from bundle: StructuredSourceBundle,
        paragraphGroups: [ParagraphAnalysisGroup]
    ) -> [KeySentenceInput] {
        struct Candidate {
            let priority: Int
            let input: KeySentenceInput
        }

        var candidates: [Candidate] = []
        var seenIDs: Set<String> = []

        let sentencesBySegment = Dictionary(grouping: bundle.sentences, by: { $0.segmentID })
        let paragraphIndexBySegmentID = paragraphGroups.reduce(into: [String: Int]()) { partialResult, group in
            for segmentID in group.segmentIDs {
                partialResult[segmentID] = group.requestIndex
            }
        }

        for (segIdx, segment) in bundle.segments.enumerated() {
            let sentences = sentencesBySegment[segment.id] ?? []
            let paragraphCard = bundle.paragraphCard(forSegmentID: segment.id)
            let paragraphIndex = paragraphIndexBySegmentID[segment.id] ?? min(segIdx, maxProfessorParagraphs - 1)

            for sentence in sentences {
                let isCore = sentence.id == paragraphCard?.coreSentenceID
                let isKey = bundle.sentenceCard(id: sentence.id)?.isKeySentence == true
                let isLong = sentence.text.count >= 80

                guard isCore || isKey || isLong else { continue }
                guard seenIDs.insert(sentence.id).inserted else { continue }

                let ref = "S_\(segIdx)_\(sentence.localIndex)"
                let priority = isCore ? 0 : (isKey ? 1 : 2)
                candidates.append(
                    Candidate(
                        priority: priority,
                        input: KeySentenceInput(
                            ref: ref,
                            text: sentence.text,
                            paragraph_index: paragraphIndex
                        )
                    )
                )
            }
        }

        let ordered = candidates.sorted { lhs, rhs in
            if lhs.input.paragraph_index != rhs.input.paragraph_index {
                return lhs.input.paragraph_index < rhs.input.paragraph_index
            }
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return lhs.input.ref < rhs.input.ref
        }

        return Array(ordered.prefix(maxProfessorKeySentences).map(\.input))
    }

    private static func buildParagraphAnalysisGroups(from bundle: StructuredSourceBundle) -> [ParagraphAnalysisGroup] {
        let orderedSegments = bundle.segments.sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.id < rhs.id
        }

        var groups: [MutableParagraphGroup] = []
        var current = MutableParagraphGroup()

        for segment in orderedSegments {
            let trimmedText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { continue }

            if current.isEmpty {
                current.append(segment)
                continue
            }

            let pageChanged = current.pages.last != segment.page
            let currentIsReady = current.charCount >= preferredParagraphChars || current.sentenceCount >= maxParagraphSentences
            let wouldExceedHardLimit = current.charCount + trimmedText.count > hardParagraphChars
            let shouldWrapForLargeIncoming = current.charCount >= minimumParagraphChars && trimmedText.count >= preferredParagraphChars / 2
            let shouldStartNewGroup =
                wouldExceedHardLimit ||
                (currentIsReady && (pageChanged || shouldWrapForLargeIncoming))

            if shouldStartNewGroup {
                groups.append(current)
                current = MutableParagraphGroup()
            }

            current.append(segment)
        }

        if !current.isEmpty {
            groups.append(current)
        }

        while groups.count > maxProfessorParagraphs, groups.count >= 2 {
            var mergeIndex = 0
            var smallestCombinedCount = Int.max

            for index in 0 ..< groups.count - 1 {
                let combinedCount = groups[index].charCount + groups[index + 1].charCount
                if combinedCount < smallestCombinedCount {
                    smallestCombinedCount = combinedCount
                    mergeIndex = index
                }
            }

            var merged = groups[mergeIndex]
            let next = groups[mergeIndex + 1]
            for segment in next.segments {
                merged.append(segment)
            }
            groups.replaceSubrange(mergeIndex ... mergeIndex + 1, with: [merged])
        }

        return groups.enumerated().map { index, group in
            group.finalized(requestIndex: index)
        }
    }

    // MARK: - DTO → 本地模型转换

    private static func convertOverview(_ dto: PassageOverviewDTO?) -> PassageOverview? {
        guard let dto else { return nil }
        return PassageOverview(
            articleTheme: dto.article_theme ?? "",
            authorCoreQuestion: dto.author_core_question ?? "",
            progressionPath: dto.progression_path ?? "",
            likelyQuestionTypes: dto.likely_question_types ?? [],
            logicPitfalls: dto.logic_pitfalls ?? [],
            paragraphFunctionMap: dto.paragraph_function_map ?? [],
            syntaxHighlights: dto.syntax_highlights ?? [],
            readingTraps: dto.reading_traps ?? [],
            vocabularyHighlights: dto.vocabulary_highlights ?? []
        )
    }

    private static func convertParagraphCards(
        _ dtos: [ParagraphCardDTO],
        paragraphGroups: [ParagraphAnalysisGroup],
        segments: [Segment],
        sentences: [Sentence]
    ) -> [ParagraphTeachingCard] {
        let segmentIndex = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
        let sentenceIndex = Dictionary(uniqueKeysWithValues: sentences.map { ($0.id, $0) })

        return dtos.flatMap { dto -> [ParagraphTeachingCard] in
            guard let paragraphIndex = dto.paragraph_index,
                  paragraphIndex < paragraphGroups.count else { return [] }

            let group = paragraphGroups[paragraphIndex]
            let groupSegments = group.segmentIDs.compactMap { segmentIndex[$0] }
            let groupSentences = group.sentenceIDs.compactMap { sentenceIndex[$0] }
            guard !groupSegments.isEmpty else { return [] }

            let roleString = dto.argument_role ?? "support"
            let role = ParagraphArgumentRole(rawValue: roleString) ?? .support

            let coreLocalIndex = dto.core_sentence_local_index ?? 0
            let coreSentenceID = groupSentences.indices.contains(coreLocalIndex)
                ? groupSentences[coreLocalIndex].id
                : groupSentences.first?.id

            return groupSegments.map { segment in
                ParagraphTeachingCard(
                    id: segment.id,
                    segmentID: segment.id,
                    paragraphIndex: segment.index,
                    anchorLabel: segment.anchorLabel,
                    theme: dto.theme ?? "",
                    argumentRole: role,
                    coreSentenceID: coreSentenceID,
                    keywords: dto.keywords ?? [],
                    relationToPrevious: dto.relation_to_previous ?? "",
                    examValue: dto.exam_value ?? "",
                    teachingFocuses: dto.teaching_focuses ?? [],
                    studentBlindSpot: dto.student_blind_spot,
                    isAIGenerated: true
                )
            }
        }
    }

}
