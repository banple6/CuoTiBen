import SwiftUI

struct TextBlockEditorView: View {
    @Binding var text: String
    var title: String = "文本"
    var isHighlighted: Bool = false
    var minimumHeight: CGFloat = 160
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                NotesMetaPill(text: title, tint: .green)
                if isHighlighted {
                    NotesMetaPill(text: "当前定位", tint: .blue)
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
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.8))
                .frame(minHeight: minimumHeight)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(isHighlighted ? 0.92 : 0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(isHighlighted ? Color.blue.opacity(0.32) : Color.black.opacity(0.05), lineWidth: 1)
                )
        )
        .overlay(alignment: .topLeading) {
            Capsule(style: .continuous)
                .fill(Color.green.opacity(0.18))
                .frame(width: 64, height: 5)
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
