import SwiftUI

struct MindMapCanvasView: View {
    @ObservedObject var viewModel: MindMapWorkspaceViewModel

    let simplified: Bool
    let onNodeTap: (MindMapNode) -> Void

    @State private var dragOrigin: CGSize = .zero
    @State private var scaleOrigin: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let snapshot = viewModel.layoutSnapshot
            let visibleNodes = viewModel.visibleNodes(for: viewModel.visibleRect)
            let visibleIDs = Set(visibleNodes.map(\.id))

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(red: 0.974, green: 0.981, blue: 0.994))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.86), lineWidth: 1)
                    )

                ZStack(alignment: .topLeading) {
                    ForEach(snapshot.edgePaths.filter { visibleIDs.contains($0.fromNodeID) || visibleIDs.contains($0.toNodeID) }) { edge in
                        edgePath(edge)
                            .stroke(
                                Color(red: 0.55, green: 0.64, blue: 0.78).opacity(0.42),
                                style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round)
                            )
                    }

                    ForEach(visibleNodes) { node in
                        if let frame = snapshot.nodeFrames[node.id] {
                            MindMapCanvasNodeCard(
                                node: node,
                                density: snapshot.density,
                                isSelected: node.id == viewModel.selectedNodeID,
                                isHighlighted: node.id == viewModel.highlightedNodeID,
                                simplified: simplified
                            )
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                            .onTapGesture {
                                viewModel.selectNode(node.id)
                                onNodeTap(node)
                            }
                        }
                    }
                }
                .scaleEffect(viewModel.zoomScale, anchor: .topLeading)
                .offset(viewModel.contentOffset)

                if viewModel.isUsingFallback {
                    Label("本地结构骨架", systemImage: "sparkles.rectangle.stack")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.41, green: 0.47, blue: 0.2))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(red: 0.97, green: 0.95, blue: 0.77))
                        )
                        .padding(16)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture)
            .simultaneousGesture(zoomGesture)
            .onAppear {
                viewModel.updateContainerSize(proxy.size, simplifiedMode: simplified)
                if viewModel.selectedNodeID == nil {
                    viewModel.fitToContent()
                }
            }
            .onChange(of: proxy.size) { newSize in
                viewModel.updateContainerSize(newSize, simplifiedMode: simplified)
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragOrigin == .zero {
                    dragOrigin = viewModel.contentOffset
                }
                let proposed = CGSize(
                    width: dragOrigin.width + value.translation.width,
                    height: dragOrigin.height + value.translation.height
                )
                viewModel.applyViewport(scale: viewModel.zoomScale, offset: proposed)
            }
            .onEnded { _ in
                dragOrigin = .zero
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if scaleOrigin == 1 {
                    scaleOrigin = viewModel.zoomScale
                }
                let proposed = scaleOrigin * value
                viewModel.applyViewport(scale: proposed, offset: viewModel.contentOffset)
            }
            .onEnded { _ in
                scaleOrigin = 1
            }
    }

    private func edgePath(_ edge: MindMapLayoutEdge) -> Path {
        var path = Path()
        path.move(to: edge.start)
        path.addQuadCurve(to: edge.end, control: edge.control)
        return path
    }
}

private struct MindMapCanvasNodeCard: View {
    let node: MindMapNode
    let density: MindMapDensityMode
    let isSelected: Bool
    let isHighlighted: Bool
    let simplified: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(accentColor)
                    .frame(width: node.kind == .root ? 12 : 9, height: node.kind == .root ? 12 : 9)

                Text(node.title)
                    .font(titleFont)
                    .foregroundStyle(Color.black.opacity(0.82))
                    .lineLimit(titleLineLimit)

                Spacer(minLength: 0)
            }

            Text(node.summary)
                .font(summaryFont)
                .foregroundStyle(Color.black.opacity(0.62))
                .lineLimit(summaryLineLimit)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: node.kind == .root ? 24 : 20, style: .continuous)
                .fill(backgroundFill)
                .overlay(
                    RoundedRectangle(cornerRadius: node.kind == .root ? 24 : 20, style: .continuous)
                        .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
                )
        )
        .shadow(color: shadowColor, radius: isSelected ? 18 : 12, x: 0, y: isSelected ? 12 : 8)
    }

    private var accentColor: Color {
        switch node.kind {
        case .root:
            return Color(red: 0.2, green: 0.3, blue: 0.54)
        case .paragraph:
            return Color(red: 0.23, green: 0.51, blue: 0.74)
        case .teachingFocus:
            return Color(red: 0.79, green: 0.51, blue: 0.24)
        case .anchorSentence:
            return Color(red: 0.49, green: 0.59, blue: 0.29)
        case .evidence:
            return Color(red: 0.54, green: 0.44, blue: 0.72)
        case .vocabulary, .auxiliary:
            return Color(red: 0.55, green: 0.55, blue: 0.61)
        case .diagnostic:
            return Color.red.opacity(0.72)
        }
    }

    private var backgroundFill: LinearGradient {
        if isSelected {
            return LinearGradient(
                colors: [accentColor.opacity(0.18), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        if isHighlighted {
            return LinearGradient(
                colors: [accentColor.opacity(0.12), Color.white.opacity(0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                node.kind == .root ? Color(red: 0.93, green: 0.96, blue: 1) : Color.white,
                Color(red: 0.982, green: 0.986, blue: 0.994)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        if isSelected { return accentColor.opacity(0.92) }
        if isHighlighted { return accentColor.opacity(0.5) }
        return Color.white.opacity(0.88)
    }

    private var shadowColor: Color {
        accentColor.opacity(isSelected ? 0.18 : 0.08)
    }

    private var titleFont: Font {
        switch node.kind {
        case .root:
            return .system(size: density == .compact ? 17 : 19, weight: .bold, design: .rounded)
        case .paragraph:
            return .system(size: density == .compact ? 15 : 16, weight: .semibold, design: .rounded)
        default:
            return .system(size: density == .compact ? 13 : 14, weight: .semibold, design: .rounded)
        }
    }

    private var summaryFont: Font {
        .system(size: density == .compact ? 11 : 12, weight: .medium, design: .rounded)
    }

    private var titleLineLimit: Int {
        density == .compact ? 1 : 2
    }

    private var summaryLineLimit: Int {
        if simplified, node.kind != .root, node.kind != .paragraph {
            return 1
        }
        return density == .compact ? 2 : 3
    }
}
