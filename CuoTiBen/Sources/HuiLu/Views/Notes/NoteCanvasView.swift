import SwiftUI

#if os(iOS)
import UIKit
#endif

enum NoteCanvasLayoutStyle {
    case notebook
    case studio
}

struct NoteCanvasView: View {
    let sourceAnchor: SourceAnchor
    let blocks: [NoteBlock]
    let linkedKnowledgePoints: [KnowledgePoint]
    let candidateKnowledgePoints: [KnowledgePoint]
    let highlightedBlockID: UUID?
    let currentOutlineTitle: String?
    var canvasTitle: String? = nil
    var layoutStyle: NoteCanvasLayoutStyle = .notebook
    var appearance: NoteWorkspaceAppearance = .paper
    var showsCanvasHeader: Bool = true
    var maxPaperWidth: CGFloat = 880
    @Binding var inkToolState: NoteInkToolState
    var doubleTapBehavior: NotePencilDoubleTapBehavior = .switchToEraser
    var showsAddBlockBar: Bool = true

    let onUpdateTextBlock: (UUID, String) -> Void
    let onUpdateInkBlock: (NoteBlock) -> Void
    let onLinkKnowledgePointToBlock: (String, UUID) -> Void
    let onAddTextBlock: () -> Void
    let onAddInkBlock: () -> Void
    let onAddQuoteBlock: () -> Void
    let onSelectKnowledgePoint: (KnowledgePoint) -> Void
    let onOpenSourceAnchor: (SourceAnchor) -> Void
    let sourceAnchorForBlock: (NoteBlock) -> SourceAnchor
    let onOpenKnowledgePointSource: (KnowledgePoint) -> Void
    let onHighlightHandled: () -> Void

    @State private var showsAllAnchors = false
    @State private var studioPageCount = 1

    var body: some View {
        switch layoutStyle {
        case .notebook:
            notebookBody
        case .studio:
            studioBody
        }
    }

