import SwiftUI

#if canImport(PencilKit)
import PencilKit

struct InkNoteCanvasView: View {
    @Binding var drawingData: Data
    @Binding var toolState: NoteInkToolState
    @Binding var pageCount: Int

    var appearance: NoteWorkspaceAppearance = .paper
    var doubleTapBehavior: NotePencilDoubleTapBehavior = .switchToEraser
    var suggestion: InkAssistSuggestion? = nil
    var onStopDrawing: ((Data, CGRect, CGSize) -> Void)? = nil
    var onResumeDrawing: (() -> Void)? = nil
    var onDismissSuggestion: (() -> Void)? = nil
    var onConfirmSuggestion: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            InkCanvasRepresentable(
                drawingData: $drawingData,
                toolState: $toolState,
                pageCount: $pageCount,
                appearance: appearance,
                doubleTapBehavior: doubleTapBehavior,
                onStopDrawing: onStopDrawing,
                onResumeDrawing: onResumeDrawing
            )

            if let suggestion {
                InkAssistSuggestionBubble(suggestion: suggestion) {
                    onConfirmSuggestion?()
                }
                .padding(.top, 14)
                .padding(.trailing, 14)
                .zIndex(5)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                onDismissSuggestion?()
            }
        )
    }
}

private struct InkCanvasRepresentable: UIViewRepresentable {
    @Binding var drawingData: Data
    @Binding var toolState: NoteInkToolState
    @Binding var pageCount: Int

