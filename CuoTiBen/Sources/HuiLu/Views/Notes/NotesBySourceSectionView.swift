import SwiftUI

#if os(iOS)
import UIKit
#endif

struct NotesBySourceSectionView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    let groups: [SourceNoteGroup]
    let onOpenSource: ((SourceAnchor) -> Void)?

    private var opensWorkspaceDirectly: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "按资料查看",
                subtitle: "同一份资料下的笔记自动归档。"
            )

            if groups.isEmpty {
                NotesEmptyStateCard(
                    title: "暂无资料分组",
                    message: "保存至少一条笔记后，这里会按资料自动归档。"
                )
            } else {
                ForEach(groups) { group in
                    GlassPanel(tone: .light, cornerRadius: 26, padding: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(group.sourceTitle)
                                        .font(.system(size: 19, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color.black.opacity(0.84))
                                        .lineLimit(2)

                                    Text(group.subtitle)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Color.black.opacity(0.54))
                                }

                                Spacer(minLength: 0)

                                VStack(alignment: .trailing, spacing: 6) {
                                    NotesMetaPill(text: "\(group.noteCount) 条", tint: .blue)
                                    Text(relativeDateString(from: group.updatedAt))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.black.opacity(0.42))
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(group.previewItems) { item in
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
                                            HStack(alignment: .top, spacing: 10) {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(item.title)
                                                        .font(.system(size: 15, weight: .bold))
                                                        .foregroundStyle(Color.black.opacity(0.8))
                                                        .lineLimit(1)
                                                    Text(item.anchorLabel)
                                                        .font(.system(size: 12, weight: .semibold))
                                                        .foregroundStyle(Color.black.opacity(0.44))
                                                }

                                                Spacer(minLength: 0)

                                                if item.hasInk {
                                                    Image(systemName: "pencil.tip.crop.circle")
                                                        .font(.system(size: 15, weight: .bold))
                                                        .foregroundStyle(Color.orange.opacity(0.78))
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .fill(Color.white.opacity(0.72))
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
