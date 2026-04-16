import SwiftUI

struct StructureTreePreviewMiniMap: View {
    let overviewScene: StructureTreePreviewOverviewScene
    let highlightedNodeID: String?
    let displayContentRect: CGRect
    let viewportRect: CGRect
    let densityMode: StructureTreePreviewDensityMode
    let onNodeTap: (OutlineNode) -> Void

    private var metrics: StructureTreePreviewMetrics {
        StructureTreePreviewMetrics(densityMode: densityMode)
    }

    var body: some View {
        GeometryReader { proxy in
            let projection = StructureTreePreviewMiniMapProjection(
                contentRect: overviewScene.contentRect,
                containerSize: proxy.size
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(StructureTreePreviewPalette.minimapFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(StructureTreePreviewPalette.minimapStroke, lineWidth: 1)
                    )

                ForEach(overviewScene.entries) { entry in
                    let projectedRect = projection.rect(for: entry.frame).ensuringMinimumSize(
                        width: entry.isHighlighted ? 14 : 10,
                        height: entry.isHighlighted ? 10 : 6
                    )

                    Button {
                        onNodeTap(entry.node)
                    } label: {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                StructureTreePreviewPalette.accent(for: entry.node.nodeType)
                                    .opacity(entry.id == highlightedNodeID ? 0.82 : 0.34)
                            )
                            .frame(width: projectedRect.width, height: projectedRect.height)
                    }
                    .buttonStyle(.plain)
                    .position(x: projectedRect.midX, y: projectedRect.midY)
                }

                let projectedViewport = projection.rect(
                    for: mappedViewportRect(
                        viewportRect: viewportRect,
                        displayContentRect: displayContentRect,
                        overviewContentRect: overviewScene.contentRect
                    )
                )
                .ensuringMinimumSize(width: 18, height: 14)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(StructureTreePreviewPalette.minimapViewport, lineWidth: 1.2)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .frame(width: projectedViewport.width, height: projectedViewport.height)
                    .position(x: projectedViewport.midX, y: projectedViewport.midY)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: metrics.minimapWidth, height: densityMode == .detailed ? 156 : 140)
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
    }

    private func mappedViewportRect(
        viewportRect: CGRect,
        displayContentRect: CGRect,
        overviewContentRect: CGRect
    ) -> CGRect {
        guard !viewportRect.isNull,
              displayContentRect.width > 0,
              displayContentRect.height > 0 else {
            return overviewContentRect
        }

        let normalizedMinX = (viewportRect.minX - displayContentRect.minX) / max(displayContentRect.width, 1)
        let normalizedMinY = (viewportRect.minY - displayContentRect.minY) / max(displayContentRect.height, 1)
        let normalizedWidth = viewportRect.width / max(displayContentRect.width, 1)
        let normalizedHeight = viewportRect.height / max(displayContentRect.height, 1)

        return CGRect(
            x: overviewContentRect.minX + normalizedMinX * overviewContentRect.width,
            y: overviewContentRect.minY + normalizedMinY * overviewContentRect.height,
            width: overviewContentRect.width * normalizedWidth,
            height: overviewContentRect.height * normalizedHeight
        )
        .intersection(overviewContentRect)
    }
}

private struct StructureTreePreviewMiniMapProjection {
    let scale: CGFloat
    let xOffset: CGFloat
    let yOffset: CGFloat

    init(contentRect: CGRect, containerSize: CGSize) {
        let usableWidth = max(containerSize.width - 8, 1)
        let usableHeight = max(containerSize.height - 8, 1)
        let contentWidth = max(contentRect.width, 1)
        let contentHeight = max(contentRect.height, 1)
        let fittedScale = min(usableWidth / contentWidth, usableHeight / contentHeight)
        scale = max(fittedScale, 0.12)

        let fittedWidth = contentWidth * scale
        let fittedHeight = contentHeight * scale
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
}

private extension CGRect {
    func ensuringMinimumSize(width minWidth: CGFloat, height minHeight: CGFloat) -> CGRect {
        let targetWidth = max(width, minWidth)
        let targetHeight = max(height, minHeight)
        return CGRect(
            x: midX - targetWidth / 2,
            y: midY - targetHeight / 2,
            width: targetWidth,
            height: targetHeight
        )
    }
}
