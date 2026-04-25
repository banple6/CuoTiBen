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
    @State private var activeExplanationRequestID: String?

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

    private var bundledAnalysis: ProfessorSentenceAnalysis? {
        viewModel.professorSentenceCard(for: activeSentence, in: document)?.analysis
    }

    private var effectiveAnalysis: ProfessorSentenceAnalysis? {
        let bundled = bundledAnalysis
        if let remote = visibleResult?.localFallbackAnalysis {
            return remote.mergingFallback(bundled)
        }
        return bundled
    }

    private var selectionState: SourceSelectionState {
        viewModel.sourceSelectionState(for: activeSentence, in: document)
    }

    private var visibleResult: AIExplainSentenceResult? {
        guard let result, isResultVisible(result, for: activeSentence) else {
            return nil
        }
        return result
    }

    private var shouldAutoLoadRemoteExplanation: Bool {
        guard !isLoading, result == nil else { return false }
        guard selectionState.allowsCloudSentenceExplain else { return false }
        guard let bundled = bundledAnalysis else { return true }
        return bundled.shouldPreferSentenceExplain(for: activeSentence.text)
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
        .onChange(of: activeSentence.id) { _ in
            actionNote = nil
            explanationTask?.cancel()
            explanationTask = nil
            result = nil
            errorMessage = nil
            isLoading = false
            activeExplanationRequestID = nil
            maybeAutoLoadExplanation()
        }
        .onAppear {
            maybeAutoLoadExplanation()
        }
        .onDisappear {
            explanationTask?.cancel()
            explanationTask = nil
            activeExplanationRequestID = nil
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
        let currentSelection = selectionState
        if !currentSelection.allowsCloudSentenceExplain {
            VStack(alignment: .leading, spacing: 16) {
                SentenceExplainBlock(
                    title: "本地骨架",
                    content: "当前展示的是本地结构骨架，远端 AI 精讲尚未成功获取。",
                    tone: .neutral
                )
                SourceSelectionSkeletonPanel(selectionState: currentSelection)
                relatedContextPanel
            }
        } else if let analysis = effectiveAnalysis {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading {
                    ProgressView("正在获取教授式精讲…")
                        .font(.system(size: 14, weight: .medium))
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

                if !isLoading, result == nil {
                    remoteExplanationButton(title: "重新获取 AI 精讲")
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
            await loadExplanation(for: sentence, forceRefresh: force)
        }
    }

    private func loadExplanation(
        for sentence: Sentence,
        forceRefresh: Bool
    ) async {
        let context = viewModel.explainSentenceContext(for: sentence, in: document)
        await MainActor.run {
            guard activeSentence.id == sentence.id else { return }
            isLoading = true
            errorMessage = nil
            result = nil
            activeExplanationRequestID = nil
        }

        guard let requestIdentity = viewModel.explainSentenceRequestIdentity(for: sentence, in: document) else {
            _ = try? ExplainSentenceRequestBuilder.prepare(context: context, requestIdentity: nil)
            let fallback = LocalSentenceFallbackBuilder.build(
                context: context,
                requestIdentity: nil,
                structuredError: AIStructuredError.invalidRequest(message: "缺少 sentence identity 字段。")
            )
            await MainActor.run {
                guard activeSentence.id == sentence.id else { return }
                result = fallback
                errorMessage = fallback.displayFallbackMessage
                isLoading = false
                activeExplanationRequestID = nil
            }
            return
        }

        await MainActor.run {
            guard activeSentence.id == sentence.id else { return }
            activeExplanationRequestID = requestIdentity.clientRequestID
        }

        do {
            let fetched = try await AIExplainSentenceService.fetchExplanationWithCache(
                for: context,
                requestIdentity: requestIdentity,
                forceRefresh: forceRefresh
            )
            try Task.checkCancellation()

            guard isResultVisible(fetched, for: sentence) else {
                TextPipelineDiagnostics.log(
                    "AI",
                    "[AI][SentenceExplain] discard stale result request_id=\(requestIdentity.clientRequestID) sentence_id=\(requestIdentity.sentenceID)",
                    severity: .warning
                )
                await MainActor.run {
                    guard activeSentence.id == sentence.id else { return }
                    guard activeExplanationRequestID == requestIdentity.clientRequestID else { return }
                    isLoading = false
                }
                return
            }

            await MainActor.run {
                guard activeSentence.id == sentence.id else { return }
                guard activeExplanationRequestID == requestIdentity.clientRequestID else {
                    TextPipelineDiagnostics.log(
                        "AI",
                        "[AI][SentenceExplain] discard stale request request_id=\(requestIdentity.clientRequestID) discard_reason=requestSuperseded",
                        severity: .warning
                    )
                    return
                }
                result = fetched
                errorMessage = fetched.shouldShowFallbackBanner ? fetched.displayFallbackMessage : nil
                isLoading = false
                activeExplanationRequestID = nil
            }
        } catch is CancellationError {
            await MainActor.run {
                guard activeSentence.id == sentence.id else { return }
                isLoading = false
                if activeExplanationRequestID == requestIdentity.clientRequestID {
                    activeExplanationRequestID = nil
                }
            }
        } catch {
            let fallback = LocalSentenceFallbackBuilder.build(
                context: context,
                requestIdentity: requestIdentity,
                structuredError: AIStructuredError.invalidModelResponse(message: error.localizedDescription)
            )
            await MainActor.run {
                guard activeSentence.id == sentence.id else { return }
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
        ).isAllowed && AnalysisConsistencyGuard.warnings(
            expectedIdentity: expectedIdentity,
            sentenceText: sentence.text,
            analysis: result
        ).isEmpty
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

    private var displayedSentenceFunction: String {
        conciseTeachingHeaderText(snapshot.currentSentenceFunction, maxLength: compact ? 54 : 92)
    }

    private var displayedTeachingFocus: String {
        conciseTeachingHeaderText(snapshot.currentTeachingFocus, maxLength: compact ? 42 : 68)
    }

    private var displayedSentenceAnchor: String {
        conciseTeachingHeaderChip(snapshot.currentSentenceAnchor, fallback: "等待定位")
    }

    private var displayedParagraphRole: String {
        conciseTeachingHeaderChip(snapshot.currentParagraphRole, fallback: "段落角色待识别")
    }

    private var usesSentenceLabels: Bool {
        snapshot.currentMode == "句子讲解"
    }

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
                primaryChip: (displayedSentenceAnchor, .sentence),
                secondaryChip: (displayedParagraphRole, .structure)
            )

            statusField(
                label: usesSentenceLabels ? "当前句定位" : "当前节点说明",
                content: displayedSentenceFunction,
                tone: .node
            )

            statusField(
                label: usesSentenceLabels ? "当前教学焦点" : "当前结构焦点",
                content: displayedTeachingFocus,
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
            .lineLimit(1)
            .minimumScaleFactor(0.8)
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
                .lineLimit(compact ? 3 : 4)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tone.softFill)
                )
        }
    }
}

