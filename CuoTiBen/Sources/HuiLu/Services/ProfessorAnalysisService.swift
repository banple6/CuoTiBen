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
    let analysisDiagnostics: PassageAnalysisDiagnostics

    var usedFallback: Bool { meta.usedFallback }
}

enum ProfessorAnalysisService {
    private static let analyzePassageTimeout: TimeInterval = 150
    private static let activeCallPath = "ProfessorAnalysisService.enrichBundle"

    private struct AnalyzePassageResponseEnvelope {
        let success: Bool
        let requestID: String?
        let meta: AIServiceResponseMeta
        let data: AnalyzePassagePayload?
        let identity: PassageAnalysisIdentity?
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
        let materialDecision = MaterialAnalysisGate.evaluate(document: document, bundle: bundle)
        let requestBuild = AnalyzePassageRequestBuilder.build(
            document: document,
            bundle: bundle,
            title: title,
            decision: materialDecision,
            activeCallPath: activeCallPath
        )

        logRequestPreparation(requestBuild.diagnostics)
        if requestBuild.diagnostics.requestBuilderUsed,
           !requestBuild.diagnostics.contractPreflightPassed {
            logContractPreflightFailure(requestBuild.diagnostics)
        }

        guard let requestBody = requestBuild.payload else {
            return fallbackResult(
                document: document,
                bundle: bundle,
                diagnostics: requestBuild.diagnostics,
                structuredError: AIStructuredError.invalidRequest(
                    message: requestBuild.diagnostics.fallbackMessage,
                    requestID: requestBuild.diagnostics.clientRequestID,
                    fallbackAvailable: true
                ),
                meta: AIServiceResponseMeta.localFallback()
            )
        }

        if let blockingMessage = await aiServiceAvailabilityGate.blockingMessage(for: .professorAnalysis) {
            return fallbackResult(
                document: document,
                bundle: bundle,
                diagnostics: requestBuild.diagnostics,
                structuredError: AIStructuredError(
                    kind: .upstream503,
                    requestID: requestBuild.diagnostics.clientRequestID,
                    errorCode: "UPSTREAM_503",
                    retryable: true,
                    fallbackAvailable: true,
                    message: blockingMessage
                ),
                meta: AIServiceResponseMeta.localFallback()
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
                diagnostics: requestBuild.diagnostics,
                structuredError: AIStructuredError(
                    kind: .networkUnavailable,
                    requestID: requestBuild.diagnostics.clientRequestID,
                    errorCode: "BACKEND_NOT_CONFIGURED",
                    retryable: true,
                    fallbackAvailable: true,
                    message: "AI 后端未配置，已展示本地结构骨架。"
                ),
                meta: AIServiceResponseMeta.localFallback()
            )
        }

        let requestData = try JSONEncoder().encode(requestBody)

        return try await performAnalyzePassage(
            document: document,
            bundle: bundle,
            requestBuild: requestBuild,
            endpointURLs: endpointURLs,
            requestData: requestData
        )
    }

    private static func performAnalyzePassage(
        document: SourceDocument,
        bundle: StructuredSourceBundle,
        requestBuild: AnalyzePassageRequestBuildResult,
        endpointURLs: [URL],
        requestData: Data
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

                        if let structuredError,
                           structuredError.errorCode == "INVALID_REQUEST",
                           structuredError.message.contains("缺少 passage identity 字段") {
                            logMissingIdentityBug(
                                diagnostics: requestBuild.diagnostics.withFlags(
                                    requestBuilderUsed: true,
                                    missingIdentity: true
                                ),
                                structuredError: structuredError
                            )
                            return fallbackResult(
                                document: document,
                                bundle: bundle,
                                diagnostics: requestBuild.diagnostics.withFlags(
                                    requestBuilderUsed: true,
                                    missingIdentity: true
                                ),
                                structuredError: structuredError,
                                meta: AIServiceResponseMeta.localFallback()
                            )
                        }

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
                                diagnostics: requestBuild.diagnostics,
                                structuredError: structuredError,
                                meta: AIServiceResponseMeta.localFallback()
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
                        acceptedParagraphs: requestBuild.payload?.paragraphs ?? []
                    )