    let appearance: NoteWorkspaceAppearance
    let doubleTapBehavior: NotePencilDoubleTapBehavior
    var onStopDrawing: ((Data, CGRect, CGSize) -> Void)?
    var onResumeDrawing: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            drawingData: $drawingData,
            toolState: $toolState,
            pageCount: $pageCount,
            doubleTapBehavior: doubleTapBehavior,
            onStopDrawing: onStopDrawing,
            onResumeDrawing: onResumeDrawing
        )
    }

    func makeUIView(context: Context) -> NotebookCanvasHostView {
        let hostView = NotebookCanvasHostView()
        hostView.scrollView.delegate = context.coordinator
        hostView.canvasView.delegate = context.coordinator
        hostView.configurePencilInteractionDelegate(context.coordinator)
        hostView.updateAppearance(appearance)
        hostView.canvasView.tool = toolState.pkTool

        if !drawingData.isEmpty,
           let drawing = try? PKDrawing(data: drawingData) {
            hostView.canvasView.drawing = drawing
        }

        context.coordinator.hostView = hostView
        return hostView
    }

    func updateUIView(_ uiView: NotebookCanvasHostView, context: Context) {
        context.coordinator.hostView = uiView
        context.coordinator.doubleTapBehavior = doubleTapBehavior
        uiView.scrollView.delegate = context.coordinator
        uiView.canvasView.delegate = context.coordinator
        uiView.configurePencilInteractionDelegate(context.coordinator)
        uiView.updateAppearance(appearance)

        let resolvedPageCount = max(pageCount, uiView.minimumPageCount(for: drawingData), 1)
        if resolvedPageCount != pageCount {
            DispatchQueue.main.async {
                pageCount = resolvedPageCount
            }
        }

        uiView.configureLayout(pageCount: resolvedPageCount, preserveVisibleRect: true)
        uiView.canvasView.tool = toolState.pkTool
        context.coordinator.sync(toolState: toolState)

        if drawingData.isEmpty, !uiView.canvasView.drawing.bounds.isEmpty {
            uiView.canvasView.drawing = PKDrawing()
            return
        }

        if !drawingData.isEmpty,
           let drawing = try? PKDrawing(data: drawingData),
           drawing.dataRepresentation() != uiView.canvasView.drawing.dataRepresentation() {
            uiView.canvasView.drawing = drawing
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIScrollViewDelegate {
        @Binding var drawingData: Data
        @Binding var toolState: NoteInkToolState
        @Binding var pageCount: Int

        weak var hostView: NotebookCanvasHostView?

        var doubleTapBehavior: NotePencilDoubleTapBehavior

        private let onStopDrawing: ((Data, CGRect, CGSize) -> Void)?
        private let onResumeDrawing: (() -> Void)?
        private var debounceWorkItem: DispatchWorkItem?
        private var lastDrawingToolState = NoteInkToolState()

        init(
            drawingData: Binding<Data>,
            toolState: Binding<NoteInkToolState>,
            pageCount: Binding<Int>,
            doubleTapBehavior: NotePencilDoubleTapBehavior,
            onStopDrawing: ((Data, CGRect, CGSize) -> Void)?,
            onResumeDrawing: (() -> Void)?
        ) {
            _drawingData = drawingData
            _toolState = toolState
            _pageCount = pageCount
            self.doubleTapBehavior = doubleTapBehavior
            self.onStopDrawing = onStopDrawing
            self.onResumeDrawing = onResumeDrawing
            self.lastDrawingToolState = toolState.wrappedValue
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawingData = canvasView.drawing.dataRepresentation()
            onResumeDrawing?()

            ensurePageCapacity(forInkBounds: canvasView.drawing.bounds)
            debounceWorkItem?.cancel()

            let snapshotData = canvasView.drawing.dataRepresentation()
            let snapshotBounds = canvasView.drawing.bounds
            let snapshotSize = hostView?.pageContentSize ?? canvasView.bounds.size

            let workItem = DispatchWorkItem { [weak self] in
                self?.onStopDrawing?(snapshotData, snapshotBounds, snapshotSize)
            }

            debounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            ensurePageCapacityForScroll()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostView?.zoomContainer
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            hostView?.updateContentInsetsForCurrentZoom()
        }

        func sync(toolState: NoteInkToolState) {
            if toolState.kind == .pen || toolState.kind == .highlighter {
                lastDrawingToolState = toolState
            }
        }

        private func ensurePageCapacity(forInkBounds bounds: CGRect) {
            guard let hostView, !bounds.isEmpty else { return }
            let required = Int(ceil((bounds.maxY + 220) / max(hostView.pageHeight, 1)))
            updatePageCountIfNeeded(required)
        }

        private func ensurePageCapacityForScroll() {
            guard let hostView else { return }
            let threshold = (CGFloat(pageCount) * hostView.pageHeight) - 180
            guard hostView.visibleBottomInPageContent() > threshold else { return }
            updatePageCountIfNeeded(pageCount + 1)
        }

        private func updatePageCountIfNeeded(_ candidate: Int) {
            // Cap at 11 pages to stay within Metal texture height limit (≈12000px)
            let clamped = min(max(candidate, 1), 11)
            guard clamped > pageCount else { return }
            DispatchQueue.main.async {
                self.pageCount = clamped
            }
        }
    }
}

private final class NotebookCanvasHostView: UIView {
    let scrollView = UIScrollView()
    let zoomContainer = UIView()
    let pageContentView = UIView()
    let paperBackgroundView = NotebookPaperBackgroundView()
    let canvasView = PKCanvasView()

    private(set) var pageContentSize: CGSize = .zero
    private(set) var pageHeight: CGFloat = 0
    private(set) var currentPageCount = 1

    private let verticalPadding: CGFloat = 20
    private let minimumHorizontalPadding: CGFloat = 20
    private var lastLayoutSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastLayoutSize else { return }
        lastLayoutSize = bounds.size
        configureLayout(pageCount: currentPageCount, preserveVisibleRect: true)
    }

    func configurePencilInteractionDelegate(_ delegate: UIPencilInteractionDelegate) {
        canvasView.interactions
            .compactMap { $0 as? UIPencilInteraction }
            .first?
            .delegate = delegate
    }

    func updateAppearance(_ appearance: NoteWorkspaceAppearance) {
        paperBackgroundView.appearance = appearance
        layer.masksToBounds = false
        backgroundColor = .clear
    }

    func configureLayout(pageCount: Int, preserveVisibleRect: Bool) {
        let resolvedPageCount = max(pageCount, 1)
        currentPageCount = resolvedPageCount

        guard bounds.width > 0, bounds.height > 0 else { return }

        let previousOffset = scrollView.contentOffset
        let pageWidth = min(max(bounds.width - 44, 820), 1280)
        let resolvedPageHeight = max(pageWidth * 1.28, bounds.height - 20)
        // Cap total content height to avoid Metal texture allocation failures (limit ≈ 16384).
        let maxContentHeight: CGFloat = 12000
        let contentHeight = min(resolvedPageHeight * CGFloat(resolvedPageCount), maxContentHeight)
        let horizontalPadding = max((bounds.width - pageWidth) * 0.5, minimumHorizontalPadding)

        pageHeight = resolvedPageHeight
        pageContentSize = CGSize(width: pageWidth, height: contentHeight)

        scrollView.frame = bounds

        let zoomContainerSize = CGSize(
            width: pageWidth + (horizontalPadding * 2),
            height: contentHeight + (verticalPadding * 2)
        )
        zoomContainer.frame = CGRect(origin: .zero, size: zoomContainerSize)
        scrollView.contentSize = zoomContainerSize

        pageContentView.frame = CGRect(
            x: horizontalPadding,
            y: verticalPadding,
            width: pageWidth,
            height: contentHeight
        )

        paperBackgroundView.frame = pageContentView.bounds
        paperBackgroundView.pageCount = resolvedPageCount
        paperBackgroundView.pageHeight = resolvedPageHeight
        paperBackgroundView.setNeedsDisplay()

        canvasView.frame = pageContentView.bounds
        updateContentInsetsForCurrentZoom()

        guard preserveVisibleRect else { return }
        let maxOffsetX = max(scrollView.contentSize.width * scrollView.zoomScale - scrollView.bounds.width, -scrollView.adjustedContentInset.left)
        let maxOffsetY = max(scrollView.contentSize.height * scrollView.zoomScale - scrollView.bounds.height, -scrollView.adjustedContentInset.top)
        scrollView.contentOffset = CGPoint(
            x: min(max(previousOffset.x, -scrollView.adjustedContentInset.left), maxOffsetX),
            y: min(max(previousOffset.y, -scrollView.adjustedContentInset.top), maxOffsetY)
        )
    }

    func minimumPageCount(for drawingData: Data) -> Int {
        guard !drawingData.isEmpty,
              let drawing = try? PKDrawing(data: drawingData),
              !drawing.bounds.isEmpty else {
            return 1
        }

        let estimatedHeight = max(drawing.bounds.maxY + 180, 1)
        let referencePageHeight = max(pageHeight, 980)
        return max(Int(ceil(estimatedHeight / referencePageHeight)), 1)
    }

    func visibleBottomInPageContent() -> CGFloat {
        let zoomScale = max(scrollView.zoomScale, 0.0001)
        let visibleBottom = (scrollView.contentOffset.y + scrollView.bounds.height) / zoomScale
        return visibleBottom - pageContentView.frame.minY
    }

    func updateContentInsetsForCurrentZoom() {
        let scaledWidth = zoomContainer.bounds.width * scrollView.zoomScale
        let scaledHeight = zoomContainer.bounds.height * scrollView.zoomScale
        let insetX = max((scrollView.bounds.width - scaledWidth) * 0.5, 0)
        let insetY = max((scrollView.bounds.height - scaledHeight) * 0.5, 0)
        scrollView.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }

    private func setup() {
        backgroundColor = .clear

        scrollView.backgroundColor = .clear
        scrollView.alwaysBounceVertical = true
        scrollView.alwaysBounceHorizontal = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.decelerationRate = .fast
        scrollView.minimumZoomScale = 0.72
        scrollView.maximumZoomScale = 2.4
        scrollView.bouncesZoom = true
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)

        zoomContainer.backgroundColor = .clear
        scrollView.addSubview(zoomContainer)

        pageContentView.backgroundColor = .clear
        zoomContainer.addSubview(pageContentView)

        paperBackgroundView.isOpaque = false
        paperBackgroundView.backgroundColor = .clear
        pageContentView.addSubview(paperBackgroundView)

        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.isScrollEnabled = false
        canvasView.drawingPolicy = .pencilOnly
        pageContentView.addSubview(canvasView)

        let pencilInteraction = UIPencilInteraction()
        canvasView.addInteraction(pencilInteraction)
    }
}

