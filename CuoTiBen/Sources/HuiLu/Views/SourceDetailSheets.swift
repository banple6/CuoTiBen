import SwiftUI

enum ExplainHighlightTone {
    case neutral
    case sentence
    case translation
    case teaching
    case structure
    case grammar
    case rewrite
    case node
    case vocabulary
    case misread

    var accent: Color {
        switch self {
        case .neutral:
            return Color.blue.opacity(0.74)
        case .sentence:
            return AppPalette.amber
        case .translation:
            return AppPalette.mint
        case .teaching:
            return Color.green.opacity(0.74)
        case .structure:
            return AppPalette.primary
        case .grammar:
            return AppPalette.amber
        case .rewrite:
            return Color.pink.opacity(0.72)
        case .node:
            return Color.blue.opacity(0.76)
        case .vocabulary:
            return Color.cyan.opacity(0.78)
        case .misread:
            return Color.orange.opacity(0.76)
        }
    }

    var softFill: Color {
        accent.opacity(0.1)
    }

    var stroke: Color {
        accent.opacity(0.22)
    }
}

struct SentenceExplainDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: AppViewModel

    let document: SourceDocument

    @State private var activeSentence: Sentence
    @State private var result: AIExplainSentenceResult?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showsContext = false
    @State private var selectedWord: WordExplanationEntry?
    @State private var noteSeed: NoteEditorSeed?
    @State private var actionNote: String?
    @State private var activeRelatedNote: Note?
    @State private var activeKnowledgePoint: KnowledgePoint?
    @State private var explanationTask: Task<Void, Never>?

    init(document: SourceDocument, sentence: Sentence) {
        self.document = document
        _activeSentence = State(initialValue: sentence)
    }

    private var breadcrumb: SentenceBreadcrumb {
        viewModel.sentenceBreadcrumb(for: activeSentence, in: document)
    }

    private var previousSentence: Sentence? {
        viewModel.previousSentence(for: activeSentence, in: document)
    }

    private var nextSentence: Sentence? {
        viewModel.nextSentence(for: activeSentence, in: document)
    }

    private var contextSentences: [Sentence] {
        viewModel.contextSentences(for: activeSentence, in: document)
    }

    private var effectiveAnalysis: ProfessorSentenceAnalysis? {
        let bundled = viewModel.professorSentenceCard(for: activeSentence, in: document)?.analysis
        if let remote = result?.localFallbackAnalysis {
            return remote.mergingFallback(bundled)
        }
        return bundled
    }

    private let contentBottomInset: CGFloat = 170

    private var learningContext: LearningRecordContext {
        viewModel.learningRecordContext(forSentenceID: activeSentence.id)
    }

    private var evidenceRolePresentation: (label: String, description: String)? {
        guard let presentation = professorSentenceRolePresentation(for: effectiveAnalysis?.evidenceType) else {
            return nil
        }
        return (presentation.label, presentation.description)
    }

    private var relatedEvidenceItems: [String] {
        guard let bundle = viewModel.structuredSource(for: document) else { return [] }
        var items: [String] = []

        if let paragraphCard = bundle.paragraphCard(forSegmentID: activeSentence.segmentID) {
            if let blindSpot = paragraphCard.studentBlindSpot?.nonEmpty {
                items.append("本段易偏点：\(blindSpot)")
            }
            if let focus = paragraphCard.teachingFocuses.first?.nonEmpty {
                items.append("本段教学重点：\(focus)")
            }
        }

        let questionHints = bundle.questionLinks
            .filter { link in
                link.supportingSentenceIDs.contains(activeSentence.id) ||
                link.supportParagraphIDs.contains(activeSentence.segmentID)
            }
            .prefix(2)
            .map { link -> String in
                let trap = link.trapType.nonEmpty ?? "题目证据"
                let evidence = link.paraphraseEvidence.first?.nonEmpty
                    ?? String(link.questionText.prefix(48))
                return "\(trap)：\(evidence)"
            }

        items.append(contentsOf: questionHints)

        var seen: Set<String> = []
        return items.compactMap(\.nonEmpty).filter { item in
            let inserted = seen.insert(item).inserted
            return inserted
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let layout = AdaptiveSheetLayout(width: proxy.size.width)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        breadcrumbSection
                        sentenceCard
                        sentenceUtilitySection(layout: layout)

                        if showsContext {
                            contextSection
                        }

                        explanationContent(layout: layout)
                    }
                    .frame(maxWidth: layout.contentWidth, alignment: .leading)
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.top, 24)
                    .padding(.bottom, contentBottomInset)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .background(AppBackground(style: .light))
                .navigationTitle("句子讲解")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("关闭") { dismiss() }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    sentenceActionBar(layout: layout)
                }
            }
        }
        .sheet(item: $selectedWord) { entry in
            WordExplainDetailSheet(document: document, entry: entry)
                .environmentObject(viewModel)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $noteSeed) { seed in
            NoteEditorSheet(seed: seed)
                .environmentObject(viewModel)
        }
        .sheet(item: $activeRelatedNote) { note in
            NavigationStack {
                NoteDetailView(note: note) { anchor in
                    openRelatedAnchor(anchor)
                }
                .environmentObject(viewModel)
            }
        }
        .sheet(item: $activeKnowledgePoint) { point in
            NavigationStack {
                KnowledgePointDetailView(point: point) { anchor in
                    openRelatedAnchor(anchor)
                }
                .environmentObject(viewModel)
            }
        }
        .onAppear {
            scheduleExplanationLoad(force: result == nil)
        }
        .onChange(of: activeSentence.id) { _ in
            actionNote = nil
            scheduleExplanationLoad(force: true)
        }
        .onDisappear {
            explanationTask?.cancel()
            explanationTask = nil
        }
    }

    private var breadcrumbSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        }
    }

    private var sentenceCard: some View {
        SentenceFocusCard(
            anchorLabel: activeSentence.anchorLabel,
            text: activeSentence.text,
            highlightTokens: effectiveAnalysis?.vocabularyInContext.map(\.term) ?? []
        )
    }

    private var sentenceNavigationBar: some View {
        HStack(spacing: 12) {
            DetailActionButton(title: "上一句", icon: "chevron.left", isDisabled: previousSentence == nil) {
                guard let previousSentence else { return }
                activeSentence = previousSentence
            }

            DetailActionButton(title: "下一句", icon: "chevron.right", isDisabled: nextSentence == nil) {
                guard let nextSentence else { return }
                activeSentence = nextSentence
            }
        }
    }

    private var contextToggleButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
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

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("原文上下文")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.76))

            ForEach(contextSentences) { sentence in
                ContextSentenceCard(
                    sentence: sentence,
                    isCurrent: sentence.id == activeSentence.id
                ) {
                    activeSentence = sentence
                }
            }
        }
    }

    @ViewBuilder
    private func explanationContent(layout: AdaptiveSheetLayout) -> some View {
        if let analysis = effectiveAnalysis {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading {
                    ProgressView("正在获取教授式精讲…")
                        .font(.system(size: 14, weight: .medium))
                } else if let errorMessage, result == nil {
                    SentenceExplainBlock(
                        title: "提示",
                        content: "当前展示的是本地教学卡骨架；远端教授式精讲获取失败：\(errorMessage)",
                        tone: .neutral
                    )
                }

                if analysis.isAIGenerated {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                        Text("AI 教授级精析")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.purple.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color.purple.opacity(0.08))
                        )
                }

                ProfessorAnalysisPanel(
                    analysis: analysis,
                    keywordMinimumWidth: layout.keywordMinimumWidth,
                    selectedTerm: selectedWord?.term,
                    relatedEvidenceItems: relatedEvidenceItems
                ) { keyword in
                    selectedWord = viewModel.wordExplanation(
                        for: keyword.term,
                        meaningHint: keyword.hint,
                        sentence: activeSentence,
                        in: document
                    )
                }

                relatedContextPanel
            }
        } else if isLoading {
            ProgressView("正在获取讲解…")
                .font(.system(size: 15, weight: .medium))
        } else if let errorMessage {
            VStack(alignment: .leading, spacing: 10) {
                Text("讲解获取失败")
                    .font(.system(size: 16, weight: .bold))

                Text(errorMessage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.62))

                Button("重新获取") {
                    scheduleExplanationLoad(force: true)
                }
                .font(.system(size: 14, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.blue.opacity(0.82))
            }
        }
    }

    @ViewBuilder
    private func sentenceUtilitySection(layout: AdaptiveSheetLayout) -> some View {
        if layout.prefersUtilitySplit {
            HStack(alignment: .top, spacing: 12) {
                sentenceNavigationBar
                contextToggleButton
            }
        } else {
            sentenceNavigationBar
            contextToggleButton
        }
    }

    private func sentenceActionBar(layout: AdaptiveSheetLayout) -> some View {
        VStack(spacing: 12) {
            if let actionNote {
                SheetActionStatus(text: actionNote)
            }

            HStack(spacing: 12) {
                DetailActionButton(title: "加入笔记", icon: "note.text.badge.plus") {
                    noteSeed = viewModel.sentenceNoteSeed(
                        for: activeSentence,
                        explanation: result,
                        in: document
                    )
                }

                DetailActionButton(title: "生成卡片", icon: "rectangle.stack.badge.plus") {
                    _ = viewModel.addSentenceCard(for: activeSentence, explanation: result, in: document)
                    actionNote = "已把当前句子加入卡片草稿。"
                }
            }
        }
        .frame(maxWidth: layout.actionBarWidth, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, layout.usesPadPresentation ? 16 : 18)
        .background(actionBarBackground(layout: layout))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, layout.usesPadPresentation ? 24 : 0)
        .padding(.bottom, layout.usesPadPresentation ? 10 : 0)
    }

    private func scheduleExplanationLoad(force: Bool) {
        let sentence = activeSentence
        if !force, isLoading || result != nil {
            return
        }

        explanationTask?.cancel()
        explanationTask = Task {
            await loadExplanation(for: sentence)
        }
    }

    private func loadExplanation(for sentence: Sentence) async {
        await MainActor.run {
            guard activeSentence.id == sentence.id else { return }
            isLoading = true
            errorMessage = nil
            result = nil
        }

        do {
            let context = viewModel.explainSentenceContext(for: sentence, in: document)
            let fetched = try await AIExplainSentenceService.fetchExplanation(for: context)
            try Task.checkCancellation()

            await MainActor.run {
                guard activeSentence.id == sentence.id else { return }
                result = fetched
                isLoading = false
            }
        } catch is CancellationError {
            await MainActor.run {
                guard activeSentence.id == sentence.id else { return }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                guard activeSentence.id == sentence.id else { return }
                result = nil
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private var relatedContextPanel: some View {
        RelatedContextPanel(
            context: learningContext,
            onOpenNote: { note in
                activeRelatedNote = note
            },
            onOpenKnowledgePoint: { point in
                activeKnowledgePoint = point
            },
            onOpenSourceAnchor: { anchor in
                openRelatedAnchor(anchor)
            },
            onOpenCard: { item in
                if let anchor = item.sourceAnchor {
                    openRelatedAnchor(anchor)
                } else {
                    actionNote = "当前卡片暂时没有更精确的来源锚点。"
                }
            }
        )
    }

    private func openRelatedAnchor(_ anchor: SourceAnchor) {
        if let sentence = viewModel.sentence(for: anchor) {
            activeSentence = sentence
            showsContext = true
        } else {
            actionNote = "该来源暂时无法直接定位到句子。"
        }
    }
}

struct OutlineNodeDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: AppViewModel

    let document: SourceDocument
    let node: OutlineNode
    let onAnchorTap: (OutlineNodeAnchorItem) -> Void
    let onSentenceTap: (Sentence) -> Void
    let onJumpToOriginal: (OutlineNode) -> Void

    @State private var selectedWord: WordExplanationEntry?
    @State private var actionNote: String?

    private var snapshot: OutlineNodeDetailSnapshot {
        viewModel.outlineNodeDetail(for: node, in: document)
    }

    private let contentBottomInset: CGFloat = 178

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let layout = AdaptiveSheetLayout(width: proxy.size.width)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
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
                        keywordSection(layout: layout)
                    }
                    .frame(maxWidth: layout.contentWidth, alignment: .leading)
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.top, 24)
                    .padding(.bottom, contentBottomInset)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .background(AppBackground(style: .light))
                .navigationTitle("节点详情")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("关闭") { dismiss() }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    nodeActionBar(layout: layout)
                }
            }
        }
        .sheet(item: $selectedWord) { entry in
            WordExplainDetailSheet(document: document, entry: entry)
                .environmentObject(viewModel)
                .presentationDetents([.medium, .large])
        }
    }

    private var anchorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("来源锚点")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.78))

            ForEach(snapshot.anchorItems) { anchor in
                Button {
                    dismissThen {
                        onAnchorTap(anchor)
                    }
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
                    content: "当前节点暂未绑定到具体句子，可先点击“查看原文”定位到上下文。",
                    tone: .node
                )
            } else {
                ForEach(snapshot.keySentences) { sentence in
                    Button {
                        dismissThen {
                            onSentenceTap(sentence)
                        }
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

    private func keywordSection(layout: AdaptiveSheetLayout) -> some View {
        InteractiveKeywordSection(
            title: "关键词",
            minimumItemWidth: layout.keywordMinimumWidth,
            selectedTerm: selectedWord?.term,
            keywords: snapshot.keywords
        ) { keyword in
            selectedWord = viewModel.wordExplanation(
                for: keyword.term,
                meaningHint: keyword.hint,
                sentence: snapshot.keySentences.first,
                in: document
            )
        }
    }

    private func nodeActionBar(layout: AdaptiveSheetLayout) -> some View {
        VStack(spacing: 12) {
            if let actionNote {
                SheetActionStatus(text: actionNote)
            }

            HStack(spacing: 10) {
                DetailActionButton(title: "查看原文", icon: "text.alignleft") {
                    dismissThen {
                        onJumpToOriginal(node)
                    }
                }

                DetailActionButton(
                    title: "逐句解析",
                    icon: "text.magnifyingglass",
                    isDisabled: snapshot.keySentences.isEmpty
                ) {
                    guard let sentence = snapshot.keySentences.first else { return }
                    dismissThen {
                        onSentenceTap(sentence)
                    }
                }

                DetailActionButton(title: "生成卡片", icon: "rectangle.stack.badge.plus") {
                    _ = viewModel.addNodeCard(for: node, in: document)
                    actionNote = "已把当前节点加入卡片草稿。"
                }
            }
        }
        .frame(maxWidth: layout.actionBarWidth, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, layout.usesPadPresentation ? 16 : 18)
        .background(actionBarBackground(layout: layout))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, layout.usesPadPresentation ? 24 : 0)
        .padding(.bottom, layout.usesPadPresentation ? 10 : 0)
    }

    private func dismissThen(_ action: @escaping () -> Void) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            action()
        }
    }
}

