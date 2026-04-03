import SwiftUI

#if os(iOS)
import UIKit
#endif

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

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        Group {
            if isPad {
                archivistPadBody
            } else {
                phonePaneBody
            }
        }
    }

    private var phonePaneBody: some View {
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

            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(
                    title: paneTitle,
                    subtitle: paneSubtitle
                )

                listContent
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.56))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.84), lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        PaperTapeAccent(color: AppPalette.paperTapeBlue, width: 78, height: 18)
                            .offset(x: 26, y: -8)
                    }
            )
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 10)
        }
    }

    private var archivistPadBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Collections")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(4)
                    .foregroundStyle(Color.white.opacity(0.5))

                Text("学术笔记索引")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.92))
            }

            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.42))

                    TextField("搜索 archive…", text: $searchText)
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundStyle(.white)
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.white.opacity(0.1), in: Capsule())

                Menu {
                    ForEach(NotesFilterMode.allCases) { filter in
                        Button(filter.title) {
                            activeFilter = filter
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                ForEach(NotesHomeTab.allCases) { tab in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.title)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .textCase(.uppercase)
                            .tracking(1.8)
                            .foregroundStyle(selectedTab == tab ? ArchivistColors.primaryInk : Color.white.opacity(0.62))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selectedTab == tab ? Color.white.opacity(0.92) : Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(paneSubtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.48))
                .padding(.bottom, 2)

            listContent
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if paneItems.isEmpty {
            NotesEmptyStateCard(
                title: paneEmptyTitle,
                message: paneEmptyMessage
            )
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: isPad ? 14 : 8) {
                    ForEach(paneItems) { item in
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                selectedNoteID = item.noteID
                            }
                        } label: {
                            NoteListRow(
                                item: item,
                                isSelected: selectedNoteID == item.noteID,
                                style: isPad ? .archivistIndexCard : .paperCard
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 6)
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
