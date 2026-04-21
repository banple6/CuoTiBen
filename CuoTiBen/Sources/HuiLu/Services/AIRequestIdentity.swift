import Foundation

struct AIRequestIdentity: Codable, Equatable, Hashable, CustomDebugStringConvertible {
    let clientRequestID: String
    let documentID: String
    let sentenceID: String
    let segmentID: String
    let sentenceTextHash: String
    let anchorLabel: String

    private enum CodingKeys: String, CodingKey {
        case clientRequestID = "client_request_id"
        case documentID = "document_id"
        case sentenceID = "sentence_id"
        case segmentID = "segment_id"
        case sentenceTextHash = "sentence_text_hash"
        case anchorLabel = "anchor_label"
    }

    static func make(document: SourceDocument, sentence: Sentence) -> AIRequestIdentity? {
        make(
            documentID: document.id.uuidString,
            sentenceID: sentence.id,
            segmentID: sentence.segmentID,
            sentenceText: sentence.text,
            anchorLabel: sentence.anchorLabel
        )
    }

    static func make(
        documentID: String,
        sentenceID: String?,
        segmentID: String?,
        sentenceText: String,
        anchorLabel: String?,
        clientRequestID: String = UUID().uuidString.lowercased()
    ) -> AIRequestIdentity? {
        let normalizedDocumentID = normalize(documentID)
        let normalizedSentenceID = normalize(sentenceID)
        let normalizedSegmentID = normalize(segmentID)
        let normalizedAnchorLabel = normalize(anchorLabel)
        let normalizedHash = hash(text: sentenceText)

        guard !normalizedDocumentID.isEmpty,
              !normalizedSentenceID.isEmpty,
              !normalizedSegmentID.isEmpty,
              !normalizedAnchorLabel.isEmpty,
              !normalizedHash.isEmpty else {
            return nil
        }

        return AIRequestIdentity(
            clientRequestID: clientRequestID,
            documentID: normalizedDocumentID,
            sentenceID: normalizedSentenceID,
            segmentID: normalizedSegmentID,
            sentenceTextHash: normalizedHash,
            anchorLabel: normalizedAnchorLabel
        )
    }

    static func hash(text: String) -> String {
        let normalized = normalize(text)
            .lowercased()

        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3

        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }

        return String(hash, radix: 16)
    }

    func asRequestFields() -> [String: String] {
        [
            "client_request_id": clientRequestID,
            "document_id": documentID,
            "sentence_id": sentenceID,
            "segment_id": segmentID,
            "sentence_text_hash": sentenceTextHash,
            "anchor_label": anchorLabel
        ]
    }

    var responseIdentity: AIResponseIdentity {
        AIResponseIdentity(
            clientRequestID: clientRequestID,
            documentID: documentID,
            sentenceID: sentenceID,
            segmentID: segmentID,
            sentenceTextHash: sentenceTextHash,
            anchorLabel: anchorLabel
        )
    }

    var semanticKey: SemanticKey {
        SemanticKey(
            documentID: documentID,
            sentenceID: sentenceID,
            segmentID: segmentID,
            sentenceTextHash: sentenceTextHash,
            anchorLabel: anchorLabel
        )
    }

    func matchesSemanticIdentity(_ other: AIRequestIdentity) -> Bool {
        semanticKey == other.semanticKey
    }

    var debugDescription: String {
        [
            "client_request_id=\(short(clientRequestID))",
            "document_id=\(documentID)",
            "sentence_id=\(sentenceID)",
            "segment_id=\(segmentID)",
            "sentence_text_hash=\(sentenceTextHash)",
            "anchor_label=\(anchorLabel)"
        ].joined(separator: " ")
    }

    private static func normalize(_ value: String?) -> String {
        (value ?? "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func short(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > 12 else { return normalized }
        return "\(normalized.prefix(8))…"
    }
}

extension AIRequestIdentity {
    struct SemanticKey: Equatable, Hashable {
        let documentID: String
        let sentenceID: String
        let segmentID: String
        let sentenceTextHash: String
        let anchorLabel: String
    }
}

struct AIResponseIdentity: Codable, Equatable, Hashable {
    let clientRequestID: String?
    let documentID: String?
    let sentenceID: String
    let segmentID: String
    let sentenceTextHash: String
    let anchorLabel: String

    private enum CodingKeys: String, CodingKey {
        case clientRequestID = "client_request_id"
        case documentID = "document_id"
        case sentenceID = "sentence_id"
        case segmentID = "segment_id"
        case sentenceTextHash = "sentence_text_hash"
        case anchorLabel = "anchor_label"
    }

    init(
        clientRequestID: String?,
        documentID: String?,
        sentenceID: String,
        segmentID: String,
        sentenceTextHash: String,
        anchorLabel: String
    ) {
        self.clientRequestID = Self.normalize(clientRequestID)
        self.documentID = Self.normalize(documentID)
        self.sentenceID = sentenceID
        self.segmentID = segmentID
        self.sentenceTextHash = sentenceTextHash
        self.anchorLabel = anchorLabel
    }

    init?(
        clientRequestID: String?,
        documentID: String?,
        sentenceID: String?,
        segmentID: String?,
        sentenceTextHash: String?,
        anchorLabel: String?
    ) {
        let normalizedSentenceID = Self.normalize(sentenceID)
        let normalizedSegmentID = Self.normalize(segmentID)
        let normalizedTextHash = Self.normalize(sentenceTextHash)
        let normalizedAnchorLabel = Self.normalize(anchorLabel)

        guard !normalizedSentenceID.isEmpty,
              !normalizedSegmentID.isEmpty,
              !normalizedTextHash.isEmpty,
              !normalizedAnchorLabel.isEmpty else {
            return nil
        }

        self.init(
            clientRequestID: clientRequestID,
            documentID: documentID,
            sentenceID: normalizedSentenceID,
            segmentID: normalizedSegmentID,
            sentenceTextHash: normalizedTextHash,
            anchorLabel: normalizedAnchorLabel
        )
    }

    init?(dictionary: [String: Any]) {
        self.init(
            clientRequestID: dictionary["client_request_id"] as? String,
            documentID: dictionary["document_id"] as? String,
            sentenceID: dictionary["sentence_id"] as? String,
            segmentID: dictionary["segment_id"] as? String,
            sentenceTextHash: dictionary["sentence_text_hash"] as? String,
            anchorLabel: dictionary["anchor_label"] as? String
        )
    }

    private static func normalize(_ value: String?) -> String {
        (value ?? "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension ExplainSentenceContext {
    func makeRequestIdentity() -> AIRequestIdentity? {
        AIRequestIdentity.make(
            documentID: documentID ?? "",
            sentenceID: sentenceID,
            segmentID: segmentID,
            sentenceText: sentence,
            anchorLabel: anchorLabel
        )
    }
}
