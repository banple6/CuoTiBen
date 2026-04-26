import SwiftUI

private enum ReviewWorkbenchPanelKind {
    case empty
    case sentence
    case node
    case word
}

struct ReviewWorkbenchView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    let document: SourceDocument
    let initialAnchor: SourceAnchor?
    let onClose: () -> Void

    @State private var selectedSentence: Sentence?
    @State private var selectedNode: OutlineNode?
    @State private var selectedWord: WordExplanationEntry?
    @State private var panelKind: ReviewWorkbenchPanelKind = .empty
    @State private var highlightedSentenceID: String?
    @State private var highlightedSegmentIDs: Set<String> = []
    @State private var highlightedNodeID: String?
    @State private var jumpTargetSentenceID: String?
    @State private var jumpTargetSegmentID: String?
    @State private var jumpTargetOutlineNodeID: String?
    @State private var hasRestoredInitialState = false
    @State private var showsPhoneAnalysisDrawer = false
    @State private var showsPadOutlineWorkspace = false
    @State private var phoneDrawerDetent: PresentationDetent = .large
    @State private var padSplitRatio: CGFloat = 0.56
    @State private var padDragStartRatio: CGFloat?
    @State private var isEnsuringProfessorAnalysis = false

    private var liveDocument: SourceDocument {
        viewModel.sourceDocuments.first(where: { $0.id == document.id }) ?? document
    }

    private var structuredSource: StructuredSourceBundle? {
        viewModel.structuredSource(for: liveDocument)
    }

    private var progress: ReviewWorkbenchProgress {
        viewModel.reviewWorkbenchProgress(for: liveDocument)
    }

    private var currentSentence: Sentence? {
        if let selectedSentence {
            return selectedSentence
        }

        if let sentenceID = selectedNode?.primarySentenceID {
            return structuredSource?.sentence(id: sentenceID)
        }

        return structuredSource?.sentence(id: progress.lastSentenceID)
    }

    private var currentNode: OutlineNode? {
        if let selectedNode {
            return selectedNode
        }

        return viewModel.currentWorkbenchNode(
            for: liveDocument,
            sentenceID: currentSentence?.id ?? progress.lastSentenceID,
            nodeID: progress.lastOutlineNodeID
        )
    }

    private var selectedNodeSnapshot: OutlineNodeDetailSnapshot? {
        guard let currentNode else { return nil }
        return viewModel.outlineNodeDetail(for: currentNode, in: liveDocument)
    }

    private var currentPageLabel: String {
        currentSentence?.page.map { "第\($0)页" } ?? "未定位页码"
    }

    private var currentSentenceLabel: String {
        guard let currentSentence else {
            return progress.lastAnchorLabel
        }

        return "第\(currentSentence.localIndex + 1)句"
    }

    private var currentNodeLabel: String {
        currentNode?.title ?? "未选中结构节点"
    }

    private var masteryValue: Int {
        viewModel.workbenchMastery(for: liveDocument)
    }

    private var highlightedWordToken: String? {
        guard panelKind == .sentence || panelKind == .word else { return nil }
        return selectedWord?.term
    }

    private var outlineAncestorNodeIDs: [String] {
        guard let structuredSource else { return [] }
        return structuredSource.ancestorNodeIDs(
            for: jumpTargetOutlineNodeID ?? highlightedNodeID
        )
    }

    private var usesPhoneLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    init(
        document: SourceDocument,
        initialAnchor: SourceAnchor? = nil,
        onClose: @escaping () -> Void
    ) {
        self.document = document
        self.initialAnchor = initialAnchor
        self.onClose = onClose
    }

    var body: some View {
        GeometryReader { proxy in
            let usesPadLayout = !usesPhoneLayout && proxy.size.width >= 820
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = max(proxy.safeAreaInsets.bottom, 12)

            ZStack {
                PaperCanvasBackground()

                VStack(spacing: usesPadLayout ? 18 : 10) {
                    ReviewWorkbenchHeader(
                        title: liveDocument.title,
                        pageLabel: currentPageLabel,
                        sentenceLabel: currentSentenceLabel,
                        nodeLabel: currentNodeLabel,
                        masteryValue: masteryValue,
                        usesCompactChrome: !usesPadLayout,
                        onClose: onClose
                    )

                    if let structuredSource {
                        if usesPadLayout {
                            padSplitLayout(
                                bundle: structuredSource,
                                size: proxy.size,
                                safeBottom: safeBottom
                            )
                        } else {
                            compactSplitLayout(
                                bundle: structuredSource,
                                size: proxy.size,
                                safeBottom: safeBottom
                            )
                        }
                    } else {
                        loadingStateCard
                    }
                }
                .padding(.top, safeTop + (usesPadLayout ? 8 : 2))
                .padding(.horizontal, usesPadLayout ? 24 : 12)
                .padding(.bottom, safeBottom)

                if showsPadOutlineWorkspace, let structuredSource {
                    MindMapWorkspaceOverlay(
                        documentTitle: liveDocument.title,
                        bundle: structuredSource,
                        focusSentenceID: highlightedSentenceID,
                        focusSegmentIDs: highlightedSegmentIDs,
                        onNodeTap: { node in
                            handleMindMapNodeSelection(
                                node,
                                revealAnalysisOnPhone: false
                            )
                        },
                        onClose: {
                            showsPadOutlineWorkspace = false
                        },
                        onRegenerate: {
                            Task {
                                await viewModel.ensureProfessorAnalysis(
                                    for: liveDocument,
                                    trigger: .openReviewWorkbench,
                                    force: true
                                )
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
                    .zIndex(20)
                }
            }
            .ignoresSafeArea()
        }
        .task(id: liveDocument.id) {
            await prepareWorkbench()
        }
        .onChange(of: structuredSource?.source.id) { _ in
            restoreInitialStateIfNeeded()
            guard structuredSource != nil else { return }
            Task {
                await ensureWorkbenchProfessorAnalysisIfNeeded()
            }
        }
        .sheet(isPresented: $showsPhoneAnalysisDrawer) {
            ReviewWorkbenchPhoneAnalysisDrawer(
                document: liveDocument,
                panelKind: panelKind,
                selectedSentence: selectedSentence,
                selectedNode: selectedNode,
                selectedWord: selectedWord,
                onSentenceTap: { sentence in
                    handleSentenceSelection(sentence)
                },
                onAnchorTap: handleAnchorSelection,
                onWordTap: handleWordSelection
            )
            .environmentObject(viewModel)
            .presentationDetents([.fraction(0.72), .large], selection: $phoneDrawerDetent)
            .presentationDragIndicator(.visible)
        }
    }

    private func padSplitLayout(
        bundle: StructuredSourceBundle,
        size: CGSize,
        safeBottom: CGFloat
    ) -> some View {
        GeometryReader { proxy in
            let splitterWidth: CGFloat = 28
            let totalWidth = proxy.size.width
            let usableWidth = max(totalWidth - splitterWidth, 1)
            let minPaneWidth = max(min(totalWidth * 0.28, 420), 320)
            let clampedRatio = clampedPadSplitRatio(
                proposed: padSplitRatio,
                totalWidth: usableWidth,
                minPaneWidth: minPaneWidth
            )
            let leftWidth = usableWidth * clampedRatio
            let rightWidth = usableWidth - leftWidth

            HStack(spacing: 0) {
                ReviewWorkbenchOriginalPane(
                    document: liveDocument,
                    bundle: bundle,
                    readerMode: viewModel.sourceReaderMode,
                    currentNodeSnapshot: selectedNodeSnapshot,
                    currentNodeTitle: currentNode?.title,
                    highlightedSentenceID: highlightedSentenceID,
                    highlightedWordToken: highlightedWordToken,
                    highlightedSegmentIDs: highlightedSegmentIDs,
                    jumpTargetSentenceID: jumpTargetSentenceID,
                    jumpTargetSegmentID: jumpTargetSegmentID,
                    currentAnchorLabel: currentSentence?.anchorLabel ?? progress.lastAnchorLabel,
                    usesCompactChrome: false,
                    previousSentence: currentSentence.flatMap { viewModel.previousSentence(for: $0, in: liveDocument) },
                    nextSentence: currentSentence.flatMap { viewModel.nextSentence(for: $0, in: liveDocument) },
                    onSentenceTap: { sentence in
                        handleSentenceSelection(sentence)
                    },
                    onWordTap: handlePDFWordSelection,
                    onAnchorTap: handleAnchorSelection,
                    onCurrentNodeTap: {
                        if let currentNode {
                            handleNodeSelection(currentNode)
                        }
                    },
                    onPreviousSentence: selectPreviousSentence,
                    onNextSentence: selectNextSentence,
                    onJumpHandled: handleOriginalJumpHandled
                )
                .frame(width: leftWidth)

                WorkbenchSplitHandle()
                    .frame(width: splitterWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let startRatio = padDragStartRatio ?? clampedRatio
                                if padDragStartRatio == nil {
                                    padDragStartRatio = clampedRatio
                                }

                                let proposed = startRatio + (value.translation.width / usableWidth)
                                padSplitRatio = clampedPadSplitRatio(
                                    proposed: proposed,
                                    totalWidth: usableWidth,
                                    minPaneWidth: minPaneWidth
                                )
                            }
                            .onEnded { _ in
                                padDragStartRatio = nil
                            }
                    )

                ReviewWorkbenchAnalysisPane(
                    document: liveDocument,
                    bundle: bundle,
                    analysisStatusMessage: viewModel.structuredSourceError(for: liveDocument),
                    usesPadLayout: true,
                    showsOutlineButton: true,
                    panelKind: panelKind,
                    selectedSentence: selectedSentence,
                    selectedNode: selectedNode,
                    selectedWord: selectedWord,
                    highlightedNodeID: highlightedNodeID,
                    jumpTargetNodeID: jumpTargetOutlineNodeID,
                    ancestorNodeIDs: outlineAncestorNodeIDs,
                    onNodeTap: { node in
                        handleNodeSelection(node)
                    },
                    onOutlineJumpHandled: handleOutlineJumpHandled,
                    onSentenceTap: { sentence in
                        handleSentenceSelection(sentence)
                    },
                    onAnchorTap: handleAnchorSelection,
                    onWordTap: handleWordSelection,
                    onShowOutline: {
                        showsPadOutlineWorkspace = true
                    },
                    onRetryPassageAnalysis: {
                        Task {
                            await viewModel.ensureProfessorAnalysis(
                                for: liveDocument,
                                trigger: .openReviewWorkbench,
                                force: true
                            )
                        }
                    }
                )
                .frame(width: rightWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func compactSplitLayout(
        bundle: StructuredSourceBundle,
        size: CGSize,
        safeBottom: CGFloat
    ) -> some View {
        let availableHeight = max(size.height - 116 - safeBottom, 460)

        return VStack(spacing: 0) {
            ReviewWorkbenchOriginalPane(
                document: liveDocument,
                bundle: bundle,
                readerMode: viewModel.sourceReaderMode,
                currentNodeSnapshot: selectedNodeSnapshot,
                currentNodeTitle: currentNode?.title,
                highlightedSentenceID: highlightedSentenceID,
                highlightedWordToken: highlightedWordToken,
                highlightedSegmentIDs: highlightedSegmentIDs,
                jumpTargetSentenceID: jumpTargetSentenceID,
                jumpTargetSegmentID: jumpTargetSegmentID,
                currentAnchorLabel: currentSentence?.anchorLabel ?? progress.lastAnchorLabel,
                usesCompactChrome: true,
                previousSentence: currentSentence.flatMap { viewModel.previousSentence(for: $0, in: liveDocument) },
                nextSentence: currentSentence.flatMap { viewModel.nextSentence(for: $0, in: liveDocument) },
                onSentenceTap: { sentence in
                    handleSentenceSelection(sentence)
                },
                onWordTap: handlePDFWordSelection,
                onAnchorTap: handleAnchorSelection,
                onCurrentNodeTap: {
                    if let currentNode {
                        handleNodeSelection(currentNode)
                    }
                },
                onPreviousSentence: selectPreviousSentence,
                onNextSentence: selectNextSentence,
                onJumpHandled: handleOriginalJumpHandled
            )
            .frame(minHeight: availableHeight * 0.8, maxHeight: .infinity)
        }
    }

    private var loadingStateCard: some View {
        GlassPanel(tone: .light, cornerRadius: 32, padding: 24) {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.isLoadingStructuredSource(for: liveDocument) {
                    ProgressView()
                    Text("正在恢复这份资料的原文和结构树…")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.74))
                } else if let error = viewModel.structuredSourceError(for: liveDocument) {
                    Text("资料复盘工作台暂不可用")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.82))

                    Text(error)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.62))

                    Button("重新加载") {
                        Task {
                            await viewModel.loadStructuredSource(for: liveDocument, force: true)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.blue.opacity(0.8))
                } else {
                    Text("点击资料后，这里会显示原文、高亮定位和解析分析。")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.62))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func prepareWorkbench() async {
        if structuredSource == nil {
            await viewModel.loadStructuredSource(for: liveDocument)
        }

        restoreInitialStateIfNeeded()

        await ensureWorkbenchProfessorAnalysisIfNeeded()
    }

    private func ensureWorkbenchProfessorAnalysisIfNeeded() async {
        guard viewModel.structuredSource(for: liveDocument) != nil else { return }
        guard !isEnsuringProfessorAnalysis else { return }

        isEnsuringProfessorAnalysis = true
        defer { isEnsuringProfessorAnalysis = false }

        await viewModel.ensureProfessorAnalysis(
            for: liveDocument,
            trigger: .openReviewWorkbench
        )
    }

    private func restoreInitialStateIfNeeded() {
        guard !hasRestoredInitialState, let structuredSource else { return }
        hasRestoredInitialState = true

        if let initialAnchor {
            if let sentence = structuredSource.sentence(id: initialAnchor.sentenceID) {
                handleSentenceSelection(
                    sentence,
                    recordProgress: true,
                    shouldJump: true,
                    revealAnalysisOnPhone: false
                )
                return
            }

            if let node = structuredSource.outlineNode(id: initialAnchor.outlineNodeID) {
                handleNodeSelection(
                    node,
                    recordProgress: true,
                    shouldJump: true,
                    revealAnalysisOnPhone: false
                )
                return
            }
        }

        let restoredProgress = viewModel.restoreWorkbenchState(for: liveDocument)

        if let sentence = structuredSource.sentence(id: restoredProgress.lastSentenceID) {
            handleSentenceSelection(
                sentence,
                recordProgress: false,
                shouldJump: true,
                revealAnalysisOnPhone: false
            )
            return
        }

        if let node = structuredSource.outlineNode(id: restoredProgress.lastOutlineNodeID) {
            handleNodeSelection(
                node,
                recordProgress: false,
                shouldJump: true,
                revealAnalysisOnPhone: false
            )
            return
        }

        panelKind = .empty
        highlightedSentenceID = nil
        highlightedSegmentIDs = []
        highlightedNodeID = nil
    }

    private func handleSentenceSelection(
        _ sentence: Sentence,
        recordProgress: Bool = true,
        shouldJump: Bool = true,
        revealAnalysisOnPhone: Bool = true
    ) {
        guard let structuredSource else { return }
        let matchedNode = structuredSource.bestOutlineNode(forSentenceID: sentence.id)

        selectedSentence = sentence
        selectedNode = matchedNode
        selectedWord = nil
        panelKind = .sentence

        highlightedSentenceID = sentence.id
        highlightedSegmentIDs = [sentence.segmentID]
        highlightedNodeID = matchedNode?.id

        if shouldJump {
            jumpTargetSentenceID = sentence.id
            jumpTargetSegmentID = sentence.segmentID
            jumpTargetOutlineNodeID = matchedNode?.id
        }

        if recordProgress {
            viewModel.recordWorkbenchSelection(
                for: liveDocument,
                sentence: sentence,
                node: matchedNode
            )
        }

        if usesPhoneLayout, revealAnalysisOnPhone {
            phoneDrawerDetent = .large
            showsPhoneAnalysisDrawer = true
        }
    }

    private func handleNodeSelection(
        _ node: OutlineNode,
        recordProgress: Bool = true,
        shouldJump: Bool = true,
        revealAnalysisOnPhone: Bool = true
    ) {
        guard let structuredSource else { return }

        let anchorSentence = structuredSource.sentence(id: node.primarySentenceID ?? node.anchor.sentenceID)

        selectedNode = node
        selectedSentence = anchorSentence
        selectedWord = nil
        panelKind = .node

        highlightedNodeID = node.id
        highlightedSentenceID = anchorSentence?.id
        highlightedSegmentIDs = Set([anchorSentence?.segmentID, node.primarySegmentID].compactMap { $0 })

        if shouldJump {
            jumpTargetSentenceID = anchorSentence?.id
            jumpTargetSegmentID = anchorSentence?.segmentID ?? node.primarySegmentID
            jumpTargetOutlineNodeID = node.id
        }

        if recordProgress {
            viewModel.recordWorkbenchSelection(
                for: liveDocument,
                sentence: anchorSentence,
                node: node
            )
        }

        if usesPhoneLayout, revealAnalysisOnPhone {
            phoneDrawerDetent = .large
            showsPhoneAnalysisDrawer = true
        }
    }

    private func handleMindMapNodeSelection(
        _ node: MindMapNode,
        revealAnalysisOnPhone: Bool
    ) {
        guard let structuredSource else { return }

        if node.kind == .anchorSentence,
           let sentence = structuredSource.sentence(id: node.provenance.sourceSentenceID) {
            handleSentenceSelection(
                sentence,
                recordProgress: true,
                shouldJump: true,
                revealAnalysisOnPhone: revealAnalysisOnPhone
            )
            return
        }

        if let outlineNode = structuredSource.bestOutlineNode(forSentenceID: node.provenance.sourceSentenceID)
            ?? structuredSource.bestOutlineNode(forSegmentID: node.provenance.sourceSegmentID) {
            handleNodeSelection(
                outlineNode,
                recordProgress: true,
                shouldJump: true,
                revealAnalysisOnPhone: revealAnalysisOnPhone
            )
            return
        }

        if let sentence = structuredSource.sentences.first(where: { $0.segmentID == node.provenance.sourceSegmentID }) {
            handleSentenceSelection(
                sentence,
                recordProgress: true,
                shouldJump: true,
                revealAnalysisOnPhone: revealAnalysisOnPhone
            )
        }
    }

    private func handleWordSelection(_ entry: WordExplanationEntry) {
        selectedWord = entry
        panelKind = .word

        if usesPhoneLayout {
            phoneDrawerDetent = .large
            showsPhoneAnalysisDrawer = true
        }
    }

    private func handlePDFWordSelection(_ sentence: Sentence, token: String) {
        handleSentenceSelection(
            sentence,
            recordProgress: true,
            shouldJump: false,
            revealAnalysisOnPhone: true
        )

        selectedWord = viewModel.wordExplanation(
            for: token,
            sentence: sentence,
            in: liveDocument
        )
        panelKind = .sentence
    }

    private func handleAnchorSelection(_ anchor: OutlineNodeAnchorItem) {
        guard let structuredSource else { return }
        var matchedNode: OutlineNode?
        var matchedSentence: Sentence?

        if let sentence = structuredSource.sentence(id: anchor.sentenceID) {
            matchedSentence = sentence
            selectedSentence = sentence
            highlightedSentenceID = sentence.id
            highlightedSegmentIDs = [sentence.segmentID]
        } else {
            highlightedSentenceID = nil
            highlightedSegmentIDs = Set([anchor.segmentID].compactMap { $0 })
        }

        jumpTargetSentenceID = anchor.sentenceID
        jumpTargetSegmentID = anchor.segmentID

        if let segmentID = anchor.segmentID,
           let node = structuredSource.bestOutlineNode(forSegmentID: segmentID) {
            matchedNode = node
            selectedNode = node
            highlightedNodeID = node.id
            jumpTargetOutlineNodeID = node.id
            if panelKind == .empty {
                panelKind = .node
            }
        }

        if usesPhoneLayout {
            if let matchedSentence {
                selectedSentence = matchedSentence
                panelKind = .sentence
            } else if let matchedNode {
                selectedNode = matchedNode
                panelKind = .node
            }
            phoneDrawerDetent = .large
            showsPhoneAnalysisDrawer = true
        }
    }

    private func selectPreviousSentence() {
        guard let currentSentence,
              let previousSentence = viewModel.previousSentence(for: currentSentence, in: liveDocument) else {
            return
        }

        handleSentenceSelection(previousSentence)
    }

    private func selectNextSentence() {
        guard let currentSentence,
              let nextSentence = viewModel.nextSentence(for: currentSentence, in: liveDocument) else {
            return
        }

        handleSentenceSelection(nextSentence)
    }

    private func handleOriginalJumpHandled() {
        jumpTargetSentenceID = nil
        jumpTargetSegmentID = nil
    }

    private func handleOutlineJumpHandled() {
        jumpTargetOutlineNodeID = nil
    }

    private func clampedPadSplitRatio(
        proposed: CGFloat,
        totalWidth: CGFloat,
        minPaneWidth: CGFloat
    ) -> CGFloat {
        let minRatio = minPaneWidth / totalWidth
        let maxRatio = 1 - minRatio
        return min(max(proposed, minRatio), maxRatio)
    }

}

private struct WorkbenchSplitHandle: View {
    var body: some View {
        VStack(spacing: 10) {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.96))
                .frame(width: 4, height: 76)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.82), lineWidth: 1)
                )
                .shadow(color: Color.blue.opacity(0.12), radius: 10, y: 6)

            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Image(systemName: "chevron.right")
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.28))
        }
        .frame(maxHeight: .infinity)
        .padding(.vertical, 18)
    }
}

