import Foundation

struct NoteSummaryItem: Identifiable, Equatable, Hashable {
    let id: UUID
    let noteID: UUID
    let title: String
    let snippet: String
    let sourceTitle: String
    let anchorLabel: String
    let updatedAt: Date
    let tags: [String]
    let knowledgePointTitles: [String]
    let hasInk: Bool
}
