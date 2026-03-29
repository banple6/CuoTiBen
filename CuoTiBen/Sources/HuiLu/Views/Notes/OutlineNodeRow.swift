import SwiftUI

struct OutlinePathView: View {
    let nodes: [OutlineNode]

    var body: some View {
        if nodes.isEmpty {
            Text("当前没有明确结构路径")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.42))
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                        Text(node.title)
                            .font(.system(size: 12, weight: index == nodes.count - 1 ? .bold : .semibold))
                            .foregroundStyle(index == nodes.count - 1 ? Color.blue.opacity(0.88) : Color.black.opacity(0.58))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(index == nodes.count - 1 ? Color.blue.opacity(0.12) : Color.white.opacity(0.65))
                            )

                        if index < nodes.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.28))
                        }
                    }
                }
            }
        }
    }
}

struct OutlineNodeRow: View {
    let node: OutlineNode
    let isCurrent: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(isCurrent ? Color.blue.opacity(0.9) : Color.blue.opacity(0.35))
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(node.depth == 0 ? "一级节点" : "二级节点")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.42))

                        Text(node.anchor.label)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.blue.opacity(0.8))
                    }

                    Text(node.title)
                        .font(.system(size: node.depth == 0 ? 16 : 14, weight: .bold))
                        .foregroundStyle(isCurrent ? Color.blue.opacity(0.9) : Color.black.opacity(0.8))
                        .multilineTextAlignment(.leading)

                    Text(node.summary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.56))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, CGFloat(node.depth) * 12)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isCurrent ? Color.blue.opacity(0.12) : Color.white.opacity(0.54))
            )
        }
        .buttonStyle(.plain)
    }
}
