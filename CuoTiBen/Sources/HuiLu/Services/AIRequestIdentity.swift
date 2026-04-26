import Foundation

enum SourceSelectionKind: String, Codable, CaseIterable, Equatable, Hashable {
    case passageSentence
    case passageParagraph
    case heading
    case question
    case option
    case vocabulary
    case chineseInstruction
    case bilingualNote
    case unknown

    var allowsCloudSentenceExplain: Bool {
        self == .passageSentence
    }

    var skipRemoteReason: String? {
        allowsCloudSentenceExplain ? nil : "notPassageSentence"
    }

    var displayName: String {
        switch self {
        case .passageSentence:
            return "正文句子"
        case .passageParagraph:
            return "正文段落"
        case .heading:
            return "标题块"
        case .question:
            return "题干块"
        case .option:
            return "选项/答案块"
        case .vocabulary:
            return "词汇块"
        case .chineseInstruction:
            return "中文说明"
        case .bilingualNote:
            return "双语注释"
        case .unknown:
            return "未知块"
        }
    }

    static func make(
        sourceKind: SourceContentKind,
        hasSentenceID: Bool,
        preferParagraph: Bool = false
    ) -> SourceSelectionKind {
        switch sourceKind {
        case .passageBody:
            return hasSentenceID && !preferParagraph ? .passageSentence : .passageParagraph
        case .passageHeading:
            return .heading
        case .question:
            return .question
        case .answerKey:
            return .option
        case .vocabularySupport:
            return .vocabulary
        case .chineseInstruction:
            return .chineseInstruction
        case .bilingualNote:
            return .bilingualNote
        case .noise, .synthetic, .unknown:
            return .unknown
        }
    }
}

struct SourceSelectionState: Codable, Equatable, Hashable {
    let kind: SourceSelectionKind
    let documentID: String?
    let segmentID: String?
    let sentenceID: String?
    let anchorLabel: String?
    let sourceKind: SourceContentKind
    let text: String
    let sourceTitle: String

    static let unknown = SourceSelectionState(
        kind: .unknown,
        documentID: nil,
        segmentID: nil,
        sentenceID: nil,
        anchorLabel: nil,
        sourceKind: .unknown,
        text: "",
        sourceTitle: ""
    )

    static func make(
        document: SourceDocument,
        sentence: Sentence,
        segment: Segment?
    ) -> SourceSelectionState {
        let sourceKind = resolvedSourceKind(sentence: sentence, segment: segment)
        return SourceSelectionState(
            kind: resolvedSelectionKind(
                sourceKind: sourceKind,
                hasSentenceID: !normalize(sentence.id).isEmpty,
                text: sentence.text
            ),
            documentID: document.id.uuidString,
            segmentID: sentence.segmentID,
            sentenceID: sentence.id,
            anchorLabel: sentence.anchorLabel,
            sourceKind: sourceKind,
            text: sentence.text,
            sourceTitle: document.title
        )
    }

    static func make(
        document: SourceDocument,
        text: String,
        sentence: Sentence?,
        segment: Segment?
    ) -> SourceSelectionState {
        let sourceKind = resolvedSourceKind(sentence: sentence, segment: segment)
        return SourceSelectionState(
            kind: resolvedSelectionKind(
                sourceKind: sourceKind,
                hasSentenceID: sentence.map { !normalize($0.id).isEmpty } ?? false,
                text: text
            ),
            documentID: document.id.uuidString,
            segmentID: sentence?.segmentID ?? segment?.id,
            sentenceID: sentence?.id,
            anchorLabel: sentence?.anchorLabel ?? segment?.anchorLabel,
            sourceKind: sourceKind,
            text: normalize(text),
            sourceTitle: document.title
        )
    }

    var allowsCloudSentenceExplain: Bool {
        kind.allowsCloudSentenceExplain
    }

    var skipRemoteReason: String? {
        kind.skipRemoteReason
    }

    private static func normalize(_ value: String?) -> String {
        (value ?? "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolvedSourceKind(sentence: Sentence?, segment: Segment?) -> SourceContentKind {
        if let sentenceKind = sentence?.provenance.sourceKind,
           sentenceKind != .unknown,
           sentenceKind != .synthetic {
            return sentenceKind
        }
        return segment?.provenance.sourceKind ?? .unknown
    }

    private static func resolvedSelectionKind(
        sourceKind: SourceContentKind,
        hasSentenceID: Bool,
        text: String
    ) -> SourceSelectionKind {
        if sourceKind == .passageBody, looksLikeHeading(text) {
            return .heading
        }
        return SourceSelectionKind.make(
            sourceKind: sourceKind,
            hasSentenceID: hasSentenceID
        )
    }

    private static func looksLikeHeading(_ text: String) -> Bool {
        let normalized = normalize(text)
        guard normalized.count >= 12, normalized.count <= 180 else {
            return false
        }
        let wordCount = normalized.split { $0.isWhitespace }.count
        guard wordCount <= 20 else { return false }

        let terminalPunctuation = CharacterSet(charactersIn: ".?!。？！")
        let hasTerminalSentencePunctuation = normalized.unicodeScalars.last.map {
            terminalPunctuation.contains($0)
        } ?? false
        if normalized.contains(":"), !hasTerminalSentencePunctuation {
            return true
        }

        let uppercaseLetters = normalized.unicodeScalars.filter { CharacterSet.uppercaseLetters.contains($0) }.count
        let letters = normalized.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let uppercaseRatio = letters == 0 ? 0 : Double(uppercaseLetters) / Double(letters)
        return !hasTerminalSentencePunctuation && uppercaseRatio >= 0.18 && wordCount <= 14
    }
}

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
            sentenceID: (dictionary["sentence_id"] as? String) ?? (dictionary["source_sentence_id"] as? String),
            segmentID: (dictionary["segment_id"] as? String) ?? (dictionary["source_segment_id"] as? String),
            sentenceTextHash: (dictionary["sentence_text_hash"] as? String) ?? (dictionary["source_sentence_text_hash"] as? String),
            anchorLabel: (dictionary["anchor_label"] as? String) ?? (dictionary["source_anchor_label"] as? String)
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
