import Foundation

struct AIServiceResponseMeta: Codable, Equatable, Hashable {
    let provider: String?
    let model: String?
    let retryCount: Int
    let usedCache: Bool
    let usedFallback: Bool
    let circuitState: String

    private enum CodingKeys: String, CodingKey {
        case provider
        case model
        case retryCount = "retry_count"
        case usedCache = "used_cache"
        case usedFallback = "used_fallback"
        case circuitState = "circuit_state"
    }

    static let empty = AIServiceResponseMeta(
        provider: nil,
        model: nil,
        retryCount: 0,
        usedCache: false,
        usedFallback: false,
        circuitState: "closed"
    )

    static func from(dictionary: [String: Any]?) -> AIServiceResponseMeta {
        guard let dictionary else { return .empty }
        return AIServiceResponseMeta(
            provider: normalize(dictionary["provider"]),
            model: normalize(dictionary["model"]),
            retryCount: dictionary["retry_count"] as? Int ?? 0,
            usedCache: dictionary["used_cache"] as? Bool ?? false,
            usedFallback: dictionary["used_fallback"] as? Bool ?? false,
            circuitState: normalize(dictionary["circuit_state"]).isEmpty
                ? "closed"
                : normalize(dictionary["circuit_state"])
        )
    }

    static func localFallback(
        provider: String? = "local_fallback",
        model: String? = "local_fallback"
    ) -> AIServiceResponseMeta {
        AIServiceResponseMeta(
            provider: provider,
            model: model,
            retryCount: 0,
            usedCache: false,
            usedFallback: true,
            circuitState: "closed"
        )
    }

