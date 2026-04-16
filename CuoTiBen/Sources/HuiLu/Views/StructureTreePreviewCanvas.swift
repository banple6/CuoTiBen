import SwiftUI

struct StructureTreePreviewCanvas: View {
    let nodes: [OutlineNode]
    let highlightedNodeID: String?
    let jumpTargetNodeID: String?
    let ancestorNodeIDs: [String]
    let densityMode: StructureTreePreviewDensityMode
    let command: StructureTreePreviewCanvasCommand?
    let onScaleChanged: (CGFloat) -> Void
    let onNodeTap: (OutlineNode) -> Void
    let onJumpHandled: () -> Void

    @State private var expandedNodeIDs: Set<String> = []
    @State private var hasAppliedInitialExpansion = false
    @State private var canvasScale: CGFloat = 1.0
    @State private var scaleAnchor: CGFloat = 1.0
    @State private var canvasOffset: CGSize = .zero
    @State private var offsetAnchor: CGSize = .zero
    @State private var viewportSize: CGSize = .zero
    @State private var hasPositionedInitially = false
    @State private var userAdjustedZoom = false
    @State private var isCanvasInteracting = false
    @State private var tapSuppressionToken: UInt = 0

    private var metrics: StructureTreePreviewMetrics {
        StructureTreePreviewMetrics(densityMode: densityMode)
    }

    private var effectiveHighlightedNodeID: String? {
        jumpTargetNodeID ?? highlightedNodeID ?? StructureTreePreviewLayout.focusNodeID(in: nodes, highlightedNodeID: nil)
    }

    private var displayScene: StructureTreePreviewScene {
        StructureTreePreviewLayout.displayScene(
            nodes: nodes,
            highlightedNodeID: effectiveHighlightedNodeID,
            densityMode: densityMode,
            expandedNodeIDs: expandedNodeIDs
        )
    }

    private var overviewScene: StructureTreePreviewOverviewScene {
        StructureTreePreviewLayout.overviewScene(from: displayScene)
    }

