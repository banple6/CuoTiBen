import SwiftUI

struct LinkedKnowledgePointChipsView: View {
    let points: [KnowledgePoint]
    let onSelect: (KnowledgePoint) -> Void
    var onOpenSource: ((KnowledgePoint) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("关联知识点")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.76))

            if points.isEmpty {
                Text("当前笔记还没有关联知识点。")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.45))
            } else {
                FlexibleChipFlow(items: points) { point in
                    chipRow(for: point)
                }
            }
        }
    }

    private func chipRow(for point: KnowledgePoint) -> some View {
        HStack(spacing: 6) {
            Button {
                onSelect(point)
            } label: {
                NotesMetaPill(text: point.title, tint: .blue)
            }
            .buttonStyle(.plain)

            if let onOpenSource, !point.sourceAnchors.isEmpty {
                Button {
                    onOpenSource(point)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.blue.opacity(0.86))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.76))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct FlexibleChipFlow<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let items: Data
    let content: (Data.Element) -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(Array(items), id: \.id) { item in
                content(item)
            }
        }
    }
}

struct LinkedKnowledgePointChipsView_Previews: PreviewProvider {
    static var previews: some View {
        LinkedKnowledgePointChipsView(
            points: [
                KnowledgePoint(title: "宾语从句", shortDefinition: "that 引导作宾语"),
                KnowledgePoint(title: "政策表达", shortDefinition: "英语政策语境常见搭配")
            ],
            onSelect: { _ in }
        )
        .padding()
        .background(AppBackground(style: .light))
    }
}
