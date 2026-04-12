import SwiftUI

struct ArchivistWorkspaceView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    let document: SourceDocument
    let bundle: StructuredSourceBundle
    let onClose: () -> Void

    @StateObject private var workspaceViewModel: ArchivistWorkspaceViewModel
    @State private var selectedTool: ArchivistTool = .pen
    @State private var selectedWord: WordExplanationEntry?

    init(document: SourceDocument, bundle: StructuredSourceBundle, onClose: @escaping () -> Void) {
        self.document = document
        self.bundle = bundle
        self.onClose = onClose
        _workspaceViewModel = StateObject(wrappedValue: ArchivistWorkspaceViewModel(document: document, bundle: bundle))
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = ArchivistWorkspaceLayout(width: proxy.size.width, height: proxy.size.height)

            ZStack {
                ArchivistDeskBackground()

                VStack(spacing: 0) {
                    ArchivistTopToolbar(
                        documentTitle: document.title,
                        selectedTool: $selectedTool,
                        onClose: onClose
                    )
                    .padding(.horizontal, layout.outerPadding)
                    .padding(.top, 18)

                    HStack(alignment: .top, spacing: layout.contentGap) {
                        ArchivistSideRail()
                            .frame(width: layout.sideRailWidth)
                            .padding(.top, 18)

                        EditorialPaperCanvas(
                            document: document,
                            bundle: bundle,
                            headerTags: workspaceViewModel.headerTags,
                            selectedSentenceID: workspaceViewModel.selectedSentenceID,
                            onSentenceTap: { workspaceViewModel.selectSentence($0) }
                        ) {
                            ArchivistContextAssistant(
                                node: workspaceViewModel.selectedNode,
                                sentence: workspaceViewModel.selectedSentence,
                                result: workspaceViewModel.analysisResult,
                                isLoading: workspaceViewModel.isLoadingAnalysis,
                                errorMessage: workspaceViewModel.analysisError,
                                onWordTap: { keyword in
                                    guard let sentence = workspaceViewModel.selectedSentence else { return }
                                    selectedWord = appViewModel.wordExplanation(
                                        for: keyword.term,
                                        meaningHint: keyword.meaning,
                                        sentence: sentence,
                                        in: document
                                    )
                                }
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)

                        ArchivistFloatingNavigator(
                            nodes: bundle.outline,
                            selectedNodeID: workspaceViewModel.selectedNodeID,
                            currentAnchorLabel: workspaceViewModel.anchorLabel(for: workspaceViewModel.selectedNode),
                            onNodeTap: { workspaceViewModel.selectNode($0) }
                        )
                        .frame(width: layout.navigatorWidth)
                        .padding(.top, 22)
                    }
                    .padding(.horizontal, layout.outerPadding)

                    Spacer(minLength: 10)

                    ArchivistFooterStrip(
                        pageText: workspaceViewModel.selectedSentence?.anchorLabel ?? "Page 1",
                        masteryText: "Structured Source",
                        helperText: "Digital Archivist"
                    )
                    .padding(.horizontal, layout.outerPadding)
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom, 14))
                }

                // Debug 解析来源徽标（左下角）
                #if DEBUG
                VStack {
                    Spacer()
                    HStack {
                        ParseSourceDebugBadge(
                            info: appViewModel.parseSessionInfo(for: document),
                            stage: appViewModel.structuredSourceStage(for: document),
                            error: appViewModel.structuredSourceError(for: document)
                        )
                        .padding(.leading, layout.outerPadding)
                        .padding(.bottom, max(proxy.safeAreaInsets.bottom, 14) + 36)
                        Spacer()
                    }
                }
                #endif
            }
        }
        .background(ArchivistColors.deskBackground)
        .task(id: workspaceViewModel.selectedSentenceID) {
            await workspaceViewModel.loadAnalysis(using: appViewModel)
        }
        .sheet(item: $selectedWord) { entry in
            WordExplainDetailSheet(document: document, entry: entry)
                .environmentObject(appViewModel)
                .presentationDetents([.medium, .large])
        }
    }
}

private enum ArchivistTool: String, CaseIterable, Identifiable {
    case pen = "Pen"
    case highlighter = "Highlighter"
    case eraser = "Eraser"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        }
    }
}

private struct ArchivistWorkspaceLayout {
    let width: CGFloat
    let height: CGFloat

    var outerPadding: CGFloat { width > 1360 ? 28 : 22 }
    var sideRailWidth: CGFloat { 196 }
    var navigatorWidth: CGFloat { min(232, width * 0.18) }
    var contentGap: CGFloat { width > 1400 ? 26 : 18 }
}

private struct ArchivistDeskBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [ArchivistColors.deskLift, ArchivistColors.deskBackground],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            NotebookGrid(spacing: 26)
                .opacity(0.04)
        }
        .ignoresSafeArea()
    }
}

private struct ArchivistTopToolbar: View {
    let documentTitle: String
    @Binding var selectedTool: ArchivistTool
    let onClose: () -> Void

