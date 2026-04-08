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
// ║  Page model:                                                 ║
// ║    A. Workspace Home  — selectedNoteID == nil                ║
// ║    B. Note Page       — selectedNoteID != nil (center canvas)║
// ║    C. Reference Browser — right panel (structure/source/     ║
// ║                           mindmap/materials)                 ║
// ║                                                              ║
// ║  Layout:  sidebar (264) │ canvas/home │ ReferencePanel (280) ║
// ║  Toolbar: ← 返回工作区 · [Pen HL Eraser Text Select] · ref  ║
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

    // ── Core state: nil = Home, non-nil = Note Page ──
    @State private var selectedNoteID: UUID?
    @State private var referencePanelOpen = false

    // ── Draft tracking: notes created via "新建笔记" that haven't been persisted yet ──
    @State private var draftNoteID: UUID?
    @State private var draftNote: Note?

    // ── Editing tools (only relevant when note is selected) ──
    @State private var activeTool: WorkspaceTool = .pen
    @State private var inkToolState = NoteInkToolState()
    @State private var showTextStylePopover = false

    // ── Unified editor selection state (drives contextual inspector) ──
    @State private var editorSelection: EditorSelection = .none

    // ── Active note VM reference (set by canvas host, used by toolbar inspector) ──
    @State private var noteVM: NoteWorkspaceViewModel?

    // ── Snapshot of the currently-inspected block (kept in sync for toolbar re-renders) ──
    @State private var inspectorBlock: NoteBlock?

    // ── Bridge for sending actions (delete/copy) to PKCanvasView ──
    @State private var inkActionBridge = InkActionBridge()

    // ── Reference panel tab ──
    @State private var referencePanelActiveTab: ReferencePanelTab = .structure

    // ── Persistence ──
    @AppStorage("notes.workspace.appearance")       private var appearanceRawValue = NoteWorkspaceAppearance.paper.rawValue
    @AppStorage("notes.workspace.doubleTapBehavior") private var doubleTapBehaviorRawValue = NotePencilDoubleTapBehavior.switchToEraser.rawValue

    // ── Derived ──
    private var paneItems: [NotesPaneItem] { screenModel.paneItems(for: selectedTab) }
    private var selectedNote: Note? {
        guard let selectedNoteID else { return nil }
        // Check in-memory draft first, then persisted notes
        if let draft = draftNote, draft.id == selectedNoteID {
            return draft
        }
        return appViewModel.note(with: selectedNoteID)
    }
    private var isOnNotePage: Bool { selectedNoteID != nil }
    private var pencilDoubleTapBehavior: NotePencilDoubleTapBehavior {
        NotePencilDoubleTapBehavior(rawValue: doubleTapBehaviorRawValue) ?? .switchToEraser
    }
    private var isTextMode: Bool { activeTool == .text }
    private var isTextObjectInteractionMode: Bool { activeTool == .text || activeTool == .select }
    private var isSelectMode: Bool { activeTool == .select }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Body
    // ═══════════════════════════════════════════════════════════

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                noteIndexSidebar
                    .frame(width: 264)

                centerArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if referencePanelOpen, isOnNotePage {
                    referencePanelView
                        .frame(width: 280)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Group {
                if isOnNotePage {
                    noteToolbar
                } else {
                    homeToolbar
                }
            }
            .zIndex(1000)
        }
        .background(WS.surface.ignoresSafeArea())
        .navigationBarHidden(true)
        // ── Selection management ──
        .onChange(of: activeTool) { newTool in
            DispatchQueue.main.async {
                let keepsCanvasTextContext = (newTool == .text || newTool == .select)

                // Legacy text blocks only stay editable in TEXT mode.
                if newTool != .text {
                    if case .textBlock = editorSelection {
                        editorSelection = .none
                        inspectorBlock = nil
                        showTextStylePopover = false
                    }
                }

                // Free-form canvas text objects remain selectable in TEXT / SELECT mode.
                if !keepsCanvasTextContext {
                    if case .textObject = editorSelection {
                        editorSelection = .none
                    }
                }

                // Switching away from select mode clears ink selection
                if newTool != .select, case .inkSelection = editorSelection {
                    editorSelection = .none
                }
            }
        }
        .onChange(of: editorSelection) { newSel in
            // Synchronous — onChange runs after body re-render, safe to modify @State here
            switch newSel {
            case .textBlock(let id):
                inspectorBlock = noteVM?.blocks.first(where: { $0.id == id })
            case .textObject:
                // Text object inspector reads directly from VM, no inspectorBlock needed
                inspectorBlock = nil
                showTextStylePopover = false
            case .none, .inkSelection:
                inspectorBlock = nil
                showTextStylePopover = false
            }
        }
    }

    // ── Actions ──

    private func returnToHome() {
        // Clean up draft if it has no meaningful content
        cleanUpDraftIfEmpty()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            selectedNoteID = nil
            referencePanelOpen = false
        }
    }

    private func openNote(_ noteID: UUID) {
        // Clean up any pending draft before switching to another note
        cleanUpDraftIfEmpty()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            selectedNoteID = noteID
        }
    }

    private func createNewNote() {
        let blankAnchor = SourceAnchor(
            sourceID: UUID(),
            sourceTitle: "",
            pageIndex: nil,
            sentenceID: nil,
            outlineNodeID: nil,
            quotedText: "",
            anchorLabel: ""
        )
        let newNote = Note(
            title: "",
            sourceAnchor: blankAnchor,
            blocks: []
        )
        // Do NOT persist yet — hold in memory as draft
        draftNoteID = newNote.id
        draftNote = newNote
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            selectedNoteID = newNote.id
        }
    }

    /// Called when leaving a note page. If the note is a draft with no content, discard it.
    /// If it has content, persist it and clear the draft state.
    private func handleNotePageDisappear(vm: NoteWorkspaceViewModel) {
        // Sync ink from the live PKCanvasView into VM's blocks before saving
        vm.syncInkFromBridge(inkActionBridge)

        let noteID = vm.note.id

        // Build the latest note state from the VM
        var latestNote = vm.note
        latestNote.title = vm.title.trimmingCharacters(in: .whitespacesAndNewlines)
        latestNote.blocks = vm.blocks
        latestNote.textObjects = vm.textObjects

        if noteID == draftNoteID {
            // This was a draft
            if latestNote.hasMeaningfulContent {
                // User produced content → commit the draft
                appViewModel.persistWorkspaceNote(latestNote)
            }
            // If no meaningful content, simply don't persist → draft vanishes
            draftNoteID = nil
            draftNote = nil
        } else {
            // Existing committed note — save if dirty
            if vm.isDirty {
                _ = vm.save(using: appViewModel)
            }
            // Also clean up committed notes that became empty
            if !latestNote.hasMeaningfulContent {
                appViewModel.deleteNote(latestNote)
            }
        }
    }

    private func cleanUpDraftIfEmpty() {
        guard let draftID = draftNoteID else { return }
        // If the draft was already persisted (by onDisappear), check if it's empty
        if let persisted = appViewModel.note(with: draftID), !persisted.hasMeaningfulContent {
            appViewModel.deleteNote(persisted)
        }
        draftNoteID = nil
        draftNote = nil
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Home Toolbar
    // ═══════════════════════════════════════════════════════════

    private var homeToolbar: some View {
        HStack(spacing: 0) {
            Text("笔记工作区")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(WS.onSurface.opacity(0.75))

            Spacer(minLength: 12)

            Button(action: createNewNote) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("新建笔记")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(WS.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule(style: .continuous).fill(WS.secondaryContainer.opacity(0.3)))
            }
            .buttonStyle(.plain)

            Spacer()

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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            WS.surface.overlay(alignment: .bottom) {
                Rectangle().fill(WS.onSurface.opacity(0.06)).frame(height: 0.5)
            }
        )
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Note Toolbar (shown when editing a note)
    // ═══════════════════════════════════════════════════════════

    private var noteToolbar: some View {
        VStack(spacing: 0) {
            // ═══════════════════════════════════════
            // Layer 1: Tool buttons + ink palette + controls
            // ═══════════════════════════════════════
            HStack(spacing: 0) {
                // ── Left: 返回工作区 ──
                Button(action: returnToHome) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                        Text("返回工作区")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(WS.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule(style: .continuous).fill(WS.secondaryContainer.opacity(0.3)))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                // ── Center: all tool buttons ──
                HStack(spacing: 0) {
                    toolButton(.pen,         icon: "pencil.tip",         label: "钢笔")
                    toolButton(.pencil,      icon: "pencil",             label: "铅笔")
                    toolButton(.ballpoint,   icon: "pencil.line",        label: "圆珠")
                    toolButton(.highlighter, icon: "highlighter",        label: "荧光")
                    toolDivider
                    toolButton(.eraser,      icon: "eraser",             label: "橡皮")
                    toolDivider
                    toolButton(.text,        icon: "character.textbox",  label: "文本")
                    toolButton(.select,      icon: "lasso",              label: "套索")
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule(style: .continuous).fill(WS.surfaceContainerHigh.opacity(0.6)))

                Spacer(minLength: 8)

                // ── Drawing tool palette (color + width) — only when a drawing tool is active ──
                if activeTool.isDrawingTool {
                    inkPaletteStrip
                }

                Spacer(minLength: 8)

                // ── Right: reference toggle + close ──
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            referencePanelOpen.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sidebar.right")
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
            .padding(.vertical, 5)

            // ═══════════════════════════════════════
            // Layer 2: Contextual Inspector
            // ═══════════════════════════════════════
            contextInspectorStrip
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
        }
        .allowsHitTesting(true)
        .contentShape(Rectangle())
        .background(
            WS.surface.overlay(alignment: .bottom) {
                Rectangle().fill(WS.onSurface.opacity(0.06)).frame(height: 0.5)
            }
        )
        .zIndex(1000)
    }

    // ── Ink palette strip: shows active tool's color swatches + width chips ──
    private var inkPaletteStrip: some View {
        HStack(spacing: 4) {
            // Color swatches
            ForEach(inkToolState.activeColorTokens, id: \.self) { token in
                let choice = NoteInkColorChoice(token: token)
                let isActive = token == inkToolState.colorToken
                Circle()
                    .fill(choice.color)
                    .frame(width: 13, height: 13)
                    .overlay {
                        if isActive {
                            Circle().stroke(WS.primary, lineWidth: 1.5)
                                .frame(width: 17, height: 17)
                        }
                    }
                    .onTapGesture { inkToolState.colorToken = token }
            }

            paletteVertDivider

            // Width chips — different for highlighter vs pen
            if activeTool == .highlighter {
                ForEach(HighlighterWidthPreset.allCases) { preset in
                    let isActive = abs(inkToolState.width - preset.width) < 0.5
                    Button { inkToolState.width = preset.width } label: {
                        Circle()
                            .fill(isActive ? WS.primary : WS.onSurface.opacity(0.3))
                            .frame(width: preset.dotSize, height: preset.dotSize)
                            .frame(width: 18, height: 18)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(isActive ? WS.primary.opacity(0.12) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ForEach(PenWidthPreset.allCases) { preset in
                    let isActive = abs(inkToolState.width - preset.width) < 0.5
                    Button { inkToolState.width = preset.width } label: {
                        Circle()
                            .fill(isActive ? WS.primary : WS.onSurface.opacity(0.3))
                            .frame(width: preset.dotSize, height: preset.dotSize)
                            .frame(width: 18, height: 18)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(isActive ? WS.primary.opacity(0.12) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule(style: .continuous).fill(WS.surfaceContainerHigh.opacity(0.5)))
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var paletteVertDivider: some View {
        Rectangle()
            .fill(WS.outlineVariant.opacity(0.3))
            .frame(width: 0.5, height: 16)
            .padding(.horizontal, 2)
    }

    private func toolButton(_ tool: WorkspaceTool, icon: String, label: String) -> some View {
        Button {
            activeTool = tool
            if let inkKind = tool.inkKind {
                inkToolState.switchTo(inkKind)
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
    // MARK: - Contextual Inspector Strip
    // ═══════════════════════════════════════════════════════════

    /// Shows text style controls when in text mode (always visible),
    /// Text inspector is always visible in the toolbar when a note is open.
    /// Ink inspector additionally appears when lasso selects strokes.
    private var contextInspectorStrip: some View {
        Group {
            // Text inspector — for legacy text blocks
            if case .textBlock(let blockID) = editorSelection {
                textInspectorStrip(blockID: blockID)
            }
            // Text object inspector — for free-form canvas text objects
            else if case .textObject(let objID) = editorSelection {
                textObjectInspectorStrip(objectID: objID)
            }
            // Default dim text inspector when no text is selected
            else {
                textInspectorStrip(blockID: nil)
            }

            // Ink inspector — only when lasso has selected strokes
            if case .inkSelection = editorSelection, activeTool == .select {
                inkInspectorStrip
            }
        }
    }

    /// Compact text style inspector: Aa popover • font size • text color • highlight
    /// `blockID` is nil when no text block is focused — controls show defaults and are dimmed.
    private func textInspectorStrip(blockID: UUID?) -> some View {
        let hasFocus = blockID != nil
        return HStack(spacing: 2) {
            // ── Popover trigger (Aa for full BlockStylePicker) ──
            Button {
                showTextStylePopover.toggle()
            } label: {
                Image(systemName: "textformat.size")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(showTextStylePopover ? Color.white : WS.primary)
                    .frame(width: 30, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(showTextStylePopover ? WS.primary : WS.primary.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showTextStylePopover, arrowEdge: .bottom) {
                BlockStylePicker(
                    blockKind: inspectorBlock?.kind ?? .text,
                    textStyle: inspectorStyleBinding(blockID: blockID, keyPath: \.textStyle),
                    textColor: inspectorStyleBinding(blockID: blockID, keyPath: \.textColor),
                    highlightStyle: inspectorStyleBinding(blockID: blockID, keyPath: \.highlightStyle),
                    fontSizePreset: inspectorStyleBinding(blockID: blockID, keyPath: \.fontSizePreset)
                )
            }

            inspectorDivider

            // ── Quick font size chips ──
            ForEach(BlockFontSize.allCases) { size in
                let isActive = inspectorBlock?.fontSizePreset == size
                    || (inspectorBlock?.fontSizePreset == nil && size == .medium)
                Button {
                    applyTextStyle(blockID: blockID, fontSize: size)
                } label: {
                    Text(size.chipLabel)
                        .font(.system(size: 10, weight: isActive ? .bold : .medium))
                        .foregroundStyle(isActive ? Color.white : WS.onSurface.opacity(0.6))
                        .frame(width: 30, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(isActive ? WS.primary : WS.primary.opacity(0.06))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            inspectorDivider

            // ── Quick text color swatches ──
            ForEach(BlockTextColor.allCases) { color in
                let isActive = inspectorBlock?.textColor == color
                    || (inspectorBlock?.textColor == nil && color == BlockStyleMapping.defaultTextColor(for: inspectorBlock?.kind ?? .text))
                Button {
                    applyTextStyle(blockID: blockID, textColor: color)
                } label: {
                    Circle()
                        .fill(BlockStyleMapping.swatchColor(for: color))
                        .frame(width: 14, height: 14)
                        .overlay {
                            if isActive {
                                Circle().stroke(WS.primary, lineWidth: 1.5)
                                    .frame(width: 18, height: 18)
                            }
                        }
                        .frame(width: 30, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            inspectorDivider

            // ── Quick highlight swatches ──
            ForEach(BlockHighlight.allCases) { hl in
                let isActive = inspectorBlock?.highlightStyle == hl
                    || (inspectorBlock?.highlightStyle == nil && hl == .none)
                Button {
                    applyTextStyle(blockID: blockID, highlight: hl)
                } label: {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(hl == .none ? Color.clear : BlockStyleMapping.highlightSwatchColor(for: hl))
                        .frame(width: 14, height: 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(hl == .none ? WS.outline.opacity(0.3) : Color.clear, lineWidth: 0.5)
                        )
                        .overlay {
                            if hl == .none {
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(WS.outline.opacity(0.4))
                            }
                            if isActive && hl != .none {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(WS.onSurface.opacity(0.7))
                            }
                        }
                        .frame(width: 30, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(WS.surfaceContainerHigh.opacity(0.5))
        )
        .opacity(hasFocus ? 1.0 : 0.45)
        .allowsHitTesting(hasFocus)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: blockID)
    }

    /// Text Object inspector: font size • text color • highlight • alignment • delete
    /// Active only when a free-form CanvasTextObject is selected.
    private func textObjectInspectorStrip(objectID: UUID) -> some View {
        let obj = noteVM?.textObject(with: objectID)
        return HStack(spacing: 0) {
            Button {
                showTextStylePopover.toggle()
            } label: {
                Image(systemName: "textformat.size")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(showTextStylePopover ? Color.white : WS.primary)
                    .frame(width: 34, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(showTextStylePopover ? WS.primary : WS.primary.opacity(0.1))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showTextStylePopover, arrowEdge: .bottom) {
                BlockStylePicker(
                    blockKind: .text,
                    textStyle: textObjectStyleBinding(objectID: objectID, keyPath: \.textStyle),
                    textColor: textObjectStyleBinding(objectID: objectID, keyPath: \.textColor),
                    highlightStyle: textObjectStyleBinding(objectID: objectID, keyPath: \.highlightStyle),
                    fontSizePreset: textObjectStyleBinding(objectID: objectID, keyPath: \.fontSizePreset)
                )
            }

            inspectorDivider

            // ── Quick font size chips ──
            ForEach(BlockFontSize.allCases) { size in
                let isActive = obj?.fontSizePreset == size
                    || (obj?.fontSizePreset == nil && size == .medium)
                Button {
                    noteVM?.updateTextObjectStyle(id: objectID, fontSizePreset: size)
                } label: {
                    Text(size.chipLabel)
                        .font(.system(size: 10, weight: isActive ? .bold : .medium))
                        .foregroundStyle(isActive ? Color.white : WS.onSurface.opacity(0.6))
                        .frame(width: 30, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(isActive ? WS.primary : WS.primary.opacity(0.06))
                                .padding(2)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            inspectorDivider

            // ── Quick text color swatches ──
            ForEach(BlockTextColor.allCases) { color in
                let isActive = obj?.textColor == color
                    || (obj?.textColor == nil && color == .inkBlack)
                Button {
                    noteVM?.updateTextObjectStyle(id: objectID, textColor: color)
                } label: {
                    Circle()
                        .fill(BlockStyleMapping.swatchColor(for: color))
                        .frame(width: 14, height: 14)
                        .overlay {
                            if isActive {
                                Circle().stroke(WS.primary, lineWidth: 1.5)
                                    .frame(width: 18, height: 18)
                            }
                        }
                        .frame(width: 30, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            inspectorDivider

            // ── Quick highlight swatches ──
            ForEach(BlockHighlight.allCases) { hl in
                let isActive = obj?.highlightStyle == hl
                    || (obj?.highlightStyle == nil && hl == .none)
                Button {
                    noteVM?.updateTextObjectStyle(id: objectID, highlightStyle: hl)
                } label: {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(hl == .none ? Color.clear : BlockStyleMapping.highlightSwatchColor(for: hl))
                        .frame(width: 14, height: 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(hl == .none ? WS.outline.opacity(0.3) : Color.clear, lineWidth: 0.5)
                        )
                        .overlay {
                            if hl == .none {
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(WS.outline.opacity(0.4))
                            }
                            if isActive && hl != .none {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(WS.onSurface.opacity(0.7))
                            }
                        }
                        .frame(width: 30, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            inspectorDivider

            // ── Alignment ──
            ForEach(CanvasTextAlignment.allCases) { align in
                let isActive = obj?.textAlignment == align
                    || (obj?.textAlignment == nil && align == .leading)
                Button {
                    noteVM?.updateTextObjectStyle(id: objectID, textAlignment: align)
                } label: {
                    Image(systemName: align.icon)
                        .font(.system(size: 11, weight: isActive ? .bold : .regular))
                        .foregroundStyle(isActive ? WS.primary : WS.onSurface.opacity(0.4))
                        .frame(width: 30, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            inspectorDivider

            // ── Delete text object ──
            Button {
                noteVM?.deleteTextObject(id: objectID)
                editorSelection = .none
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WS.error.opacity(0.7))
                    .frame(width: 30, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(WS.error.opacity(0.08))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(WS.surfaceContainerHigh.opacity(0.5))
        )
        .allowsHitTesting(true)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: objectID)
    }

    /// Ink inspector: recolor • rewidth • delete • copy • duplicate
    private var inkInspectorStrip: some View {
        HStack(spacing: 5) {
            Image(systemName: "lasso")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WS.primary.opacity(0.6))

            inspectorDivider

            // ── Recolor: pen colors ──
            ForEach(PenColorPreset.allCases.prefix(6)) { preset in
                Circle()
                    .fill(preset.color)
                    .frame(width: 13, height: 13)
                    .onTapGesture {
                        inkActionBridge.recolorSelection(to: UIColor(preset.color))
                    }
            }

            inspectorDivider

            // ── Rewidth: 3 presets ──
            ForEach(InkWidthPreset.allCases) { preset in
                Button {
                    inkActionBridge.rewidthSelection(to: preset.width)
                } label: {
                    Circle()
                        .fill(WS.onSurface.opacity(0.35))
                        .frame(width: preset.dotSize, height: preset.dotSize)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
            }

            inspectorDivider

            // ── Delete ──
            Button {
                inkActionBridge.deleteSelection()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WS.error.opacity(0.7))
                    .frame(width: 26, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(WS.error.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)

            // ── Copy ──
            Button {
                inkActionBridge.copySelection()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WS.primary.opacity(0.6))
                    .frame(width: 26, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(WS.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)

            // ── Duplicate ──
            Button {
                inkActionBridge.duplicateSelection()
            } label: {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WS.primary.opacity(0.6))
                    .frame(width: 26, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(WS.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(WS.surfaceContainerHigh.opacity(0.5))
        )
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var inspectorDivider: some View {
        Rectangle()
            .fill(WS.outlineVariant.opacity(0.3))
            .frame(width: 0.5, height: 18)
            .padding(.horizontal, 3)
    }

    // ── Style helpers ──

    /// Applies a single text style axis change, keeping other axes as-is.
    private func applyTextStyle(
        blockID: UUID?,
        textStyle: BlockTextStyle? = nil,
        fontSize: BlockFontSize? = nil,
        textColor: BlockTextColor? = nil,
        highlight: BlockHighlight? = nil
    ) {
        guard let blockID, let vm = noteVM else { return }
        let current = vm.blocks.first(where: { $0.id == blockID })
        vm.updateBlockStyle(
            id: blockID,
            textStyle: textStyle ?? current?.textStyle,
            textColor: textColor ?? current?.textColor,
            highlightStyle: highlight ?? current?.highlightStyle,
            fontSizePreset: fontSize ?? current?.fontSizePreset
        )
        // Refresh inspector snapshot so toolbar re-renders
        inspectorBlock = vm.blocks.first(where: { $0.id == blockID })
    }

    /// Binding for the BlockStylePicker popover (reads from inspectorBlock, writes through VM).
    private func inspectorStyleBinding<T: Equatable>(blockID: UUID?, keyPath: WritableKeyPath<NoteBlock, T?>) -> Binding<T?> {
        Binding<T?>(
            get: { inspectorBlock?[keyPath: keyPath] },
            set: { newValue in
                guard let blockID, let vm = noteVM else { return }
                var block = vm.blocks.first(where: { $0.id == blockID }) ?? inspectorBlock
                block?[keyPath: keyPath] = newValue
                vm.updateBlockStyle(
                    id: blockID,
                    textStyle: block?.textStyle,
                    textColor: block?.textColor,
                    highlightStyle: block?.highlightStyle,
                    fontSizePreset: block?.fontSizePreset
                )
                inspectorBlock = vm.blocks.first(where: { $0.id == blockID })
            }
        )
    }

    private func textObjectStyleBinding<T: Equatable>(objectID: UUID, keyPath: WritableKeyPath<CanvasTextObject, T?>) -> Binding<T?> {
        Binding<T?>(
            get: { noteVM?.textObject(with: objectID)?[keyPath: keyPath] },
            set: { newValue in
                guard let vm = noteVM else { return }
                var object = vm.textObject(with: objectID)
                object?[keyPath: keyPath] = newValue
                vm.updateTextObjectStyle(
                    id: objectID,
                    textStyle: object?.textStyle,
                    textColor: object?.textColor,
                    highlightStyle: object?.highlightStyle,
                    fontSizePreset: object?.fontSizePreset,
                    textAlignment: object?.textAlignment
                )
            }
        )
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Left Sidebar: Note Index
    // ═══════════════════════════════════════════════════════════

    private var noteIndexSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("笔记本")
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
                            NoteIndexRow(
                                item: item,
                                isSelected: selectedNoteID == item.noteID,
                                displayMode: selectedTab
                            ) {
                                openNote(item.noteID)
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
    // MARK: - Center Area
    // ═══════════════════════════════════════════════════════════

    @ViewBuilder
    private var centerArea: some View {
        if let note = selectedNote {
            NotebookPageCanvasHost(
                note: note,
                appViewModel: appViewModel,
                inkToolState: $inkToolState,
                isTextMode: isTextMode,
                isSelectMode: isSelectMode,
                isTextObjectInteractionMode: isTextObjectInteractionMode,
                doubleTapBehavior: pencilDoubleTapBehavior,
                onDisappearHandler: { vm in handleNotePageDisappear(vm: vm) },
                activeVM: $noteVM,
                editorSelection: $editorSelection,
                inkActionBridge: inkActionBridge
            )
            .id(note.id)
        } else {
            workspaceHome
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Workspace Home
    // ═══════════════════════════════════════════════════════════

    private var workspaceHome: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 60)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("笔记工作区")
                            .font(.system(size: 28, weight: .medium, design: .serif))
                            .foregroundStyle(WS.onSurface.opacity(0.85))
                        Text("从左侧选择一条笔记，或新建一页开始书写")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(WS.outline.opacity(0.5))
                    }
                    Spacer(minLength: 16)
                    Button(action: createNewNote) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.square")
                                .font(.system(size: 16, weight: .medium))
                            Text("新建笔记")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(WS.primary)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 48)
                .padding(.bottom, 40)

                if !paneItems.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("最近编辑")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(WS.outline.opacity(0.4))
                            .padding(.horizontal, 48)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ], spacing: 14) {
                            ForEach(paneItems.prefix(6)) { item in
                                HomeNoteCard(item: item) {
                                    openNote(item.noteID)
                                }
                            }
                        }
                        .padding(.horizontal, 48)
                    }
                    .padding(.bottom, 32)
                } else {
                    VStack(spacing: 10) {
                        Text("还没有最近编辑的笔记")
                            .font(.system(size: 14, weight: .medium, design: .serif))
                            .foregroundStyle(WS.outline.opacity(0.4))
                        Text("新建一页，开始记录第一条笔记")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(WS.outline.opacity(0.3))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .padding(.bottom, 16)
                }

                HStack(spacing: 16) {
                    statBadge(icon: "doc.text", label: "\(screenModel.totalNoteCount) 条笔记")
                    statBadge(icon: "tray.full", label: "\(screenModel.sourceGroups.count) 份资料")
                    statBadge(icon: "lightbulb", label: "\(screenModel.conceptItems.count) 个概念")
                }
                .padding(.horizontal, 48)

                Spacer(minLength: 100)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(WS.surface)
    }

    private func statBadge(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(WS.outline.opacity(0.35))
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Reference Panel (right)
    // ═══════════════════════════════════════════════════════════

    @ViewBuilder
    private var referencePanelView: some View {
        if let note = selectedNote {
            ReferencePanelHost(
                note: note,
                appViewModel: appViewModel,
                activeTab: $referencePanelActiveTab
            )
            .id(note.id)
        } else {
            EmptyView()
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Workspace Tool
// ═══════════════════════════════════════════════════════════════

private enum WorkspaceTool: String, CaseIterable, Identifiable {
    case pen, pencil, ballpoint, highlighter, eraser, text, select
    var id: String { rawValue }

    /// The corresponding NoteInkToolKind (nil for .text)
    var inkKind: NoteInkToolKind? {
        switch self {
        case .pen: return .pen
        case .pencil: return .pencil
        case .ballpoint: return .ballpoint
        case .highlighter: return .highlighter
        case .eraser: return .eraser
        case .select: return .lasso
        case .text: return nil
        }
    }

    var isDrawingTool: Bool {
        switch self {
        case .pen, .pencil, .ballpoint, .highlighter: return true
        default: return false
        }
    }
}

/// Unified editor selection state — drives the contextual inspector in the toolbar.
enum EditorSelection: Equatable {
    case none
    case textBlock(UUID)       // legacy block ID of the focused text block
    case textObject(UUID)      // free-form canvas text object selected
    case inkSelection          // lasso has selected ink strokes
}

/// Stroke width presets for the Ink Inspector (selected strokes).
private enum InkWidthPreset: String, CaseIterable, Identifiable {
    case thin, medium, thick
    var id: String { rawValue }
    var width: CGFloat {
        switch self { case .thin: return 2; case .medium: return 4; case .thick: return 8 }
    }
    var dotSize: CGFloat {
        switch self { case .thin: return 4; case .medium: return 7; case .thick: return 10 }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - NotebookPageCanvasHost
// ═══════════════════════════════════════════════════════════════

private struct NotebookPageCanvasHost: View {
    let note: Note
    let appViewModel: AppViewModel
    @Binding var inkToolState: NoteInkToolState
    let isTextMode: Bool
    let isSelectMode: Bool
    let isTextObjectInteractionMode: Bool
    let doubleTapBehavior: NotePencilDoubleTapBehavior
    let onDisappearHandler: (NoteWorkspaceViewModel) -> Void
    /// Exposes the VM to the parent so the toolbar inspector can read/write styles.
    @Binding var activeVM: NoteWorkspaceViewModel?
    /// Unified editor selection (text block focus or ink lasso selection).
    @Binding var editorSelection: EditorSelection
    /// Bridge for sending delete/copy actions to the PKCanvasView.
    let inkActionBridge: InkActionBridge

    @StateObject private var vm: NoteWorkspaceViewModel

    init(note: Note,
         appViewModel: AppViewModel,
         inkToolState: Binding<NoteInkToolState>,
         isTextMode: Bool,
         isSelectMode: Bool,
         isTextObjectInteractionMode: Bool,
         doubleTapBehavior: NotePencilDoubleTapBehavior,
         onDisappearHandler: @escaping (NoteWorkspaceViewModel) -> Void,
         activeVM: Binding<NoteWorkspaceViewModel?>,
         editorSelection: Binding<EditorSelection>,
         inkActionBridge: InkActionBridge)
    {
        self.note = note
        self.appViewModel = appViewModel
        self._inkToolState = inkToolState
        self.isTextMode = isTextMode
        self.isSelectMode = isSelectMode
        self.isTextObjectInteractionMode = isTextObjectInteractionMode
        self.doubleTapBehavior = doubleTapBehavior
        self.onDisappearHandler = onDisappearHandler
        self._activeVM = activeVM
        self._editorSelection = editorSelection
        self.inkActionBridge = inkActionBridge
        _vm = StateObject(wrappedValue: NoteWorkspaceViewModel(note: note))
    }

    var body: some View {
        NotebookPageCanvasView(
            vm: vm,
            appViewModel: appViewModel,
            inkToolState: $inkToolState,
            isTextMode: isTextMode,
            isSelectMode: isSelectMode,
            isTextObjectInteractionMode: isTextObjectInteractionMode,
            doubleTapBehavior: doubleTapBehavior,
            editorSelection: $editorSelection,
            inkActionBridge: inkActionBridge,
            onOpenSource: { _ in }
        )
        .onAppear {
            vm.reload(using: appViewModel)
            activeVM = vm
        }
        .onDisappear {
            onDisappearHandler(vm)
            activeVM = nil
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - ReferencePanelHost
// ═══════════════════════════════════════════════════════════════

private struct ReferencePanelHost: View {
    let note: Note
    let appViewModel: AppViewModel
    @Binding var activeTab: ReferencePanelTab

    @StateObject private var vm: NoteWorkspaceViewModel

    init(note: Note,
         appViewModel: AppViewModel,
         activeTab: Binding<ReferencePanelTab>)
    {
        self.note = note
        self.appViewModel = appViewModel
        self._activeTab = activeTab
        _vm = StateObject(wrappedValue: NoteWorkspaceViewModel(note: note))
    }

    var body: some View {
        ReferencePanel(
            vm: vm,
            appViewModel: appViewModel,
            onOpenSource: { _ in },
            activeTab: $activeTab
        )
        .onAppear { vm.reload(using: appViewModel) }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Note Index Row
// ═══════════════════════════════════════════════════════════════

private struct NoteIndexRow: View {
    let item: NotesPaneItem
    let isSelected: Bool
    let displayMode: NotesHomeTab
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? WS.primary : WS.onSurface.opacity(0.7))
                    .lineLimit(1)
                Text(secondaryText)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(WS.outline.opacity(isSelected ? 0.5 : 0.35))
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

    private var secondaryText: String {
        switch displayMode {
        case .recent:
            return timeAgo(item.updatedAt)
        case .source:
            return item.subtitle.components(separatedBy: " · ").first ?? item.subtitle
        case .concept:
            return item.badges.isEmpty ? "" : item.badges.prefix(2).joined(separator: " · ")
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        if interval < 604800 { return "\(Int(interval / 86400)) 天前" }
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f.string(from: date)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Home Note Card
// ═══════════════════════════════════════════════════════════════

private struct HomeNoteCard: View {
    let item: NotesPaneItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WS.onSurface.opacity(0.8))
                    .lineLimit(2)

                if let s = item.summary.nonEmpty {
                    Text(s)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(WS.outline.opacity(0.5))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Text(formattedDate(item.updatedAt))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(WS.outline.opacity(0.3))
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(WS.surfaceContainer.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(WS.outlineVariant.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: date)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Tab Extensions
// ═══════════════════════════════════════════════════════════════

private extension NotesHomeTab {
    var sidebarLabel: String {
        switch self {
        case .recent:  return "最近笔记"
        case .source:  return "按来源"
        case .concept: return "按概念"
        }
    }
    var compactTitle: String {
        switch self {
        case .recent:  return "最近"
        case .source:  return "来源"
        case .concept: return "概念"
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