struct SourceSelectionSkeletonPanel: View {
    let selectionState: SourceSelectionState

    private var normalizedText: String {
        selectionState.text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var headingKeywords: [String] {
        let lowered = normalizedText.lowercased()
        let preferred = [
            "securing",
            "shared environment",
            "trust",
            "air",
            "algorithms"
        ].filter { lowered.contains($0) }

        if !preferred.isEmpty {
            return preferred
        }

        let stopwords: Set<String> = ["the", "and", "why", "now", "both", "on", "of", "a", "an", "to", "in"]
        return normalizedText
            .lowercased()
            .split { !$0.isLetter }
            .map(String.init)
            .filter { $0.count > 3 && !stopwords.contains($0) }
            .prefix(5)
            .map { $0 }
    }

    private var headingThemePrediction: String {
        let lowered = normalizedText.lowercased()
        if lowered.contains("air"),
           lowered.contains("algorithm"),
           lowered.contains("trust"),
           lowered.contains("shared environment") {
            return "文章可能讨论公共环境中的信任基础如何从现实空气质量扩展到算法信息环境。"
        }
        return "文章可能围绕标题中的关键词展开，说明它们之间的因果、并列或转折关系。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch selectionState.kind {
            case .heading:
                SentenceExplainBlock(
                    title: "标题解读",
                    content: "这是一句标题，不是正文句子，因此不会做句子主干解析。",
                    tone: .node
                )
                SentenceExplainBlock(
                    title: "标题含义",
                    content: normalizedText.isEmpty ? "当前标题文本为空，已保留标题结构骨架。" : headingThemePrediction,
                    tone: .translation
                )
                SentenceExplainBlock(
                    title: "主题预测",
                    content: headingThemePrediction,
                    tone: .teaching
                )
                SentenceExplainListBlock(
                    title: "关键词",
                    items: headingKeywords,
                    tone: .vocabulary
                )
                SentenceExplainListBlock(
                    title: "可能考点",
                    items: [
                        "标题中的核心名词可能对应全文主线。",
                        "并列对象之间的关系可能成为段落推进或主旨题线索。"
                    ],
                    tone: .rewrite
                )
                SentenceExplainListBlock(
                    title: "学习提示",
                    items: ["如果要做句子精讲，请选择正文段落中的完整英文句子。"],
                    tone: .teaching
                )
            case .question:
                SentenceExplainBlock(
                    title: "题目结构",
                    content: normalizedText.isEmpty ? "当前题干文本为空。" : normalizedText,
                    tone: .node
                )
                SentenceExplainListBlock(
                    title: "本地提示",
                    items: ["先识别题干问法，再回到正文定位证据。"],
                    tone: .teaching
                )
            case .option:
                SentenceExplainBlock(
                    title: "选项/答案块",
                    content: normalizedText.isEmpty ? "当前选项或答案区文本为空。" : normalizedText,
                    tone: .node
                )
                SentenceExplainListBlock(
                    title: "本地提示",
                    items: ["先判断该块是选项、答案线索还是解析说明，再与正文证据绑定。"],
                    tone: .teaching
                )
            case .vocabulary:
                SentenceExplainBlock(
                    title: "词汇讲义",
                    content: normalizedText.isEmpty ? "当前词汇块文本为空。" : normalizedText,
                    tone: .vocabulary
                )
                SentenceExplainListBlock(
                    title: "本地提示",
                    items: ["优先整理词义、搭配和例句，不进入句子主干精讲。"],
                    tone: .teaching
                )
            case .chineseInstruction:
                SentenceExplainBlock(
                    title: "学习提示",
                    content: normalizedText.isEmpty ? "当前中文说明为空。" : normalizedText,
                    tone: .teaching
                )
            case .bilingualNote:
                SentenceExplainBlock(
                    title: "双语注释结构",
                    content: normalizedText.isEmpty ? "当前双语注释为空。" : normalizedText,
                    tone: .translation
                )
                SentenceExplainListBlock(
                    title: "本地提示",
                    items: ["这类内容用于辅助理解，不直接进入句子精讲云请求。"],
                    tone: .teaching
                )
            case .passageParagraph:
                SentenceExplainBlock(
                    title: "段落结构",
                    content: normalizedText.isEmpty ? "当前段落文本为空。" : normalizedText,
                    tone: .node
                )
                SentenceExplainListBlock(
                    title: "本地提示",
                    items: ["段落应进入全文地图或段落结构分析，不直接进入单句精讲。"],
                    tone: .teaching
                )
            case .passageSentence:
                SentenceExplainBlock(
                    title: "句子结构",
                    content: normalizedText.isEmpty ? "当前句子文本为空。" : normalizedText,
                    tone: .node
                )
            case .unknown:
                SentenceExplainBlock(
                    title: "本地结构",
                    content: normalizedText.isEmpty ? "当前选中内容来源未知。" : normalizedText,
                    tone: .neutral
                )
                SentenceExplainListBlock(
                    title: "本地提示",
                    items: ["来源类型未确认前，只展示本地骨架，不请求云端句子精讲。"],
                    tone: .teaching
                )
            }
        }
    }
}

