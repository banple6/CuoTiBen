import SwiftUI

struct RelatedKnowledgePointsSection: View {
    let knowledgePoints: [KnowledgePoint]
    let onOpenKnowledgePoint: (KnowledgePoint) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 130), spacing: 8)
    ]

    var body: some View {
        RelatedContextSectionContainer(title: "相关知识点") {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(knowledgePoints.prefix(6)) { point in
                    Button {
                        onOpenKnowledgePoint(point)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(point.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.78))
                                .lineLimit(2)

                            if let summary = compactDefinition(point) {
                                Text(summary)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.46))
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.blue.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private func compactDefinition(_ point: KnowledgePoint) -> String? {
    let text = (point.shortDefinition ?? point.definition).trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
}