    private var notebookBody: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                HStack {
                    Spacer(minLength: 24)

                    VStack(alignment: .leading, spacing: 36) {
                        if showsCanvasHeader {
                            notebookHeader
                        }

                        if blocks.isEmpty {
                            emptyState
                        } else {
                            ForEach(blocks) { block in
                                blockCard(block)
                                    .id(block.id)
                            }
                        }

                        if showsAddBlockBar {
                            addBlockBar
                        }
                    }
                    .padding(.leading, 104)
                    .padding(.trailing, 74)
                    .padding(.vertical, 72)
                    .frame(maxWidth: maxPaperWidth, alignment: .leading)
                    .background(NotebookPaperBackground())
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.06),
                                        Color.black.opacity(0.018),
                                        .clear
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 38)
                            .padding(.vertical, 22)
                            .padding(.leading, 18)
                    }
                    .overlay(alignment: .topLeading) {
                        PaperTapeAccent(color: AppPalette.paperTapeBlue, width: 60, height: 16, angle: -5)
                            .padding(.top, 18)
                            .padding(.leading, 92)
                    }
                    .overlay(alignment: .topTrailing) {
                        PaperTapeAccent(color: AppPalette.paperTape, width: 54, height: 16, angle: 6)
                            .padding(.top, 18)
                            .padding(.trailing, 90)
                    }
                    .shadow(color: Color.black.opacity(0.05), radius: 32, y: 16)
                    .padding(.vertical, 8)

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 36)
            }
            .onChange(of: highlightedBlockID) { blockID in
                scrollToHighlighted(blockID, using: proxy)
            }
        }
    }

    private var studioBody: some View {
        GeometryReader { proxy in
            let pageWidth = min(max(proxy.size.width - 54, 860), 1380)
            let pageHeight = max(proxy.size.height - 28, 620)

            ZStack(alignment: .bottomLeading) {
                WorkspaceNotebookBackdrop(appearance: appearance)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(appearance.pageFill)
                        .overlay {
                            NotebookGuideLines(
                                topInset: 118,
                                lineSpacing: 36,
                                lineColor: appearance.pageLineColor
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                        }
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(appearance.marginLineColor)
                                .frame(width: 2)
                                .padding(.vertical, 24)
                                .padding(.leading, 38)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .stroke(appearance.pageBorderColor, lineWidth: 1)
                        )

                    if let inkBlock = studioInkBlock {
                        studioInkSurface(for: inkBlock)
                    } else {
                        studioCanvasPlaceholder
                    }

                    studioSourceStrip
                        .padding(.top, 14)
                        .padding(.leading, 16)

                    if hasStudioAccessories {
                        studioAccessoryColumn
                            .padding(.top, 82)
                            .padding(.trailing, 18)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .frame(width: pageWidth, height: pageHeight)
                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                .shadow(color: appearance.pageShadowColor, radius: 28, y: 18)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                pageCounter
                    .padding(.leading, 20)
                    .padding(.bottom, 18)

                undoRedoDock
                    .padding(.leading, 20)
                    .padding(.top, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .onChange(of: highlightedBlockID) { blockID in
                guard blockID != nil else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    onHighlightHandled()
                }
            }
            .onAppear(perform: syncStudioPageCount)
            .onChange(of: studioInkBlock?.id) { _ in
                syncStudioPageCount()
            }
            .onChange(of: studioInkBlock?.inkGeometry?.pageCount) { _ in
                syncStudioPageCount()
            }
        }
    }

    private var notebookHeader: some View {
        editorialNotebookHeader
    }

    private var studioHeader: some View {
        canvasHeader(isStudio: true)
    }

    private var studioInkBlock: NoteBlock? {
        blocks.last(where: { $0.kind == .ink })
    }

    private var studioQuoteBlock: NoteBlock? {
        blocks.last(where: { $0.kind == .quote })
    }

    private var studioTextBlocks: [NoteBlock] {
        blocks.filter { $0.kind == .text }
    }

    private var notebookDisplayTitle: String {
        canvasTitle?.nonEmpty ?? sourceAnchor.sourceTitle
    }

    private var hasStudioAccessories: Bool {
        studioQuoteBlock != nil || !studioTextBlocks.isEmpty || !linkedKnowledgePoints.isEmpty
    }

    private var editorialNotebookHeader: some View {
        VStack(alignment: .leading, spacing: 24) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    editorMetaTag(text: "Source: \(sourceAnchor.sourceTitle)", tint: AppPalette.paperTapeBlue.opacity(0.28))
                    if let currentOutlineTitle, !currentOutlineTitle.isEmpty {
                        editorMetaTag(text: "Topic: \(currentOutlineTitle)", tint: AppPalette.paperHighlight.opacity(0.78))
                    }
                    editorMetaTag(text: "Anchor: \(sourceAnchor.anchorLabel)", tint: AppPalette.paperHighlightMint.opacity(0.7))
                }
            }

            Text(notebookDisplayTitle)
                .font(.system(size: 42, weight: .medium, design: .serif))
                .foregroundStyle(AppPalette.paperInk)
                .lineSpacing(10)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text(sourceAnchor.anchorLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppPalette.paperMuted)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AppPalette.paperLine.opacity(0.68))
                    .frame(width: 128, height: 2)
            }

            HStack(spacing: 12) {
                if let pageIndex = sourceAnchor.pageIndex {
                    NotesMetaPill(text: "第\(pageIndex)页", tint: AppPalette.paperTapeBlue)
                }
                NotesMetaPill(text: sourceAnchor.anchorLabel, tint: AppPalette.paperHighlightMint)
                if !linkedKnowledgePoints.isEmpty {
                    NotesMetaPill(text: "\(linkedKnowledgePoints.count) 个知识点", tint: AppPalette.paperHighlight)
                }
            }

            if let quote = sourceAnchor.quotedText.nonEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Focus Excerpt")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(AppPalette.paperMuted)

                    Text(quote)
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .foregroundStyle(AppPalette.paperInk.opacity(0.82))
                        .italic()
                        .lineSpacing(10)
                        .frame(maxWidth: 780, alignment: .leading)
                }
                .padding(.top, 4)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var studioSourceStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let currentOutlineTitle {
                    Text(currentOutlineTitle)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(appearance.primaryForeground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(appearance.primaryChipFill)
                        )
                }

                Button {
                    onOpenSourceAnchor(sourceAnchor)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.square")
                        Text("回到原文")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(appearance.primaryForeground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(appearance.secondaryChipFill)
                    )
                }
                .buttonStyle(.plain)
            }

            Text(sourceAnchor.sourceTitle)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(appearance.pageTextColor)
                .lineLimit(1)

            HStack(spacing: 8) {
                NotesMetaPill(text: sourceAnchor.anchorLabel, tint: .blue)
                if let pageIndex = sourceAnchor.pageIndex {
                    NotesMetaPill(text: "第\(pageIndex)页", tint: .purple)
                }
                if studioPageCount > 1 {
                    NotesMetaPill(text: "笔记 \(studioPageCount) 页", tint: .green)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 420, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(appearance.headerPanelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(appearance.headerPanelStroke, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func studioInkSurface(for block: NoteBlock) -> some View {
        StudioInkCanvasSurface(
            block: Binding(
                get: { block },
                set: { onUpdateInkBlock($0) }
            ),
            sourceAnchor: sourceAnchor,
            candidateKnowledgePoints: candidateKnowledgePoints,
            appearance: appearance,
            inkToolState: $inkToolState,
            pageCount: $studioPageCount,
            doubleTapBehavior: doubleTapBehavior,
            highlighted: highlightedBlockID == block.id,
            onLinkKnowledgePoint: { pointID in
                onLinkKnowledgePointToBlock(pointID, block.id)
            },
            onSelectKnowledgePoint: onSelectKnowledgePoint
        )
        .padding(.top, 78)
        .padding(.leading, 18)
        .padding(.trailing, hasStudioAccessories ? 316 : 18)
        .padding(.bottom, 18)
    }

    private var studioCanvasPlaceholder: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "pencil.tip.crop.circle.badge.plus")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(appearance.pageTextColor)

            Text("这是一整页手写画布")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(appearance.pageTextColor)

            Text("点击上方手写工具，或者直接创建一个手写层，在整页上自由书写、圈画和标记。")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(appearance.pageSecondaryTextColor)
                .lineSpacing(5)
                .frame(maxWidth: 360, alignment: .leading)

            Button {
                onAddInkBlock()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "pencil.tip")
                    Text("开始整页书写")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    Capsule(style: .continuous)
                        .fill(appearance.actionFill)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 34)
        .padding(.top, 116)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var studioAccessoryColumn: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .trailing, spacing: 12) {
                if let quoteBlock = studioQuoteBlock {
                    StudioQuoteMemoCard(
                        block: quoteBlock,
                        sourceAnchor: sourceAnchorForBlock(quoteBlock),
                        isHighlighted: highlightedBlockID == quoteBlock.id,
                        onOpenSource: {
                            onOpenSourceAnchor(sourceAnchorForBlock(quoteBlock))
                        }
                    )
                }

                ForEach(Array(studioTextBlocks.enumerated()), id: \.element.id) { index, block in
                    StudioTextMemoCard(
                        title: "文本块 \(index + 1)",
                        text: Binding(
                            get: { block.text ?? "" },
                            set: { onUpdateTextBlock(block.id, $0) }
                        ),
                        isHighlighted: highlightedBlockID == block.id
                    )
                }

                if !linkedKnowledgePoints.isEmpty {
                    GlassPanel(tone: .light, cornerRadius: 24, padding: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("关联知识点")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.78))

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], alignment: .leading, spacing: 8) {
                                ForEach(Array(linkedKnowledgePoints.prefix(6))) { point in
                                    Button {
                                        onSelectKnowledgePoint(point)
                                    } label: {
                                        NotesMetaPill(text: point.title, tint: .blue)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .frame(width: 320)
                }
            }
            .padding(.bottom, 8)
        }
        .frame(width: 280)
    }

    private func canvasHeader(isStudio: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(isStudio ? "编辑画布" : "笔记页")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(isStudio ? appearance.pageSecondaryTextColor : Color.blue.opacity(0.76))

                Spacer(minLength: 0)

                if let currentOutlineTitle {
                    NotesMetaPill(text: currentOutlineTitle, tint: .blue)
                }

                Button {
                    onOpenSourceAnchor(sourceAnchor)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.square")
                        Text("回到原文")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isStudio ? appearance.primaryForeground : Color.blue.opacity(0.86))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isStudio ? appearance.secondaryChipFill : Color.white.opacity(0.74))
                    )
                }
                .buttonStyle(.plain)
            }

            Text(sourceAnchor.sourceTitle)
                .font(.system(size: isStudio ? 28 : 24, weight: .bold, design: .rounded))
                .foregroundStyle(isStudio ? appearance.pageTextColor : Color.black.opacity(0.82))

            HStack(spacing: 8) {
                NotesMetaPill(text: sourceAnchor.anchorLabel, tint: .blue)
                if let pageIndex = sourceAnchor.pageIndex {
                    NotesMetaPill(text: "第\(pageIndex)页", tint: .purple)
                }
                NotesMetaPill(text: "\(blocks.count) 个内容块", tint: .green)
            }

            ExpandableText(
                text: sourceAnchor.quotedText,
                font: .system(size: isStudio ? 17 : 16, weight: .medium),
                foregroundColor: isStudio ? appearance.pageSecondaryTextColor : Color.black.opacity(0.72),
                collapsedLineLimit: isStudio ? 3 : 4
            )

            if !isStudio {
                LinkedKnowledgePointChipsView(
                    points: linkedKnowledgePoints,
                    onSelect: onSelectKnowledgePoint,
                    onOpenSource: onOpenKnowledgePointSource
                )
            } else if !linkedKnowledgePoints.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(linkedKnowledgePoints.prefix(4)) { point in
                            Button {
                                onSelectKnowledgePoint(point)
                            } label: {
                                Text(point.title)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(appearance.primaryForeground)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(appearance.secondaryChipFill)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    showsAllAnchors.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(showsAllAnchors ? "收起来源细节" : "展开来源细节")
                    Image(systemName: showsAllAnchors ? "chevron.up" : "chevron.down")
                }
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(isStudio ? appearance.actionFill : Color.blue.opacity(0.82))
            }
            .buttonStyle(.plain)

            if showsAllAnchors {
                HStack(spacing: 20) {
                    if let sentenceID = sourceAnchor.sentenceID {
                        detailMetaLine(label: "句子 ID", value: sentenceID, isStudio: isStudio)
                    }

                    if let outlineNodeID = sourceAnchor.outlineNodeID {
                        detailMetaLine(label: "结构节点", value: outlineNodeID, isStudio: isStudio)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(isStudio ? 24 : 0)
        .background(
            Group {
                if isStudio {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(appearance.headerPanelFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(appearance.headerPanelStroke, lineWidth: 1)
                        )
                }
            }
        )
    }

    @ViewBuilder
    private func blockCard(_ block: NoteBlock) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionMarker(for: block.kind)

            switch block.kind {
            case .quote:
                QuoteBlockView(
                    block: block,
                    sourceAnchor: sourceAnchorForBlock(block),
                    presentationStyle: .editorial,
                    onOpenSource: {
                        onOpenSourceAnchor(sourceAnchorForBlock(block))
                    }
                )
                .overlay(highlightOverlay(for: block.id))

            case .text:
                TextBlockEditorView(
                    text: Binding(
                        get: { block.text ?? "" },
                        set: { onUpdateTextBlock(block.id, $0) }
                    ),
                    title: "Analysis Notes",
                    isHighlighted: highlightedBlockID == block.id,
                    minimumHeight: 190,
                    presentationStyle: .editorial
                )
                .overlay(highlightOverlay(for: block.id))

            case .ink:
                InkBlockWorkspaceView(
                    block: Binding(
                        get: { block },
                        set: { onUpdateInkBlock($0) }
                    ),
                    sourceAnchor: sourceAnchor,
                    candidateKnowledgePoints: candidateKnowledgePoints,
                    toolState: $inkToolState,
                    doubleTapBehavior: doubleTapBehavior,
                    appearance: appearance,
                    onLinkKnowledgePoint: { pointID in
                        onLinkKnowledgePointToBlock(pointID, block.id)
                    }
                )
                .overlay(highlightOverlay(for: block.id))
            }
        }
    }

    private func highlightOverlay(for blockID: UUID) -> some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .stroke(highlightedBlockID == blockID ? Color.blue.opacity(0.36) : Color.clear, lineWidth: 2)
            .animation(.easeInOut(duration: 0.22), value: highlightedBlockID == blockID)
    }

    private func editorMetaTag(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(AppPalette.paperInk.opacity(0.82))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint)
            )
            .rotationEffect(.degrees(Double((text.count % 3) - 1)))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                Text("工作台还是空的")
                    .font(.system(size: 24, weight: .medium, design: .serif))
                    .foregroundStyle(AppPalette.paperInk)

                Text("先添加一个文本块或手写块，把引用、理解和联想整理成自己的笔记。")
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(AppPalette.paperMuted)
                    .lineSpacing(8)
            }
        }
        .padding(.vertical, 20)
    }

    private var studioEmptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("开始整理这页笔记")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.94))

            Text("用顶部工具条添加引用、文本或手写块，把这份资料整理成你自己的学习页面。")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.68))
                .lineSpacing(5)

            HStack(spacing: 10) {
                studioChip(text: "插入引用")
                studioChip(text: "添加手写")
                studioChip(text: "添加文本")
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private var addBlockBar: some View {
        HStack(spacing: 12) {
            canvasButton(title: "添加文本块", icon: "text.justify") {
                onAddTextBlock()
            }

            canvasButton(title: "添加手写块", icon: "pencil.tip.crop.circle.badge.plus") {
                onAddInkBlock()
            }

            canvasButton(title: "插入引用块", icon: "quote.opening") {
                onAddQuoteBlock()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.34))
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
        )
    }

    private func canvasButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.72))
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.68))
            )
        }
        .buttonStyle(.plain)
    }

    private func sectionMarker(for kind: NoteBlockKind) -> some View {
        HStack(spacing: 10) {
            Text(sectionTitle(for: kind))
                .font(.system(size: 10, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(AppPalette.paperMuted)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(AppPalette.paperLine.opacity(0.54))
                .frame(height: 1)
        }
    }

    private func sectionTitle(for kind: NoteBlockKind) -> String {
        switch kind {
        case .quote:
            return "PRIMARY SOURCE"
        case .text:
            return "EDITORIAL NOTES"
        case .ink:
            return "INK LAYER"
        }
    }

    private var pageCounter: some View {
        Text(pageCounterText)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(appearance.primaryForeground.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(appearance.secondaryChipFill)
            )
    }

    private var undoRedoDock: some View {
        HStack(spacing: 10) {
            dockButton(icon: "arrow.uturn.backward")
            dockButton(icon: "arrow.uturn.forward")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(appearance.headerPanelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(appearance.headerPanelStroke, lineWidth: 1)
                )
        )
    }

    private func dockButton(icon: String) -> some View {
        Button {} label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(appearance.pageSecondaryTextColor)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(appearance.secondaryChipFill)
                )
        }
        .buttonStyle(.plain)
        .disabled(true)
    }

    private func studioChip(text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(appearance.primaryForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(appearance.secondaryChipFill)
            )
    }

    private func detailMetaLine(label: String, value: String, isStudio: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isStudio ? appearance.pageSecondaryTextColor.opacity(0.82) : Color.black.opacity(0.44))

            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isStudio ? appearance.pageSecondaryTextColor : Color.black.opacity(0.58))
                .lineLimit(2)
        }
    }

    private var pageCounterText: String {
        if layoutStyle == .studio {
            var parts: [String] = []
            if let pageIndex = sourceAnchor.pageIndex {
                parts.append("原文第\(pageIndex)页")
            }
            parts.append("笔记 \(studioPageCount) 页")
            return parts.joined(separator: " · ")
        }

        if let pageIndex = sourceAnchor.pageIndex {
            return "第\(pageIndex)页"
        }
        return "笔记画布"
    }

    private func syncStudioPageCount() {
        let storedCount = max(studioInkBlock?.inkGeometry?.pageCount ?? 1, 1)
        guard studioPageCount != storedCount else { return }
        studioPageCount = storedCount
    }

    private func scrollToHighlighted(_ blockID: UUID?, using proxy: ScrollViewProxy) {
        guard let blockID else { return }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
            proxy.scrollTo(blockID, anchor: .center)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            onHighlightHandled()
        }
    }
}

