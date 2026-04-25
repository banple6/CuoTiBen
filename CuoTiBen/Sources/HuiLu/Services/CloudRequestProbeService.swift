import Foundation

struct CloudRequestProbeResult: Identifiable, Equatable {
    enum Scope: String, CaseIterable {
        case health = "health"
        case explainSentence = "explain-sentence"
        case analyzePassage = "analyze-passage"

        var displayName: String {
            switch self {
            case .health: return "GET /health"
            case .explainSentence: return "POST /ai/explain-sentence"
            case .analyzePassage: return "POST /ai/analyze-passage"
            }
        }
    }

    let id = UUID()
    let scope: Scope
    let endpoint: String
    let httpStatus: Int?
    let requestID: String?
    let errorCode: String?
    let retryable: Bool?
    let fallbackAvailable: Bool?
    let usedFallback: Bool?
    let latencyMs: Int
    let identityComplete: Bool
    let missingFields: [String]
    let message: String?
    let timestamp: Date

    var statusText: String {
        if let httpStatus {
            return "HTTP \(httpStatus)"
        }
        return "未请求"
    }
}

enum CloudRequestProbeService {
    static func runHealthProbe() async -> CloudRequestProbeResult {
        guard let endpointURL = AIBackendConfig.endpointURL(path: "health") else {
            return notConfiguredResult(scope: .health, identityComplete: true, missingFields: [])
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        return await performProbe(
            scope: .health,
            request: request,
            identityComplete: true,
            missingFields: []
        )
    }

    static func runExplainProbe() async -> CloudRequestProbeResult {
        let sentence = "Careful readers connect sentence structure with the writer's main claim."
        let payload: [String: Any] = [
            "client_request_id": "probe-explain-\(UUID().uuidString.lowercased())",
            "document_id": "probe-document",
            "sentence_id": "probe-sentence-1",
            "segment_id": "probe-segment-1",
            "sentence_text_hash": AIRequestIdentity.hash(text: sentence),
            "anchor_label": "Probe 1",
            "title": "Cloud Probe",
            "sentence": sentence,
            "context": sentence,
            "paragraph_theme": "Probe paragraph",
            "paragraph_role": "claim",
            "question_prompt": ""
        ]
        let missingFields = missingFields(
            in: payload,
            required: [
                "client_request_id",
                "document_id",
                "sentence_id",
                "segment_id",
                "sentence_text_hash",
                "anchor_label"
            ]
        )

        guard let endpointURL = AIBackendConfig.endpointURL(path: "ai/explain-sentence") else {
            return notConfiguredResult(scope: .explainSentence, identityComplete: missingFields.isEmpty, missingFields: missingFields)
        }
        return await performJSONProbe(
            scope: .explainSentence,
            endpointURL: endpointURL,
            payload: payload,
            identityComplete: missingFields.isEmpty,
            missingFields: missingFields
        )
    }

    static func runAnalyzeProbe() async -> CloudRequestProbeResult {
        let paragraph = "Public trust now depends not only on clean air but also on transparent algorithms that shape shared decisions."
        let payload: [String: Any] = [
            "client_request_id": "probe-passage-\(UUID().uuidString.lowercased())",
            "document_id": "probe-document",
            "content_hash": PassageAnalysisIdentity.contentHash(forParagraphTexts: [paragraph]),
            "title": "Cloud Probe",
            "paragraphs": [
                [
                    "segment_id": "probe-segment-1",
                    "index": 0,
                    "anchor_label": "Probe P1",
                    "text": paragraph,
                    "source_kind": SourceContentKind.passageBody.rawValue,
                    "hygiene_score": 0.96
                ]
            ],
            "question_blocks": [],
            "answer_blocks": [],
            "vocabulary_blocks": []
        ]
        let missingFields = analyzeProbeMissingFields(payload: payload)

        guard let endpointURL = AIBackendConfig.endpointURL(path: "ai/analyze-passage") else {
            return notConfiguredResult(scope: .analyzePassage, identityComplete: missingFields.isEmpty, missingFields: missingFields)
        }
        return await performJSONProbe(
            scope: .analyzePassage,
            endpointURL: endpointURL,
            payload: payload,
            identityComplete: missingFields.isEmpty,
            missingFields: missingFields
        )
    }

    private static func performJSONProbe(
        scope: CloudRequestProbeResult.Scope,
        endpointURL: URL,
        payload: [String: Any],
        identityComplete: Bool,
        missingFields: [String]
    ) async -> CloudRequestProbeResult {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])
        return await performProbe(
            scope: scope,
            request: request,
            identityComplete: identityComplete,
            missingFields: missingFields
        )
    }

    private static func performProbe(
        scope: CloudRequestProbeResult.Scope,
        request: URLRequest,
        identityComplete: Bool,
        missingFields: [String]
    ) async -> CloudRequestProbeResult {
        let startedAt = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let latency = Int(Date().timeIntervalSince(startedAt) * 1000)
            let httpStatus = (response as? HTTPURLResponse)?.statusCode
            let envelope = ResponseEnvelope(data: data)
            let result = CloudRequestProbeResult(
                scope: scope,
                endpoint: request.url?.absoluteString ?? "nil",
                httpStatus: httpStatus,
                requestID: envelope.requestID,
                errorCode: envelope.errorCode,
                retryable: envelope.retryable,
                fallbackAvailable: envelope.fallbackAvailable,
                usedFallback: envelope.usedFallback,
                latencyMs: latency,
                identityComplete: identityComplete,
                missingFields: missingFields,
                message: envelope.message,
                timestamp: Date()
            )
            log(result)
            return result
        } catch {
            let latency = Int(Date().timeIntervalSince(startedAt) * 1000)
            let result = CloudRequestProbeResult(
                scope: scope,
                endpoint: request.url?.absoluteString ?? "nil",
                httpStatus: nil,
                requestID: nil,
                errorCode: "NETWORK_ERROR",
                retryable: true,
                fallbackAvailable: true,
                usedFallback: nil,
                latencyMs: latency,
                identityComplete: identityComplete,
                missingFields: missingFields,
                message: error.localizedDescription,
                timestamp: Date()
            )
            log(result)
            return result
        }
    }

    private static func notConfiguredResult(
        scope: CloudRequestProbeResult.Scope,
        identityComplete: Bool,
        missingFields: [String]
    ) -> CloudRequestProbeResult {
        let result = CloudRequestProbeResult(
            scope: scope,
            endpoint: "unconfigured",
            httpStatus: nil,
            requestID: nil,
            errorCode: "BACKEND_NOT_CONFIGURED",
            retryable: true,
            fallbackAvailable: true,
            usedFallback: nil,
            latencyMs: 0,
            identityComplete: identityComplete,
            missingFields: missingFields,
            message: "AI 后端未配置。",
            timestamp: Date()
        )
        log(result)
        return result
    }

    private static func log(_ result: CloudRequestProbeResult) {
        TextPipelineDiagnostics.log(
            "CloudProbe",
            [
                "[CloudProbe]",
                "scope=\(result.scope.rawValue)",
                "endpoint=\(result.endpoint)",
                "http_status=\(result.httpStatus.map(String.init) ?? "nil")",
                "request_id=\(result.requestID ?? "nil")",
                "error_code=\(result.errorCode ?? "nil")",
                "retryable=\(result.retryable.map { $0 ? "true" : "false" } ?? "nil")",
                "fallback_available=\(result.fallbackAvailable.map { $0 ? "true" : "false" } ?? "nil")",
                "used_fallback=\(result.usedFallback.map { $0 ? "true" : "false" } ?? "nil")",
                "latency_ms=\(result.latencyMs)",
                "identity_complete=\(result.identityComplete)",
                "missing_fields=\(result.missingFields.isEmpty ? "[]" : result.missingFields.joined(separator: ","))"
            ].joined(separator: " "),
            severity: (result.httpStatus ?? 0) >= 200 && (result.httpStatus ?? 0) < 300 ? .info : .warning
        )
    }

    private static func missingFields(in payload: [String: Any], required fields: [String]) -> [String] {
        fields.filter { field in
            guard let value = payload[field] as? String else { return true }
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func analyzeProbeMissingFields(payload: [String: Any]) -> [String] {
        var missing = missingFields(in: payload, required: ["client_request_id", "document_id", "content_hash"])
        guard let paragraphs = payload["paragraphs"] as? [[String: Any]], !paragraphs.isEmpty else {
            missing.append("paragraphs")
            return missing
        }
        for (index, paragraph) in paragraphs.enumerated() {
            for field in ["segment_id", "anchor_label", "text", "source_kind"] {
                if (paragraph[field] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                    missing.append("paragraphs[\(index)].\(field)")
                }
            }
            if paragraph["index"] as? Int == nil {
                missing.append("paragraphs[\(index)].index")
            }
            if let score = paragraph["hygiene_score"] as? Double {
                if !score.isFinite || score < 0 || score > 1 {
                    missing.append("paragraphs[\(index)].hygiene_score")
                }
            } else {
                missing.append("paragraphs[\(index)].hygiene_score")
            }
        }
        return missing
    }
}

private struct ResponseEnvelope {
    let requestID: String?
    let errorCode: String?
    let retryable: Bool?
    let fallbackAvailable: Bool?
    let usedFallback: Bool?
    let message: String?

    init(data: Data) {
        let object = (try? JSONSerialization.jsonObject(with: data)) as Any
        requestID = Self.findString(in: object, keys: ["request_id", "requestId"])
        errorCode = Self.findString(in: object, keys: ["error_code", "errorCode", "code"])
        retryable = Self.findBool(in: object, keys: ["retryable"])
        fallbackAvailable = Self.findBool(in: object, keys: ["fallback_available", "fallbackAvailable"])
        usedFallback = Self.findBool(in: object, keys: ["used_fallback", "usedFallback"])
        message = Self.findString(in: object, keys: ["message", "error"])
    }

    private static func findString(in object: Any, keys: Set<String>) -> String? {
        if let dictionary = object as? [String: Any] {
            for key in keys {
                if let value = dictionary[key] as? String, !value.isEmpty {
                    return value
                }
            }
            for value in dictionary.values {
                if let found = findString(in: value, keys: keys) {
                    return found
                }
            }
        } else if let array = object as? [Any] {
            for item in array {
                if let found = findString(in: item, keys: keys) {
                    return found
                }
            }
        }
        return nil
    }

    private static func findBool(in object: Any, keys: Set<String>) -> Bool? {
        if let dictionary = object as? [String: Any] {
            for key in keys {
                if let value = dictionary[key] as? Bool {
                    return value
                }
            }
            for value in dictionary.values {
                if let found = findBool(in: value, keys: keys) {
                    return found
                }
            }
        } else if let array = object as? [Any] {
            for item in array {
                if let found = findBool(in: item, keys: keys) {
                    return found
                }
            }
        }
        return nil
    }
}
