import SwiftUI

struct StructureTreePreviewScene {
    struct Entry: Identifiable {
        let node: OutlineNode
        let frame: CGRect
        let role: StructureTreePreviewNodeRole
        let title: String
        let summary: String
        let pageBadge: String?
        let anchorBadge: String?
        let isHighlighted: Bool
        let isOnFocusPath: Bool
        let hasChildren: Bool
        let showsSummary: Bool
        let showsAnchorBadge: Bool

        var id: String { node.id }
    }

    struct Connector: Identifiable {
        enum Kind {
            case trunk
            case branch
        }

        let id: String
        let fromNodeID: String
        let toNodeID: String
        let start: CGPoint
        let end: CGPoint
        let kind: Kind
    }

    let entries: [Entry]
    let connectors: [Connector]
    let contentRect: CGRect

    func entry(id: String) -> Entry? {
        entries.first(where: { $0.id == id })
    }
}

struct StructureTreePreviewOverviewScene {
    struct Entry: Identifiable {
        let node: OutlineNode
        let frame: CGRect
        let isHighlighted: Bool

        var id: String { node.id }
    }

    let entries: [Entry]
    let contentRect: CGRect
}

enum StructureTreePreviewLayout {
    static func displayScene(
        nodes: [OutlineNode],
        highlightedNodeID: String?,
        densityMode: StructureTreePreviewDensityMode,
        expandedNodeIDs: Set<String>
    ) -> StructureTreePreviewScene {
        let metrics = StructureTreePreviewMetrics(densityMode: densityMode)
        let index = StructureTreePreviewIndex(nodes: nodes)
        guard let rootNode = index.roots.first else {
            return StructureTreePreviewScene(entries: [], connectors: [], contentRect: CGRect(x: 0, y: 0, width: 480, height: 320))
        }
        let focusNode = index.focusNode(id: highlightedNodeID) ?? rootNode
        let focusPathIDs = Set(index.path(to: focusNode.id).map(\.id))

        var entries: [StructureTreePreviewScene.Entry] = []
        var connectors: [StructureTreePreviewScene.Connector] = []
        let rootRole: StructureTreePreviewNodeRole = .focus
        let rootFrame = centeredFrame(
            center: .zero,
            size: metrics.cardSize(for: rootRole)
        )
        entries.append(
            StructureTreePreviewScene.Entry(
                node: rootNode,
                frame: rootFrame,
                role: rootRole,
                title: clippedText(rootNode.title, limit: metrics.titleCharacterLimit(for: rootRole)),
                summary: clippedText(rootNode.summary, limit: metrics.summaryCharacterLimit(for: rootRole)),
                pageBadge: pageBadge(for: rootNode),
                anchorBadge: anchorBadge(for: rootNode),
                isHighlighted: rootNode.id == highlightedNodeID,
                isOnFocusPath: focusPathIDs.contains(rootNode.id),
                hasChildren: !rootNode.children.isEmpty,
                showsSummary: metrics.summaryLineLimit(for: rootRole) > 0,
                showsAnchorBadge: false
            )
        )

        let primaryNodes = index.children(of: rootNode.id)
        let paragraphCount = max(primaryNodes.count, 1)
        let primaryRadius = metrics.paragraphRingRadius(for: primaryNodes.count)
        let startAngle = -CGFloat.pi / 2
        let stepAngle = (2 * CGFloat.pi) / CGFloat(paragraphCount)

        for (rowIndex, node) in primaryNodes.enumerated() {
            let angle = startAngle + stepAngle * CGFloat(rowIndex)
            let role: StructureTreePreviewNodeRole = .mainPath
            let frame = centeredFrame(
                center: CGPoint(
                    x: cos(angle) * primaryRadius,
                    y: sin(angle) * primaryRadius
                ),
                size: metrics.cardSize(for: role)
            )

            entries.append(
                StructureTreePreviewScene.Entry(
                    node: node,
                    frame: frame,
                    role: role,
                    title: clippedText(node.title, limit: metrics.titleCharacterLimit(for: role)),
                    summary: clippedText(node.summary, limit: metrics.summaryCharacterLimit(for: role)),
                    pageBadge: pageBadge(for: node),
                    anchorBadge: anchorBadge(for: node),
                    isHighlighted: node.id == highlightedNodeID,
                    isOnFocusPath: focusPathIDs.contains(node.id),
                    hasChildren: !node.children.isEmpty,
                    showsSummary: metrics.summaryLineLimit(for: role) > 0,
                    showsAnchorBadge: true
                )
            )
            connectors.append(
                StructureTreePreviewScene.Connector(
                    id: "trunk-\(rootNode.id)-\(node.id)",
                    fromNodeID: rootNode.id,
                    toNodeID: node.id,
                    start: edgePoint(from: rootFrame, toward: frame),
                    end: edgePoint(from: frame, toward: rootFrame),
                    kind: .trunk
                )
            )

            let branchNodes = visibleBranchNodes(
                for: node,
                index: index,
                highlightedNodeID: highlightedNodeID,
                expandedNodeIDs: expandedNodeIDs,
                metrics: metrics
            )
            guard !branchNodes.isEmpty else { continue }

            let secondaryRadius = primaryRadius + metrics.childRingGap
            let sectorAngle = metrics.paragraphSectorAngle(for: primaryNodes.count)
            let spreadAngle = branchNodes.count == 1 ? 0 : sectorAngle
            let childStep = branchNodes.count <= 1 ? 0 : spreadAngle / CGFloat(max(branchNodes.count - 1, 1))
            let childStartAngle = angle - spreadAngle / 2

            for (childIndex, branchNode) in branchNodes.enumerated() {
                let childAngle = branchNodes.count == 1
                    ? angle
                    : childStartAngle + childStep * CGFloat(childIndex)
                let branchRole: StructureTreePreviewNodeRole = .branch
                let childFrame = centeredFrame(
                    center: CGPoint(
                        x: cos(childAngle) * secondaryRadius,
                        y: sin(childAngle) * secondaryRadius
                    ),
                    size: metrics.cardSize(for: branchRole)
                )

                entries.append(
                    StructureTreePreviewScene.Entry(
                        node: branchNode,
                        frame: childFrame,
                        role: branchRole,
                        title: clippedText(branchNode.title, limit: metrics.titleCharacterLimit(for: branchRole)),
                        summary: clippedText(branchNode.summary, limit: metrics.summaryCharacterLimit(for: branchRole)),
                        pageBadge: pageBadge(for: branchNode),
                        anchorBadge: anchorBadge(for: branchNode),
                        isHighlighted: branchNode.id == highlightedNodeID,
                        isOnFocusPath: focusPathIDs.contains(branchNode.id),
                        hasChildren: !branchNode.children.isEmpty,
                        showsSummary: metrics.summaryLineLimit(for: branchRole) > 0,
                        showsAnchorBadge: true
                    )
                )
                connectors.append(
                    StructureTreePreviewScene.Connector(
                        id: "branch-\(node.id)-\(branchNode.id)",
                        fromNodeID: node.id,
                        toNodeID: branchNode.id,
                        start: edgePoint(from: frame, toward: childFrame),
                        end: edgePoint(from: childFrame, toward: frame),
                        kind: .branch
                    )
                )
            }
        }

        let contentRect = sceneRect(
            for: entries.map(\.frame),
            metrics: metrics,
            fallback: CGRect(x: 0, y: 0, width: 520, height: 340)
        )

        return StructureTreePreviewScene(entries: entries, connectors: connectors, contentRect: contentRect)
    }