struct WordExplainDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: AppViewModel

    let document: SourceDocument
    let entry: WordExplanationEntry

    @State private var noteSeed: NoteEditorSeed?
    @State private var actionNote: String?
    @State private var activeRelatedNote: Note?
    @State private var activeKnowledgePoint: KnowledgePoint?
    @State private var activeRelatedSentence: Sentence?
    private let contentBottomInset: CGFloat = 160

    private var learningContext: LearningRecordContext {
        if let sentence = entry.sourceSentence {
            return viewModel.learningRecordContext(forWord: entry.term, sentenceID: sentence.id)
        }

        return .empty(for: .word(term: entry.term, lemma: nil, sentenceID: ""))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let layout = AdaptiveSheetLayout(width: proxy.size.width)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        headerCard
                        SentenceExplainBlock(
                            title: "本句释义",
                            content: entry.sentenceMeaning,
                            tone: .vocabulary,
                            highlightTokens: [entry.term]
                        )

                        if layout.prefersTwoColumnCards {
                            HStack(alignment: .top, spacing: 14) {
                                SentenceExplainListBlock(title: "常见义项", items: entry.commonMeanings, tone: .vocabulary)
                                SentenceExplainListBlock(title: "常见搭配", items: entry.collocations, tone: .vocabulary)
                            }

                            SentenceExplainListBlock(title: "例句", items: entry.examples, tone: .vocabulary)
                        } else {
                            SentenceExplainListBlock(title: "常见义项", items: entry.commonMeanings, tone: .vocabulary)
                            SentenceExplainListBlock(title: "常见搭配", items: entry.collocations, tone: .vocabulary)
                            SentenceExplainListBlock(title: "例句", items: entry.examples, tone: .vocabulary)
                        }

                        relatedWordContextPanel
                    }
                    .frame(maxWidth: layout.contentWidth, alignment: .leading)
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.top, 24)
                    .padding(.bottom, contentBottomInset)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .background(AppBackground(style: .light))
                .navigationTitle("单词讲解")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("关闭") { dismiss() }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    wordActionBar(layout: layout)
                }
            }
        }
        .sheet(item: $noteSeed) { seed in
            NoteEditorSheet(seed: seed)
                .environmentObject(viewModel)
        }
        .sheet(item: $activeRelatedNote) { note in
            NavigationStack {
                NoteDetailView(note: note) { anchor in
                    openRelatedAnchor(anchor)
                }
                .environmentObject(viewModel)
            }
        }
        .sheet(item: $activeKnowledgePoint) { point in
            NavigationStack {
                KnowledgePointDetailView(point: point) { anchor in
                    openRelatedAnchor(anchor)
                }
                .environmentObject(viewModel)
            }
        }
        .sheet(item: $activeRelatedSentence) { sentence in
            SentenceExplainDetailSheet(document: document, sentence: sentence)
                .environmentObject(viewModel)
                .presentationDetents([.large])
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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.86))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.96), lineWidth: 1)
                )
        )
    }

    private func wordActionBar(layout: AdaptiveSheetLayout) -> some View {
        VStack(spacing: 12) {
            if let actionNote {
                SheetActionStatus(text: actionNote)
            }

            HStack(spacing: 12) {
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
        .frame(maxWidth: layout.actionBarWidth, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, layout.usesPadPresentation ? 16 : 18)
        .background(actionBarBackground(layout: layout))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, layout.usesPadPresentation ? 24 : 0)
        .padding(.bottom, layout.usesPadPresentation ? 10 : 0)
    }

    private var relatedWordContextPanel: some View {
        RelatedContextPanel(
            context: learningContext,
            onOpenNote: { note in
                activeRelatedNote = note
            },
            onOpenKnowledgePoint: { point in
                activeKnowledgePoint = point
            },
            onOpenSourceAnchor: { anchor in
                openRelatedAnchor(anchor)
            },
            onOpenCard: { item in
                if let anchor = item.sourceAnchor {
                    openRelatedAnchor(anchor)
                } else {
                    actionNote = "当前卡片暂时没有更精确的来源锚点。"
                }
            }
        )
    }

    private func openRelatedAnchor(_ anchor: SourceAnchor) {
        if let sentence = viewModel.sentence(for: anchor) {
            activeRelatedSentence = sentence
        } else if let fallback = entry.sourceSentence {
            activeRelatedSentence = fallback
        } else {
            actionNote = "该来源暂时无法直接定位到句子。"
        }
    }
}

