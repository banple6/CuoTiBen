import SwiftUI

struct NotesSplitView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    let screenModel: NotesHomeViewModel
    @Binding var selectedTab: NotesHomeTab
    @Binding var searchText: String
    @Binding var activeFilter: NotesFilterMode
    @Binding var selectedNoteID: UUID?
    let onOpenSource: ((SourceAnchor) -> Void)?
    let onOpenWorkspace: ((Note) -> Void)?
    var showsCloseButton: Bool = true
    let onClose: (() -> Void)?

    private var paneItems: [NotesPaneItem] {
        screenModel.paneItems(for: selectedTab)
    }

    private var paneNoteIDs: [UUID] {
        paneItems.map(\.noteID)
    }

    private var selectedNote: Note? {
        guard let selectedNoteID else { return nil }
        return viewModel.note(with: selectedNoteID)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Level 0: surface background
            DigitalArchivistSurface()

            VStack(spacing: 0) {
                // Top NavBar — fixed, surface-colored
                DigitalArchivistTopBar(
                    sourceTitle: selectedNote?.sourceAnchor.sourceTitle,
                    showsCloseButton: showsCloseButton,
                    onClose: onClose
                )

                // Main content area  
                HStack(spacing: 0) {
                    // Left SideNav — surface-container with glassmorphism
                    DigitalArchivistSideNav(
                        screenModel: screenModel,
                        selectedTab: $selectedTab,
                        searchText: $searchText,
                        activeFilter: $activeFilter,
                        selectedNoteID: $selectedNoteID
                    )
                    .frame(width: 264)

                    // Central Paper Canvas
                    NoteDetailPane(
                        note: selectedNote,
                        onOpenSource: onOpenSource,
                        onOpenNote: { note in
                            selectedNoteID = note.id
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Footer bar
                DigitalArchivistFooter()
            }

            // Floating Navigator Panel (right side)
            if let note = selectedNote {
                DigitalArchivistNavigator(note: note)
                    .padding(.top, 80)
                    .padding(.trailing, 8)
            }
        }
        .navigationBarHidden(true)
        .onAppear(perform: selectFirstAvailableNote)
        .onChange(of: selectedTab) { _ in
            selectFirstAvailableNote()
        }
        .onChange(of: paneNoteIDs) { _ in
            syncSelectionIfNeeded()
        }
    }

    private func selectFirstAvailableNote() {
        selectedNoteID = screenModel.firstNoteID(for: selectedTab)
    }

    private func syncSelectionIfNeeded() {
        guard !paneNoteIDs.isEmpty else {
            selectedNoteID = nil
            return
        }

        if let selectedNoteID, paneNoteIDs.contains(selectedNoteID) {
            return
        }

        selectFirstAvailableNote()
    }
}

// MARK: - Design Tokens (local to this file)

private enum DAColor {
    static let surface = Color(red: 251 / 255, green: 249 / 255, blue: 244 / 255)
    static let surfaceContainer = Color(red: 240 / 255, green: 238 / 255, blue: 233 / 255)
    static let surfaceContainerHigh = Color(red: 234 / 255, green: 232 / 255, blue: 227 / 255)
    static let onSurface = Color(red: 27 / 255, green: 28 / 255, blue: 25 / 255)
    static let primary = Color(red: 0 / 255, green: 93 / 255, blue: 167 / 255)
    static let primaryContainer = Color(red: 41 / 255, green: 118 / 255, blue: 199 / 255)
    static let outline = Color(red: 113 / 255, green: 119 / 255, blue: 131 / 255)
    static let outlineVariant = Color(red: 193 / 255, green: 199 / 255, blue: 211 / 255)
    static let secondaryContainer = Color(red: 198 / 255, green: 228 / 255, blue: 244 / 255)
    static let tertiary = Color(red: 89 / 255, green: 97 / 255, blue: 0 / 255)
}

// MARK: - Surface Background

private struct DigitalArchivistSurface: View {
    var body: some View {
        DAColor.surface
            .ignoresSafeArea()
    }
}

// MARK: - Top NavBar

private struct DigitalArchivistTopBar: View {
    let sourceTitle: String?
    let showsCloseButton: Bool
    let onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            // Left: brand + undo/redo
            HStack(spacing: 18) {
                Text("Digital Archivist")
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(DAColor.primary)

                HStack(spacing: 4) {
                    topBarIcon("arrow.uturn.backward")
                    topBarIcon("arrow.uturn.forward")
                }
            }

            Spacer()

            // Center: segmented toolbar (pen/highlighter/eraser + color dots)
            HStack(spacing: 2) {
                ToolSegmentButton(icon: "pencil.tip", label: "Pen", isActive: true)
                ToolSegmentButton(icon: "highlighter", label: "Highlighter", isActive: false)
                ToolSegmentButton(icon: "eraser", label: "Eraser", isActive: false)

                Divider()
                    .frame(height: 22)
                    .padding(.horizontal, 8)
                    .opacity(0.3)

                HStack(spacing: 6) {
                    Circle().fill(DAColor.onSurface).frame(width: 14, height: 14)
                    Circle().fill(DAColor.primary).frame(width: 14, height: 14)
                    Circle().fill(Color(red: 186 / 255, green: 26 / 255, blue: 26 / 255)).frame(width: 14, height: 14)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(DAColor.surfaceContainerHigh)
            )

            Spacer()

            // Right: document title + actions
            HStack(spacing: 14) {
                if let sourceTitle {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(sourceTitle)
                            .font(.system(size: 13, weight: .bold, design: .serif))
                            .foregroundStyle(DAColor.primary)
                            .lineLimit(1)
                    }
                }

                topBarIcon("gearshape")
                topBarIcon("square.and.arrow.up")
                topBarIcon("ellipsis")

                if showsCloseButton, let onClose {
                    topBarIcon("xmark", action: onClose)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(DAColor.surface)
    }

    private func topBarIcon(_ name: String, action: (() -> Void)? = nil) -> some View {
        Button {
            action?()
        } label: {
            Image(systemName: name)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(DAColor.outline)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ToolSegmentButton: View {
    let icon: String
    let label: String
    let isActive: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: isActive ? .semibold : .regular))
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .textCase(.uppercase)
                .tracking(1)
        }
        .foregroundStyle(isActive ? DAColor.primary : DAColor.outline)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(DAColor.primary)
                    .frame(height: 2)
                    .padding(.horizontal, 4)
            }
        }
    }
}

