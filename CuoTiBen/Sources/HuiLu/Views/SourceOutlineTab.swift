import SwiftUI

struct SourceOutlineTab: View {
    let nodes: [OutlineNode]
    let highlightedNodeID: String?
    let jumpTargetNodeID: String?
    let ancestorNodeIDs: [String]
    let onNodeTap: (OutlineNode) -> Void
    let onJumpHandled: () -> Void
    @State private var expandedNodeIDs: Set<String> = []
    @State private var hasAppliedInitialExpansion = false

    var body: some View {
        ScrollViewReader { proxy in
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(nodes) { node in
                    OutlineTreeNodeRow(
                        node: node,
                        highlightedNodeID: highlightedNodeID,
                        expandedNodeIDs: $expandedNodeIDs,
                        onNodeTap: onNodeTap
                    )
                }
            }
            .onAppear {
                applyInitialExpansionIfNeeded()
                expandAncestors()
                scrollToHighlightedNode(with: proxy, animated: false)
                if jumpTargetNodeID != nil {
                    onJumpHandled()
                }
            }
            .onChange(of: ancestorNodeIDs) { _ in
                expandAncestors()
            }
            .onChange(of: nodes) { _ in
                applyInitialExpansionIfNeeded(force: true)
            }
            .onChange(of: jumpTargetNodeID) { target in
                guard target != nil else { return }
                expandAncestors()
                scrollToHighlightedNode(with: proxy, animated: true)
                onJumpHandled()
            }
        }
    }

    private func applyInitialExpansionIfNeeded(force: Bool = false) {
        guard force || !hasAppliedInitialExpansion else { return }
        expandedNodeIDs = allExpandableNodeIDs(from: nodes)
        hasAppliedInitialExpansion = true
    }

    private func expandAncestors() {
        expandedNodeIDs.formUnion(ancestorNodeIDs)
        if let highlightedNodeID {
            expandedNodeIDs.insert(highlightedNodeID)
        }
    }

    private func scrollToHighlightedNode(with proxy: ScrollViewProxy, animated: Bool) {
        guard let targetID = jumpTargetNodeID ?? highlightedNodeID else { return }

        let action = {
            proxy.scrollTo(targetID, anchor: .center)
        }

        if animated {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                action()
            }
        } else {
            action()
        }
    }

    private func allExpandableNodeIDs(from nodes: [OutlineNode]) -> Set<String> {
        var results: Set<String> = []

        func walk(_ currentNodes: [OutlineNode]) {
            for node in currentNodes {
                if !node.children.isEmpty {
                    results.insert(node.id)
                    walk(node.children)
                }
            }
        }

        walk(nodes)
        return results
    }
}

private struct OutlineTreeNodeRow: View {
    let node: OutlineNode
    let highlightedNodeID: String?
    @Binding var expandedNodeIDs: Set<String>
    let onNodeTap: (OutlineNode) -> Void

    private var isExpanded: Bool {
        expandedNodeIDs.contains(node.id)
    }

    private var isHighlighted: Bool {
        highlightedNodeID == node.id
    }

    private var normalizedDepth: Int {
        max(node.depth, 0)
    }

    private var isTopLevelNode: Bool {
        normalizedDepth == 0
    }

    private var titleFont: Font {
        switch normalizedDepth {
        case 0:
            return .system(size: 19, weight: .heavy, design: .rounded)
        case 1:
            return .system(size: 17, weight: .bold, design: .rounded)
        default:
            return .system(size: 15, weight: .semibold, design: .rounded)
        }
    }

    private var summaryFont: Font {
        switch normalizedDepth {
        case 0:
            return .system(size: 14, weight: .medium)
        case 1:
            return .system(size: 13.5, weight: .medium)
        default:
            return .system(size: 13, weight: .medium)
        }
    }

    private var rowPadding: CGFloat {
        switch normalizedDepth {
        case 0:
            return 20
        case 1:
            return 17
        default:
            return 15
        }
    }

    private var childIndent: CGFloat {
        switch normalizedDepth {
        case 0:
            return 28
        case 1:
            return 24
        default:
            return 20
        }
    }

    private var titleColor: Color {
        isHighlighted ? Color.blue.opacity(0.92) : Color.black.opacity(0.82)
    }

    private var summaryColor: Color {
        isHighlighted ? Color.black.opacity(0.7) : Color.black.opacity(0.58)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                hierarchyRail

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        disclosureView
                        outlineNodeButton
                    }