private struct NotebookPaperBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white,
                        Color(red: 0.991, green: 0.988, blue: 0.98)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                NotebookGrid(spacing: 28)
                    .opacity(0.08)
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            }
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.48),
                        .clear,
                        Color(red: 0.96, green: 0.95, blue: 0.92).opacity(0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            }
            .shadow(color: Color.black.opacity(0.04), radius: 32, x: 0, y: 8)
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct NotebookGuideLines: View {
    var topInset: CGFloat = 72
    var lineSpacing: CGFloat = 38
    var lineColor: Color = Color.blue.opacity(0.06)

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height

            Path { path in
                var y = topInset
                while y < height - 24 {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    y += lineSpacing
                }
            }
            .stroke(lineColor, lineWidth: 1)
        }
    }
}

private struct WorkspaceNotebookBackdrop: View {
    let appearance: NoteWorkspaceAppearance

    var body: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(appearance.workspaceDeskFill)
            .overlay {
                appearance.workspaceDeskOverlay
                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            }
    }
}

private struct StudioInkCanvasSurface: View {
    @Binding var block: NoteBlock
    @Binding var inkToolState: NoteInkToolState
    @Binding var pageCount: Int

    let sourceAnchor: SourceAnchor
    let candidateKnowledgePoints: [KnowledgePoint]
    let appearance: NoteWorkspaceAppearance
    let doubleTapBehavior: NotePencilDoubleTapBehavior
    let highlighted: Bool
    let onLinkKnowledgePoint: (String) -> Void
    let onSelectKnowledgePoint: (KnowledgePoint) -> Void

