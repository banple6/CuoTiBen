import SwiftUI

struct SourceOutlineTab: View {
    let documentTitle: String
    let bundle: StructuredSourceBundle
    let focusSentenceID: String?
    let focusSegmentIDs: Set<String>
    let onNodeTap: (MindMapNode) -> Void
    let onClose: (() -> Void)?
    let onRegenerate: (() -> Void)?

    init(
        documentTitle: String,
        bundle: StructuredSourceBundle,
        focusSentenceID: String?,
        focusSegmentIDs: Set<String> = [],
        onNodeTap: @escaping (MindMapNode) -> Void,
        onClose: (() -> Void)? = nil,
        onRegenerate: (() -> Void)? = nil
    ) {
        self.documentTitle = documentTitle
        self.bundle = bundle
        self.focusSentenceID = focusSentenceID
        self.focusSegmentIDs = focusSegmentIDs
        self.onNodeTap = onNodeTap
        self.onClose = onClose
        self.onRegenerate = onRegenerate
    }

    var body: some View {
        MindMapWorkspaceView(
            documentTitle: documentTitle,
            bundle: bundle,
            focusSentenceID: focusSentenceID,
            focusSegmentIDs: focusSegmentIDs,
            displayMode: .embeddedCard,
            onNodeTap: onNodeTap,
            onClose: onClose,
            onRegenerate: onRegenerate
        )
    }
}
