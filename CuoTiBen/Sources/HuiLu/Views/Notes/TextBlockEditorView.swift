import SwiftUI

struct TextBlockEditorView: View {
    @Binding var text: String
    var title: String = "文本"
    var isHighlighted: Bool = false
    var minimumHeight: CGFloat = 160
    var presentationStyle: NoteBlockPresentationStyle = .card
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(AppPalette.paperMuted)
                if isHighlighted {
                    NotesMetaPill(text: "当前定位", tint: AppPalette.paperTapeBlue)
                }
                Spacer(minLength: 0)
                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.red.opacity(0.82))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.red.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            TextEditor(text: $text)
                .font(
                    presentationStyle == .editorial
                    ? .system(size: 19, weight: .regular, design: .serif)
                    : .system(size: 18, weight: .regular)
                )
                .foregroundStyle(AppPalette.paperInk.opacity(0.82))
                .frame(minHeight: minimumHeight)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
        }
        .padding(.horizontal, presentationStyle == .editorial ? 0 : 24)
        .padding(.vertical, presentationStyle == .editorial ? 12 : 22)
        .background(backgroundView)
        .overlay(alignment: .topLeading) {
            topAccent
        }
        .overlay(alignment: .leading) {
            if presentationStyle == .editorial {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill((isHighlighted ? AppPalette.paperTapeBlue : AppPalette.paperHighlightMint).opacity(0.36))
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .offset(x: -18)
            }
        }
        .shadow(color: presentationStyle == .editorial ? .clear : Color.black.opacity(isHighlighted ? 0.05 : 0.03), radius: 14, y: 8)
    }

    @ViewBuilder
    private var backgroundView: some View {
        if presentationStyle == .editorial {
            Color.clear
        } else {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isHighlighted ? AppPalette.paperCard : Color.white.opacity(0.82))
        }
    }

    @ViewBuilder
    private var topAccent: some View {
        if presentationStyle == .editorial {
            Rectangle()
                .fill((isHighlighted ? AppPalette.paperTapeBlue : AppPalette.paperHighlightMint).opacity(0.44))
                .frame(width: 96, height: 4)
                .padding(.top, 6)
        } else {
            Capsule(style: .continuous)
                .fill(isHighlighted ? AppPalette.paperTapeBlue.opacity(0.72) : AppPalette.paperHighlightMint.opacity(0.62))
                .frame(width: 72, height: 6)
                .padding(.top, 12)
                .padding(.leading, 18)
        }
    }
}

struct TextBlockEditorView_Previews: PreviewProvider {
    static var previews: some View {
        TextBlockEditorPreview()
    }
}

private struct TextBlockEditorPreview: View {
    @State private var text = "这里继续扩写结构化理解的思路，把引用、笔记正文和手写联想串起来。"

    var body: some View {
        TextBlockEditorView(text: $text, isHighlighted: true)
            .padding()
            .background(AppBackground(style: .light))
    }
}
