import Combine
import Foundation

@MainActor
final class ArchivistWorkspaceViewModel: ObservableObject {
    let document: SourceDocument
    let bundle: StructuredSourceBundle

    @Published var selectedSentenceID: String?
    @Published var selectedNodeID: String?
    @Published var analysisResult: AIExplainSentenceResult?
    @Published var isLoadingAnalysis = false
    @Published var analysisError: String?

    init(document: SourceDocument, bundle: StructuredSourceBundle) {
        self.document = document
        self.bundle = bundle

        if let firstSentence = bundle.sentences.first {
            selectedSentenceID = firstSentence.id
            selectedNodeID = bundle.bestOutlineNode(forSentenceID: firstSentence.id)?.id
        } else if let firstNode = bundle.flattenedOutlineNodes().first {
            selectedNodeID = firstNode.id
            selectedSentenceID = firstNode.primarySentenceID ?? firstNode.anchor.sentenceID
        }
    }

    var selectedSentence: Sentence? {
        bundle.sentence(id: selectedSentenceID)
    }

    var selectedNode: OutlineNode? {
        if let selectedNodeID, let node = bundle.outlineNode(id: selectedNodeID) {
            return node
        }
        return bundle.bestOutlineNode(forSentenceID: selectedSentenceID)
    }

    var flattenedOutlineNodes: [OutlineNode] {
        bundle.flattenedOutlineNodes()
    }

    var headerTags: [String] {
        var tags = [
            "Source: \(document.title)",
            "Type: \(document.documentType.displayName)",
            "Pages: \(max(document.pageCount, bundle.source.pageCount))"
        ]

        let topical = document.topicTags
            .prefix(2)
            .map { "Topic: \($0)" }

        tags.append(contentsOf: topical)
        return tags
    }

    func selectSentence(_ sentence: Sentence) {
        selectedSentenceID = sentence.id
        selectedNodeID = bundle.bestOutlineNode(forSentenceID: sentence.id)?.id
    }

    func selectNode(_ node: OutlineNode) {
        selectedNodeID = node.id
        if let sentenceID = node.primarySentenceID ?? node.anchor.sentenceID {
            selectedSentenceID = sentenceID
        } else if let segmentID = node.primarySegmentID ?? node.anchor.segmentID,
                  let sentence = bundle.sentences.first(where: { $0.segmentID == segmentID }) {
            selectedSentenceID = sentence.id
        }
    }

    func anchorLabel(for node: OutlineNode?) -> String {
        guard let node else { return "Awaiting context" }
        return node.anchor.label
    }

    func loadAnalysis(using appViewModel: AppViewModel) async {
        guard let sentence = selectedSentence else {
            analysisResult = nil
            return
        }

        isLoadingAnalysis = true
        analysisError = nil

        do {
            let context = appViewModel.explainSentenceContext(for: sentence, in: document)
            analysisResult = try await AIExplainSentenceService.fetchExplanation(for: context)
        } catch {
            analysisError = error.localizedDescription
            analysisResult = nil
        }

        isLoadingAnalysis = false
    }
}
