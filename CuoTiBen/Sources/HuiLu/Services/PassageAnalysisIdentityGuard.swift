import Foundation

enum PassageAnalysisIdentityDiscardReason: String, Equatable {
    case missingIdentity
    case documentIDMismatch
    case contentHashMismatch
    case materialModeMismatch

    var debugLabel: String { rawValue }
}

struct PassageAnalysisIdentityDecision: Equatable {
    let isAllowed: Bool
    let reason: PassageAnalysisIdentityDiscardReason?

    static let allow = PassageAnalysisIdentityDecision(isAllowed: true, reason: nil)

    static func discard(_ reason: PassageAnalysisIdentityDiscardReason) -> PassageAnalysisIdentityDecision {
        PassageAnalysisIdentityDecision(isAllowed: false, reason: reason)
    }
}

enum PassageAnalysisIdentityGuard {
    static func validate(
        expected: PassageAnalysisIdentity,
        actual: PassageAnalysisIdentity?
    ) -> PassageAnalysisIdentityDecision {
        guard let actual else {
            return .discard(.missingIdentity)
        }

        if actual.documentID != expected.documentID {
            return .discard(.documentIDMismatch)
        }
        if actual.contentHash != expected.contentHash {
            return .discard(.contentHashMismatch)
        }
        if actual.materialMode != expected.materialMode {
            return .discard(.materialModeMismatch)
        }

        return .allow
    }

    static func logDecision(
        requestID: String?,
        expected: PassageAnalysisIdentity,
        actual: PassageAnalysisIdentity?,
        decision: PassageAnalysisIdentityDecision
    ) {
        let isMatch = decision.isAllowed
        TextPipelineDiagnostics.log(
            "AI",
            [
                "[AI][PassageMap] identity_match=\(isMatch)",
                "request_id=\(requestID ?? "nil")",
                "expected_document_id=\(expected.documentID)",
                "actual_document_id=\(actual?.documentID ?? "nil")",
                "expected_content_hash=\(expected.contentHash)",
                "actual_content_hash=\(actual?.contentHash ?? "nil")",
                "expected_material_mode=\(expected.materialMode.rawValue)",
                "actual_material_mode=\(actual?.materialMode.rawValue ?? "nil")",
                "discard_reason=\(decision.reason?.debugLabel ?? "none")"
            ].joined(separator: " "),
            severity: isMatch ? .info : .warning
        )
    }
}
