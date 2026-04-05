import SwiftUI

#if canImport(PencilKit)
import PencilKit
#endif

#if os(iOS)
import UIKit
#endif

struct NoteDetailPane: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    let note: Note?
    let onOpenSource: ((SourceAnchor) -> Void)?
    var onOpenNote: ((Note) -> Void)? = nil

    @State private var activeKnowledgePoint: KnowledgePoint?
    @State private var activeRelatedNote: Note?
    @State private var sourceJumpTarget: SourceJumpTarget?
    @State private var draftNote: Note?
    @State private var saveStatusText = "已保存"
    @State private var autosaveTask: Task<Void, Never>?
    @State private var cachedContext: LearningRecordContext?
    @State private var cachedLinkedKnowledgePoints: [KnowledgePoint] = []
    @State private var cachedSourceDocument: SourceDocument?

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var detailModel: NoteDetailViewModel? {
        guard let draftNote else { return nil }
        return NoteDetailViewModel(
            note: draftNote,
            sourceDocument: cachedSourceDocument,
            context: cachedContext ?? .empty(for: .note(noteID: draftNote.id)),
            linkedKnowledgePoints: cachedLinkedKnowledgePoints
        )
    }

    private var hasPendingEdits: Bool {
        saveStatusText == "未保存" || saveStatusText == "保存中"
    }

    var body: some View {
        Group {
            if let detailModel {
                ScrollView(showsIndicators: false) {
                    editorialCanvas(for: detailModel)
                }
            } else {
                emptyState
            }
        }
        .background(editorialShell)
        .onAppear {
            syncDraftNote(force: true)
        }
        .onChange(of: note?.id) { _ in
            syncDraftNote(force: true)
        }
        .onChange(of: note?.updatedAt) { _ in
            syncDraftNote(force: !hasPendingEdits)
        }
        .onDisappear {
            autosaveTask?.cancel()
        }
        .sheet(item: $activeKnowledgePoint) { point in
            NavigationStack {
                KnowledgePointDetailView(point: point) { anchor in
                    openSource(anchor)
                }
                .environmentObject(appViewModel)
            }
        }
        .sheet(item: $activeRelatedNote) { note in
            NavigationStack {
                NoteDetailView(note: note) { anchor in
                    openSource(anchor)
                }
                .environmentObject(appViewModel)
            }
        }
        .fullScreenCover(item: $sourceJumpTarget) { target in
            ReviewWorkbenchView(document: target.document, initialAnchor: target.anchor) {
                sourceJumpTarget = nil
            }
            .environmentObject(appViewModel)
        }
    }

    // MARK: - Editorial Canvas (main layout)

    private func editorialCanvas(for model: NoteDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Paper article container
            VStack(alignment: .leading, spacing: 0) {
                // — Note Header Area —
                editorialHeader(for: model)
                    .padding(.bottom, isPad ? 40 : 28)

                // — Two-column grid on iPad, stacked on iPhone —
                if isPad {
                    HStack(alignment: .top, spacing: ArchivistSpacing.xl) {
                        // Left: Original text column
                        VStack(alignment: .leading, spacing: ArchivistSpacing.xxl) {
                            editorialQuoteSection(for: model)
                            editorialTextBlocksSection(for: model)
                            editorialInkSection(for: model)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Right: Analysis panel
                        VStack(alignment: .leading, spacing: ArchivistSpacing.xl) {
                            editorialAnalysisPanel(for: model)
                            editorialKnowledgeSection(for: model)
                            editorialRelatedSection(for: model)
                        }
                        .frame(width: 320, alignment: .topLeading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: ArchivistSpacing.xxl) {
                        editorialQuoteSection(for: model)
                        editorialAnalysisPanel(for: model)
                        editorialTextBlocksSection(for: model)
                        editorialKnowledgeSection(for: model)
                        editorialInkSection(for: model)
                        editorialRelatedSection(for: model)
                    }
                }
            }
            // Asymmetric margins: wider left margin mimics notebook binding
            .padding(.leading, isPad ? ArchivistSpacing.paperLeftMargin : 28)
            .padding(.trailing, isPad ? ArchivistSpacing.paperRightMargin : 20)
            .padding(.vertical, isPad ? ArchivistSpacing.paperVerticalMargin : 32)
            .background(editorialPaperSurface)

            Spacer(minLength: isPad ? 40 : 24)
        }
        .padding(.bottom, 14)
    }

    // MARK: - Editorial Shell & Paper Surface

    @ViewBuilder
    private var editorialShell: some View {
        Color(red: 251 / 255, green: 249 / 255, blue: 244 / 255) // surface #fbf9f4
            .ignoresSafeArea()
    }

    private var editorialPaperSurface: some View {
        ZStack {
            // Base: crisp white paper
            RoundedRectangle(cornerRadius: isPad ? 4 : 6, style: .continuous)
                .fill(Color.white)

            // Dot grid texture (subtle)
            EditorialDotGrid()
                .clipShape(RoundedRectangle(cornerRadius: isPad ? 4 : 6, style: .continuous))

            // Left binding accent (4pt colored bar) 
            RoundedRectangle(cornerRadius: isPad ? 4 : 6, style: .continuous)
                .fill(Color.clear)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color(red: 234 / 255, green: 232 / 255, blue: 227 / 255))
                        .frame(width: 4)
                }
        }
        .shadow(color: Color(red: 27 / 255, green: 28 / 255, blue: 25 / 255).opacity(0.04), radius: 20, x: 0, y: 8)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "note.text")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.blue.opacity(0.72))

            Text("从左侧选择一条笔记，查看完整内容。")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.72))

            Text("这里会展示可编辑标题、引用、文本块、手写块、关联知识点，以及可继续回看的上下文。")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.48))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Editorial Header

    private func editorialHeader(for model: NoteDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: ArchivistSpacing.lg) {
            // Washi tape tags (source, topic, level)
            HStack(spacing: 10) {
                EditorialWashiTag(
                    text: "Source: \(model.sourceTitle)",
                    tint: Color(red: 198 / 255, green: 228 / 255, blue: 244 / 255) // secondary-container
                )
                if let pageLabel = model.pageLabel {
                    EditorialWashiTag(
                        text: pageLabel,
                        tint: Color(red: 223 / 255, green: 236 / 255, blue: 96 / 255).opacity(0.3) // tertiary-fixed/30
                    )
                }
                EditorialWashiTag(
                    text: model.anchorLabel,
                    tint: Color(red: 212 / 255, green: 227 / 255, blue: 255 / 255).opacity(0.3) // primary-fixed/30
                )
            }

            // Large serif title
            TextField(
                "输入笔记标题",
                text: Binding(
                    get: { draftNote?.title ?? "" },
                    set: { newValue in
                        updateDraftNote { note in
                            note.title = newValue
                        }
                    }
                )
            )
            .font(.system(size: isPad ? 36 : 28, weight: .regular, design: .serif))
            .foregroundStyle(Color(red: 27 / 255, green: 28 / 255, blue: 25 / 255)) // on-surface
            .textInputAutocapitalization(.never)

            // Thin rule
            Rectangle()
                .fill(Color(red: 193 / 255, green: 199 / 255, blue: 211 / 255).opacity(0.15)) // outline-variant at 15%
                .frame(height: 1)

            // Source subtitle + save status + actions
            HStack(alignment: .center, spacing: 14) {
                Text(model.sourceSubtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0 / 255, green: 93 / 255, blue: 167 / 255).opacity(0.82)) // primary
                    .lineLimit(1)

                Text("·")
                    .foregroundStyle(Color(red: 113 / 255, green: 119 / 255, blue: 131 / 255).opacity(0.5))

                Text("最近编辑 \(model.lastEditedText)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 113 / 255, green: 119 / 255, blue: 131 / 255)) // outline
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(saveStatusText)
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(
                        saveStatusText == "已保存"
                            ? Color(red: 89 / 255, green: 97 / 255, blue: 0 / 255) // tertiary
                            : Color(red: 186 / 255, green: 26 / 255, blue: 26 / 255) // error
                    )
            }

            // Action buttons — secondary style (text + icon, no heavy bg)
            HStack(spacing: isPad ? 16 : 10) {
                EditorialActionLink(title: "回到原文", icon: "text.alignleft") {
                    flushAutosave()
                    openSource(model.note.sourceAnchor)
                }

                EditorialActionLink(title: "生成卡片", icon: "rectangle.stack.badge.plus") {
                    flushAutosave()
                    generateCard(for: model)
                }
            }
        }
    }

    // MARK: - Editorial Quote Section

    private func editorialQuoteSection(for model: NoteDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.quoteBlocks) { block in
                QuoteBlockView(
                    block: block,
                    sourceAnchor: model.note.sourceAnchor,
                    presentationStyle: .editorial,
                    onOpenSource: {
                        openSource(model.note.sourceAnchor)
                    }
                )
            }

            // Handwritten-style note
            if !model.quoteText.isEmpty {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color(red: 0 / 255, green: 93 / 255, blue: 167 / 255).opacity(0.2))
                        .frame(width: 2)
                    Text("Note: \(model.quoteText.prefix(80))…")
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(Color(red: 0 / 255, green: 93 / 255, blue: 167 / 255).opacity(0.7))
                        .padding(.leading, 14)
                        .padding(.vertical, 12)
                }
                .padding(.top, 12)
            }
        }
    }

    // MARK: - Editorial Text Blocks

    @ViewBuilder
    private func editorialTextBlocksSection(for model: NoteDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                EditorialSectionLabel(text: "文本笔记")
                Spacer()
                Button {
                    addTextBlock()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("添加")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color(red: 0 / 255, green: 93 / 255, blue: 167 / 255))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(red: 0 / 255, green: 93 / 255, blue: 167 / 255).opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
            }

            if model.textBlocks.isEmpty {
                Text("点击右上角添加文本块。")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(red: 113 / 255, green: 119 / 255, blue: 131 / 255))
            } else {
                ForEach(Array(model.textBlocks.enumerated()), id: \.element.id) { index, block in
                    TextBlockEditorView(
                        text: textBinding(for: block.id),
                        title: "文本块 \(index + 1)",
                        isHighlighted: false,
                        minimumHeight: 138,
                        onDelete: {
                            deleteTextBlock(block.id)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Editorial Analysis Panel (Glass)

    @ViewBuilder
    private func editorialAnalysisPanel(for model: NoteDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: ArchivistSpacing.lg) {
            // Panel header
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0 / 255, green: 93 / 255, blue: 167 / 255))
                Text("ANALYSIS")
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(Color(red: 0 / 255, green: 93 / 255, blue: 167 / 255))
            }

            // Analysis blocks separated by dashed dividers
            VStack(alignment: .leading, spacing: 0) {
                // Quote context
                editorialAnalysisBlock(label: "原句线索", content: model.quoteText)

                editorialDashedDivider()

                // Auto-linked knowledge
                editorialAnalysisBlock(
                    label: "自动关联",
                    content: model.suggestedKnowledgePoints.first?.title ?? fallbackKnowledgeLine(for: model)
                )

                editorialDashedDivider()

                // Reverse lookup
                editorialAnalysisBlock(
                    label: "反向回看",
                    content: "相关来源 \(model.relatedSourceAnchors.count) 条 · 相关笔记 \(model.relatedNotes.count) 条 · 相关卡片 \(model.relatedCards.count) 张"
                )
            }
        }
        .padding(ArchivistSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 240 / 255, green: 238 / 255, blue: 233 / 255).opacity(0.3)) // surface-container/30
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
        )
    }

    private func editorialAnalysisBlock(label: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Color(red: 113 / 255, green: 119 / 255, blue: 131 / 255).opacity(0.7))

            Text(content)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(red: 65 / 255, green: 71 / 255, blue: 81 / 255))
                .lineSpacing(4)
                .lineLimit(4)
        }
        .padding(.vertical, 10)
    }

    private func editorialDashedDivider() -> some View {
        Rectangle()
            .fill(Color(red: 193 / 255, green: 199 / 255, blue: 211 / 255).opacity(0.3))
            .frame(height: 1)
    }

    // MARK: - Editorial Knowledge Points

    @ViewBuilder
    private func editorialKnowledgeSection(for model: NoteDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialSectionLabel(text: "关联知识点")

            if model.knowledgePoints.isEmpty {
                Text("当前笔记还没有挂上知识点。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 113 / 255, green: 119 / 255, blue: 131 / 255))
            } else {
                NoteEditableKnowledgePointFlow(
                    points: model.knowledgePoints,
                    onSelect: { point in
                        activeKnowledgePoint = point
                    },
                    onOpenSource: { point in
                        if let anchor = point.sourceAnchors.first {
                            openSource(anchor)
                        }
                    },
                    onRemove: { point in
                        removeKnowledgePoint(point)
                    }
                )
            }

            if !model.suggestedKnowledgePoints.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("推荐关联")
                        .font(.system(size: 10, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundStyle(Color(red: 113 / 255, green: 119 / 255, blue: 131 / 255).opacity(0.7))

                    FlexibleChipFlow(items: Array(model.suggestedKnowledgePoints.prefix(8))) { point in
                        Button {
                            appendKnowledgePoint(point)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10, weight: .bold))
                                Text("关联 \(point.title)")
                                    .lineLimit(1)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(red: 0 / 255, green: 93 / 255, blue: 167 / 255))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color(red: 0 / 255, green: 93 / 255, blue: 167 / 255).opacity(0.06))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Editorial Ink Section

    @ViewBuilder
    private func editorialInkSection(for model: NoteDetailViewModel) -> some View {
        if !model.inkBlocks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                EditorialSectionLabel(text: "手写块预览")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                    ForEach(model.inkBlocks) { block in
                        NoteInkPreviewCard(block: block)
                    }
                }
            }
        }
    }

    // MARK: - Editorial Related Section

    private func editorialRelatedSection(for model: NoteDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                EditorialSectionLabel(text: "关联信息")
                Spacer()
                Text("最后整理于 \(model.lastEditedText)")
                    .font(.system(size: 10, weight: .medium))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(Color(red: 113 / 255, green: 119 / 255, blue: 131 / 255))
            }

            RelatedContextPanel(
                context: model.context,
                hiddenNoteIDs: Set([model.note.id]),
                hiddenKnowledgePointIDs: Set(model.note.linkedKnowledgePointIDs),
                onOpenNote: { relatedNote in
                    flushAutosave()
                    if let onOpenNote {
                        onOpenNote(relatedNote)
                    } else {
                        activeRelatedNote = relatedNote
                    }
                },
                onOpenKnowledgePoint: { point in
                    activeKnowledgePoint = point
                },
                onOpenSourceAnchor: { anchor in
                    flushAutosave()
                    openSource(anchor)
                },
                onOpenCard: { item in
                    flushAutosave()
                    if let anchor = item.sourceAnchor {
                        openSource(anchor)
                    }
                }
            )
        }
    }

    private func syncDraftNote(force: Bool) {
        guard force || !hasPendingEdits else { return }

        guard let note else {
            draftNote = nil
            cachedContext = nil
            cachedLinkedKnowledgePoints = []
            cachedSourceDocument = nil
            saveStatusText = "已保存"
            return
        }

        let resolvedNote = appViewModel.note(with: note.id) ?? note
        draftNote = resolvedNote
        refreshDetailCaches(for: resolvedNote, refreshContext: true)
        saveStatusText = "已保存"
    }

    private func updateDraftNote(_ mutate: (inout Note) -> Void) {
        guard var current = draftNote else { return }
        mutate(&current)
        current.updatedAt = Date()
        draftNote = current
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        saveStatusText = "未保存"
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                persistDraftNote()
            }
        }
    }

    private func flushAutosave() {
        guard hasPendingEdits else { return }
        autosaveTask?.cancel()
        persistDraftNote()
    }

    private func persistDraftNote() {
        guard var current = draftNote else { return }
        saveStatusText = "保存中"
        current.title = current.title.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? current.sourceAnchor.anchorLabel
        current.updatedAt = Date()

        if let saved = appViewModel.persistWorkspaceNote(current) {
            draftNote = saved
            refreshDetailCaches(for: saved, refreshContext: true)
            saveStatusText = "已保存"
        } else {
            saveStatusText = "保存失败"
        }
    }

    private func textBinding(for blockID: UUID) -> Binding<String> {
        Binding(
            get: {
                draftNote?.blocks.first(where: { $0.id == blockID })?.text ?? ""
            },
            set: { newValue in
                updateDraftNote { note in
                    guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return }
                    note.blocks[index].text = newValue
                    note.blocks[index].updatedAt = Date()
                }
            }
        )
    }

    private func addTextBlock() {
        updateDraftNote { note in
            note.blocks.append(NoteBlock(kind: .text, text: ""))
        }
    }

    private func deleteTextBlock(_ blockID: UUID) {
        updateDraftNote { note in
            note.blocks.removeAll { $0.id == blockID }
        }
    }

    private func appendKnowledgePoint(_ point: KnowledgePoint) {
        updateDraftNote { note in
            guard !note.knowledgePoints.contains(where: { $0.id == point.id }) else { return }
            note.knowledgePoints.append(point)
        }
        if let draftNote {
            refreshDetailCaches(for: draftNote, refreshContext: false)
        }
    }

    private func removeKnowledgePoint(_ point: KnowledgePoint) {
        updateDraftNote { note in
            note.knowledgePoints.removeAll { $0.id == point.id }
            for index in note.blocks.indices {
                note.blocks[index].linkedKnowledgePointIDs.removeAll { $0 == point.id }
            }
        }
        if let draftNote {
            refreshDetailCaches(for: draftNote, refreshContext: false)
        }
    }

    private func generateCard(for model: NoteDetailViewModel) {
        guard let document = model.sourceDocument else { return }

        if let sentence = appViewModel.sentence(for: model.note.sourceAnchor) {
            _ = appViewModel.addSentenceCard(for: sentence, explanation: nil, in: document)
            return
        }

        if let node = appViewModel.outlineNode(for: model.note.sourceAnchor) {
            _ = appViewModel.addNodeCard(for: node, in: document)
        }
    }

    private func openSource(_ anchor: SourceAnchor) {
        if let target = appViewModel.sourceJumpTarget(for: anchor) {
            if let onOpenSource {
                onOpenSource(target.anchor)
            } else {
                sourceJumpTarget = target
            }
            return
        }

        onOpenSource?(anchor)
    }

    private func refreshDetailCaches(for note: Note, refreshContext: Bool) {
        cachedSourceDocument = appViewModel.sourceDocument(for: note.sourceAnchor)
        cachedLinkedKnowledgePoints = NoteDetailViewModel.resolveLinkedKnowledgePoints(
            for: note,
            using: appViewModel
        )

        if refreshContext || cachedContext == nil {
            cachedContext = appViewModel.learningRecordContext(forNoteID: note.id)
        }
    }
}

