import Combine
import CoreGraphics
import SwiftUI

@MainActor
final class MindMapWorkspaceViewModel: ObservableObject {
    let documentTitle: String

    @Published private(set) var rootNode: MindMapNode?
    @Published private(set) var mainlineNodes: [MindMapNode] = []
    @Published private(set) var auxiliaryNodes: [MindMapNode] = []
    @Published private(set) var rejectedNodes: [MindMapNode] = []
    @Published private(set) var diagnostics: [MindMapAdmissionDiagnostic] = []
    @Published private(set) var isUsingFallback = false
    @Published private(set) var fallbackMessage: String?
    @Published private(set) var materialMode: MaterialAnalysisMode = .passageReading

    @Published var selectedNodeID: String?
    @Published var highlightedNodeID: String?
    @Published var densityMode: MindMapDensityMode = .detailed
    @Published var showsAuxiliary = false
    @Published var showsDiagnostics = false
    @Published var zoomScale: CGFloat = 1
    @Published var contentOffset: CGSize = .zero
    @Published private(set) var visibleRect: CGRect = .zero
    @Published private(set) var contentBoundingRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @Published private(set) var layoutSnapshot: MindMapLayoutSnapshot = .empty

    private var bundle: StructuredSourceBundle
    private var passageMap: PassageMap?
    private var admissionResult: MindMapAdmissionResult?
    private var nodeIndex: [String: MindMapNode] = [:]
    private var parentIndex: [String: String] = [:]
    private var containerSize: CGSize = .zero
    private var simplifiedMode = false
    private var hasAppliedInitialFit = false
    private var expandedParagraphNodeID: String?

    init(documentTitle: String, bundle: StructuredSourceBundle) {
        self.documentTitle = documentTitle
        self.bundle = bundle
        rebuildDomainState()
    }

    var selectedNode: MindMapNode? {
        if let selectedNodeID, let selectedNode = nodeIndex[selectedNodeID] {
            return selectedNode
        }
        if let highlightedNodeID, let highlightedNode = nodeIndex[highlightedNodeID] {
            return highlightedNode
        }
        return rootNode
    }

    func refresh(bundle: StructuredSourceBundle) {
        self.bundle = bundle
        rebuildDomainState()
        rebuildLayout(fitIfNeeded: true)
    }

    func updateContainerSize(_ size: CGSize, simplifiedMode: Bool) {
        let normalized = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        let sizeChanged = normalized != containerSize
        let presentationChanged = simplifiedMode != self.simplifiedMode
        guard sizeChanged || presentationChanged else { return }
        containerSize = normalized
        self.simplifiedMode = simplifiedMode
        rebuildLayout(fitIfNeeded: true)
    }

    func updateFocus(sentenceID: String?, segmentIDs: Set<String>) {
        let resolvedNode = resolveFocusNode(sentenceID: sentenceID, segmentIDs: segmentIDs)
        highlightedNodeID = resolvedNode?.id
        if selectedNodeID == nil {
            selectedNodeID = resolvedNode?.id ?? rootNode?.id
        }
        if simplifiedMode, let paragraphID = paragraphNodeID(containing: resolvedNode?.id) {
            expandedParagraphNodeID = paragraphID
            rebuildLayout(fitIfNeeded: false)
        }
    }

    func selectNode(_ nodeID: String) {
        guard nodeIndex[nodeID] != nil else { return }
        selectedNodeID = nodeID
        highlightedNodeID = nodeID
        if simplifiedMode {
            expandedParagraphNodeID = paragraphNodeID(containing: nodeID)
            rebuildLayout(fitIfNeeded: false)
        }
    }

    func updateDensityMode(_ mode: MindMapDensityMode) {
        guard densityMode != mode else { return }
        densityMode = mode
        rebuildLayout(fitIfNeeded: true)
    }

    func focusCurrentNode() {
        let targetID = selectedNodeID ?? highlightedNodeID ?? rootNode?.id
        guard let nodeID = targetID else { return }
        applyFocusRect(layoutSnapshot.focusRect(for: nodeID))
    }

