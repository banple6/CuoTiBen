import Foundation

struct ProfessorAnalysisServiceResult {
    let delta: ProfessorAnalysisDelta
    let meta: AIServiceResponseMeta
    let requestID: String?
    let keySentenceIDs: [String]
    let questionLinks: [QuestionEvidenceLink]
    let passageMap: PassageMap?
    let admissionResult: MindMapAdmissionResult?
    let message: String?
    let structuredError: AIStructuredError?

    var usedFallback: Bool { meta.usedFallback }
}

enum ProfessorAnalysisService {
    private static let maxParagraphCount = 4
    private static let maxParagraphCharacters = 700
    private static let analyzePassageTimeout: TimeInterval = 150

    private struct AnalyzePassageIdentity: Encodable {
        let clientRequestID: String
        let documentID: String
        let contentHash: String

        private enum CodingKeys: String, CodingKey {
            case clientRequestID = "client_request_id"
            case documentID = "document_id"
            case contentHash = "content_hash"
        }
    }

    private struct ParagraphInput: Encodable {
        let segmentID: String
        let index: Int
        let anchorLabel: String
        let text: String
        let sourceKind: String
        let hygieneScore: Double

        private enum CodingKeys: String, CodingKey {
            case segmentID = "segment_id"
            case index
            case anchorLabel = "anchor_label"
            case text
            case sourceKind = "source_kind"
            case hygieneScore = "hygiene_score"
        }
    }

    private struct AuxiliaryBlock: Encodable {
        let id: String
        let text: String
        let sourceKind: String

        private enum CodingKeys: String, CodingKey {
            case id
            case text
            case sourceKind = "source_kind"
        }
    }

    private struct AnalyzePassageRequest: Encodable {
        let identity: AnalyzePassageIdentity
        let title: String
        let paragraphs: [ParagraphInput]
        let questionBlocks: [AuxiliaryBlock]
        let answerBlocks: [AuxiliaryBlock]
        let vocabularyBlocks: [AuxiliaryBlock]

        private enum CodingKeys: String, CodingKey {
            case identity
            case title
            case paragraphs
            case questionBlocks = "question_blocks"
            case answerBlocks = "answer_blocks"
            case vocabularyBlocks = "vocabulary_blocks"
        }
    }

    private struct AnalyzePassageResponseEnvelope {
        let success: Bool
        let requestID: String?
        let meta: AIServiceResponseMeta
        let data: AnalyzePassagePayload?
        let structuredError: AIStructuredError?
    }

    private struct AnalyzePassagePayload {
        let overview: PassageOverview?
        let paragraphCards: [ParagraphTeachingCard]
        let keySentenceIDs: [String]
        let questionLinks: [QuestionEvidenceLink]
    }

    static func enrichBundle(
        _ bundle: StructuredSourceBundle,
        document: SourceDocument,
        title: String,
        overrideBaseURL: String? = nil
    ) async throws -> ProfessorAnalysisServiceResult {
        let paragraphInputs = buildParagraphInputs(from: bundle)
        guard !paragraphInputs.isEmpty else {
            return fallbackResult(
                document: document,
                bundle: bundle,
                structuredError: AIStructuredError.invalidRequest(message: "当前资料缺少可用于地图分析的正文段落。")
            )
        }

        let contentHash = AIRequestIdentity.hash(
            text: paragraphInputs.map(\.text).joined(separator: "\n\n")
        )
        let identity = AnalyzePassageIdentity(
            clientRequestID: UUID().uuidString.lowercased(),
            documentID: document.id.uuidString,
            contentHash: contentHash
        )

        if let blockingMessage = await aiServiceAvailabilityGate.blockingMessage(for: .professorAnalysis) {
            return fallbackResult(
                document: document,
                bundle: bundle,
                structuredError: AIStructuredError(
                    kind: .upstream503,
                    requestID: identity.clientRequestID,
                    errorCode: "UPSTREAM_503",
                    retryable: true,
                    fallbackAvailable: true,
                    message: blockingMessage
                )
            )
        }

        let endpointURLs = AIExplainSentenceService.endpointCandidates(
            path: "ai/analyze-passage",
            overrideBaseURL: overrideBaseURL
        )
        guard !endpointURLs.isEmpty else {
            return fallbackResult(
                document: document,
                bundle: bundle,
                structuredError: AIStructuredError(
                    kind: .networkUnavailable,
                    requestID: identity.clientRequestID,
                    errorCode: "BACKEND_NOT_CONFIGURED",
                    retryable: true,
                    fallbackAvailable: true,
                    message: "AI 后端未配置，已展示本地结构骨架。"
                )
            )
        }

        let requestBody = AnalyzePassageRequest(
            identity: identity,
            title: title,
            paragraphs: paragraphInputs,
            questionBlocks: [],
            answerBlocks: [],
            vocabularyBlocks: []
        )
        let requestData = try JSONEncoder().encode(requestBody)

        return try await performAnalyzePassage(
            document: document,
            bundle: bundle,
            requestIdentity: identity,
            endpointURLs: endpointURLs,
            requestData: requestData,
            paragraphInputs: paragraphInputs
        )
    }

