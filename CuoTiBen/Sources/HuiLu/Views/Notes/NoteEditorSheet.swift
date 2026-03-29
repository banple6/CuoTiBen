import SwiftUI
import UIKit

enum NoteEditorMode: String, Identifiable {
    case create
    case edit
    case append

    var id: String { rawValue }

    var navigationTitle: String {
        switch self {
        case .create:
            return "加入笔记"
        case .edit:
            return "编辑笔记"
        case .append:
            return "追加内容"
        }
    }

    var saveTitle: String {
        switch self {
        case .append:
            return "追加"
        default:
            return "保存"
        }
    }
}

struct NoteEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: AppViewModel

    let seed: NoteEditorSeed
    var existingNote: Note? = nil
    var mode: NoteEditorMode = .create

    @State private var titleText: String
    @State private var bodyText: String
    @State private var tagsText: String
    @State private var knowledgePointsText: String
    @State private var drawingData: Data
    @State private var inkDraftBlock: NoteBlock
    @State private var saveError: String?
    @State private var enablesInkEditing: Bool
    @State private var showsInkCanvas = false
    @State private var notebookNote: Note?
    @StateObject private var inkAssistViewModel = InkAssistViewModel()

    init(seed: NoteEditorSeed, existingNote: Note? = nil, mode: NoteEditorMode = .create) {
        self.seed = seed
        self.existingNote = existingNote
        self.mode = mode

        let existingInkBlock = mode == .append ? nil : existingNote?.inkBlocks.first
        let existingBody = existingNote?.textBlocks.map { $0.text ?? "" }.joined(separator: "\n\n") ?? seed.suggestedBody
        _titleText = State(initialValue: existingNote?.title ?? seed.suggestedTitle)
        _bodyText = State(initialValue: mode == .append ? "" : existingBody)
        _tagsText = State(initialValue: mode == .append ? "" : (existingNote?.tags ?? seed.suggestedTags).joined(separator: ", "))
        _knowledgePointsText = State(initialValue: mode == .append ? "" : (existingNote?.knowledgePoints.map(\.title) ?? seed.suggestedKnowledgePoints.map(\.title)).joined(separator: ", "))
        _drawingData = State(initialValue: mode == .append ? Data() : (existingInkBlock?.inkData ?? Data()))
        _enablesInkEditing = State(initialValue: false)
        _inkDraftBlock = State(
            initialValue: existingInkBlock ?? NoteBlock(
                kind: .ink,
                inkData: mode == .append ? nil : existingInkBlock?.inkData,
                recognizedText: existingInkBlock?.recognizedText,
                recognitionConfidence: existingInkBlock?.recognitionConfidence,
                linkedSourceAnchorID: existingInkBlock?.linkedSourceAnchorID ?? seed.anchor.id,
                linkedKnowledgePointIDs: existingInkBlock?.linkedKnowledgePointIDs ?? [],
                inkGeometry: existingInkBlock?.inkGeometry,
                lastSuggestionAt: existingInkBlock?.lastSuggestionAt,
                lastRecognitionAt: existingInkBlock?.lastRecognitionAt
            )
        )
    }

    private var usesPadInkCanvas: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var candidateKnowledgePointsForInkAssist: [KnowledgePoint] {
        let typedPoints = knowledgePointsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { KnowledgePoint(title: $0) }
        let merged = viewModel.allKnowledgePoints()
            + seed.suggestedKnowledgePoints
            + (existingNote?.knowledgePoints ?? [])
            + typedPoints

        return merged
            .reduce(into: [String: KnowledgePoint]()) { partialResult, point in
                guard !point.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                if let existing = partialResult[point.id] {
                    partialResult[point.id] = KnowledgePoint(
                        id: existing.id,
                        title: existing.title,
                        definition: longerText(existing.definition, point.definition) ?? existing.definition,
                        shortDefinition: longerText(existing.shortDefinition, point.shortDefinition),
                        aliases: Array(Set(existing.aliases + point.aliases)).sorted(),
                        relatedKnowledgePointIDs: Array(Set(existing.relatedKnowledgePointIDs + point.relatedKnowledgePointIDs)).sorted()
                    )
                } else {
                    partialResult[point.id] = point
                }
            }
            .values
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    private var linkedKnowledgePointTitles: [String] {
        let lookup = Dictionary(uniqueKeysWithValues: candidateKnowledgePointsForInkAssist.map { ($0.id, $0.title) })
        return inkDraftBlock.linkedKnowledgePointIDs.compactMap { lookup[$0] }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .light)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        sourceCard
                        if mode == .append {
                            existingBlocksSection
                        } else {
                            titleSection
                        }
                        quoteSection
                        textSection
                        tagSection
                        knowledgePointSection

                        if usesPadInkCanvas {
                            inkSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            }
            .navigationTitle(mode.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        if usesPadInkCanvas {
                            Button("笔记本") {
                                openNotebook()
                            }
                            .font(.system(size: 15, weight: .bold))
                        }

                        Button(mode.saveTitle) {
                            saveAndDismiss()
                        }
                        .font(.system(size: 16, weight: .bold))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let saveError {
                    SheetActionStatus(text: saveError)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
            }
        }
        .presentationDetents(usesPadInkCanvas ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            guard usesPadInkCanvas else { return }
            if enablesInkEditing, !showsInkCanvas {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    showsInkCanvas = true
                }
            }
        }
        .onDisappear {
            showsInkCanvas = false
            inkAssistViewModel.hideSuggestion()
        }
        .fullScreenCover(item: $notebookNote) { note in
            NavigationStack {
                NoteNotebookView(note: note)
                    .environmentObject(viewModel)
            }
        }
    }

    private var existingBlocksSection: some View {
        GlassPanel(tone: .light, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(existingNote?.title ?? seed.suggestedTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.82))

                Text("当前已有 \(existingNote?.blocks.count ?? 0) 个内容块，你现在追加的文字或手写会直接挂到这条笔记后面。")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.58))
                    .lineSpacing(4)

                if let latestText = existingNote?.textBlocks.last?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !latestText.isEmpty {
                    ExpandableText(
                        text: latestText,
                        font: .system(size: 14, weight: .medium),
                        foregroundColor: Color.black.opacity(0.68),
                        collapsedLineLimit: 3
                    )
                }
            }
        }
    }

    private var sourceCard: some View {
        GlassPanel(tone: .light, cornerRadius: 26, padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(seed.document.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.82))

                HStack(spacing: 8) {
                    BreadcrumbPill(text: seed.anchor.anchorLabel)
                    if let pageIndex = seed.anchor.pageIndex {
                        BreadcrumbPill(text: "第\(pageIndex)页")
                    }
                }
            }
        }
    }

    private var titleSection: some View {
        noteInputSection(title: "标题") {
            TextField("输入笔记标题", text: $titleText)
                .font(.system(size: 16, weight: .semibold))
                .textInputAutocapitalization(.never)
        }
    }

    private var quoteSection: some View {
        noteInputSection(title: "引用原句") {
            ExpandableText(
                text: seed.anchor.quotedText,
                font: .system(size: 15, weight: .medium),
                foregroundColor: Color.black.opacity(0.72),
                collapsedLineLimit: 5
            )
        }
    }

    private var textSection: some View {
        noteInputSection(title: mode == .append ? "追加正文" : "笔记正文") {
            TextEditor(text: $bodyText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.78))
                .frame(minHeight: 180)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
        }
    }

    private var tagSection: some View {
        noteInputSection(title: mode == .append ? "追加标签" : "标签") {
            TextField(mode == .append ? "可留空；新增标签会并入原笔记" : "用英文逗号分隔，例如：长难句, 政策语境", text: $tagsText)
                .font(.system(size: 15, weight: .medium))
                .textInputAutocapitalization(.never)
        }
    }

    private var knowledgePointSection: some View {
        noteInputSection(title: mode == .append ? "追加知识点" : "关联知识点") {
            TextField(mode == .append ? "可留空；新增知识点会参与重新抽取" : "用英文逗号分隔，例如：宾语从句, 政策表达", text: $knowledgePointsText)
                .font(.system(size: 15, weight: .medium))
                .textInputAutocapitalization(.never)
        }
    }

    @ViewBuilder
    private var inkSection: some View {
        noteInputSection(title: "手写块") {
            VStack(alignment: .leading, spacing: 12) {
                Text("局部手写只挂载到当前笔记，不做整页无限画布。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.5))

                if enablesInkEditing {
                    Group {
                        if showsInkCanvas {
                            InkNoteCanvasView(
                                drawingData: $drawingData,
                                toolState: .constant(NoteInkToolState()),
                                pageCount: .constant(1),
                                appearance: .paper,
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
                                    confirmInkSuggestion()
                                }
                            )
                        } else {
                            ProgressView("正在准备手写画布…")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.48))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(height: 220)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.9), lineWidth: 1)
                    )
                } else {
                    Button {
                        enablesInkEditing = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            showsInkCanvas = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "pencil.tip.crop.circle.badge.plus")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Color.blue.opacity(0.86))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(drawingData.isEmpty ? "添加手写块" : "继续编辑手写块")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Color.black.opacity(0.82))

                                Text("点击后再加载手写画布，减少 iPad 上打开编辑器时的干扰。")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.54))
                                    .lineSpacing(3)
                            }

                            Spacer()
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white.opacity(0.58))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(Color.blue.opacity(0.14), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let suggestion = inkAssistViewModel.activeSuggestion {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.blue.opacity(0.82))
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("可能关联知识点：\(suggestion.matchedKnowledgePointTitle)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.8))

                            if !suggestion.recognizedText.isEmpty {
                                Text("识别到：\(suggestion.recognizedText)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.56))
                                    .lineLimit(2)
                            }
                        }

                        Spacer(minLength: 8)

                        Button("关联") {
                            confirmInkSuggestion()
                        }
                        .font(.system(size: 13, weight: .bold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.blue.opacity(0.9))
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.blue.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.blue.opacity(0.18), lineWidth: 1)
                            )
                    )
                }

                if let recognizedText = inkDraftBlock.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !recognizedText.isEmpty {
                    Text("识别结果：\(recognizedText)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.56))
                        .lineLimit(2)
                }

                if !linkedKnowledgePointTitles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(linkedKnowledgePointTitles, id: \.self) { title in
                                NotesMetaPill(text: title, tint: .blue)
                            }
                        }
                    }
                }

                HStack {
                    Spacer()

                    Button("清空手写") {
                        clearInkDraft()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.blue.opacity(0.8))
                }
            }
        }
    }

    private func noteInputSection<Content: View>(title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        GlassPanel(tone: .light, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.8))

                content()
            }
        }
    }

    private func saveAndDismiss() {
        guard persistNote() != nil else { return }
        dismiss()
    }

    private func openNotebook() {
        guard let note = persistNote() else { return }
        notebookNote = note
    }

    @discardableResult
    private func persistNote() -> Note? {
        let tags = tagsText
            .split(separator: ",")
            .map(String.init)
        let knowledgePoints = knowledgePointsText
            .split(separator: ",")
            .map(String.init)

        let result: Note?
        if mode == .append, let existingNote {
            result = viewModel.appendBlocks(
                to: existingNote,
                body: bodyText,
                tags: tags,
                knowledgePointTitles: knowledgePoints,
                inkData: drawingData,
                inkBlock: resolvedInkBlockForSave()
            )
        } else {
            result = viewModel.saveNote(
                existingNote: existingNote,
                seed: seed,
                title: titleText,
                body: bodyText,
                tags: tags,
                knowledgePointTitles: knowledgePoints,
                inkData: drawingData,
                inkBlock: resolvedInkBlockForSave()
            )
        }

        guard result != nil else {
            saveError = "笔记保存失败，请稍后重试。"
            return nil
        }

        saveError = nil
        return result
    }

    private func resolvedInkBlockForSave() -> NoteBlock? {
        guard !drawingData.isEmpty else { return nil }
        var block = inkDraftBlock
        block.inkData = drawingData
        block.linkedSourceAnchorID = block.linkedSourceAnchorID ?? seed.anchor.id
        return block
    }

    private func clearInkDraft() {
        drawingData = Data()
        inkDraftBlock = NoteBlock(kind: .ink, linkedSourceAnchorID: seed.anchor.id)
        inkAssistViewModel.hideSuggestion()
    }

    private func handleInkDidSettle(data: Data, bounds: CGRect, canvasSize: CGSize) {
        guard !data.isEmpty, canvasSize.width > 0, canvasSize.height > 0, !bounds.isEmpty else {
            inkAssistViewModel.hideSuggestion()
            return
        }

        inkDraftBlock.inkData = data
        inkDraftBlock.linkedSourceAnchorID = seed.anchor.id
        inkDraftBlock.inkGeometry = InkGeometry(
            normalizedBounds: normalizedBounds(bounds, in: canvasSize),
            pageIndex: seed.anchor.pageIndex
        )
        inkDraftBlock.lastRecognitionAt = Date()

        inkAssistViewModel.handleDrawingDidSettle(
            block: inkDraftBlock,
            sourceAnchor: seed.anchor,
            knowledgePoints: candidateKnowledgePointsForInkAssist
        )
    }

    private func confirmInkSuggestion() {
        inkAssistViewModel.confirmSuggestion { suggestion in
            inkDraftBlock.recognizedText = suggestion.recognizedText
            inkDraftBlock.recognitionConfidence = suggestion.recognitionConfidence
            inkDraftBlock.linkedSourceAnchorID = suggestion.sourceAnchorID ?? seed.anchor.id
            inkDraftBlock.lastSuggestionAt = Date()

            if !inkDraftBlock.linkedKnowledgePointIDs.contains(suggestion.matchedKnowledgePointID) {
                inkDraftBlock.linkedKnowledgePointIDs.append(suggestion.matchedKnowledgePointID)
            }

            mergeKnowledgePointTitleIntoField(suggestion.matchedKnowledgePointTitle)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func mergeKnowledgePointTitleIntoField(_ title: String) {
        var items = knowledgePointsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !items.contains(where: { $0.localizedCaseInsensitiveCompare(title) == .orderedSame }) {
            items.append(title)
            knowledgePointsText = items.joined(separator: ", ")
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

    private func longerText(_ lhs: String?, _ rhs: String?) -> String? {
        let left = lhs?.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (left?.isEmpty == false ? left : nil, right?.isEmpty == false ? right : nil) {
        case let (left?, right?):
            return left.count >= right.count ? left : right
        case let (left?, nil):
            return left
        case let (nil, right?):
            return right
        default:
            return nil
        }
    }
}
