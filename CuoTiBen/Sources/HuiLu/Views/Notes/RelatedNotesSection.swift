import SwiftUI

struct RelatedNotesSection: View {
    let notes: [Note]
    let onOpenNote: (Note) -> Void

    var body: some View {
        RelatedContextSectionContainer(title: "相关笔记") {
            VStack(spacing: 10) {
                ForEach(Array(notes.prefix(4).enumerated()), id: \.element.id) { index, note in
                    Button {
                        onOpenNote(note)
                    } label: {
                        RelatedContextCompactRow(isLast: index == min(notes.count, 4) - 1) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.black.opacity(0.8))
                                    .lineLimit(2)

                                Text(note.sourceAnchor.anchorLabel)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.46))
                            }
                        } trailing: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.34))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
