import SwiftUI
import UIKit

struct NoteWorkspaceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appViewModel: AppViewModel

    let note: Note
    var onOpenSource: ((SourceAnchor) -> Void)? = nil

    @StateObject private var workspaceViewModel: NoteWorkspaceViewModel
    @State private var activeKnowledgePoint: KnowledgePoint?
    @State private var sourceJumpTarget: SourceJumpTarget?
    @State private var showsExitConfirm = false
    @State private var activeTool: WorkspaceEditorTool = .ink
    @State private var sidebarSelection: WorkspaceSidebarSection = .structure
    @State private var inkToolState = NoteInkToolState()
    @AppStorage("notes.workspace.appearance") private var appearanceRawValue = NoteWorkspaceAppearance.paper.rawValue
    @AppStorage("notes.workspace.recentInkColors") private var recentInkColorsRawValue = "blue,black,red,green,yellow,purple"
    @AppStorage("notes.workspace.doubleTapBehavior") private var doubleTapBehaviorRawValue = NotePencilDoubleTapBehavior.switchToEraser.rawValue

    init(note: Note, onOpenSource: ((SourceAnchor) -> Void)? = nil) {
        self.note = note
        self.onOpenSource = onOpenSource
        _workspaceViewModel = StateObject(wrappedValue: NoteWorkspaceViewModel(note: note))
    }

    private var supportsWorkspace: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var workspaceAppearance: NoteWorkspaceAppearance {
        get { NoteWorkspaceAppearance(rawValue: appearanceRawValue) ?? .paper }
        nonmutating set { appearanceRawValue = newValue.rawValue }
    }

    private var pencilDoubleTapBehavior: NotePencilDoubleTapBehavior {
        get { NotePencilDoubleTapBehavior(rawValue: doubleTapBehaviorRawValue) ?? .switchToEraser }
        nonmutating set { doubleTapBehaviorRawValue = newValue.rawValue }
    }

    var body: some View {
        Group {
            if supportsWorkspace {
                workspaceBody
            } else {
                NoteDetailView(note: note, onOpenSource: onOpenSource)
                    .environmentObject(appViewModel)
            }
        }
        .onAppear {
            workspaceViewModel.reload(using: appViewModel)
            syncRecentInkColorsFromStorage()
            if workspaceViewModel.panelState == .hidden {
                workspaceViewModel.panelState = .expanded
            }
        }
        .onChange(of: inkToolState.recentColorTokens) { _ in
            recentInkColorsRawValue = inkToolState.recentColorTokens.joined(separator: ",")
        }
    }

    private var workspaceBody: some View {
        ZStack {
            WorkspaceDeskBackdrop(appearance: workspaceAppearance)

            HStack(spacing: 22) {
                WorkspaceSidebar(
                    selection: $sidebarSelection,
                    panelState: $workspaceViewModel.panelState,
                    appearance: workspaceAppearance,
                    sourceTitle: workspaceViewModel.sourceAnchor.sourceTitle,
                    onQuickAdd: {
                        activeTool = .text
                        workspaceViewModel.addTextBlock()
                    }
                )

                VStack(spacing: 12) {
                    WorkspaceHeaderBar(
                        title: Binding(
                            get: { workspaceViewModel.title },
                            set: { workspaceViewModel.updateTitle($0) }
                        ),
                        sourceTitle: workspaceViewModel.sourceAnchor.sourceTitle,
                        sourceHint: workspaceViewModel.sourceHint,
                        saveStatus: workspaceViewModel.saveStatusText,
                        appearance: workspaceAppearance,
                        onBack: handleBack,
                        onSave: {
                            _ = workspaceViewModel.save(using: appViewModel)
                        },
                        onOpenSource: {
                            openSource(workspaceViewModel.sourceAnchor)
                        }
                    )

                    WorkspacePaperSurface(appearance: workspaceAppearance) {
                        NoteCanvasView(
                            sourceAnchor: workspaceViewModel.sourceAnchor,
                            blocks: workspaceViewModel.blocks,
                            linkedKnowledgePoints: workspaceViewModel.linkedKnowledgePoints,
                            candidateKnowledgePoints: workspaceViewModel.candidateKnowledgePoints,
                            highlightedBlockID: workspaceViewModel.highlightedBlockID,
                            currentOutlineTitle: workspaceViewModel.outlineContext.currentNode?.title,
                            canvasTitle: workspaceViewModel.title,
                            layoutStyle: .notebook,
                            appearance: workspaceAppearance,
                            showsCanvasHeader: true,
                            maxPaperWidth: 1160,
                            inkToolState: $inkToolState,
                            doubleTapBehavior: pencilDoubleTapBehavior,
                            showsAddBlockBar: false,
                            onUpdateTextBlock: { id, text in
                                workspaceViewModel.updateTextBlock(id: id, text: text)
                            },
                            onUpdateInkBlock: { block in
                                workspaceViewModel.updateInkBlock(block)
                            },
                            onLinkKnowledgePointToBlock: { pointID, blockID in
                                workspaceViewModel.linkKnowledgePoint(pointID, using: appViewModel, to: blockID)
                            },
                            onAddTextBlock: {
                                workspaceViewModel.addTextBlock()
                            },
                            onAddInkBlock: {
                                workspaceViewModel.ensureInkBlock()
                            },
                            onAddQuoteBlock: {
                                workspaceViewModel.addQuoteBlockFromSource()
                            },
                            onSelectKnowledgePoint: { point in
                                activeKnowledgePoint = point
                            },
                            onOpenSourceAnchor: openSource,
                            sourceAnchorForBlock: { block in
                                workspaceViewModel.sourceAnchor(for: block)
                            },
                            onOpenKnowledgePointSource: { point in
                                openSource(for: point)
                            },
                            onHighlightHandled: {
                                workspaceViewModel.clearHighlight()
                            }
                        )
                        .padding(.top, 58)
                    }
                    .overlay(alignment: .top) {
                        WorkspaceFloatingToolPalette(
                            activeTool: $activeTool,
                            inkToolState: $inkToolState,
                            doubleTapBehavior: Binding(
                                get: { pencilDoubleTapBehavior },
                                set: { pencilDoubleTapBehavior = $0 }
                            ),
                            appearance: workspaceAppearance,
                            onSelectAppearance: { mode in
                                workspaceAppearance = mode
                            },
                            onAddQuote: {
                                workspaceViewModel.addQuoteBlockFromSource()
                            },
                            onAddText: {
                                workspaceViewModel.addTextBlock()
                            },
                            onAddInk: {
                                workspaceViewModel.ensureInkBlock()
                            },
                            onSave: {
                                _ = workspaceViewModel.save(using: appViewModel)
                            },
                            onGenerateCard: generateCard
                        )
                        .padding(.top, 18)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if workspaceViewModel.panelState != .hidden {
                    WorkspaceContextSidebar(
                        selection: sidebarSelection,
                        panelState: $workspaceViewModel.panelState,
                        panelMode: $workspaceViewModel.panelMode,
                        appearance: workspaceAppearance,
                        sourceAnchor: workspaceViewModel.sourceAnchor,
                        sourceHint: workspaceViewModel.sourceHint,
                        outlineContext: workspaceViewModel.outlineContext,
                        linkedKnowledgePoints: workspaceViewModel.linkedKnowledgePoints,
                        candidateKnowledgePoints: workspaceViewModel.candidateKnowledgePoints,
                        currentQuoteBlock: currentQuoteBlock,
                        currentTextBlock: currentTextBlock,
                        onSelectNode: { nodeID in
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                workspaceViewModel.focus(on: nodeID)
                            }
                        },
                        onSelectKnowledgePoint: { point in
                            activeKnowledgePoint = point
                        },
                        onOpenSource: { anchor in
                            openSource(anchor)
                        },
                        onOpenKnowledgePointSource: { point in
                            openSource(for: point)
                        },
                        onGenerateCard: generateCard
                    )
                    .frame(width: contextSidebarWidth)
                    .frame(maxHeight: .infinity)
                    .padding(.top, 34)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 18)
            .padding(.bottom, 40)

            WorkspaceFooterStrip(
                appearance: workspaceAppearance,
                sourceTitle: workspaceViewModel.sourceAnchor.sourceTitle,
                saveStatus: workspaceViewModel.saveStatusText
            )
            .padding(.horizontal, 30)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .navigationBarHidden(true)
        .interactiveDismissDisabled(workspaceViewModel.isDirty)
        .confirmationDialog("当前笔记有未保存修改", isPresented: $showsExitConfirm, titleVisibility: .visible) {
            Button("保存并返回") {
                if workspaceViewModel.save(using: appViewModel) {
                    dismiss()
                }
            }

            Button("直接离开", role: .destructive) {
                dismiss()
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("要先保存这次整理过的文本块、手写块和关联知识点吗？")
        }
        .sheet(item: $activeKnowledgePoint) { point in
            KnowledgePointDetailView(point: point) { anchor in
                openSource(anchor)
            }
                .environmentObject(appViewModel)
        }
        .fullScreenCover(item: $sourceJumpTarget) { target in
            ReviewWorkbenchView(document: target.document, initialAnchor: target.anchor) {
                sourceJumpTarget = nil
            }
            .environmentObject(appViewModel)
        }
    }

    private func handleBack() {
        if workspaceViewModel.isDirty {
            showsExitConfirm = true
        } else {
            dismiss()
        }
    }

    private var contextSidebarWidth: CGFloat {
        switch workspaceViewModel.panelState {
        case .expanded:
            return 310
        case .compact:
            return 232
        case .hidden:
            return 0
        }
    }

    private func togglePanelVisibility() {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
            switch workspaceViewModel.panelState {
            case .expanded:
                workspaceViewModel.panelState = .hidden
            case .compact:
                workspaceViewModel.panelState = .hidden
            case .hidden:
                workspaceViewModel.panelState = .expanded
            }
        }
    }

    private var currentQuoteBlock: NoteBlock? {
        if let highlighted = workspaceViewModel.highlightedBlockID,
           let block = workspaceViewModel.blocks.first(where: { $0.id == highlighted && $0.kind == .quote }) {
            return block
        }

        return workspaceViewModel.blocks.last(where: { $0.kind == .quote })
    }

    private var currentTextBlock: NoteBlock? {
        if let highlighted = workspaceViewModel.highlightedBlockID,
           let block = workspaceViewModel.blocks.first(where: { $0.id == highlighted && $0.kind == .text }) {
            return block
        }

        return workspaceViewModel.blocks.last(where: { $0.kind == .text })
    }

    private func generateCard() {
        guard let document = workspaceViewModel.sourceDocument else { return }

        if let sentence = appViewModel.sentence(for: workspaceViewModel.sourceAnchor) {
            _ = appViewModel.addSentenceCard(for: sentence, explanation: nil, in: document)
            return
        }

        if let node = workspaceViewModel.outlineContext.currentNode {
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

    private func openSource(for point: KnowledgePoint) {
        guard let target = appViewModel.sourceJumpTarget(
            for: point,
            preferredSourceID: workspaceViewModel.sourceAnchor.sourceID
        ) else {
            return
        }

        if let onOpenSource {
            onOpenSource(target.anchor)
        } else {
            sourceJumpTarget = target
        }
    }

    private func syncRecentInkColorsFromStorage() {
        let tokens = recentInkColorsRawValue
            .split(separator: ",")
            .map(String.init)
        if !tokens.isEmpty {
            inkToolState.recentColorTokens = Array(tokens.prefix(6))
        }
    }
}

private enum WorkspaceSidebarSection: String, CaseIterable, Identifiable {
    case structure
    case knowledge
    case source
    case review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .structure:
            return "Structure"
        case .knowledge:
            return "Mind Map"
        case .source:
            return "Archive"
        case .review:
            return "Tags"
        }
    }

    var icon: String {
        switch self {
        case .structure:
            return "square.grid.2x2"
        case .knowledge:
            return "point.3.filled.connected.trianglepath.dotted"
        case .source:
            return "archivebox"
        case .review:
            return "tag"
        }
    }
}

private struct WorkspaceSidebar: View {
    @Binding var selection: WorkspaceSidebarSection
    @Binding var panelState: NoteOutlineFloatingPanelState
    let appearance: NoteWorkspaceAppearance
    let sourceTitle: String
    let onQuickAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Digital Archivist")
                    .font(.system(size: 24, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(appearance.workspaceAccent)

                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    appearance.workspaceSelectedFill,
                                    Color.white.opacity(0.96)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "person.crop.square")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(appearance.workspaceAccent)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(appearance.workspacePanelStroke, lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Research Library")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(appearance.workspaceText)
                        Text(sourceTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(appearance.workspaceMutedText)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 6)
            }

            VStack(spacing: 8) {
                ForEach(WorkspaceSidebarSection.allCases) { item in
                    Button {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                            selection = item
                            if panelState == .hidden {
                                panelState = .expanded
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 22)

                            Text(item.title)
                                .font(.system(size: 16, weight: .medium))

                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(selection == item ? appearance.workspaceAccent : appearance.workspaceMutedText)
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(selection == item ? appearance.workspaceSelectedFill : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(selection == item ? appearance.workspacePanelStroke : Color.clear, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(action: onQuickAdd) {
                HStack {
                    Spacer(minLength: 0)
                    Text("New Document")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.white)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(appearance.workspaceAccent)
                )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                        panelState = panelState == .hidden ? .expanded : .hidden
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: panelState == .hidden ? "sidebar.right" : "sidebar.left")
                        Text(panelState == .hidden ? "Show Context" : "Hide Context")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(appearance.workspaceMutedText)
                }
                .buttonStyle(.plain)

                Text("Workspace")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(appearance.workspaceMutedText.opacity(0.78))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .frame(width: 236, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(appearance.workspaceSidebarFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(appearance.workspacePanelStroke, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(appearance == .night ? 0.14 : 0.05), radius: 20, y: 10)
    }
}

private struct WorkspaceHeaderBar: View {
    @Binding var title: String
    let sourceTitle: String
    let sourceHint: String
    let saveStatus: String
    let appearance: NoteWorkspaceAppearance
    let onBack: () -> Void
    let onSave: () -> Void
    let onOpenSource: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(appearance.workspaceText.opacity(0.82))
                }
                .buttonStyle(.plain)

                Text("Digital Archivist")
                    .font(.system(size: 24, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(appearance.workspaceAccent)

                HStack(spacing: 8) {
                    iconButton("arrow.uturn.backward", action: {})
                    iconButton("arrow.uturn.forward", action: {})
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .center, spacing: 2) {
                TextField("Untitled Note", text: $title)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(appearance.workspaceText)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.never)

                Text(sourceHint.isEmpty ? sourceTitle : sourceHint)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(appearance.workspaceMutedText)
                    .lineLimit(1)
            }
            .frame(maxWidth: 460)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(sourceTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(appearance.workspaceAccent)
                        .lineLimit(1)
                    Text(sourceHint.uppercased())
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(appearance.workspaceMutedText.opacity(0.85))
                        .lineLimit(1)
                }
                .frame(maxWidth: 160, alignment: .trailing)

                Text(saveStatus.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(saveStatus == "已保存" ? Color.green.opacity(0.92) : Color.orange.opacity(0.88))

                iconButton("doc.text", action: onOpenSource)
                iconButton("square.and.arrow.up", action: onSave)
                iconButton("ellipsis", action: onSave)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(appearance.workspaceToolbarFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(appearance.workspacePanelStroke, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(appearance == .night ? 0.12 : 0.04), radius: 18, y: 10)
    }

    private func iconButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(appearance.workspaceText.opacity(0.78))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(appearance.workspaceBadgeFill)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct WorkspacePaperSurface<Content: View>: View {
    let appearance: NoteWorkspaceAppearance
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(appearance.workspaceMainSurface)
                .overlay {
                    NotebookGrid(spacing: 34)
                        .opacity(appearance == .night ? 0.05 : 0.07)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                }
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(appearance.workspaceAccent.opacity(0.14))
                        .frame(width: 4)
                        .padding(.vertical, 24)
                        .padding(.leading, 12)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(appearance.workspacePanelStroke, lineWidth: 1)
                )

            content()
                .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: Color.black.opacity(appearance == .night ? 0.12 : 0.045), radius: 24, y: 12)
    }
}

private struct WorkspaceFloatingToolPalette: View {
    @Binding var activeTool: WorkspaceEditorTool
    @Binding var inkToolState: NoteInkToolState
    @Binding var doubleTapBehavior: NotePencilDoubleTapBehavior
    let appearance: NoteWorkspaceAppearance
    let onSelectAppearance: (NoteWorkspaceAppearance) -> Void
    let onAddQuote: () -> Void
    let onAddText: () -> Void
    let onAddInk: () -> Void
    let onSave: () -> Void
    let onGenerateCard: () -> Void

    private var recentColorChoices: [NoteInkColorChoice] {
        inkToolState.recentColorTokens.map(NoteInkColorChoice.init(token:)).prefix(4).map { $0 }
    }

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 0) {
                compactToolButton(kind: .pen, title: "PEN")
                compactToolButton(kind: .highlighter, title: "HIGHLIGHTER")
                compactToolButton(kind: .eraser, title: "ERASER")
            }

            Divider()
                .frame(height: 28)

            HStack(spacing: 10) {
                ForEach(recentColorChoices) { choice in
                    Button {
                        inkToolState.colorToken = choice.token
                        activeTool = .ink
                    } label: {
                        Circle()
                            .fill(choice.color)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle()
                                    .stroke(inkToolState.colorToken == choice.token ? appearance.workspaceText : Color.clear, lineWidth: 1.5)
                                    .padding(-2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .frame(height: 28)

            Menu {
                Button("添加引用", action: onAddQuote)
                Button("添加文本", action: onAddText)
                Button("添加手写", action: onAddInk)
                Button("生成卡片", action: onGenerateCard)
                Button("保存", action: onSave)
                Divider()
                Section("主题") {
                    ForEach(NoteWorkspaceAppearance.allCases) { mode in
                        Button(mode.title) {
                            onSelectAppearance(mode)
                        }
                    }
                }
                Section("Apple Pencil 双击") {
                    ForEach(NotePencilDoubleTapBehavior.allCases) { behavior in
                        Button(behavior.title) {
                            doubleTapBehavior = behavior
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(appearance.workspaceMutedText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(appearance.workspaceToolTrayFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(appearance.workspacePanelStroke, lineWidth: 0.8)
                )
        )
        .shadow(color: Color.black.opacity(appearance == .night ? 0.14 : 0.05), radius: 20, y: 8)
    }

    private func compactToolButton(kind: NoteInkToolKind, title: String) -> some View {
        Button {
            activeTool = .ink
            inkToolState.kind = kind
        } label: {
            VStack(spacing: 5) {
                Image(systemName: kind.icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(inkToolState.kind == kind ? appearance.workspaceAccent : appearance.workspaceMutedText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                VStack(spacing: 0) {
                    Color.clear
                    Rectangle()
                        .fill(inkToolState.kind == kind ? appearance.workspaceAccent : Color.clear)
                        .frame(height: 2)
                        .padding(.horizontal, 4)
                }
            )
        }
        .buttonStyle(.plain)
    }
}

private struct WorkspaceContextSidebar: View {
    let selection: WorkspaceSidebarSection
    @Binding var panelState: NoteOutlineFloatingPanelState
    @Binding var panelMode: NoteOutlineFloatingPanelMode
    let appearance: NoteWorkspaceAppearance
    let sourceAnchor: SourceAnchor
    let sourceHint: String
    let outlineContext: WorkspaceOutlineContext
    let linkedKnowledgePoints: [KnowledgePoint]
    let candidateKnowledgePoints: [KnowledgePoint]
    let currentQuoteBlock: NoteBlock?
    let currentTextBlock: NoteBlock?
    let onSelectNode: (String?) -> Void
    let onSelectKnowledgePoint: (KnowledgePoint) -> Void
    let onOpenSource: (SourceAnchor) -> Void
    let onOpenKnowledgePointSource: (KnowledgePoint) -> Void
    let onGenerateCard: () -> Void

    private var isCompact: Bool {
        panelState == .compact
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                headerBar
                summaryCard

                switch selection {
                case .structure:
                    structureSection
                case .knowledge:
                    knowledgeSection
                case .source:
                    sourceSection
                case .review:
                    reviewSection
                }
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(appearance.workspaceContextFill)
        )
        .shadow(color: Color.black.opacity(appearance == .night ? 0.12 : 0.04), radius: 18, y: 10)
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            Text(sidebarHeadline)
                .font(.system(size: 12, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(appearance.workspaceText)

            Spacer(minLength: 0)

            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    panelState = panelState == .expanded ? .compact : .expanded
                }
            } label: {
                Image(systemName: panelState == .expanded ? "arrow.right.to.line.compact" : "arrow.left.to.line.compact")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(appearance.workspaceMutedText)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(appearance.workspaceBadgeFill))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    panelState = .hidden
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(appearance.workspaceMutedText)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(appearance.workspaceBadgeFill))
            }
            .buttonStyle(.plain)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CURRENT CONTEXT")
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundStyle(appearance.workspaceMutedText)

            Text(outlineContext.currentNode?.title ?? sourceAnchor.sourceTitle)
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(appearance.workspaceText)
                .lineLimit(isCompact ? 2 : 3)

            Text(sourceHint)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(appearance.workspaceMutedText)
                .lineLimit(isCompact ? 2 : 3)
        }
            .padding(14)
            .background(sidebarCardFill)
    }

    private var structureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !isCompact {
                Picker("结构", selection: $panelMode) {
                    ForEach(NoteOutlineFloatingPanelMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            if panelMode == .structure {
                analysisSection(
                    title: "Structure Path",
                    content: {
                        OutlinePathView(nodes: outlineContext.pathNodes)
                    }
                )

                if let currentNode = outlineContext.currentNode {
                    OutlineNodeRow(node: currentNode, isCurrent: true) {
                        onSelectNode(currentNode.id)
                    }
                }

                ForEach(Array(outlineContext.nearbyNodes.prefix(isCompact ? 3 : 6))) { node in
                    OutlineNodeRow(node: node, isCurrent: node.id == outlineContext.currentNode?.id) {
                        onSelectNode(node.id)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if let currentNode = outlineContext.currentNode {
                        analysisSection(
                            title: "Current Node",
                            content: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(currentNode.title)
                                        .font(.system(size: 17, weight: .semibold, design: .serif))
                                        .foregroundStyle(appearance.workspaceAccent)
                                    Text(currentNode.summary)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(appearance.workspaceMutedText)
                                        .lineSpacing(4)
                                }
                            }
                        )
                    }

                    ForEach(Array(outlineContext.pathNodes.prefix(isCompact ? 3 : 6))) { node in
                        Button {
                            onSelectNode(node.id)
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(node.id == outlineContext.currentNode?.id ? appearance.workspaceAccent : appearance.workspaceAccent.opacity(0.28))
                                    .frame(width: 8, height: 8)
                                Text(node.title)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(appearance.workspaceText.opacity(0.84))
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(sidebarCardFill)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var knowledgeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            analysisSection(
                title: "Knowledge Chips",
                content: {
                    LinkedKnowledgePointChipsView(
                        points: Array(linkedKnowledgePoints.prefix(isCompact ? 6 : 12)),
                        onSelect: onSelectKnowledgePoint,
                        onOpenSource: onOpenKnowledgePointSource
                    )
                }
            )

            if !candidateKnowledgePoints.isEmpty && !isCompact {
                analysisSection(
                    title: "Suggested Links",
                    content: {
                        FlexibleChipFlow(items: Array(candidateKnowledgePoints.prefix(8))) { point in
                            Button {
                                onSelectKnowledgePoint(point)
                            } label: {
                                NotesMetaPill(text: point.title, tint: .purple)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                )
            }
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            analysisSection(
                title: "Source",
                content: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(sourceAnchor.sourceTitle)
                            .font(.system(size: 17, weight: .semibold, design: .serif))
                            .foregroundStyle(appearance.workspaceText)
                        Text(sourceAnchor.anchorLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(appearance.workspaceAccent)
                    }
                }
            )

            if let currentQuoteBlock, let text = currentQuoteBlock.text?.nonEmpty {
                analysisSection(
                    title: "Current Quote",
                    content: {
                        Text(text)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(appearance.workspaceText.opacity(0.82))
                            .lineSpacing(4)
                            .lineLimit(isCompact ? 4 : 7)
                    }
                )
            }

            Button {
                onOpenSource(sourceAnchor)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.forward.square")
                    Text("回到原文")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(appearance.workspaceAccent)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let currentTextBlock, let text = currentTextBlock.text?.nonEmpty {
                analysisSection(
                    title: "AI Analysis",
                    content: {
                        Text(text)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(appearance.workspaceText.opacity(0.82))
                            .lineSpacing(4)
                            .lineLimit(isCompact ? 5 : 8)
                    }
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("整理动作")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(appearance.workspaceMutedText)

                actionRow(title: "生成卡片", icon: "rectangle.stack.badge.plus", action: onGenerateCard)
                actionRow(title: "回到原文", icon: "doc.text.magnifyingglass") {
                    onOpenSource(sourceAnchor)
                }
            }
            .padding(14)
            .background(sidebarCardFill)
        }
    }

    private func actionRow(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(appearance.workspaceText.opacity(0.82))
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(appearance.workspaceBadgeFill)
            )
        }
        .buttonStyle(.plain)
    }

    private var sidebarHeadline: String {
        switch selection {
        case .structure:
            return "NAVIGATOR"
        case .knowledge:
            return "VOCABULARY"
        case .source:
            return "ARCHIVE"
        case .review:
            return "ANALYSIS"
        }
    }

    @ViewBuilder
    private func analysisSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(appearance.workspaceMutedText)
            content()
        }
        .padding(14)
        .background(sidebarCardFill)
    }

    private var sidebarCardFill: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(appearance.workspacePanelFill)
    }
}

private struct WorkspaceDeskBackdrop: View {
    let appearance: NoteWorkspaceAppearance

    var body: some View {
        ZStack {
            LinearGradient(
                colors: appearance.deskGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            NotebookGrid(spacing: 40)
                .opacity(appearance == .night ? 0.04 : 0.08)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.white.opacity(appearance == .night ? 0.02 : 0.22),
                    .clear,
                    AppPalette.paperTape.opacity(appearance == .night ? 0.03 : 0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

private struct WorkspaceFooterStrip: View {
    let appearance: NoteWorkspaceAppearance
    let sourceTitle: String
    let saveStatus: String

    var body: some View {
        HStack {
            HStack(spacing: 16) {
                Text("MASTER NOTE")
                Text("QUICK ADD")
                Text("SUPPORT")
            }
            .font(.system(size: 10, weight: .bold))
            .tracking(1.1)
            .foregroundStyle(appearance.workspaceMutedText)

            Spacer(minLength: 0)

            Text("\(sourceTitle) · \(saveStatus)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(appearance.workspaceMutedText)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(appearance == .night ? 0.06 : 0.72))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(appearance.workspacePanelStroke, lineWidth: 1)
                )
        )
    }
}

private extension NoteWorkspaceAppearance {
    var workspaceMainSurface: Color {
        switch self {
        case .paper:
            return Color.white.opacity(0.58)
        case .night:
            return Color.white.opacity(0.03)
        case .eyeCare:
            return Color.white.opacity(0.42)
        }
    }

    var workspacePanelFill: Color {
        switch self {
        case .paper:
            return Color.white.opacity(0.84)
        case .night:
            return Color.white.opacity(0.07)
        case .eyeCare:
            return Color.white.opacity(0.64)
        }
    }

    var workspaceSidebarFill: Color {
        switch self {
        case .paper:
            return Color(red: 239 / 255, green: 237 / 255, blue: 231 / 255)
        case .night:
            return Color(red: 27 / 255, green: 31 / 255, blue: 40 / 255)
        case .eyeCare:
            return Color(red: 233 / 255, green: 238 / 255, blue: 223 / 255)
        }
    }

    var workspaceContextFill: Color {
        switch self {
        case .paper:
            return Color(red: 244 / 255, green: 242 / 255, blue: 238 / 255).opacity(0.94)
        case .night:
            return Color(red: 30 / 255, green: 35 / 255, blue: 46 / 255).opacity(0.95)
        case .eyeCare:
            return Color(red: 238 / 255, green: 242 / 255, blue: 231 / 255).opacity(0.95)
        }
    }

    var workspaceToolTrayFill: Color {
        switch self {
        case .paper:
            return Color(red: 245 / 255, green: 243 / 255, blue: 237 / 255).opacity(0.94)
        case .night:
            return Color(red: 35 / 255, green: 40 / 255, blue: 54 / 255).opacity(0.96)
        case .eyeCare:
            return Color(red: 241 / 255, green: 245 / 255, blue: 233 / 255).opacity(0.94)
        }
    }

    var workspaceToolbarFill: Color {
        switch self {
        case .paper:
            return Color.white.opacity(0.88)
        case .night:
            return Color(red: 31 / 255, green: 36 / 255, blue: 48 / 255).opacity(0.94)
        case .eyeCare:
            return Color(red: 243 / 255, green: 246 / 255, blue: 236 / 255).opacity(0.92)
        }
    }

    var workspacePanelStroke: Color {
        switch self {
        case .paper:
            return AppPalette.paperLine.opacity(0.58)
        case .night:
            return Color.white.opacity(0.10)
        case .eyeCare:
            return Color.white.opacity(0.46)
        }
    }

    var workspaceSelectedFill: Color {
        switch self {
        case .paper:
            return AppPalette.primary.opacity(0.12)
        case .night:
            return AppPalette.primary.opacity(0.18)
        case .eyeCare:
            return Color.green.opacity(0.14)
        }
    }

    var workspaceBadgeFill: Color {
        switch self {
        case .paper:
            return Color.white.opacity(0.92)
        case .night:
            return Color.white.opacity(0.08)
        case .eyeCare:
            return Color.white.opacity(0.62)
        }
    }

    var workspaceAccent: Color {
        switch self {
        case .paper:
            return AppPalette.primaryDeep
        case .night:
            return AppPalette.primary
        case .eyeCare:
            return Color.green.opacity(0.82)
        }
    }

    var workspaceText: Color {
        switch self {
        case .paper:
            return AppPalette.paperInk
        case .night:
            return AppPalette.softText
        case .eyeCare:
            return Color(red: 34 / 255, green: 49 / 255, blue: 31 / 255)
        }
    }

    var workspaceMutedText: Color {
        switch self {
        case .paper:
            return AppPalette.paperMuted
        case .night:
            return AppPalette.softMutedText
        case .eyeCare:
            return Color(red: 93 / 255, green: 112 / 255, blue: 82 / 255)
        }
    }

    var deskGradient: [Color] {
        switch self {
        case .paper:
            return [
                Color(red: 244 / 255, green: 241 / 255, blue: 233 / 255),
                Color(red: 248 / 255, green: 245 / 255, blue: 237 / 255),
                Color(red: 242 / 255, green: 239 / 255, blue: 232 / 255)
            ]
        case .night:
            return [
                Color(red: 23 / 255, green: 31 / 255, blue: 44 / 255),
                Color(red: 39 / 255, green: 50 / 255, blue: 71 / 255),
                Color(red: 61 / 255, green: 74 / 255, blue: 98 / 255)
            ]
        case .eyeCare:
            return [
                Color(red: 214 / 255, green: 227 / 255, blue: 202 / 255),
                Color(red: 232 / 255, green: 239 / 255, blue: 220 / 255),
                Color(red: 243 / 255, green: 246 / 255, blue: 233 / 255)
            ]
        }
    }

    var glowColor: Color {
        switch self {
        case .paper:
            return Color.white.opacity(0.08)
        case .night:
            return Color(red: 127 / 255, green: 153 / 255, blue: 214 / 255).opacity(0.18)
        case .eyeCare:
            return Color.white.opacity(0.12)
        }
    }

    var secondaryGlowColor: Color {
        switch self {
        case .paper:
            return AppPalette.paperTapeBlue.opacity(0.04)
        case .night:
            return Color(red: 97 / 255, green: 121 / 255, blue: 177 / 255).opacity(0.18)
        case .eyeCare:
            return Color(red: 134 / 255, green: 173 / 255, blue: 127 / 255).opacity(0.08)
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct NoteWorkspaceView_Previews: PreviewProvider {
    static var previews: some View {
        NoteWorkspacePreview()
    }
}

private struct NoteWorkspacePreview: View {
    @StateObject private var appViewModel = AppViewModel()

    var body: some View {
        NavigationStack {
            if let note = appViewModel.notes.first {
                NoteWorkspaceView(note: note)
                    .environmentObject(appViewModel)
            } else {
                Text("暂无预览笔记")
            }
        }
    }
}