struct SentenceFocusCard: View {
    let anchorLabel: String
    let text: String
    var highlightTokens: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                sectionMarker(text: "目标句子", tone: .sentence)

                Spacer(minLength: 10)

                Text(anchorLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ExplainHighlightTone.sentence.accent.opacity(0.92))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(ExplainHighlightTone.sentence.softFill)
                    )
            }

            if !highlightTokens.isEmpty {
                HighlightTokenRow(tokens: highlightTokens, tone: .sentence, compact: true)
            }

            ExpandableText(
                text: text,
                font: .system(size: 20, weight: .bold),
                foregroundColor: Color.black.opacity(0.82),
                collapsedLineLimit: 5
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            ExplainHighlightTone.sentence.softFill,
                            Color.white.opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(ExplainHighlightTone.sentence.stroke, lineWidth: 1)
                )
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(ExplainHighlightTone.sentence.accent.opacity(0.4))
                .frame(width: 4)
                .padding(.vertical, 16)
                .padding(.leading, 10)
        }
    }
}

struct SentenceExplainBlock: View {
    let title: String
    let content: String
    var tone: ExplainHighlightTone = .neutral
    var highlightTokens: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionMarker(text: title, tone: tone)

            if !highlightTokens.isEmpty {
                HighlightTokenRow(tokens: highlightTokens, tone: tone)
            }