// MARK: - Editorial Section Label

private struct EditorialSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .textCase(.uppercase)
            .tracking(2)
            .foregroundStyle(Color(red: 113 / 255, green: 119 / 255, blue: 131 / 255).opacity(0.7))
    }
}

// MARK: - Editorial Washi Tag

private struct EditorialWashiTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color(red: 27 / 255, green: 28 / 255, blue: 25 / 255).opacity(0.75))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint.opacity(0.4))
            )
            .rotationEffect(.degrees(-0.5))
    }
}

// MARK: - Editorial Action Link (secondary button style)

private struct EditorialActionLink: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Color(red: 0 / 255, green: 93 / 255, blue: 167 / 255)) // primary
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(red: 41 / 255, green: 118 / 255, blue: 199 / 255).opacity(0.08)) // primary-container at 20%
            )
        }
        .buttonStyle(.plain)
    }
}

private struct NoteEditableKnowledgePointFlow: View {
    let points: [KnowledgePoint]
    let onSelect: (KnowledgePoint) -> Void
    let onOpenSource: (KnowledgePoint) -> Void
    let onRemove: (KnowledgePoint) -> Void

    var body: some View {
        FlexibleChipFlow(items: points) { point in
            HStack(spacing: 6) {
                Button {
                    onSelect(point)
                } label: {
                    WashiKnowledgeChip(
                        title: point.title,
                        tint: AppPalette.paperTapeBlue.opacity(0.28),
                        foreground: WorkspaceColors.primaryInk
                    )
                }
                .buttonStyle(.plain)

                Button {
                    onOpenSource(point)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WorkspaceColors.primaryInk.opacity(0.86))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppPalette.paperCard.opacity(0.84))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    onRemove(point)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.red.opacity(0.84))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.red.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private extension NoteDetailPane {
    func fallbackKnowledgeLine(for model: NoteDetailViewModel) -> String {
        if let point = model.knowledgePoints.first {
            return "已关联知识点：\(point.title)"
        }
        return "当前还没有明确知识点，建议从这句原文开始标注。"
    }
}

private struct NoteInkPreviewCard: View {
    let block: NoteBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            inkPreview
                .frame(height: 170)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.78))
                )

                if let recognizedText = block.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !recognizedText.isEmpty {
                    Text(recognizedText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.56))
                        .lineLimit(2)
                } else {
                    Text("手写块预览")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.42))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.92), lineWidth: 1)
                    )
            )
    }

    @ViewBuilder
    private var inkPreview: some View {
        #if canImport(PencilKit)
        if let data = block.inkData,
           let drawing = try? PKDrawing(data: data) {
            let rect = drawing.bounds.insetBy(dx: -20, dy: -20)
            let renderRect = rect.isNull ? CGRect(x: 0, y: 0, width: 320, height: 180) : rect
            let image = drawing.image(from: renderRect, scale: 2)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(12)
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        Text("暂无手写预览")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.black.opacity(0.42))
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Dot Grid Texture (matches HTML dot-grid)

private struct EditorialDotGrid: View {
    var spacing: CGFloat = 24
    var dotSize: CGFloat = 1
    var opacity: Double = 0.1

    var body: some View {
        Canvas { context, size in
            let cols = Int(size.width / spacing) + 1
            let rows = Int(size.height / spacing) + 1
            for row in 0..<rows {
                for col in 0..<cols {
                    let point = CGPoint(
                        x: CGFloat(col) * spacing,
                        y: CGFloat(row) * spacing
                    )
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: point.x - dotSize / 2,
                            y: point.y - dotSize / 2,
                            width: dotSize,
                            height: dotSize
                        )),
                        with: .color(Color(red: 27 / 255, green: 28 / 255, blue: 25 / 255))
                    )
                }
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}