    var body: some View {
        GeometryReader { proxy in
            let scene = displayScene
            let viewportRect = currentViewportRect(scene: scene, viewportSize: proxy.size)

            ZStack(alignment: .topTrailing) {
                canvasContainer(scene: scene)

                if !overviewScene.entries.isEmpty {
                    StructureTreePreviewMiniMap(
                        overviewScene: overviewScene,
                        highlightedNodeID: effectiveHighlightedNodeID,
                        displayContentRect: scene.contentRect,
                        viewportRect: viewportRect,
                        densityMode: densityMode
                    ) { node in
                        handleNodeTap(node)
                        focusNode(node.id, scene: latestSceneSnapshot(), viewportSize: viewportSize, animated: true, ensureReadableScale: false)
                    }
                    .padding(.top, 14)
                    .padding(.trailing, min(max(proxy.size.width * 0.015, 8), 14))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .onAppear {
                handleCanvasAppear()
                onScaleChanged(canvasScale)
            }
            .onChange(of: canvasScale) { value in
                onScaleChanged(value)
            }
            .onChange(of: ancestorNodeIDs) { _ in
                expandAncestors()
                ensureHighlightedNodeVisibleDeferred(animated: false)
            }
            .onChange(of: nodes) { _ in
                applyInitialExpansionIfNeeded(force: true)
                hasPositionedInitially = false
                DispatchQueue.main.async {
                    fitSceneToViewport(
                        scene: latestSceneSnapshot(),
                        viewportSize: viewportSize,
                        animated: false
                    )
                }
            }
            .onChange(of: densityMode) { _ in
                hasPositionedInitially = false
                DispatchQueue.main.async {
                    fitSceneToViewport(
                        scene: latestSceneSnapshot(),
                        viewportSize: viewportSize,
                        animated: false
                    )
                }
            }
            .onChange(of: expandedNodeIDs) { _ in
                clampCanvasStateDeferred(animated: true)
                ensureHighlightedNodeVisibleDeferred(animated: false)
            }
            .onChange(of: jumpTargetNodeID) { target in
                guard target != nil else { return }
                expandAncestors()
                positionCurrentNodeDeferred(animated: true, ensureReadableScale: true)
                deferJumpHandled()
            }
            .onChange(of: highlightedNodeID) { _ in
                guard jumpTargetNodeID == nil else { return }
                ensureHighlightedNodeVisibleDeferred(animated: true)
            }
            .onChange(of: command) { command in
                guard let command else { return }
                handleCommand(command, scene: latestSceneSnapshot())
            }
        }
    }

    private func canvasContainer(scene: StructureTreePreviewScene) -> some View {
        GeometryReader { canvasGeometry in
            let canvasViewportSize = canvasGeometry.size
            let visibleRect = currentViewportRect(scene: scene, viewportSize: canvasViewportSize)
            let renderRect = renderRect(in: scene, viewportRect: visibleRect)
            let renderedEntries = visibleEntries(in: scene, renderRect: renderRect)
            let renderedConnectors = visibleConnectors(in: scene, renderRect: renderRect)
            let scaledRenderOrigin = CGPoint(
                x: renderRect.minX * canvasScale,
                y: renderRect.minY * canvasScale
            )

            ZStack(alignment: .topLeading) {
                canvasBackground

                ZStack(alignment: .topLeading) {
                    connectorLayer(connectors: renderedConnectors, renderRect: renderRect)

                    ForEach(renderedEntries) { entry in
                        StructureTreePreviewNodeCard(
                            entry: entry,
                            densityMode: densityMode,
                            isExpanded: expandedNodeIDs.contains(entry.id),
                            onTap: {
                                handleNodeTap(entry.node)
                                focusNode(entry.id, scene: latestSceneSnapshot(), viewportSize: viewportSize, animated: true, ensureReadableScale: false)
                            },
                            onToggleExpand: {
                                toggleExpansion(for: entry.node)
                            }
                        )
                        .offset(
                            x: entry.frame.minX - renderRect.minX,
                            y: entry.frame.minY - renderRect.minY
                        )
                    }
                }
                .frame(
                    width: max(renderRect.width, 1),
                    height: max(renderRect.height, 1),
                    alignment: .topLeading
                )
                .scaleEffect(canvasScale, anchor: .topLeading)
                .offset(
                    x: canvasOffset.width + scaledRenderOrigin.x,
                    y: canvasOffset.height + scaledRenderOrigin.y
                )
                .animation(.spring(response: 0.28, dampingFraction: 0.88), value: canvasScale)
                .animation(.spring(response: 0.28, dampingFraction: 0.88), value: canvasOffset)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .topLeading) {
                zoomBadge
                    .padding(16)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture(scene: scene, viewportSize: canvasViewportSize))
            .simultaneousGesture(magnificationGesture(scene: scene, viewportSize: canvasViewportSize))
            .onTapGesture(count: 2) {
                positionCurrentNodeDeferred(animated: true, ensureReadableScale: true)
            }
            .onAppear {
                viewportSize = canvasViewportSize
                if !hasPositionedInitially {
                    fitSceneToViewport(
                        scene: latestSceneSnapshot(),
                        viewportSize: canvasViewportSize,
                        animated: false
                    )
                }
            }
            .onChange(of: canvasViewportSize) { newSize in
                viewportSize = newSize
                clampCanvasStateDeferred(animated: false)
                if !hasPositionedInitially {
                    DispatchQueue.main.async {
                        fitSceneToViewport(
                            scene: latestSceneSnapshot(),
                            viewportSize: newSize,
                            animated: false
                        )
                    }
                }
            }
        }
    }

    private var canvasBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        StructureTreePreviewPalette.canvasFill,
                        Color.white.opacity(0.9)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(StructureTreePreviewPalette.canvasStroke, lineWidth: 1)
            )
            .shadow(color: StructureTreePreviewPalette.canvasShadow, radius: 24, x: 0, y: 14)
    }

