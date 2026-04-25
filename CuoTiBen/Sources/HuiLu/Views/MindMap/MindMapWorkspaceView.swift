import SwiftUI

enum MindMapWorkspaceDisplayMode {
    case fullScreen
    case embeddedCard
    case sidebar
}

struct MindMapWorkspaceView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let documentTitle: String
    let bundle: StructuredSourceBundle
    let focusSentenceID: String?
    let focusSegmentIDs: Set<String>
    let displayMode: MindMapWorkspaceDisplayMode
    let onNodeTap: (MindMapNode) -> Void
    let onClose: (() -> Void)?
    let onRegenerate: (() -> Void)?

    @StateObject private var viewModel: MindMapWorkspaceViewModel

    init(
        documentTitle: String,
        bundle: StructuredSourceBundle,
        focusSentenceID: String?,
        focusSegmentIDs: Set<String> = [],
        displayMode: MindMapWorkspaceDisplayMode = .embeddedCard,
        onNodeTap: @escaping (MindMapNode) -> Void,
        onClose: (() -> Void)? = nil,
        onRegenerate: (() -> Void)? = nil
    ) {
        self.documentTitle = documentTitle
        self.bundle = bundle
        self.focusSentenceID = focusSentenceID
        self.focusSegmentIDs = focusSegmentIDs
        self.displayMode = displayMode
        self.onNodeTap = onNodeTap
        self.onClose = onClose
        self.onRegenerate = onRegenerate
        _viewModel = StateObject(wrappedValue: MindMapWorkspaceViewModel(documentTitle: documentTitle, bundle: bundle))
    }

    private var usesSimplifiedMode: Bool {
        displayMode == .sidebar || horizontalSizeClass == .compact || UIDevice.current.userInterfaceIdiom == .phone
    }

    private var showsMiniMap: Bool {
        displayMode != .sidebar
    }

    private var refreshToken: String {
        let passageCount = bundle.passageMap?.paragraphMaps.count ?? -1
        let mainlineCount = bundle.mindMapAdmissionResult?.mainlineCount ?? -1
        let auxiliaryCount = bundle.mindMapAdmissionResult?.auxiliaryCount ?? -1
        let rejectedCount = bundle.mindMapAdmissionResult?.rejectedCount ?? -1
        return [documentTitle, "\(passageCount)", "\(mainlineCount)", "\(auxiliaryCount)", "\(rejectedCount)"].joined(separator: "#")
    }

    var body: some View {
        Group {
            if displayMode == .sidebar {
                sidebarLayout
            } else {
                workspaceCard
            }
        }
        .onAppear {
            viewModel.refresh(bundle: bundle)
            viewModel.updateFocus(sentenceID: focusSentenceID, segmentIDs: focusSegmentIDs)
        }
        .onChange(of: refreshToken) { _ in
            viewModel.refresh(bundle: bundle)
            viewModel.updateFocus(sentenceID: focusSentenceID, segmentIDs: focusSegmentIDs)
        }
        .onChange(of: focusSentenceID) { sentenceID in
            viewModel.updateFocus(sentenceID: sentenceID, segmentIDs: focusSegmentIDs)
        }
        .onChange(of: focusSegmentIDs) { segmentIDs in
            viewModel.updateFocus(sentenceID: focusSentenceID, segmentIDs: segmentIDs)
        }
    }

    private var workspaceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            MindMapToolbar(
                densityMode: viewModel.densityMode,
                showsAuxiliary: viewModel.showsAuxiliary,
                showsDiagnostics: viewModel.showsDiagnostics,
                isUsingFallback: viewModel.isUsingFallback,
                onDensityChange: { mode in
                    viewModel.updateDensityMode(mode)
                },
                onFitToContent: {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        viewModel.fitToContent()
                    }
                },
                onFocusCurrent: {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        viewModel.focusCurrentNode()
                    }
                },
                onToggleAuxiliary: {
                    viewModel.showsAuxiliary.toggle()
                },
                onToggleDiagnostics: {
                    viewModel.showsDiagnostics.toggle()
                },
                onRegenerate: { onRegenerate?() },
                onClose: onClose
            )

            if let fallbackMessage = viewModel.fallbackMessage {
                fallbackBanner(text: fallbackMessage)
            }

            if usesSimplifiedMode {
                compactWorkspace
            } else {
                regularWorkspace
            }
        }
        .padding(displayMode == .fullScreen ? 20 : 16)
        .background(
            RoundedRectangle(cornerRadius: displayMode == .fullScreen ? 30 : 26, style: .continuous)
                .fill(Color.white.opacity(0.84))
                .overlay(
                    RoundedRectangle(cornerRadius: displayMode == .fullScreen ? 30 : 26, style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(displayMode == .fullScreen ? 0.14 : 0.08), radius: displayMode == .fullScreen ? 24 : 16, x: 0, y: 12)
    }

    private var regularWorkspace: some View {
        HStack(alignment: .top, spacing: 16) {
            canvasArea(minHeight: displayMode == .fullScreen ? 540 : 360)

            VStack(spacing: 12) {
                if viewModel.showsAuxiliary {
                    auxiliaryPanel
                }
                if viewModel.showsDiagnostics {
                    diagnosticsPanel
                }
                selectedNodePanel
            }
            .frame(width: displayMode == .fullScreen ? 288 : 264)
        }
    }

    private var compactWorkspace: some View {
        VStack(spacing: 12) {
            canvasArea(minHeight: displayMode == .fullScreen ? 420 : 260)

            selectedNodePanel

            if viewModel.showsAuxiliary {
                auxiliaryPanel
            }

            if viewModel.showsDiagnostics {
                diagnosticsPanel
            }
        }
    }

    private func canvasArea(minHeight: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            MindMapCanvasView(viewModel: viewModel, simplified: usesSimplifiedMode) { node in
                onNodeTap(node)
            }
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity)

            if showsMiniMap {
                MindMapMiniMapView(
                    snapshot: viewModel.layoutSnapshot,
                    selectedNodeID: viewModel.selectedNode?.id,
                    visibleRect: viewModel.visibleRect
                ) { logicalPoint in
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                        viewModel.centerViewport(at: logicalPoint)
                    }
                }
                .padding(14)
            }
        }
    }

    private var selectedNodePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("当前节点")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.72))

            if let node = viewModel.selectedNode {
                VStack(alignment: .leading, spacing: 8) {
                    Text(node.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.82))
                    Text(node.summary)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.6))
                    Divider()
                    Text("来源：\(node.provenance.sourceKind.displayName)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.54))
                    if let segmentID = node.provenance.sourceSegmentID {
                        Text("段落：\(segmentID)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.54))
                    }
                    if let sentenceID = node.provenance.sourceSentenceID {
                        Text("句子：\(sentenceID)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.54))
                    }
                }
            } else {
                Text("当前还没有可聚焦的主图节点。")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.54))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.74))
        )
    }

    private var auxiliaryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("辅助层")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.72))
            if viewModel.auxiliaryNodes.isEmpty {
                Text("当前没有辅助节点。")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.54))
            } else {
                ForEach(viewModel.auxiliaryNodes.prefix(8)) { node in
                    Button {
                        viewModel.selectNode(node.id)
                        onNodeTap(node)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(node.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            Text(node.summary)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.58))
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.74))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.97, green: 0.973, blue: 0.986))
        )
    }

    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("准入诊断")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.72))

            VStack(alignment: .leading, spacing: 6) {
                Text("主线 \(viewModel.mainlineNodes.count) · 辅助 \(viewModel.auxiliaryNodes.count) · 拒绝 \(viewModel.rejectedNodes.count)")
                Text(String(format: "平均 hygiene %.2f · average consistency %.2f", diagnosticAverage(\.hygieneScore), diagnosticAverage(\.consistencyScore)))
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.58))

            ForEach(viewModel.diagnostics.prefix(4)) { diagnostic in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(diagnostic.nodeType.rawValue) · \(diagnostic.sourceKind.displayName)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(diagnostic.rejectedReason ?? "已通过准入。")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.58))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.74))
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.987, green: 0.976, blue: 0.972))
        )
    }

    private var sidebarLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("思维导图")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.72))
                Spacer()
                if viewModel.isUsingFallback {
                    Text("本地骨架")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.41, green: 0.47, blue: 0.2))
                }
            }

            MindMapCanvasView(viewModel: viewModel, simplified: true) { node in
                onNodeTap(node)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            viewModel.showsAuxiliary = false
            viewModel.showsDiagnostics = false
        }
    }

    private func fallbackBanner(text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(text)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(Color(red: 0.42, green: 0.38, blue: 0.15))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.986, green: 0.965, blue: 0.83))
        )
    }

    private func diagnosticAverage(_ keyPath: KeyPath<MindMapAdmissionDiagnostic, Double>) -> Double {
        guard !viewModel.diagnostics.isEmpty else { return 0 }
        return viewModel.diagnostics.map { $0[keyPath: keyPath] }.reduce(0, +) / Double(viewModel.diagnostics.count)
    }
}

struct MindMapWorkspaceOverlay: View {
    let documentTitle: String
    let bundle: StructuredSourceBundle
    let focusSentenceID: String?
    let focusSegmentIDs: Set<String>
    let onNodeTap: (MindMapNode) -> Void
    let onClose: () -> Void
    let onRegenerate: (() -> Void)?

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("思维导图工作区")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.84))

                    Text(documentTitle)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.54))
                        .lineLimit(1)
                }

                MindMapWorkspaceView(
                    documentTitle: documentTitle,
                    bundle: bundle,
                    focusSentenceID: focusSentenceID,
                    focusSegmentIDs: focusSegmentIDs,
                    displayMode: .fullScreen,
                    onNodeTap: onNodeTap,
                    onClose: onClose,
                    onRegenerate: onRegenerate
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
