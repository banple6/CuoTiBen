import Foundation

// MARK: - 文档解析服务客户端
// 负责与自有后端通信，后端代理调用 PP-StructureV3
// Token 存放在后端环境变量中，客户端不接触任何 AI Studio 凭据

enum DocumentParseServiceError: LocalizedError {
    case remoteUnavailable
    case missingBackendURL
    case invalidBackendURL
    case uploadFailed(String)
    case parseFailed(String)
    case legacySchema(String)
    case pollTimeout
    case invalidResponse
    case jobNotFound
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .remoteUnavailable: return "文档解析后端未配置，已跳过远端 PP 解析"
        case .missingBackendURL:    return "后端地址未配置"
        case .invalidBackendURL:    return "后端地址格式无效"
        case .uploadFailed(let m):  return "上传失败：\(m)"
        case .parseFailed(let m):   return "解析失败：\(m)"
        case .legacySchema(let m):  return "后端仍返回旧版结构：\(m)"
        case .pollTimeout:          return "解析超时，请稍后重试"
        case .invalidResponse:      return "后端返回格式异常"
        case .jobNotFound:          return "解析任务不存在"
        case .serverError(let m):   return "服务器错误：\(m)"
        }
    }
}

enum DocumentParseEndpointConfig {
    private static let runtimeBaseURLStorageKey = "huiLu.documentParseBaseURL"
    private static let legacyRuntimeBaseURLStorageKey = "huiLu.documentParseBackendURL"
    private static let infoPlistBaseURLKey = "DOCUMENT_PARSE_BASE_URL"
    private static let parsePathComponents = ["api", "document", "parse"]

    struct Snapshot: Equatable {
        let isConfigured: Bool
        let endpointURL: URL?

        var endpointDescription: String {
            endpointURL?.absoluteString ?? "unconfigured"
        }
    }

    static var snapshot: Snapshot {
        guard let baseURLString = resolvedBaseURL,
              let endpointURL = makeParseEndpointURL(from: baseURLString)
        else {
            return Snapshot(isConfigured: false, endpointURL: nil)
        }
        return Snapshot(isConfigured: true, endpointURL: endpointURL)
    }

    static var isConfigured: Bool {
        snapshot.isConfigured
    }

    static var parseEndpointURL: URL? {
        snapshot.endpointURL
    }

    static func parseEndpointURL(jobID: String) -> URL? {
        guard let baseEndpoint = parseEndpointURL else { return nil }
        return baseEndpoint.appendingPathComponent(jobID)
    }

    static func saveRuntimeBaseURL(_ value: String) {
        UserDefaults.standard.set(normalizeBaseURL(value), forKey: runtimeBaseURLStorageKey)
    }

