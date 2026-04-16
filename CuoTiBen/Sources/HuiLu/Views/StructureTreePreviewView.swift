import SwiftUI

struct StructureTreePreviewView: View {
    let nodes: [OutlineNode]
    let highlightedNodeID: String?
    let jumpTargetNodeID: String?
    let ancestorNodeIDs: [String]
    let onNodeTap: (OutlineNode) -> Void
    let onJumpHandled: () -> Void
    let onClose: (() -> Void)?
    let fillsAvailableHeight: Bool

    @State private var densityMode: StructureTreePreviewDensityMode = .detailed
    @State private var pendingCanvasCommand: StructureTreePreviewCanvasCommand?
    @State private var reportedScale: CGFloat = 1.0

    private var metrics: StructureTreePreviewMetrics {
        StructureTreePreviewMetrics(densityMode: densityMode)
    }

    init(
        nodes: [OutlineNode],
        highlightedNodeID: String?,
        jumpTargetNodeID: String?,
        ancestorNodeIDs: [String],
        onNodeTap: @escaping (OutlineNode) -> Void,
        onJumpHandled: @escaping () -> Void,
        onClose: (() -> Void)? = nil,
        fillsAvailableHeight: Bool = false
    ) {
        self.nodes = nodes
        self.highlightedNodeID = highlightedNodeID
        self.jumpTargetNodeID = jumpTargetNodeID
        self.ancestorNodeIDs = ancestorNodeIDs
        self.onNodeTap = onNodeTap
        self.onJumpHandled = onJumpHandled
        self.onClose = onClose
        self.fillsAvailableHeight = fillsAvailableHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StructureTreePreviewToolbar(
                densityMode: densityMode,
                scalePercentage: Int((reportedScale * 100).rounded()),
                onDensityChange: { densityMode = $0 },
                onZoomIn: { issueCanvasCommand(.zoomIn) },
                onZoomOut: { issueCanvasCommand(.zoomOut) },
                onFocus: { issueCanvasCommand(.focus) },
                onClose: onClose
            )

            StructureTreePreviewCanvas(
                nodes: nodes,
                highlightedNodeID: highlightedNodeID,
                jumpTargetNodeID: jumpTargetNodeID,
                ancestorNodeIDs: ancestorNodeIDs,
                densityMode: densityMode,
                command: pendingCanvasCommand,
                onScaleChanged: { reportedScale = $0 },
                onNodeTap: onNodeTap,
                onJumpHandled: onJumpHandled
            )
            .frame(maxWidth: .infinity)
            .frame(
                minHeight: fillsAvailableHeight ? nil : metrics.canvasViewportHeight,
                maxHeight: fillsAvailableHeight ? .infinity : metrics.canvasViewportHeight
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.88),
                            Color(red: 0.965, green: 0.973, blue: 0.99).opacity(0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 26, x: 0, y: 18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func issueCanvasCommand(_ action: StructureTreePreviewCanvasCommand.Action) {
        pendingCanvasCommand = StructureTreePreviewCanvasCommand(action: action)
    }
}

struct StructureTreeWorkspaceOverlay: View {
    let title: String
    let nodes: [OutlineNode]
    let highlightedNodeID: String?
    let jumpTargetNodeID: String?
    let ancestorNodeIDs: [String]
    let onNodeTap: (OutlineNode) -> Void
    let onJumpHandled: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("教学树工作区")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.84))

                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(StructureTreePreviewPalette.mutedText)
                        .lineLimit(1)
                }

                StructureTreePreviewView(
                    nodes: nodes,
                    highlightedNodeID: highlightedNodeID,
                    jumpTargetNodeID: jumpTargetNodeID,
                    ancestorNodeIDs: ancestorNodeIDs,
                    onNodeTap: onNodeTap,
                    onJumpHandled: onJumpHandled,
                    onClose: onClose,
                    fillsAvailableHeight: true
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.94),
                                Color(red: 0.958, green: 0.968, blue: 0.988).opacity(0.98)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .stroke(Color.white.opacity(0.74), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.14), radius: 30, x: 0, y: 18)
            )
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }
}
