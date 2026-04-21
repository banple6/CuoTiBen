import Combine
import Foundation

@MainActor
final class ArchivistWorkspaceViewModel: ObservableObject {
    let document: SourceDocument
    let bundle: StructuredSourceBundle

    @Published var selectedSentenceID: String? {
        didSet {
            guard selectedSentenceID != oldValue else { return }
            handleSelectedSentenceChange()
        }
    }
    @Published var selectedNodeID: String?
    @Published var analysisResult: AIExplainSentenceResult?
    @Published var isLoadingAnalysis = false
    @Published var analysisError: String?

    /// 当前分析任务，用于取消
    private var analysisTask: Task<Void, Never>?
    private var currentAnalysisIdentity: AIRequestIdentity?

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

        handleSelectedSentenceChange()
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

    var selectedParagraphCard: ParagraphTeachingCard? {
        if let selectedSentence {
            return bundle.paragraphCard(forSegmentID: selectedSentence.segmentID)
        }
        if let selectedNode {
            return bundle.paragraphCard(forSegmentID: selectedNode.primarySegmentID ?? selectedNode.anchor.segmentID)
        }
        return bundle.paragraphTeachingCards.first
    }

    private var bundledAnalysis: ProfessorSentenceAnalysis? {
        guard let selectedSentence else {
            return bundle.displayedSentenceCard(id: selectedSentenceID)?.analysis
        }

        guard let analysis = bundle.displayedSentenceCard(id: selectedSentence.id)?.analysis,
              analysis.isCompatible(with: selectedSentence.text) else {
            return nil
        }
        return analysis
    }

    var effectiveAnalysis: ProfessorSentenceAnalysis? {
        let bundled = bundledAnalysis
        if let sentence = selectedSentence,
           let remote = analysisResult,
           isResultVisible(remote, for: sentence) {
            let remoteAnalysis = remote.localFallbackAnalysis
            return remoteAnalysis.mergingFallback(bundled)
        }
        if analysisResult != nil {
            TextPipelineDiagnostics.log(
                "句子分析",
                "检测到不匹配的分析结果，已回退到本地教学卡 doc=\(document.id)",
                severity: .warning
            )
        }
        return bundled
    }

    var shouldAutoLoadAnalysis: Bool {
        guard !isLoadingAnalysis, analysisResult == nil, let selectedSentence else { return false }
        guard let bundled = bundledAnalysis else { return true }
        return bundled.shouldPreferSentenceExplain(for: selectedSentence.text)
    }

    var relatedEvidenceItems: [String] {
        guard let selectedSentence else { return [] }
        var items: [String] = []

        if let card = selectedParagraphCard {
            if let blindSpot = card.studentBlindSpot?.nonEmpty {
                items.append("本段易偏点：\(blindSpot)")
            }
            if let focus = card.teachingFocuses.first?.nonEmpty {
                items.append("本段教学重点：\(focus)")
            }
        }

        items.append(contentsOf: bundle.questionLinks
            .filter { link in
                link.supportingSentenceIDs.contains(selectedSentence.id) ||
                link.supportParagraphIDs.contains(selectedSentence.segmentID)
            }
            .prefix(2)
            .map { link in
                let trap = link.trapType.nonEmpty ?? "题目证据"
                let evidence = link.paraphraseEvidence.first?.nonEmpty ?? String(link.questionText.prefix(48))
                return "\(trap)：\(evidence)"
            })

        var seen: Set<String> = []
        return items.compactMap(\.nonEmpty).filter { seen.insert($0).inserted }
    }

