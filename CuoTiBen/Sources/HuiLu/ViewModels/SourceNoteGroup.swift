import Foundation

struct SourceNoteGroup: Identifiable, Equatable, Hashable {
    let id: UUID
    let sourceID: UUID
    let sourceTitle: String
    let subtitle: String
    let noteCount: Int
    let updatedAt: Date
    let previewItems: [NoteSummaryItem]
}
