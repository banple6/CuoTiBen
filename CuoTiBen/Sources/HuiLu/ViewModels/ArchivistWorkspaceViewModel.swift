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
    private var activeAnalysisKey: AIRequestIdentity.SemanticKey?

    init(document: SourceDocument, bundle: StructuredSourceBundle) {
        self.document = document
        self.bundle = bundle

        if let firstSentence = bundle.sentences.first(where: { Self.isPassageSentence($0, in: bundle) }) {
            selectedSentenceID = firstSentence.id
            selectedNodeID = bundle.bestOutlineNode(forSentenceID: firstSentence.id)?.id
        } else if let firstNode = bundle.flattenedOutlineNodes().first {
            selectedNodeID = firstNode.id
            selectedSentenceID = nil
        }

        handleSelectedSentenceChange()
    }

    var selectedSentence: Sentence? {
        guard let sentence = bundle.sentence(id: selectedSentenceID),
              Self.isPassageSentence(sentence, in: bundle)
        else { return nil }
        return sentence
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
        guard let selectedSentence else { return nil }
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
            if remote.usedFallback || remote.fallbackAvailable {
                return remoteAnalysis
            }
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
        guard !isLoadingAnalysis, let selectedSentence else { return false }
        if let analysisResult, isResultVisible(analysisResult, for: selectedSentence) {
            return false
        }
        return true
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
        let materialMode = bundle.passageAnalysisDiagnostics?.materialMode ?? .passageReading
        let isSentenceMode = materialMode == .passageReading && selectedSentence != nil
        let structureTitle = materialMode.structureTitle
        return ProfessorTeachingStatusSnapshot(
            documentTitle: document.title,
            currentSentenceAnchor: selectedSentence?.anchorLabel ?? selectedNode?.anchor.label ?? "等待定位",
            currentSentenceFunction: effectiveAnalysis?.renderedSentenceFunction.nonEmpty
                ?? (isSentenceMode
                    ? "先在原文或教学树里选中一句，系统会把当前句的定位、主干和教学焦点同步到这里。"
                    : "当前资料按\(structureTitle)展示，不进入句子主干解析。"),
            currentParagraphRole: selectedParagraphCard?.argumentRole.displayName
                ?? (isSentenceMode ? "段落角色待识别" : "本地结构骨架"),
            currentTeachingFocus: selectedParagraphCard?.teachingFocuses.first?.nonEmpty
                ?? selectedParagraphCard?.theme.nonEmpty
                ?? (isSentenceMode ? "教学焦点待提取" : materialMode.statusTitle),
            currentMode: isSentenceMode ? "句子讲解" : structureTitle
        )
    }

    func selectSentence(_ sentence: Sentence) {
        guard Self.isPassageSentence(sentence, in: bundle) else {
            selectedSentenceID = nil
            selectedNodeID = bundle.bestOutlineNode(forSentenceID: sentence.id)?.id
                ?? bundle.bestOutlineNode(forSegmentID: sentence.segmentID)?.id
                ?? selectedNodeID
            return
        }
        TextPipelineDiagnostics.log(
            "AI",
            "[AI][SentenceExplain] selection_changed sentence_id=\(sentence.id) segment_id=\(sentence.segmentID) anchor_label=\(sentence.anchorLabel)",
            severity: .info
        )
        selectedSentenceID = sentence.id
        selectedNodeID = bundle.bestOutlineNode(forSentenceID: sentence.id)?.id
    }

    func selectNode(_ node: OutlineNode) {
        selectedNodeID = node.id
        if let sentenceID = node.primarySentenceID ?? node.anchor.sentenceID,
           let sentence = bundle.sentence(id: sentenceID),
           Self.isPassageSentence(sentence, in: bundle) {
            selectedSentenceID = sentenceID
        } else {
            selectedSentenceID = nil
        }
    }

    func anchorLabel(for node: OutlineNode?) -> String {
        guard let node else { return "等待定位" }
        return node.anchor.label
    }

    /// 取消正在进行的分析请求
    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        activeAnalysisKey = nil
        isLoadingAnalysis = false
    }

    func loadAnalysis(using appViewModel: AppViewModel) async {
        guard let sentence = selectedSentence else {
            currentAnalysisIdentity = nil
            activeAnalysisKey = nil
            analysisResult = nil
            analysisError = nil
            isLoadingAnalysis = false
            return
        }

        guard let targetIdentity = appViewModel.explainSentenceRequestIdentity(for: sentence, in: document) else {
            let context = appViewModel.explainSentenceContext(for: sentence, in: document)
            _ = try? ExplainSentenceRequestBuilder.prepare(context: context, requestIdentity: nil)
            analysisResult = LocalSentenceFallbackBuilder.build(
                context: context,
                requestIdentity: nil,
                structuredError: AIStructuredError.invalidRequest(message: "缺少 sentence identity 字段。")
            )
            analysisError = analysisResult?.displayFallbackMessage
            isLoadingAnalysis = false
            return
        }

        if isLoadingAnalysis, activeAnalysisKey == targetIdentity.semanticKey {
            TextPipelineDiagnostics.log(
                "AI",
                "[AI][SentenceExplain] skip duplicate active request sentence_id=\(targetIdentity.sentenceID)",
                severity: .info
            )
            return
        }

        analysisTask?.cancel()
        analysisTask = nil
        currentAnalysisIdentity = targetIdentity
        activeAnalysisKey = targetIdentity.semanticKey
        isLoadingAnalysis = true
        analysisError = nil
        let currentDocument = document

        let task = Task { @MainActor [weak self] in
            defer {
                if self?.matchesCurrentSelection(identity: targetIdentity) == true {
                    self?.isLoadingAnalysis = false
                    self?.activeAnalysisKey = nil
                }
            }

            do {
                try Task.checkCancellation()
                let context = appViewModel.explainSentenceContext(for: sentence, in: currentDocument)
                let result = try await AIExplainSentenceService.fetchExplanationWithCache(
                    for: context,
                    requestIdentity: targetIdentity
                )

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
                TextPipelineDiagnostics.log(
                    "AI",
                    [
                        "[AI][SentenceExplain] ui_state_applied",
                        "sentence_id=\(targetIdentity.sentenceID)",
                        "request_id=\(result.requestID ?? "nil")",
                        "used_fallback=\(result.usedFallback)",
                        "used_cache=\(result.usedCache)",
                        "is_ai_generated=\(result.localFallbackAnalysis.isAIGenerated)"
                    ].joined(separator: " "),
                    severity: .info
                )
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
        activeAnalysisKey = nil
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

    private static func isPassageSentence(_ sentence: Sentence, in bundle: StructuredSourceBundle) -> Bool {
        let materialMode = bundle.passageAnalysisDiagnostics?.materialMode ?? .passageReading
        return materialMode == .passageReading && sentence.provenance.sourceKind == .passageBody
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