    var headerSnapshot: ProfessorTeachingStatusSnapshot {
        ProfessorTeachingStatusSnapshot(
            documentTitle: document.title,
            currentSentenceAnchor: selectedSentence?.anchorLabel ?? selectedNode?.anchor.label ?? "等待定位",
            currentSentenceFunction: effectiveAnalysis?.renderedSentenceFunction.nonEmpty
                ?? "先在原文或教学树里选中一句，系统会把当前句的定位、主干和教学焦点同步到这里。",
            currentParagraphRole: selectedParagraphCard?.argumentRole.displayName ?? "段落角色待识别",
            currentTeachingFocus: selectedParagraphCard?.teachingFocuses.first?.nonEmpty
                ?? selectedParagraphCard?.theme.nonEmpty
                ?? "教学焦点待提取",
            currentMode: "句子讲解"
        )
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

        guard let sentence = selectedSentence else {
            currentAnalysisIdentity = nil
            analysisResult = nil
            analysisError = nil
            isLoadingAnalysis = false
            return
        }

        guard let targetIdentity = appViewModel.explainSentenceRequestIdentity(for: sentence, in: document) else {
            analysisResult = LocalSentenceFallbackBuilder.build(
                context: appViewModel.explainSentenceContext(for: sentence, in: document),
                requestIdentity: nil,
                structuredError: AIStructuredError.invalidRequest(message: "缺少 sentence identity 字段。")
            )
            analysisError = analysisResult?.displayFallbackMessage
            isLoadingAnalysis = false
            return
        }
        currentAnalysisIdentity = targetIdentity
        let currentDocument = document

        let task = Task { @MainActor [weak self] in
            defer {
                if self?.matchesCurrentSelection(identity: targetIdentity) == true {
                    self?.isLoadingAnalysis = false
                }
            }

            do {
                try Task.checkCancellation()
                let context = appViewModel.explainSentenceContext(for: sentence, in: currentDocument)

                // 新模型响应更慢，给工作台留足等待窗口，避免未完成就被本地超时打断。
                let result = try await withThrowingTaskGroup(of: AIExplainSentenceResult.self) { group in
                    group.addTask {
                        try await AIExplainSentenceService.fetchExplanationWithCache(
                            for: context,
                            requestIdentity: targetIdentity
                        )
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 80_000_000_000)
                        throw CancellationError()
                    }
                    let first = try await group.next()!
                    group.cancelAll()
                    return first
                }

                try Task.checkCancellation()

                guard let self else { return }

                guard self.matchesCurrentSelection(identity: targetIdentity) else {
                    TextPipelineDiagnostics.log(
                        "句子分析",
                        "分析结果返回时选中句已变化，静默丢弃 sentence=\(targetIdentity.sentenceID)",
                        severity: .warning
                    )
                    return
                }

                let warnings = AnalysisConsistencyGuard.warnings(
                    expectedIdentity: targetIdentity,
                    sentenceText: sentence.text,
                    analysis: result
                )
                guard warnings.isEmpty else {
                    TextPipelineDiagnostics.log(
                        "句子分析",
                        "分析结果身份或内容不一致，静默丢弃：\(warnings.joined(separator: "；")) sentence=\(targetIdentity.sentenceID)",
                        severity: .warning
                    )
                    self.analysisResult = nil
                    self.analysisError = nil
                    return
                }

                self.analysisResult = result
                self.analysisError = result.shouldShowFallbackBanner ? result.displayFallbackMessage : nil
            } catch is CancellationError {
                // 被取消，不更新状态
            } catch {
                guard let self, self.matchesCurrentSelection(identity: targetIdentity) else { return }
                self.analysisError = "解析失败：\(error.localizedDescription)"
                self.analysisResult = nil
            }
        }

        analysisTask = task
        await task.value
    }

    private func handleSelectedSentenceChange() {
        analysisTask?.cancel()
        analysisTask = nil
        analysisResult = nil
        analysisError = nil
        isLoadingAnalysis = false

        if let sentence = selectedSentence {
            currentAnalysisIdentity = AIRequestIdentity.make(document: document, sentence: sentence)
        } else {
            currentAnalysisIdentity = nil
        }
    }

    private func matchesCurrentSelection(identity: AIRequestIdentity) -> Bool {
        guard let sentence = selectedSentence else { return false }
        guard let currentIdentity = AIRequestIdentity.make(document: document, sentence: sentence) else {
            return false
        }
        return currentIdentity.matchesSemanticIdentity(identity)
    }

    private func isResultVisible(_ result: AIExplainSentenceResult, for sentence: Sentence) -> Bool {
        guard let identity = result.analysisIdentity else { return false }
        guard let expectedIdentity = AIRequestIdentity.make(document: document, sentence: sentence) else {
            return false
        }
        return AIResponseIdentityGuard.validate(
            expected: expectedIdentity,
            actual: identity
        ).isAllowed && AnalysisConsistencyGuard.warnings(
            expectedIdentity: expectedIdentity,
            sentenceText: sentence.text,
            analysis: result
        ).isEmpty
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
