import SwiftUI

private enum SourceDetailTab: String, CaseIterable {
    case original = "原文"
    case outline = "大纲"
}

struct SourceDetailView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let document: SourceDocument
    let onClose: () -> Void

    @State private var isGeneratingDrafts = false
    @State private var generationNote: String?
    @State private var isExpanded = false
    @State private var dragOffset: CGFloat = 0
    @State private var selectedTab: SourceDetailTab = .original
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

                        ProgressView("正在整理资料工作台…")
                            .font(.system(size: 16, weight: .medium, design: .serif))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 18)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                            overlayHeader
                                .padding(.horizontal, usesPadChrome ? 30 : 24)
                                .padding(.top, 14)
                                .padding(.bottom, 18)
                                .contentShape(Rectangle())
                                .gesture(sheetDragGesture(collapsedHeight: collapsedHeight, expandedHeight: expandedHeight))

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
            }
        }
        .ignoresSafeArea()
        .task(id: liveDocument.id) {
            guard structuredSource == nil else { return }
            await viewModel.loadStructuredSource(for: liveDocument)
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
    }

    private var overlayHeader: some View {
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
    }

    @ViewBuilder
    private var overlayBody: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Resource Details")
                    .font(.system(size: 31, weight: .bold, design: .serif))
                    .italic()
                    .foregroundStyle(AppPalette.paperInk)

                Rectangle()
                    .fill(AppPalette.paperLine)
                    .frame(width: 190, height: 2)

                Text("结构化预览与资料整理")
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(AppPalette.paperMuted)
            }

            sourceMetaSection

            overlayStatsSection

            if let structuredSource {
                structureSection(structuredSource)
            } else {
                structureLoadingSection
            }

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
                MarkerTitle(text: "结构化理解", tint: AppPalette.paperHighlightMint)

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
        } else {
            SourceOutlineTab(
                nodes: structuredSource.outline,
                highlightedNodeID: highlightedOutlineNodeID,
                jumpTargetNodeID: jumpTargetOutlineNodeID,
                ancestorNodeIDs: structuredOutlineAncestorNodeIDs,
                onNodeTap: { node in
                    handleOutlineNodeTap(node)
                },
                onJumpHandled: handleOutlineJumpHandled
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
                            MarkerTitle(text: "大纲", tint: Color.pink.opacity(0.28))

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
                MarkerTitle(text: "结构化理解", tint: AppPalette.paperHighlightMint)

                if viewModel.isLoadingStructuredSource(for: liveDocument) {
                    ProgressView()
                    Text("正在生成原文切分和资料大纲…")
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(AppPalette.paperInk.opacity(0.82))
                } else if let error = viewModel.structuredSourceError(for: liveDocument) {
                    Text("结构化理解暂不可用")
                        .font(.system(size: 17, weight: .bold, design: .serif))
                        .foregroundStyle(AppPalette.paperInk)

                    Text(error)
                        .font(.system(size: 15, weight: .medium, design: .serif))
                        .foregroundStyle(AppPalette.paperMuted)

                    Button("重试解析") {
                        Task {
                            await viewModel.loadStructuredSource(for: liveDocument, force: true)
                        }
                    }
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.blue.opacity(0.8))
                } else {
                    Text("资料导入后会在这里展示原文与大纲。")
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
