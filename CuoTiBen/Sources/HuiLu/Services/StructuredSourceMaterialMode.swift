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
    let candidateParagraphCount: Int
    let passageParagraphCount: Int
    let questionParagraphCount: Int
    let answerParagraphCount: Int
    let vocabularyParagraphCount: Int
    let learningParagraphCount: Int
    let nonPassageRatio: Double
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
            candidateParagraphCount: candidateParagraphCount,
            passageParagraphCount: passageParagraphCount,
            questionParagraphCount: questionParagraphCount,
            answerParagraphCount: answerParagraphCount,
            vocabularyParagraphCount: vocabularyParagraphCount,
            learningParagraphCount: learningParagraphCount,
            nonPassageRatio: nonPassageRatio,
            reasons: Array(Set(reasons + [appendedReason])).sorted()
        )
    }

    func asPassageDiagnostics(
        documentID: String,
        activeCallPath: String
    ) -> PassageAnalysisDiagnostics {
        let acceptedParagraphCount = mode == .passageReading ? passageParagraphCount : 0
        let rejectedParagraphCount = max(candidateParagraphCount - acceptedParagraphCount, 0)
        return PassageAnalysisDiagnostics(
            materialMode: mode.analysisMode,
            candidateParagraphCount: candidateParagraphCount,
            acceptedParagraphCount: acceptedParagraphCount,
            rejectedParagraphCount: rejectedParagraphCount,
            rejectedReasons: reasons,
            contentHash: nil,
            nonPassageRatio: nonPassageRatio,
            reason: primaryReason,
            reasonFlags: reasons,
            clientRequestID: nil,
            documentID: documentID,
            activeCallPath: activeCallPath,
            requestBuilderUsed: false,
            missingIdentity: false,
            rawTextLength: rawTextLength,
            sentenceDraftCount: sentenceDraftCount
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

        var reasons: [String] = []
        if draft.sentenceDrafts.isEmpty {
            reasons.append("sentenceDrafts=0")
        }
        if draft.rawText.count < minimumRawTextLength {
            reasons.append("rawTextTooShort")
        }
        if passageSegments.count < minimumPassageParagraphCount {
            reasons.append("noPassageBody")
        }
        if nonPassageRatio > maximumNonPassageRatio {
            reasons.append("nonPassageRatioHigh")
        }

        let questionLikeCount = questionSegments.count + answerSegments.count
        let vocabularyLikeCount = vocabularySegments.count
        let learningLikeCount = learningSegments.count
        let questionLikeRatio = Double(questionLikeCount) / Double(totalSegmentCount)
        let vocabularyLikeRatio = Double(vocabularyLikeCount) / Double(totalSegmentCount)
        let learningLikeRatio = Double(learningLikeCount) / Double(totalSegmentCount)

        let mode: StructuredSourceMaterialMode
        if reasons.isEmpty {
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
            rawTextLength: draft.rawText.count,
            anchorCount: draft.anchors.count,
            sentenceDraftCount: draft.sentenceDrafts.count,
            candidateParagraphCount: nonEmptySegments.count,
            passageParagraphCount: passageSegments.count,
            questionParagraphCount: questionSegments.count,
            answerParagraphCount: answerSegments.count,
            vocabularyParagraphCount: vocabularyLikeCount,
            learningParagraphCount: learningLikeCount,
            nonPassageRatio: nonPassageRatio,
            reasons: Array(Set(reasons)).sorted()
        )
    }
}
