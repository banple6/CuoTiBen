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

    /// 当前分析任务，用于取消
    private var analysisTask: Task<Void, Never>?

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

    /// 取消正在进行的分析请求
    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        isLoadingAnalysis = false
    }

    func loadAnalysis(using appViewModel: AppViewModel) async {
        // 取消之前的分析请求
        analysisTask?.cancel()

        // 捕获当前 sentenceID 以检测竞态
        let targetSentenceID = selectedSentenceID

        guard let sentence = selectedSentence else {
            analysisResult = nil
            return
        }

        isLoadingAnalysis = true
        analysisError = nil

        let task = Task { @MainActor [weak self] in
            defer {
                // 仅当仍是同一请求时重置 loading
                if self?.selectedSentenceID == targetSentenceID {
                    self?.isLoadingAnalysis = false
                }
            }

            do {
                try Task.checkCancellation()
                let context = appViewModel.explainSentenceContext(for: sentence, in: document)

                // 30 秒超时
                let result = try await withThrowingTaskGroup(of: AIExplainSentenceResult.self) { group in
                    group.addTask {
                        try await AIExplainSentenceService.fetchExplanation(for: context)
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 30_000_000_000)
                        throw CancellationError()
                    }
                    let first = try await group.next()!
                    group.cancelAll()
                    return first
                }

                try Task.checkCancellation()

                // 竞态检查：sentence 是否已变更
                guard self?.selectedSentenceID == targetSentenceID else { return }

                self?.analysisResult = result
                self?.analysisError = nil
            } catch is CancellationError {
                // 被取消，不更新状态
            } catch {
                guard self?.selectedSentenceID == targetSentenceID else { return }
                self?.analysisError = "解析失败：\(error.localizedDescription)"
                self?.analysisResult = nil
            }
        }

        analysisTask = task
        await task.value
    }
}