    private static func performAnalyzePassage(
        document: SourceDocument,
        bundle: StructuredSourceBundle,
        requestIdentity: AnalyzePassageIdentity,
        endpointURLs: [URL],
        requestData: Data,
        paragraphInputs: [ParagraphInput]
    ) async throws -> ProfessorAnalysisServiceResult {
        var lastError: Error?

        for (endpointIndex, endpointURL) in endpointURLs.enumerated() {
            for attempt in 0..<2 {
                var request = URLRequest(url: endpointURL)
                request.httpMethod = "POST"
                request.timeoutInterval = analyzePassageTimeout
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = requestData

                do {
                    try Task.checkCancellation()
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIExplainSentenceServiceError.invalidServerResponse
                    }

                    if AIExplainSentenceService.shouldRetrySameEndpoint(statusCode: httpResponse.statusCode), attempt == 0 {
                        try await Task.sleep(nanoseconds: AIExplainSentenceService.retryDelayNanoseconds(for: attempt))
                        continue
                    }

                    guard (200 ..< 300).contains(httpResponse.statusCode) else {
                        let structuredError = AIStructuredError.from(data: data, statusCode: httpResponse.statusCode)
                        let bodySnippet = String(data: data.prefix(500), encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        await aiServiceAvailabilityGate.recordFailure(
                            for: .professorAnalysis,
                            technicalReason: bodySnippet.isEmpty ? "HTTP \(httpResponse.statusCode)" : "HTTP \(httpResponse.statusCode): \(bodySnippet)",
                            cooldown: AIServiceAvailabilityPolicy.cooldown(for: httpResponse.statusCode)
                        )

                        if AIExplainSentenceService.shouldRetryEndpoint(statusCode: httpResponse.statusCode),
                           endpointIndex < endpointURLs.count - 1 {
                            lastError = structuredError.map(AIExplainSentenceServiceError.structured)
                                ?? AIExplainSentenceServiceError.requestFailed(
                                    bodySnippet.isEmpty ? "HTTP \(httpResponse.statusCode)" : "HTTP \(httpResponse.statusCode): \(bodySnippet)"
                                )
                            break
                        }

                        if let structuredError, structuredError.shouldUseLocalFallback {
                            return fallbackResult(
                                document: document,
                                bundle: bundle,
                                structuredError: structuredError,
                                meta: .localFallback()
                            )
                        }

                        throw structuredError.map(AIExplainSentenceServiceError.structured)
                            ?? AIExplainSentenceServiceError.requestFailed(
                                bodySnippet.isEmpty ? "HTTP \(httpResponse.statusCode)" : "HTTP \(httpResponse.statusCode): \(bodySnippet)"
                            )
                    }

                    let decoded = try decodeResponseEnvelope(
                        from: data,
                        bundle: bundle,
                        paragraphInputs: paragraphInputs
                    )

                    if decoded.success, let payload = decoded.data {
                        await aiServiceAvailabilityGate.recordSuccess(for: .professorAnalysis)
                        let delta = ProfessorAnalysisDelta(
                            schemaVersion: ProfessorAnalysisCacheStore.analysisSchemaVersion,
                            storedAt: Date(),
                            passageOverview: payload.overview,
                            paragraphCards: payload.paragraphCards,
                            sentenceCards: []
                        )
                        TextPipelineDiagnostics.log(
                            "AI",
                            [
                                "[AI][PassageMap] success",
                                "request_id=\(decoded.requestID ?? "nil")",
                                "provider=\(decoded.meta.provider ?? "nil")",
                                "model=\(decoded.meta.model ?? "nil")",
                                "retry_count=\(decoded.meta.retryCount)",
                                "used_cache=\(decoded.meta.usedCache)",
                                "used_fallback=\(decoded.meta.usedFallback)"
                            ].joined(separator: " "),
                            severity: .info
                        )
                        let enrichedBundle = bundle.enrichedWithAIAnalysis(
                            overview: payload.overview,
                            paragraphCards: payload.paragraphCards,
                            sentenceCards: []
                        )
                        return ProfessorAnalysisServiceResult(
                            delta: delta,
                            meta: decoded.meta,
                            requestID: decoded.requestID,
                            keySentenceIDs: payload.keySentenceIDs,
                            questionLinks: payload.questionLinks,
                            passageMap: enrichedBundle.passageMap,
                            admissionResult: enrichedBundle.mindMapAdmissionResult,
                            message: decoded.meta.usedFallback ? "AI 地图分析暂不可用，已展示本地结构骨架。" : nil,
                            structuredError: decoded.structuredError
                        )
                    }

                    if let structuredError = decoded.structuredError {
                        if structuredError.shouldUseLocalFallback {
                            return fallbackResult(
                                document: document,
                                bundle: bundle,
                                structuredError: structuredError,
                                meta: fallbackMeta(from: decoded.meta)
                            )
                        }
                        throw AIExplainSentenceServiceError.structured(structuredError)
                    }

                    return fallbackResult(
                        document: document,
                        bundle: bundle,
                        structuredError: AIStructuredError.invalidModelResponse(
                            message: "AI 地图分析返回内容不可解析。",
                            requestID: decoded.requestID
                        ),
                        meta: fallbackMeta(from: decoded.meta)
                    )
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
                        try await Task.sleep(nanoseconds: AIExplainSentenceService.retryDelayNanoseconds(for: attempt))
                        continue
                    }
                    if AIExplainSentenceService.shouldRetryEndpoint(for: error),
                       endpointIndex < endpointURLs.count - 1 {
                        lastError = AIExplainSentenceServiceError.transport(error.localizedDescription)
                        break
                    }
                    return fallbackResult(
                        document: document,
                        bundle: bundle,
                        structuredError: AIStructuredError.from(urlError: error)
                    )
                } catch let error as AIExplainSentenceServiceError {
                    if case .structured(let structuredError) = error, structuredError.shouldUseLocalFallback {
                        return fallbackResult(
                            document: document,
                            bundle: bundle,
                            structuredError: structuredError
                        )
                    }
                    if case .invalidServerResponse = error {
                        return fallbackResult(
                            document: document,
                            bundle: bundle,
                            structuredError: AIStructuredError.invalidModelResponse(message: "AI 地图分析返回内容不可解析。")
                        )
                    }
                    if endpointIndex < endpointURLs.count - 1 {
                        lastError = error
                        break
                    }
                    throw error
                } catch {
                    if endpointIndex < endpointURLs.count - 1 {
                        lastError = error
                        break
                    }
                    return fallbackResult(
                        document: document,
                        bundle: bundle,
                        structuredError: AIStructuredError.invalidModelResponse(message: "AI 地图分析返回内容不可解析。")
                    )
                }
            }
        }

