import Foundation

enum AIResponseIdentityDiscardReason: String, Equatable {
    case missingIdentity
    case sentenceIDMismatch
    case segmentIDMismatch
    case textHashMismatch
    case anchorLabelMismatch

    var debugLabel: String { rawValue }
}

struct AIResponseIdentityDecision: Equatable {
    let isAllowed: Bool
    let reason: AIResponseIdentityDiscardReason?

    static let allow = AIResponseIdentityDecision(isAllowed: true, reason: nil)

    static func discard(_ reason: AIResponseIdentityDiscardReason) -> AIResponseIdentityDecision {
        AIResponseIdentityDecision(isAllowed: false, reason: reason)
    }
}

enum AIResponseIdentityGuard {
    static func validate(
        expected: AIRequestIdentity,
        actual: AIResponseIdentity?
    ) -> AIResponseIdentityDecision {
        guard let actual else {
            return .discard(.missingIdentity)
        }

        if actual.sentenceID != expected.sentenceID {
            return .discard(.sentenceIDMismatch)
        }
        if actual.segmentID != expected.segmentID {
            return .discard(.segmentIDMismatch)
        }
        if actual.sentenceTextHash != expected.sentenceTextHash {
            return .discard(.textHashMismatch)
        }
        if actual.anchorLabel != expected.anchorLabel {
            return .discard(.anchorLabelMismatch)
        }

        return .allow
    }

    static func logDiscard(
        requestID: String?,
        expected: AIRequestIdentity,
        actual: AIResponseIdentity?,
        reason: AIResponseIdentityDiscardReason
    ) {
        TextPipelineDiagnostics.log(
            "AI",
            [
                "[AI][IdentityGuard] discard",
                "request_id=\(requestID ?? "nil")",
                "identity_match=false",
                "expected_sentence_id=\(expected.sentenceID)",
                "actual_sentence_id=\(actual?.sentenceID ?? "nil")",
                "expected_hash=\(expected.sentenceTextHash)",
                "actual_hash=\(actual?.sentenceTextHash ?? "nil")",
                "discard_reason=\(reason.debugLabel)",
                "currentResultSource=discardedMismatch",
                "current_result_source=discardedMismatch"
            ].joined(separator: " "),
            severity: .warning
        )
    }
}
