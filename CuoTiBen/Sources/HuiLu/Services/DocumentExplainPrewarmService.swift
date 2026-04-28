import Foundation

struct DocumentExplainPrewarmSentencePayload: Encodable, Equatable, Hashable {
    let sentenceID: String
    let sentenceTextHash: String
    let text: String
    let context: String
    let anchorLabel: String
    let segmentID: String
    let pageIndex: Int?
    let paragraphRole: String
    let paragraphTheme: String
    let questionPrompt: String
    let isCurrentPage: Bool
    let isKeySentence: Bool
    let isPassageSentence: Bool
    let kind: String

    private enum CodingKeys: String, CodingKey {
        case sentenceID = "sentence_id"
        case sentenceTextHash = "sentence_text_hash"
        case text
        case context
        case anchorLabel = "anchor_label"
        case segmentID = "segment_id"
        case pageIndex = "page_index"
        case paragraphRole = "paragraph_role"
        case paragraphTheme = "paragraph_theme"
        case questionPrompt = "question_prompt"
        case isCurrentPage = "is_current_page"
        case isKeySentence = "is_key_sentence"
        case isPassageSentence = "is_passage_sentence"
        case kind
    }
}

enum DocumentExplainPrewarmJobState: String, Codable, Equatable, Hashable {
    case queued
    case running
    case completed
    case completedWithErrors = "completed_with_errors"
    case failed

    var isTerminal: Bool {
        switch self {
        case .completed, .completedWithErrors, .failed:
            return true
        case .queued, .running:
            return false
        }
    }
}

struct DocumentExplainPrewarmStatus: Decodable, Equatable, Hashable {
    let jobID: String
    let documentID: String
    let status: DocumentExplainPrewarmJobState
    let totalCount: Int
    let readyCount: Int
    let failedCount: Int
    let processingCount: Int
    let queuedCount: Int
    let requestID: String?

    private enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case documentID = "document_id"
        case status
        case totalCount = "total_count"
        case readyCount = "ready_count"
        case failedCount = "failed_count"
        case processingCount = "processing_count"
        case queuedCount = "queued_count"
        case requestID = "request_id"
    }

    var progressText: String {
        switch status {
        case .queued, .running:
            return "AI 精讲生成中 \(readyCount) / \(max(totalCount, 0))"
        case .completed:
            return "AI 精讲已生成"
        case .completedWithErrors:
            return "部分句子精讲失败，可单句重试"
        case .failed:
            return "AI 精讲预生成失败，本地结构仍可学习"
        }
    }
}

struct DocumentExplainPrewarmEnvelope: Decodable {
    let success: Bool
    let data: DocumentExplainPrewarmStatus?
    let requestID: String?
    let errorCode: String?
    let message: String?
    let retryable: Bool?
    let fallbackAvailable: Bool?

    private enum CodingKeys: String, CodingKey {
        case success
        case data
        case requestID = "request_id"
        case errorCode = "error_code"
        case message
        case retryable
        case fallbackAvailable = "fallback_available"
    }
}

final class DocumentExplainPrewarmService {
    private struct StartRequest: Encodable {
        let documentID: String
        let title: String
        let clientRequestID: String?
        let sentences: [DocumentExplainPrewarmSentencePayload]

        private enum CodingKeys: String, CodingKey {
            case documentID = "document_id"
            case title
            case clientRequestID = "client_request_id"
            case sentences
        }
    }

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func start(
        documentID: UUID,
        title: String,
        sentences: [DocumentExplainPrewarmSentencePayload],
        clientRequestID: String? = nil
    ) async throws -> DocumentExplainPrewarmStatus {
        let body = StartRequest(
            documentID: documentID.uuidString,
            title: title,
            clientRequestID: clientRequestID,
            sentences: sentences
        )
        guard let url = AIBackendConfig.endpointURL(path: "ai/prewarm-document") else {
            throw AIStructuredError.invalidRequest(
                message: "AI 后端地址未配置，无法启动文档级精讲预生成。",
                fallbackAvailable: false
            )
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    func status(jobID: String) async throws -> DocumentExplainPrewarmStatus {
        let encodedJobID = jobID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobID
        guard let url = AIBackendConfig.endpointURL(path: "ai/prewarm-document/\(encodedJobID)") else {
            throw AIStructuredError.invalidRequest(
                message: "AI 后端地址未配置，无法查询文档级精讲预生成状态。",
                fallbackAvailable: false
            )
        }
        let request = URLRequest(url: url)
        return try await perform(request)
    }

    func latest(documentID: UUID) async throws -> DocumentExplainPrewarmStatus {
        guard let latestURL = AIBackendConfig.endpointURL(path: "ai/prewarm-document/latest") else {
            throw AIStructuredError.invalidRequest(
                message: "AI 后端地址未配置，无法恢复文档级精讲预生成任务。",
                fallbackAvailable: false
            )
        }
        var components = URLComponents(url: latestURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "document_id", value: documentID.uuidString)
        ]
        guard let url = components?.url else {
            throw AIStructuredError.invalidRequest(message: "无法生成预热任务查询地址。")
        }
        let request = URLRequest(url: url)
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> DocumentExplainPrewarmStatus {
        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode

            guard let statusCode, (200..<300).contains(statusCode) else {
                if let structuredError = AIStructuredError.from(data: data, statusCode: statusCode) {
                    throw structuredError
                }
                throw AIStructuredError.from(dictionary: [
                    "error_code": statusCode.map { "HTTP_\($0)" } ?? "NETWORK_UNAVAILABLE",
                    "message": "AI 精讲预生成请求失败。",
                    "retryable": false,
                    "fallback_available": true
                ], statusCode: statusCode) ?? AIStructuredError.invalidModelResponse(message: "AI 精讲预生成请求失败。")
            }

            let envelope = try decoder.decode(DocumentExplainPrewarmEnvelope.self, from: data)
            guard envelope.success, let status = envelope.data else {
                if let structuredError = AIStructuredError.from(data: data, statusCode: statusCode) {
                    throw structuredError
                }
                throw AIStructuredError.invalidModelResponse(
                    message: envelope.message ?? "AI 精讲预生成返回内容不可用。",
                    requestID: envelope.requestID
                )
            }

            if status.requestID != nil || envelope.requestID == nil {
                return status
            }
            return DocumentExplainPrewarmStatus(
                jobID: status.jobID,
                documentID: status.documentID,
                status: status.status,
                totalCount: status.totalCount,
                readyCount: status.readyCount,
                failedCount: status.failedCount,
                processingCount: status.processingCount,
                queuedCount: status.queuedCount,
                requestID: envelope.requestID
            )
        } catch let urlError as URLError {
            throw AIStructuredError.from(urlError: urlError)
        }
    }
}
