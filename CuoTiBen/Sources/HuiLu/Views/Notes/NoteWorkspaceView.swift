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
        }
        .onChange(of: inkToolState.recentColorTokens) { _ in
            recentInkColorsRawValue = inkToolState.recentColorTokens.joined(separator: ",")
        }
    }

    private var workspaceBody: some View {
        ZStack(alignment: .topTrailing) {
            WorkspaceDeskBackdrop(appearance: workspaceAppearance)

            VStack(spacing: 8) {
                WorkspaceTopBar(
                    title: $workspaceViewModel.title,
                    activeTool: $activeTool,
                    inkToolState: $inkToolState,
                    doubleTapBehavior: Binding(
                        get: { pencilDoubleTapBehavior },
                        set: { pencilDoubleTapBehavior = $0 }
                    ),
                    appearance: workspaceAppearance,
                    saveStatus: workspaceViewModel.saveStatusText,
                    sourceHint: workspaceViewModel.sourceHint,
                    notebookContextLine: workspaceViewModel.notebookContextLine,
                    contextTabTitle: workspaceViewModel.outlineContext.currentNode?.title ?? "结构整理",
                    onBack: handleBack,
                    onSave: {
                        _ = workspaceViewModel.save(using: appViewModel)
                    },
                    onOpenSource: {
                        openSource(workspaceViewModel.sourceAnchor)
                    },
                    onGenerateCard: generateCard,
                    onInsertQuote: {
                        workspaceViewModel.addQuoteBlockFromSource()
                    },
                    onAddTextBlock: {
                        workspaceViewModel.addTextBlock()
                    },
                    onAddInkBlock: {
                        workspaceViewModel.ensureInkBlock()
                    },
                    onToggleOutline: {
                        togglePanelVisibility()
                    },
                    onSelectAppearance: { mode in
                        workspaceAppearance = mode
                    }
                )

                NoteCanvasView(
                    sourceAnchor: workspaceViewModel.sourceAnchor,
                    blocks: workspaceViewModel.blocks,
                    linkedKnowledgePoints: workspaceViewModel.linkedKnowledgePoints,
                    candidateKnowledgePoints: workspaceViewModel.candidateKnowledgePoints,
                    highlightedBlockID: workspaceViewModel.highlightedBlockID,
                    currentOutlineTitle: workspaceViewModel.outlineContext.currentNode?.title,
                    layoutStyle: .studio,
                    appearance: workspaceAppearance,
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
                .frame(maxWidth: 1320, maxHeight: .infinity, alignment: .leading)
                .padding(.trailing, workspaceTrailingInset)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            NoteOutlineFloatingPanel(
                state: workspaceViewModel.panelState,
                mode: $workspaceViewModel.panelMode,
                sourceTitle: workspaceViewModel.sourceAnchor.sourceTitle,
                context: workspaceViewModel.outlineContext,
                onSelectNode: { nodeID in
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        workspaceViewModel.focus(on: nodeID)
                    }
                },
                onCycleState: togglePanelVisibility
            )
            .padding(.top, 88)
            .padding(.trailing, 16)
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

    private var workspaceTrailingInset: CGFloat {
        switch workspaceViewModel.panelState {
        case .expanded:
            return 330
        case .compact:
            return 210
        case .hidden:
            return 4
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

            Circle()
                .fill(appearance.glowColor)
                .frame(width: 460, height: 460)
                .blur(radius: 110)
                .offset(x: 320, y: -180)

            Circle()
                .fill(appearance.secondaryGlowColor)
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .offset(x: -260, y: 260)
        }
        .ignoresSafeArea()
    }
}

private extension NoteWorkspaceAppearance {
    var deskGradient: [Color] {
        switch self {
        case .paper:
            return [
                Color(red: 208 / 255, green: 224 / 255, blue: 249 / 255),
                Color(red: 233 / 255, green: 241 / 255, blue: 251 / 255),
                Color(red: 246 / 255, green: 248 / 255, blue: 252 / 255)
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
            return Color.white.opacity(0.34)
        case .night:
            return Color(red: 127 / 255, green: 153 / 255, blue: 214 / 255).opacity(0.18)
        case .eyeCare:
            return Color.white.opacity(0.20)
        }
    }

    var secondaryGlowColor: Color {
        switch self {
        case .paper:
            return AppPalette.cyan.opacity(0.10)
        case .night:
            return Color(red: 97 / 255, green: 121 / 255, blue: 177 / 255).opacity(0.18)
        case .eyeCare:
            return Color(red: 134 / 255, green: 173 / 255, blue: 127 / 255).opacity(0.14)
        }
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
