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
        ZStack {
            ArchivistNotesDeskBackground()

            VStack(spacing: 0) {
                ArchivistNotesTopBar(
                    selectedTab: selectedTab,
                    showsCloseButton: showsCloseButton,
                    onClose: onClose
                )
                .padding(.horizontal, 28)
                .padding(.top, 18)

                HStack(alignment: .top, spacing: 28) {
                    NotesListPane(
                        screenModel: screenModel,
                        selectedTab: $selectedTab,
                        searchText: $searchText,
                        activeFilter: $activeFilter,
                        selectedNoteID: $selectedNoteID,
                        showsCloseButton: false,
                        onClose: nil
                    )
                    .frame(width: 332)

                    NoteDetailPane(
                        note: selectedNote,
                        onOpenSource: onOpenSource,
                        onOpenWorkspace: onOpenWorkspace,
                        onOpenNote: { note in
                            selectedNoteID = note.id
                        }
                    )
                    .frame(maxWidth: 980, maxHeight: .infinity, alignment: .topLeading)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 28)
                .padding(.top, 26)
                .padding(.bottom, 28)
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

private struct ArchivistNotesDeskBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [ArchivistColors.deskMatStart, ArchivistColors.deskMatEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            NotebookGrid(spacing: 24)
                .opacity(0.035)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    .clear,
                    Color.black.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

private struct ArchivistNotesTopBar: View {
    let selectedTab: NotesHomeTab
    let showsCloseButton: Bool
    let onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Digital Archivist")
                    .font(.system(size: 24, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(Color.white.opacity(0.9))

                Text(selectedTabTitle)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(3)
                    .foregroundStyle(Color.white.opacity(0.42))
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                toolbarButton(icon: "magnifyingglass")
                toolbarButton(icon: "square.and.arrow.up")
                toolbarButton(icon: "ellipsis")

                if showsCloseButton, let onClose {
                    toolbarButton(icon: "xmark", action: onClose)
                }
            }
        }
    }

    private var selectedTabTitle: String {
        switch selectedTab {
        case .recent:
            return "Active Notebooks"
        case .source:
            return "Source Archives"
        case .concept:
            return "Knowledge Index"
        }
    }

    private func toolbarButton(icon: String, action: (() -> Void)? = nil) -> some View {
        Button {
            action?()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.84))
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }
}