        if let structuredError = (lastError as? AIExplainSentenceServiceError).flatMap({ error -> AIStructuredError? in
            if case .structured(let value) = error {
                return value
            }
            return nil
        }), structuredError.shouldUseLocalFallback {
            return fallbackResult(
                document: document,
                bundle: bundle,
                structuredError: structuredError
            )
        }

        if let error = lastError {
            throw error
        }

        return fallbackResult(
            document: document,
            bundle: bundle,
            structuredError: AIStructuredError.invalidModelResponse(message: "AI 地图分析返回内容不可解析。")
        )
    }

    private static func decodeResponseEnvelope(
        from data: Data,
        bundle: StructuredSourceBundle,
        paragraphInputs: [ParagraphInput]
    ) throws -> AnalyzePassageResponseEnvelope {
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

        let requestID = normalizedString(dictionary["request_id"] as? String)
        let meta = AIServiceResponseMeta.from(dictionary: dictionary["meta"] as? [String: Any])
        let structuredError = AIStructuredError.from(dictionary: dictionary, statusCode: nil)
        let success = dictionary["success"] as? Bool ?? false

        guard let payloadDictionary = dictionary["data"] as? [String: Any] else {
            return AnalyzePassageResponseEnvelope(
                success: success,
                requestID: requestID,
                meta: meta,
                data: nil,
                structuredError: structuredError
            )
        }

        let payload = normalizePayload(
            from: payloadDictionary,
            bundle: bundle,
            paragraphInputs: paragraphInputs
        )
        return AnalyzePassageResponseEnvelope(
            success: success,
            requestID: requestID,
            meta: meta,
            data: payload,
            structuredError: structuredError
        )
    }

    private static func normalizePayload(
        from dictionary: [String: Any],
        bundle: StructuredSourceBundle,
        paragraphInputs: [ParagraphInput]
    ) -> AnalyzePassagePayload? {
        let allowedSegmentIDs = Set(paragraphInputs.map(\.segmentID))
        let segmentIndex = Dictionary(uniqueKeysWithValues: bundle.segments.map { ($0.id, $0) })
        let sentencesBySegment = Dictionary(grouping: bundle.sentences, by: \.segmentID)

        let overview = (dictionary["passage_overview"] as? [String: Any]).map { payload in
            PassageOverview(
                articleTheme: normalizedString(payload["article_theme"] as? String) ?? "",
                authorCoreQuestion: normalizedString(payload["author_core_question"] as? String) ?? "",
                progressionPath: normalizedString(payload["progression_path"] as? String) ?? "",
                likelyQuestionTypes: stringArray(payload["likely_question_types"]),
                logicPitfalls: stringArray(payload["logic_pitfalls"]),
                paragraphFunctionMap: [],
                syntaxHighlights: [],
                readingTraps: [],
                vocabularyHighlights: []
            )
        }

        let paragraphCards = (dictionary["paragraph_cards"] as? [Any] ?? []).compactMap { item -> ParagraphTeachingCard? in
            guard let payload = item as? [String: Any] else { return nil }
            guard let segmentID = normalizedString(payload["segment_id"] as? String),
                  allowedSegmentIDs.contains(segmentID),
                  let segment = segmentIndex[segmentID]
            else {
                return nil
            }

            let provenance = payload["provenance"] as? [String: Any]
            let sourceKind = normalizedString(provenance?["source_kind"] as? String) ?? segment.provenance.sourceKind.rawValue
            guard sourceKind == SourceContentKind.passageBody.rawValue else {
                return nil
            }

            let sentenceIDs = Set(sentencesBySegment[segmentID]?.map(\.id) ?? [])
            let proposedCoreSentenceID = normalizedString(payload["core_sentence_id"] as? String)
            let coreSentenceID = proposedCoreSentenceID.flatMap { sentenceIDs.contains($0) ? $0 : nil }
                ?? sentencesBySegment[segmentID]?.first?.id

            return ParagraphTeachingCard(
                id: "ai_passage_\(segmentID)",
                segmentID: segmentID,
                paragraphIndex: (payload["paragraph_index"] as? Int) ?? segment.index,
                anchorLabel: normalizedString(payload["anchor_label"] as? String) ?? segment.anchorLabel,
                theme: normalizedString(payload["theme"] as? String) ?? truncated(segment.text, limit: 48),
                argumentRole: ParagraphArgumentRole(rawValue: normalizedString(payload["argument_role"] as? String) ?? "") ?? .support,
                coreSentenceID: coreSentenceID,
                keywords: [],
                relationToPrevious: normalizedString(payload["relation_to_previous"] as? String) ?? "",
                examValue: normalizedString(payload["exam_value"] as? String) ?? "",
                teachingFocuses: stringArray(payload["teaching_focuses"]),
                studentBlindSpot: normalizedString(payload["student_blind_spot"] as? String),
                isAIGenerated: true
            )
        }

        guard !paragraphCards.isEmpty || overview != nil else {
            return nil
        }

        let keySentenceIDs = Array(
            Array(Set(stringArray(dictionary["key_sentence_ids"]))).prefix(6)
        )

        return AnalyzePassagePayload(
            overview: overview,
            paragraphCards: paragraphCards,
            keySentenceIDs: keySentenceIDs,
            questionLinks: []
        )
    }

    private static func fallbackResult(
        document: SourceDocument,
        bundle: StructuredSourceBundle,
        structuredError: AIStructuredError,
        meta: AIServiceResponseMeta? = nil
    ) -> ProfessorAnalysisServiceResult {
        let fallback = LocalPassageFallbackBuilder.build(
            document: document,
            bundle: bundle,
            structuredError: structuredError,
            meta: meta ?? .localFallback()
        )

        TextPipelineDiagnostics.log(
            "AI",
            [
                "[AI][PassageMap] local fallback",
                "request_id=\(structuredError.requestID ?? "nil")",
                "error_code=\(structuredError.errorCode)",
                "retry_count=\(fallback.meta.retryCount)",
                "used_cache=\(fallback.meta.usedCache)",
                "used_fallback=\(fallback.meta.usedFallback)"
            ].joined(separator: " "),
            severity: .warning
        )

        let enrichedBundle = bundle.applyingProfessorAnalysis(fallback.delta)
        return ProfessorAnalysisServiceResult(
            delta: fallback.delta,
            meta: fallback.meta,
            requestID: structuredError.requestID,
            keySentenceIDs: fallback.keySentenceIDs,
            questionLinks: [],
            passageMap: enrichedBundle.passageMap,
            admissionResult: enrichedBundle.mindMapAdmissionResult,
            message: fallback.message,
            structuredError: structuredError
        )
    }

    private static func fallbackMeta(from meta: AIServiceResponseMeta) -> AIServiceResponseMeta {
        AIServiceResponseMeta(
            provider: meta.provider ?? "local_fallback",
            model: meta.model ?? "local_fallback",
            retryCount: meta.retryCount,
            usedCache: meta.usedCache,
            usedFallback: true,
            circuitState: meta.circuitState
        )
    }

    private static func buildParagraphInputs(from bundle: StructuredSourceBundle) -> [ParagraphInput] {
        candidateSegments(in: bundle).map { segment in
            ParagraphInput(
                segmentID: segment.id,
                index: segment.index,
                anchorLabel: segment.anchorLabel,
                text: truncated(segment.text, limit: maxParagraphCharacters),
                sourceKind: segment.provenance.sourceKind.rawValue,
                hygieneScore: segment.hygiene.score
            )
        }
    }

    private static func candidateSegments(in bundle: StructuredSourceBundle) -> [Segment] {
        let primary = bundle.segments.filter { $0.provenance.sourceKind == .passageBody }
        if !primary.isEmpty {
            return Array(primary.prefix(maxParagraphCount))
        }

        return Array(
            bundle.segments
                .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .prefix(maxParagraphCount)
        )
    }

    private static func stringArray(_ value: Any?) -> [String] {
        if let array = value as? [Any] {
            return array.compactMap { item in
                normalizedString(item as? String)
            }
        }
        if let string = normalizedString(value as? String) {
            return [string]
        }
        return []
    }

    private static func normalizedString(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func truncated(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit))
    }
}
