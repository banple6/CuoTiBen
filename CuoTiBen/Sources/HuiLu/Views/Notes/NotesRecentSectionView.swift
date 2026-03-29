import SwiftUI

#if os(iOS)
import UIKit
#endif

struct NotesRecentSectionView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    let items: [NoteSummaryItem]
    let onOpenSource: ((SourceAnchor) -> Void)?

    private var opensWorkspaceDirectly: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "最近新增",
                subtitle: "按最近编辑时间查看学习记录。"
            )

            if items.isEmpty {
                NotesEmptyStateCard(
                    title: "还没有匹配结果",
                    message: "先在句子讲解、单词讲解或节点详情里保存一条笔记。"
                )
            } else {
                ForEach(items) { item in
                    if let note = viewModel.note(with: item.noteID) {
                        NavigationLink {
                            if opensWorkspaceDirectly {
                                NoteNotebookView(note: note, onOpenSource: onOpenSource)
                                    .environmentObject(viewModel)
                            } else {
                                NoteDetailView(note: note, onOpenSource: onOpenSource)
                                    .environmentObject(viewModel)
                            }
                        } label: {
                            RecentNoteRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct RecentNoteRow: View {
    let item: NoteSummaryItem

    var body: some View {
        GlassPanel(tone: .light, cornerRadius: 24, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.84))
                            .lineLimit(2)

                        Text(item.sourceTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.blue.opacity(0.8))
                    }

                    Spacer(minLength: 0)

                    Text(relativeDateString(from: item.updatedAt))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.42))
                }

                Text(item.anchorLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.44))

                Text(item.snippet)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.68))
                    .lineLimit(3)

                HStack(spacing: 8) {
                    if item.hasInk {
                        NotesMetaPill(text: "含手写", tint: .orange)
                    }

                    if let point = item.knowledgePointTitles.first {
                        NotesMetaPill(text: point, tint: .blue)
                    } else if let tag = item.tags.first {
                        NotesMetaPill(text: tag, tint: .green)
                    }
                }
            }
        }
    }
}