            Text(content)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.68))
                .lineSpacing(4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tone.softFill, Color.white.opacity(0.84)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(tone.stroke, lineWidth: 1)
                )
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(tone.accent.opacity(0.35))
                .frame(width: 4)
                .padding(.vertical, 14)
                .padding(.leading, 10)
        }
    }
}

struct SentenceExplainListBlock: View {
    let title: String
    let items: [String]
    var tone: ExplainHighlightTone = .neutral

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionMarker(text: title, tone: tone)

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let parsed = parseExplainListItem(item)

                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(tone.accent.opacity(0.8))
                        .frame(width: 8, height: 8)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 8) {
                        if let head = parsed.head {
                            Text(head)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(tone.accent.opacity(0.96))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(tone.softFill)
                                )
                        }

                        Text(parsed.body)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.68))
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tone.softFill, Color.white.opacity(0.84)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(tone.stroke, lineWidth: 1)
                )
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(tone.accent.opacity(0.35))
                .frame(width: 4)
                .padding(.vertical, 14)
                .padding(.leading, 10)
        }
    }
}

struct InteractiveKeywordSection: View {
    let title: String
    var minimumItemWidth: CGFloat = 120
    var selectedTerm: String? = nil
    let keywords: [OutlineNodeKeyword]
    let onTap: (OutlineNodeKeyword) -> Void

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: minimumItemWidth), spacing: 10)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.78))

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(keywords) { keyword in
                    let isSelected = normalizedKeywordLookupKey(keyword.term) == normalizedKeywordLookupKey(selectedTerm)
                    Button {
                        onTap(keyword)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text(keyword.term)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(isSelected ? Color.white : Color.blue.opacity(0.82))

                                Spacer(minLength: 8)

                                Image(systemName: "chevron.right.circle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.blue.opacity(0.62))
                            }

                            Text(keyword.hint)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.black.opacity(0.54))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    isSelected
                                    ? LinearGradient(
                                        colors: [Color.blue.opacity(0.84), Color.cyan.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        colors: [Color.blue.opacity(0.08), Color.white.opacity(0.84)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(isSelected ? Color.blue.opacity(0.42) : Color.blue.opacity(0.14), lineWidth: isSelected ? 1.4 : 1)
                                )
                        )
                        .shadow(color: isSelected ? Color.blue.opacity(0.18) : .clear, radius: 12, y: 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private func normalizedKeywordLookupKey(_ value: String?) -> String {
    guard let value else { return "" }
    let trimmed = value
        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        .lowercased()

    guard !trimmed.isEmpty else { return "" }
    if trimmed.count > 3, trimmed.hasSuffix("s") {
        return String(trimmed.dropLast())
    }
    return trimmed
}

struct AdaptiveSheetLayout {
    let width: CGFloat

    var usesPadPresentation: Bool {
        width >= 820
    }

    var prefersUtilitySplit: Bool {
        width >= 940
    }

    var prefersTwoColumnCards: Bool {
        width >= 980
    }

    var contentWidth: CGFloat {
        usesPadPresentation ? min(width - 88, 920) : width
    }

    var horizontalPadding: CGFloat {
        usesPadPresentation ? max((width - contentWidth) / 2, 28) : 24
    }

    var actionBarWidth: CGFloat {
        usesPadPresentation ? min(contentWidth, 760) : contentWidth
    }

    var keywordMinimumWidth: CGFloat {
        usesPadPresentation ? 176 : 120
    }
}

@ViewBuilder
func actionBarBackground(layout: AdaptiveSheetLayout) -> some View {
    if layout.usesPadPresentation {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color.white.opacity(0.94))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.98), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 24, y: 10)
    } else {
        Rectangle()
            .fill(Color.white.opacity(0.9))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.96))
                    .frame(height: 1)
            }
    }
}

