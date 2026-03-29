import SwiftUI

struct InkAssistSuggestionBubble: View {
    let suggestion: InkAssistSuggestion
    let onLink: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.blue.opacity(0.86))

            VStack(alignment: .leading, spacing: 4) {
                Text("可能关联知识点")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.blue.opacity(0.7))

                Text(suggestion.matchedKnowledgePointTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .lineLimit(2)

                if !suggestion.recognizedText.isEmpty {
                    Text("识别到：\(suggestion.recognizedText)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.54))
                        .lineLimit(1)
                }
            }

            Button("关联") {
                onLink()
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.blue.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.blue.opacity(0.13))
            )
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.97),
                            Color.blue.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.blue.opacity(0.18), lineWidth: 1)
                )
        )
        .shadow(color: Color.blue.opacity(0.12), radius: 16, y: 6)
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
    }
}