private struct ReviewWorkbenchHeader: View {
    let title: String
    let pageLabel: String
    let sentenceLabel: String
    let nodeLabel: String
    let masteryValue: Int
    let usesCompactChrome: Bool
    let onClose: () -> Void

    var body: some View {
        PaperSheetCard(
            padding: usesCompactChrome ? 12 : 18,
            cornerRadius: usesCompactChrome ? 22 : 28,
            accent: AppPalette.paperTape,
            showsTape: !usesCompactChrome
        ) {
            VStack(alignment: .leading, spacing: usesCompactChrome ? 6 : 10) {
                HStack(alignment: .top, spacing: usesCompactChrome ? 8 : 16) {
                    VStack(alignment: .leading, spacing: usesCompactChrome ? 4 : 8) {
                        Text(title)
                            .font(.system(size: usesCompactChrome ? 16 : 28, weight: .semibold, design: .serif))
                            .foregroundStyle(AppPalette.paperInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }

                    Spacer(minLength: 8)

                    Button(action: onClose) {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                            if !usesCompactChrome {
                                Text("关闭")
                            }
                        }
                        .font(.system(size: usesCompactChrome ? 16 : 15, weight: .medium))
                        .foregroundStyle(AppPalette.paperMuted)
                    }
                    .buttonStyle(.plain)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: usesCompactChrome ? 8 : 10) {
                        MetricCapsule(label: pageLabel, tone: .light, tint: Color.blue)
                        MetricCapsule(label: sentenceLabel, tone: .light, tint: Color.cyan)
                        MetricCapsule(label: "掌握度 \(masteryValue)%", tone: .light, tint: AppPalette.mint)
                    }
                    .padding(.vertical, 1)
                }

                Text(nodeLabel)
                    .font(.system(size: usesCompactChrome ? 12 : 14, weight: .medium))
                    .foregroundStyle(AppPalette.paperMuted)
                    .lineLimit(1)
            }
        }
    }
}

