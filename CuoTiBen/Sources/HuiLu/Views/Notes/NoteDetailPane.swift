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
    var onOpenWorkspace: ((Note) -> Void)? = nil
    var onOpenNote: ((Note) -> Void)? = nil

    @State private var activeKnowledgePoint: KnowledgePoint?
    @State private var activeRelatedNote: Note?
    @State private var fallbackWorkspaceNote: Note?
    @State private var sourceJumpTarget: SourceJumpTarget?
    @State private var draftNote: Note?
    @State private var saveStatusText = "已保存"
    @State private var autosaveTask: Task<Void, Never>?
    @State private var cachedContext: LearningRecordContext?
    @State private var cachedLinkedKnowledgePoints: [KnowledgePoint] = []
    @State private var cachedSourceDocument: SourceDocument?

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
        GlassPanel(tone: .light, cornerRadius: 34, padding: 22) {
            if let detailModel {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        headerCard(for: detailModel)
                        quoteSection(for: detailModel)
                        textBlocksSection(for: detailModel)
                        knowledgePointSection(for: detailModel)
                        inkSection(for: detailModel)
                        relatedSection(for: detailModel)
                    }
                    .padding(.bottom, 14)
                }
            } else {
                emptyState
            }
        }
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
        .fullScreenCover(item: $fallbackWorkspaceNote) { note in
            NavigationStack {
                NoteWorkspaceView(note: note, onOpenSource: onOpenSource)
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

    private func headerCard(for model: NoteDetailViewModel) -> some View {
        GlassPanel(tone: .light, cornerRadius: 28, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
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
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.86))
                    .textInputAutocapitalization(.never)

                    NoteDetailStatusPill(text: saveStatusText)
                }

                Text(model.sourceSubtitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.blue.opacity(0.82))

                HStack(spacing: 8) {
                    if let pageLabel = model.pageLabel {
                        BreadcrumbPill(text: pageLabel)
                    }
                    BreadcrumbPill(text: model.anchorLabel)
                    Text("最近编辑 \(model.lastEditedText)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.45))
                        .padding(.leading, 2)
                }

                HStack(spacing: 12) {
                    NotePaneActionButton(title: "回到原文", icon: "text.alignleft") {
                        flushAutosave()
                        openSource(model.note.sourceAnchor)
                    }

                    NotePaneActionButton(title: "进入工作台", icon: "rectangle.and.pencil.and.ellipsis") {
                        openWorkspace(using: model.note)
                    }

                    NotePaneActionButton(title: "生成卡片", icon: "rectangle.stack.badge.plus") {
                        flushAutosave()
                        generateCard(for: model)
                    }
                }
            }
        }
    }

    private func quoteSection(for model: NoteDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NotePaneSectionTitle(text: "原句引用")

            ForEach(model.quoteBlocks) { block in
                QuoteBlockView(
                    block: block,
                    sourceAnchor: model.note.sourceAnchor,
                    onOpenSource: {
                        openSource(model.note.sourceAnchor)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func textBlocksSection(for model: NoteDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                NotePaneSectionTitle(text: "文本笔记")
                Spacer()
                Button {
                    addTextBlock()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("添加文本块")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.blue.opacity(0.86))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.blue.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }

            if model.textBlocks.isEmpty {
                SentenceExplainBlock(
                    title: "还没有文本块",
                    content: "点击右上角添加文本块，把想法、总结或解题思路写下来。",
                    tone: .neutral
                )
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

    @ViewBuilder
    private func knowledgePointSection(for model: NoteDetailViewModel) -> some View {
        GlassPanel(tone: .light, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("关联知识点")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.8))

                if model.knowledgePoints.isEmpty {
                    Text("当前笔记还没有挂上知识点。下方会继续给你推荐可一键关联的知识点。")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.5))
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
                    VStack(alignment: .leading, spacing: 10) {
                        Text("推荐关联")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.72))

                        FlexibleChipFlow(items: Array(model.suggestedKnowledgePoints.prefix(8))) { point in
                            Button {
                                appendKnowledgePoint(point)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("关联 \(point.title)")
                                        .lineLimit(1)
                                }
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.blue.opacity(0.88))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.blue.opacity(0.08))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func inkSection(for model: NoteDetailViewModel) -> some View {
        if !model.inkBlocks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                NotePaneSectionTitle(text: "手写块预览")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                    ForEach(model.inkBlocks) { block in
                        NoteInkPreviewCard(block: block) {
                            openWorkspace(using: model.note)
                        }
                    }
                }
            }
        }
    }

    private func relatedSection(for model: NoteDetailViewModel) -> some View {
        GlassPanel(tone: .light, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("关联信息")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.8))

                    Spacer()

                    Text("最后整理于 \(model.lastEditedText)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.45))
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

    private func openWorkspace(using note: Note) {
        flushAutosave()
        let target = draftNote ?? note
        if let onOpenWorkspace {
            onOpenWorkspace(target)
        } else {
            fallbackWorkspaceNote = target
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

private struct NotePaneSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.8))
    }
}

private struct NotePaneActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(Color.blue.opacity(0.88))
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.blue.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct NoteDetailStatusPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(text == "已保存" ? Color.green.opacity(0.9) : Color.orange.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.78))
            )
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
                    NotesMetaPill(text: point.title, tint: .blue)
                }
                .buttonStyle(.plain)

                Button {
                    onOpenSource(point)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.blue.opacity(0.86))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.78))
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
                            Capsule(style: .continuous)
                                .fill(Color.red.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct NoteInkPreviewCard: View {
    let block: NoteBlock
    let onOpenWorkspace: () -> Void

    var body: some View {
        Button(action: onOpenWorkspace) {
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
                    Text("点击进入工作台深度编辑")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.42))
                }

                HStack(spacing: 6) {
                    Image(systemName: "rectangle.and.pencil.and.ellipsis")
                    Text("进入工作台")
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.blue.opacity(0.82))
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
        .buttonStyle(.plain)
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