    private var zoomBadge: some View {
        Text("缩放 \(Int((canvasScale * 100).rounded()))%")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(StructureTreePreviewPalette.mutedText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
    }

    private func connectorLayer(
        connectors: [StructureTreePreviewScene.Connector],
        renderRect: CGRect
    ) -> some View {
        Canvas { context, _ in
            for connector in connectors {
                let start = CGPoint(
                    x: connector.start.x - renderRect.minX,
                    y: connector.start.y - renderRect.minY
                )
                let end = CGPoint(
                    x: connector.end.x - renderRect.minX,
                    y: connector.end.y - renderRect.minY
                )
                var path = Path()
                path.move(to: start)

                switch connector.kind {
                case .trunk:
                    let midY = (start.y + end.y) / 2
                    path.addCurve(
                        to: end,
                        control1: CGPoint(x: start.x, y: midY),
                        control2: CGPoint(x: end.x, y: midY)
                    )
                case .branch:
                    let midX = start.x + (end.x - start.x) * 0.54
                    path.addCurve(
                        to: end,
                        control1: CGPoint(x: midX, y: start.y),
                        control2: CGPoint(x: midX, y: end.y)
                    )
                }

                context.stroke(
                    path,
                    with: .color(
                        connector.kind == .trunk
                            ? StructureTreePreviewPalette.connector
                            : StructureTreePreviewPalette.branchConnector
                    ),
                    style: StrokeStyle(lineWidth: connector.kind == .trunk ? 2.2 : 1.6, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(width: max(renderRect.width, 1), height: max(renderRect.height, 1))
    }

    private func handleCanvasAppear() {
        applyInitialExpansionIfNeeded()
        expandAncestors()
        DispatchQueue.main.async {
            fitSceneToViewport(
                scene: latestSceneSnapshot(),
                viewportSize: viewportSize,
                animated: false
            )
            if jumpTargetNodeID != nil {
                positionCurrentNode(
                    scene: latestSceneSnapshot(),
                    viewportSize: viewportSize,
                    animated: false,
                    ensureReadableScale: true
                )
                deferJumpHandled()
            }
        }
    }

    private func latestSceneSnapshot() -> StructureTreePreviewScene {
        StructureTreePreviewLayout.displayScene(
            nodes: nodes,
            highlightedNodeID: effectiveHighlightedNodeID,
            densityMode: densityMode,
            expandedNodeIDs: expandedNodeIDs
        )
    }

    private func applyInitialExpansionIfNeeded(force: Bool = false) {
        guard force || !hasAppliedInitialExpansion else { return }
        expandedNodeIDs = Set(combinedAncestorIDs())
        hasAppliedInitialExpansion = true
    }

    private func expandAncestors() {
        expandedNodeIDs.formUnion(combinedAncestorIDs())
    }

    private func combinedAncestorIDs() -> [String] {
        let derived = StructureTreePreviewLayout.ancestorPathIDs(in: nodes, to: effectiveHighlightedNodeID)
        return Array(Set(ancestorNodeIDs + derived))
    }

    private func deferJumpHandled() {
        DispatchQueue.main.async {
            onJumpHandled()
        }
    }

    private func handleNodeTap(_ node: OutlineNode) {
        guard !isCanvasInteracting else { return }
        onNodeTap(node)
    }

    private func toggleExpansion(for node: OutlineNode) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            if expandedNodeIDs.contains(node.id) {
                expandedNodeIDs.remove(node.id)
            } else {
                expandedNodeIDs.insert(node.id)
            }
        }
    }

    private func handleCommand(_ command: StructureTreePreviewCanvasCommand, scene: StructureTreePreviewScene) {
        switch command.action {
        case .zoomIn:
            withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                let targetScale = clampedScale(canvasScale + 0.12)
                let targetOffset = adjustedOffsetForScaleChange(
                    from: canvasScale,
                    to: targetScale,
                    viewportSize: viewportSize
                )
                canvasScale = targetScale
                scaleAnchor = targetScale
                canvasOffset = clampedOffset(
                    targetOffset,
                    viewportSize: viewportSize,
                    scene: scene,
                    scale: targetScale
                )
                offsetAnchor = canvasOffset
                userAdjustedZoom = true
            }
        case .zoomOut:
            withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                let targetScale = clampedScale(canvasScale - 0.12)
                let targetOffset = adjustedOffsetForScaleChange(
                    from: canvasScale,
                    to: targetScale,
                    viewportSize: viewportSize
                )
                canvasScale = targetScale
                scaleAnchor = targetScale
                canvasOffset = clampedOffset(
                    targetOffset,
                    viewportSize: viewportSize,
                    scene: scene,
                    scale: targetScale
                )
                offsetAnchor = canvasOffset
                userAdjustedZoom = true
            }
        case .focus:
            positionCurrentNode(scene: scene, viewportSize: viewportSize, animated: true, ensureReadableScale: true)
        case .fit:
            fitSceneToViewport(scene: scene, viewportSize: viewportSize, animated: true)
        }
    }

    private func positionCurrentNodeDeferred(animated: Bool, ensureReadableScale: Bool) {
        DispatchQueue.main.async {
            positionCurrentNode(
                scene: latestSceneSnapshot(),
                viewportSize: viewportSize,
                animated: animated,
                ensureReadableScale: ensureReadableScale
            )
        }
    }

    private func positionCurrentNode(
        scene: StructureTreePreviewScene,
        viewportSize: CGSize,
        animated: Bool,
        ensureReadableScale: Bool
    ) {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        guard let targetID = effectiveHighlightedNodeID ?? scene.entries.first?.id else {
            alignCanvasToTopLeading(scene: scene, viewportSize: viewportSize, animated: animated)
            return
        }
        focusNode(targetID, scene: scene, viewportSize: viewportSize, animated: animated, ensureReadableScale: ensureReadableScale)
        hasPositionedInitially = true
    }

    private func fitSceneToViewport(
        scene: StructureTreePreviewScene,
        viewportSize: CGSize,
        animated: Bool
    ) {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        let availableWidth = max(
            viewportSize.width - metrics.leadingViewportPadding - metrics.trailingViewportPadding,
            1
        )
        let availableHeight = max(
            viewportSize.height - metrics.topViewportPadding - metrics.bottomViewportPadding,
            1
        )
        let fittedScale = clampedScale(
            min(
                availableWidth / max(scene.contentRect.width, 1),
                availableHeight / max(scene.contentRect.height, 1)
            )
        )
        let proposedOffset = CGSize(
            width: metrics.leadingViewportPadding - scene.contentRect.minX * fittedScale,
            height: metrics.topViewportPadding - scene.contentRect.minY * fittedScale
        )
        let clamped = clampedOffset(
            proposedOffset,
            viewportSize: viewportSize,
            scene: scene,
            scale: fittedScale
        )

        let apply = {
            canvasScale = fittedScale
            scaleAnchor = fittedScale
            canvasOffset = clamped
            offsetAnchor = clamped
        }

        if animated {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                apply()
            }
        } else {
            apply()
        }

        hasPositionedInitially = true
    }

