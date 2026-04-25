import CoreGraphics
import Foundation

enum MindMapDensityMode: String, CaseIterable, Identifiable {
    case compact = "紧凑"
    case detailed = "详细"

    var id: String { rawValue }
}

struct MindMapLayoutEdge: Identifiable, Equatable {
    let id: String
    let fromNodeID: String
    let toNodeID: String
    let start: CGPoint
    let end: CGPoint
    let control: CGPoint
}

struct MindMapLayoutSnapshot: Equatable {
    let containerSize: CGSize
    let contentBoundingRect: CGRect
    let nodeFrames: [String: CGRect]
    let edgePaths: [MindMapLayoutEdge]
    let orderedNodeIDs: [String]
    let density: MindMapDensityMode
    let simplified: Bool

    static let empty = MindMapLayoutSnapshot(
        containerSize: .zero,
        contentBoundingRect: CGRect(x: 0, y: 0, width: 1, height: 1),
        nodeFrames: [:],
        edgePaths: [],
        orderedNodeIDs: [],
        density: .detailed,
        simplified: false
    )

    func focusRect(for nodeID: String) -> CGRect {
        guard let frame = nodeFrames[nodeID] else { return contentBoundingRect }
        return frame.insetBy(dx: -84, dy: -72)
    }

    func visibleNodeIDs(in visibleRect: CGRect) -> [String] {
        let paddedRect = visibleRect.insetBy(dx: -180, dy: -180)
        return orderedNodeIDs.filter { nodeID in
            guard let frame = nodeFrames[nodeID] else { return false }
            return frame.intersects(paddedRect)
        }
    }
}

enum MindMapLayout {
    static func makeLayout(
        rootNode: MindMapNode?,
        density: MindMapDensityMode,
        containerSize: CGSize,
        simplified: Bool,
        expandedParagraphNodeID: String?
    ) -> MindMapLayoutSnapshot {
        guard let rootNode else { return .empty }

        let metrics = Metrics(density: density, simplified: simplified)
        var logicalFrames: [String: CGRect] = [:]
        var edges: [MindMapLayoutEdge] = []
        var orderedIDs: [String] = []

        let rootCenter = CGPoint(x: 0, y: 0)
        logicalFrames[rootNode.id] = centeredRect(center: rootCenter, size: metrics.rootSize)
        orderedIDs.append(rootNode.id)

        let paragraphNodes = rootNode.children.filter { $0.admission == .mainline }
        let paragraphCount = max(paragraphNodes.count, 1)
        let paragraphRadius = metrics.paragraphRadius(for: paragraphNodes.count)
        let baseAngle = -CGFloat.pi / 2
        let angleStep = (2 * CGFloat.pi) / CGFloat(paragraphCount)

        for (index, paragraphNode) in paragraphNodes.enumerated() {
            let angle = baseAngle + (CGFloat(index) * angleStep)
            let paragraphCenter = CGPoint(
                x: cos(angle) * paragraphRadius,
                y: sin(angle) * paragraphRadius
            )
            let paragraphFrame = centeredRect(center: paragraphCenter, size: metrics.paragraphSize)
            logicalFrames[paragraphNode.id] = paragraphFrame
            orderedIDs.append(paragraphNode.id)
            edges.append(edge(from: rootNode.id, to: paragraphNode.id, fromFrame: logicalFrames[rootNode.id]!, toFrame: paragraphFrame))

            let visibleChildren: [MindMapNode]
            if simplified {
                visibleChildren = paragraphNode.id == expandedParagraphNodeID ? paragraphNode.children : []
            } else {
                visibleChildren = Array(paragraphNode.children.prefix(metrics.maxChildrenPerParagraph))
            }

            guard !visibleChildren.isEmpty else { continue }

            let childRadius = metrics.childRadius(for: visibleChildren.count)
            let sectorSpread = visibleChildren.count == 1 ? 0 : metrics.sectorSpread
            let childStart = angle - (sectorSpread / 2)
            let childStep = visibleChildren.count <= 1 ? 0 : sectorSpread / CGFloat(max(visibleChildren.count - 1, 1))

            for (childIndex, childNode) in visibleChildren.enumerated() {
                let childAngle = visibleChildren.count == 1 ? angle : childStart + (CGFloat(childIndex) * childStep)
                let childCenter = CGPoint(
                    x: paragraphCenter.x + cos(childAngle) * childRadius,
                    y: paragraphCenter.y + sin(childAngle) * childRadius
                )
                let childFrame = centeredRect(center: childCenter, size: metrics.size(for: childNode.kind))
                logicalFrames[childNode.id] = childFrame
                orderedIDs.append(childNode.id)
                edges.append(edge(from: paragraphNode.id, to: childNode.id, fromFrame: paragraphFrame, toFrame: childFrame))
            }
        }

        let boundingRect = translateFramesToCanvas(
            nodeFrames: &logicalFrames,
            edges: &edges,
            metrics: metrics,
            containerSize: containerSize
        )

        return MindMapLayoutSnapshot(
            containerSize: containerSize,
            contentBoundingRect: boundingRect,
            nodeFrames: logicalFrames,
            edgePaths: edges,
            orderedNodeIDs: orderedIDs,
            density: density,
            simplified: simplified
        )
    }

