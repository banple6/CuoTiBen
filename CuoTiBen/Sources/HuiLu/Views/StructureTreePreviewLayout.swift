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
        guard let focusNode = index.focusNode(id: highlightedNodeID) else {
            return StructureTreePreviewScene(entries: [], connectors: [], contentRect: CGRect(x: 0, y: 0, width: 480, height: 320))
        }

        let focusPath = index.path(to: focusNode.id)
        guard !focusPath.isEmpty else {
            return StructureTreePreviewScene(entries: [], connectors: [], contentRect: CGRect(x: 0, y: 0, width: 480, height: 320))
        }

        var entries: [StructureTreePreviewScene.Entry] = []
        var connectors: [StructureTreePreviewScene.Connector] = []
        var currentY = metrics.contentInset.height
        var previousMainFrame: CGRect?
        var previousMainNodeID: String?

        for (rowIndex, node) in focusPath.enumerated() {
            let role: StructureTreePreviewNodeRole = node.id == focusNode.id ? .focus : .mainPath
            let mainSize = metrics.cardSize(for: role)
            let mainFrame = CGRect(
                x: metrics.mainColumnX,
                y: currentY,
                width: mainSize.width,
                height: mainSize.height
            )

            entries.append(
                StructureTreePreviewScene.Entry(
                    node: node,
                    frame: mainFrame,
                    role: role,
                    title: clippedText(node.title, limit: metrics.titleCharacterLimit(for: role)),
                    summary: clippedText(node.summary, limit: metrics.summaryCharacterLimit(for: role)),
                    pageBadge: pageBadge(for: node),
                    anchorBadge: anchorBadge(for: node),
                    isHighlighted: node.id == highlightedNodeID,
                    isOnFocusPath: true,
                    hasChildren: !node.children.isEmpty,
                    showsSummary: metrics.summaryLineLimit(for: role) > 0,
                    showsAnchorBadge: true
                )
            )

            if let previousMainFrame, let previousMainNodeID {
                connectors.append(
                    StructureTreePreviewScene.Connector(
                        id: "trunk-\(previousMainNodeID)-\(node.id)",
                        fromNodeID: previousMainNodeID,
                        toNodeID: node.id,
                        start: CGPoint(x: previousMainFrame.minX + 26, y: previousMainFrame.maxY),
                        end: CGPoint(x: mainFrame.minX + 26, y: mainFrame.minY),
                        kind: .trunk
                    )
                )
            }

            let nextPathID = rowIndex + 1 < focusPath.count ? focusPath[rowIndex + 1].id : nil
            let branchNodes = visibleBranchNodes(
                for: node,
                index: index,
                excluding: nextPathID,
                isFocusRow: node.id == focusNode.id,
                expandedNodeIDs: expandedNodeIDs,
                metrics: metrics,
                isRootRow: rowIndex == 0
            )

            var rowBottom = mainFrame.maxY
            if !branchNodes.isEmpty {
                var branchY = currentY + (role == .focus ? 4 : 2)
                let branchX = mainFrame.maxX + metrics.branchColumnSpacing

                for branchNode in branchNodes {
                    let branchRole: StructureTreePreviewNodeRole = .branch
                    let branchSize = metrics.cardSize(for: branchRole)
                    let branchFrame = CGRect(
                        x: branchX,
                        y: branchY,
                        width: branchSize.width,
                        height: branchSize.height
                    )

                    entries.append(
                        StructureTreePreviewScene.Entry(
                            node: branchNode,
                            frame: branchFrame,
                            role: branchRole,
                            title: clippedText(branchNode.title, limit: metrics.titleCharacterLimit(for: branchRole)),
                            summary: clippedText(branchNode.summary, limit: metrics.summaryCharacterLimit(for: branchRole)),
                            pageBadge: pageBadge(for: branchNode),
                            anchorBadge: anchorBadge(for: branchNode),
                            isHighlighted: branchNode.id == highlightedNodeID,
                            isOnFocusPath: false,
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
                            start: CGPoint(x: mainFrame.maxX, y: mainFrame.midY),
                            end: CGPoint(x: branchFrame.minX, y: branchFrame.midY),
                            kind: .branch
                        )
                    )

                    branchY = branchFrame.maxY + metrics.branchNodeSpacing
                    rowBottom = max(rowBottom, branchFrame.maxY)
                }
            }

            previousMainFrame = mainFrame
            previousMainNodeID = node.id
            currentY = rowBottom + metrics.rowSpacing
        }

        let contentRect = sceneRect(
            for: entries.map(\.frame),
            metrics: metrics,
            fallback: CGRect(x: 0, y: 0, width: 520, height: 340)
        )

        return StructureTreePreviewScene(entries: entries, connectors: connectors, contentRect: contentRect)
    }

    static func overviewScene(
        nodes: [OutlineNode],
        highlightedNodeID: String?,
        densityMode: StructureTreePreviewDensityMode
    ) -> StructureTreePreviewOverviewScene {
        let index = StructureTreePreviewIndex(nodes: nodes)
        let heightStep: CGFloat = densityMode == .detailed ? 7 : 6
        let depthStep: CGFloat = densityMode == .detailed ? 12 : 10
        var built: [StructureTreePreviewOverviewScene.Entry] = []
        var cursorY: CGFloat = 10

        func append(_ node: OutlineNode) {
            let width = max(18, 56 - CGFloat(min(node.depth, 4)) * 6)
            let height: CGFloat = node.id == highlightedNodeID ? 12 : 8
            let frame = CGRect(
                x: 10 + CGFloat(max(node.depth, 0)) * depthStep,
                y: cursorY,
                width: width,
                height: height
            )
            built.append(
                StructureTreePreviewOverviewScene.Entry(
                    node: node,
                    frame: frame,
                    isHighlighted: node.id == highlightedNodeID
                )
            )
            cursorY = frame.maxY + heightStep
            for child in node.children.sorted(by: { $0.order < $1.order }) {
                append(child)
            }
        }

        for node in index.roots {
            append(node)
        }

        let contentRect = sceneRect(
            for: built.map(\.frame),
            metrics: StructureTreePreviewMetrics(densityMode: densityMode),
            fallback: CGRect(x: 0, y: 0, width: 120, height: 160)
        )

        return StructureTreePreviewOverviewScene(entries: built, contentRect: contentRect)
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
        excluding nextPathID: String?,
        isFocusRow: Bool,
        expandedNodeIDs: Set<String>,
        metrics: StructureTreePreviewMetrics,
        isRootRow: Bool
    ) -> [OutlineNode] {
        var candidates: [OutlineNode] = []

        candidates.append(contentsOf: index.children(of: node.id).filter { $0.id != nextPathID })

        var deduplicated: [OutlineNode] = []
        var seen: Set<String> = []
        for candidate in candidates.sorted(by: { $0.order < $1.order }) where !seen.contains(candidate.id) {
            seen.insert(candidate.id)
            deduplicated.append(candidate)
        }

        let limit: Int
        if expandedNodeIDs.contains(node.id) {
            limit = metrics.expandedBranchLimit
        } else if isFocusRow {
            limit = metrics.focusedCollapsedBranchLimit
        } else if isRootRow {
            limit = max(metrics.collapsedBranchLimit, 1)
        } else {
            limit = metrics.collapsedBranchLimit
        }

        return Array(deduplicated.prefix(limit))
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
            x: 0,
            y: 0,
            width: max(union.maxX + metrics.trailingInset, fallback.width),
            height: max(union.maxY + metrics.bottomInset, fallback.height)
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
