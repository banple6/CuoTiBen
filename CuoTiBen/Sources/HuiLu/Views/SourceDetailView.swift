import SwiftUI

private enum SourceDetailTab: String, CaseIterable {
    case original = "原文"
    case outline = "思维导图"
    case professor = "教授式解析"
}

struct SourceDetailView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let document: SourceDocument
    let onClose: () -> Void

    @State private var isGeneratingDrafts = false
    @State private var generationNote: String?
    @State private var isExpanded = false
    @State private var dragOffset: CGFloat = 0
    @State private var selectedTab: SourceDetailTab = .outline
    @State private var lastNonOutlineTab: SourceDetailTab = .original
    @State private var selectedSentence: Sentence?
    @State private var selectedOutlineNode: OutlineNode?
    @State private var jumpTargetSentenceID: String?
    @State private var jumpTargetSegmentID: String?
    @State private var highlightedSentenceID: String?
    @State private var highlightedSegmentIDs: Set<String> = []
    @State private var highlightedOutlineNodeID: String?
    @State private var jumpTargetOutlineNodeID: String?

    private var liveDocument: SourceDocument {
        viewModel.sourceDocuments.first(where: { $0.id == document.id }) ?? document
    }

    private var structuredSource: StructuredSourceBundle? {
        viewModel.structuredSource(for: liveDocument)
    }

    private var previewChunks: [KnowledgeChunk] {
        viewModel.chunks(for: liveDocument)
    }

    private var conceptTags: [String] {
        let fallback = [liveDocument.documentType.displayName, "重点整理", "深度复习"]
        return Array((liveDocument.topicTags + fallback).prefix(6))
    }

    private var generatedDraftCount: Int {
        max(liveDocument.generatedCardCount, viewModel.generatedCards(for: liveDocument).count)
    }

    private var canGenerateDrafts: Bool {
        liveDocument.processingStatus == .ready && liveDocument.chunkCount > 0 && !isGeneratingDrafts
    }

    private var detailPrimaryTitle: String {
        if isGeneratingDrafts { return "生成中..." }
        if generatedDraftCount > 0 { return "开始复习" }
        return "生成卡片"
    }

    private var detailPrimaryIcon: String {
        if isGeneratingDrafts { return "hourglass" }
        if generatedDraftCount > 0 { return "play.fill" }
        return "rectangle.stack.fill"
    }

    private var structuredOutlineAncestorNodeIDs: [String] {
        guard let structuredSource else { return [] }
        return structuredSource.ancestorNodeIDs(
            for: jumpTargetOutlineNodeID ?? highlightedOutlineNodeID
        )
    }

    private var currentSentenceForTeachingStatus: Sentence? {
        guard let structuredSource else { return nil }
        if let selectedSentence {
            let sentence = structuredSource.sentence(id: selectedSentence.id) ?? selectedSentence
            return isPassageTeachingSentence(sentence, in: structuredSource) ? sentence : nil
        }
        if let highlightedSentenceID,
           let sentence = structuredSource.sentence(id: highlightedSentenceID),
           isPassageTeachingSentence(sentence, in: structuredSource) {
            return sentence
        }
        if let node = structuredSource.outlineNode(id: highlightedOutlineNodeID),
           let sentence = structuredSource.sentence(id: node.primarySentenceID ?? node.anchor.sentenceID),
           isPassageTeachingSentence(sentence, in: structuredSource) {
            return sentence
        }
        if let firstKeySentence = structuredSource.professorSentenceCards.first,
           let sentence = structuredSource.sentence(id: firstKeySentence.sentenceID),
           isPassageTeachingSentence(sentence, in: structuredSource) {
            return sentence
        }
        return structuredSource.sentences.first { isPassageTeachingSentence($0, in: structuredSource) }
    }

    private var currentParagraphCardForTeachingStatus: ParagraphTeachingCard? {
        guard let structuredSource else { return nil }
        if let sentence = currentSentenceForTeachingStatus,
           let card = structuredSource.paragraphCard(forSegmentID: sentence.segmentID) {
            return card
        }
        if let node = structuredSource.outlineNode(id: highlightedOutlineNodeID) {
            return structuredSource.paragraphCard(forSegmentID: node.primarySegmentID ?? node.anchor.segmentID)
        }
        return structuredSource.paragraphTeachingCards.first
    }

    private var currentAnalysisForTeachingStatus: ProfessorSentenceAnalysis? {
        guard let structuredSource else { return nil }
        if let sentence = currentSentenceForTeachingStatus {
            guard let analysis = structuredSource.displayedSentenceCard(id: sentence.id)?.analysis,
                  analysis.isCompatible(with: sentence.text) else {
                return nil
            }
            return analysis
        }
        return nil
    }

    private var currentModeLabel: String {
        if let mode = passageMaterialMode, mode != .passageReading {
            return mode.structureTitle
        }
        switch selectedTab {
        case .original:
            return "原文"
        case .outline:
            return "思维导图"
        case .professor:
            return "句子讲解"
        }
    }

    private var teachingStatusSnapshot: ProfessorTeachingStatusSnapshot {
        let materialMode = passageMaterialMode ?? .passageReading
        let isSentenceMode = materialMode == .passageReading && currentSentenceForTeachingStatus != nil
        let structureTitle = materialMode.structureTitle
        let anchor = currentSentenceForTeachingStatus?.anchorLabel
            ?? structuredSource?.outlineNode(id: highlightedOutlineNodeID)?.anchor.label
            ?? "等待定位"
        let sentenceFunction = currentAnalysisForTeachingStatus?.renderedSentenceFunction.nonEmpty
            ?? (isSentenceMode
                ? "先选中一句或一个教学节点，系统会把当前句的定位、主干和教学焦点放到这里。"
                : "当前资料按\(structureTitle)展示，不进入句子主干解析。")
        let paragraphRole = currentParagraphCardForTeachingStatus?.argumentRole.displayName
            ?? (isSentenceMode ? "段落角色待识别" : "本地结构骨架")
        let teachingFocus = currentParagraphCardForTeachingStatus?.displayedTeachingFocuses.first?.nonEmpty
            ?? currentParagraphCardForTeachingStatus?.displayedTheme.nonEmpty
            ?? (isSentenceMode ? "教学焦点待提取" : materialMode.statusTitle)

        return ProfessorTeachingStatusSnapshot(
            documentTitle: liveDocument.title,
            currentSentenceAnchor: anchor,
            currentSentenceFunction: sentenceFunction,
            currentParagraphRole: paragraphRole,
            currentTeachingFocus: teachingFocus,
            currentMode: currentModeLabel
        )
    }

    private var passageMaterialMode: MaterialAnalysisMode? {
        structuredSource?.passageAnalysisDiagnostics?.materialMode
    }

    private var structureStatusTitle: String {
        passageMaterialMode?.statusTitle ?? "思维导图暂不可用"
    }

    private var allowsPassageRetry: Bool {
        passageMaterialMode == nil || passageMaterialMode == .passageReading
    }

    private func isPassageTeachingSentence(
        _ sentence: Sentence,
        in bundle: StructuredSourceBundle
    ) -> Bool {
        let mode = bundle.passageAnalysisDiagnostics?.materialMode ?? .passageReading
        return mode == .passageReading && sentence.provenance.sourceKind == .passageBody
    }

    var body: some View {
        GeometryReader { proxy in
            let usesArchivistWorkspace = proxy.size.width >= 960

            if usesArchivistWorkspace {
                if let structuredSource {
                    ArchivistWorkspaceView(
                        document: liveDocument,
                        bundle: structuredSource,
                        onClose: onClose
                    )
                    .environmentObject(viewModel)
                } else {
                    ZStack {
                        AppBackground(style: .light)
                            .ignoresSafeArea()

                        VStack(spacing: 12) {
                            ProgressView("正在整理资料工作台…")
                                .font(.system(size: 16, weight: .medium, design: .serif))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 18)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                            #if DEBUG
                            ParseSourceDebugBadge(
                                info: viewModel.parseSessionInfo(for: liveDocument),
                                stage: viewModel.structuredSourceStage(for: liveDocument),
                                error: viewModel.structuredSourceError(for: liveDocument)
                            )
                            #endif
                        }
                    }
                }
            } else {
            let safeBottom = max(proxy.safeAreaInsets.bottom, 14)
            let usesPadChrome = proxy.size.width >= 820
            let panelWidth = usesPadChrome ? min(proxy.size.width - 72, 920) : proxy.size.width
            let collapsedHeight = min(max(proxy.size.height * 0.76, 580), proxy.size.height * 0.86)
            let expandedHeight = proxy.size.height * 0.94
            let baseHeight = isExpanded ? expandedHeight : collapsedHeight
            let liveHeight = min(max(baseHeight - dragOffset, collapsedHeight), expandedHeight)

            ZStack {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    HStack(spacing: 0) {
                        Spacer(minLength: 0)

                        ZStack {
                            RoundedRectangle(cornerRadius: 36, style: .continuous)
                                .fill(AppPalette.paperCard.opacity(0.78))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                                )
                                .offset(x: -10, y: 14)
                                .padding(.horizontal, 16)

                            RoundedRectangle(cornerRadius: 36, style: .continuous)
                                .fill(AppPalette.paperBackgroundDeep.opacity(0.9))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                                        .stroke(AppPalette.paperLine.opacity(0.72), lineWidth: 1)
                                )
                                .offset(x: 8, y: 8)
                                .padding(.horizontal, 8)

                            VStack(spacing: 0) {
                                overlayHeaderSection(
                                    usesPadChrome: usesPadChrome,
                                    collapsedHeight: collapsedHeight,
                                    expandedHeight: expandedHeight
                                )

                                ScrollView(showsIndicators: false) {
                                    overlayBody
                                        .padding(.horizontal, usesPadChrome ? 30 : 24)
                                        .padding(.bottom, safeBottom + 118)
                                }

                                overlayActionBar(
                                    safeBottom: safeBottom,
                                    usesPadChrome: usesPadChrome,
                                    panelWidth: panelWidth
                                )
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 36, style: .continuous)
                                .fill(AppPalette.paperCard)
                                .overlay {
                                    NotebookGrid(spacing: 28)
                                        .opacity(0.12)
                                        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                                        .stroke(Color.white.opacity(0.92), lineWidth: 1)
                                )
                                .overlay(alignment: .topTrailing) {
                                    PaperTapeAccent(color: AppPalette.paperTape)
                                        .offset(x: -10, y: 8)
                                }
                                .shadow(color: Color.black.opacity(0.14), radius: 28, y: 16)
                        )
                        .frame(width: panelWidth, height: liveHeight)

                        Spacer(minLength: 0)
                    }
                }

                if let structuredSource, selectedTab == .outline {
                    ZStack {
                        Color.black.opacity(0.18)
                            .ignoresSafeArea()

                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("思维导图工作区")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.black.opacity(0.84))

                                Text(liveDocument.title)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.black.opacity(0.54))
                                    .lineLimit(1)
                            }

                            MindMapWorkspaceView(
                                documentTitle: liveDocument.title,
                                bundle: structuredSource,
                                focusSentenceID: highlightedSentenceID,
                                focusSegmentIDs: highlightedSegmentIDs,
                                displayMode: .fullScreen,
                                onNodeTap: { node in
                                    handleMindMapNodeTap(node, in: structuredSource)
                                },
                                onClose: closeOutlineWorkspace,
                                onRegenerate: {
                                    Task {
                                        await viewModel.ensureProfessorAnalysis(
                                            for: liveDocument,
                                            trigger: .openProfessorView,
                                            force: true
                                        )
                                    }
                                }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.94),
                                            Color(red: 0.958, green: 0.968, blue: 0.988).opacity(0.98)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                                        .stroke(Color.white.opacity(0.74), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.14), radius: 30, x: 0, y: 18)
                        )
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
                    .zIndex(20)
                }
            }
            }
        }
        .ignoresSafeArea()
        .interactiveDismissDisabled(selectedTab == .outline)
        .presentationDragIndicator(selectedTab == .outline ? .hidden : .visible)
        .task(id: liveDocument.id) {
            if structuredSource == nil {
                await viewModel.loadStructuredSource(for: liveDocument)
            }

            guard selectedTab == .professor, viewModel.structuredSource(for: liveDocument) != nil else { return }
            await viewModel.ensureProfessorAnalysis(
                for: liveDocument,
                trigger: .openProfessorView
            )
        }
        .onChange(of: structuredSource?.source.id) { _ in
            guard selectedTab == .professor, structuredSource != nil else { return }
            Task {
                await viewModel.ensureProfessorAnalysis(
                    for: liveDocument,
                    trigger: .openProfessorView
                )
            }
        }
        .sheet(item: $selectedSentence) { sentence in
            SentenceExplainDetailSheet(
                document: liveDocument,
                sentence: sentence
            )
            .environmentObject(viewModel)
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedOutlineNode) { node in
            OutlineNodeDetailSheet(
                document: liveDocument,
                node: node,
                onAnchorTap: { anchor in
                    selectedTab = .original
                    highlightedSentenceID = anchor.sentenceID
                    highlightedSegmentIDs = Set([anchor.segmentID].compactMap { $0 })
                    jumpTargetSentenceID = anchor.sentenceID
                    jumpTargetSegmentID = anchor.segmentID
                },
                onSentenceTap: { sentence in
                    if let bundle = structuredSource {
                        handleSentenceTap(sentence, in: bundle)
                    } else {
                        highlightedSentenceID = sentence.id
                        highlightedSegmentIDs = [sentence.segmentID]
                    }
                    selectedTab = .original
                    jumpTargetSentenceID = sentence.id
                    jumpTargetSegmentID = sentence.segmentID
                    selectedSentence = sentence
                }
            ) { targetNode in
                selectedTab = .original
                syncHighlight(for: targetNode)
                jumpTargetSentenceID = targetNode.primarySentenceID
                jumpTargetSegmentID = targetNode.primarySegmentID
            }
            .environmentObject(viewModel)
            .presentationDetents([.medium, .large])
        }
        .onChange(of: selectedTab) { newValue in
            if newValue != .outline {
                lastNonOutlineTab = newValue
            }

            guard newValue == .professor, structuredSource != nil else { return }
            Task {
                await viewModel.ensureProfessorAnalysis(
                    for: liveDocument,
                    trigger: .openProfessorView
                )
            }
        }
    }

    private var overlayHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Capsule()
                    .fill(AppPalette.paperLine)
                    .frame(width: 66, height: 6)

                Spacer()

                Text(isExpanded ? "下拉收起" : "上拉展开")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(AppPalette.paperMuted)

                Spacer()

                Button(action: onClose) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                        Text("关闭")
                    }
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(AppPalette.paperMuted)
                }
                .buttonStyle(.plain)
            }

            ProfessorTeachingStatusHeader(
                snapshot: teachingStatusSnapshot,
                compact: true
            )
        }
    }

    @ViewBuilder
    private func overlayHeaderSection(
        usesPadChrome: Bool,
        collapsedHeight: CGFloat,
        expandedHeight: CGFloat
    ) -> some View {
        let header = overlayHeader
            .padding(.horizontal, usesPadChrome ? 30 : 24)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .contentShape(Rectangle())

        if selectedTab == .outline {
            header
        } else {
            header.gesture(
                sheetDragGesture(
                    collapsedHeight: collapsedHeight,
                    expandedHeight: expandedHeight
                )
            )
        }
    }

    @ViewBuilder
    private var overlayBody: some View {
        VStack(alignment: .leading, spacing: 22) {
            overlayStatsSection

            if let structuredSource {
                structureSection(structuredSource)
            } else {
                structureLoadingSection
            }

            sourceMetaSection

            topicTagsSection
        }
    }

    private var overlayStatsSection: some View {
        PaperSheetCard(
            padding: 18,
            cornerRadius: 24,
            rotation: 0.4,
            accent: AppPalette.paperTapeBlue.opacity(0.7),
            showsTape: false
        ) {
            HStack(spacing: 10) {
                SketchBadge(title: liveDocument.processingStatus.displayName, tint: AppPalette.paperHighlightMint)

                if liveDocument.chunkCount > 0 {
                    SketchBadge(title: "\(liveDocument.chunkCount) 个知识块", tint: AppPalette.paperTapeBlue.opacity(0.22))
                }

                if let structuredSource {
                    SketchBadge(title: "\(structuredSource.source.sentenceCount) 句", tint: AppPalette.paperTape.opacity(0.28))
                }

                if let info = viewModel.parseSessionInfo(for: liveDocument) {
                    if info.skippedBecauseUnconfigured {
                        SketchBadge(title: "文档解析云接口未配置", tint: AppPalette.paperTapeBlue.opacity(0.22))
                    }
                    if info.fallbackUsed {
                        SketchBadge(title: "本地骨架", tint: AppPalette.paperHighlight.opacity(0.34))
                    }
                }
            }
        }
    }

    private func structureSection(_ structuredSource: StructuredSourceBundle) -> some View {
        PaperSheetCard(
            padding: 20,
            cornerRadius: 28,
            rotation: -0.6,
            accent: AppPalette.paperTape,
            showsTape: true
        ) {
            VStack(alignment: .leading, spacing: 14) {
                MarkerTitle(text: "导图化理解", tint: AppPalette.paperHighlightMint)

                SegmentedGlassControl(
                    items: SourceDetailTab.allCases,
                    selected: $selectedTab,
                    label: \.rawValue
                )

                structureTabContent(structuredSource)
            }
        }
    }

    @ViewBuilder
    private func structureTabContent(_ structuredSource: StructuredSourceBundle) -> some View {
        if selectedTab == .original {
            SourceOriginalTab(
                bundle: structuredSource,
                highlightedSentenceID: highlightedSentenceID,
                highlightedSegmentIDs: highlightedSegmentIDs,
                jumpTargetSentenceID: jumpTargetSentenceID,
                jumpTargetSegmentID: jumpTargetSegmentID,
                onSentenceTap: { sentence in
                    handleSentenceTap(sentence, in: structuredSource)
                },
                onJumpHandled: handleOriginalJumpHandled
            )
        } else if selectedTab == .outline {
            SentenceExplainBlock(
                title: "思维导图工作区",
                content: "当前主导航已经切成思维导图。请在上层面板里缩放、平移、聚焦当前节点，按段落分支查看教学重点、支撑句和题目证据。",
                tone: .structure
            )
        } else {
            ProfessorAnalysisTab(
                bundle: structuredSource,
                onSentenceTap: { sentence in
                    handleSentenceTap(sentence, in: structuredSource)
                }
            )
        }
    }

    private var topicTagsSection: some View {
        PaperSheetCard(
            padding: 20,
            cornerRadius: 26,
            rotation: 0.8,
            accent: AppPalette.paperTapeBlue.opacity(0.7),
            showsTape: false
        ) {
            VStack(alignment: .leading, spacing: 12) {
                MarkerTitle(text: "主题标签", tint: AppPalette.paperHighlight)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                    ForEach(conceptTags, id: \.self) { tag in
                        SketchBadge(
                            title: tag,
                            tint: tag.count.isMultiple(of: 2)
                                ? AppPalette.paperTapeBlue.opacity(0.26)
                                : AppPalette.paperHighlightMint.opacity(0.52)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var sourceMetaSection: some View {
        PaperSheetCard(
            padding: 22,
            cornerRadius: 30,
            rotation: -0.8,
            accent: AppPalette.paperTapeBlue,
            showsTape: true
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    FrostedOrb(icon: liveDocument.documentType.icon, size: 42, tone: .light)

                    VStack(alignment: .leading, spacing: 5) {
                        MarkerTitle(text: "原始资料", tint: AppPalette.paperTapeBlue.opacity(0.3))

                        Text(liveDocument.title)
                            .font(.system(size: 20, weight: .semibold, design: .serif))
                            .foregroundStyle(AppPalette.paperInk)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("\(liveDocument.pageCount) 页 · 导入于 \(formattedDate)")
                            .font(.system(size: 15, weight: .medium, design: .serif))
                            .foregroundStyle(AppPalette.paperMuted)
                    }
                }

                if let structuredSource {
                    Divider()
                        .overlay(AppPalette.paperLine)

                    HStack(alignment: .top, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            MarkerTitle(text: "原文", tint: AppPalette.paperHighlightMint)

                            Text(structuredSource.source.cleanedText.prefix(86))
                                .font(.system(size: 17, weight: .medium, design: .serif))
                                .foregroundStyle(AppPalette.paperInk.opacity(0.88))
                                .lineSpacing(4)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            MarkerTitle(text: "导图分支", tint: Color.pink.opacity(0.28))

                            ForEach(Array(structuredSource.outline.prefix(3).enumerated()), id: \.offset) { _, node in
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(AppPalette.paperMuted)
                                    Text(node.title)
                                        .font(.system(size: 16, weight: .semibold, design: .serif))
                                        .foregroundStyle(AppPalette.paperInk)
                                }
                            }
                        }
                        .frame(maxWidth: 240, alignment: .leading)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var structureLoadingSection: some View {
        PaperSheetCard(
            padding: 20,
            cornerRadius: 28,
            rotation: -0.5,
            accent: AppPalette.paperTapeBlue.opacity(0.72),
            showsTape: false
        ) {
            VStack(alignment: .leading, spacing: 12) {
                MarkerTitle(text: "导图化理解", tint: AppPalette.paperHighlightMint)

                if viewModel.isLoadingStructuredSource(for: liveDocument) {
                    ProgressView()
                    Text("正在生成原文切分和资料大纲…")
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(AppPalette.paperInk.opacity(0.82))
                } else if let error = viewModel.structuredSourceError(for: liveDocument) {
                    Text(structureStatusTitle)
                        .font(.system(size: 17, weight: .bold, design: .serif))
                        .foregroundStyle(AppPalette.paperInk)

                    Text(error)
                        .font(.system(size: 15, weight: .medium, design: .serif))
                        .foregroundStyle(AppPalette.paperMuted)

                    if allowsPassageRetry {
                        Button("重试解析") {
                            Task {
                                await viewModel.loadStructuredSource(for: liveDocument, force: true)
                            }
                        }
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.blue.opacity(0.8))
                    }
                } else {
                    Text("资料导入后会在这里展示原文、思维导图和教授式讲解。")
                        .font(.system(size: 15, weight: .medium, design: .serif))
                        .foregroundStyle(AppPalette.paperMuted)
                }

                if !previewChunks.isEmpty {
                    Text("当前已有 \(previewChunks.count) 个知识块预览，可继续生成卡片。")
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundStyle(AppPalette.paperMuted.opacity(0.86))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        }
    }

    private func overlayActionBar(
        safeBottom: CGFloat,
        usesPadChrome: Bool,
        panelWidth: CGFloat
    ) -> some View {
        VStack(spacing: 12) {
            if let generationNote {
                Text(generationNote)
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(AppPalette.paperMuted)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button(action: {}) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("分享")
                    }
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(AppPalette.paperMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.78))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(AppPalette.paperLine, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)

                Button(action: handlePrimaryAction) {
                    HStack(spacing: 8) {
                        Image(systemName: detailPrimaryIcon)
                        Text(detailPrimaryTitle)
                    }
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(RibbonButtonStyle())
                .disabled(!canGenerateDrafts && generatedDraftCount == 0)
                .opacity((!canGenerateDrafts && generatedDraftCount == 0) ? 0.46 : 1)
            }
        }
        .frame(maxWidth: usesPadChrome ? min(panelWidth - 56, 760) : .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, usesPadChrome ? 16 : safeBottom)
        .background(actionBarBackground(usesPadChrome: usesPadChrome))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, usesPadChrome ? 24 : 0)
        .padding(.bottom, usesPadChrome ? 10 : 0)
    }

    @ViewBuilder
    private func actionBarBackground(usesPadChrome: Bool) -> some View {
        RoundedRectangle(cornerRadius: usesPadChrome ? 26 : 22, style: .continuous)
            .fill(AppPalette.paperBackgroundDeep.opacity(0.96))
            .overlay(
                RoundedRectangle(cornerRadius: usesPadChrome ? 26 : 22, style: .continuous)
                    .stroke(Color.white.opacity(0.96), lineWidth: 1)
            )
            .overlay {
                NotebookGrid(spacing: 22)
                    .opacity(0.08)
                    .clipShape(RoundedRectangle(cornerRadius: usesPadChrome ? 26 : 22, style: .continuous))
            }
            .shadow(color: Color.black.opacity(0.08), radius: 20, y: 8)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: liveDocument.importDate)
    }

    private func handlePrimaryAction() {
        if generatedDraftCount > 0 {
            NotificationCenter.default.post(name: .switchToReviewTab, object: nil)
            onClose()
            return
        }

        guard canGenerateDrafts else { return }

        generationNote = nil
        isGeneratingDrafts = true

        Task {
            do {
                let count = try await viewModel.generateDraftCards(for: liveDocument)
                await MainActor.run {
                    generationNote = "已生成 \(count) 张卡片草稿，现在可以开始复习。"
                    isGeneratingDrafts = false
                }
            } catch {
                await MainActor.run {
                    generationNote = error.localizedDescription
                    isGeneratingDrafts = false
                }
            }
        }
    }

    private func handleSentenceTap(_ sentence: Sentence, in bundle: StructuredSourceBundle) {
        syncHighlight(for: sentence, in: bundle)
        selectedSentence = sentence
    }

    private func handleOutlineNodeTap(_ node: OutlineNode) {
        syncHighlight(for: node)
        selectedOutlineNode = node
    }

    private func handleMindMapNodeTap(_ node: MindMapNode, in bundle: StructuredSourceBundle) {
        if node.kind == .anchorSentence,
           let sentence = bundle.sentence(id: node.provenance.sourceSentenceID) {
            syncHighlight(for: sentence, in: bundle)
            selectedSentence = sentence
            return
        }

        if let outlineNode = bundle.bestOutlineNode(forSentenceID: node.provenance.sourceSentenceID)
            ?? bundle.bestOutlineNode(forSegmentID: node.provenance.sourceSegmentID) {
            syncHighlight(for: outlineNode)
            selectedOutlineNode = outlineNode
            return
        }

        if let sentence = bundle.sentence(id: node.provenance.sourceSentenceID)
            ?? bundle.sentences.first(where: { $0.segmentID == node.provenance.sourceSegmentID }) {
            syncHighlight(for: sentence, in: bundle)
            selectedSentence = sentence
        }
    }

    private func closeOutlineWorkspace() {
        selectedTab = lastNonOutlineTab == .outline ? .original : lastNonOutlineTab
    }

    private func handleOriginalJumpHandled() {
        jumpTargetSentenceID = nil
        jumpTargetSegmentID = nil
    }

    private func handleOutlineJumpHandled() {
        jumpTargetOutlineNodeID = nil
    }

    private func syncHighlight(for sentence: Sentence, in bundle: StructuredSourceBundle) {
        highlightedSentenceID = sentence.id
        highlightedSegmentIDs = [sentence.segmentID]

        if let matchedNode = bundle.bestOutlineNode(forSentenceID: sentence.id) {
            highlightedOutlineNodeID = matchedNode.id
            jumpTargetOutlineNodeID = matchedNode.id
        } else if let matchedNode = bundle.bestOutlineNode(forSegmentID: sentence.segmentID) {
            highlightedOutlineNodeID = matchedNode.id
            jumpTargetOutlineNodeID = matchedNode.id
        } else {
            highlightedOutlineNodeID = nil
            jumpTargetOutlineNodeID = nil
        }
    }

    private func syncHighlight(for node: OutlineNode) {
        highlightedOutlineNodeID = node.id
        highlightedSentenceID = node.primarySentenceID
        highlightedSegmentIDs = Set(
            node.sourceSegmentIDs.isEmpty
                ? [node.primarySegmentID].compactMap { $0 }
                : node.sourceSegmentIDs
        )
        jumpTargetOutlineNodeID = node.id
    }

    private func sheetDragGesture(collapsedHeight: CGFloat, expandedHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let predictedHeight = (isExpanded ? expandedHeight : collapsedHeight) - value.predictedEndTranslation.height

                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    if value.translation.height > 160 || value.predictedEndTranslation.height > 220 {
                        if isExpanded {
                            isExpanded = false
                        } else {
                            onClose()
                        }
                    } else if predictedHeight > (collapsedHeight + expandedHeight) * 0.5 || value.translation.height < -70 {
                        isExpanded = true
                    } else {
                        isExpanded = false
                    }

                    dragOffset = 0
                }
            }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ProfessorAnalysisTab: View {
    let bundle: StructuredSourceBundle
    let onSentenceTap: (Sentence) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            zoningSummarySection

            if let overview = bundle.passageOverview {
                overviewSection(overview)
            }

            if !bundle.paragraphTeachingCards.isEmpty {
                paragraphCardsSection
            }

            if !bundle.questionLinks.isEmpty {
                questionLinksSection
            }
        }
    }

    private var zoningSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MarkerTitle(text: "文档分区", tint: AppPalette.paperHighlightMint)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                SketchBadge(title: "正文 \(bundle.zoningSummary.passageParagraphCount) 段", tint: AppPalette.paperHighlightMint)
                SketchBadge(title: "题目 \(bundle.zoningSummary.questionParagraphCount) 段", tint: AppPalette.paperTapeBlue.opacity(0.28))
                SketchBadge(title: "答案 \(bundle.zoningSummary.answerKeyParagraphCount) 段", tint: AppPalette.paperHighlight.opacity(0.52))
                SketchBadge(title: "词汇 \(bundle.zoningSummary.vocabularyParagraphCount) 段", tint: AppPalette.paperTape.opacity(0.34))
                SketchBadge(title: "说明 \(bundle.zoningSummary.metaInstructionParagraphCount) 段", tint: AppPalette.paperLine.opacity(0.82))
            }
        }
    }

    private func overviewSection(_ overview: PassageOverview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MarkerTitle(text: "文章总览", tint: AppPalette.paperTapeBlue.opacity(0.28))

            professorCard {
                SentenceExplainBlock(title: "文章主题", content: overview.displayedArticleTheme, tone: .node)
                SentenceExplainBlock(title: "作者真正关心的问题", content: overview.displayedAuthorCoreQuestion, tone: .structure)
                SentenceExplainBlock(title: "段落推进路径", content: overview.displayedProgressionPath, tone: .structure)
                if !overview.displayedSyntaxHighlights.isEmpty {
                    SentenceExplainListBlock(title: "最重要的句法学习点", items: overview.displayedSyntaxHighlights, tone: .grammar)
                }
                if !overview.displayedLikelyQuestionTypes.isEmpty {
                    SentenceExplainListBlock(title: "最容易出的题", items: overview.displayedLikelyQuestionTypes, tone: .rewrite)
                }
                if !overview.displayedLogicPitfalls.isEmpty {
                    SentenceExplainListBlock(title: "最容易错的逻辑点", items: overview.displayedLogicPitfalls, tone: .misread)
                }
                if !overview.displayedParagraphFunctionMap.isEmpty {
                    SentenceExplainListBlock(title: "各段功能图", items: overview.displayedParagraphFunctionMap, tone: .sentence)
                }
                if !overview.displayedReadingTraps.isEmpty {
                    SentenceExplainListBlock(title: "补充阅读陷阱", items: overview.displayedReadingTraps, tone: .misread)
                }
                if !overview.vocabularyHighlights.isEmpty {
                    SentenceExplainListBlock(title: "补充词汇/搭配亮点", items: overview.vocabularyHighlights, tone: .vocabulary)
                }
            }
        }
    }

    private var paragraphCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MarkerTitle(text: "段落教学卡", tint: AppPalette.paperHighlight)

            ForEach(bundle.paragraphTeachingCards) { card in
                professorCard {
                    HStack(spacing: 8) {
                        SketchBadge(title: "第\(card.paragraphIndex + 1)段", tint: AppPalette.paperTapeBlue.opacity(0.24))
                        SketchBadge(title: card.argumentRole.displayName, tint: AppPalette.paperHighlightMint.opacity(0.5))
                    }

                    SentenceExplainBlock(title: "段落主旨", content: card.displayedTheme, tone: .sentence)
                    SentenceExplainBlock(title: "段落角色", content: card.argumentRole.teachingDescription, tone: .structure)

                    if let coreSentence = bundle.sentence(id: card.coreSentenceID) {
                        Button {
                            onSentenceTap(coreSentence)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("本段核心句")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.blue.opacity(0.82))
                                Text(coreSentence.text)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.72))
                                    .lineSpacing(3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.72))
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    SentenceExplainBlock(title: "与上一段关系", content: card.displayedRelationToPrevious, tone: .neutral)
                    SentenceExplainBlock(title: "对应题型价值", content: card.displayedExamValue, tone: .rewrite)
                    if let blindSpot = card.displayedStudentBlindSpot, !blindSpot.isEmpty {
                        SentenceExplainBlock(title: "学生最容易读偏的点", content: blindSpot, tone: .misread)
                    }

                    if !card.displayedTeachingFocuses.isEmpty {
                        SentenceExplainListBlock(title: "教学重点", items: card.displayedTeachingFocuses, tone: .grammar)
                    }

                    let relatedQuestionHints = relatedQuestionHints(for: card.segmentID)
                    if !relatedQuestionHints.isEmpty {
                        SentenceExplainListBlock(
                            title: "相关题目线索",
                            items: relatedQuestionHints,
                            tone: .rewrite
                        )
                    }

                    if !card.keywords.isEmpty {
                        SentenceExplainListBlock(title: "关键词", items: card.keywords, tone: .vocabulary)
                    }

                    if card.isAIGenerated {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                            Text("AI 教授级分析")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(Color.purple.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color.purple.opacity(0.08))
                        )
                    }
                }
            }
        }
    }

    private func relatedQuestionHints(for segmentID: String) -> [String] {
        bundle.questionLinks
            .filter { $0.supportParagraphIDs.contains(segmentID) }
            .prefix(2)
            .map { link in
                let trap = link.trapType.trimmingCharacters(in: .whitespacesAndNewlines)
                let evidence = link.paraphraseEvidence.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let question = link.questionText.trimmingCharacters(in: .whitespacesAndNewlines)
                let head = trap.isEmpty ? shortHint(question) : trap
                let tail = !evidence.isEmpty ? evidence : shortHint(question)
                return "\(head)：\(tail)"
            }
    }

    private func shortHint(_ text: String) -> String {
        let trimmed = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(48))
    }

    private var questionLinksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MarkerTitle(text: "题目与证据联动", tint: Color.pink.opacity(0.28))

            ForEach(bundle.questionLinks) { link in
                professorCard {
                    SentenceExplainBlock(title: "题目", content: link.questionText, tone: .sentence)
                    SentenceExplainBlock(title: "陷阱类型", content: link.trapType, tone: .rewrite)

                    if !link.paraphraseEvidence.isEmpty {
                        SentenceExplainListBlock(title: "改写证据", items: link.paraphraseEvidence, tone: .grammar)
                    }

                    if !link.supportParagraphIDs.isEmpty {
                        let paragraphLabels = link.supportParagraphIDs.compactMap { bundle.paragraphCard(forSegmentID: $0)?.displayedTheme }
                        SentenceExplainListBlock(title: "支撑段落", items: paragraphLabels, tone: .structure)
                    }

                    if !link.supportingSentenceIDs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("支撑句")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.78))

                            ForEach(link.supportingSentenceIDs, id: \.self) { sentenceID in
                                if let sentence = bundle.sentence(id: sentenceID) {
                                    Button {
                                        onSentenceTap(sentence)
                                    } label: {
                                        Text(sentence.text)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(Color.black.opacity(0.72))
                                            .lineSpacing(3)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .fill(Color.white.opacity(0.72))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if let answerKeySnippet = link.answerKeySnippet, !answerKeySnippet.isEmpty {
                        SentenceExplainBlock(title: "答案区线索", content: answerKeySnippet, tone: .neutral)
                    }
                }
            }
        }
    }

    private func professorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.96), lineWidth: 1)
                )
        )
    }
}
