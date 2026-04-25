import Foundation

enum StructuredSourceMaterialMode: String, Codable, Equatable, Hashable {
    case passageReading
    case learningMaterial
    case vocabularyNotes
    case questionSheet
    case auxiliaryOnlyMap
    case insufficientText

    var analysisMode: MaterialAnalysisMode {
        switch self {
        case .passageReading:
            return .passageReading
        case .learningMaterial:
            return .learningMaterial
        case .vocabularyNotes:
            return .vocabularyNotes
        case .questionSheet:
            return .questionSheet
        case .auxiliaryOnlyMap:
            return .auxiliaryOnlyMap
        case .insufficientText:
            return .insufficientText
        }
    }

    var fallbackMessage: String {
        analysisMode.fallbackMessage
    }
}

struct StructuredSourceMaterialDecision: Codable, Equatable, Hashable {
    let mode: StructuredSourceMaterialMode
    let rawTextLength: Int
    let anchorCount: Int
    let sentenceDraftCount: Int
    let finalSegmentsCount: Int
    let finalSentencesCount: Int
    let passageBodyParagraphCount: Int
    let candidateParagraphCount: Int
    let passageParagraphCount: Int
    let questionParagraphCount: Int
    let answerParagraphCount: Int
    let vocabularyParagraphCount: Int
    let learningParagraphCount: Int
    let nonPassageRatio: Double
    let sourceKindDistribution: [String: Int]
    let reasons: [String]

    var primaryReason: String {
        reasons.first ?? "passageEligible"
    }

    var shouldEnterFallbackPath: Bool {
        mode != .passageReading
    }

    func withFallbackOverride(
        mode: StructuredSourceMaterialMode,
        appendedReason: String
    ) -> StructuredSourceMaterialDecision {
        StructuredSourceMaterialDecision(
            mode: mode,
            rawTextLength: rawTextLength,
            anchorCount: anchorCount,
            sentenceDraftCount: sentenceDraftCount,
            finalSegmentsCount: finalSegmentsCount,
            finalSentencesCount: finalSentencesCount,
            passageBodyParagraphCount: passageBodyParagraphCount,
            candidateParagraphCount: candidateParagraphCount,
            passageParagraphCount: passageParagraphCount,
            questionParagraphCount: questionParagraphCount,
            answerParagraphCount: answerParagraphCount,
            vocabularyParagraphCount: vocabularyParagraphCount,
            learningParagraphCount: learningParagraphCount,
            nonPassageRatio: nonPassageRatio,
            sourceKindDistribution: sourceKindDistribution,
            reasons: Array(Set(reasons + [appendedReason])).sorted()
        )
    }

    func asPassageDiagnostics(
        documentID: String,
        activeCallPath: String,
        bundle: StructuredSourceBundle,
        sourceTitle: String
    ) -> PassageAnalysisDiagnostics {
        let acceptedParagraphCount = mode == .passageReading ? passageParagraphCount : 0
        let rejectedParagraphCount = max(candidateParagraphCount - acceptedParagraphCount, 0)
        let analysisMode = mode.analysisMode
        return PassageAnalysisDiagnostics(
            materialMode: analysisMode,
            candidateParagraphCount: candidateParagraphCount,
            acceptedParagraphCount: acceptedParagraphCount,
            rejectedParagraphCount: rejectedParagraphCount,
            rejectedReasons: reasons,
            contentHash: PassageAnalysisIdentity.contentHash(for: bundle, materialMode: analysisMode),
            nonPassageRatio: nonPassageRatio,
            reason: primaryReason,
            reasonFlags: reasons,
            clientRequestID: nil,
            documentID: documentID,
            activeCallPath: activeCallPath,
            requestBuilderUsed: false,
            missingIdentity: false,
            rawTextLength: rawTextLength,
            sentenceDraftCount: sentenceDraftCount,
            finalSegmentsCount: finalSegmentsCount,
            finalSentencesCount: finalSentencesCount,
            passageBodyParagraphCount: passageBodyParagraphCount,
            sourceKindDistribution: sourceKindDistribution,
            contractPreflightPassed: false,
            missingFields: [],
            sourceTitle: sourceTitle
        )
    }
}

enum StructuredSourceMaterialGate {
    private static let minimumRawTextLength = 300
    private static let minimumPassageParagraphCount = 2
    private static let maximumNonPassageRatio = 0.70