    static func overviewScene(from scene: StructureTreePreviewScene) -> StructureTreePreviewOverviewScene {
        StructureTreePreviewOverviewScene(
            entries: scene.entries.map {
                StructureTreePreviewOverviewScene.Entry(
                    node: $0.node,
                    frame: $0.frame,
                    isHighlighted: $0.isHighlighted
                )
            },
            contentRect: scene.contentRect
        )
    }

    static func ancestorPathIDs(in nodes: [OutlineNode], to highlightedNodeID: String?) -> [String] {
        let index = StructureTreePreviewIndex(nodes: nodes)
        return index.path(to: highlightedNodeID).dropLast().map(\.id)
    }

    static func focusNodeID(in nodes: [OutlineNode], highlightedNodeID: String?) -> String? {
        StructureTreePreviewIndex(nodes: nodes).focusNode(id: highlightedNodeID)?.id
    }

    private static func visibleBranchNodes(
        for node: OutlineNode,
        index: StructureTreePreviewIndex,
        highlightedNodeID: String?,
        expandedNodeIDs: Set<String>,
        metrics: StructureTreePreviewMetrics
    ) -> [OutlineNode] {
        let highlightedChildID = index.path(to: highlightedNodeID).dropFirst().first { $0.parentID == node.id }?.id
        let candidates = index.children(of: node.id)

        var deduplicated: [OutlineNode] = []
        var seen: Set<String> = []
        let sortedCandidates = candidates.sorted { lhs, rhs in
            if lhs.branchDisplayPriority != rhs.branchDisplayPriority {
                return lhs.branchDisplayPriority < rhs.branchDisplayPriority
            }
            if lhs.isAuxiliaryNode != rhs.isAuxiliaryNode {
                return !lhs.isAuxiliaryNode && rhs.isAuxiliaryNode
            }
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.id < rhs.id
        }
        for candidate in sortedCandidates where !seen.contains(candidate.id) {
            seen.insert(candidate.id)
            deduplicated.append(candidate)
        }

        let limit: Int
        if expandedNodeIDs.contains(node.id) {
            limit = metrics.expandedBranchLimit
        } else if highlightedChildID != nil {
            limit = metrics.focusedCollapsedBranchLimit
        } else {
            limit = metrics.collapsedBranchLimit
        }

        let preferredCandidates = deduplicated.filter { !$0.isAuxiliaryNode }
        let source = preferredCandidates.isEmpty ? deduplicated : preferredCandidates + deduplicated.filter(\.isAuxiliaryNode)
        var visible = Array(source.prefix(limit))
        if let highlightedChildID,
           let highlightedChild = deduplicated.first(where: { $0.id == highlightedChildID }),
           !visible.contains(where: { $0.id == highlightedChildID }) {
            if visible.isEmpty {
                visible.append(highlightedChild)
            } else {
                visible[visible.count - 1] = highlightedChild
            }
        }

        return visible
    }

