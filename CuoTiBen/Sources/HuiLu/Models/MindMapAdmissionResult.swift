import Foundation

struct MindMapAdmissionDiagnostic: Identifiable, Codable, Equatable, Hashable {
    let nodeID: String
    let nodeType: MindMapNodeKind
    let sourceSegmentID: String?
    let sourceSentenceID: String?
    let sourceKind: SourceContentKind
    let hygieneScore: Double
    let consistencyScore: Double
    let admission: MindMapAdmission
    let rejectedReason: String?

    var id: String { "\(nodeID)#\(admission.rawValue)" }
}

struct MindMapAdmissionResult: Codable, Equatable, Hashable {
    let mainlineNodes: [MindMapNode]
    let auxiliaryNodes: [MindMapNode]
    let rejectedNodes: [MindMapNode]
    let diagnostics: [MindMapAdmissionDiagnostic]

    var mainlineCount: Int { mainlineNodes.count }
    var auxiliaryCount: Int { auxiliaryNodes.count }
    var rejectedCount: Int { rejectedNodes.count }

    var averageHygieneScore: Double {
        guard !diagnostics.isEmpty else { return 0 }
        return diagnostics.map(\.hygieneScore).reduce(0, +) / Double(diagnostics.count)
    }

    var averageConsistencyScore: Double {
        guard !diagnostics.isEmpty else { return 0 }
        return diagnostics.map(\.consistencyScore).reduce(0, +) / Double(diagnostics.count)
    }

    var topRejectedReasons: [(reason: String, count: Int)] {
        let counts = diagnostics.reduce(into: [String: Int]()) { partialResult, item in
            guard let reason = item.rejectedReason?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !reason.isEmpty else { return }
            partialResult[reason, default: 0] += 1
        }
        return counts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .map { (reason: $0.key, count: $0.value) }
    }
}
