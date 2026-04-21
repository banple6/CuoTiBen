import Foundation

struct PassageMap: Codable, Equatable, Hashable {
    let documentID: String
    let sourceID: String
    let title: String
    let articleTheme: String
    let authorCoreQuestion: String
    let progressionPath: String
    let paragraphMaps: [ParagraphMap]
    let keySentenceIDs: [String]
    let questionLinks: [QuestionEvidenceLink]
    let diagnostics: [MindMapAdmissionDiagnostic]

    func withDiagnostics(_ diagnostics: [MindMapAdmissionDiagnostic]) -> PassageMap {
        PassageMap(
            documentID: documentID,
            sourceID: sourceID,
            title: title,
            articleTheme: articleTheme,
            authorCoreQuestion: authorCoreQuestion,
            progressionPath: progressionPath,
            paragraphMaps: paragraphMaps,
            keySentenceIDs: keySentenceIDs,
            questionLinks: questionLinks,
            diagnostics: diagnostics
        )
    }
}
