import SwiftUI

struct NoteOutlineFloatingPanel: View {
    let state: NoteOutlineFloatingPanelState
    @Binding var mode: NoteOutlineFloatingPanelMode
    let sourceTitle: String
    let context: WorkspaceOutlineContext
    let onSelectNode: (String?) -> Void
    let onCycleState: () -> Void

    var body: some View {
        switch state {
        case .expanded:
            expandedPanel
        case .compact:
            compactPanel
        case .hidden:
            hiddenButton
        }
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode == .structure ? "结构树导航" : "导图导航")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.82))

                    Text(sourceTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.46))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button(action: onCycleState) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.62))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.76)))
                }
                .buttonStyle(.plain)
            }

            panelModePicker

            if mode == .structure {
                structureContent
            } else {
                mindMapContent
            }
        }
        .padding(18)
        .frame(width: 332)
        .background(panelBackground)
    }

    private var structureContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("当前路径")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.68))

                OutlinePathView(nodes: context.pathNodes)
            }

            if let currentNode = context.currentNode {
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前节点")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.68))

                    OutlineNodeRow(node: currentNode, isCurrent: true) {
                        onSelectNode(currentNode.id)
                    }
                }
            }

            if !context.nearbyNodes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("邻近节点")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.68))

                    ForEach(context.nearbyNodes) { node in
                        OutlineNodeRow(node: node, isCurrent: node.id == context.currentNode?.id) {
                            onSelectNode(node.id)
                        }
                    }
                }
            }
        }
    }

    private var mindMapContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("当前路径")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.68))

            OutlinePathView(nodes: context.pathNodes)

            WorkspaceMindMapPreview(
                currentNode: context.currentNode,
                pathNodes: context.pathNodes,
                nearbyNodes: context.nearbyNodes,
                onSelectNode: onSelectNode
            )
        }
    }

    private var panelModePicker: some View {
        HStack(spacing: 8) {
            ForEach(NoteOutlineFloatingPanelMode.allCases) { item in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        mode = item
                    }
                } label: {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(mode == item ? Color.blue.opacity(0.88) : Color.black.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(mode == item ? Color.blue.opacity(0.14) : Color.white.opacity(0.7))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var compactPanel: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(mode == .structure ? "结构树" : "导图")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.44))

                Text(context.currentNode?.title ?? "展开导航")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.78))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button(action: onCycleState) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.62))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.76)))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 220)
        .background(panelBackground)
    }

    private var hiddenButton: some View {
        Button(action: onCycleState) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.indent")
                Text("结构树")
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.72))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(panelBackground)
        }
        .buttonStyle(.plain)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.white.opacity(0.74))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.92), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 18, y: 8)
    }
}

private struct WorkspaceMindMapPreview: View {
    let currentNode: OutlineNode?
    let pathNodes: [OutlineNode]
    let nearbyNodes: [OutlineNode]
    let onSelectNode: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let currentNode {
                VStack(alignment: .leading, spacing: 12) {
                    if !pathNodes.dropLast().isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(pathNodes.dropLast()), id: \.id) { node in
                                miniNode(node, tint: .cyan, isPrimary: false)
                            }
                        }
                    }

                    miniNode(currentNode, tint: .blue, isPrimary: true)

                    if !nearbyNodes.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(nearbyNodes.prefix(3)) { node in
                                miniNode(node, tint: .mint, isPrimary: false)
                            }
                        }
                    }
                }
            } else {
                Text("当前还没有定位到明确结构节点。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.46))
                    .padding(.vertical, 18)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.58))
        )
    }

    private func miniNode(_ node: OutlineNode, tint: Color, isPrimary: Bool) -> some View {
        Button {
            onSelectNode(node.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(node.title)
                    .font(.system(size: isPrimary ? 15 : 12.5, weight: .bold))
                    .foregroundStyle(isPrimary ? Color.blue.opacity(0.9) : Color.black.opacity(0.76))
                    .multilineTextAlignment(.leading)
                    .lineLimit(isPrimary ? 3 : 2)

                Text(node.anchor.label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint.opacity(0.84))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tint.opacity(isPrimary ? 0.14 : 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(tint.opacity(isPrimary ? 0.24 : 0.14), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
