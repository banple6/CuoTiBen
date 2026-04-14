import SwiftUI

private enum OutlineCanvasDensityMode: String, CaseIterable, Identifiable {
    case detailed = "详细"
    case compact = "紧凑"

    var id: String { rawValue }

    var rowSpacing: CGFloat {
        switch self {
        case .detailed: return 18
        case .compact: return 10
        }
    }

    var branchSpacing: CGFloat {
        switch self {
        case .detailed: return 12
        case .compact: return 8
        }
    }

    var indent: CGFloat {
        switch self {
        case .detailed: return 72
        case .compact: return 54
        }
    }

    var baseWidth: CGFloat {
        switch self {
        case .detailed: return 344
        case .compact: return 292
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .detailed: return 232
        case .compact: return 214
        }
    }

    var titleLineLimit: Int {
        switch self {
        case .detailed: return 3
        case .compact: return 2
        }
    }

    var summaryLineLimit: Int {
        switch self {
        case .detailed: return 3
        case .compact: return 2
        }
    }

    var canvasInset: CGSize {
        switch self {
        case .detailed:
            return CGSize(width: 28, height: 24)
        case .compact:
            return CGSize(width: 20, height: 18)
        }
    }
}

struct TeachingTreeCanvasView: View {
    let nodes: [OutlineNode]
    let highlightedNodeID: String?
    let jumpTargetNodeID: String?
    let ancestorNodeIDs: [String]
    let onNodeTap: (OutlineNode) -> Void
    let onJumpHandled: () -> Void

    @State private var expandedNodeIDs: Set<String> = []
    @State private var hasAppliedInitialExpansion = false
    @State private var densityMode: OutlineCanvasDensityMode = .detailed
    @State private var canvasScale: CGFloat = 1.0
    @State private var scaleAnchor: CGFloat = 1.0
    @State private var canvasOffset: CGSize = .zero
    @State private var offsetAnchor: CGSize = .zero
    @State private var viewportSize: CGSize = .zero
    @State private var hasPerformedInitialFit = false
    @State private var userAdjustedZoom = false

    private let minScale: CGFloat = 0.68
    private let maxScale: CGFloat = 1.65

    var body: some View {
        GeometryReader { proxyGeometry in
            outlineCanvasScene(proxyGeometry: proxyGeometry)
        }
    }

    @ViewBuilder
    private func outlineCanvasScene(proxyGeometry: GeometryProxy) -> some View {
        let layout = TeachingTreeCanvasLayout(
            nodes: visibleNodes,
            densityMode: densityMode,
            highlightedNodeID: jumpTargetNodeID ?? highlightedNodeID
        )
        let viewportRect = currentViewportRect(layout: layout, viewportSize: viewportSize)

        ZStack(alignment: .topTrailing) {
            outlineCanvasMainContent(proxyGeometry: proxyGeometry, layout: layout)
            miniMapOverlay(proxyGeometry: proxyGeometry, layout: layout, viewportRect: viewportRect)
        }
        .onAppear {
            handleCanvasAppear(layout: layout)
        }
        .onChange(of: ancestorNodeIDs) { _ in
            expandAncestors()
        }
        .onChange(of: nodes) { _ in
            applyInitialExpansionIfNeeded(force: true)
            fitToContent(in: viewportSize, layout: layout, force: true)
        }
        .onChange(of: densityMode) { _ in
            fitToContent(in: viewportSize, layout: layout, force: true)
        }
        .onChange(of: expandedNodeIDs) { _ in
            clampCanvasState(layout: layout, animated: true)
            ensureHighlightedNodeVisible(layout: layout, animated: false)
        }
        .onChange(of: jumpTargetNodeID) { target in
            guard target != nil else { return }
            expandAncestors()
            focusCurrentNode(layout: layout, viewportSize: viewportSize, animated: true, ensureReadableScale: true)
            deferJumpHandled()
        }
        .onChange(of: highlightedNodeID) { _ in
            guard jumpTargetNodeID == nil else { return }
            ensureHighlightedNodeVisible(layout: layout, animated: true)
        }
    }

