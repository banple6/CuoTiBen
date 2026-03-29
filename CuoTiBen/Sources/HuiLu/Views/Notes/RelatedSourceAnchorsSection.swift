import SwiftUI

struct RelatedSourceAnchorsSection: View {
    let anchors: [SourceAnchor]
    let onOpenSourceAnchor: (SourceAnchor) -> Void

    var body: some View {
        RelatedContextSectionContainer(title: "相关来源") {
            VStack(spacing: 10) {
                ForEach(Array(anchors.prefix(4).enumerated()), id: \.element.id) { index, anchor in
                    Button {
                        onOpenSourceAnchor(anchor)
                    } label: {
                        RelatedContextCompactRow(isLast: index == min(anchors.count, 4) - 1) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(anchor.anchorLabel)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.blue.opacity(0.78))

                                Text(anchor.quotedText)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.56))
                                    .lineLimit(2)
                            }
                        } trailing: {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.blue.opacity(0.58))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