private struct ReviewWorkbenchOriginalPane: View {
    let document: SourceDocument
    let bundle: StructuredSourceBundle
    let readerMode: SourceReaderMode
    let currentNodeSnapshot: OutlineNodeDetailSnapshot?
    let currentNodeTitle: String?
    let highlightedSentenceID: String?
    let highlightedWordToken: String?
    let highlightedSegmentIDs: Set<String>
    let jumpTargetSentenceID: String?
    let jumpTargetSegmentID: String?
    let currentAnchorLabel: String
    let usesCompactChrome: Bool
    let previousSentence: Sentence?
    let nextSentence: Sentence?
    let onSentenceTap: (Sentence) -> Void
    let onWordTap: (Sentence, String) -> Void
    let onAnchorTap: (OutlineNodeAnchorItem) -> Void
    let onCurrentNodeTap: () -> Void
    let onPreviousSentence: () -> Void
    let onNextSentence: () -> Void
    let onJumpHandled: () -> Void

    @State private var showsAllAnchors = false

    var body: some View {
        PaperSheetCard(
            padding: usesCompactChrome ? 12 : 18,
            cornerRadius: usesCompactChrome ? 24 : 30,
            accent: AppPalette.paperTapeBlue,
            showsTape: true
        ) {
            VStack(alignment: .leading, spacing: usesCompactChrome ? 8 : 14) {
                header

                if let currentNodeSnapshot, !currentNodeSnapshot.anchorItems.isEmpty {
                    anchorRow(currentNodeSnapshot.anchorItems)
                }

                if let currentNodeTitle, usesCompactChrome {
                    currentNodeButton(title: currentNodeTitle)
                }

                controls

                StructuredSourcePDFReader(
                    document: document,
                    bundle: bundle,
                    renderMode: readerMode,
                    highlightedSentenceID: highlightedSentenceID,
                    highlightedWordToken: highlightedWordToken,
                    jumpTargetSentenceID: jumpTargetSentenceID,
                    jumpTargetSegmentID: jumpTargetSegmentID,
                    onSentenceTap: onSentenceTap,
                    onWordTap: onWordTap,
                    onJumpHandled: onJumpHandled
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.88), lineWidth: 1)
                )
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(AppPalette.paperCard)
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            MarkerTitle(text: "原文", tint: AppPalette.paperHighlight)

            Text(currentAnchorLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.blue.opacity(0.72))
                .lineLimit(1)

            Spacer()

            if usesCompactChrome {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.32))
            }
        }
    }

    private func anchorRow(_ anchors: [OutlineNodeAnchorItem]) -> some View {
        VStack(alignment: .leading, spacing: usesCompactChrome ? 6 : 10) {
            HStack {
                    Text("当前节点来源")
                        .font(.system(size: usesCompactChrome ? 13 : 14, weight: .bold))
                        .foregroundStyle(AppPalette.paperInk.opacity(0.78))

                Spacer()

                if usesCompactChrome && anchors.count > 1 {
                    Button(showsAllAnchors ? "收起" : "展开") {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                            showsAllAnchors.toggle()
                        }
                    }
                    .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.blue.opacity(0.78))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(displayedAnchors(from: anchors)) { anchor in
                        Button {
                            onAnchorTap(anchor)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "bookmark.fill")
                                Text(anchor.label)
                                    .lineLimit(1)
                            }
                        .font(.system(size: 12, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.blue.opacity(0.8))
                            .padding(.horizontal, usesCompactChrome ? 10 : 12)
                            .padding(.vertical, usesCompactChrome ? 8 : 9)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.72))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func currentNodeButton(title: String) -> some View {
        Button(action: onCurrentNodeTap) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前结构节点")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.45))

                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.76))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.blue.opacity(0.72))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }

    private var controls: some View {
        Group {
            if usesCompactChrome {
                HStack(spacing: 10) {
                    CompactSentenceStepperButton(
                        icon: "chevron.left",
                        title: "上一句",
                        isDisabled: previousSentence == nil,
                        action: onPreviousSentence
                    )

                    CompactSentenceStepperButton(
                        icon: "chevron.right",
                        title: "下一句",
                        isDisabled: nextSentence == nil,
                        action: onNextSentence
                    )
                }
            } else {
                HStack(spacing: 10) {
                    DetailActionButton(title: "上一句", icon: "chevron.left", isDisabled: previousSentence == nil) {
                        onPreviousSentence()
                    }

                    DetailActionButton(title: "下一句", icon: "chevron.right", isDisabled: nextSentence == nil) {
                        onNextSentence()
                    }
                }
            }
        }
    }

    private func displayedAnchors(from anchors: [OutlineNodeAnchorItem]) -> [OutlineNodeAnchorItem] {
        if usesCompactChrome, !showsAllAnchors {
            return Array(anchors.prefix(1))
        }
        return anchors
    }
}

