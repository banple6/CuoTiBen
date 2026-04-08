import SwiftUI

#if os(iOS)
import UIKit
#endif

struct NotesHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: AppViewModel

    let onOpenSource: ((SourceAnchor) -> Void)?
    var showsCloseButton: Bool = true

    @State private var selectedTab: NotesHomeTab = .recent
    @State private var searchText = ""
    @State private var activeFilter: NotesFilterMode = .all
    @State private var screenModel = NotesHomeViewModel.empty

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        Group {
            if isPad {
                // Single persistent workspace — no NavigationStack, no push layers
                NotebookWorkspaceView(
                    screenModel: screenModel,
                    selectedTab: $selectedTab,
                    searchText: $searchText,
                    activeFilter: $activeFilter,
                    showsCloseButton: showsCloseButton,
                    onClose: showsCloseButton ? { dismiss() } : nil,
                    onOpenSource: onOpenSource
                )
            } else {
                phoneBody
            }
        }
        .onAppear(perform: syncScreenModel)
        .onChange(of: viewModel.notes) { _ in
            syncScreenModel()
        }
        .onChange(of: viewModel.sourceDocuments) { _ in
            syncScreenModel()
        }
        .onChange(of: searchText) { _ in
            syncScreenModel()
        }
        .onChange(of: activeFilter) { _ in
            syncScreenModel()
        }
    }

    private var phoneBody: some View {
        NavigationStack {
            ZStack {
                PaperCanvasBackground()

                VStack(spacing: 16) {
                    NotesHeaderBar(
                        searchText: $searchText,
                        activeFilter: $activeFilter,
                        totalCount: screenModel.totalNoteCount,
                        filteredCount: screenModel.filteredNoteCount,
                        showsCloseButton: showsCloseButton,
                        onClose: showsCloseButton ? { dismiss() } : nil
                    )

                    NotesSegmentedControl(selectedTab: $selectedTab)

                    ScrollView(showsIndicators: false) {
                        currentSection
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: selectedTab)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationBarHidden(true)
        }
    }

    @ViewBuilder
    private var currentSection: some View {
        switch selectedTab {
        case .recent:
            NotesRecentSectionView(
                items: screenModel.recentItems,
                onOpenSource: onOpenSource
            )
        case .source:
            NotesBySourceSectionView(
                groups: screenModel.sourceGroups,
                onOpenSource: onOpenSource
            )
        case .concept:
            NotesByConceptSectionView(
                items: screenModel.conceptItems,
                onOpenSource: onOpenSource
            )
        }
    }
    private func syncScreenModel() {
        let committedNotes = viewModel.notes.filter { $0.hasMeaningfulContent }
        screenModel = NotesHomeViewModel(
            notes: committedNotes,
            sourceDocuments: viewModel.sourceDocuments,
            searchText: searchText,
            activeFilter: activeFilter
        )
    }
}
