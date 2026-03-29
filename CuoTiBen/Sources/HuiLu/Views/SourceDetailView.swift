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

                    GlassPanel(tone: .light, cornerRadius: 34, padding: 0) {
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
                    .frame(width: panelWidth, height: liveHeight)

                    Spacer(minLength: 0)
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
                .fill(Color.black.opacity(0.14))
                .frame(width: 66, height: 6)

            Spacer()

            Text(isExpanded ? "下拉收起" : "上拉展开")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.38))

            Spacer()

            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                    Text("关闭")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.48))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var overlayBody: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("资料详情")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.82))

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
        HStack(spacing: 10) {
            LibraryMetaPill(title: liveDocument.processingStatus.displayName)

            if liveDocument.chunkCount > 0 {
                LibraryMetaPill(title: "\(liveDocument.chunkCount) 个知识块")
            }

            if let structuredSource {
                LibraryMetaPill(title: "\(structuredSource.source.sentenceCount) 句")
            }
        }
    }

    private func structureSection(_ structuredSource: StructuredSourceBundle) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("结构化理解")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.74))

            SegmentedGlassControl(
                items: SourceDetailTab.allCases,
                selected: $selectedTab,
                label: \.rawValue
            )

            structureTabContent(structuredSource)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("主题标签")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.74))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                ForEach(conceptTags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.55), Color.purple.opacity(0.55)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
            }
        }
    }

    private var sourceMetaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("资料来源")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.74))

            HStack(alignment: .top, spacing: 12) {
                FrostedOrb(icon: liveDocument.documentType.icon, size: 42, tone: .light)

                VStack(alignment: .leading, spacing: 4) {
                    Text(liveDocument.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.82))

                    Text("\(liveDocument.pageCount) 页 • 导入于 \(formattedDate)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.48))
                }
            }
        }
    }

    @ViewBuilder
    private var structureLoadingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("结构化理解")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.74))

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.82), lineWidth: 1)
                )
                .overlay {
                    VStack(alignment: .leading, spacing: 12) {
                        if viewModel.isLoadingStructuredSource(for: liveDocument) {
                            ProgressView()
                            Text("正在生成原文切分和资料大纲…")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.72))
                        } else if let error = viewModel.structuredSourceError(for: liveDocument) {
                            Text("结构化理解暂不可用")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.78))

                            Text(error)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.58))

                            Button("重试解析") {
                                Task {
                                    await viewModel.loadStructuredSource(for: liveDocument, force: true)
                                }
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.blue.opacity(0.8))
                        } else {
                            Text("资料导入后会在这里展示原文与大纲。")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.58))
                        }

                        if !previewChunks.isEmpty {
                            Text("当前已有 \(previewChunks.count) 个知识块预览，可继续生成卡片。")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.46))
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
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
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.blue.opacity(0.72))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                DetailActionButton(title: "分享", icon: "square.and.arrow.up") {}
                DetailActionButton(
                    title: detailPrimaryTitle,
                    icon: detailPrimaryIcon,
                    isDisabled: !canGenerateDrafts && generatedDraftCount == 0
                ) {
                    handlePrimaryAction()
                }
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
        if usesPadChrome {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.96), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 20, y: 8)
        } else {
            Rectangle()
                .fill(Color.white.opacity(0.78))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.9))
                        .frame(height: 1)
                }
        }
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