    static func evaluate(
        draft: SourceTextDraft,
        bundle: StructuredSourceBundle
    ) -> StructuredSourceMaterialDecision {
        let nonEmptySegments = bundle.segments.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let passageSegments = nonEmptySegments.filter { $0.provenance.sourceKind == .passageBody }
        let questionSegments = nonEmptySegments.filter { $0.provenance.sourceKind == .question }
        let answerSegments = nonEmptySegments.filter { $0.provenance.sourceKind == .answerKey }
        let vocabularySegments = nonEmptySegments.filter {
            $0.provenance.sourceKind == .vocabularySupport || $0.provenance.sourceKind == .bilingualNote
        }
        let learningSegments = nonEmptySegments.filter {
            $0.provenance.sourceKind == .chineseInstruction || $0.provenance.sourceKind == .passageHeading
        }

        let totalSegmentCount = max(nonEmptySegments.count, 1)
        let nonPassageCount = max(nonEmptySegments.count - passageSegments.count, 0)
        let nonPassageRatio = Double(nonPassageCount) / Double(totalSegmentCount)
        let rawTextLength = draft.rawText.count
        let finalSegmentsCount = nonEmptySegments.count
        let finalSentencesCount = bundle.sentences.count
        let sourceKindDistribution = Dictionary(
            grouping: nonEmptySegments,
            by: { $0.provenance.sourceKind.rawValue }
        ).mapValues(\.count)

        var reasons: [String] = []
        var blockingReasons: [String] = []
        if draft.sentenceDrafts.isEmpty {
            reasons.append("sentenceDrafts=0")
        }
        if rawTextLength < minimumRawTextLength {
            blockingReasons.append("rawTextTooShort")
        }
        if passageSegments.count < minimumPassageParagraphCount {
            blockingReasons.append("noPassageBody")
        }
        if finalSentencesCount == 0 {
            blockingReasons.append("finalSentences=0")
        }
        if nonPassageRatio > maximumNonPassageRatio {
            blockingReasons.append("nonPassageRatioHigh")
        }
        reasons.append(contentsOf: blockingReasons)

        let questionLikeCount = questionSegments.count + answerSegments.count
        let vocabularyLikeCount = vocabularySegments.count
        let learningLikeCount = learningSegments.count
        let questionLikeRatio = Double(questionLikeCount) / Double(totalSegmentCount)
        let vocabularyLikeRatio = Double(vocabularyLikeCount) / Double(totalSegmentCount)
        let learningLikeRatio = Double(learningLikeCount) / Double(totalSegmentCount)

        let mode: StructuredSourceMaterialMode
        if blockingReasons.isEmpty {
            mode = .passageReading
        } else if questionLikeCount > 0,
                  questionLikeRatio >= 0.35,
                  questionLikeCount >= max(vocabularyLikeCount, learningLikeCount) {
            reasons.append("mostlyQuestionBlocks")
            mode = .questionSheet
        } else if vocabularyLikeCount > 0,
                  vocabularyLikeRatio >= 0.30,
                  vocabularyLikeCount >= max(questionLikeCount, learningLikeCount) {
            reasons.append("mostlyVocabularyNotes")
            mode = .vocabularyNotes
        } else if learningLikeCount > 0,
                  learningLikeRatio >= 0.30 || nonPassageRatio > maximumNonPassageRatio {
            reasons.append("mostlyChineseInstruction")
            mode = .learningMaterial
        } else if learningLikeCount > 0 || questionLikeCount > 0 || vocabularyLikeCount > 0 {
            reasons.append("auxiliaryOnlyMap")
            mode = .auxiliaryOnlyMap
        } else {
            reasons.append("insufficientText")
            mode = .insufficientText
        }

        return StructuredSourceMaterialDecision(
            mode: mode,
            rawTextLength: rawTextLength,
            anchorCount: draft.anchors.count,
            sentenceDraftCount: draft.sentenceDrafts.count,
            finalSegmentsCount: finalSegmentsCount,
            finalSentencesCount: finalSentencesCount,
            passageBodyParagraphCount: passageSegments.count,
            candidateParagraphCount: nonEmptySegments.count,
            passageParagraphCount: passageSegments.count,
            questionParagraphCount: questionSegments.count,
            answerParagraphCount: answerSegments.count,
            vocabularyParagraphCount: vocabularyLikeCount,
            learningParagraphCount: learningLikeCount,
            nonPassageRatio: nonPassageRatio,
            sourceKindDistribution: sourceKindDistribution,
            reasons: Array(Set(reasons)).sorted()
        )
    }
}