    @State private var drawingData: Data
    @StateObject private var inkAssistViewModel = InkAssistViewModel()

    init(
        block: Binding<NoteBlock>,
        sourceAnchor: SourceAnchor,
        candidateKnowledgePoints: [KnowledgePoint],
        appearance: NoteWorkspaceAppearance,
        inkToolState: Binding<NoteInkToolState>,
        pageCount: Binding<Int>,
        doubleTapBehavior: NotePencilDoubleTapBehavior,
        highlighted: Bool,
        onLinkKnowledgePoint: @escaping (String) -> Void,
        onSelectKnowledgePoint: @escaping (KnowledgePoint) -> Void
    ) {
        _block = block
        _inkToolState = inkToolState
        _pageCount = pageCount
        self.sourceAnchor = sourceAnchor
        self.candidateKnowledgePoints = candidateKnowledgePoints
        self.appearance = appearance
        self.doubleTapBehavior = doubleTapBehavior
        self.highlighted = highlighted
        self.onLinkKnowledgePoint = onLinkKnowledgePoint
        self.onSelectKnowledgePoint = onSelectKnowledgePoint
        _drawingData = State(initialValue: block.wrappedValue.inkData ?? Data())
    }

    private var linkedPoints: [KnowledgePoint] {
        let lookup = Dictionary(uniqueKeysWithValues: candidateKnowledgePoints.map { ($0.id, $0) })
        return block.linkedKnowledgePointIDs.compactMap { lookup[$0] }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            InkNoteCanvasView(
                drawingData: $drawingData,
                toolState: $inkToolState,
                pageCount: $pageCount,
                appearance: appearance,
                doubleTapBehavior: doubleTapBehavior,
                suggestion: inkAssistViewModel.activeSuggestion,
                onStopDrawing: { data, bounds, canvasSize in
                    handleInkDidSettle(data: data, bounds: bounds, canvasSize: canvasSize)
                },
                onResumeDrawing: {
                    inkAssistViewModel.handleResumeWriting()
                },
                onDismissSuggestion: {
                    inkAssistViewModel.hideSuggestion()
                },
                onConfirmSuggestion: {
                    confirmSuggestion()
                }
            )

            if !linkedPoints.isEmpty || !(block.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                VStack(alignment: .leading, spacing: 10) {
                    if let recognizedText = block.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !recognizedText.isEmpty {
                        Text("识别结果：\(recognizedText)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(appearance.pageSecondaryTextColor)
                            .lineLimit(2)
                    }

                    if !linkedPoints.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(linkedPoints) { point in
                                    Button {
                                        onSelectKnowledgePoint(point)
                                    } label: {
                                        Text(point.title)
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(appearance.primaryForeground)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                Capsule(style: .continuous)
                                                    .fill(appearance.secondaryChipFill)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(appearance.infoDockFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(appearance.headerPanelStroke, lineWidth: 1)
                        )
                )
                .padding(.leading, 14)
                .padding(.bottom, 14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(appearance.inkSurfaceFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(highlighted ? appearance.actionFill.opacity(0.72) : Color.clear, lineWidth: 2)
                )
        )
        .onChange(of: block.inkData) { newValue in
            drawingData = newValue ?? Data()
        }
    }

    private func handleInkDidSettle(data: Data, bounds: CGRect, canvasSize: CGSize) {
        guard !data.isEmpty, canvasSize.width > 0, canvasSize.height > 0, !bounds.isEmpty else {
            inkAssistViewModel.hideSuggestion()
            return
        }

        block.inkData = data
        block.linkedSourceAnchorID = sourceAnchor.id
        block.inkGeometry = InkGeometry(
            normalizedBounds: normalizedBounds(bounds, in: canvasSize),
            pageIndex: sourceAnchor.pageIndex,
            pageCount: pageCount
        )
        block.lastRecognitionAt = Date()

        inkAssistViewModel.handleDrawingDidSettle(
            block: block,
            sourceAnchor: sourceAnchor,
            knowledgePoints: candidateKnowledgePoints
        )
    }

    private func confirmSuggestion() {
        inkAssistViewModel.confirmSuggestion { suggestion in
            block.recognizedText = suggestion.recognizedText
            block.recognitionConfidence = suggestion.recognitionConfidence
            block.linkedSourceAnchorID = suggestion.sourceAnchorID ?? sourceAnchor.id
            block.lastSuggestionAt = Date()

            if !block.linkedKnowledgePointIDs.contains(suggestion.matchedKnowledgePointID) {
                block.linkedKnowledgePointIDs.append(suggestion.matchedKnowledgePointID)
            }

            onLinkKnowledgePoint(suggestion.matchedKnowledgePointID)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func normalizedBounds(_ bounds: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: min(max(bounds.origin.x / size.width, 0), 1),
            y: min(max(bounds.origin.y / size.height, 0), 1),
            width: min(max(bounds.width / size.width, 0), 1),
            height: min(max(bounds.height / size.height, 0), 1)
        )
    }
}

private struct StudioQuoteMemoCard: View {
    let block: NoteBlock
    let sourceAnchor: SourceAnchor
    let isHighlighted: Bool
    let onOpenSource: () -> Void

    var body: some View {
        GlassPanel(tone: .light, cornerRadius: 24, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    NotesMetaPill(text: "引用", tint: .orange)
                    NotesMetaPill(text: sourceAnchor.anchorLabel, tint: .blue)
                }

                ExpandableText(
                    text: block.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? block.text ?? "" : sourceAnchor.quotedText,
                    font: .system(size: 14, weight: .semibold),
                    foregroundColor: Color.black.opacity(0.78),
                    collapsedLineLimit: 5
                )

                Button(action: onOpenSource) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.square")
                        Text("查看原文")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.blue.opacity(0.86))
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isHighlighted ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 2)
        )
        .frame(width: 320)
    }
}

private struct StudioTextMemoCard: View {
    let title: String
    @Binding var text: String
    let isHighlighted: Bool

    var body: some View {
        GlassPanel(tone: .light, cornerRadius: 24, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    NotesMetaPill(text: title, tint: .green)
                    if isHighlighted {
                        NotesMetaPill(text: "当前定位", tint: .blue)
                    }
                }

                TextEditor(text: $text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 150)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isHighlighted ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 2)
        )
        .frame(width: 320)
    }
}

