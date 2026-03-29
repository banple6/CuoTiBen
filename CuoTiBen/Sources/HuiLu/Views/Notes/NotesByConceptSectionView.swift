import SwiftUI

struct NotesByConceptSectionView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    let items: [ConceptSummaryItem]
    let onOpenSource: ((SourceAnchor) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "按知识点查看",
                subtitle: "先索引，再进入知识点详情承接定义、原句和笔记。"
            )

            if items.isEmpty {
                NotesEmptyStateCard(
                    title: "暂无知识点索引",
                    message: "给笔记挂上知识点后，这里会显示更稳定的知识点摘要。"
                )
            } else {
                ForEach(items) { item in
                    if let point = viewModel.knowledgePoint(with: item.knowledgePointID) {
                        NavigationLink {
                            KnowledgePointDetailView(point: point, onOpenSource: onOpenSource)
                                .environmentObject(viewModel)
                        } label: {
                            ConceptSummaryCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct ConceptSummaryCard: View {
    let item: ConceptSummaryItem

    var body: some View {
        GlassPanel(tone: .light, cornerRadius: 24, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.84))
                            .lineLimit(2)

                        if let previewSourceTitle = item.previewSourceTitle {
                            Text(previewSourceTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.blue.opacity(0.78))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 6) {
                        NotesMetaPill(text: "\(item.noteCount) 条笔记", tint: .blue)
                        NotesMetaPill(text: "\(item.sourceCount) 份资料", tint: .green)
                    }
                }

                Text(item.definition)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.62))
                    .lineLimit(3)

                if !item.relatedPointTitles.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(item.relatedPointTitles.prefix(2), id: \.self) { title in
                            NotesMetaPill(text: title, tint: .purple)
                        }
                    }
                }
            }
        }
    }
}
