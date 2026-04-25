import Foundation

enum MindMapNodeKind: String, Codable, CaseIterable, Equatable, Hashable {
    case root = "root"
    case paragraph = "paragraph"
    case teachingFocus = "teaching_focus"
    case anchorSentence = "anchor_sentence"
    case evidence = "evidence"
    case vocabulary = "vocabulary"
    case auxiliary = "auxiliary"
    case diagnostic = "diagnostic"
}

enum MindMapAdmission: String, Codable, CaseIterable, Equatable, Hashable {
    case mainline = "mainline"
    case auxiliary = "auxiliary"
    case rejected = "rejected"
}

struct MindMapNode: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let kind: MindMapNodeKind
    let title: String
    let summary: String
    let children: [MindMapNode]
    let provenance: NodeProvenance
    let admission: MindMapAdmission
}
