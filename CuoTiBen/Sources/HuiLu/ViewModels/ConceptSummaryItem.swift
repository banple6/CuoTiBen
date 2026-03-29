import Foundation

struct ConceptSummaryItem: Identifiable, Equatable, Hashable {
    let id: String
    let knowledgePointID: String
    let title: String
    let definition: String
    let noteCount: Int
    let sourceCount: Int
    let previewSourceTitle: String?
    let relatedPointTitles: [String]
}
