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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode == .structure ? "Navigator" : "Mind Map")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(WorkspaceColors.textSecondary)

                    Text(sourceTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WorkspaceColors.textSecondary.opacity(0.76))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button(action: onCycleState) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WorkspaceColors.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(.regularMaterial, in: Circle())
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
        .padding(14)
        .frame(width: 236)
        .background(panelBackground)
    }

    private var structureContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("当前路径")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WorkspaceColors.textSecondary)

                OutlinePathView(nodes: context.pathNodes)
            }

            if let currentNode = context.currentNode {
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前节点")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WorkspaceColors.textSecondary)

                    OutlineNodeRow(node: currentNode, isCurrent: true) {
                        onSelectNode(currentNode.id)
                    }
                }
            }

            if !context.nearbyNodes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("邻近节点")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WorkspaceColors.textSecondary)

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
                .foregroundStyle(WorkspaceColors.textSecondary)

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
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(mode == item ? WorkspaceColors.primaryInk : WorkspaceColors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(mode == item ? WorkspaceColors.primaryInk.opacity(0.1) : WorkspaceColors.paperCanvas.opacity(0.2))
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
                    .foregroundStyle(WorkspaceColors.textSecondary)

                Text(context.currentNode?.title ?? "展开导航")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WorkspaceColors.textPrimary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button(action: onCycleState) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WorkspaceColors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 168)
        .background(panelBackground)
    }

    private var hiddenButton: some View {
        Button(action: onCycleState) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.indent")
                Text("结构树")
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(WorkspaceColors.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(panelBackground)
        }
        .buttonStyle(.plain)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(WorkspaceColors.paperCanvas.opacity(0.14))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: WorkspaceColors.paperShadow, radius: 32, x: 0, y: 8)
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
                .fill(WorkspaceColors.paperCanvas.opacity(0.24))
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
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
                    .fill(tint.opacity(isPrimary ? 0.16 : 0.09))
            )
        }
        .buttonStyle(.plain)
    }
}