    var body: some View {
        ZStack {
            HStack {
                Text("Digital Archivist")
                    .font(.system(size: 24, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(ArchivistColors.primaryInk)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(documentTitle)
                        .font(ArchivistTypography.label)
                        .foregroundStyle(ArchivistColors.primaryInk)
                        .lineLimit(1)
                    Text("Academic Workspace")
                        .font(ArchivistTypography.annotationSmall)
                        .foregroundStyle(ArchivistColors.softInk)
                }

                HStack(spacing: 8) {
                    ToolbarCircleButton(icon: "gearshape")
                    ToolbarCircleButton(icon: "square.and.arrow.up")
                    ToolbarCircleButton(icon: "ellipsis")
                    ToolbarCircleButton(icon: "xmark", action: onClose)
                }
            }

            HStack(spacing: 6) {
                ForEach(ArchivistTool.allCases) { tool in
                    Button {
                        selectedTool = tool
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tool.icon)
                                .font(.system(size: 16, weight: .semibold))
                            Text(tool.rawValue.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(0.8)
                        }
                        .foregroundStyle(selectedTool == tool ? ArchivistColors.primaryInk : ArchivistColors.softInk)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selectedTool == tool ? ArchivistColors.blueWash.opacity(0.6) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    Circle().fill(ArchivistColors.mutedInk).frame(width: 10, height: 10)
                    Circle().fill(ArchivistColors.primaryInk).frame(width: 10, height: 10)
                    Circle().fill(Color(red: 180 / 255, green: 59 / 255, blue: 47 / 255)).frame(width: 10, height: 10)
                }
                .padding(.leading, 10)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .archivistFloatingShadow()
        }
    }
}

private struct ToolbarCircleButton: View {
    let icon: String
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ArchivistColors.softInk)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct ArchivistSideRail: View {
    private let items: [(String, String)] = [
        ("Structure", "square.grid.2x2"),
        ("Mind Map", "point.3.connected.trianglepath.dotted"),
        ("Archive", "archivebox"),
        ("Tags", "tag")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Circle()
                    .fill(ArchivistColors.blueWash.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "person.crop.square")
                            .foregroundStyle(ArchivistColors.primaryInk)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Research Library")
                        .font(ArchivistTypography.label)
                        .foregroundStyle(ArchivistColors.primaryInk)
                    Text("Ph.D. Candidate")
                        .font(ArchivistTypography.annotationSmall)
                        .foregroundStyle(ArchivistColors.softInk)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.0) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.1)
                            .font(.system(size: 15, weight: .semibold))
                        Text(item.0)
                            .font(ArchivistTypography.annotation)
                    }
                    .foregroundStyle(item.0 == "Structure" ? ArchivistColors.primaryInk : ArchivistColors.mutedInk.opacity(0.74))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(item.0 == "Structure" ? ArchivistColors.blueWash.opacity(0.45) : Color.clear)
                    )
                }
            }

            Spacer()

            Button {
            } label: {
                Text("New Document")
                    .font(ArchivistTypography.label)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(ArchivistColors.primaryInk)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .archivistFloatingShadow()
    }
}

private struct ArchivistFloatingNavigator: View {
    let nodes: [OutlineNode]
    let selectedNodeID: String?
    let currentAnchorLabel: String
    let onNodeTap: (OutlineNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Navigator")
                    .font(ArchivistTypography.label)
                    .foregroundStyle(ArchivistColors.softInk)
                Spacer()
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(ArchivistColors.primaryInk)
            }

            Text(currentAnchorLabel)
                .font(ArchivistTypography.annotationSmall)
                .foregroundStyle(ArchivistColors.softInk)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(nodes) { node in
                    NavigatorNodeRow(
                        node: node,
                        selectedNodeID: selectedNodeID,
                        onNodeTap: onNodeTap
                    )
                }
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .archivistFloatingShadow()
    }
}

private struct NavigatorNodeRow: View {
    let node: OutlineNode
    let selectedNodeID: String?
    let onNodeTap: (OutlineNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                onNodeTap(node)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(selectedNodeID == node.id ? ArchivistColors.primaryInk : ArchivistColors.navigatorDot.opacity(0.6))
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(node.title)
                            .font(.system(size: 13, weight: selectedNodeID == node.id ? .bold : .semibold, design: .serif))
                            .foregroundStyle(ArchivistColors.mutedInk)
                            .lineLimit(2)

                        Text(node.anchor.label)
                            .font(ArchivistTypography.annotationSmall)
                            .foregroundStyle(ArchivistColors.softInk)
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if !node.children.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(node.children) { child in
                        NavigatorNodeRow(node: child, selectedNodeID: selectedNodeID, onNodeTap: onNodeTap)
                    }
                }
                .padding(.leading, 14)
            }
        }
    }
}