    static func normalizeBaseURL(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static var resolvedBaseURL: String? {
        #if DEBUG
        if let runtimeBaseURL = normalizedDebugRuntimeBaseURL(UserDefaults.standard.string(forKey: runtimeBaseURLStorageKey)) {
            return runtimeBaseURL
        }
        if let legacyRuntimeBaseURL = normalizedDebugRuntimeBaseURL(UserDefaults.standard.string(forKey: legacyRuntimeBaseURLStorageKey)) {
            return legacyRuntimeBaseURL
        }
        #endif
        if let infoPlistBaseURL = normalizedNonEmpty(Bundle.main.object(forInfoDictionaryKey: infoPlistBaseURLKey) as? String) {
            return infoPlistBaseURL
        }
        return nil
    }

    private static func normalizedNonEmpty(_ value: String?) -> String? {
        let normalized = normalizeBaseURL(value ?? "")
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedDebugRuntimeBaseURL(_ value: String?) -> String? {
        guard let normalized = normalizedNonEmpty(value),
              isLocalParserEndpoint(normalized)
        else {
            return nil
        }
        return normalized
    }

    private static func isLocalParserEndpoint(_ value: String) -> Bool {
        guard let host = URLComponents(string: value)?.host?.lowercased() else {
            return false
        }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private static func makeParseEndpointURL(from baseURLString: String) -> URL? {
        guard let components = URLComponents(string: baseURLString),
              components.scheme != nil,
              components.host != nil
        else {
            return nil
        }

        let normalizedPath = components.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath == parsePathComponents.joined(separator: "/") {
            return components.url
        }

        var url = components.url
        for component in parsePathComponents {
            url = url?.appendingPathComponent(component)
        }
        return url
    }
}

enum DocumentParseService {

    // MARK: - 后端地址管理

    /// 文档解析服务已拆为独立 endpoint，保留旧 API 名称仅用于设置页兼容。
    static var backendBaseURL: String {
        DocumentParseEndpointConfig.parseEndpointURL?.absoluteString ?? ""
    }

    static func saveBackendURL(_ value: String) {
        DocumentParseEndpointConfig.saveRuntimeBaseURL(value)
    }

    static func logRemoteUnavailableRoute() {
        TextPipelineDiagnostics.log(
            "PP",
            "[PP][Route] document_parse_endpoint=unconfigured",
            severity: .warning
        )
        TextPipelineDiagnostics.log(
            "PP",
            "[PP][Route] skip remote document parse, use local extraction",
            severity: .warning
        )
    }

    // MARK: - 配置

    /// 上传+解析总超时（秒）
    static let uploadTimeoutSeconds: TimeInterval = 90
    /// 轮询间隔（秒）
    static let pollIntervalSeconds: UInt64 = 2_000_000_000 // 2s in nanoseconds
    /// 轮询最大次数
    static let maxPollAttempts = 45 // 45 × 2s = 90s 最大等待
    /// 单次 HTTP 请求超时
    static let httpTimeoutSeconds: TimeInterval = 30

    // MARK: - POST /api/document/parse（上传并启动解析）

    /// 上传文档并启动 PP-StructureV3 解析
    /// - Parameters:
    ///   - fileData: PDF/图片的原始数据
    ///   - fileName: 文件名（含后缀）
    ///   - fileType: "pdf" / "image" / "text"
    ///   - documentID: 本地文档 ID
    ///   - title: 文档标题
    /// - Returns: 如果同步完成返回 NormalizedDocument，否则返回 jobID
    static func submitParseJob(
        fileData: Data,
        fileName: String,
        fileType: String,
        documentID: UUID,
        title: String
    ) async throws -> DocumentParseResponse {
        let route = DocumentParseEndpointConfig.snapshot
        guard route.isConfigured, let url = route.endpointURL else {
            logRemoteUnavailableRoute()
            throw DocumentParseServiceError.remoteUnavailable
        }
        TextPipelineDiagnostics.log(
            "PP",
            "[PP][Route] document_parse_endpoint=\(url.absoluteString)",
            severity: .info
        )
        TextPipelineDiagnostics.log(
            "PP",
            "[PP][Route] remote parse request start",
            severity: .info
        )

        // Multipart form-data 构建
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = uploadTimeoutSeconds

        var body = Data()
        // 文件部分
        body.appendMultipart(boundary: boundary, name: "file", fileName: fileName, mimeType: mimeType(for: fileName), data: fileData)
        // 元数据部分
        body.appendMultipartField(boundary: boundary, name: "document_id", value: documentID.uuidString)
        body.appendMultipartField(boundary: boundary, name: "title", value: title)
        body.appendMultipartField(boundary: boundary, name: "file_type", value: fileType)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        TextPipelineDiagnostics.log("PP", "[PP] parse request start doc=\(documentID) url=\(url.absoluteString) fileSize=\(fileData.count)字节 fileName=\(fileName)", severity: .info)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            TextPipelineDiagnostics.log("PP", "[PP] parse request failed: 无效的 HTTP 响应", severity: .error)
            throw DocumentParseServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            TextPipelineDiagnostics.log("PP", "[PP] parse request failed HTTP \(httpResponse.statusCode): \(body.prefix(200))", severity: .error)
            throw DocumentParseServiceError.uploadFailed("HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        do {
            let result = try decoder.decode(DocumentParseResponse.self, from: data)

            // 记录 schema + quality 信息
            let sv = result.schemaVersion ?? "v1(legacy)"
            let qr = result.qualityReason ?? "none"
            TextPipelineDiagnostics.log("PP", "[PP] parse response schema=\(sv) quality_reason=\(qr) doc=\(documentID)", severity: .info)

            if let error = result.error, !result.success {
                TextPipelineDiagnostics.log("PP", "[PP] parse request server error: \(error) quality_reason=\(qr)", severity: .error)
                throw DocumentParseServiceError.serverError(error)
            }

            if looksLikeLegacySchema(result) {
                let parseVersion = result.document?.metadata.parseVersion ?? "none"
                let reason = "schema=\(sv) parse_version=\(parseVersion) blocks=\(result.document?.blocks.count ?? 0)"
                TextPipelineDiagnostics.log("PP", "[PP] parse response incompatible with PP-StructureV3: \(reason)", severity: .warning)
                throw DocumentParseServiceError.legacySchema(reason)
            }

            TextPipelineDiagnostics.log("PP", "[PP] parse request success doc=\(documentID) status=\(result.status?.rawValue ?? "immediate") jobID=\(result.jobID ?? "sync")", severity: .info)
            return result
        } catch let e as DocumentParseServiceError {
            throw e
        } catch {
            TextPipelineDiagnostics.log("PP", "[PP] parse response decode failed: \(error.localizedDescription)", severity: .error)
            throw DocumentParseServiceError.invalidResponse
        }
    }

    // MARK: - GET /api/document/parse/{jobId}（轮询结果）

    /// 轮询解析任务状态，直到完成或超时
    static func pollParseResult(jobID: String) async throws -> NormalizedDocument {
        let route = DocumentParseEndpointConfig.snapshot
        guard route.isConfigured else {
            logRemoteUnavailableRoute()
            throw DocumentParseServiceError.remoteUnavailable
        }
        guard let url = DocumentParseEndpointConfig.parseEndpointURL(jobID: jobID) else {
            throw DocumentParseServiceError.invalidBackendURL
        }

        for attempt in 1...maxPollAttempts {
            try Task.checkCancellation()

            var request = URLRequest(url: url)
            request.timeoutInterval = httpTimeoutSeconds

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                // 404 → 任务不存在
                if let h = response as? HTTPURLResponse, h.statusCode == 404 {
                    throw DocumentParseServiceError.jobNotFound
                }
                throw DocumentParseServiceError.invalidResponse
            }

            let result = try JSONDecoder().decode(DocumentParseResponse.self, from: data)

            switch result.status {
            case .completed:
                guard let doc = result.document else {
                    throw DocumentParseServiceError.invalidResponse
                }
                TextPipelineDiagnostics.log("PP", "[PP] poll completed job=\(jobID) attempt=\(attempt) blocks=\(doc.blocks.count) paragraphs=\(doc.paragraphs.count) candidates=\(doc.structureCandidates.count)", severity: .info)
                return doc

            case .failed:
                TextPipelineDiagnostics.log("PP", "[PP] poll failed job=\(jobID): \(result.error ?? "未知错误")", severity: .error)
                throw DocumentParseServiceError.parseFailed(result.error ?? "未知错误")

            case .timedOut:
                TextPipelineDiagnostics.log("PP", "[PP] poll timed out job=\(jobID)", severity: .error)
                throw DocumentParseServiceError.pollTimeout

            case .pending, .parsing, .normalizing, .none:
                TextPipelineDiagnostics.log("PP", "[PP] poll waiting job=\(jobID) attempt=\(attempt) status=\(result.status?.rawValue ?? "nil")", severity: .info)
                try await Task.sleep(nanoseconds: pollIntervalSeconds)
            }
        }

        throw DocumentParseServiceError.pollTimeout
    }

    // MARK: - 便捷方法：上传并等待结果

    /// 一站式方法：上传文档 → 轮询至完成 → 返回归一化文档
    static func parseDocument(
        fileData: Data,
        fileName: String,
        fileType: String,
        documentID: UUID,
        title: String
    ) async throws -> NormalizedDocument {
        let submitResult = try await submitParseJob(
            fileData: fileData,
            fileName: fileName,
            fileType: fileType,
            documentID: documentID,
            title: title
        )

        // 同步模式：后端直接返回解析结果
        if let document = submitResult.document, submitResult.status == .completed {
            return document
        }

        // 异步模式：通过 jobID 轮询
        guard let jobID = submitResult.jobID else {
            throw DocumentParseServiceError.invalidResponse
        }

        return try await pollParseResult(jobID: jobID)
    }

    // MARK: - Private

    private static func mimeType(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":             return "application/pdf"
        case "png":             return "image/png"
        case "jpg", "jpeg":     return "image/jpeg"
        case "heic":            return "image/heic"
        case "txt":             return "text/plain"
        default:                return "application/octet-stream"
        }
    }

    private static func looksLikeLegacySchema(_ result: DocumentParseResponse) -> Bool {
        let schemaVersion = (result.schemaVersion ?? "").lowercased()
        let parseVersion = (result.document?.metadata.parseVersion ?? "").lowercased()
        let blockCount = result.document?.blocks.count ?? 0

        if parseVersion.contains("v3") || blockCount > 0 {
            return false
        }

        if schemaVersion.isEmpty {
            return true
        }

        return schemaVersion.contains("legacy") || schemaVersion.hasPrefix("v1")
    }
}

// MARK: - Data Multipart 辅助

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, fileName: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartField(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}
