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
            PaperCanvasBackground()

            HStack(spacing: 20) {
                NotesListPane(
                    screenModel: screenModel,
                    selectedTab: $selectedTab,
                    searchText: $searchText,
                    activeFilter: $activeFilter,
                    selectedNoteID: $selectedNoteID,
                    showsCloseButton: showsCloseButton,
                    onClose: onClose
                )
                .frame(width: 324)

                NoteDetailPane(
                    note: selectedNote,
                    onOpenSource: onOpenSource,
                    onOpenWorkspace: onOpenWorkspace,
                    onOpenNote: { note in
                        selectedNoteID = note.id
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
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