struct ProfessorAnalysisPanel: View {
    let analysis: ProfessorSentenceAnalysis
    var keywordMinimumWidth: CGFloat = 120
    var selectedTerm: String? = nil
    var relatedEvidenceItems: [String] = []
    let onWordTap: (OutlineNodeKeyword) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let sentenceFunction = conciseSentenceFunctionText(analysis.renderedSentenceFunction).nonEmpty {
                SentenceExplainBlock(
                    title: "句子定位",
                    content: sentenceFunction,
                    tone: .node
                )
            }

            StructuredCoreSkeletonCard(analysis: analysis)

            TranslationInterpretationGroup(
                analysis: analysis,
                highlightTokens: analysis.vocabularyInContext.map(\.term)
            )

            StructuredChunkLayerCard(analysis: analysis)

            GrammarFocusLocalizedSection(analysis: analysis)

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

            if analysis.renderedSimplerRewrite.nonEmpty != nil {
                RewriteCardSection(
                    rewrite: analysis.renderedSimplerRewrite,
                    rewriteExplanation: analysis.renderedSimplerRewriteTranslation.nonEmpty ?? "暂无改写译意。",
                    highlightTokens: analysis.vocabularyInContext.map(\.term)
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
                    title: "相关证据 / 知识点",
                    items: relatedEvidenceItems,
                    tone: .node
                )
            }
        }
    }
}

private struct TranslationInterpretationGroup: View {
    let analysis: ProfessorSentenceAnalysis
    let highlightTokens: [String]

    private var faithfulTranslationText: String {
        if let faithfulTranslation = analysis.renderedFaithfulTranslation.nonEmpty {
            return faithfulTranslation
        }
        return analysis.isAIGenerated ? "暂无忠实翻译" : "AI 翻译暂不可用，可稍后重试。"
    }

    private var teachingInterpretationText: String {
        analysis.renderedTeachingInterpretation.nonEmpty ?? "暂无教学解读"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SentenceExplainBlock(
                title: "忠实翻译",
                content: faithfulTranslationText,
                tone: .translation,
                highlightTokens: highlightTokens
            )

            SentenceExplainBlock(
                title: "教学解读",
                content: teachingInterpretationText,
                tone: .teaching
            )
        }
    }
}