struct ExpandableText: View {
    let text: String
    let font: Font
    let foregroundColor: Color
    let collapsedLineLimit: Int

    @State private var isExpanded = false

    private var canExpand: Bool {
        text.count > 90 || text.contains("\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(font)
                .foregroundStyle(foregroundColor)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .lineLimit(isExpanded ? nil : collapsedLineLimit)

            if canExpand {
                Button(isExpanded ? "收起" : "展开全文") {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        isExpanded.toggle()
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.blue.opacity(0.78))
            }
        }
    }
}

struct BreadcrumbPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.blue.opacity(0.82))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.82))
            )
    }
}

struct HighlightTokenRow: View {
    let tokens: [String]
    let tone: ExplainHighlightTone
    var compact: Bool = false

    private var deduplicatedTokens: [String] {
        var seen = Set<String>()
        return tokens.compactMap { raw in
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return nil }
            let key = token.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return token
        }
    }

    private var displayTokens: [String] {
        Array(deduplicatedTokens.prefix(compact ? 4 : 6))
    }

    private var hiddenCount: Int {
        max(deduplicatedTokens.count - displayTokens.count, 0)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(displayTokens, id: \.self) { token in
                    Text(token)
                        .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(tone.accent.opacity(0.94))
                        .padding(.horizontal, compact ? 9 : 10)
                        .padding(.vertical, compact ? 5 : 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(tone.softFill)
                        )
                }

                if hiddenCount > 0 {
                    Text("+\(hiddenCount)")
                        .font(.system(size: compact ? 11 : 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.45))
                }
            }
        }
    }
}

