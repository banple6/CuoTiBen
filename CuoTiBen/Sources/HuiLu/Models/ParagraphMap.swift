import Foundation

struct ParagraphMap: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let segmentID: String
    let paragraphIndex: Int
    let anchorLabel: String
    let theme: String
    let argumentRole: ParagraphArgumentRole
    let coreSentenceID: String?
    let relationToPrevious: String
    let examValue: String
    let teachingFocuses: [String]
    let studentBlindSpot: String?
    let provenance: NodeProvenance
}
