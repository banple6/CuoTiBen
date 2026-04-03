import SwiftUI

enum NoteBlockPresentationStyle {
    case card
    case editorial
}

struct QuoteBlockView: View {
    let block: NoteBlock
    let sourceAnchor: SourceAnchor
    var presentationStyle: NoteBlockPresentationStyle = .card
    var onOpenSource: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                HStack(spacing: 8) {
                    Text("QUOTE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(AppPalette.primaryDeep.opacity(0.85))
                    Rectangle()
                        .fill(AppPalette.paperLine)
                        .frame(width: 1, height: 12)
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
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppPalette.primaryDeep.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppPalette.paperTapeBlue.opacity(0.16))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(resolvedText)
                .font(.system(size: 20, weight: .medium, design: .serif))
                .foregroundStyle(AppPalette.paperInk.opacity(0.88))
                .italic()
                .lineSpacing(9)
        }
        .padding(.horizontal, presentationStyle == .editorial ? 0 : 24)
        .padding(.vertical, presentationStyle == .editorial ? 10 : 22)
        .background(backgroundView)
        .overlay(alignment: .topLeading, content: quoteMarkOverlay)
        .overlay(alignment: .leading, content: editorialRuleOverlay)
        .shadow(color: presentationStyle == .editorial ? .clear : Color.black.opacity(0.04), radius: 16, y: 8)
    }

    private var resolvedText: String {
        let candidate = block.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return candidate.isEmpty ? sourceAnchor.quotedText : candidate
    }

    @ViewBuilder
    private var backgroundView: some View {
        if presentationStyle == .editorial {
            Color.clear
        } else {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppPalette.paperCard.opacity(0.94))
        }
    }

    @ViewBuilder
    private func quoteMarkOverlay() -> some View {
        if presentationStyle == .card {
            Text("“")
                .font(.system(size: 60, weight: .bold, design: .serif))
                .foregroundStyle(AppPalette.paperTape.opacity(0.34))
                .padding(.leading, 12)
                .padding(.top, -8)
        }
    }

    @ViewBuilder
    private func editorialRuleOverlay() -> some View {
        if presentationStyle == .editorial {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(AppPalette.paperTapeBlue.opacity(0.46))
                .frame(width: 4)
                .padding(.vertical, 6)
                .offset(x: -18)
        }
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