private final class NotebookPaperBackgroundView: UIView {
    var appearance: NoteWorkspaceAppearance = .paper {
        didSet { setNeedsDisplay() }
    }

    var pageCount: Int = 1 {
        didSet { setNeedsDisplay() }
    }

    var pageHeight: CGFloat = 1080 {
        didSet { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let topInset: CGFloat = 86
        let bottomInset: CGFloat = 28
        let lineSpacing: CGFloat = 34
        let marginX: CGFloat = 46
        let width = bounds.width

        for index in 0..<max(pageCount, 1) {
            let originY = CGFloat(index) * pageHeight
            let pageRect = CGRect(x: 0, y: originY, width: width, height: pageHeight)

            context.saveGState()
            let fillPath = UIBezierPath(rect: pageRect)
            appearance.notebookPageFillColor.setFill()
            fillPath.fill()
            context.restoreGState()

            let borderPath = UIBezierPath(rect: pageRect.insetBy(dx: 0.5, dy: 0.5))
            appearance.notebookPageBorderColor.setStroke()
            borderPath.lineWidth = 1
            borderPath.stroke()

            let rulePath = UIBezierPath()
            var y = pageRect.minY + topInset
            while y < pageRect.maxY - bottomInset {
                rulePath.move(to: CGPoint(x: pageRect.minX, y: y))
                rulePath.addLine(to: CGPoint(x: pageRect.maxX, y: y))
                y += lineSpacing
            }
            appearance.notebookRuleColor.setStroke()
            rulePath.lineWidth = 1
            rulePath.stroke()

            let marginPath = UIBezierPath()
            marginPath.move(to: CGPoint(x: pageRect.minX + marginX, y: pageRect.minY + 18))
            marginPath.addLine(to: CGPoint(x: pageRect.minX + marginX, y: pageRect.maxY - 18))
            appearance.notebookMarginColor.setStroke()
            marginPath.lineWidth = 1.6
            marginPath.stroke()

            if index < max(pageCount, 1) - 1 {
                let separatorPath = UIBezierPath()
                let separatorY = pageRect.maxY - 1
                separatorPath.move(to: CGPoint(x: pageRect.minX + 24, y: separatorY))
                separatorPath.addLine(to: CGPoint(x: pageRect.maxX - 24, y: separatorY))
                appearance.notebookDividerColor.setStroke()
                separatorPath.lineWidth = 2
                separatorPath.stroke()
            }
        }
    }
}

#else

struct InkNoteCanvasView: View {
    @Binding var drawingData: Data
    @Binding var toolState: NoteInkToolState
    @Binding var pageCount: Int
    var appearance: NoteWorkspaceAppearance = .paper
    var doubleTapBehavior: NotePencilDoubleTapBehavior = .switchToEraser
    var suggestion: InkAssistSuggestion? = nil
    var onStopDrawing: ((Data, CGRect, CGSize) -> Void)? = nil
    var onResumeDrawing: (() -> Void)? = nil
    var onDismissSuggestion: (() -> Void)? = nil
    var onConfirmSuggestion: (() -> Void)? = nil

