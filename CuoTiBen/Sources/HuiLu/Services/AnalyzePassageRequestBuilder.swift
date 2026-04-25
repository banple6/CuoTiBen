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
    let finalSegmentsCount: Int
    let finalSentencesCount: Int
    let passageBodyParagraphCount: Int
    let sourceKindDistribution: [String: Int]
    let contractPreflightPassed: Bool
    let missingFields: [String]
    let sourceTitle: String

    init(
        materialMode: MaterialAnalysisMode,
        candidateParagraphCount: Int,
        acceptedParagraphCount: Int,
        rejectedParagraphCount: Int,
        rejectedReasons: [String],
        contentHash: String?,
        nonPassageRatio: Double,
        reason: String,
        reasonFlags: [String],
        clientRequestID: String?,
        documentID: String,
        activeCallPath: String,
        requestBuilderUsed: Bool,
        missingIdentity: Bool,
        rawTextLength: Int,
        sentenceDraftCount: Int,
        finalSegmentsCount: Int = 0,
        finalSentencesCount: Int = 0,
        passageBodyParagraphCount: Int = 0,
        sourceKindDistribution: [String: Int] = [:],
        contractPreflightPassed: Bool = false,
        missingFields: [String] = [],
        sourceTitle: String = ""
    ) {
        self.materialMode = materialMode
        self.candidateParagraphCount = candidateParagraphCount
        self.acceptedParagraphCount = acceptedParagraphCount
        self.rejectedParagraphCount = rejectedParagraphCount
        self.rejectedReasons = rejectedReasons
        self.contentHash = contentHash
        self.nonPassageRatio = nonPassageRatio
        self.reason = reason
        self.reasonFlags = reasonFlags
        self.clientRequestID = clientRequestID
        self.documentID = documentID
        self.activeCallPath = activeCallPath
        self.requestBuilderUsed = requestBuilderUsed
        self.missingIdentity = missingIdentity
        self.rawTextLength = rawTextLength
        self.sentenceDraftCount = sentenceDraftCount
        self.finalSegmentsCount = finalSegmentsCount
        self.finalSentencesCount = finalSentencesCount
        self.passageBodyParagraphCount = passageBodyParagraphCount
        self.sourceKindDistribution = sourceKindDistribution
        self.contractPreflightPassed = contractPreflightPassed
        self.missingFields = missingFields
        self.sourceTitle = sourceTitle
    }

    private enum CodingKeys: String, CodingKey {
        case materialMode
        case candidateParagraphCount
        case acceptedParagraphCount
        case rejectedParagraphCount
        case rejectedReasons
        case contentHash
        case nonPassageRatio
        case reason
        case reasonFlags
        case clientRequestID
        case documentID
        case activeCallPath
        case requestBuilderUsed
        case missingIdentity
        case rawTextLength
        case sentenceDraftCount
        case finalSegmentsCount
        case finalSentencesCount
        case passageBodyParagraphCount
        case sourceKindDistribution
        case contractPreflightPassed
        case missingFields
        case sourceTitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            materialMode: try container.decode(MaterialAnalysisMode.self, forKey: .materialMode),
            candidateParagraphCount: try container.decode(Int.self, forKey: .candidateParagraphCount),
            acceptedParagraphCount: try container.decode(Int.self, forKey: .acceptedParagraphCount),
            rejectedParagraphCount: try container.decode(Int.self, forKey: .rejectedParagraphCount),
            rejectedReasons: try container.decodeIfPresent([String].self, forKey: .rejectedReasons) ?? [],
            contentHash: try container.decodeIfPresent(String.self, forKey: .contentHash),
            nonPassageRatio: try container.decode(Double.self, forKey: .nonPassageRatio),
            reason: try container.decode(String.self, forKey: .reason),
            reasonFlags: try container.decodeIfPresent([String].self, forKey: .reasonFlags) ?? [],
            clientRequestID: try container.decodeIfPresent(String.self, forKey: .clientRequestID),
            documentID: try container.decode(String.self, forKey: .documentID),
            activeCallPath: try container.decode(String.self, forKey: .activeCallPath),
            requestBuilderUsed: try container.decode(Bool.self, forKey: .requestBuilderUsed),
            missingIdentity: try container.decode(Bool.self, forKey: .missingIdentity),
            rawTextLength: try container.decode(Int.self, forKey: .rawTextLength),
            sentenceDraftCount: try container.decode(Int.self, forKey: .sentenceDraftCount),
            finalSegmentsCount: try container.decodeIfPresent(Int.self, forKey: .finalSegmentsCount) ?? 0,
            finalSentencesCount: try container.decodeIfPresent(Int.self, forKey: .finalSentencesCount) ?? 0,
            passageBodyParagraphCount: try container.decodeIfPresent(Int.self, forKey: .passageBodyParagraphCount) ?? 0,
            sourceKindDistribution: try container.decodeIfPresent([String: Int].self, forKey: .sourceKindDistribution) ?? [:],
            contractPreflightPassed: try container.decodeIfPresent(Bool.self, forKey: .contractPreflightPassed) ?? false,
            missingFields: try container.decodeIfPresent([String].self, forKey: .missingFields) ?? [],
            sourceTitle: try container.decodeIfPresent(String.self, forKey: .sourceTitle) ?? ""
        )
    }

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
        missingIdentity: Bool? = nil,
        contractPreflightPassed: Bool? = nil,
        missingFields: [String]? = nil
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
            sentenceDraftCount: sentenceDraftCount,
            finalSegmentsCount: finalSegmentsCount,
            finalSentencesCount: finalSentencesCount,
            passageBodyParagraphCount: passageBodyParagraphCount,
            sourceKindDistribution: sourceKindDistribution,
            contractPreflightPassed: contractPreflightPassed ?? self.contractPreflightPassed,
            missingFields: missingFields ?? self.missingFields,
            sourceTitle: sourceTitle
        )
    }
}

