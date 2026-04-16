import SwiftUI

struct TeachingTreeCanvasView: View {
    let nodes: [OutlineNode]
    let highlightedNodeID: String?
    let jumpTargetNodeID: String?
    let ancestorNodeIDs: [String]
    let onNodeTap: (OutlineNode) -> Void
    let onJumpHandled: () -> Void
    let onClose: (() -> Void)?

    init(
        nodes: [OutlineNode],
        highlightedNodeID: String?,
        jumpTargetNodeID: String?,
        ancestorNodeIDs: [String],
        onNodeTap: @escaping (OutlineNode) -> Void,
        onJumpHandled: @escaping () -> Void,
        onClose: (() -> Void)? = nil
    ) {
        self.nodes = nodes
        self.highlightedNodeID = highlightedNodeID
        self.jumpTargetNodeID = jumpTargetNodeID
        self.ancestorNodeIDs = ancestorNodeIDs
        self.onNodeTap = onNodeTap
        self.onJumpHandled = onJumpHandled
        self.onClose = onClose
    }

    var body: some View {
        StructureTreePreviewView(
            nodes: nodes,
            highlightedNodeID: highlightedNodeID,
            jumpTargetNodeID: jumpTargetNodeID,
            ancestorNodeIDs: ancestorNodeIDs,
            onNodeTap: onNodeTap,
            onJumpHandled: onJumpHandled,
            onClose: onClose,
            fillsAvailableHeight: false,
            showsToolbar: true,
            initialDensityMode: .detailed
        )
    }
}

struct SourceOutlineTab: View {
    let nodes: [OutlineNode]
    let highlightedNodeID: String?
    let jumpTargetNodeID: String?
    let ancestorNodeIDs: [String]
    let onNodeTap: (OutlineNode) -> Void
    let onJumpHandled: () -> Void
    let onClose: (() -> Void)?

    init(
        nodes: [OutlineNode],
        highlightedNodeID: String?,
        jumpTargetNodeID: String?,
        ancestorNodeIDs: [String],
        onNodeTap: @escaping (OutlineNode) -> Void,
        onJumpHandled: @escaping () -> Void,
        onClose: (() -> Void)? = nil
    ) {
        self.nodes = nodes
        self.highlightedNodeID = highlightedNodeID
        self.jumpTargetNodeID = jumpTargetNodeID
        self.ancestorNodeIDs = ancestorNodeIDs
        self.onNodeTap = onNodeTap
        self.onJumpHandled = onJumpHandled
        self.onClose = onClose
    }

    var body: some View {
        TeachingTreeCanvasView(
            nodes: nodes,
            highlightedNodeID: highlightedNodeID,
            jumpTargetNodeID: jumpTargetNodeID,
            ancestorNodeIDs: ancestorNodeIDs,
            onNodeTap: onNodeTap,
            onJumpHandled: onJumpHandled,
            onClose: onClose
        )
    }
}