private struct StructuredCoreSkeletonCard: View {
    let analysis: ProfessorSentenceAnalysis

    private var skeleton: ProfessorCoreSkeleton {
        analysis.displayedCoreSkeleton
    }

    private var hasStableSkeleton: Bool {
        analysis.displayedStableCoreSkeleton?.isMeaningful == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionMarker(text: "句子主干", tone: .structure)

            if hasStableSkeleton {
                VStack(spacing: 10) {
                    skeletonRow(label: "主语", content: skeleton.subject, tone: .structure)
                    skeletonRow(label: "谓语", content: skeleton.predicate, tone: .grammar)
                    skeletonRow(label: "核心补足", content: skeleton.complementOrObject, tone: .sentence)
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ExplainHighlightTone.structure.accent.opacity(0.85))

                    Text("当前结果里主干拆分不稳定，建议先看语块切分和教学解读。")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.7))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(ExplainHighlightTone.structure.softFill)
                )
            }
        }
    }

    private func skeletonRow(label: String, content: String, tone: ExplainHighlightTone) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(tone.accent.opacity(0.9))
                .frame(width: 68, alignment: .leading)

            Text(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? compactSkeletonPlaceholder(for: label) : content)
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

private struct GrammarFocusLocalizedSection: View {
    let analysis: ProfessorSentenceAnalysis

    private var items: [ProfessorGrammarFocusDisplayItem] {
        analysis.displayedGrammarFocusCards
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionMarker(text: "关键语法点", tone: .grammar)

                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 8) {
                            Text("第\(index + 1)点")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.42))

                            Text(item.title)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(ExplainHighlightTone.grammar.accent.opacity(0.92))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(ExplainHighlightTone.grammar.softFill)
                                )

                            if let tag = item.terminologyTag?.nonEmpty {
                                Text(tag)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.black.opacity(0.5))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color.black.opacity(0.05))
                                    )
                            }
                        }

                        grammarMetaRow(label: "这是什么", value: item.whatItIs)
                        grammarMetaRow(label: "在本句里", value: item.functionInSentence)
                        grammarMetaRow(label: "为什么重要", value: item.whyItMatters)

                        if let example = item.exampleEN?.nonEmpty {
                            grammarMetaRow(label: "原句线索", value: example, usesMonospace: true)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(ExplainHighlightTone.grammar.stroke, lineWidth: 1)
                            )
                    )
                }
            }
        }
    }

    private func grammarMetaRow(label: String, value: String, usesMonospace: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.42))

            Text(value)
                .font(usesMonospace ? .system(size: 13, weight: .medium, design: .monospaced) : .system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.68))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
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

private struct RewriteCardSection: View {
    let rewrite: String
    let rewriteExplanation: String
    let highlightTokens: [String]

    @State private var showsExplanation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionMarker(text: "英文简化改写", tone: .rewrite)

            VStack(alignment: .leading, spacing: 10) {
                Text("保留原意，只把句法压缩成更直接的表达。")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.48))

                if !highlightTokens.isEmpty {
                    HighlightTokenRow(tokens: highlightTokens, tone: .rewrite)
                }

                Text(rewrite)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.68))
                    .lineSpacing(4)

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        showsExplanation.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: showsExplanation ? "eye.slash" : "eye")
                            .font(.system(size: 12, weight: .bold))
                        Text(showsExplanation ? "隐藏译意" : "显示译意")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(ExplainHighlightTone.rewrite.accent.opacity(0.92))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.88))
                    )
                }
                .buttonStyle(.plain)

                if showsExplanation {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("改写译意")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.46))

                        Text(rewriteExplanation)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.7))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.84))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(ExplainHighlightTone.translation.stroke, lineWidth: 1)
                            )
                    )
                }
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
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private func conciseSentenceFunctionText(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    let firstSentence = trimmed
        .components(separatedBy: CharacterSet(charactersIn: "。！？\n"))
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty }) ?? trimmed

    if firstSentence.count <= 44 {
        return firstSentence
    }
    return String(firstSentence.prefix(43)) + "…"
}

private func compactSkeletonPlaceholder(for label: String) -> String {
    switch label {
    case "主语":
        return "主语未单独提取"
    case "谓语":
        return "谓语未单独提取"
    default:
        return "无明显单独补足"
    }
}

private func conciseTeachingHeaderChip(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return fallback }
    if trimmed.count <= 18 { return trimmed }
    return String(trimmed.prefix(18)) + "…"
}

private func conciseTeachingHeaderText(_ value: String, maxLength: Int) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "待补充" }

    let firstSentence = trimmed
        .components(separatedBy: CharacterSet(charactersIn: "。！？\n"))
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty }) ?? trimmed

    if firstSentence.count <= maxLength {
        return firstSentence
    }

    return String(firstSentence.prefix(maxLength)) + "…"
}
