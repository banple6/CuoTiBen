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
                            .frame(maxHeight: .infinity, alignment: .top)
                            .padding(.top, 18)

                        EditorialPaperCanvas(
                            document: document,
                            bundle: bundle,
                            headerSnapshot: workspaceViewModel.headerSnapshot,
                            selectedSentenceID: workspaceViewModel.selectedSentenceID,
                            onSentenceTap: { workspaceViewModel.selectSentence($0) }
                        ) {
                            ArchivistContextAssistant(
                                node: workspaceViewModel.selectedNode,
                                sentence: workspaceViewModel.selectedSentence,
                                analysis: workspaceViewModel.effectiveAnalysis,
                                isLoading: workspaceViewModel.isLoadingAnalysis,
                                errorMessage: workspaceViewModel.analysisError,
                                selectedTerm: selectedWord?.term,
                                relatedEvidenceItems: workspaceViewModel.relatedEvidenceItems,
                                onWordTap: { keyword in
                                    guard let sentence = workspaceViewModel.selectedSentence else { return }
                                    selectedWord = appViewModel.wordExplanation(
                                        for: keyword.term,
                                        meaningHint: keyword.hint,
                                        sentence: sentence,
                                        in: document
                                    )
                                }
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 12)

                        ArchivistFloatingNavigator(
                            nodes: bundle.outline,
                            selectedNodeID: workspaceViewModel.selectedNodeID,
                            currentAnchorLabel: workspaceViewModel.anchorLabel(for: workspaceViewModel.selectedNode),
                            onNodeTap: { workspaceViewModel.selectNode($0) }
                        )
                        .frame(width: layout.navigatorWidth)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 22)
                    }
                    .padding(.horizontal, layout.outerPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

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
    var navigatorWidth: CGFloat { min(320, width * 0.24) }
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
        ("Mind Map", "point.3.connected.trianglepath.dotted"),
        ("Structure", "square.grid.2x2"),
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
                    .foregroundStyle(item.0 == "Mind Map" ? ArchivistColors.primaryInk : ArchivistColors.mutedInk.opacity(0.74))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(item.0 == "Mind Map" ? ArchivistColors.blueWash.opacity(0.45) : Color.clear)
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
                Text("Mind Map")
                    .font(ArchivistTypography.label)
                    .foregroundStyle(ArchivistColors.softInk)
                Spacer()
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(ArchivistColors.primaryInk)
            }

            Text(currentAnchorLabel)
                .font(ArchivistTypography.annotationSmall)
                .foregroundStyle(ArchivistColors.softInk)

            if nodes.isEmpty {
                Text("当前还没有可展示的导图节点。")
                    .font(ArchivistTypography.annotation)
                    .foregroundStyle(ArchivistColors.softInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                StructureTreePreviewView(
                    nodes: nodes,
                    highlightedNodeID: selectedNodeID,
                    jumpTargetNodeID: selectedNodeID,
                    ancestorNodeIDs: [],
                    onNodeTap: onNodeTap,
                    onJumpHandled: {},
                    onClose: nil,
                    fillsAvailableHeight: true,
                    showsToolbar: false,
                    initialDensityMode: .compact
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .archivistFloatingShadow()
    }
}

private struct ArchivistContextAssistant: View {
    let node: OutlineNode?
    let sentence: Sentence?
    let analysis: ProfessorSentenceAnalysis?
    let isLoading: Bool
    let errorMessage: String?
    let selectedTerm: String?
    let relatedEvidenceItems: [String]
    let onWordTap: (OutlineNodeKeyword) -> Void

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
                ContextAnalysisCard(title: "当前教学节点", tapeColor: ArchivistColors.blueWash, offset: CGSize(width: -4, height: 0)) {
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
                ContextAnalysisCard(title: "教授式解析", tapeColor: ArchivistColors.yellowWash, offset: CGSize(width: 6, height: -4)) {
                    ProgressView("正在更新当前句的教授式解析…")
                        .font(ArchivistTypography.annotation)
                        .tint(ArchivistColors.primaryInk)
                }
            } else if let errorMessage {
                ContextAnalysisCard(title: "教授式解析", tapeColor: ArchivistColors.pinkWash, offset: CGSize(width: 8, height: -6)) {
                    Text(errorMessage)
                        .font(ArchivistTypography.annotation)
                        .foregroundStyle(ArchivistColors.mutedInk)
                }
            } else if let analysis {
                ContextAnalysisCard(title: "教授式解析", tapeColor: ArchivistColors.yellowWash, offset: CGSize(width: 6, height: -4)) {
                    ScrollView(showsIndicators: false) {
                        ProfessorAnalysisPanel(
                            analysis: analysis,
                            keywordMinimumWidth: 118,
                            selectedTerm: selectedTerm,
                            relatedEvidenceItems: relatedEvidenceItems,
                            onWordTap: onWordTap
                        )
                    }
                    .frame(maxHeight: 520)
                }
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