private struct ReviewWorkbenchAnalysisPane: View {
    let document: SourceDocument
    let bundle: StructuredSourceBundle
    let analysisStatusMessage: String?
    let usesPadLayout: Bool
    let showsOutlineButton: Bool
    let panelKind: ReviewWorkbenchPanelKind
    let selectedSentence: Sentence?
    let selectedNode: OutlineNode?
    let selectedWord: WordExplanationEntry?
    let highlightedNodeID: String?
    let jumpTargetNodeID: String?
    let ancestorNodeIDs: [String]
    let onNodeTap: (OutlineNode) -> Void
    let onOutlineJumpHandled: () -> Void
    let onSentenceTap: (Sentence) -> Void
    let onAnchorTap: (OutlineNodeAnchorItem) -> Void
    let onWordTap: (WordExplanationEntry) -> Void
    let onShowOutline: () -> Void
    let onRetryPassageAnalysis: () -> Void

    private var materialMode: MaterialAnalysisMode? {
        bundle.passageAnalysisDiagnostics?.materialMode
    }

    private var analysisStatusTitle: String {
        materialMode?.statusTitle ?? "AI 地图分析暂不可用，已展示本地结构骨架"
    }

    private var allowsPassageRetry: Bool {
        materialMode == nil || materialMode == .passageReading
    }