private struct ArchivistContextAssistant: View {
    let node: OutlineNode?
    let sentence: Sentence?
    let result: AIExplainSentenceResult?
    let isLoading: Bool
    let errorMessage: String?
    let onWordTap: (AIExplainSentenceResult.KeyTerm) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ArchivistSpacing.lg) {
            if let sentence {
                Text(sentence.anchorLabel)
                    .font(ArchivistTypography.annotationSmall)
                    .foregroundStyle(ArchivistColors.softInk)

                Text(sentence.text)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(ArchivistColors.mutedInk)
                    .lineSpacing(5)
            }

            if let node {
                ContextAnalysisCard(title: "Navigator", tapeColor: ArchivistColors.blueWash, offset: CGSize(width: -4, height: 0)) {
                    Text(node.title)
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .foregroundStyle(ArchivistColors.mutedInk)
                    Text(node.summary)
                        .font(ArchivistTypography.annotation)
                        .foregroundStyle(ArchivistColors.mutedInk.opacity(0.84))
                        .lineSpacing(4)
                }
            }

            if isLoading {
                ContextAnalysisCard(title: "Analysis", tapeColor: ArchivistColors.yellowWash, offset: CGSize(width: 6, height: -4)) {
                    ProgressView("Loading contextual analysis…")
                        .font(ArchivistTypography.annotation)
                        .tint(ArchivistColors.primaryInk)
                }
            } else if let errorMessage {
                ContextAnalysisCard(title: "Analysis", tapeColor: ArchivistColors.pinkWash, offset: CGSize(width: 8, height: -6)) {
                    Text(errorMessage)
                        .font(ArchivistTypography.annotation)
                        .foregroundStyle(ArchivistColors.mutedInk)
                }
            } else if let result {
                let sentenceFunction = result.renderedSentenceFunction.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentenceFunction.isEmpty {
                    ContextAnalysisCard(title: "句子定位", tapeColor: ArchivistColors.greenWash, offset: CGSize(width: 0, height: 0)) {
                        Text(sentenceFunction)
                            .font(ArchivistTypography.annotation)
                            .foregroundStyle(ArchivistColors.mutedInk)
                            .lineSpacing(4)
                    }
                }

                ContextAnalysisCard(title: "句子主干", tapeColor: ArchivistColors.blueWash, offset: CGSize(width: 10, height: -6)) {
                    Text(result.renderedSentenceCore)
                        .font(ArchivistTypography.annotation)
                        .foregroundStyle(ArchivistColors.mutedInk)
                        .lineSpacing(4)
                }

                if let misread = result.renderedMisreadingTraps.first {
                    ContextAnalysisCard(title: "学生易错点", tapeColor: ArchivistColors.pinkWash, offset: CGSize(width: 6, height: -2)) {
                        Text(misread)
                            .font(ArchivistTypography.annotation)
                            .foregroundStyle(ArchivistColors.mutedInk)
                            .lineSpacing(4)
                    }
                }

                if let rewrite = result.renderedExamParaphraseRoutes.first {
                    ContextAnalysisCard(title: "出题改写点", tapeColor: ArchivistColors.yellowWash, offset: CGSize(width: -8, height: -4)) {
                        Text(rewrite)
                            .font(ArchivistTypography.annotation)
                            .foregroundStyle(ArchivistColors.mutedInk)
                            .lineSpacing(4)
                    }
                }

                if !result.keyTerms.isEmpty {
                    ContextAnalysisCard(title: "词汇在句中义", tapeColor: ArchivistColors.yellowWash, offset: CGSize(width: -8, height: -4)) {
                        FlexibleVocabFlow(terms: result.keyTerms, onTap: onWordTap)
                    }
                }
            }
        }
    }
}

private struct FlexibleVocabFlow: View {
    let terms: [AIExplainSentenceResult.KeyTerm]
    let onTap: (AIExplainSentenceResult.KeyTerm) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(terms, id: \.term) { term in
                Button {
                    onTap(term)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(term.term)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text(term.meaning)
                            .font(ArchivistTypography.annotationSmall)
                            .lineLimit(2)
                    }
                    .foregroundStyle(ArchivistColors.primaryInk)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(ArchivistColors.paperCanvas.opacity(0.7))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ArchivistFooterStrip: View {
    let pageText: String
    let masteryText: String
    let helperText: String

    var body: some View {
        HStack {
            Text(masteryText.uppercased())
                .font(ArchivistTypography.annotationSmall)
                .foregroundStyle(ArchivistColors.tertiaryLabel)

            Spacer()

            Text(pageText)
                .font(ArchivistTypography.annotationSmall)
                .foregroundStyle(ArchivistColors.softInk)

            Spacer()

            Text(helperText.uppercased())
                .font(ArchivistTypography.annotationSmall)
                .foregroundStyle(ArchivistColors.softInk)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
    }
}

private extension ArchivistColors {
    static let tertiaryLabel = Color(red: 89 / 255, green: 97 / 255, blue: 0 / 255)
}