    private func outlineCanvasMainContent(
        proxyGeometry: GeometryProxy,
        layout: TeachingTreeCanvasLayout
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            outlineToolbar(layout: layout, viewportSize: viewportSize)

            GeometryReader { canvasGeometry in
                let canvasViewportSize = canvasGeometry.size
                let visibleRect = currentViewportRect(layout: layout, viewportSize: canvasViewportSize)
                let renderedEntries = visibleEntries(for: layout, viewportRect: visibleRect)

                ZStack(alignment: .topLeading) {
                    canvasBackground
                    outlineCanvasTree(layout: layout, entries: renderedEntries)
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    zoomBadge
                        .padding(14)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(dragGesture(layout: layout, viewportSize: canvasViewportSize))
                .simultaneousGesture(magnificationGesture(layout: layout, viewportSize: canvasViewportSize))
                .onTapGesture(count: 2) {
                    focusCurrentNode(layout: layout, viewportSize: canvasViewportSize, animated: true, ensureReadableScale: true)
                }
                .onAppear {
                    viewportSize = canvasViewportSize
                    fitToContent(in: canvasViewportSize, layout: layout, force: false)
                }
                .onChange(of: canvasViewportSize) { newSize in
                    viewportSize = newSize
                    fitToContent(in: newSize, layout: layout, force: false)
                    clampCanvasState(layout: layout, animated: false)
                }
            }
            .frame(minHeight: 320)
        }
    }

