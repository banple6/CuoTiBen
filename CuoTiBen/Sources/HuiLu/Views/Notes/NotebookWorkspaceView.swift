import SwiftUI
import UIKit

// MARK: - Enums (kept for backward compatibility)

enum CanvasContentMode: String, CaseIterable, Identifiable {
    case note, sourceLinked, knowledge, handwriting
    var id: String { rawValue }
}

enum NavigatorContentMode: String, CaseIterable, Identifiable {
    case structure, related, outline
    var id: String { rawValue }
    var title: String {
        switch self { case .structure: return "结构"; case .related: return "关联"; case .outline: return "大纲" }
    }
    var icon: String {
        switch self { case .structure: return "list.bullet.indent"; case .related: return "link"; case .outline: return "doc.text.magnifyingglass" }
    }
}

enum WorkspacePhase { case empty, loaded, editing }

// MARK: - Design Tokens

private enum WS {
    static let surface              = Color(red: 251/255, green: 249/255, blue: 244/255)
    static let surfaceContainer     = Color(red: 240/255, green: 238/255, blue: 233/255)
    static let surfaceContainerHigh = Color(red: 234/255, green: 232/255, blue: 227/255)
    static let onSurface            = Color(red: 27/255,  green: 28/255,  blue: 25/255)
    static let primary              = Color(red: 0/255,   green: 93/255,  blue: 167/255)
    static let outline              = Color(red: 113/255, green: 119/255, blue: 131/255)
    static let outlineVariant       = Color(red: 193/255, green: 199/255, blue: 211/255)
    static let secondaryContainer   = Color(red: 198/255, green: 228/255, blue: 244/255)
    static let tertiary             = Color(red: 89/255,  green: 97/255,  blue: 0/255)
    static let error                = Color(red: 186/255, green: 26/255,  blue: 26/255)
}

// ╔══════════════════════════════════════════════════════════════╗
// ║  NotebookWorkspaceView                                       ║
// ║                                                              ║
// ║  Layout:  sidebar (264) │ blank canvas │ ReferencePanel (280)║
// ║  Toolbar: ← 返回原文 · [Pen HL Eraser Text Select] colors · ref toggle
// ╚══════════════════════════════════════════════════════════════╝