                    if decoded.success, let payload = decoded.data {
                        let expectedIdentity = requestBuild.expectedIdentity ?? PassageAnalysisIdentity.make(
                            document: document,
                            bundle: bundle,
                            materialMode: requestBuild.diagnostics.materialMode,
                            acceptedParagraphCount: requestBuild.diagnostics.acceptedParagraphCount,
                            contentHash: requestBuild.diagnostics.contentHash
                        )
                        let actualIdentity = decoded.identity ?? expectedIdentity
                        let identityDecision = PassageAnalysisIdentityGuard.validate(
                            expected: expectedIdentity,
                            actual: actualIdentity
                        )
                        PassageAnalysisIdentityGuard.logDecision(
                            requestID: decoded.requestID,
                            expected: expectedIdentity,
                            actual: actualIdentity,
                            decision: identityDecision
                        )
                        guard identityDecision.isAllowed else {
                            return fallbackResult(
                                document: document,
                                bundle: bundle,
                                diagnostics: requestBuild.diagnostics,
                                structuredError: AIStructuredError.invalidModelResponse(
                                    message: "AI 地图分析身份与当前资料不一致，已展示本地结构骨架。",
                                    requestID: decoded.requestID
                                ),
                                meta: AIServiceResponseMeta.localFallback()
                            )
                        }

                        await aiServiceAvailabilityGate.recordSuccess(for: .professorAnalysis)
                        let delta = ProfessorAnalysisDelta(
                            schemaVersion: ProfessorAnalysisCacheStore.analysisSchemaVersion,
                            storedAt: Date(),
                            passageOverview: payload.overview,
                            paragraphCards: payload.paragraphCards,
                            sentenceCards: [],
                            passageAnalysisDiagnostics: requestBuild.diagnostics,
                            passageAnalysisIdentity: expectedIdentity
                        )
                        TextPipelineDiagnostics.log(
                            "AI",
                            successLogFields(
                                diagnostics: requestBuild.diagnostics,
                                requestID: decoded.requestID,
                                meta: decoded.meta
                            ).joined(separator: " "),
                            severity: .info
                        )
                        let enrichedBundle = bundle.enrichedWithAIAnalysis(
                            overview: payload.overview,
                            paragraphCards: payload.paragraphCards,
                            sentenceCards: [],
                            passageAnalysisDiagnostics: requestBuild.diagnostics,
                            passageAnalysisIdentity: expectedIdentity
                        )
                        return ProfessorAnalysisServiceResult(
                            delta: delta,
                            meta: decoded.meta,
                            requestID: decoded.requestID,
                            keySentenceIDs: payload.keySentenceIDs,
                            questionLinks: payload.questionLinks,
                            passageMap: enrichedBundle.passageMap,
                            admissionResult: enrichedBundle.mindMapAdmissionResult,
                            message: decoded.meta.usedFallback ? requestBuild.diagnostics.fallbackMessage : nil,
                            structuredError: decoded.structuredError,
                            analysisDiagnostics: requestBuild.diagnostics
                        )
                    }

                    if let structuredError = decoded.structuredError {
                        if structuredError.shouldUseLocalFallback {
                            return fallbackResult(
                                document: document,
                                bundle: bundle,
                                diagnostics: requestBuild.diagnostics,
                                structuredError: structuredError,
                                meta: fallbackMeta(from: decoded.meta)
                            )
                        }
                        throw AIExplainSentenceServiceError.structured(structuredError)
                    }