    func fitToContent() {
        guard containerSize != .zero else { return }
        let contentRect = layoutSnapshot.contentBoundingRect
        guard contentRect.width > 0, contentRect.height > 0 else { return }

        let horizontalPadding: CGFloat = simplifiedMode ? 28 : 44
        let verticalPadding: CGFloat = simplifiedMode ? 24 : 40
        let availableWidth = max(containerSize.width - horizontalPadding * 2, 1)
        let availableHeight = max(containerSize.height - verticalPadding * 2, 1)
        let proposedScale = min(availableWidth / contentRect.width, availableHeight / contentRect.height)
        let clampedScale = clampScale(proposedScale)
        let proposedOffset = CGSize(
            width: (containerSize.width - (contentRect.width * clampedScale)) / 2 - (contentRect.minX * clampedScale),
            height: (containerSize.height - (contentRect.height * clampedScale)) / 2 - (contentRect.minY * clampedScale)
        )
        zoomScale = clampedScale
        contentOffset = clampOffset(proposedOffset, scale: clampedScale)
        updateVisibleRect()
        hasAppliedInitialFit = true
    }

    func applyViewport(scale: CGFloat, offset: CGSize) {
        let clampedScale = clampScale(scale)
        zoomScale = clampedScale
        contentOffset = clampOffset(offset, scale: clampedScale)
        updateVisibleRect()
    }

    func centerViewport(at logicalPoint: CGPoint) {
        guard containerSize != .zero else { return }
        let proposedOffset = CGSize(
            width: (containerSize.width / 2) - (logicalPoint.x * zoomScale),
            height: (containerSize.height / 2) - (logicalPoint.y * zoomScale)
        )
        contentOffset = clampOffset(proposedOffset, scale: zoomScale)
        updateVisibleRect()
    }

    func visibleNodes(for visibleRect: CGRect) -> [MindMapNode] {
        let visibleIDs = layoutSnapshot.visibleNodeIDs(in: visibleRect)
        return visibleIDs.compactMap { nodeIndex[$0] }
    }

    private func rebuildDomainState() {
        let resolvedPassageMap = bundle.passageMap ?? MindMapAdmissionService.buildPassageMap(from: bundle)
        let resolvedAdmission = bundle.mindMapAdmissionResult
            ?? MindMapAdmissionService.admit(bundle: bundle, passageMap: resolvedPassageMap)

        passageMap = resolvedPassageMap
        admissionResult = resolvedAdmission
        mainlineNodes = resolvedAdmission.mainlineNodes
        auxiliaryNodes = resolvedAdmission.auxiliaryNodes
        rejectedNodes = resolvedAdmission.rejectedNodes
        diagnostics = resolvedAdmission.diagnostics
        rootNode = resolvedAdmission.mainlineNodes.first(where: { $0.kind == .root })
        materialMode = bundle.passageAnalysisDiagnostics?.materialMode ?? .passageReading
        rebuildIndices()

        let fallbackInProvenance = resolvedPassageMap.paragraphMaps.contains { $0.provenance.generatedFrom == .localFallback }
            || resolvedAdmission.mainlineNodes.contains { $0.provenance.generatedFrom == .localFallback }
        let fallbackInText = resolvedPassageMap.authorCoreQuestion.contains("本地结构骨架")
            || resolvedPassageMap.authorCoreQuestion.contains("暂不可用")
            || resolvedPassageMap.authorCoreQuestion.contains("结构骨架")
        isUsingFallback = fallbackInProvenance || fallbackInText || materialMode != .passageReading
        fallbackMessage = isUsingFallback
            ? (bundle.passageAnalysisDiagnostics?.fallbackMessage
                ?? "AI 地图分析暂不可用，已展示本地结构骨架。")
            : nil
        if materialMode != .passageReading, !auxiliaryNodes.isEmpty {
            showsAuxiliary = true
        }

        if let selectedNodeID, nodeIndex[selectedNodeID] == nil {
            self.selectedNodeID = nil
        }
        if let highlightedNodeID, nodeIndex[highlightedNodeID] == nil {
            self.highlightedNodeID = nil
        }
        if selectedNodeID == nil {
            selectedNodeID = rootNode?.id
        }
    }

    private func rebuildIndices() {
        nodeIndex = [:]
        parentIndex = [:]
        guard let rootNode else { return }

        func walk(node: MindMapNode, parentID: String?) {
            nodeIndex[node.id] = node
            if let parentID {
                parentIndex[node.id] = parentID
            }
            for child in node.children {
                walk(node: child, parentID: node.id)
            }
        }

        walk(node: rootNode, parentID: nil)
        for node in auxiliaryNodes {
            nodeIndex[node.id] = node
        }
        for node in rejectedNodes {
            nodeIndex[node.id] = node
        }
    }

