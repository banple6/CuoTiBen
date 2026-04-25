import SwiftUI

struct MindMapMiniMapView: View {
    let snapshot: MindMapLayoutSnapshot
    let selectedNodeID: String?
    let visibleRect: CGRect
    let onNavigate: (CGPoint) -> Void

    var body: some View {
        GeometryReader { proxy in
            let projection = MindMapMiniMapProjection(
                contentRect: snapshot.contentBoundingRect,
                containerSize: proxy.size
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 0.95, green: 0.965, blue: 0.992))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.9), lineWidth: 1)
                    )

                ForEach(snapshot.orderedNodeIDs, id: \.self) { nodeID in
                    if let frame = snapshot.nodeFrames[nodeID] {
                        let projected = projection.rect(for: frame).ensuringMinimumSize(
                            width: nodeID == selectedNodeID ? 16 : 10,
                            height: nodeID == selectedNodeID ? 10 : 6
                        )
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(nodeID == selectedNodeID ? Color.accentColor.opacity(0.8) : Color.accentColor.opacity(0.32))
                            .frame(width: projected.width, height: projected.height)
                            .position(x: projected.midX, y: projected.midY)
                    }
                }

                let viewport = projection.rect(for: visibleRect.intersection(snapshot.contentBoundingRect))
                    .ensuringMinimumSize(width: 18, height: 14)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(red: 0.22, green: 0.34, blue: 0.54), lineWidth: 1.2)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .frame(width: viewport.width, height: viewport.height)
                    .position(x: viewport.midX, y: viewport.midY)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let logicalPoint = projection.logicalPoint(for: value.location)
                        onNavigate(logicalPoint)
                    }
            )
        }
        .frame(width: 178, height: snapshot.simplified ? 122 : 142)
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
    }
}

private struct MindMapMiniMapProjection {
    let contentRect: CGRect
    let containerSize: CGSize
    let scale: CGFloat
    let xOffset: CGFloat
    let yOffset: CGFloat

    init(contentRect: CGRect, containerSize: CGSize) {
        self.contentRect = contentRect
        self.containerSize = containerSize
        let usableWidth = max(containerSize.width - 10, 1)
        let usableHeight = max(containerSize.height - 10, 1)
        let width = max(contentRect.width, 1)
        let height = max(contentRect.height, 1)
        let fittedScale = min(usableWidth / width, usableHeight / height)
        scale = max(fittedScale, 0.12)
        let fittedWidth = width * scale
        let fittedHeight = height * scale
        xOffset = (containerSize.width - fittedWidth) / 2 - contentRect.minX * scale
        yOffset = (containerSize.height - fittedHeight) / 2 - contentRect.minY * scale
    }

    func rect(for rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX * scale + xOffset,
            y: rect.minY * scale + yOffset,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    func logicalPoint(for point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - xOffset) / scale,
            y: (point.y - yOffset) / scale
        )
    }
}

private extension CGRect {
    func ensuringMinimumSize(width minWidth: CGFloat, height minHeight: CGFloat) -> CGRect {
        let resolvedWidth = max(width, minWidth)
        let resolvedHeight = max(height, minHeight)
        return CGRect(
            x: midX - resolvedWidth / 2,
            y: midY - resolvedHeight / 2,
            width: resolvedWidth,
            height: resolvedHeight
        )
    }
}