    private func focusNode(
        _ nodeID: String,
        scene: StructureTreePreviewScene,
        viewportSize: CGSize,
        animated: Bool,
        ensureReadableScale: Bool
    ) {
        guard let entry = scene.entry(id: nodeID), viewportSize.width > 0, viewportSize.height > 0 else { return }

        let targetScale: CGFloat
        if ensureReadableScale {
            targetScale = max(canvasScale, metrics.focusReadableScale)
        } else {
            targetScale = canvasScale
        }

        let proposedOffset = CGSize(
            width: viewportSize.width * metrics.focusXRatio - entry.frame.midX * targetScale,
            height: viewportSize.height * metrics.focusYRatio - entry.frame.midY * targetScale
        )
        let clamped = clampedOffset(
            proposedOffset,
            viewportSize: viewportSize,
            scene: scene,
            scale: targetScale
        )

        let apply = {
            canvasScale = self.clampedScale(targetScale)
            scaleAnchor = canvasScale
            canvasOffset = clamped
            offsetAnchor = clamped
        }

        if animated {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                apply()
            }
        } else {
            apply()
        }
    }

    private func ensureHighlightedNodeVisibleDeferred(animated: Bool) {
        DispatchQueue.main.async {
            ensureHighlightedNodeVisible(scene: latestSceneSnapshot(), animated: animated)
        }
    }

    private func ensureHighlightedNodeVisible(scene: StructureTreePreviewScene, animated: Bool) {
        guard let targetID = effectiveHighlightedNodeID,
              let entry = scene.entry(id: targetID),
              viewportSize.width > 0,
              viewportSize.height > 0 else { return }

        let visibleRect = currentViewportRect(scene: scene, viewportSize: viewportSize)
        let paddedVisibleRect = visibleRect.insetBy(dx: -24, dy: -20)

        guard !paddedVisibleRect.contains(entry.frame) else { return }
        focusNode(targetID, scene: scene, viewportSize: viewportSize, animated: animated, ensureReadableScale: false)
    }

    private func alignCanvasToTopLeading(scene: StructureTreePreviewScene, viewportSize: CGSize, animated: Bool) {
        let targetScale = max(canvasScale, metrics.defaultScale)
        let targetOffset = clampedOffset(
            CGSize(
                width: metrics.leadingViewportPadding,
                height: metrics.topViewportPadding
            ),
            viewportSize: viewportSize,
            scene: scene,
            scale: targetScale
        )

        if animated {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                canvasScale = targetScale
                scaleAnchor = targetScale
                canvasOffset = targetOffset
                offsetAnchor = targetOffset
            }
        } else {
            canvasScale = targetScale
            scaleAnchor = targetScale
            canvasOffset = targetOffset
            offsetAnchor = targetOffset
        }
    }

    private func currentViewportRect(
        scene: StructureTreePreviewScene,
        viewportSize: CGSize
    ) -> CGRect {
        guard viewportSize.width > 0, viewportSize.height > 0, canvasScale > 0 else {
            return scene.contentRect
        }

        let rawRect = CGRect(
            x: -canvasOffset.width / canvasScale,
            y: -canvasOffset.height / canvasScale,
            width: viewportSize.width / canvasScale,
            height: viewportSize.height / canvasScale
        )
        let intersection = rawRect.intersection(scene.contentRect)
        return intersection.isNull ? scene.contentRect : intersection
    }

    private func renderRect(
        in scene: StructureTreePreviewScene,
        viewportRect: CGRect
    ) -> CGRect {
        let padding = metrics.renderPadding
        let expandedRect = viewportRect.insetBy(dx: -padding.width, dy: -padding.height)
        let clipped = expandedRect.intersection(scene.contentRect)
        if clipped.isNull || clipped.isEmpty {
            return viewportRect.isNull ? scene.contentRect : viewportRect
        }
        return clipped
    }

    private func visibleEntries(
        in scene: StructureTreePreviewScene,
        renderRect: CGRect
    ) -> [StructureTreePreviewScene.Entry] {
        scene.entries.filter { renderRect.intersects($0.frame) }
    }

    private func visibleConnectors(
        in scene: StructureTreePreviewScene,
        renderRect: CGRect
    ) -> [StructureTreePreviewScene.Connector] {
        scene.connectors.filter { connectorBounds(for: $0).intersects(renderRect) }
    }

    private func connectorBounds(for connector: StructureTreePreviewScene.Connector) -> CGRect {
        CGRect(
            x: min(connector.start.x, connector.end.x),
            y: min(connector.start.y, connector.end.y),
            width: abs(connector.end.x - connector.start.x),
            height: abs(connector.end.y - connector.start.y)
        )
        .insetBy(dx: -28, dy: -28)
    }

    private func dragGesture(
        scene: StructureTreePreviewScene,
        viewportSize: CGSize
    ) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                beginCanvasInteraction()
                if value.startLocation == value.location {
                    offsetAnchor = canvasOffset
                }

                let proposed = CGSize(
                    width: offsetAnchor.width + value.translation.width,
                    height: offsetAnchor.height + value.translation.height
                )
                canvasOffset = clampedOffset(
                    proposed,
                    viewportSize: viewportSize,
                    scene: scene,
                    scale: canvasScale
                )
            }
            .onEnded { _ in
                offsetAnchor = canvasOffset
                endCanvasInteraction(after: 0.2)
            }
    }

    private func magnificationGesture(
        scene: StructureTreePreviewScene,
        viewportSize: CGSize
    ) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                beginCanvasInteraction()
                let baseScale = scaleAnchor == 0 ? canvasScale : scaleAnchor
                let targetScale = clampedScale(baseScale * value)
                let targetOffset = adjustedOffsetForScaleChange(
                    from: canvasScale,
                    to: targetScale,
                    viewportSize: viewportSize
                )
                canvasScale = targetScale
                canvasOffset = clampedOffset(
                    targetOffset,
                    viewportSize: viewportSize,
                    scene: scene,
                    scale: targetScale
                )
                userAdjustedZoom = true
            }
            .onEnded { _ in
                scaleAnchor = canvasScale
                offsetAnchor = canvasOffset
                endCanvasInteraction(after: 0.24)
            }
    }

    private func beginCanvasInteraction() {
        guard !isCanvasInteracting else { return }
        tapSuppressionToken &+= 1
        isCanvasInteracting = true
    }

    private func endCanvasInteraction(after delay: TimeInterval) {
        let token = tapSuppressionToken &+ 1
        tapSuppressionToken = token

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard self.tapSuppressionToken == token else { return }
            self.isCanvasInteracting = false
        }
    }

    private func adjustedOffsetForScaleChange(
        from oldScale: CGFloat,
        to newScale: CGFloat,
        viewportSize: CGSize
    ) -> CGSize {
        guard viewportSize.width > 0, viewportSize.height > 0, oldScale > 0 else {
            return canvasOffset
        }

        let viewportCenter = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let contentPoint = CGPoint(
            x: (viewportCenter.x - canvasOffset.width) / oldScale,
            y: (viewportCenter.y - canvasOffset.height) / oldScale
        )

        return CGSize(
            width: viewportCenter.x - contentPoint.x * newScale,
            height: viewportCenter.y - contentPoint.y * newScale
        )
    }

    private func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, metrics.minimumScale), metrics.maximumScale)
    }

    private func clampedOffset(
        _ proposed: CGSize,
        viewportSize: CGSize,
        scene: StructureTreePreviewScene,
        scale: CGFloat
    ) -> CGSize {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return proposed }

        let contentWidth = scene.contentRect.width * scale
        let contentHeight = scene.contentRect.height * scale

        let leadingPadding = metrics.leadingViewportPadding
        let trailingPadding = metrics.trailingViewportPadding
        let topPadding = metrics.topViewportPadding
        let bottomPadding = metrics.bottomViewportPadding

        let minXBound = viewportSize.width - scene.contentRect.maxX * scale - trailingPadding
        let maxXBound = leadingPadding - scene.contentRect.minX * scale
        let clampedX: CGFloat
        if contentWidth <= viewportSize.width - leadingPadding - trailingPadding {
            clampedX = (viewportSize.width - contentWidth) / 2 - scene.contentRect.minX * scale
        } else {
            clampedX = min(max(proposed.width, minXBound), maxXBound)
        }

        let minYBound = viewportSize.height - scene.contentRect.maxY * scale - bottomPadding
        let maxYBound = topPadding - scene.contentRect.minY * scale
        let clampedY: CGFloat
        if contentHeight <= viewportSize.height - topPadding - bottomPadding {
            clampedY = (viewportSize.height - contentHeight) / 2 - scene.contentRect.minY * scale
        } else {
            clampedY = min(max(proposed.height, minYBound), maxYBound)
        }

        return CGSize(width: clampedX, height: clampedY)
    }

    private func clampCanvasStateDeferred(animated: Bool) {
        DispatchQueue.main.async {
            clampCanvasState(scene: latestSceneSnapshot(), animated: animated)
        }
    }

    private func clampCanvasState(scene: StructureTreePreviewScene, animated: Bool) {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        let targetOffset = clampedOffset(canvasOffset, viewportSize: viewportSize, scene: scene, scale: canvasScale)
        if animated {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                canvasOffset = targetOffset
                offsetAnchor = targetOffset
            }
        } else {
            canvasOffset = targetOffset
            offsetAnchor = targetOffset
        }
    }
}