    private func rebuildLayout(fitIfNeeded: Bool) {
        layoutSnapshot = MindMapLayout.makeLayout(
            rootNode: rootNode,
            density: densityMode,
            containerSize: containerSize,
            simplified: simplifiedMode,
            expandedParagraphNodeID: expandedParagraphNodeID
        )
        contentBoundingRect = layoutSnapshot.contentBoundingRect
        if fitIfNeeded || !hasAppliedInitialFit {
            fitToContent()
        } else {
            contentOffset = clampOffset(contentOffset, scale: zoomScale)
            updateVisibleRect()
        }
    }

    private func resolveFocusNode(sentenceID: String?, segmentIDs: Set<String>) -> MindMapNode? {
        if let sentenceID {
            if let exactSentence = nodeIndex.values.first(where: { $0.provenance.sourceSentenceID == sentenceID && $0.admission == .mainline }) {
                return exactSentence
            }
            if let paragraphBySentence = nodeIndex.values.first(where: { $0.kind == .paragraph && $0.provenance.sourceSentenceID == sentenceID && $0.admission == .mainline }) {
                return paragraphBySentence
            }
        }

        if !segmentIDs.isEmpty,
           let paragraphNode = nodeIndex.values.first(where: {
               $0.kind == .paragraph &&
               $0.admission == .mainline &&
               segmentIDs.contains($0.provenance.sourceSegmentID ?? "")
           }) {
            return paragraphNode
        }

        return rootNode
    }

    private func paragraphNodeID(containing nodeID: String?) -> String? {
        guard let nodeID else { return nil }
        if nodeIndex[nodeID]?.kind == .paragraph {
            return nodeID
        }
        var cursor = nodeID
        while let parentID = parentIndex[cursor] {
            if nodeIndex[parentID]?.kind == .paragraph {
                return parentID
            }
            cursor = parentID
        }
        return nil
    }

    private func applyFocusRect(_ rect: CGRect) {
        guard containerSize != .zero else { return }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let proposedOffset = CGSize(
            width: (containerSize.width / 2) - (center.x * zoomScale),
            height: (containerSize.height / 2) - (center.y * zoomScale)
        )
        contentOffset = clampOffset(proposedOffset, scale: zoomScale)
        updateVisibleRect()
    }

    private func clampScale(_ scale: CGFloat) -> CGFloat {
        let lowerBound: CGFloat = simplifiedMode ? 0.42 : 0.35
        let upperBound: CGFloat = simplifiedMode ? 2.0 : 2.2
        return min(max(scale, lowerBound), upperBound)
    }

    private func clampOffset(_ proposed: CGSize, scale: CGFloat) -> CGSize {
        let contentRect = layoutSnapshot.contentBoundingRect
        guard containerSize != .zero, contentRect.width > 0, contentRect.height > 0 else {
            return proposed
        }

        let margin: CGFloat = simplifiedMode ? 48 : 72
        let scaledWidth = contentRect.width * scale
        let scaledHeight = contentRect.height * scale

        let x: CGFloat
        if scaledWidth + margin * 2 <= containerSize.width {
            x = (containerSize.width - scaledWidth) / 2 - (contentRect.minX * scale)
        } else {
            let minimum = containerSize.width - (contentRect.maxX * scale) - margin
            let maximum = margin - (contentRect.minX * scale)
            x = min(max(proposed.width, minimum), maximum)
        }

        let y: CGFloat
        if scaledHeight + margin * 2 <= containerSize.height {
            y = (containerSize.height - scaledHeight) / 2 - (contentRect.minY * scale)
        } else {
            let minimum = containerSize.height - (contentRect.maxY * scale) - margin
            let maximum = margin - (contentRect.minY * scale)
            y = min(max(proposed.height, minimum), maximum)
        }

        return CGSize(width: x, height: y)
    }

    private func updateVisibleRect() {
        guard zoomScale > 0 else {
            visibleRect = contentBoundingRect
            return
        }
        visibleRect = CGRect(
            x: (-contentOffset.width) / zoomScale,
            y: (-contentOffset.height) / zoomScale,
            width: containerSize.width / zoomScale,
            height: containerSize.height / zoomScale
        )
    }
}