    private func outlineCanvasTree(
        layout: TeachingTreeCanvasLayout,
        entries: [TeachingTreeCanvasLayout.Entry]
    ) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(entries) { entry in
                OutlineTreeNodeRow(
                    node: entry.node,
                    highlightedNodeID: highlightedNodeID,
                    densityMode: densityMode,
                    expandedNodeIDs: $expandedNodeIDs,
                    onNodeTap: onNodeTap,
                    isCanvasCard: true
                )
                .frame(width: entry.frame.width, alignment: .topLeading)
                .offset(x: entry.frame.minX, y: entry.frame.minY)
                .id(entry.node.id)
            }
        }
        .frame(
            width: layout.contentBoundingRect.width,
            alignment: .topLeading
        )
        .frame(
            height: layout.contentBoundingRect.height,
            alignment: .topLeading
        )
        .scaleEffect(canvasScale, anchor: .topLeading)
        .offset(x: canvasOffset.width, y: canvasOffset.height)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: canvasScale)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: canvasOffset)
    }

    @ViewBuilder
    private func miniMapOverlay(
        proxyGeometry: GeometryProxy,
        layout: TeachingTreeCanvasLayout,
        viewportRect: CGRect
    ) -> some View {
        if !layout.entries.isEmpty {
            TeachingTreeMiniMap(
                layout: layout,
                highlightedNodeID: jumpTargetNodeID ?? highlightedNodeID,
                densityMode: densityMode,
                viewportRect: viewportRect
            ) { node in
                onNodeTap(node)
                focusNode(node.id, layout: layout, viewportSize: viewportSize, animated: true, ensureReadableScale: false)
            }
            .padding(.top, 64)
            .padding(.trailing, min(max(proxyGeometry.size.width * 0.018, 10), 18))
        }
    }

    private func handleCanvasAppear(layout: TeachingTreeCanvasLayout) {
        applyInitialExpansionIfNeeded()
        expandAncestors()
        DispatchQueue.main.async {
            fitToContent(in: viewportSize, layout: layout, force: false)
            ensureHighlightedNodeVisible(layout: layout, animated: false)
            if jumpTargetNodeID != nil {
                deferJumpHandled()
            }
        }
    }

    private var visibleNodes: [OutlineNode] {
        flattenVisible(nodes)
    }

    private var canvasBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color.white.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.blue.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 22, x: 0, y: 10)
    }

    private var zoomBadge: some View {
        Text("缩放 \(Int((canvasScale * 100).rounded()))%")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.72))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
    }

    @ViewBuilder
    private func outlineToolbar(
        layout: TeachingTreeCanvasLayout,
        viewportSize: CGSize
    ) -> some View {
        HStack(spacing: 10) {
            Picker("密度", selection: $densityMode) {
                ForEach(OutlineCanvasDensityMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)

            Spacer(minLength: 0)

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    let targetScale = clampedScale(canvasScale - 0.12)
                    let targetOffset = adjustedOffsetForScaleChange(
                        from: canvasScale,
                        to: targetScale,
                        viewportSize: viewportSize
                    )
                    canvasScale = targetScale
                    scaleAnchor = targetScale
                    canvasOffset = clampedOffset(targetOffset, viewportSize: viewportSize, layout: layout, scale: targetScale)
                    offsetAnchor = canvasOffset
                    userAdjustedZoom = true
                }
            } label: {
                toolbarIcon(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    let targetScale = clampedScale(canvasScale + 0.12)
                    let targetOffset = adjustedOffsetForScaleChange(
                        from: canvasScale,
                        to: targetScale,
                        viewportSize: viewportSize
                    )
                    canvasScale = targetScale
                    scaleAnchor = targetScale
                    canvasOffset = clampedOffset(targetOffset, viewportSize: viewportSize, layout: layout, scale: targetScale)
                    offsetAnchor = canvasOffset
                    userAdjustedZoom = true
                }
            } label: {
                toolbarIcon(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)

            Button {
                fitToContent(in: viewportSize, layout: layout, force: true)
                focusCurrentNode(layout: layout, viewportSize: viewportSize, animated: true, ensureReadableScale: true)
            } label: {
                toolbarIcon(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.plain)

            Button {
                focusCurrentNode(layout: layout, viewportSize: viewportSize, animated: true, ensureReadableScale: true)
            } label: {
                Label("聚焦当前", systemImage: "scope")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.blue.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1), in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func toolbarIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.68))
            .frame(width: 36, height: 36)
            .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func dragGesture(
        layout: TeachingTreeCanvasLayout,
        viewportSize: CGSize
    ) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let proposed = CGSize(
                    width: offsetAnchor.width + value.translation.width,
                    height: offsetAnchor.height + value.translation.height
                )
                canvasOffset = clampedOffset(proposed, viewportSize: viewportSize, layout: layout, scale: canvasScale)
                userAdjustedZoom = true
            }
            .onEnded { _ in
                offsetAnchor = canvasOffset
            }
    }

    private func magnificationGesture(
        layout: TeachingTreeCanvasLayout,
        viewportSize: CGSize
    ) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let targetScale = clampedScale(scaleAnchor * value)
                let targetOffset = adjustedOffsetForScaleChange(
                    from: canvasScale,
                    to: targetScale,
                    viewportSize: viewportSize
                )
                canvasScale = targetScale
                canvasOffset = clampedOffset(targetOffset, viewportSize: viewportSize, layout: layout, scale: targetScale)
                userAdjustedZoom = true
            }
            .onEnded { _ in
                scaleAnchor = canvasScale
                offsetAnchor = canvasOffset
                ensureHighlightedNodeVisible(layout: layout, animated: true)
            }
    }

    private func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minScale), maxScale)
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

    private func allExpandableNodeIDs(from nodes: [OutlineNode]) -> Set<String> {
        Set(flatten(nodes).filter { !$0.children.isEmpty }.map(\.id))
    }

    private func flattenVisible(_ currentNodes: [OutlineNode]) -> [OutlineNode] {
        currentNodes.flatMap { node in
            let children = expandedNodeIDs.contains(node.id) ? flattenVisible(node.children) : []
            return [node] + children
        }
    }

    private func flatten(_ currentNodes: [OutlineNode]) -> [OutlineNode] {
        currentNodes.flatMap { node in
            [node] + flatten(node.children)
        }
    }

    private func visibleEntries(
        for layout: TeachingTreeCanvasLayout,
        viewportRect: CGRect
    ) -> [TeachingTreeCanvasLayout.Entry] {
        let preloadPadding = max(120, 220 / max(canvasScale, 0.1))
        let expandedRect = viewportRect.insetBy(dx: -preloadPadding, dy: -preloadPadding)
        let emphasizedIDs = Set(ancestorNodeIDs + [highlightedNodeID, jumpTargetNodeID].compactMap { $0 })

        return layout.entries.filter { entry in
            expandedRect.intersects(entry.frame) || emphasizedIDs.contains(entry.node.id)
        }
    }

    private func currentViewportRect(
        layout: TeachingTreeCanvasLayout,
        viewportSize: CGSize
    ) -> CGRect {
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return layout.contentBoundingRect
        }

        let scale = max(canvasScale, 0.001)
        let rawRect = CGRect(
            x: (-canvasOffset.width) / scale,
            y: (-canvasOffset.height) / scale,
            width: viewportSize.width / scale,
            height: viewportSize.height / scale
        )
        let intersection = rawRect.intersection(layout.contentBoundingRect)
        return intersection.isNull ? layout.contentBoundingRect : intersection
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

    private func clampCanvasState(layout: TeachingTreeCanvasLayout, animated: Bool) {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        let target = clampedOffset(canvasOffset, viewportSize: viewportSize, layout: layout, scale: canvasScale)
        if animated {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                canvasOffset = target
            }
        } else {
            canvasOffset = target
        }
        offsetAnchor = canvasOffset
    }

    private func clampedOffset(
        _ proposed: CGSize,
        viewportSize: CGSize,
        layout: TeachingTreeCanvasLayout,
        scale: CGFloat
    ) -> CGSize {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return proposed }

        let contentWidth = layout.contentBoundingRect.width * scale
        let contentHeight = layout.contentBoundingRect.height * scale
        let horizontalPadding = min(max(18, viewportSize.width * 0.08), 48)
        let verticalPadding = min(max(18, viewportSize.height * 0.06), 44)

        let clampedX: CGFloat
        if contentWidth <= viewportSize.width - horizontalPadding * 2 {
            clampedX = (viewportSize.width - contentWidth) / 2
        } else {
            let minX = viewportSize.width - contentWidth - horizontalPadding
            let maxX = horizontalPadding
            clampedX = min(max(proposed.width, minX), maxX)
        }

        let clampedY: CGFloat
        if contentHeight <= viewportSize.height - verticalPadding * 2 {
            clampedY = (viewportSize.height - contentHeight) / 2
        } else {
            let minY = viewportSize.height - contentHeight - verticalPadding
            let maxY = verticalPadding
            clampedY = min(max(proposed.height, minY), maxY)
        }

        return CGSize(width: clampedX, height: clampedY)
    }

    private func fitToContent(in size: CGSize, layout: TeachingTreeCanvasLayout, force: Bool) {
        guard size.width > 0, size.height > 0, layout.contentBoundingRect.width > 0, layout.contentBoundingRect.height > 0 else {
            return
        }
        guard force || !hasPerformedInitialFit || !userAdjustedZoom else { return }

        let availableWidth = max(size.width - 48, 280)
        let availableHeight = max(size.height - 48, 240)
        let scale = min(
            maxScale,
            max(
                minScale,
                min(
                    availableWidth / layout.contentBoundingRect.width,
                    availableHeight / layout.contentBoundingRect.height
                )
            )
        )

        let centeredOffset = clampedOffset(
            CGSize(
                width: (size.width - layout.contentBoundingRect.width * scale) / 2,
                height: (size.height - layout.contentBoundingRect.height * scale) / 2
            ),
            viewportSize: size,
            layout: layout,
            scale: scale
        )

        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
            canvasScale = scale
            scaleAnchor = scale
            canvasOffset = centeredOffset
            offsetAnchor = centeredOffset
        }
        hasPerformedInitialFit = true
        if force {
            userAdjustedZoom = false
        }
    }

    private func focusCurrentNode(
        layout: TeachingTreeCanvasLayout,
        viewportSize: CGSize,
        animated: Bool,
        ensureReadableScale: Bool
    ) {
        guard let targetID = jumpTargetNodeID ?? highlightedNodeID else { return }
        focusNode(targetID, layout: layout, viewportSize: viewportSize, animated: animated, ensureReadableScale: ensureReadableScale)
    }

    private func focusNode(
        _ nodeID: String,
        layout: TeachingTreeCanvasLayout,
        viewportSize: CGSize,
        animated: Bool,
        ensureReadableScale: Bool
    ) {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        guard let entry = layout.entry(id: nodeID) else { return }

        let targetScale = ensureReadableScale
            ? max(canvasScale, densityMode == .detailed ? 0.94 : 0.82)
            : canvasScale
        let proposedOffset = CGSize(
            width: viewportSize.width / 2 - entry.frame.midX * targetScale,
            height: viewportSize.height / 2 - entry.frame.midY * targetScale
        )
        let targetOffset = clampedOffset(proposedOffset, viewportSize: viewportSize, layout: layout, scale: targetScale)

        if animated {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
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

    private func ensureHighlightedNodeVisible(
        layout: TeachingTreeCanvasLayout,
        animated: Bool
    ) {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        guard let targetID = jumpTargetNodeID ?? highlightedNodeID else { return }
        guard let entry = layout.entry(id: targetID) else { return }

        let viewportRect = currentViewportRect(layout: layout, viewportSize: viewportSize)
        let extraInset = max(28, 64 / max(canvasScale, 0.1))
        let visibleRect = viewportRect.insetBy(dx: -extraInset, dy: -extraInset)

        guard !visibleRect.contains(entry.frame) else { return }
        focusNode(targetID, layout: layout, viewportSize: viewportSize, animated: animated, ensureReadableScale: false)
    }

    private func deferJumpHandled() {
        DispatchQueue.main.async {
            onJumpHandled()
        }
    }
}

struct SourceOutlineTab: View {
    let nodes: [OutlineNode]
    let highlightedNodeID: String?
    let jumpTargetNodeID: String?
    let ancestorNodeIDs: [String]
    let onNodeTap: (OutlineNode) -> Void
    let onJumpHandled: () -> Void

    var body: some View {
        TeachingTreeCanvasView(
            nodes: nodes,
            highlightedNodeID: highlightedNodeID,
            jumpTargetNodeID: jumpTargetNodeID,
            ancestorNodeIDs: ancestorNodeIDs,
            onNodeTap: onNodeTap,
            onJumpHandled: onJumpHandled
        )
    }
}

private struct OutlineTreeNodeRow: View {
    let node: OutlineNode
    let highlightedNodeID: String?
    let densityMode: OutlineCanvasDensityMode
    @Binding var expandedNodeIDs: Set<String>
    let onNodeTap: (OutlineNode) -> Void
    var isCanvasCard: Bool = false

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
        switch (densityMode, normalizedDepth) {
        case (.detailed, 0):
            return .system(size: 19, weight: .heavy, design: .rounded)
        case (.detailed, 1):
            return .system(size: 17, weight: .bold, design: .rounded)
        case (.compact, 0):
            return .system(size: 17, weight: .bold, design: .rounded)
        case (.compact, 1):
            return .system(size: 15, weight: .semibold, design: .rounded)
        default:
            return .system(size: 14, weight: .semibold, design: .rounded)
        }
    }

    private var summaryFont: Font {
        densityMode == .detailed
            ? .system(size: normalizedDepth == 0 ? 14 : 13, weight: .medium)
            : .system(size: 12.5, weight: .medium)
    }

    private var rowPadding: CGFloat {
        switch densityMode {
        case .detailed:
            return normalizedDepth == 0 ? 20 : 15
        case .compact:
            return normalizedDepth == 0 ? 16 : 12
        }
    }

    private var childIndent: CGFloat {
        switch densityMode {
        case .detailed:
            return normalizedDepth == 0 ? 28 : 20
        case .compact:
            return normalizedDepth == 0 ? 22 : 16
        }
    }

    private var rowLeadingInset: CGFloat {
        guard !isCanvasCard else { return 0 }
        return CGFloat(normalizedDepth) * (densityMode == .detailed ? 54 : 42)
    }

    private var titleColor: Color {
        isHighlighted ? nodeAccentColor.opacity(0.96) : Color.black.opacity(0.82)
    }

    private var summaryColor: Color {
        isHighlighted ? Color.black.opacity(0.76) : Color.black.opacity(0.58)
    }

    private var shouldShowSummary: Bool {
        densityMode == .detailed || isHighlighted || normalizedDepth <= 1
    }

    private var shouldShowAnchorBadge: Bool {
        densityMode == .detailed || isHighlighted || normalizedDepth == 0
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Color.clear
                .frame(width: rowLeadingInset, height: 1)

            hierarchyRail

            HStack(alignment: .top, spacing: 10) {
                disclosureView
                outlineNodeButton
            }
        }
        .padding(rowPadding)
        .frame(maxWidth: isCanvasCard ? .infinity : nil, alignment: .topLeading)
        .background(nodeBackground)
        .id(node.id)
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
                    .font(.system(size: densityMode == .detailed ? 18 : 16, weight: .semibold))
                    .foregroundStyle(Color.blue.opacity(0.75))
            }
            .buttonStyle(.plain)
        } else {
            Circle()
                .fill(isHighlighted ? Color.blue.opacity(0.75) : Color.blue.opacity(0.26))
                .frame(width: densityMode == .detailed ? 10 : 8, height: densityMode == .detailed ? 10 : 8)
                .padding(.top, densityMode == .detailed ? 9 : 8)
        }
    }

    private var outlineNodeButton: some View {
        Button {
            onNodeTap(node)
        } label: {
            VStack(alignment: .leading, spacing: densityMode == .detailed ? 8 : 6) {
                hierarchyBadge

                Text(node.title)
                    .font(titleFont)
                    .foregroundStyle(titleColor)
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    .lineLimit(densityMode.titleLineLimit)

                if shouldShowSummary {
                    Text(node.summary)
                        .font(summaryFont)
                        .foregroundStyle(summaryColor)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .lineLimit(densityMode.summaryLineLimit)
                }

                if shouldShowAnchorBadge {
                    anchorBadge
                }
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
            Image(systemName: anchorIconName)
                .font(.system(size: 10, weight: .bold))

            Text(node.anchor.label)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(nodeAccentColor.opacity(isHighlighted ? 0.96 : 0.78))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(nodeAccentColor.opacity(isHighlighted ? 0.16 : 0.09))
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
            return nodeAccentColor.opacity(0.36)
        }

        return normalizedDepth == 0 ? nodeAccentColor.opacity(0.24) : nodeAccentColor.opacity(0.16)
    }

    private var hierarchyDotColor: Color {
        if isHighlighted {
            return nodeAccentColor.opacity(0.84)
        }

        return normalizedDepth == 0 ? nodeAccentColor.opacity(0.52) : nodeAccentColor.opacity(0.36)
    }

    private var levelLabel: String {
        node.nodeType.displayName
    }

    private var levelLabelColor: Color {
        normalizedDepth == 0 ? nodeAccentColor.opacity(0.84) : nodeAccentColor.opacity(0.72)
    }

    private var levelLabelBackground: Color {
        if isHighlighted {
            return nodeAccentColor.opacity(0.16)
        }

        return normalizedDepth == 0 ? nodeAccentColor.opacity(0.1) : nodeAccentColor.opacity(0.08)
    }

    private var nodeBackground: some View {
        RoundedRectangle(cornerRadius: normalizedDepth == 0 ? 24 : 20, style: .continuous)
            .fill(nodeFillColor)
            .overlay(
                RoundedRectangle(cornerRadius: normalizedDepth == 0 ? 24 : 20, style: .continuous)
                    .stroke(nodeStrokeColor, lineWidth: 1)
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
            return nodeAccentColor.opacity(normalizedDepth == 0 ? 0.16 : 0.13)
        }

        switch node.nodeType {
        case .passageRoot:
            return Color.white.opacity(0.76)
        case .paragraphTheme:
            return Color.white.opacity(0.66)
        case .teachingFocus:
            return Color.orange.opacity(0.06)
        case .supportingSentence:
            return Color.cyan.opacity(0.05)
        case .questionLink:
            return Color.pink.opacity(0.06)
        case .vocabularySupport:
            return Color.teal.opacity(0.05)
        case .metaInstruction:
            return Color.gray.opacity(0.06)
        case .answerKey:
            return Color.yellow.opacity(0.06)
        }
    }

    private var nodeStrokeColor: Color {
        if isHighlighted {
            return nodeAccentColor.opacity(0.34)
        }

        return normalizedDepth == 0 ? nodeAccentColor.opacity(0.16) : nodeAccentColor.opacity(0.14)
    }

    private var nodeAccentColor: Color {
        switch node.nodeType {
        case .passageRoot:
            return Color.blue
        case .paragraphTheme:
            return Color.indigo
        case .teachingFocus:
            return Color.orange
        case .supportingSentence:
            return Color.cyan
        case .questionLink:
            return Color.pink
        case .vocabularySupport:
            return Color.teal
        case .metaInstruction:
            return Color.gray
        case .answerKey:
            return Color.yellow.opacity(0.82)
        }
    }

    private var anchorIconName: String {
        switch node.nodeType {
        case .questionLink:
            return "questionmark.bubble.fill"
        case .supportingSentence:
            return "text.quote"
        case .teachingFocus:
            return "lightbulb.fill"
        case .paragraphTheme:
            return "bookmark.fill"
        case .passageRoot:
            return "book.fill"
        case .vocabularySupport:
            return "character.book.closed.fill"
        case .metaInstruction:
            return "info.circle.fill"
        case .answerKey:
            return "checkmark.seal.fill"
        }
    }
}

