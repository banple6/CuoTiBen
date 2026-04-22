import Foundation

struct PassageAnalysisDiagnostics: Codable, Equatable, Hashable {
    let materialMode: MaterialAnalysisMode
    let candidateParagraphCount: Int
    let acceptedParagraphCount: Int
    let rejectedParagraphCount: Int
    let rejectedReasons: [String]
    let contentHash: String?
    let nonPassageRatio: Double
    let reason: String
    let reasonFlags: [String]
    let clientRequestID: String?
    let documentID: String
    let activeCallPath: String
    let requestBuilderUsed: Bool
    let missingIdentity: Bool
    let rawTextLength: Int
    let sentenceDraftCount: Int

    var statusTitle: String {
        materialMode.statusTitle
    }

    var fallbackMessage: String {
        materialMode.fallbackMessage
    }

    var structureTitle: String {
        materialMode.structureTitle
    }

    func withFlags(
        requestBuilderUsed: Bool? = nil,
        missingIdentity: Bool? = nil
    ) -> PassageAnalysisDiagnostics {
        PassageAnalysisDiagnostics(
            materialMode: materialMode,
            candidateParagraphCount: candidateParagraphCount,
            acceptedParagraphCount: acceptedParagraphCount,
            rejectedParagraphCount: rejectedParagraphCount,
            rejectedReasons: rejectedReasons,
            contentHash: contentHash,
            nonPassageRatio: nonPassageRatio,
            reason: reason,
            reasonFlags: reasonFlags,
            clientRequestID: clientRequestID,
            documentID: documentID,
            activeCallPath: activeCallPath,
            requestBuilderUsed: requestBuilderUsed ?? self.requestBuilderUsed,
            missingIdentity: missingIdentity ?? self.missingIdentity,
            rawTextLength: rawTextLength,
            sentenceDraftCount: sentenceDraftCount
        )
    }
}

struct AnalyzePassageRequestBuildResult {
    let payload: AnalyzePassageRequestPayload?
    let diagnostics: PassageAnalysisDiagnostics
}

struct AnalyzePassageRequestPayload: Encodable {
    let clientRequestID: String
    let documentID: String
    let contentHash: String
    let title: String
    let paragraphs: [AnalyzePassageParagraphPayload]
    let questionBlocks: [AnalyzePassageAuxiliaryBlockPayload]
    let answerBlocks: [AnalyzePassageAuxiliaryBlockPayload]
    let vocabularyBlocks: [AnalyzePassageAuxiliaryBlockPayload]

    private enum CodingKeys: String, CodingKey {
        case clientRequestID = "client_request_id"
        case documentID = "document_id"
        case contentHash = "content_hash"
        case title
        case paragraphs
        case questionBlocks = "question_blocks"
        case answerBlocks = "answer_blocks"
        case vocabularyBlocks = "vocabulary_blocks"
    }
}

struct AnalyzePassageParagraphPayload: Encodable {
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

struct AnalyzePassageAuxiliaryBlockPayload: Encodable {
    let blockID: String
    let sourceKind: String
    let anchorLabel: String
    let text: String

    private enum CodingKeys: String, CodingKey {
        case blockID = "block_id"
        case sourceKind = "source_kind"
        case anchorLabel = "anchor_label"
        case text
    }
}

enum AnalyzePassageRequestBuilder {
    private static let maxParagraphCount = 4
    private static let maxParagraphCharacters = 700
    private static let maxAuxiliaryCharacters = 2000

    static func build(
        document: SourceDocument,
        bundle: StructuredSourceBundle,
        title: String,
        decision: MaterialAnalysisDecision,
        activeCallPath: String
    ) -> AnalyzePassageRequestBuildResult {
        let normalizedDocumentID = document.id.uuidString.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientRequestID = UUID().uuidString.lowercased()
        let candidateSegments = bundle.segments
            .sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.id < rhs.id
            }
            .filter { !$0.text.normalizedForPassageRequest.isEmpty }

        var acceptedParagraphs: [AnalyzePassageParagraphPayload] = []
        var rejectedReasons: [String] = []