    private static func pageBadge(for node: OutlineNode) -> String? {
        guard let page = node.anchor.page else { return nil }
        return "第\(page)页"
    }

    private static func anchorBadge(for node: OutlineNode) -> String? {
        let trimmed = normalizedText(node.anchor.label)
        guard !trimmed.isEmpty else { return nil }
        return clippedText(trimmed, limit: 10)
    }

    private static func sceneRect(
        for frames: [CGRect],
        metrics: StructureTreePreviewMetrics,
        fallback: CGRect
    ) -> CGRect {
        guard let first = frames.first else { return fallback }
        let union = frames.dropFirst().reduce(first) { partial, frame in
            partial.union(frame)
        }
        return CGRect(
            x: min(union.minX - metrics.contentInset.width, fallback.minX),
            y: min(union.minY - metrics.contentInset.height, fallback.minY),
            width: max(union.width + metrics.contentInset.width + metrics.trailingInset, fallback.width),
            height: max(union.height + metrics.contentInset.height + metrics.bottomInset, fallback.height)
        )
    }

    private static func centeredFrame(center: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func edgePoint(from sourceFrame: CGRect, toward targetFrame: CGRect) -> CGPoint {
        let sourceCenter = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        let targetCenter = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        let deltaX = targetCenter.x - sourceCenter.x
        let deltaY = targetCenter.y - sourceCenter.y

        guard deltaX != 0 || deltaY != 0 else { return sourceCenter }

        let halfWidth = sourceFrame.width / 2
        let halfHeight = sourceFrame.height / 2
        let scale = min(
            halfWidth / max(abs(deltaX), 0.001),
            halfHeight / max(abs(deltaY), 0.001)
        )

        return CGPoint(
            x: sourceCenter.x + deltaX * scale,
            y: sourceCenter.y + deltaY * scale
        )
    }

    private static func clippedText(_ value: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = normalizedText(value)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(max(limit - 1, 0))) + "…"
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct StructureTreePreviewIndex {
    let roots: [OutlineNode]
    let nodesByID: [String: OutlineNode]
    let childrenByID: [String: [OutlineNode]]
    let parentByID: [String: String?]

    init(nodes: [OutlineNode]) {
        roots = nodes.sorted(by: { $0.order < $1.order })
        var nodesByID: [String: OutlineNode] = [:]
        var childrenByID: [String: [OutlineNode]] = [:]
        var parentByID: [String: String?] = [:]

        func visit(_ node: OutlineNode, parentID: String?) {
            nodesByID[node.id] = node
            parentByID[node.id] = parentID
            childrenByID[node.id] = node.children.sorted(by: { $0.order < $1.order })
            for child in node.children {
                visit(child, parentID: node.id)
            }
        }

        for root in roots {
            visit(root, parentID: nil)
        }

        self.nodesByID = nodesByID
        self.childrenByID = childrenByID
        self.parentByID = parentByID
    }

    func focusNode(id: String?) -> OutlineNode? {
        if let id, let node = nodesByID[id] {
            return node
        }
        return roots.first
    }

    func children(of id: String) -> [OutlineNode] {
        childrenByID[id] ?? []
    }

    func path(to id: String?) -> [OutlineNode] {
        guard let focusNode = focusNode(id: id) else { return [] }
        var pathIDs: [String] = [focusNode.id]
        var cursor = parentByID[focusNode.id] ?? nil

        while let parentID = cursor {
            pathIDs.append(parentID)
            cursor = parentByID[parentID] ?? nil
        }

        return pathIDs
            .reversed()
            .compactMap { nodesByID[$0] }
    }
}