    private static func normalize(_ value: Any?) -> String {
        (value as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

enum AIStructuredErrorKind: String, Equatable, Hashable {
    case invalidRequest
    case modelConfigMissing
    case upstream503
    case upstreamTimeout
    case invalidModelResponse
    case payloadTooLarge
    case networkUnavailable
    case unknown
}

struct AIStructuredError: Error, Equatable, Hashable, LocalizedError {
    let kind: AIStructuredErrorKind
    let requestID: String?
    let errorCode: String
    let retryable: Bool
    let fallbackAvailable: Bool
    let message: String

    var errorDescription: String? { message }

    var shouldUseLocalFallback: Bool {
        switch kind {
        case .modelConfigMissing, .upstream503, .upstreamTimeout, .invalidModelResponse, .networkUnavailable:
            return true
        case .invalidRequest, .payloadTooLarge, .unknown:
            return fallbackAvailable
        }
    }

    var sentenceFallbackMessage: String {
        switch kind {
        case .modelConfigMissing:
            return "AI 服务暂未配置，已展示本地解析骨架。"
        case .upstream503, .upstreamTimeout, .networkUnavailable:
            if errorCode == "BACKEND_NOT_CONFIGURED" {
                return "AI 后端未配置，已展示本地解析骨架。"
            }
            return "AI 服务暂时繁忙，已展示本地解析骨架。"
        case .invalidModelResponse:
            return "AI 返回内容不可用，已展示本地解析骨架。"
        case .payloadTooLarge:
            return "当前句子请求过大，已展示本地解析骨架。"
        case .invalidRequest:
            return "当前句缺少可用锚点，已展示本地解析骨架。"
        case .unknown:
            return fallbackAvailable
                ? "AI 服务异常，已展示本地解析骨架。"
                : message
        }
    }

    var passageFallbackMessage: String {
        switch kind {
        case .modelConfigMissing:
            return "AI 地图分析暂未配置，已展示本地结构骨架。"
        case .upstream503, .upstreamTimeout, .networkUnavailable:
            if errorCode == "BACKEND_NOT_CONFIGURED" {
                return "AI 后端未配置，已展示本地结构骨架。"
            }
            return "AI 地图分析暂不可用，已展示本地结构骨架。"
        case .invalidModelResponse:
            return "AI 地图分析返回内容不可用，已展示本地结构骨架。"
        case .payloadTooLarge:
            return "当前全文请求过大，已展示本地结构骨架。"
        case .invalidRequest:
            return "当前全文缺少可用锚点，已展示本地结构骨架。"
        case .unknown:
            return fallbackAvailable
                ? "AI 地图分析异常，已展示本地结构骨架。"
                : message
        }
    }

    static func from(data: Data, statusCode: Int?) -> AIStructuredError? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }

        return from(dictionary: dictionary, statusCode: statusCode)
    }

    static func from(dictionary: [String: Any], statusCode: Int?) -> AIStructuredError? {
        let errorCode = normalize(dictionary["error_code"] as? String)
        let message = normalize(dictionary["message"] as? String)
        let success = dictionary["success"] as? Bool

        if success == true, errorCode.isEmpty, message.isEmpty {
            return nil
        }

        let resolvedCode = !errorCode.isEmpty
            ? errorCode
            : (statusCode.map { "HTTP_\($0)" } ?? "UNKNOWN")
        let kind = mapKind(errorCode: resolvedCode, statusCode: statusCode)

        return AIStructuredError(
            kind: kind,
            requestID: normalize(dictionary["request_id"] as? String).isEmpty ? nil : normalize(dictionary["request_id"] as? String),
            errorCode: resolvedCode,
            retryable: dictionary["retryable"] as? Bool ?? false,
            fallbackAvailable: dictionary["fallback_available"] as? Bool ?? false,
            message: message.isEmpty ? defaultMessage(for: kind) : message
        )
    }

    static func from(urlError: URLError) -> AIStructuredError {
        let isTimeout = urlError.code == .timedOut
        return AIStructuredError(
            kind: isTimeout ? .upstreamTimeout : .networkUnavailable,
            requestID: nil,
            errorCode: isTimeout ? "UPSTREAM_TIMEOUT" : "NETWORK_UNAVAILABLE",
            retryable: true,
            fallbackAvailable: true,
            message: isTimeout ? "AI 服务请求超时。" : "当前网络不可用。"
        )
    }

    static func invalidRequest(
        message: String,
        requestID: String? = nil,
        fallbackAvailable: Bool = true
    ) -> AIStructuredError {
        AIStructuredError(
            kind: .invalidRequest,
            requestID: requestID,
            errorCode: "INVALID_REQUEST",
            retryable: false,
            fallbackAvailable: fallbackAvailable,
            message: message
        )
    }

    static func invalidModelResponse(
        message: String,
        requestID: String? = nil
    ) -> AIStructuredError {
        AIStructuredError(
            kind: .invalidModelResponse,
            requestID: requestID,
            errorCode: "INVALID_MODEL_RESPONSE",
            retryable: true,
            fallbackAvailable: true,
            message: message
        )
    }

    private static func normalize(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func mapKind(errorCode: String, statusCode: Int?) -> AIStructuredErrorKind {
        switch errorCode.uppercased() {
        case "INVALID_REQUEST":
            return .invalidRequest
        case "MODEL_CONFIG_MISSING":
            return .modelConfigMissing
        case "UPSTREAM_503":
            return .upstream503
        case "UPSTREAM_TIMEOUT":
            return .upstreamTimeout
        case "INVALID_MODEL_RESPONSE":
            return .invalidModelResponse
        case "PAYLOAD_TOO_LARGE":
            return .payloadTooLarge
        default:
            if statusCode == 503 { return .upstream503 }
            if statusCode == 504 || statusCode == 408 { return .upstreamTimeout }
            return .unknown
        }
    }

    private static func defaultMessage(for kind: AIStructuredErrorKind) -> String {
        switch kind {
        case .invalidRequest:
            return "请求参数无效。"
        case .modelConfigMissing:
            return "AI 服务配置缺失。"
        case .upstream503:
            return "AI 服务暂时繁忙。"
        case .upstreamTimeout:
            return "AI 服务请求超时。"
        case .invalidModelResponse:
            return "AI 返回内容格式异常。"
        case .payloadTooLarge:
            return "请求内容过大。"
        case .networkUnavailable:
            return "当前网络不可用。"
        case .unknown:
            return "AI 服务暂时不可用。"
        }
    }
}
