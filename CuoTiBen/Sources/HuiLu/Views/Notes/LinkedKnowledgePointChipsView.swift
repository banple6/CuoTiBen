import SwiftUI

struct LinkedKnowledgePointChipsView: View {
    let points: [KnowledgePoint]
    let onSelect: (KnowledgePoint) -> Void
    var onOpenSource: ((KnowledgePoint) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("关联知识点")
                .font(.system(size: 13, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(AppPalette.paperMuted)

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
                WashiKnowledgeChip(
                    title: point.title,
                    tint: AppPalette.paperTapeBlue.opacity(0.28),
                    foreground: WorkspaceColors.primaryInk
                )
            }
            .buttonStyle(.plain)

            if let onOpenSource, !point.sourceAnchors.isEmpty {
                Button {
                    onOpenSource(point)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WorkspaceColors.primaryInk.opacity(0.86))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppPalette.paperCard.opacity(0.84))
                                .rotationEffect(.degrees(stableRotation(for: point.id + "-source")))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func stableRotation(for key: String) -> Double {
        let hash = key.unicodeScalars.reduce(0) { partial, scalar in
            partial + Int(scalar.value)
        }
        let normalized = Double((hash % 5) - 2)
        return normalized * 0.45
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

struct WashiKnowledgeChip: View {
    let title: String
    let tint: Color
    let foreground: Color

    private var angle: Double {
        let hash = title.unicodeScalars.reduce(0) { partial, scalar in
            partial + Int(scalar.value)
        }
        let normalized = Double((hash % 5) - 2)
        return normalized * 0.45
    }

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(foreground.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint)
                    .overlay {
                        NotebookGrid(spacing: 9)
                            .opacity(0.08)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
            )
            .rotationEffect(.degrees(angle))
            .shadow(color: WorkspaceColors.paperShadow, radius: 6, x: 0, y: 2)
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