extension NoteWorkspaceAppearance {
    var pageFill: LinearGradient {
        switch self {
        case .paper:
            return LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.997, blue: 0.987),
                    Color(red: 0.992, green: 0.989, blue: 0.978)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .night:
            return LinearGradient(
                colors: [
                    Color(red: 39 / 255, green: 44 / 255, blue: 58 / 255),
                    Color(red: 29 / 255, green: 34 / 255, blue: 46 / 255)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .eyeCare:
            return LinearGradient(
                colors: [
                    Color(red: 243 / 255, green: 246 / 255, blue: 228 / 255),
                    Color(red: 235 / 255, green: 240 / 255, blue: 218 / 255)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    var pageTextColor: Color {
        switch self {
        case .paper:
            return Color.black.opacity(0.82)
        case .night:
            return Color.white.opacity(0.94)
        case .eyeCare:
            return Color(red: 46 / 255, green: 62 / 255, blue: 42 / 255).opacity(0.88)
        }
    }

    var pageSecondaryTextColor: Color {
        switch self {
        case .paper:
            return Color.black.opacity(0.58)
        case .night:
            return Color.white.opacity(0.68)
        case .eyeCare:
            return Color(red: 73 / 255, green: 90 / 255, blue: 66 / 255).opacity(0.74)
        }
    }

    var pageLineColor: Color {
        switch self {
        case .paper:
            return Color.blue.opacity(0.10)
        case .night:
            return Color.white.opacity(0.09)
        case .eyeCare:
            return Color(red: 121 / 255, green: 148 / 255, blue: 113 / 255).opacity(0.16)
        }
    }

    var marginLineColor: Color {
        switch self {
        case .paper:
            return Color.red.opacity(0.16)
        case .night:
            return Color.orange.opacity(0.22)
        case .eyeCare:
            return Color.orange.opacity(0.16)
        }
    }

    var pageBorderColor: Color {
        switch self {
        case .paper:
            return Color.white.opacity(0.86)
        case .night:
            return Color.white.opacity(0.10)
        case .eyeCare:
            return Color.white.opacity(0.54)
        }
    }

    var pageShadowColor: Color {
        switch self {
        case .paper:
            return Color.black.opacity(0.10)
        case .night:
            return Color.black.opacity(0.34)
        case .eyeCare:
            return Color.black.opacity(0.08)
        }
    }

    var primaryForeground: Color {
        switch self {
        case .paper:
            return Color.blue.opacity(0.88)
        case .night:
            return Color.white.opacity(0.94)
        case .eyeCare:
            return Color(red: 70 / 255, green: 103 / 255, blue: 69 / 255).opacity(0.9)
        }
    }

    var primaryChipFill: Color {
        switch self {
        case .paper:
            return Color.blue.opacity(0.12)
        case .night:
            return Color(red: 84 / 255, green: 120 / 255, blue: 193 / 255).opacity(0.28)
        case .eyeCare:
            return Color(red: 158 / 255, green: 188 / 255, blue: 149 / 255).opacity(0.34)
        }
    }

    var secondaryChipFill: Color {
        switch self {
        case .paper:
            return Color.white.opacity(0.76)
        case .night:
            return Color.white.opacity(0.08)
        case .eyeCare:
            return Color.white.opacity(0.44)
        }
    }

    var actionFill: Color {
        switch self {
        case .paper:
            return Color.blue.opacity(0.78)
        case .night:
            return Color(red: 102 / 255, green: 141 / 255, blue: 219 / 255).opacity(0.82)
        case .eyeCare:
            return Color(red: 103 / 255, green: 145 / 255, blue: 96 / 255).opacity(0.88)
        }
    }

    var headerPanelFill: Color {
        switch self {
        case .paper:
            return Color.white.opacity(0.72)
        case .night:
            return Color.white.opacity(0.06)
        case .eyeCare:
            return Color.white.opacity(0.42)
        }
    }

    var headerPanelStroke: Color {
        switch self {
        case .paper:
            return Color.white.opacity(0.82)
        case .night:
            return Color.white.opacity(0.10)
        case .eyeCare:
            return Color.white.opacity(0.46)
        }
    }

    var inkSurfaceFill: Color {
        switch self {
        case .paper:
            return Color.clear
        case .night:
            return Color.white.opacity(0.02)
        case .eyeCare:
            return Color.white.opacity(0.06)
        }
    }

    var infoDockFill: Color {
        switch self {
        case .paper:
            return Color.white.opacity(0.92)
        case .night:
            return Color.black.opacity(0.26)
        case .eyeCare:
            return Color.white.opacity(0.64)
        }
    }

    var workspaceDeskFill: LinearGradient {
        switch self {
        case .paper:
            return LinearGradient(
                colors: [
                    Color(red: 223 / 255, green: 234 / 255, blue: 250 / 255),
                    Color(red: 238 / 255, green: 244 / 255, blue: 251 / 255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .night:
            return LinearGradient(
                colors: [
                    Color(red: 25 / 255, green: 29 / 255, blue: 38 / 255),
                    Color(red: 20 / 255, green: 24 / 255, blue: 32 / 255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .eyeCare:
            return LinearGradient(
                colors: [
                    Color(red: 224 / 255, green: 233 / 255, blue: 211 / 255),
                    Color(red: 236 / 255, green: 241 / 255, blue: 223 / 255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    var workspaceDeskOverlay: some View {
        switch self {
        case .paper:
            GeometryReader { proxy in
                Path { path in
                    let lineSpacing: CGFloat = 54
                    var y: CGFloat = 0
                    while y <= proxy.size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        y += lineSpacing
                    }
                }
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
        case .night:
            GeometryReader { proxy in
                Path { path in
                    let gridSize: CGFloat = 52
                    var x: CGFloat = 0
                    while x <= proxy.size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                        x += gridSize
                    }

                    var y: CGFloat = 0
                    while y <= proxy.size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        y += gridSize
                    }
                }
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        case .eyeCare:
            GeometryReader { proxy in
                Path { path in
                    let lineSpacing: CGFloat = 54
                    var y: CGFloat = 0
                    while y <= proxy.size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        y += lineSpacing
                    }
                }
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
            }
        }
    }
}