    private static func translateFramesToCanvas(
        nodeFrames: inout [String: CGRect],
        edges: inout [MindMapLayoutEdge],
        metrics: Metrics,
        containerSize: CGSize
    ) -> CGRect {
        let union = nodeFrames.values.reduce(CGRect.null) { partialResult, frame in
            partialResult.union(frame)
        }
        let fallbackRect = CGRect(x: 0, y: 0, width: max(containerSize.width, 640), height: max(containerSize.height, 480))
        let contentUnion = union.isNull ? fallbackRect : union
        let padding = metrics.canvasPadding
        let translatedOrigin = CGPoint(
            x: -contentUnion.minX + padding,
            y: -contentUnion.minY + padding
        )

        nodeFrames = nodeFrames.mapValues { frame in
            frame.offsetBy(dx: translatedOrigin.x, dy: translatedOrigin.y)
        }
        edges = edges.map { edge in
            MindMapLayoutEdge(
                id: edge.id,
                fromNodeID: edge.fromNodeID,
                toNodeID: edge.toNodeID,
                start: edge.start.offsetBy(dx: translatedOrigin.x, dy: translatedOrigin.y),
                end: edge.end.offsetBy(dx: translatedOrigin.x, dy: translatedOrigin.y),
                control: edge.control.offsetBy(dx: translatedOrigin.x, dy: translatedOrigin.y)
            )
        }

        return CGRect(
            x: 0,
            y: 0,
            width: contentUnion.width + padding * 2,
            height: contentUnion.height + padding * 2
        )
    }

    private static func edge(
        from fromNodeID: String,
        to toNodeID: String,
        fromFrame: CGRect,
        toFrame: CGRect
    ) -> MindMapLayoutEdge {
        let start = CGPoint(x: fromFrame.midX, y: fromFrame.midY)
        let end = CGPoint(x: toFrame.midX, y: toFrame.midY)
        let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let control = CGPoint(
            x: midpoint.x - dy * 0.08,
            y: midpoint.y + dx * 0.08
        )
        return MindMapLayoutEdge(
            id: "edge.\(fromNodeID).\(toNodeID)",
            fromNodeID: fromNodeID,
            toNodeID: toNodeID,
            start: start,
            end: end,
            control: control
        )
    }

    private static func centeredRect(center: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: center.x - (size.width / 2),
            y: center.y - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }

    private struct Metrics {
        let density: MindMapDensityMode
        let simplified: Bool

        let rootSize: CGSize
        let paragraphSize: CGSize
        let childSizeCompact: CGSize
        let childSizeDetailed: CGSize
        let sectorSpread: CGFloat
        let canvasPadding: CGFloat
        let maxChildrenPerParagraph: Int

        init(density: MindMapDensityMode, simplified: Bool) {
            self.density = density
            self.simplified = simplified
            switch density {
            case .compact:
                rootSize = CGSize(width: 214, height: simplified ? 98 : 108)
                paragraphSize = CGSize(width: 184, height: simplified ? 84 : 94)
                childSizeCompact = CGSize(width: 154, height: 74)
                childSizeDetailed = CGSize(width: 162, height: 82)
                sectorSpread = simplified ? 0.78 : 0.92
                canvasPadding = simplified ? 120 : 144
                maxChildrenPerParagraph = simplified ? 2 : 3
            case .detailed:
                rootSize = CGSize(width: 248, height: simplified ? 110 : 122)
                paragraphSize = CGSize(width: 204, height: simplified ? 94 : 106)
                childSizeCompact = CGSize(width: 168, height: 82)
                childSizeDetailed = CGSize(width: 178, height: 94)
                sectorSpread = simplified ? 0.92 : 1.08
                canvasPadding = simplified ? 132 : 168
                maxChildrenPerParagraph = simplified ? 2 : 3
            }
        }

        func paragraphRadius(for count: Int) -> CGFloat {
            let base: CGFloat
            switch density {
            case .compact:
                base = simplified ? 196 : 224
            case .detailed:
                base = simplified ? 220 : 256
            }
            return base + (CGFloat(max(count - 4, 0)) * 8)
        }

        func childRadius(for count: Int) -> CGFloat {
            let base: CGFloat = density == .compact ? 144 : 168
            return base + CGFloat(max(count - 2, 0)) * 10
        }

        func size(for kind: MindMapNodeKind) -> CGSize {
            switch kind {
            case .teachingFocus, .anchorSentence:
                return childSizeDetailed
            case .evidence:
                return childSizeCompact
            default:
                return childSizeDetailed
            }
        }
    }
}

private extension CGPoint {
    func offsetBy(dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }
}