private struct TeachingTreeCanvasLayout {
    struct Entry: Identifiable {
        let node: OutlineNode
        let frame: CGRect

        var id: String { node.id }
    }

    let entries: [Entry]
    let contentBoundingRect: CGRect

    init(
        nodes: [OutlineNode],
        densityMode: OutlineCanvasDensityMode,
        highlightedNodeID: String?
    ) {
        let inset = densityMode.canvasInset
        var currentY: CGFloat = inset.height
        var maxX: CGFloat = 0
        var built: [Entry] = []

        for node in nodes {
            let frame = Self.frame(
                for: node,
                densityMode: densityMode,
                highlightedNodeID: highlightedNodeID,
                originY: currentY
            )
            built.append(Entry(node: node, frame: frame))
            currentY = frame.maxY + densityMode.rowSpacing
            maxX = max(maxX, frame.maxX)
        }

        self.entries = built
        self.contentBoundingRect = CGRect(
            x: 0,
            y: 0,
            width: max(maxX + inset.width, 320),
            height: max(currentY + inset.height, 240)
        )
    }

    private static func frame(
        for node: OutlineNode,
        densityMode: OutlineCanvasDensityMode,
        highlightedNodeID: String?,
        originY: CGFloat
    ) -> CGRect {
        let depth = max(node.depth, 0)
        let inset = densityMode.canvasInset
        let width = max(densityMode.minWidth, densityMode.baseWidth - CGFloat(min(depth, 4)) * 26)
        let x = inset.width + CGFloat(depth) * densityMode.indent
        let titleCount = max(min(node.title.count, densityMode.titleLineLimit * 22), 12)
        let titleLines = min(CGFloat(densityMode.titleLineLimit), ceil(CGFloat(titleCount) / (densityMode == .detailed ? 18 : 21)))
        let shouldShowSummary = densityMode == .detailed || highlightedNodeID == node.id || depth <= 1
        let summaryCount = max(min(node.summary.count, densityMode.summaryLineLimit * 34), 12)
        let summaryLines = shouldShowSummary
            ? min(CGFloat(densityMode.summaryLineLimit), ceil(CGFloat(summaryCount) / (densityMode == .detailed ? 28 : 32)))
            : 0
        let shouldShowAnchor = densityMode == .detailed || highlightedNodeID == node.id || depth == 0
        let height = (densityMode == .detailed ? 60 : 48)
            + titleLines * (densityMode == .detailed ? 20 : 18)
            + summaryLines * (densityMode == .detailed ? 18 : 16)
            + (shouldShowAnchor ? 28 : 0)

        return CGRect(x: x, y: originY, width: width, height: height)
    }