    var body: some View {
        PaperSheetCard(
            padding: usesPadLayout ? 18 : 14,
            cornerRadius: 30,
            accent: AppPalette.paperHighlightMint,
            showsTape: true
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    MarkerTitle(text: "解析分析", tint: AppPalette.paperHighlight)

                    Spacer()

                    if showsOutlineButton {
                        Button(action: onShowOutline) {
                            HStack(spacing: 6) {
                                Image(systemName: "list.bullet.indent")
                                Text("思维导图")
                            }
                            .font(.system(size: 12, weight: .semibold, design: .serif))
                            .foregroundStyle(Color.blue.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.7))
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Text(modeLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.paperMuted)
                }

                if let analysisStatusMessage = analysisStatusMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !analysisStatusMessage.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(analysisStatusTitle)
                            .font(.system(size: 15, weight: .bold, design: .serif))
                            .foregroundStyle(AppPalette.paperInk)

                        Text(analysisStatusMessage)
                            .font(.system(size: 14, weight: .medium, design: .serif))
                            .foregroundStyle(AppPalette.paperMuted)

                        if allowsPassageRetry {
                            Button("稍后重新生成地图") {
                                onRetryPassageAnalysis()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .foregroundStyle(Color.blue.opacity(0.82))
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.68))
                    )
                }

                ReviewWorkbenchPanelShell(contentPadding: usesPadLayout ? 18 : 14) {
                    switch panelKind {
                    case .empty:
                        ReviewWorkbenchEmptyPanel()
                    case .sentence:
                        if let selectedSentence {
                            ReviewWorkbenchSentencePanel(
                                document: document,
                                sentence: selectedSentence,
                                selectedWordTerm: selectedWord?.term,
                                onSentenceChange: onSentenceTap,
                                onWordTap: onWordTap
                            )
                        } else {
                            ReviewWorkbenchEmptyPanel()
                        }
                    case .node:
                        if let selectedNode {
                            ReviewWorkbenchNodePanel(
                                document: document,
                                node: selectedNode,
                                selectedWordTerm: selectedWord?.term,
                                onAnchorTap: onAnchorTap,
                                onSentenceTap: onSentenceTap,
                                onWordTap: onWordTap
                            )
                        } else {
                            ReviewWorkbenchEmptyPanel()
                        }
                    case .word:
                        if let selectedWord {
                            ReviewWorkbenchWordPanel(
                                document: document,
                                entry: selectedWord
                            )
                        } else {
                            ReviewWorkbenchEmptyPanel()
                        }
                    }
                }

            }
        }
    }

    private var modeLabel: String {
        switch panelKind {
        case .empty:
            return "等待选择"
        case .sentence:
            return "句子讲解"
        case .node:
            return "节点详情"
        case .word:
            return "单词讲解"
        }
    }

}

private struct ReviewWorkbenchPhoneAnalysisDrawer: View {
    let document: SourceDocument
    let panelKind: ReviewWorkbenchPanelKind
    let selectedSentence: Sentence?
    let selectedNode: OutlineNode?
    let selectedWord: WordExplanationEntry?
    let onSentenceTap: (Sentence) -> Void
    let onAnchorTap: (OutlineNodeAnchorItem) -> Void
    let onWordTap: (WordExplanationEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(drawerTitle)
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(AppPalette.paperInk)

                Spacer()

                Text(drawerModeLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.paperMuted)
            }

            Group {
                switch panelKind {
                case .empty:
                    ReviewWorkbenchEmptyPanel()
                case .sentence:
                    if let selectedSentence {
                        ReviewWorkbenchSentencePanel(
                            document: document,
                            sentence: selectedSentence,
                            selectedWordTerm: selectedWord?.term,
                            onSentenceChange: onSentenceTap,
                            onWordTap: onWordTap
                        )
                    } else {
                        ReviewWorkbenchEmptyPanel()
                    }
                case .node:
                    if let selectedNode {
                        ReviewWorkbenchNodePanel(
                            document: document,
                            node: selectedNode,
                            selectedWordTerm: selectedWord?.term,
                            onAnchorTap: onAnchorTap,
                            onSentenceTap: onSentenceTap,
                            onWordTap: onWordTap
                        )
                    } else {
                        ReviewWorkbenchEmptyPanel()
                    }
                case .word:
                    if let selectedWord {
                        ReviewWorkbenchWordPanel(
                            document: document,
                            entry: selectedWord
                        )
                    } else {
                        ReviewWorkbenchEmptyPanel()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(PaperCanvasBackground())
    }

    private var drawerModeLabel: String {
        switch panelKind {
        case .empty:
            return "等待选择"
        case .sentence:
            return "句子"
        case .node:
            return "节点"
        case .word:
            return "单词"
        }
    }

    private var drawerTitle: String {
        switch panelKind {
        case .empty:
            return "解析分析"
        case .sentence:
            return "句子讲解"
        case .node:
            return "节点详情"
        case .word:
            return "单词讲解"
        }
    }
}

private struct ReviewWorkbenchPanelShell<Content: View>: View {
    let contentPadding: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(contentPadding)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppPalette.paperCard)
                    .overlay(
                        NotebookGrid(spacing: 24)
                            .opacity(0.08)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.96), lineWidth: 1)
                    )
            )
    }
}

private struct ReviewWorkbenchEmptyPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("点击上方原文开始解析")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.82))

            Text("选中句子会立即同步显示句子讲解；选中结构节点会显示节点详情、来源锚点和关键句。")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.58))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ReviewWorkbenchSentencePanel: View {
    @EnvironmentObject private var viewModel: AppViewModel

    let document: SourceDocument
    let sentence: Sentence
    let selectedWordTerm: String?
    let onSentenceChange: (Sentence) -> Void
    let onWordTap: (WordExplanationEntry) -> Void

    @State private var result: AIExplainSentenceResult?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showsContext = false
    @State private var noteSeed: NoteEditorSeed?
    @State private var actionNote: String?
    @State private var explanationTask: Task<Void, Never>?
    @State private var activeExplanationRequestID: String?
    @State private var activeExplanationSentenceKey: AIRequestIdentity.SemanticKey?

    private var breadcrumb: SentenceBreadcrumb {
        viewModel.sentenceBreadcrumb(for: sentence, in: document)
    }

    private var previousSentence: Sentence? {
        viewModel.previousSentence(for: sentence, in: document)
    }

    private var nextSentence: Sentence? {
        viewModel.nextSentence(for: sentence, in: document)
    }

    private var contextSentences: [Sentence] {
        viewModel.contextSentences(for: sentence, in: document)
    }

    private var bundledAnalysis: ProfessorSentenceAnalysis? {
        viewModel.professorSentenceCard(for: sentence, in: document)?.analysis
    }

    private var effectiveAnalysis: ProfessorSentenceAnalysis? {
        let bundled = bundledAnalysis
        if let visibleResult {
            let remote = visibleResult.localFallbackAnalysis
            if visibleResult.usedFallback || visibleResult.fallbackAvailable {
                return remote
            }
            return remote.mergingFallback(bundled)
        }
        return bundled
    }

    private var selectionState: SourceSelectionState {
        viewModel.sourceSelectionState(for: sentence, in: document)
    }

    private var visibleResult: AIExplainSentenceResult? {
        if let result, isResultVisible(result, for: sentence) {
            return result
        }
        return viewModel.cachedSentenceExplanation(for: sentence, in: document)
    }

    private var shouldAutoLoadRemoteExplanation: Bool {
        guard !isLoading, visibleResult == nil else { return false }
        guard selectionState.allowsCloudSentenceExplain else { return false }
        return true
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if !breadcrumb.trailLabels.isEmpty {
                    Text(breadcrumb.trailLabels.joined(separator: " / "))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.52))
                        .lineSpacing(3)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        BreadcrumbPill(text: breadcrumb.pageLabel)
                        BreadcrumbPill(text: breadcrumb.sentenceLabel)
                        BreadcrumbPill(text: breadcrumb.outlineLabel)
                    }
                }

                sentenceCard
                utilityControls

                if showsContext {
                    contextSection
                }

                explanationSection
                actionSection
            }
        }
        .sheet(item: $noteSeed) { seed in
            NoteEditorSheet(seed: seed)
                .environmentObject(viewModel)
        }
        .onChange(of: sentence.id) { _ in
            actionNote = nil
            explanationTask?.cancel()
            explanationTask = nil
            result = nil
            errorMessage = nil
            isLoading = false
            activeExplanationRequestID = nil
            activeExplanationSentenceKey = nil
            maybeAutoLoadExplanation()
        }
        .onAppear {
            maybeAutoLoadExplanation()
        }
        .onDisappear {
            explanationTask?.cancel()
            explanationTask = nil
            activeExplanationRequestID = nil
            activeExplanationSentenceKey = nil
        }
    }

    private var sentenceCard: some View {
        SentenceFocusCard(
            anchorLabel: sentence.anchorLabel,
            text: sentence.text,
            highlightTokens: effectiveAnalysis?.vocabularyInContext.map(\.term) ?? []
        )
    }

    private var utilityControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                DetailActionButton(title: "上一句", icon: "chevron.left", isDisabled: previousSentence == nil) {
                    guard let previousSentence else { return }
                    onSentenceChange(previousSentence)
                }

                DetailActionButton(title: "下一句", icon: "chevron.right", isDisabled: nextSentence == nil) {
                    guard let nextSentence else { return }
                    onSentenceChange(nextSentence)
                }
            }

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    showsContext.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showsContext ? "text.alignleft" : "text.quote")
                    Text(showsContext ? "收起原文上下文" : "查看原文上下文")
                    Spacer()
                    Image(systemName: showsContext ? "chevron.up" : "chevron.down")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.72))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.74))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("原文上下文")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.76))

            ForEach(contextSentences) { contextSentence in
                Button {
                    onSentenceChange(contextSentence)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(contextSentence.anchorLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(contextSentence.id == sentence.id ? Color.blue.opacity(0.8) : Color.black.opacity(0.46))

                        ExpandableText(
                            text: contextSentence.text,
                            font: .system(size: 14, weight: .medium),
                            foregroundColor: Color.black.opacity(0.72),
                            collapsedLineLimit: 3
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(contextSentence.id == sentence.id ? Color.blue.opacity(0.12) : Color.white.opacity(0.78))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var explanationSection: some View {
        let currentSelection = selectionState
        if !currentSelection.allowsCloudSentenceExplain {
            VStack(alignment: .leading, spacing: 14) {
                SentenceExplainBlock(
                    title: "本地骨架",
                    content: "当前展示的是本地结构骨架，远端 AI 精讲尚未成功获取。",
                    tone: .neutral
                )
                SourceSelectionSkeletonPanel(selectionState: currentSelection)
            }
        } else if let analysis = effectiveAnalysis {
            VStack(alignment: .leading, spacing: 14) {
                if isLoading {
                    ProgressView("正在获取教授式精讲…")
                        .font(.system(size: 15, weight: .medium))
                } else if let visibleResult, visibleResult.shouldShowFallbackBanner {
                    SentenceExplainBlock(
                        title: "提示",
                        content: visibleResult.displayFallbackMessage,
                        tone: .neutral
                    )
                    debugTransportSection(for: visibleResult)
                } else if let errorMessage, result == nil {
                    SentenceExplainBlock(
                        title: "提示",
                        content: "当前展示的是本地教学卡骨架；远端教授式精讲获取失败：\(errorMessage)",
                        tone: .neutral
                    )
                }

                ProfessorAnalysisPanel(
                    analysis: analysis,
                    keywordMinimumWidth: 140,
                    selectedTerm: selectedWordTerm,
                    relatedEvidenceItems: [],
                    onWordTap: { keyword in
                        onWordTap(
                            viewModel.wordExplanation(
                                for: keyword.term,
                                meaningHint: keyword.hint,
                                sentence: sentence,
                                in: document
                            )
                        )
                    }
                )

                if !isLoading, result == nil {
                    remoteExplanationButton(title: "重新获取 AI 精讲")
                }
            }
        } else if isLoading {
            ProgressView("正在获取教授式精讲…")
                .font(.system(size: 15, weight: .medium))
        } else if let errorMessage {
            VStack(alignment: .leading, spacing: 10) {
                Text("讲解获取失败")
                    .font(.system(size: 16, weight: .bold))

                Text(errorMessage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.62))

                Button("重新获取 AI 精讲") {
                    scheduleExplanationLoad(force: true)
                }
                .font(.system(size: 14, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.blue.opacity(0.82))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("当前未自动请求云端讲解")
                    .font(.system(size: 16, weight: .bold))

                Text("现在默认只展示本地教学卡，避免自动消耗额度。需要时可手动获取云端精讲。")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.62))

                remoteExplanationButton(title: "获取 AI 精讲")
            }
        }
    }

    private func remoteExplanationButton(title: String) -> some View {
        Button(title) {
            scheduleExplanationLoad(force: true)
        }
        .font(.system(size: 14, weight: .semibold))
        .buttonStyle(.plain)
        .foregroundStyle(Color.blue.opacity(0.82))
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let actionNote {
                SheetActionStatus(text: actionNote)
            }

            HStack(spacing: 10) {
                DetailActionButton(title: "加入笔记", icon: "square.and.pencil") {
                    noteSeed = viewModel.sentenceNoteSeed(
                        for: sentence,
                        explanation: result,
                        in: document
                    )
                }

                DetailActionButton(title: "生成卡片", icon: "rectangle.stack.badge.plus") {
                    _ = viewModel.addSentenceCard(for: sentence, explanation: result, in: document)
                    actionNote = "已把当前句子加入卡片草稿。"
                }
            }
        }
    }

    private func scheduleExplanationLoad(force: Bool) {
        let currentSentence = sentence
        let sentenceKey = AIRequestIdentity.make(document: document, sentence: currentSentence)?.semanticKey
        if !force {
            if let result, isResultVisible(result, for: currentSentence) {
                return
            }
            if isLoading, activeExplanationSentenceKey == sentenceKey {
                TextPipelineDiagnostics.log(
                    "AI",
                    "[AI][SentenceExplain] skip duplicate active request sentence_id=\(currentSentence.id)",
                    severity: .info
                )
                return
            }
        }

        explanationTask?.cancel()
        explanationTask = Task {
            await loadExplanation(for: currentSentence, forceRefresh: force)
        }
    }

    private func loadExplanation(
        for currentSentence: Sentence,
        forceRefresh: Bool
    ) async {
        let context = viewModel.explainSentenceContext(for: currentSentence, in: document)
        await MainActor.run {
            guard sentence.id == currentSentence.id else { return }
            isLoading = true
            errorMessage = nil
            result = nil
            activeExplanationRequestID = nil
            activeExplanationSentenceKey = nil
        }

        guard let requestIdentity = viewModel.explainSentenceRequestIdentity(for: currentSentence, in: document) else {
            _ = try? ExplainSentenceRequestBuilder.prepare(context: context, requestIdentity: nil)
            let fallback = LocalSentenceFallbackBuilder.build(
                context: context,
                requestIdentity: nil,
                structuredError: AIStructuredError.invalidRequest(message: "缺少 sentence identity 字段。")
            )
            await MainActor.run {
                guard sentence.id == currentSentence.id else { return }
                result = fallback
                errorMessage = fallback.displayFallbackMessage
                isLoading = false
                activeExplanationRequestID = nil
                activeExplanationSentenceKey = nil
            }
            return
        }

        await MainActor.run {
            guard sentence.id == currentSentence.id else { return }
            activeExplanationRequestID = requestIdentity.clientRequestID
            activeExplanationSentenceKey = requestIdentity.semanticKey
        }

        do {
            let fetched = try await AIExplainSentenceService.fetchExplanationWithCache(
                for: context,
                requestIdentity: requestIdentity,
                forceRefresh: forceRefresh
            )
            try Task.checkCancellation()

            guard isResultVisible(fetched, for: currentSentence) else {
                TextPipelineDiagnostics.log(
                    "AI",
                    "[AI][SentenceExplain] discard stale result request_id=\(requestIdentity.clientRequestID) sentence_id=\(requestIdentity.sentenceID)",
                    severity: .warning
                )
                await MainActor.run {
                    guard sentence.id == currentSentence.id else { return }
                    guard activeExplanationRequestID == requestIdentity.clientRequestID else { return }
                    isLoading = false
                    activeExplanationSentenceKey = nil
                }
                return
            }

            await MainActor.run {
                guard sentence.id == currentSentence.id else { return }
                guard activeExplanationRequestID == requestIdentity.clientRequestID else {
                    TextPipelineDiagnostics.log(
                        "AI",
                        "[AI][SentenceExplain] discard stale request request_id=\(requestIdentity.clientRequestID) discard_reason=requestSuperseded",
                        severity: .warning
                    )
                    return
                }
                viewModel.rememberSentenceExplanation(fetched, for: currentSentence, in: document)
                result = fetched
                errorMessage = fetched.shouldShowFallbackBanner ? fetched.displayFallbackMessage : nil
                isLoading = false
                activeExplanationRequestID = nil
                activeExplanationSentenceKey = nil
                TextPipelineDiagnostics.log(
                    "AI",
                    [
                        "[AI][SentenceExplain] review_ui_state_applied",
                        "sentence_id=\(requestIdentity.sentenceID)",
                        "request_id=\(fetched.requestID ?? "nil")",
                        "used_fallback=\(fetched.usedFallback)",
                        "used_cache=\(fetched.usedCache)",
                        "is_ai_generated=\(fetched.localFallbackAnalysis.isAIGenerated)"
                    ].joined(separator: " "),
                    severity: .info
                )
            }
        } catch is CancellationError {
            await MainActor.run {
                guard sentence.id == currentSentence.id else { return }
                isLoading = false
                if activeExplanationRequestID == requestIdentity.clientRequestID {
                    activeExplanationRequestID = nil
                    activeExplanationSentenceKey = nil
                }
            }
        } catch {
            let fallback = LocalSentenceFallbackBuilder.build(
                context: context,
                requestIdentity: requestIdentity,
                structuredError: AIStructuredError.invalidModelResponse(message: error.localizedDescription)
            )
            await MainActor.run {
                guard sentence.id == currentSentence.id else { return }
                guard activeExplanationRequestID == requestIdentity.clientRequestID else {
                    TextPipelineDiagnostics.log(
                        "AI",
                        "[AI][SentenceExplain] discard stale fallback request_id=\(requestIdentity.clientRequestID) discard_reason=requestSuperseded",
                        severity: .warning
                    )
                    return
                }
                result = fallback
                errorMessage = fallback.displayFallbackMessage
                isLoading = false
                activeExplanationRequestID = nil
                activeExplanationSentenceKey = nil
            }
        }
    }

    private func maybeAutoLoadExplanation() {
        guard shouldAutoLoadRemoteExplanation else { return }
        scheduleExplanationLoad(force: false)
    }

    private func isResultVisible(_ result: AIExplainSentenceResult, for sentence: Sentence) -> Bool {
        guard let expectedIdentity = AIRequestIdentity.make(document: document, sentence: sentence) else {
            return false
        }
        return AIResponseIdentityGuard.validate(
            expected: expectedIdentity,
            actual: result.analysisIdentity
        ).isAllowed
    }

    @ViewBuilder
    private func debugTransportSection(for result: AIExplainSentenceResult) -> some View {
        #if DEBUG
        let debugLines = [
            result.requestID.map { "request_id：\($0)" },
            result.errorCode.map { "error_code：\($0)" },
            "used_fallback：\(result.usedFallback ? "true" : "false")",
            "used_cache：\(result.usedCache ? "true" : "false")",
            "retry_count：\(result.retryCount)"
        ].compactMap { $0 }

        if !debugLines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("DEBUG")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.55))

                ForEach(debugLines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
            }
        }
        #endif
    }
}