// MARK: - Side Navigation (Left Sidebar)

private struct DigitalArchivistSideNav: View {
    @EnvironmentObject private var viewModel: AppViewModel

    let screenModel: NotesHomeViewModel
    @Binding var selectedTab: NotesHomeTab
    @Binding var searchText: String
    @Binding var activeFilter: NotesFilterMode
    @Binding var selectedNoteID: UUID?

    private var paneItems: [NotesPaneItem] {
        screenModel.paneItems(for: selectedTab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Profile section
            HStack(spacing: 10) {
                Circle()
                    .fill(DAColor.secondaryContainer)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DAColor.primary.opacity(0.7))
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Research Library")
                        .font(.system(size: 13, weight: .bold, design: .serif))
                        .foregroundStyle(DAColor.primary)
                    Text("学术笔记索引")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DAColor.outline)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 20)

            // Nav items
            VStack(spacing: 2) {
                ForEach(NotesHomeTab.allCases) { tab in
                    SideNavItem(
                        icon: tab.sideNavIcon,
                        title: tab.sideNavTitle,
                        isSelected: selectedTab == tab
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(.horizontal, 10)

            // New Document button
            Button {
                // placeholder
            } label: {
                Text("New Document")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(DAColor.primary)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.top, 24)

            Spacer(minLength: 12)

            // Note list (scrollable)
            if paneItems.isEmpty {
                Text("暂无笔记")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DAColor.outline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 20)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(paneItems) { item in
                            SideNavNoteRow(
                                item: item,
                                isSelected: selectedNoteID == item.noteID
                            ) {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    selectedNoteID = item.noteID
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                }
            }

            // Bottom: Settings / Help
            VStack(spacing: 2) {
                SideNavItem(icon: "gearshape", title: "Settings", isSelected: false) {}
                SideNavItem(icon: "questionmark.circle", title: "Help", isSelected: false) {}
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .background(
            DAColor.surfaceContainer.opacity(0.8)
        )
    }
}

private struct SideNavItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isSelected ? DAColor.primary : DAColor.onSurface.opacity(0.65))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? DAColor.primaryContainer.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SideNavNoteRow: View {
    let item: NotesPaneItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? DAColor.primary : DAColor.onSurface.opacity(0.8))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DAColor.outline.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? DAColor.secondaryContainer.opacity(0.4) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Floating Navigator Panel (right side)

private struct DigitalArchivistNavigator: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NAVIGATOR")
                    .font(.system(size: 9, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(DAColor.outline.opacity(0.6))
                Spacer()
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DAColor.primary)
            }

            // Section list
            VStack(alignment: .leading, spacing: 8) {
                NavigatorDot(
                    label: note.sourceAnchor.anchorLabel,
                    subtitle: "Active",
                    isActive: true
                )

                if let pageIndex = note.sourceAnchor.pageIndex {
                    NavigatorDot(
                        label: "第\(pageIndex)页",
                        subtitle: nil,
                        isActive: false
                    )
                    .padding(.leading, 14)
                }

                NavigatorDot(
                    label: "笔记内容",
                    subtitle: "\(note.blocks.count) blocks",
                    isActive: false
                )
                .opacity(0.5)

                NavigatorDot(
                    label: "关联信息",
                    subtitle: nil,
                    isActive: false
                )
                .opacity(0.5)
            }
        }
        .padding(16)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.6))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .shadow(color: DAColor.onSurface.opacity(0.06), radius: 20, x: 0, y: 8)
    }
}

private struct NavigatorDot: View {
    let label: String
    let subtitle: String?
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isActive ? DAColor.primary : DAColor.outline.opacity(0.3))
                .frame(width: isActive ? 7 : 6, height: isActive ? 7 : 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11, weight: isActive ? .bold : .medium))
                    .foregroundStyle(isActive ? DAColor.primary : DAColor.onSurface.opacity(0.6))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DAColor.outline.opacity(0.5))
                }
            }
        }
    }
}

// MARK: - Footer

private struct DigitalArchivistFooter: View {
    var body: some View {
        HStack {
            HStack(spacing: 18) {
                Text("MASTERY: 85%")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(DAColor.tertiary)

                Text("Quick Add")
                    .font(.system(size: 10, weight: .medium))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(DAColor.outline.opacity(0.5))

                Text("Support")
                    .font(.system(size: 10, weight: .medium))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(DAColor.outline.opacity(0.5))
            }

            Spacer()

            Text("Digital Archivist v2.4")
                .font(.system(size: 10, weight: .medium))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(DAColor.outline.opacity(0.4))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 7)
        .background(DAColor.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DAColor.onSurface.opacity(0.08))
                .frame(height: 0.5)
        }
    }
}

// MARK: - NotesHomeTab extensions for sidebar

private extension NotesHomeTab {
    var sideNavIcon: String {
        switch self {
        case .recent: return "list.bullet.indent"
        case .source: return "archivebox"
        case .concept: return "tag"
        }
    }

    var sideNavTitle: String {
        switch self {
        case .recent: return "Structure"
        case .source: return "Archive"
        case .concept: return "Tags"
        }
    }
}