private struct ContextSentenceCard: View {
    let sentence: Sentence
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(sentence.anchorLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isCurrent ? Color.blue.opacity(0.82) : Color.black.opacity(0.46))

                Text(sentence.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.72))
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isCurrent ? Color.blue.opacity(0.12) : Color.white.opacity(0.78))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isCurrent ? Color.blue.opacity(0.28) : Color.white.opacity(0.92), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct SheetActionStatus: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.blue.opacity(0.78))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@ViewBuilder
private func sectionMarker(text: String, tone: ExplainHighlightTone) -> some View {
    HStack(spacing: 8) {
        Circle()
            .fill(tone.accent.opacity(0.9))
            .frame(width: 8, height: 8)

        Text(text)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.8))
    }
}

private func parseExplainListItem(_ item: String) -> (head: String?, body: String) {
    if let range = item.range(of: "：") {
        let head = String(item[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let body = String(item[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (head.isEmpty ? nil : head, body.isEmpty ? item : body)
    }

    if let range = item.range(of: ":") {
        let head = String(item[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let body = String(item[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (head.isEmpty ? nil : head, body.isEmpty ? item : body)
    }

    return (nil, item)
}

struct ProfessorTeachingStatusSnapshot: Equatable {
    let documentTitle: String
    let currentSentenceAnchor: String
    let currentSentenceFunction: String
    let currentParagraphRole: String
    let currentTeachingFocus: String
    let currentMode: String
}

struct ProfessorTeachingStatusHeader: View {
    let snapshot: ProfessorTeachingStatusSnapshot
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("教学状态")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.45))
                        .tracking(0.8)
                    Text(snapshot.documentTitle)
                        .font(compact ? .system(size: 14, weight: .semibold, design: .serif) : .system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.black.opacity(0.62))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                statusChip(text: snapshot.currentMode, tone: .node)
            }

            statusRow(
                label: "当前锚点",
                primaryChip: (snapshot.currentSentenceAnchor, .sentence),
                secondaryChip: (snapshot.currentParagraphRole, .structure)
            )

            statusField(
                label: "当前句定位",
                content: snapshot.currentSentenceFunction,
                tone: .node
            )

            statusField(
                label: "当前教学焦点",
                content: snapshot.currentTeachingFocus,
                tone: .teaching
            )
        }
        .padding(compact ? 14 : 18)
        .background(
            RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous)
                .fill(Color.white.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func statusChip(text: String, tone: ExplainHighlightTone) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(tone.accent.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tone.softFill)
            )
    }

    @ViewBuilder
    private func statusRow(
        label: String,
        primaryChip: (String, ExplainHighlightTone),
        secondaryChip: (String, ExplainHighlightTone)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.42))
                .tracking(0.5)

            if compact {
                VStack(alignment: .leading, spacing: 8) {
                    statusChip(text: primaryChip.0, tone: primaryChip.1)
                    if let secondaryChip {
                        statusChip(text: secondaryChip.0, tone: secondaryChip.1)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    statusChip(text: primaryChip.0, tone: primaryChip.1)
                    if let secondaryChip {
                        statusChip(text: secondaryChip.0, tone: secondaryChip.1)
                    }
                }
            }
        }
    }

    private func statusField(label: String, content: String, tone: ExplainHighlightTone) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.42))
                .tracking(0.5)

            Text(content)
                .font(compact ? .system(size: 14, weight: .semibold) : .system(size: 16, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.78))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tone.softFill)
                )
        }
    }
}