    var body: some View {
        Text("当前设备不支持 PencilKit。")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.black.opacity(0.55))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.4))
    }
}

#endif

#if canImport(PencilKit)
private extension NoteInkToolState {
    var pkTool: PKTool {
        switch kind {
        case .pen:
            return PKInkingTool(.pen, color: UIColor(colorChoice.color), width: width)
        case .pencil:
            return PKInkingTool(.pencil, color: UIColor(colorChoice.color), width: width)
        case .ballpoint:
            return PKInkingTool(.pen, color: UIColor(colorChoice.color), width: width)
        case .highlighter:
            return PKInkingTool(.marker, color: UIColor(colorChoice.color.opacity(0.45)), width: width)
        case .eraser:
            return PKEraserTool(
                eraserPreset == .precise ? .vector : .bitmap,
                width: eraserWidth
            )
        case .lasso:
            return PKLassoTool()
        }
    }
}

private extension NoteWorkspaceAppearance {
    var notebookPageFillColor: UIColor {
        switch self {
        case .paper:
            return UIColor(red: 0.995, green: 0.992, blue: 0.978, alpha: 1)
        case .night:
            return UIColor(red: 0.16, green: 0.18, blue: 0.23, alpha: 1)
        case .eyeCare:
            return UIColor(red: 0.949, green: 0.964, blue: 0.902, alpha: 1)
        }
    }

    var notebookPageBorderColor: UIColor {
        UIColor(pageBorderColor)
    }

    var notebookRuleColor: UIColor {
        UIColor(pageLineColor)
    }

    var notebookMarginColor: UIColor {
        UIColor(marginLineColor)
    }

    var notebookDividerColor: UIColor {
        UIColor(pageLineColor.opacity(0.3))
    }
}

extension InkCanvasRepresentable.Coordinator: UIPencilInteractionDelegate {
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        switch doubleTapBehavior {
        case .switchToEraser:
            if toolState.kind == .eraser {
                toolState = lastDrawingToolState
            } else {
                if toolState.kind == .pen || toolState.kind == .highlighter {
                    lastDrawingToolState = toolState
                }
                toolState.kind = .eraser
            }
        case .switchToLasso:
            if toolState.kind == .lasso {
                toolState = lastDrawingToolState
            } else {
                if toolState.kind == .pen || toolState.kind == .highlighter {
                    lastDrawingToolState = toolState
                }
                toolState.kind = .lasso
            }
        case .togglePenHighlighter:
            if toolState.kind == .highlighter {
                toolState.kind = .pen
            } else {
                toolState.kind = .highlighter
            }
            lastDrawingToolState = toolState
        case .ignore:
            break
        }
    }
}
#endif