        for segment in candidateSegments {
            let normalizedText = segment.text.normalizedForPassageRequest
            guard segment.provenance.sourceKind == .passageBody else {
                rejectedReasons.append("nonPassage:\(segment.provenance.sourceKind.rawValue):\(segment.id)")
                continue
            }

            if acceptedParagraphs.count >= maxParagraphCount {
                rejectedReasons.append("exceedsMaxParagraphs:\(segment.id)")
                continue
            }

            let clippedText = String(normalizedText.prefix(maxParagraphCharacters))
            if clippedText.isEmpty {
                rejectedReasons.append("emptyText:\(segment.id)")
                continue
            }

            acceptedParagraphs.append(
                AnalyzePassageParagraphPayload(
                    segmentID: segment.id,
                    index: segment.index,
                    anchorLabel: segment.anchorLabel,
                    text: clippedText,
                    sourceKind: SourceContentKind.passageBody.rawValue,
                    hygieneScore: min(max(segment.hygiene.score, 0), 1)
                )
            )
        }

        let contentHash = acceptedParagraphs.isEmpty
            ? nil
            : AIRequestIdentity.hash(
                text: acceptedParagraphs.map(\.text).joined(separator: "\n\n")
            )
        let missingIdentity = normalizedDocumentID.isEmpty || (contentHash?.isEmpty ?? true)

        let diagnostics = PassageAnalysisDiagnostics(
            materialMode: decision.mode,
            candidateParagraphCount: candidateSegments.count,
            acceptedParagraphCount: acceptedParagraphs.count,
            rejectedParagraphCount: max(candidateSegments.count - acceptedParagraphs.count, 0),
            rejectedReasons: Array(rejectedReasons.prefix(12)),
            contentHash: contentHash,
            nonPassageRatio: decision.nonPassageRatio,
            reason: decision.primaryReason,
            reasonFlags: decision.reasons,
            clientRequestID: clientRequestID,
            documentID: normalizedDocumentID,
            activeCallPath: activeCallPath,
            requestBuilderUsed: decision.mode.shouldRequestRemote && !acceptedParagraphs.isEmpty && !missingIdentity,
            missingIdentity: missingIdentity,
            rawTextLength: decision.rawTextLength,
            sentenceDraftCount: decision.sentenceDraftCount
        )

        guard decision.mode.shouldRequestRemote,
              !acceptedParagraphs.isEmpty,
              !missingIdentity,
              let resolvedContentHash = contentHash else {
            return AnalyzePassageRequestBuildResult(
                payload: nil,
                diagnostics: diagnostics
            )
        }

        return AnalyzePassageRequestBuildResult(
            payload: AnalyzePassageRequestPayload(
                clientRequestID: clientRequestID,
                documentID: normalizedDocumentID,
                contentHash: resolvedContentHash,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                paragraphs: acceptedParagraphs,
                questionBlocks: auxiliaryBlocks(in: candidateSegments, kinds: [.question], limit: 8),
                answerBlocks: auxiliaryBlocks(in: candidateSegments, kinds: [.answerKey], limit: 8),
                vocabularyBlocks: auxiliaryBlocks(
                    in: candidateSegments,
                    kinds: [.vocabularySupport, .bilingualNote, .chineseInstruction],
                    limit: 8
                )
            ),
            diagnostics: diagnostics
        )
    }

    private static func auxiliaryBlocks(
        in segments: [Segment],
        kinds: Set<SourceContentKind>,
        limit: Int
    ) -> [AnalyzePassageAuxiliaryBlockPayload] {
        segments
            .filter { kinds.contains($0.provenance.sourceKind) }
            .prefix(limit)
            .map { segment in
                AnalyzePassageAuxiliaryBlockPayload(
                    blockID: segment.id,
                    sourceKind: segment.provenance.sourceKind.rawValue,
                    anchorLabel: segment.anchorLabel,
                    text: String(segment.text.normalizedForPassageRequest.prefix(maxAuxiliaryCharacters))
                )
            }
    }
}

private extension String {
    var normalizedForPassageRequest: String {
        replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
