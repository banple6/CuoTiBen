import SwiftUI

struct RelatedCardsSection: View {
    let cards: [LearningRecordCardItem]
    let onOpenCard: (LearningRecordCardItem) -> Void

    var body: some View {
        RelatedContextSectionContainer(title: "相关卡片") {
            VStack(spacing: 10) {
                ForEach(Array(cards.prefix(4).enumerated()), id: \.element.id) { index, item in
                    Button {
                        onOpenCard(item)
                    } label: {
                        RelatedContextCompactRow(isLast: index == min(cards.count, 4) - 1) {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Text(item.chunkTitle)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Color.black.opacity(0.8))
                                        .lineLimit(2)

                                    if item.card.isDraft {
                                        Text("草稿")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color.orange.opacity(0.9))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Capsule().fill(Color.orange.opacity(0.14)))
                                    }
                                }

                                Text(item.chunkSummary)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.54))
                                    .lineLimit(2)

                                if let anchorLabel = item.anchorLabel {
                                    Text(anchorLabel)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.black.opacity(0.4))
                                }
                            }
                        } trailing: {
                            Image(systemName: "rectangle.stack.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.purple.opacity(0.52))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
