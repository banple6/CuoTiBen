import SwiftUI

struct NotesListPane: View {
    let screenModel: NotesHomeViewModel
    @Binding var selectedTab: NotesHomeTab
    @Binding var searchText: String
    @Binding var activeFilter: NotesFilterMode
    @Binding var selectedNoteID: UUID?
    var showsCloseButton: Bool = true
    let onClose: (() -> Void)?

    private var paneItems: [NotesPaneItem] {
        screenModel.paneItems(for: selectedTab)
    }

    var body: some View {
        VStack(spacing: 16) {
            NotesHeaderBar(
                searchText: $searchText,
                activeFilter: $activeFilter,
                totalCount: screenModel.totalNoteCount,
                filteredCount: screenModel.filteredNoteCount,
                showsCloseButton: showsCloseButton,
                onClose: onClose
            )

            NotesSegmentedControl(selectedTab: $selectedTab)

            GlassPanel(tone: .light, cornerRadius: 30, padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader(
                        title: paneTitle,
                        subtitle: paneSubtitle
                    )

                    if paneItems.isEmpty {
                        NotesEmptyStateCard(
                            title: paneEmptyTitle,
                            message: paneEmptyMessage
                        )
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 10) {
                                ForEach(paneItems) { item in
                                    Button {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                            selectedNoteID = item.noteID
                                        }
                                    } label: {
                                        NoteListRow(
                                            item: item,
                                            isSelected: selectedNoteID == item.noteID
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.bottom, 6)
                        }
                    }
                }
            }
        }
    }

    private var paneTitle: String {
        switch selectedTab {
        case .recent:
            return "最近"
        case .source:
            return "资料"
        case .concept:
            return "知识点"
        }
    }

    private var paneSubtitle: String {
        switch selectedTab {
        case .recent:
            return "保留轻量索引，右侧查看完整笔记。"
        case .source:
            return "按资料回看笔记，右栏承接完整阅读。"
        case .concept:
            return "按关联知识点筛出可继续整理的笔记。"
        }
    }

    private var paneEmptyTitle: String {
        switch selectedTab {
        case .recent:
            return "暂无最近笔记"
        case .source:
            return "暂无资料笔记"
        case .concept:
            return "暂无知识点笔记"
        }
    }

    private var paneEmptyMessage: String {
        switch selectedTab {
        case .recent:
            return "先在句子讲解、单词讲解或节点详情里保存一条笔记。"
        case .source:
            return "保存至少一条笔记后，这里会按资料继续整理。"
        case .concept:
            return "给笔记挂上知识点后，这里会列出可直接复盘的笔记。"
        }
    }
}