struct ProfessorAnalysisPanel: View {
    let analysis: ProfessorSentenceAnalysis
    var keywordMinimumWidth: CGFloat = 120
    var selectedTerm: String? = nil
    var relatedEvidenceItems: [String] = []
    let onWordTap: (OutlineNodeKeyword) -> Void

    @State private var showsRewriteMeaning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let sentenceFunction = analysis.renderedSentenceFunction.nonEmpty {
                SentenceExplainBlock(
                    title: "句子定位",
                    content: sentenceFunction,
                    tone: .node
                )
            }

            StructuredCoreSkeletonCard(analysis: analysis)

            StructuredChunkLayerCard(analysis: analysis)

            SentenceExplainListBlock(
                title: "关键语法点",
                items: analysis.renderedGrammarFocus,
                tone: .grammar
            )

            SentenceExplainListBlock(
                title: "学生易错点",
                items: analysis.renderedMisreadingTraps,
                tone: .misread
            )

            SentenceExplainListBlock(
                title: "出题改写点",
                items: analysis.renderedExamParaphraseRoutes,
                tone: .rewrite
            )

            if let faithfulTranslation = analysis.renderedFaithfulTranslation.nonEmpty {
                SentenceExplainBlock(
                    title: "忠实翻译",
                    content: faithfulTranslation,
                    tone: .translation,
                    highlightTokens: analysis.vocabularyInContext.map(\.term)
                )
            }

            if let teachingInterpretation = analysis.renderedTeachingInterpretation.nonEmpty {
                SentenceExplainBlock(
                    title: "教学解读",
                    content: teachingInterpretation,
                    tone: .teaching
                )
            }