struct NotebookWorkspaceView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    let screenModel: NotesHomeViewModel
    @Binding var selectedTab: NotesHomeTab
    @Binding var searchText: String
    @Binding var activeFilter: NotesFilterMode
    var showsCloseButton: Bool = true
    var onClose: (() -> Void)?
    var onOpenSource: ((SourceAnchor) -> Void)?

    // ── Core state ──
    @State private var selectedNoteID: UUID?
    @State private var referencePanelOpen = true

    // ── Editing tools ──
    @State private var activeTool: WorkspaceTool = .pen
    @State private var inkToolState = NoteInkToolState()

    // ── Persistence ──
    @AppStorage("notes.workspace.appearance")       private var appearanceRawValue = NoteWorkspaceAppearance.paper.rawValue
    @AppStorage("notes.workspace.doubleTapBehavior") private var doubleTapBehaviorRawValue = NotePencilDoubleTapBehavior.switchToEraser.rawValue

    // ── Modal ──
    @State private var sourceJumpTarget: SourceJumpTarget?
    @State private var showSourceNotFoundAlert = false

    // ── Derived ──
    private var paneItems: [NotesPaneItem] { screenModel.paneItems(for: selectedTab) }
    private var selectedNote: Note? {
        guard let selectedNoteID else { return nil }
        return appViewModel.note(with: selectedNoteID)
    }
    private var pencilDoubleTapBehavior: NotePencilDoubleTapBehavior {
        NotePencilDoubleTapBehavior(rawValue: doubleTapBehaviorRawValue) ?? .switchToEraser
    }
    private var isTextMode: Bool { activeTool == .text || activeTool == .select }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Body
    // ═══════════════════════════════════════════════════════════

    var body: some View {
        VStack(spacing: 0) {
            // ── Top: horizontal writing toolbar ──
            writingToolbar

            // ── Main: sidebar + canvas + reference panel ──
            HStack(spacing: 0) {
                noteIndexSidebar
                    .frame(width: 264)

                canvasArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if referencePanelOpen {
                    referencePanelView
                        .frame(width: 280)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }

            // ── Bottom: quiet status bar ──
            statusBar
        }
        .background(WS.surface.ignoresSafeArea())
        .navigationBarHidden(true)
        .onAppear(perform: selectFirstAvailableNote)
        .onChange(of: selectedTab) { _ in selectFirstAvailableNote() }
        .onChange(of: paneItems.map(\.noteID)) { newIDs in
            if let selectedNoteID, newIDs.contains(selectedNoteID) { return }
            self.selectedNoteID = newIDs.first
        }
        .fullScreenCover(item: $sourceJumpTarget) { target in
            ReviewWorkbenchView(document: target.document, initialAnchor: target.anchor) {
                sourceJumpTarget = nil
            }
            .environmentObject(appViewModel)
        }
        .alert("未找到原文资料", isPresented: $showSourceNotFoundAlert) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("该笔记关联的原文资料尚未导入或已被移除。")
        }
    }

    // ── Helpers ──
    private func selectFirstAvailableNote() {
        selectedNoteID = screenModel.firstNoteID(for: selectedTab)
    }

    private func openSource(_ anchor: SourceAnchor) {
        if let onOpenSource { onOpenSource(anchor); return }
        if let target = appViewModel.sourceJumpTarget(for: anchor) {
            sourceJumpTarget = target
        } else {
            showSourceNotFoundAlert = true
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Writing Toolbar (horizontal instrument tray)
    // ═══════════════════════════════════════════════════════════

    private var writingToolbar: some View {
        HStack(spacing: 0) {
            // ── Left: 返回原文 ──
            if let note = selectedNote {
                Button { openSource(note.sourceAnchor) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 12, weight: .bold))
                        Text("返回原文")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(WS.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule(style: .continuous).fill(WS.secondaryContainer.opacity(0.3)))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 16)

            // ── Center: writing tools capsule ──
            HStack(spacing: 0) {
                toolButton(.pen,         icon: "pencil.tip",         label: "Pen")
                toolButton(.highlighter, icon: "highlighter",        label: "HL")
                toolButton(.eraser,      icon: "eraser",             label: "Eraser")

                toolDivider

                toolButton(.text,   icon: "character.textbox", label: "Text")
                toolButton(.select, icon: "lasso",             label: "Select")

                toolDivider

                // Color dots
                HStack(spacing: 5) {
                    ForEach(inkToolState.recentColorTokens.prefix(4), id: \.self) { token in
                        let choice = NoteInkColorChoice(token: token)
                        Circle()
                            .fill(choice.color)
                            .frame(width: 12, height: 12)
                            .overlay {
                                if token == inkToolState.colorToken {
                                    Circle().stroke(WS.primary, lineWidth: 1.5)
                                        .frame(width: 16, height: 16)
                                }
                            }
                            .onTapGesture { inkToolState.colorToken = token }
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(WS.surfaceContainerHigh.opacity(0.6)))

            Spacer(minLength: 16)

            // ── Right: save status + reference toggle + close ──
            HStack(spacing: 10) {
                // Reference panel toggle
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        referencePanelOpen.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: referencePanelOpen ? "sidebar.right" : "sidebar.right")
                            .font(.system(size: 13, weight: .regular))
                        Text("参考")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(referencePanelOpen ? WS.primary : WS.outline.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(referencePanelOpen ? WS.secondaryContainer.opacity(0.25) : Color.clear)
                    )
                }
                .buttonStyle(.plain)

                if showsCloseButton, let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(WS.outline.opacity(0.5))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            WS.surface
                .overlay(alignment: .bottom) {
                    Rectangle().fill(WS.onSurface.opacity(0.06)).frame(height: 0.5)
                }
        )
    }

    private func toolButton(_ tool: WorkspaceTool, icon: String, label: String) -> some View {
        Button {
            activeTool = tool
            // Sync ink tool state
            switch tool {
            case .pen:         inkToolState.kind = .pen
            case .highlighter: inkToolState.kind = .highlighter
            case .eraser:      inkToolState.kind = .eraser
            case .text:        break
            case .select:      inkToolState.kind = .lasso
            }
        } label: {
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: activeTool == tool ? .semibold : .regular))
                Text(label)
                    .font(.system(size: 7, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(0.3)
            }
            .foregroundStyle(activeTool == tool ? WS.primary : WS.outline.opacity(0.5))
            .frame(width: 42, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(activeTool == tool ? WS.secondaryContainer.opacity(0.2) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var toolDivider: some View {
        Rectangle()
            .fill(WS.outlineVariant.opacity(0.4))
            .frame(width: 0.5, height: 22)
            .padding(.horizontal, 4)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Note Index Sidebar (left)
    // ═══════════════════════════════════════════════════════════

    private var noteIndexSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CATALOG")
                    .font(.system(size: 9, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(2.5)
                    .foregroundStyle(WS.outline.opacity(0.45))
                Text(selectedTab.sidebarLabel)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(WS.onSurface.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 14)

            HStack(spacing: 0) {
                ForEach(NotesHomeTab.allCases) { tab in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { selectedTab = tab }
                    } label: {
                        Text(tab.compactTitle)
                            .font(.system(size: 11, weight: selectedTab == tab ? .bold : .medium))
                            .foregroundStyle(selectedTab == tab ? WS.primary : WS.outline.opacity(0.5))
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .bottom) {
                                if selectedTab == tab {
                                    Rectangle().fill(WS.primary).frame(height: 1.5)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            Rectangle().fill(WS.outlineVariant.opacity(0.2)).frame(height: 0.5).padding(.top, 4)

            if paneItems.isEmpty {
                Spacer()
                Text("暂无笔记")
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .foregroundStyle(WS.outline.opacity(0.4))
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(paneItems) { item in
                            IndexCardRow(item: item, isSelected: selectedNoteID == item.noteID) {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    selectedNoteID = item.noteID
                                }
                            }
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
        .background(WS.surfaceContainer.opacity(0.55))
        .overlay(alignment: .trailing) {
            Rectangle().fill(WS.outlineVariant.opacity(0.15)).frame(width: 0.5)
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Canvas Area (center — blank notebook page)
    // ═══════════════════════════════════════════════════════════

    @ViewBuilder
    private var canvasArea: some View {
        if let note = selectedNote {
            NotebookPageCanvasHost(
                note: note,
                appViewModel: appViewModel,
                inkToolState: $inkToolState,
                isTextMode: isTextMode,
                doubleTapBehavior: pencilDoubleTapBehavior,
                onOpenSource: { anchor in openSource(anchor) }
            )
            .id(note.id)
        } else {
            canvasEmptyState
        }
    }

    private var canvasEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(WS.outline.opacity(0.2))
            Text("从左侧索引选择一条笔记")
                .font(.system(size: 14, weight: .medium, design: .serif))
                .foregroundStyle(WS.outline.opacity(0.35))
            Spacer()
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Reference Panel (right — floating reference sidebar)
    // ═══════════════════════════════════════════════════════════

    @ViewBuilder
    private var referencePanelView: some View {
        if let note = selectedNote {
            ReferencePanelHost(
                note: note,
                appViewModel: appViewModel,
                onOpenSource: { anchor in openSource(anchor) }
            )
            .id(note.id)
        } else {
            VStack {
                Spacer()
                Text("选择笔记后查看参考资料")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WS.outline.opacity(0.35))
                Spacer()
            }
            .background(Color(red: 0.97, green: 0.965, blue: 0.95))
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Status Bar (bottom)
    // ═══════════════════════════════════════════════════════════

    private var statusBar: some View {
        HStack(spacing: 0) {
            if let note = selectedNote {
                Text(note.sourceAnchor.anchorLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WS.outline.opacity(0.4))
                Text(" · ").foregroundStyle(WS.outline.opacity(0.2))
                Text("\(note.blocks.count) blocks")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WS.outline.opacity(0.35))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
        .background(
            WS.surface.overlay(alignment: .top) {
                Rectangle().fill(WS.onSurface.opacity(0.06)).frame(height: 0.5)
            }
        )
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Workspace Tool
// ═══════════════════════════════════════════════════════════════

private enum WorkspaceTool: String, CaseIterable, Identifiable {
    case pen, highlighter, eraser, text, select
    var id: String { rawValue }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - NotebookPageCanvasHost
// ═══════════════════════════════════════════════════════════════

private struct NotebookPageCanvasHost: View {
    let note: Note
    let appViewModel: AppViewModel
    @Binding var inkToolState: NoteInkToolState
    let isTextMode: Bool
    let doubleTapBehavior: NotePencilDoubleTapBehavior
    let onOpenSource: (SourceAnchor) -> Void

    @StateObject private var vm: NoteWorkspaceViewModel

    init(note: Note,
         appViewModel: AppViewModel,
         inkToolState: Binding<NoteInkToolState>,
         isTextMode: Bool,
         doubleTapBehavior: NotePencilDoubleTapBehavior,
         onOpenSource: @escaping (SourceAnchor) -> Void)
    {
        self.note = note
        self.appViewModel = appViewModel
        self._inkToolState = inkToolState
        self.isTextMode = isTextMode
        self.doubleTapBehavior = doubleTapBehavior
        self.onOpenSource = onOpenSource
        _vm = StateObject(wrappedValue: NoteWorkspaceViewModel(note: note))
    }

    var body: some View {
        NotebookPageCanvasView(
            vm: vm,
            appViewModel: appViewModel,
            inkToolState: $inkToolState,
            isTextMode: isTextMode,
            doubleTapBehavior: doubleTapBehavior,
            onOpenSource: onOpenSource
        )
        .onAppear { vm.reload(using: appViewModel) }
        .onDisappear { if vm.isDirty { _ = vm.save(using: appViewModel) } }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - ReferencePanelHost
// ═══════════════════════════════════════════════════════════════

private struct ReferencePanelHost: View {
    let note: Note
    let appViewModel: AppViewModel
    let onOpenSource: (SourceAnchor) -> Void

    @StateObject private var vm: NoteWorkspaceViewModel

    init(note: Note,
         appViewModel: AppViewModel,
         onOpenSource: @escaping (SourceAnchor) -> Void)
    {
        self.note = note
        self.appViewModel = appViewModel
        self.onOpenSource = onOpenSource
        _vm = StateObject(wrappedValue: NoteWorkspaceViewModel(note: note))
    }

    var body: some View {
        ReferencePanel(
            vm: vm,
            appViewModel: appViewModel,
            onOpenSource: onOpenSource
        )
        .onAppear { vm.reload(using: appViewModel) }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Private Sub-Components
// ═══════════════════════════════════════════════════════════════

private struct IndexCardRow: View {
    let item: NotesPaneItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? WS.primary : WS.onSurface.opacity(0.7))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WS.outline.opacity(isSelected ? 0.6 : 0.4))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isSelected ? WS.secondaryContainer.opacity(0.25) : Color.clear)
                    .padding(.horizontal, 6)
            )
            .overlay(alignment: .bottom) {
                if !isSelected {
                    Rectangle().fill(WS.outlineVariant.opacity(0.1)).frame(height: 0.5).padding(.horizontal, 16)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab Extensions

private extension NotesHomeTab {
    var sidebarLabel: String {
        switch self {
        case .recent:  return "Recent Notes"
        case .source:  return "By Source"
        case .concept: return "By Concept"
        }
    }
    var compactTitle: String {
        switch self {
        case .recent:  return "Recent"
        case .source:  return "Source"
        case .concept: return "Concept"
        }
    }
}