private struct ReviewWorkbenchNodePanel: View {
    @EnvironmentObject private var viewModel: AppViewModel

    let document: SourceDocument
    let node: OutlineNode
    let selectedWordTerm: String?
    let onAnchorTap: (OutlineNodeAnchorItem) -> Void
    let onSentenceTap: (Sentence) -> Void
    let onWordTap: (WordExplanationEntry) -> Void

    @State private var actionNote: String?

    private var snapshot: OutlineNodeDetailSnapshot {
        viewModel.outlineNodeDetail(for: node, in: document)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    BreadcrumbPill(text: snapshot.levelLabel)
                    BreadcrumbPill(text: node.anchor.label)
                }

                SentenceExplainBlock(
                    title: snapshot.title,
                    content: snapshot.summary,
                    tone: .node,
                    highlightTokens: snapshot.keywords.map(\.term)
                )
                anchorSection
                keySentenceSection
                keywordSection
                actionSection
            }
        }
    }

    private var anchorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("来源锚点")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.78))

            ForEach(snapshot.anchorItems) { anchor in
                Button {
                    onAnchorTap(anchor)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(anchor.label)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.blue.opacity(0.78))

                        if !anchor.previewText.isEmpty {
                            ExpandableText(
                                text: anchor.previewText,
                                font: .system(size: 14, weight: .medium),
                                foregroundColor: Color.black.opacity(0.62),
                                collapsedLineLimit: 4
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.94), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var keySentenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("关键句")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.78))

            if snapshot.keySentences.isEmpty {
                SentenceExplainBlock(
                    title: "暂无关键句",
                    content: "当前节点暂未绑定到具体句子，可先点击来源锚点定位到原文。",
                    tone: .node
                )
            } else {
                ForEach(snapshot.keySentences) { sentence in
                    Button {
                        onSentenceTap(sentence)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(sentence.anchorLabel)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.blue.opacity(0.72))

                            ExpandableText(
                                text: sentence.text,
                                font: .system(size: 15, weight: .medium),
                                foregroundColor: Color.black.opacity(0.76),
                                collapsedLineLimit: 4
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.94), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var keywordSection: some View {
        InteractiveKeywordSection(
            title: "关键词",
            minimumItemWidth: 140,
            selectedTerm: selectedWordTerm,
            keywords: snapshot.keywords
        ) { keyword in
            onWordTap(
                viewModel.wordExplanation(
                    for: keyword.term,
                    meaningHint: keyword.hint,
                    sentence: snapshot.keySentences.first,
                    in: document
                )
            )
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let actionNote {
                SheetActionStatus(text: actionNote)
            }

            HStack(spacing: 10) {
                DetailActionButton(title: "查看原文", icon: "text.alignleft") {
                    guard let firstAnchor = snapshot.anchorItems.first else { return }
                    onAnchorTap(firstAnchor)
                }

                DetailActionButton(
                    title: "逐句解析",
                    icon: "text.magnifyingglass",
                    isDisabled: snapshot.keySentences.isEmpty
                ) {
                    guard let sentence = snapshot.keySentences.first else { return }
                    onSentenceTap(sentence)
                }

                DetailActionButton(title: "生成卡片", icon: "rectangle.stack.badge.plus") {
                    _ = viewModel.addNodeCard(for: node, in: document)
                    actionNote = "已把当前节点加入卡片草稿。"
                }
            }
        }
    }
}

private struct ReviewWorkbenchWordPanel: View {
    @EnvironmentObject private var viewModel: AppViewModel

    let document: SourceDocument
    let entry: WordExplanationEntry

    @State private var noteSeed: NoteEditorSeed?
    @State private var actionNote: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                SentenceExplainBlock(
                    title: "本句释义",
                    content: entry.sentenceMeaning,
                    tone: .vocabulary,
                    highlightTokens: [entry.term]
                )
                SentenceExplainListBlock(title: "常见义项", items: entry.commonMeanings, tone: .vocabulary)
                SentenceExplainListBlock(title: "常见搭配", items: entry.collocations, tone: .vocabulary)
                SentenceExplainListBlock(title: "例句", items: entry.examples, tone: .vocabulary)
                actionSection
            }
        }
        .sheet(item: $noteSeed) { seed in
            NoteEditorSheet(seed: seed)
                .environmentObject(viewModel)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entry.term)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.84))

            HStack(spacing: 8) {
                BreadcrumbPill(text: entry.phonetic)
                BreadcrumbPill(text: entry.partOfSpeech)
            }
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let actionNote {
                SheetActionStatus(text: actionNote)
            }

            HStack(spacing: 10) {
                DetailActionButton(title: "加入词汇卡", icon: "character.book.closed.fill") {
                    _ = viewModel.addVocabularyCard(for: entry, in: document)
                    actionNote = "已加入词汇卡草稿。"
                }

                DetailActionButton(title: "加入笔记", icon: "square.and.pencil") {
                    if let seed = viewModel.wordNoteSeed(for: entry, in: document) {
                        noteSeed = seed
                    } else {
                        actionNote = "当前词条没有绑定到具体原句，暂时无法生成来源笔记。"
                    }
                }
            }
        }
    }
}

private struct CompactSentenceStepperButton: View {
    let icon: String
    let title: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isDisabled ? Color.black.opacity(0.24) : Color.black.opacity(0.58))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(isDisabled ? Color.white.opacity(0.3) : Color.white.opacity(0.76))
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