struct AnalyzePassageRequestBuildResult {
    let payload: AnalyzePassageRequestPayload?
    let diagnostics: PassageAnalysisDiagnostics
    let expectedIdentity: PassageAnalysisIdentity?
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
                    hygieneScore: normalizedHygieneScore(segment.hygiene.score)
                )
            )
        }

        let contentHash = acceptedParagraphs.isEmpty
            ? nil
            : PassageAnalysisIdentity.contentHash(forParagraphTexts: acceptedParagraphs.map(\.text))
        let missingIdentity = normalizedDocumentID.isEmpty || (contentHash?.isEmpty ?? true)
        let expectedIdentity = PassageAnalysisIdentity.make(
            document: document,
            bundle: bundle,
            materialMode: decision.mode,
            acceptedParagraphCount: acceptedParagraphs.count,
            contentHash: contentHash
        )
        let candidatePayload = AnalyzePassageRequestPayload(
            clientRequestID: clientRequestID,
            documentID: normalizedDocumentID,
            contentHash: contentHash ?? "",
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            paragraphs: acceptedParagraphs,
            questionBlocks: auxiliaryBlocks(in: candidateSegments, kinds: [.question], limit: 8),
            answerBlocks: auxiliaryBlocks(in: candidateSegments, kinds: [.answerKey], limit: 8),
            vocabularyBlocks: auxiliaryBlocks(
                in: candidateSegments,
                kinds: [.vocabularySupport, .bilingualNote, .chineseInstruction],
                limit: 8
            )
        )
        let preflight = contractPreflight(payload: candidatePayload, shouldRequestRemote: decision.mode.shouldRequestRemote)

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
            requestBuilderUsed: decision.mode.shouldRequestRemote,
            missingIdentity: missingIdentity,
            rawTextLength: decision.rawTextLength,
            sentenceDraftCount: decision.sentenceDraftCount,
            finalSegmentsCount: decision.finalSegmentsCount,
            finalSentencesCount: decision.finalSentencesCount,
            passageBodyParagraphCount: decision.passageBodyParagraphCount,
            sourceKindDistribution: decision.sourceKindDistribution,
            contractPreflightPassed: preflight.passed,
            missingFields: preflight.missingFields,
            sourceTitle: title.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard decision.mode.shouldRequestRemote,
              preflight.passed else {
            return AnalyzePassageRequestBuildResult(
                payload: nil,
                diagnostics: diagnostics,
                expectedIdentity: expectedIdentity
            )
        }

        return AnalyzePassageRequestBuildResult(
            payload: candidatePayload,
            diagnostics: diagnostics,
            expectedIdentity: expectedIdentity
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

    private static func normalizedHygieneScore(_ score: Double) -> Double {
        guard score.isFinite else { return 0.9 }
        return min(max(score, 0), 1)
    }

    private struct ContractPreflightResult {
        let passed: Bool
        let missingFields: [String]
    }

    private static func contractPreflight(
        payload: AnalyzePassageRequestPayload,
        shouldRequestRemote: Bool
    ) -> ContractPreflightResult {
        guard shouldRequestRemote else {
            return ContractPreflightResult(passed: false, missingFields: [])
        }

        var missingFields: [String] = []
        if payload.clientRequestID.normalizedForPassageRequest.isEmpty {
            missingFields.append("client_request_id")
        }
        if payload.documentID.normalizedForPassageRequest.isEmpty {
            missingFields.append("document_id")
        }
        if payload.contentHash.normalizedForPassageRequest.isEmpty {
            missingFields.append("content_hash")
        }
        if payload.paragraphs.isEmpty {
            missingFields.append("paragraphs")
        }

        for (index, paragraph) in payload.paragraphs.enumerated() {
            if paragraph.segmentID.normalizedForPassageRequest.isEmpty {
                missingFields.append("paragraphs[\(index)].segment_id")
            }
            if paragraph.index < 0 {
                missingFields.append("paragraphs[\(index)].index")
            }
            if paragraph.anchorLabel.normalizedForPassageRequest.isEmpty {
                missingFields.append("paragraphs[\(index)].anchor_label")
            }
            if paragraph.text.normalizedForPassageRequest.isEmpty {
                missingFields.append("paragraphs[\(index)].text")
            }
            if paragraph.sourceKind.normalizedForPassageRequest.isEmpty {
                missingFields.append("paragraphs[\(index)].source_kind")
            }
            if !paragraph.hygieneScore.isFinite || paragraph.hygieneScore < 0 || paragraph.hygieneScore > 1 {
                missingFields.append("paragraphs[\(index)].hygiene_score")
            }
        }

        return ContractPreflightResult(
            passed: missingFields.isEmpty,
            missingFields: missingFields
        )
    }
}

private extension String {
    var normalizedForPassageRequest: String {
        replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