                    if isExpanded && !node.children.isEmpty {
                        childNodesSection
                    }
                }
            }
        }
        .padding(rowPadding)
        .background(nodeBackground)
        .id(node.id)
    }

    private var childNodesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(node.children) { child in
                OutlineTreeNodeRow(
                    node: child,
                    highlightedNodeID: highlightedNodeID,
                    expandedNodeIDs: $expandedNodeIDs,
                    onNodeTap: onNodeTap
                )
            }
        }
        .padding(.leading, childIndent)
    }

    @ViewBuilder
    private var disclosureView: some View {
        if !node.children.isEmpty {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    if isExpanded {
                        expandedNodeIDs.remove(node.id)
                    } else {
                        expandedNodeIDs.insert(node.id)
                    }
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.blue.opacity(0.75))
            }
            .buttonStyle(.plain)
        } else {
            Circle()
                .fill(isHighlighted ? Color.blue.opacity(0.75) : Color.blue.opacity(0.26))
                .frame(width: 10, height: 10)
                .padding(.top, 9)
        }
    }

    private var outlineNodeButton: some View {
        Button {
            onNodeTap(node)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                hierarchyBadge

                Text(node.title)
                    .font(titleFont)
                    .foregroundStyle(titleColor)
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)

                Text(node.summary)
                    .font(summaryFont)
                    .foregroundStyle(summaryColor)
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)

                anchorBadge
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var hierarchyBadge: some View {
        Text(levelLabel)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(levelLabelColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(levelLabelBackground)
            )
    }

    private var anchorBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 10, weight: .bold))

            Text(node.anchor.label)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(Color.blue.opacity(isHighlighted ? 0.9 : 0.74))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color.blue.opacity(isHighlighted ? 0.14 : 0.09))
        )
    }

    private var hierarchyRail: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(hierarchyLineColor)
                .frame(width: 2)
                .padding(.vertical, isTopLevelNode ? 6 : 2)

            Circle()
                .fill(hierarchyDotColor)
                .frame(width: isTopLevelNode ? 12 : 9, height: isTopLevelNode ? 12 : 9)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                )
                .padding(.top, isTopLevelNode ? 10 : 14)
        }
        .frame(width: 14)
        .opacity(isTopLevelNode ? 0.95 : 0.85)
    }

    private var hierarchyLineColor: Color {
        if isHighlighted {
            return Color.blue.opacity(0.34)
        }

        return normalizedDepth == 0 ? Color.blue.opacity(0.22) : Color.blue.opacity(0.14)
    }

    private var hierarchyDotColor: Color {
        if isHighlighted {
            return Color.blue.opacity(0.82)
        }

        return normalizedDepth == 0 ? Color.blue.opacity(0.5) : Color.blue.opacity(0.34)
    }

    private var levelLabel: String {
        switch normalizedDepth {
        case 0:
            return "一级节点"
        case 1:
            return "二级节点"
        default:
            return "子节点"
        }
    }

    private var levelLabelColor: Color {
        normalizedDepth == 0 ? Color.blue.opacity(0.82) : Color.black.opacity(0.58)
    }

    private var levelLabelBackground: Color {
        if isHighlighted {
            return Color.blue.opacity(0.16)
        }

        return normalizedDepth == 0 ? Color.blue.opacity(0.1) : Color.white.opacity(0.68)
    }

    private var nodeBackground: some View {
        RoundedRectangle(cornerRadius: normalizedDepth == 0 ? 24 : 20, style: .continuous)
            .fill(nodeFillColor)
            .overlay(
                RoundedRectangle(cornerRadius: normalizedDepth == 0 ? 24 : 20, style: .continuous)
                    .stroke(
                        nodeStrokeColor,
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Color.black.opacity(normalizedDepth == 0 ? 0.06 : 0.03),
                radius: normalizedDepth == 0 ? 20 : 12,
                x: 0,
                y: normalizedDepth == 0 ? 10 : 6
            )
    }

    private var nodeFillColor: Color {
        if isHighlighted {
            return Color.blue.opacity(normalizedDepth == 0 ? 0.14 : 0.12)
        }

        return normalizedDepth == 0 ? Color.white.opacity(0.72) : Color.white.opacity(0.58)
    }

    private var nodeStrokeColor: Color {
        if isHighlighted {
            return Color.blue.opacity(0.32)
        }

        return normalizedDepth == 0 ? Color.white.opacity(0.92) : Color.white.opacity(0.82)
    }
}