                    return fallbackResult(
                        document: document,
                        bundle: bundle,
                        diagnostics: requestBuild.diagnostics,
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
                        diagnostics: requestBuild.diagnostics,
                        structuredError: AIStructuredError.from(urlError: error),
                        meta: AIServiceResponseMeta.localFallback()
                    )
                } catch let error as AIExplainSentenceServiceError {
                    if case .structured(let structuredError) = error, structuredError.shouldUseLocalFallback {
                        return fallbackResult(
                            document: document,
                            bundle: bundle,
                            diagnostics: requestBuild.diagnostics,
                            structuredError: structuredError,
                            meta: AIServiceResponseMeta.localFallback()
                        )
                    }
                    if case .invalidServerResponse = error {
                        return fallbackResult(
                            document: document,
                            bundle: bundle,
                            diagnostics: requestBuild.diagnostics,
                            structuredError: AIStructuredError.invalidModelResponse(message: "AI 地图分析返回内容不可解析。"),
                            meta: AIServiceResponseMeta.localFallback()
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
                        diagnostics: requestBuild.diagnostics,
                        structuredError: AIStructuredError.invalidModelResponse(message: "AI 地图分析返回内容不可解析。"),
                        meta: AIServiceResponseMeta.localFallback()
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
                diagnostics: requestBuild.diagnostics,
                structuredError: structuredError,
                meta: AIServiceResponseMeta.localFallback()
            )
        }

        if let error = lastError {
            throw error
        }

        return fallbackResult(
            document: document,
            bundle: bundle,
            diagnostics: requestBuild.diagnostics,
            structuredError: AIStructuredError.invalidModelResponse(message: "AI 地图分析返回内容不可解析。"),
            meta: AIServiceResponseMeta.localFallback()
        )
    }

    private static func decodeResponseEnvelope(
        from data: Data,
        bundle: StructuredSourceBundle,
        acceptedParagraphs: [AnalyzePassageParagraphPayload]
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
                identity: responseIdentity(from: dictionary, payloadDictionary: nil),
                structuredError: structuredError
            )
        }

        let payload = normalizePayload(
            from: payloadDictionary,
            bundle: bundle,
            acceptedParagraphs: acceptedParagraphs
        )
        return AnalyzePassageResponseEnvelope(
            success: success,
            requestID: requestID,
            meta: meta,
            data: payload,
            identity: responseIdentity(from: dictionary, payloadDictionary: payloadDictionary),
            structuredError: structuredError
        )
    }

    private static func normalizePayload(
        from dictionary: [String: Any],
        bundle: StructuredSourceBundle,
        acceptedParagraphs: [AnalyzePassageParagraphPayload]
    ) -> AnalyzePassagePayload? {
        let allowedSegmentIDs = Set(acceptedParagraphs.map { $0.segmentID })
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
        diagnostics: PassageAnalysisDiagnostics,
        structuredError: AIStructuredError,
        meta: AIServiceResponseMeta? = nil
    ) -> ProfessorAnalysisServiceResult {
        let fallback = LocalPassageFallbackBuilder.build(
            document: document,
            bundle: bundle,
            diagnostics: diagnostics,
            structuredError: structuredError,
            meta: meta ?? AIServiceResponseMeta.localFallback()
        )

        TextPipelineDiagnostics.log(
            "AI",
            fallbackLogFields(
                diagnostics: fallback.analysisDiagnostics,
                requestID: structuredError.requestID,
                errorCode: structuredError.errorCode,
                meta: fallback.meta
            ).joined(separator: " "),
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
            structuredError: structuredError,
            analysisDiagnostics: fallback.analysisDiagnostics
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

    private static func logRequestPreparation(_ diagnostics: PassageAnalysisDiagnostics) {
        TextPipelineDiagnostics.log(
            "AI",
            [
                "[AI][PassageMap] request_prepared",
                "client_request_id=\(diagnostics.clientRequestID ?? "nil")",
                "document_id=\(diagnostics.documentID)",
                "active_call_path=\(diagnostics.activeCallPath)",
                "content_hash=\(diagnostics.contentHash ?? "nil")",
                "accepted_paragraph_count=\(diagnostics.acceptedParagraphCount)",
                "rejected_paragraph_count=\(diagnostics.rejectedParagraphCount)",
                String(format: "non_passage_ratio=%.2f", diagnostics.nonPassageRatio),
                "material_mode=\(diagnostics.materialMode.rawValue)",
                "reason=\(diagnostics.reasonFlags.isEmpty ? diagnostics.reason : diagnostics.reasonFlags.joined(separator: "||"))",
                "request_builder_used=\(diagnostics.requestBuilderUsed)",
                "contract_preflight_passed=\(diagnostics.contractPreflightPassed)",
                "missing_fields=\(formatMissingFields(diagnostics.missingFields))",
                "final_segments_count=\(diagnostics.finalSegmentsCount)",
                "final_sentences_count=\(diagnostics.finalSentencesCount)",
                "passage_body_paragraph_count=\(diagnostics.passageBodyParagraphCount)",
                "used_fallback=\(!diagnostics.contractPreflightPassed)"
            ].joined(separator: " "),
            severity: diagnostics.requestBuilderUsed ? .info : .warning
        )
    }

    private static func logContractPreflightFailure(_ diagnostics: PassageAnalysisDiagnostics) {
        TextPipelineDiagnostics.log(
            "AI",
            [
                "[AI][PassageMap] contract_preflight_failed",
                "missingFields=\(formatMissingFields(diagnostics.missingFields))",
                "requestBuilderUsed=true",
                "activeCallPath=\(diagnostics.activeCallPath)",
                "client_request_id=\(diagnostics.clientRequestID ?? "nil")",
                "document_id=\(diagnostics.documentID)",
                "content_hash=\(diagnostics.contentHash ?? "nil")",
                "accepted_paragraph_count=\(diagnostics.acceptedParagraphCount)",
                "material_mode=\(diagnostics.materialMode.rawValue)",
                "used_fallback=true"
            ].joined(separator: " "),
            severity: .error
        )
    }

    private static func logMissingIdentityBug(
        diagnostics: PassageAnalysisDiagnostics,
        structuredError: AIStructuredError
    ) {
        TextPipelineDiagnostics.log(
            "AI",
            [
                "[AI][PassageMap] identity_bug",
                "request_id=\(structuredError.requestID ?? "nil")",
                "client_request_id=\(diagnostics.clientRequestID ?? "nil")",
                "document_id=\(diagnostics.documentID)",
                "active_call_path=\(diagnostics.activeCallPath)",
                "content_hash=\(diagnostics.contentHash ?? "nil")",
                "accepted_paragraph_count=\(diagnostics.acceptedParagraphCount)",
                "material_mode=\(diagnostics.materialMode.rawValue)",
                "request_builder_used=\(diagnostics.requestBuilderUsed)",
                "missing_identity=true",
                "used_fallback=true",
                "error_code=\(structuredError.errorCode)"
            ].joined(separator: " "),
            severity: .error
        )
    }

    private static func successLogFields(
        diagnostics: PassageAnalysisDiagnostics,
        requestID: String?,
        meta: AIServiceResponseMeta
    ) -> [String] {
        [
            "[AI][PassageMap] success",
            "request_id=\(requestID ?? "nil")",
            "client_request_id=\(diagnostics.clientRequestID ?? "nil")",
            "document_id=\(diagnostics.documentID)",
            "active_call_path=\(diagnostics.activeCallPath)",
            "content_hash=\(diagnostics.contentHash ?? "nil")",
            "accepted_paragraph_count=\(diagnostics.acceptedParagraphCount)",
            "rejected_paragraph_count=\(diagnostics.rejectedParagraphCount)",
            String(format: "non_passage_ratio=%.2f", diagnostics.nonPassageRatio),
            "material_mode=\(diagnostics.materialMode.rawValue)",
            "reason=\(diagnostics.reasonFlags.isEmpty ? diagnostics.reason : diagnostics.reasonFlags.joined(separator: "||"))",
            "request_builder_used=\(diagnostics.requestBuilderUsed)",
            "contract_preflight_passed=\(diagnostics.contractPreflightPassed)",
            "missing_fields=\(formatMissingFields(diagnostics.missingFields))",
            "provider=\(meta.provider ?? "nil")",
            "model=\(meta.model ?? "nil")",
            "retry_count=\(meta.retryCount)",
            "used_cache=\(meta.usedCache)",
            "used_fallback=\(meta.usedFallback)",
            "circuit_state=\(meta.circuitState)"
        ]
    }

    private static func fallbackLogFields(
        diagnostics: PassageAnalysisDiagnostics,
        requestID: String?,
        errorCode: String,
        meta: AIServiceResponseMeta
    ) -> [String] {
        [
            "[AI][PassageMap] local fallback",
            "request_id=\(requestID ?? "nil")",
            "client_request_id=\(diagnostics.clientRequestID ?? "nil")",
            "document_id=\(diagnostics.documentID)",
            "active_call_path=\(diagnostics.activeCallPath)",
            "content_hash=\(diagnostics.contentHash ?? "nil")",
            "accepted_paragraph_count=\(diagnostics.acceptedParagraphCount)",
            "rejected_paragraph_count=\(diagnostics.rejectedParagraphCount)",
            String(format: "non_passage_ratio=%.2f", diagnostics.nonPassageRatio),
            "material_mode=\(diagnostics.materialMode.rawValue)",
            "reason=\(diagnostics.reasonFlags.isEmpty ? diagnostics.reason : diagnostics.reasonFlags.joined(separator: "||"))",
            "request_builder_used=\(diagnostics.requestBuilderUsed)",
            "contract_preflight_passed=\(diagnostics.contractPreflightPassed)",
            "missing_fields=\(formatMissingFields(diagnostics.missingFields))",
            "error_code=\(errorCode)",
            "retry_count=\(meta.retryCount)",
            "used_cache=\(meta.usedCache)",
            "used_fallback=\(meta.usedFallback)",
            "circuit_state=\(meta.circuitState)"
        ]
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

    private static func responseIdentity(
        from dictionary: [String: Any],
        payloadDictionary: [String: Any]?
    ) -> PassageAnalysisIdentity? {
        PassageAnalysisIdentity(dictionary: dictionary["identity"] as? [String: Any])
            ?? PassageAnalysisIdentity(dictionary: payloadDictionary?["identity"] as? [String: Any])
    }

    private static func formatMissingFields(_ fields: [String]) -> String {
        fields.isEmpty ? "[]" : "[\(fields.joined(separator: ","))]"
    }

    private static func truncated(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit))
    }
}