    func entry(id: String) -> Entry? {
        entries.first(where: { $0.node.id == id })
    }
}

private struct TeachingTreeMiniMap: View {
    let layout: TeachingTreeCanvasLayout
    let highlightedNodeID: String?
    let densityMode: OutlineCanvasDensityMode
    let viewportRect: CGRect
    let onNodeTap: (OutlineNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("教学树概览")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.72))
                Spacer(minLength: 0)
                Text(densityMode.rawValue)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.45))
            }

            GeometryReader { proxy in
                let contentWidth = max(layout.contentBoundingRect.width, 1)
                let contentHeight = max(layout.contentBoundingRect.height, 1)
                let scale = min((proxy.size.width - 12) / contentWidth, (proxy.size.height - 12) / contentHeight)
                let adjustedScale = max(scale, 0.12)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.52))

                    ForEach(layout.entries) { entry in
                        let frame = entry.frame

                        Button {
                            onNodeTap(entry.node)
                        } label: {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(accentColor(for: entry.node).opacity(entry.node.id == highlightedNodeID ? 0.8 : 0.42))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .stroke(entry.node.id == highlightedNodeID ? Color.black.opacity(0.18) : .clear, lineWidth: 1)
                                )
                                .frame(
                                    width: max(frame.width * adjustedScale, 18),
                                    height: max(frame.height * adjustedScale, 8)
                                )
                        }
                        .buttonStyle(.plain)
                        .position(
                            x: frame.minX * adjustedScale + max(frame.width * adjustedScale, 18) / 2 + 6,
                            y: frame.minY * adjustedScale + max(frame.height * adjustedScale, 8) / 2 + 6
                        )
                    }

                    if !viewportRect.isNull {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.black.opacity(0.32), lineWidth: 1.2)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.white.opacity(0.12))
                            )
                            .frame(
                                width: max(viewportRect.width * adjustedScale, 26),
                                height: max(viewportRect.height * adjustedScale, 16)
                            )
                            .position(
                                x: viewportRect.minX * adjustedScale + max(viewportRect.width * adjustedScale, 26) / 2 + 6,
                                y: viewportRect.minY * adjustedScale + max(viewportRect.height * adjustedScale, 16) / 2 + 6
                            )
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: 152)
        }
        .padding(12)
        .frame(width: 196)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
    }

    private func accentColor(for node: OutlineNode) -> Color {
        switch node.nodeType {
        case .passageRoot:
            return .blue
        case .paragraphTheme:
            return .indigo
        case .teachingFocus:
            return .orange
        case .supportingSentence:
            return .cyan
        case .questionLink:
            return .pink
        case .vocabularySupport:
            return .teal
        case .metaInstruction:
            return .gray
        case .answerKey:
            return .yellow
        }
    }
}
