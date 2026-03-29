import SwiftUI

struct QuoteBlockView: View {
    let block: NoteBlock
    let sourceAnchor: SourceAnchor
    var onOpenSource: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                HStack(spacing: 8) {
                    NotesMetaPill(text: "引用", tint: .orange)
                    NotesMetaPill(text: sourceAnchor.anchorLabel, tint: .blue)
                    if let pageIndex = sourceAnchor.pageIndex {
                        NotesMetaPill(text: "第\(pageIndex)页", tint: .purple)
                    }
                }

                Spacer(minLength: 0)

                if let onOpenSource {
                    Button {
                        onOpenSource()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.forward.square")
                            Text("回到原文")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.blue.opacity(0.86))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.76))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(resolvedText)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.82))
                .lineSpacing(6)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppPalette.amber.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(AppPalette.amber.opacity(0.22), lineWidth: 1)
                )
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(AppPalette.amber.opacity(0.42))
                .frame(width: 4)
                .padding(.vertical, 18)
                .padding(.leading, 10)
        }
    }

    private var resolvedText: String {
        let candidate = block.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return candidate.isEmpty ? sourceAnchor.quotedText : candidate
    }
}

struct QuoteBlockView_Previews: PreviewProvider {
    static var previews: some View {
        QuoteBlockView(
            block: .quote("The committee concluded that further research was necessary."),
            sourceAnchor: SourceAnchor(
                sourceID: UUID(),
                sourceTitle: "English Reading",
                pageIndex: 1,
                sentenceID: "sentence-1",
                outlineNodeID: "node-1",
                quotedText: "The committee concluded that further research was necessary.",
                anchorLabel: "第1页 第3句"
            ),
            onOpenSource: {}
        )
        .padding()
        .background(AppBackground(style: .light))
    }
}