            if analysis.renderedSimplerRewrite.nonEmpty != nil {
                RewriteCardWithTranslationToggle(
                    rewrite: analysis.renderedSimplerRewrite,
                    explanation: analysis.renderedSimplerRewriteTranslation,
                    highlightTokens: analysis.vocabularyInContext.map(\.term),
                    showsExplanation: $showsRewriteMeaning
                )
            }

            if let miniExercise = analysis.renderedMiniCheck?.nonEmpty {
                SentenceExplainBlock(
                    title: "微练习",
                    content: miniExercise,
                    tone: .grammar
                )
            }

            if !analysis.vocabularyInContext.isEmpty {
                InteractiveKeywordSection(
                    title: "词汇在句中义",
                    minimumItemWidth: keywordMinimumWidth,
                    selectedTerm: selectedTerm,
                    keywords: analysis.vocabularyInContext.map {
                        OutlineNodeKeyword(
                            id: $0.term.lowercased(),
                            term: $0.term,
                            hint: $0.meaning
                        )
                    },
                    onTap: onWordTap
                )
            }

            if !relatedEvidenceItems.isEmpty {
                SentenceExplainListBlock(
                    title: "相关知识点 / 题目证据",
                    items: relatedEvidenceItems,
                    tone: .node
                )
            }
        }
    }
}

private struct StructuredCoreSkeletonCard: View {
    let analysis: ProfessorSentenceAnalysis

    private var skeleton: ProfessorCoreSkeleton {
        analysis.displayedCoreSkeleton
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionMarker(text: "句子主干", tone: .structure)

            VStack(spacing: 10) {
                skeletonRow(label: "主语", content: skeleton.subject, tone: .structure)
                skeletonRow(label: "谓语", content: skeleton.predicate, tone: .grammar)
                skeletonRow(label: "核心补足", content: skeleton.complementOrObject, tone: .sentence)
            }
        }
    }

    private func skeletonRow(label: String, content: String, tone: ExplainHighlightTone) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(tone.accent.opacity(0.9))
                .frame(width: 68, alignment: .leading)

            Text(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "当前结果里没有单独提取这一栏。" : content)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.78))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tone.softFill)
        )
    }
}

private struct StructuredChunkLayerCard: View {
    let analysis: ProfessorSentenceAnalysis

    private var layers: [ProfessorChunkLayerDisplayItem] {
        analysis.displayedChunkLayers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionMarker(text: "语块切分", tone: .sentence)

            ForEach(Array(layers.enumerated()), id: \.offset) { index, layer in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        Text("第\(index + 1)块")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.42))

                        Text(layer.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "语块" : layer.role)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(ExplainHighlightTone.sentence.accent.opacity(0.9))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(ExplainHighlightTone.sentence.softFill)
                            )
                    }

                    Text(layer.text)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.8))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    if let attaches = layer.attachesTo.nonEmpty {
                        chunkMetaRow(label: "挂接对象", value: attaches)
                    }

                    if let gloss = layer.gloss.nonEmpty {
                        chunkMetaRow(label: "这一块在干什么", value: gloss)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.78))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(ExplainHighlightTone.sentence.accent.opacity(0.12), lineWidth: 1)
                        )
                )
            }
        }
    }

    private func chunkMetaRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.42))
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.64))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct RewriteCardWithTranslationToggle: View {
    let rewrite: String
    let explanation: String
    let highlightTokens: [String]
    @Binding var showsExplanation: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                sectionMarker(text: "英文简化改写", tone: .rewrite)
                Spacer(minLength: 0)
                if explanation.nonEmpty != nil {
                    Button(showsExplanation ? "隐藏译意" : "显示译意") {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                            showsExplanation.toggle()
                        }
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .buttonStyle(.plain)
                    .foregroundStyle(ExplainHighlightTone.rewrite.accent.opacity(0.9))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                if !highlightTokens.isEmpty {
                    HighlightTokenRow(tokens: highlightTokens, tone: .rewrite)
                }

                Text(rewrite)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.68))
                    .lineSpacing(4)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [ExplainHighlightTone.rewrite.softFill, Color.white.opacity(0.84)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(ExplainHighlightTone.rewrite.stroke, lineWidth: 1)
                    )
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(ExplainHighlightTone.rewrite.accent.opacity(0.35))
                    .frame(width: 4)
                    .padding(.vertical, 14)
                    .padding(.leading, 10)
            }

            if showsExplanation, let visibleExplanation = explanation.nonEmpty {
                SentenceExplainBlock(
                    title: "改写译意",
                    content: visibleExplanation,
                    tone: .translation
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
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
