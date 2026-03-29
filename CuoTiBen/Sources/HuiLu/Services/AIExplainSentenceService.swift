import Foundation

struct ExplainSentenceContext: Equatable {
    let title: String
    let sentence: String
    let context: String
}

struct AIExplainSentenceResult: Decodable, Equatable {
    struct GrammarPoint: Decodable, Equatable {
        let name: String
        let explanation: String
    }

    struct KeyTerm: Decodable, Equatable {
        let term: String
        let meaning: String
    }

    let translation: String
    let mainStructure: String
    let grammarPoints: [GrammarPoint]
    let keyTerms: [KeyTerm]
    let rewriteExample: String

    private enum CodingKeys: String, CodingKey {
        case translation
        case mainStructure = "main_structure"
        case grammarPoints = "grammar_points"
        case keyTerms = "key_terms"
        case rewriteExample = "rewrite_example"
    }
}

private struct ExplainSentenceRequest: Encodable {
    let title: String
    let sentence: String
    let context: String
}

private struct ExplainSentenceResponseEnvelope: Decodable {
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

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ExplainSentenceRequest(
                title: context.title,
                sentence: context.sentence,
                context: context.context
            )
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIExplainSentenceServiceError.invalidServerResponse
            }

            let decoded = try JSONDecoder().decode(ExplainSentenceResponseEnvelope.self, from: data)

            if httpResponse.statusCode == 200, decoded.success, let result = decoded.data {
                return result
            }

            if let message = decoded.error, !message.isEmpty {
                throw AIExplainSentenceServiceError.requestFailed(message)
            }

            throw AIExplainSentenceServiceError.invalidServerResponse
        } catch let error as AIExplainSentenceServiceError {
            throw error
        } catch let error as DecodingError {
            print("[AIExplainSentenceService] decode failed: \(error)")
            throw AIExplainSentenceServiceError.invalidServerResponse
        } catch {
            throw AIExplainSentenceServiceError.transport(error.localizedDescription)
        }
    }
}
