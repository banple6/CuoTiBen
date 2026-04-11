import SwiftUI
import UIKit

#if canImport(PencilKit)
import PencilKit
#endif

// ╔══════════════════════════════════════════════════════════════╗
// ║  NotebookPageCanvasView — Blank Notebook Page                ║
// ║                                                              ║
// ║  UIKit-hosted architecture:                                  ║
// ║    UIScrollView (finger scrolls via allowedTouchTypes)       ║
// ║      └─ contentView (UIView)                                 ║
// ║           ├─ paperHost (UIHostingController: bg + text)      ║
// ║           └─ PKCanvasView (drawingPolicy = .pencilOnly)      ║
// ║                                                              ║
// ║  Pencil → PKCanvasView draws (natively, no hitTest hack)    ║
// ║  Finger → UIScrollView scrolls; taps reach paper host       ║
// ╚══════════════════════════════════════════════════════════════╝

// MARK: - Design Tokens

private enum PT {
    static let paperFill    = Color(red: 0.995, green: 0.992, blue: 0.978)
    static let ruleColor    = Color(red: 0.82, green: 0.82, blue: 0.78).opacity(0.35)
    static let marginColor  = Color(red: 0.85, green: 0.25, blue: 0.25).opacity(0.18)
    static let ink          = Color(red: 0.08, green: 0.08, blue: 0.06)
    static let accent       = Color(red: 0, green: 0.365, blue: 0.655)
    static let quoteBar     = Color(red: 0, green: 0.365, blue: 0.655).opacity(0.5)
    static let tagFill      = Color(red: 0.89, green: 0.93, blue: 0.97)
    static let tagText      = Color(red: 0, green: 0.365, blue: 0.655)
    static let divider      = Color(red: 0.82, green: 0.82, blue: 0.78).opacity(0.25)
    static let muted        = Color(red: 0.45, green: 0.45, blue: 0.42)
    static let lineSpacing: CGFloat = 34
    static let marginX:     CGFloat = 52
    static let topInset:    CGFloat = 64
    static let leading:     CGFloat = 72
    static let trailing:    CGFloat = 48
}

// ═══════════════════════════════════════════════════════════════
// MARK: - NotebookPageCanvasView (SwiftUI entry)
// ═══════════════════════════════════════════════════════════════

struct NotebookPageCanvasView: View {
    @ObservedObject var vm: NoteWorkspaceViewModel
    let appViewModel: AppViewModel
    @Binding var inkToolState: NoteInkToolState
    let isTextMode: Bool
    let isSelectMode: Bool
    let isTextObjectInteractionMode: Bool
    let doubleTapBehavior: NotePencilDoubleTapBehavior
    @Binding var editorSelection: EditorSelection
    let inkActionBridge: InkActionBridge
    let onOpenSource: (SourceAnchor) -> Void

    @State private var pageCount: Int = 1
    @State private var contentHeight: CGFloat = 800

    /// Maximum canvas page height — Metal texture limit is 16384 px;
    /// divide by screen scale so the backing store never exceeds that.
    /// On 2× Retina → 8192 pt, on 3× → 5461 pt.
    private static let maxPageHeight: CGFloat = floor(16384 / UIScreen.main.scale)

    var body: some View {
        GeometryReader { geo in
            let paper = vm.paperConfiguration
            let pageWidth = min(max(geo.size.width - 40, 820), 1280)
            let baseH = max(paper.lineSpacing * CGFloat(max(pageCount, 1)) * 30,
                            geo.size.height - 20)
            let pageH = min(max(max(baseH, paper.size.height), contentHeight + 300), Self.maxPageHeight)

            NotebookScrollHost(
                initialInkData: initialInkData,
                viewportController: vm.viewportController,
                inkToolState: $inkToolState,
                pageWidth: pageWidth,
                pageHeight: pageH,
                isTextMode: isTextMode,
                isSelectMode: isSelectMode,
                isTextObjectInteractionMode: isTextObjectInteractionMode,
                doubleTapBehavior: doubleTapBehavior,
                editorSelection: $editorSelection,
                inkActionBridge: inkActionBridge,
                onInkChanged: {
                    vm.markInkDirty()
                    vm.scheduleAutosave(using: appViewModel, bridge: inkActionBridge)
                }
            ) {
                ZStack(alignment: .topLeading) {
                    PaperLayerView(pageWidth: pageWidth, pageHeight: pageH, paper: paper)

                    BackgroundReferenceLayerView(vm: vm, pageWidth: pageWidth)

                    CanvasObjectLayerView(
                        vm: vm,
                        pageWidth: pageWidth,
                        pageHeight: pageH,
                        appViewModel: appViewModel,
                        isTextMode: isTextMode,
                        isSelectMode: isSelectMode,
                        isTextObjectInteractionMode: isTextObjectInteractionMode,
                        editorSelection: $editorSelection,
                        onHeightChange: { h in
                            DispatchQueue.main.async { contentHeight = h }
                        }
                    )

                    CanvasOverlayLayerView(
                        vm: vm,
                        appViewModel: appViewModel,
                        isSelectMode: isSelectMode,
                        editorSelection: $editorSelection,
                        pageWidth: pageWidth,
                        pageHeight: pageH
                    )
                }
                .frame(width: pageWidth, height: pageH)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(PT.paperFill)
                        .shadow(color: .black.opacity(0.06), radius: 24, y: 12)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            pageCount = vm.blocks.first(where: { $0.kind == .ink })?.inkGeometry?.pageCount ?? 1
        }
    }

    /// Initial ink data from the ink block — passed to the canvas once at creation.
    private var initialInkData: Data {
        vm.blocks.first(where: { $0.kind == .ink })?.inkData ?? Data()
    }

}


// ═══════════════════════════════════════════════════════════════
// MARK: - NotebookScrollHost (UIViewControllerRepresentable)
// ═══════════════════════════════════════════════════════════════
//
//  Why UIViewControllerRepresentable instead of UIViewRepresentable?
//  Because we host a UIHostingController for the SwiftUI paper content
//  as a child VC, which requires proper VC containment.
//
//  Layout:
//    UIScrollView
//      └─ contentView (UIView, sized to page)
//           ├─ paperHostVC.view  (SwiftUI paper + text, bottom)
//           └─ canvasView        (PKCanvasView, top, pencil-only)
//
//  Key design decisions:
//    1. PKCanvasView.drawingPolicy = .pencilOnly
//       → PencilKit natively ignores finger input. No hitTest override needed.
//    2. UIScrollView.panGestureRecognizer.allowedTouchTypes = [.direct]
//       → Only finger drags scroll the page; pencil drags don't scroll.
//    3. canvasView.isScrollEnabled = false
//       → PKCanvasView won't try to scroll internally.
//    4. Finger taps on canvasView fall through because:
//       - PKCanvasView with .pencilOnly ignores finger touches
//       - The tap reaches the paper host below via responder chain

#if canImport(PencilKit)

struct NotebookScrollHost<Paper: View>: UIViewControllerRepresentable {
    let initialInkData: Data
    let viewportController: CanvasViewportController
    @Binding var inkToolState: NoteInkToolState
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let isTextMode: Bool
    let isSelectMode: Bool
    let isTextObjectInteractionMode: Bool
    let doubleTapBehavior: NotePencilDoubleTapBehavior
    @Binding var editorSelection: EditorSelection
    let inkActionBridge: InkActionBridge
    var onInkChanged: (() -> Void)?
    @ViewBuilder let paperContent: () -> Paper

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> NotebookScrollVC {
        let vc = NotebookScrollVC()
        let c = context.coordinator
        c.parent = self

        c.vc = vc
        vc.scrollView.delegate = c

        // Paper host
        let paperHost = UIHostingController(rootView: AnyView(paperContent()))
        paperHost.view.backgroundColor = .clear
        vc.addChild(paperHost)
        vc.contentView.addSubview(paperHost.view)
        paperHost.didMove(toParent: vc)
        c.paperHost = paperHost

        // Canvas
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .pencilOnly
        canvas.isScrollEnabled = false
        canvas.isUserInteractionEnabled = true
        // Ensure crisp Retina rendering — use the main screen's native scale.
        canvas.contentScaleFactor = UIScreen.main.scale
        canvas.tool = inkToolState.pkTool
        canvas.delegate = c
        vc.contentView.addSubview(canvas)
        c.canvas = canvas

        // Wire InkActionBridge to the canvas
        inkActionBridge.canvas = canvas

        // Load initial drawing (one-time; PKCanvasView is source of truth after this)
        if !initialInkData.isEmpty, let d = try? PKDrawing(data: initialInkData) {
            canvas.drawing = d
        }

        // Pencil double-tap
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = c
        canvas.addInteraction(pencilInteraction)

        // Sizing
        let sz = CGSize(width: pageWidth, height: pageHeight)
        vc.scrollView.contentSize = sz
        vc.contentView.frame = CGRect(origin: .zero, size: sz)
        paperHost.view.frame = CGRect(origin: .zero, size: sz)
        canvas.frame = CGRect(origin: .zero, size: sz)
        vc.applyViewportPolicy(viewportController)
        c.syncViewport(using: vc.scrollView)

        // Debug
        // print("[INK] makeUIVC: canvas.frame=\\(canvas.frame), policy=\\(canvas.drawingPolicy.rawValue), interaction=\\(canvas.isUserInteractionEnabled)")

        return vc
    }

    func updateUIViewController(_ vc: NotebookScrollVC, context: Context) {
        let c = context.coordinator
        c.parent = self

        // Keep ink action bridge pointed at the canvas
        inkActionBridge.canvas = c.canvas

        // Resize (threshold to prevent frame jitter during writing)
        let sz = CGSize(width: pageWidth, height: pageHeight)
        let cur = vc.scrollView.contentSize
        if abs(cur.width - sz.width) > 2 || abs(cur.height - sz.height) > 2 {
            vc.scrollView.contentSize = sz
            vc.contentView.frame = CGRect(origin: .zero, size: sz)
            c.paperHost?.view.frame = CGRect(origin: .zero, size: sz)
            c.canvas?.frame = CGRect(origin: .zero, size: sz)
        }

        // Ensure canvas always renders at native Retina scale
        if c.canvas?.contentScaleFactor != UIScreen.main.scale {
            c.canvas?.contentScaleFactor = UIScreen.main.scale
        }

        // Update paper content
        c.paperHost?.rootView = AnyView(paperContent())

        // Only update tool when it actually changed to avoid redundant delegate callbacks
        let newTool = inkToolState.pkTool
        if c.lastAppliedTool == nil || type(of: c.lastAppliedTool!) != type(of: newTool)
            || c.lastAppliedToolState != inkToolState {
            c.canvas?.tool = newTool
            c.lastAppliedTool = newTool
            c.lastAppliedToolState = inkToolState
        }

        // In text mode: disable canvas so finger taps 100% go to text fields
        // In ink mode: canvas is enabled, pencil draws, finger is ignored by .pencilOnly
        c.canvas?.isUserInteractionEnabled = !isTextMode

        vc.applyViewportPolicy(viewportController)
        vc.scrollView.isTextMode = isTextObjectInteractionMode
        vc.isTextMode = isTextObjectInteractionMode

        // NOTE: No drawing data sync here.
        // PKCanvasView is the sole source of truth for ink while the page is open.
        // Ink is synced to the data model only on save via syncInkFromBridge().
        c.syncViewport(using: vc.scrollView)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate, UIScrollViewDelegate {
        var parent: NotebookScrollHost!
        weak var vc: NotebookScrollVC?
        var paperHost: UIHostingController<AnyView>?
        weak var canvas: PKCanvasView?
        var lastAppliedTool: PKTool?
        var lastAppliedToolState: NoteInkToolState?
        private var debounce: DispatchWorkItem?
        private var lastToolState: NoteInkToolState?
        /// Tracks whether the current tool is a lasso and user has completed a stroke.
        private var lassoStrokeCompleted = false

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Mark dirty after a brief debounce. No SwiftUI state is written here —
            // the PKCanvasView holds the drawing as source of truth.
            debounce?.cancel()
            let cb = parent.onInkChanged
            let item = DispatchWorkItem {
                cb?()
            }
            debounce = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
        }

        func syncViewport(using scrollView: UIScrollView) {
            let zoom = max(scrollView.zoomScale, 0.001)
            let visibleRect = CGRect(
                x: scrollView.contentOffset.x / zoom,
                y: scrollView.contentOffset.y / zoom,
                width: scrollView.bounds.width / zoom,
                height: scrollView.bounds.height / zoom
            )
            let fitMode: CanvasViewportFitMode = abs(zoom - scrollView.minimumZoomScale) < 0.02 ? .fitWidth : .free
            parent.viewportController.update(
                zoomScale: zoom,
                contentOffset: scrollView.contentOffset,
                visibleRect: visibleRect,
                fitMode: fitMode
            )
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            vc?.contentView
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            syncViewport(using: scrollView)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            syncViewport(using: scrollView)
        }

        func canvasViewDidBeginUsingTool(_ cv: PKCanvasView) {
            // If user starts using any non-lasso tool, clear ink selection
            if !(cv.tool is PKLassoTool) {
                lassoStrokeCompleted = false
                if case .inkSelection = parent.editorSelection {
                    DispatchQueue.main.async { [weak self] in
                        self?.parent.editorSelection = .none
                    }
                }
            }
        }

        func canvasViewDidEndUsingTool(_ cv: PKCanvasView) {
            // When lasso tool finishes a stroke, assume user created a selection
            if cv.tool is PKLassoTool {
                lassoStrokeCompleted = true
                // Estimate selection bounds from recent drawing changes
                let bounds = cv.drawing.bounds
                DispatchQueue.main.async { [weak self] in
                    guard let self, let parent = self.parent else { return }
                    parent.inkActionBridge.selectionBounds = bounds
                    if case .inkSelection = parent.editorSelection { return }
                    parent.editorSelection = .inkSelection
                }
            }
        }

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            guard let parent = self.parent else { return }
            let saved = lastToolState ?? parent.inkToolState
            switch parent.doubleTapBehavior {
            case .switchToEraser:
                if parent.inkToolState.kind == .eraser {
                    parent.inkToolState = saved
                } else {
                    lastToolState = parent.inkToolState
                    parent.inkToolState.kind = .eraser
                }
            case .switchToLasso:
                if parent.inkToolState.kind == .lasso {
                    parent.inkToolState = saved
                } else {
                    lastToolState = parent.inkToolState
                    parent.inkToolState.kind = .lasso
                }
            case .togglePenHighlighter:
                if parent.inkToolState.kind == .highlighter {
                    parent.inkToolState = saved
                } else {
                    lastToolState = parent.inkToolState
                    parent.inkToolState.kind = .highlighter
                }
            case .ignore:
                break
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - NotebookScrollVC
// ═══════════════════════════════════════════════════════════════

/// Custom UIScrollView that suppresses touch cancellation in text mode,
/// allowing SwiftUI DragGesture on text objects to work without being
/// killed by the scroll view's internal touch-forwarding machinery.
final class CanvasScrollView: UIScrollView {
    var isTextMode = false

    /// In text mode, allow touch cancellation ONLY for 2-finger scroll.
    /// Single-finger content touches (text object drag) are protected by
    /// `minimumNumberOfTouches = 2` on the pan gesture — the scroll view
    /// won't try to recognize single-finger pan, so it won't cancel them.
    /// Returning `super` (true) here is essential so that 2-finger pan CAN
    /// cancel content touches and start scrolling.
}

final class NotebookScrollVC: UIViewController, UIGestureRecognizerDelegate {
    let scrollView = CanvasScrollView()
    let contentView = UIView()
    var isTextMode = false
    private var dismissTap: UITapGestureRecognizer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        scrollView.backgroundColor = .clear
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.bouncesZoom = true
        scrollView.delaysContentTouches = false
        scrollView.minimumZoomScale = 0.75
        scrollView.maximumZoomScale = 3.0

        // CRITICAL: Only finger (direct touch) can pan the scroll view.
        // Pencil (stylus) pan gestures are NOT claimed by the scroll view,
        // so PKCanvasView gets them for drawing.
        scrollView.panGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]
        if let pinch = scrollView.pinchGestureRecognizer {
            pinch.allowedTouchTypes = [
                NSNumber(value: UITouch.TouchType.direct.rawValue)
            ]
        }

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.backgroundColor = .clear

        // UIKit tap-to-dismiss: reliably resigns any UITextView first responder
        // when user taps blank space on the canvas (outside a UITextView).
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleDismissTap))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        scrollView.addGestureRecognizer(tap)
        dismissTap = tap
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
    }

    func applyViewportPolicy(_ controller: CanvasViewportController) {
        scrollView.minimumZoomScale = controller.minimumZoomScale
        scrollView.maximumZoomScale = controller.maximumZoomScale

        switch controller.gesturePolicy {
        case .standard, .selectionAware:
            scrollView.panGestureRecognizer.minimumNumberOfTouches = 1
        case .textEditing:
            scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        }
    }

    // MARK: - Dismiss keyboard on blank-area tap

    @objc private func handleDismissTap() {
        guard isTextMode else { return }
        view.endEditing(true)
    }

    // Only fire when tapping outside a UITextView
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dismissTap, isTextMode else { return true }
        let location = gestureRecognizer.location(in: contentView)
        let hitView = contentView.hitTest(location, with: nil)
        return !(hitView is UITextView)
    }

    // Allow simultaneous recognition with SwiftUI gestures
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        return gestureRecognizer === dismissTap
    }
}

#endif

// ═══════════════════════════════════════════════════════════════
// MARK: - Paper Background
// ═══════════════════════════════════════════════════════════════

private struct PaperBackground: View {
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let paper: NotePaperConfiguration

    var body: some View {
        Canvas { ctx, size in
            switch paper.style {
            case .plain:
                drawMarginGuide(in: &ctx, size: size)
            case .lined:
                drawLinedPaper(in: &ctx, size: size)
            case .grid:
                drawGridPaper(in: &ctx, size: size)
            case .dotted:
                drawDottedPaper(in: &ctx, size: size)
            case .cornell:
                drawCornellTemplate(in: &ctx, size: size)
            case .readingStudy:
                drawReadingStudyTemplate(in: &ctx, size: size)
            case .wrongAnswer:
                drawWrongAnswerTemplate(in: &ctx, size: size)
            }
        }
        .frame(width: pageWidth, height: pageHeight)
        .allowsHitTesting(false)
    }

    private var spacing: CGFloat {
        max(paper.lineSpacing, 24)
    }

    private var marginLeading: CGFloat {
        max(paper.marginInsets.leading, PT.leading)
    }

    private func drawLinedPaper(in ctx: inout GraphicsContext, size: CGSize) {
        drawHorizontalRules(in: &ctx, size: size, startY: paper.marginInsets.top, spacing: spacing)
        drawMarginGuide(in: &ctx, size: size)
    }

    private func drawGridPaper(in ctx: inout GraphicsContext, size: CGSize) {
        drawHorizontalRules(in: &ctx, size: size, startY: paper.marginInsets.top, spacing: spacing)
        var x = marginLeading
        while x < size.width - paper.marginInsets.trailing {
            ctx.stroke(
                Path { path in
                    path.move(to: CGPoint(x: x, y: paper.marginInsets.top))
                    path.addLine(to: CGPoint(x: x, y: size.height - paper.marginInsets.bottom))
                },
                with: .color(PT.ruleColor.opacity(0.8)),
                lineWidth: 0.45
            )
            x += spacing
        }
        drawMarginGuide(in: &ctx, size: size)
    }

    private func drawDottedPaper(in ctx: inout GraphicsContext, size: CGSize) {
        var y = paper.marginInsets.top
        while y < size.height - paper.marginInsets.bottom {
            var x = marginLeading
            while x < size.width - paper.marginInsets.trailing {
                let dot = CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2)
                ctx.fill(Path(ellipseIn: dot), with: .color(PT.ruleColor.opacity(0.75)))
                x += spacing
            }
            y += spacing
        }
        drawMarginGuide(in: &ctx, size: size)
    }

    private func drawCornellTemplate(in ctx: inout GraphicsContext, size: CGSize) {
        let cueColumnWidth = max(160, size.width * 0.2)
        let summaryHeight = max(160, size.height * 0.16)
        let contentTop = paper.marginInsets.top + 18
        let summaryTop = size.height - summaryHeight - paper.marginInsets.bottom

        drawHorizontalRules(in: &ctx, size: size, startY: contentTop, spacing: spacing, endY: summaryTop - 16)

        ctx.stroke(
            Path(CGRect(
                x: paper.marginInsets.leading,
                y: contentTop,
                width: cueColumnWidth,
                height: summaryTop - contentTop
            )),
            with: .color(PT.marginColor.opacity(0.9)),
            lineWidth: 1
        )
        ctx.stroke(
            Path { path in
                path.move(to: CGPoint(x: paper.marginInsets.leading + cueColumnWidth + 18, y: contentTop))
                path.addLine(to: CGPoint(x: paper.marginInsets.leading + cueColumnWidth + 18, y: summaryTop))
            },
            with: .color(PT.marginColor.opacity(0.9)),
            lineWidth: 1
        )
        ctx.stroke(
            Path { path in
                path.move(to: CGPoint(x: paper.marginInsets.leading, y: summaryTop))
                path.addLine(to: CGPoint(x: size.width - paper.marginInsets.trailing, y: summaryTop))
            },
            with: .color(PT.accent.opacity(0.25)),
            lineWidth: 1.2
        )
    }

    private func drawReadingStudyTemplate(in ctx: inout GraphicsContext, size: CGSize) {
        let headerHeight = max(96, spacing * 2.4)
        let vocabColumnWidth = max(220, size.width * 0.22)
        let bodyTop = paper.marginInsets.top + headerHeight

        ctx.stroke(
            Path(CGRect(
                x: paper.marginInsets.leading,
                y: paper.marginInsets.top,
                width: size.width - paper.marginInsets.leading - paper.marginInsets.trailing,
                height: headerHeight - 20
            )),
            with: .color(PT.accent.opacity(0.18)),
            lineWidth: 1
        )
        drawHorizontalRules(in: &ctx, size: size, startY: bodyTop, spacing: spacing)
        ctx.stroke(
            Path { path in
                let splitX = size.width - paper.marginInsets.trailing - vocabColumnWidth
                path.move(to: CGPoint(x: splitX, y: bodyTop))
                path.addLine(to: CGPoint(x: splitX, y: size.height - paper.marginInsets.bottom))
            },
            with: .color(PT.accent.opacity(0.22)),
            lineWidth: 1
        )
        drawMarginGuide(in: &ctx, size: size)
    }

    private func drawWrongAnswerTemplate(in ctx: inout GraphicsContext, size: CGSize) {
        let headerHeight = max(110, spacing * 2.8)
        let sectionGap: CGFloat = 18
        let bodyTop = paper.marginInsets.top + headerHeight
        let availableHeight = size.height - bodyTop - paper.marginInsets.bottom
        let sectionHeight = max(120, (availableHeight - sectionGap * 2) / 3)

        for index in 0..<3 {
            let y = bodyTop + CGFloat(index) * (sectionHeight + sectionGap)
            let rect = CGRect(
                x: paper.marginInsets.leading,
                y: y,
                width: size.width - paper.marginInsets.leading - paper.marginInsets.trailing,
                height: sectionHeight
            )
            ctx.stroke(
                RoundedRectangle(cornerRadius: 10, style: .continuous).path(in: rect),
                with: .color(PT.accent.opacity(index == 0 ? 0.22 : 0.16)),
                style: StrokeStyle(lineWidth: 1, dash: index == 1 ? [6, 4] : [])
            )
        }

        ctx.stroke(
            Path(CGRect(
                x: paper.marginInsets.leading,
                y: paper.marginInsets.top,
                width: size.width - paper.marginInsets.leading - paper.marginInsets.trailing,
                height: headerHeight - 24
            )),
            with: .color(PT.marginColor.opacity(0.85)),
            lineWidth: 1
        )
    }

    private func drawHorizontalRules(
        in ctx: inout GraphicsContext,
        size: CGSize,
        startY: CGFloat,
        spacing: CGFloat,
        endY: CGFloat? = nil
    ) {
        var y = startY
        let lastY = endY ?? (size.height - paper.marginInsets.bottom)
        while y < lastY {
            ctx.stroke(
                Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                },
                with: .color(PT.ruleColor),
                lineWidth: 0.5
            )
            y += spacing
        }
    }

    private func drawMarginGuide(in ctx: inout GraphicsContext, size: CGSize) {
        ctx.stroke(
            Path { path in
                path.move(to: CGPoint(x: marginLeading, y: 18))
                path.addLine(to: CGPoint(x: marginLeading, y: size.height - 18))
            },
            with: .color(PT.marginColor),
            lineWidth: 1.2
        )
    }
}

private struct PaperLayerView: View {
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let paper: NotePaperConfiguration

    var body: some View {
        PaperBackground(pageWidth: pageWidth, pageHeight: pageHeight, paper: paper)
    }
}

private struct BackgroundReferenceLayerView: View {
    @ObservedObject var vm: NoteWorkspaceViewModel
    let pageWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !vm.sourceHint.isEmpty {
                Text(vm.sourceHint)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PT.muted.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.55))
                    )
                    .padding(.leading, PT.leading)
                    .padding(.top, 18)
            }
            Spacer()
        }
        .frame(maxWidth: pageWidth, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

private struct CanvasObjectLayerView: View {
    @ObservedObject var vm: NoteWorkspaceViewModel
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let appViewModel: AppViewModel
    let isTextMode: Bool
    let isSelectMode: Bool
    let isTextObjectInteractionMode: Bool
    @Binding var editorSelection: EditorSelection
    var onHeightChange: (CGFloat) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            UserContentLayer(
                vm: vm,
                isTextObjectInteractionMode: isTextObjectInteractionMode,
                editorSelection: $editorSelection,
                onHeightChange: onHeightChange
            )
            .frame(width: pageWidth - PT.leading - PT.trailing)
            .padding(.leading, PT.leading)
            .padding(.trailing, PT.trailing)
            .padding(.top, PT.topInset)

            CanvasStaticObjectLayer(
                vm: vm,
                isSelectMode: isSelectMode,
                editorSelection: $editorSelection,
                pageWidth: pageWidth,
                pageHeight: pageHeight
            )

            CanvasTextObjectsLayer(
                vm: vm,
                appViewModel: appViewModel,
                isTextToolActive: isTextMode,
                canManipulateTextObjects: isTextObjectInteractionMode || isSelectMode,
                editorSelection: $editorSelection,
                pageWidth: pageWidth,
                pageHeight: pageHeight
            )
        }
    }
}

private struct CanvasStaticObjectLayer: View {
    @ObservedObject var vm: NoteWorkspaceViewModel
    let isSelectMode: Bool
    @Binding var editorSelection: EditorSelection
    let pageWidth: CGFloat
    let pageHeight: CGFloat

    private var visibleElements: [CanvasElement] {
        vm.canvasObjectElements
            .filter { element in
                guard element.isVisibleObject else { return false }
                switch element.kind {
                case .imageObject, .knowledgeCardObject, .linkPreviewObject:
                    return true
                case .quoteObject:
                    return element.isFloatingObject
                case .textObject, .inkStroke, .inkSelectionObject:
                    return false
                }
            }
            .sorted { lhs, rhs in
                if lhs.resolvedZIndex != rhs.resolvedZIndex {
                    return lhs.resolvedZIndex < rhs.resolvedZIndex
                }
                return lhs.metadata.createdAt < rhs.metadata.createdAt
            }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(visibleElements) { element in
                CanvasStaticObjectCard(
                    element: element,
                    isSelected: vm.selectionController.contains(element.id)
                )
                    .frame(
                        width: max(element.effectiveFrame.width, 80),
                        height: max(element.effectiveFrame.height, 60)
                    )
                    .position(
                        x: element.effectiveFrame.midX,
                        y: element.effectiveFrame.midY
                    )
                    .rotationEffect(.degrees(Double(element.rotation)))
                    .zIndex(Double(element.resolvedZIndex))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard isSelectMode else { return }
                        editorSelection = .none
                        vm.selectCanvasObject(id: element.id)
                    }
            }
        }
        .frame(width: pageWidth, height: pageHeight)
        .allowsHitTesting(isSelectMode)
    }
}

private struct CanvasStaticObjectCard: View {
    let element: CanvasElement
    let isSelected: Bool

    var body: some View {
        switch element.kind {
        case .imageObject:
            imageCard
        case .knowledgeCardObject:
            knowledgeCard
        case .linkPreviewObject:
            linkPreviewCard
        case .quoteObject:
            floatingQuoteCard
        case .textObject, .inkStroke, .inkSelectionObject:
            EmptyView()
        }
    }

    private var imageCard: some View {
        let caption = element.imageObject?.caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 8) {
            Group {
                if let data = element.imageObject?.imageData,
                   let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.72))
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(PT.accent.opacity(0.8))
                            Text(element.imageObject?.remoteURL?.nonEmpty ?? "图片对象")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(PT.muted)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PT.ink.opacity(0.82))
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(cardBackground)
    }

    private var knowledgeCard: some View {
        let payload = element.knowledgeCardObject
        let linkedCount = payload?.linkedKnowledgePointIDs.count ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.stack.badge.person.crop")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PT.accent)
                Text("知识卡")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(PT.accent)
                Spacer(minLength: 0)
                if linkedCount > 0 {
                    Text("\(linkedCount) 关联")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PT.muted)
                }
            }

            Text(payload?.title.nonEmpty ?? "未命名知识卡")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(PT.ink)
                .lineLimit(2)

            Text(payload?.summary.nonEmpty ?? "补充概念、例句或解题逻辑。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PT.ink.opacity(0.76))
                .lineSpacing(4)
                .lineLimit(5)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    private var linkPreviewCard: some View {
        let payload = element.linkPreviewObject
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(PT.accent)
                Text(payload?.title.nonEmpty ?? "链接卡片")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PT.ink)
                    .lineLimit(1)
            }

            Text(payload?.url.nonEmpty ?? "未提供 URL")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(PT.accent.opacity(0.84))
                .lineLimit(1)

            if let summary = payload?.summary?.nonEmpty {
                Text(summary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PT.muted)
                    .lineSpacing(3)
                    .lineLimit(4)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    private var floatingQuoteCard: some View {
        let payload = element.quoteObject
        let font = BlockStyleMapping.font(
            for: payload?.textStyle ?? .classicSerif,
            kind: .quote,
            size: payload?.fontSizePreset ?? .medium
        )
        let color = BlockStyleMapping.color(for: payload?.textColor ?? .inkBlack)
        return HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(PT.quoteBar)
                .frame(width: 3)
            Text(payload?.text ?? "")
                .font(font)
                .italic()
                .foregroundStyle(color.opacity(0.88))
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.84))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? PT.accent.opacity(0.85) : PT.divider, lineWidth: isSelected ? 1.5 : 0.8)
            )
            .shadow(color: .black.opacity(0.04), radius: 12, y: 6)
    }
}

private struct CanvasOverlayLayerView: View {
    @ObservedObject var vm: NoteWorkspaceViewModel
    let appViewModel: AppViewModel
    let isSelectMode: Bool
    @Binding var editorSelection: EditorSelection
    let pageWidth: CGFloat
    let pageHeight: CGFloat

    @State private var draftFrame: CGRect?
    @State private var dragStartFrame: CGRect?
    @State private var resizeStartFrame: CGRect?

    private var selectedElement: CanvasElement? {
        vm.primarySelectedCanvasElement
    }

    private var isInteractiveObjectSelected: Bool {
        guard let selectedElement else { return false }
        return isSelectMode && selectedElement.kind != .textObject
    }

    private var liveSelectionFrame: CGRect? {
        draftFrame ?? selectedElement?.effectiveFrame
    }

    private var showsVerticalGuide: Bool {
        guard let frame = liveSelectionFrame else { return false }
        return abs(frame.midX - (pageWidth / 2)) < 6
    }

    private var showsHorizontalGuide: Bool {
        guard let frame = liveSelectionFrame else { return false }
        return abs(frame.midY - (pageHeight / 2)) < 6
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: pageWidth, height: pageHeight)
                .contentShape(Rectangle())
                .allowsHitTesting(false)

            zoomHUD

            if showsVerticalGuide {
                Rectangle()
                    .fill(PT.accent.opacity(0.18))
                    .frame(width: 1, height: pageHeight)
                    .position(x: pageWidth / 2, y: pageHeight / 2)
                    .allowsHitTesting(false)
            }

            if showsHorizontalGuide {
                Rectangle()
                    .fill(PT.accent.opacity(0.18))
                    .frame(width: pageWidth, height: 1)
                    .position(x: pageWidth / 2, y: pageHeight / 2)
                    .allowsHitTesting(false)
            }

            if let selectedElement, let frame = liveSelectionFrame, isInteractiveObjectSelected {
                selectionOverlay(for: selectedElement, frame: frame)
            }
        }
        .frame(width: pageWidth, height: pageHeight)
        .accessibilityLabel(accessibilityLabel)
    }

    private var zoomHUD: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
            Text(vm.viewportController.zoomHUDLabel)
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(PT.ink.opacity(0.82))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.75))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(PT.divider, lineWidth: 0.8)
                )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 18)
        .padding(.trailing, 18)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func selectionOverlay(for element: CanvasElement, frame: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: frame.width, height: frame.height)
                .contentShape(Rectangle())
                .position(x: frame.midX, y: frame.midY)
                .highPriorityGesture(moveGesture(for: element, frame: frame))

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PT.accent, style: StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .allowsHitTesting(false)

            ForEach(CanvasTransformHandle.allCases.filter { $0 != .move }) { handle in
                if let corner = handle.resizeCorner {
                    TextObjectResizeHandle()
                        .position(handlePosition(for: corner, frame: frame))
                        .highPriorityGesture(resizeGesture(for: element, handle: handle, frame: frame))
                }
            }

            objectMenu(for: element, frame: frame)
        }
    }

    private func objectMenu(for element: CanvasElement, frame: CGRect) -> some View {
        HStack(spacing: 8) {
            Text((vm.selectionController.selectionKind ?? .mixed).label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(PT.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.9))
                )

            Button {
                vm.selectionController.showsInspector.toggle()
            } label: {
                Image(systemName: vm.selectionController.showsInspector ? "sidebar.right" : "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PT.ink)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.92)))
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                vm.deleteCanvasObject(id: element.id)
                vm.scheduleAutosave(using: appViewModel, delayNanoseconds: 150_000_000)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.88))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.92)))
            }
            .buttonStyle(.plain)
        }
        .position(
            x: min(max(frame.midX, 120), pageWidth - 120),
            y: max(frame.minY - 26, 24)
        )
    }

    private func moveGesture(for element: CanvasElement, frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStartFrame == nil {
                    dragStartFrame = frame
                    vm.beginCanvasInteraction(handle: .move, mode: .moving)
                }
                let base = dragStartFrame ?? frame
                let next = clamp(frame: base.offsetBy(dx: value.translation.width, dy: value.translation.height), minimumSize: minimumSize(for: element))
                draftFrame = next
                vm.updateCanvasSelectionPreview(next)
            }
            .onEnded { value in
                let base = dragStartFrame ?? frame
                let next = clamp(frame: base.offsetBy(dx: value.translation.width, dy: value.translation.height), minimumSize: minimumSize(for: element))
                draftFrame = nil
                dragStartFrame = nil
                vm.moveCanvasObject(id: element.id, to: next.origin)
                vm.endCanvasInteraction()
                vm.scheduleAutosave(using: appViewModel, delayNanoseconds: 150_000_000)
            }
    }

    private func resizeGesture(for element: CanvasElement, handle: CanvasTransformHandle, frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard let corner = handle.resizeCorner else { return }
                if resizeStartFrame == nil {
                    resizeStartFrame = frame
                    vm.beginCanvasInteraction(handle: handle, mode: .resizing)
                }
                let base = resizeStartFrame ?? frame
                let minimumSize = minimumSize(for: element)
                let next = clamp(
                    frame: corner.apply(
                        delta: value.translation,
                        origin: base.origin,
                        size: base.size,
                        minW: minimumSize.width,
                        minH: minimumSize.height
                    ),
                    minimumSize: minimumSize
                )
                draftFrame = next
                vm.updateCanvasSelectionPreview(next)
            }
            .onEnded { value in
                guard let corner = handle.resizeCorner else { return }
                let base = resizeStartFrame ?? frame
                let minimumSize = minimumSize(for: element)
                let next = clamp(
                    frame: corner.apply(
                        delta: value.translation,
                        origin: base.origin,
                        size: base.size,
                        minW: minimumSize.width,
                        minH: minimumSize.height
                    ),
                    minimumSize: minimumSize
                )
                draftFrame = nil
                resizeStartFrame = nil
                vm.resizeCanvasObject(id: element.id, to: next)
                vm.endCanvasInteraction()
                vm.scheduleAutosave(using: appViewModel, delayNanoseconds: 150_000_000)
            }
    }

    private func handlePosition(for corner: ResizeCorner, frame: CGRect) -> CGPoint {
        CGPoint(
            x: frame.midX + corner.xOffsetFromCenter(frame.width),
            y: frame.midY + corner.yOffsetFromCenter(frame.height)
        )
    }

    private func minimumSize(for element: CanvasElement) -> CGSize {
        switch element.kind {
        case .imageObject:
            return CGSize(width: 140, height: 110)
        case .knowledgeCardObject:
            return CGSize(width: 220, height: 140)
        case .quoteObject:
            return CGSize(width: 220, height: 80)
        case .linkPreviewObject:
            return CGSize(width: 220, height: 100)
        case .textObject:
            return CGSize(width: 160, height: 60)
        case .inkStroke, .inkSelectionObject:
            return CGSize(width: 80, height: 80)
        }
    }

    private func clamp(frame: CGRect, minimumSize: CGSize) -> CGRect {
        let width = min(max(frame.width, minimumSize.width), pageWidth)
        let height = min(max(frame.height, minimumSize.height), pageHeight)
        let x = max(0, min(frame.origin.x, pageWidth - width))
        let y = max(0, min(frame.origin.y, pageHeight - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private var accessibilityLabel: String {
        switch editorSelection {
        case .none:
            return "画布覆盖交互层"
        case .textBlock:
            return "文本块交互层"
        case .textObject:
            return "文本对象交互层"
        case .inkSelection:
            return "墨迹选区交互层"
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - User Content Layer
// ═══════════════════════════════════════════════════════════════
//
// This renders ONLY user-authored content on the paper:
//   • Title (editable)
//   • Tiny metadata hint (one line, source reference)
//   • User-CREATED text blocks (from "添加文本" or TEXT tool tap)
//   • User-INSERTED quotes (from ReferencePanel "插入引用" action)
//   • "Add content" buttons
//
// It does NOT render:
//   • Source document text
//   • Auto-generated source excerpts
//   • Imported material previews
//
// To distinguish user-inserted quotes from auto-generated ones:
//   Blocks with kind == .quote that were created at note-creation time
//   (same text as sourceAnchor.quotedText) are HIDDEN on canvas.
//   They still exist in the data model but are only visible in ReferencePanel.

private struct UserContentLayer: View {
    @ObservedObject var vm: NoteWorkspaceViewModel
    let isTextObjectInteractionMode: Bool
    @Binding var editorSelection: EditorSelection
    var onHeightChange: ((CGFloat) -> Void)?

    /// Focus sentinel — nil means title, non-nil means a block's TextEditor.
    /// Prevents keyboard input from leaking between title and body blocks.
    @FocusState private var focusedBlockID: UUID?

    /// Only show user-inserted quotes on the canvas.
    /// Auto-generated source excerpts are hidden:
    ///  - Any .quote whose text matches sourceAnchor.quotedText (fuzzy: ignoring whitespace)
    ///  - Any .quote whose linkedSourceAnchorID matches note's anchor AND was created at note-creation time
    /// These still exist in the data model and ReferencePanel can access them.
    private var userQuoteBlocks: [NoteBlock] {
        let sourceQuoteNorm = vm.sourceAnchor.quotedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let noteCreatedAt = vm.note.createdAt

        return vm.blocks.filter { block in
            guard block.kind == .quote else { return false }
            guard let text = block.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

            // Hide quotes created at the same time as the note (auto-injected at creation)
            if abs(block.createdAt.timeIntervalSince(noteCreatedAt)) < 2 {
                return false
            }

            let blockTextNorm = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

            // Hide if this matches the source anchor's quoted text
            if !sourceQuoteNorm.isEmpty && blockTextNorm == sourceQuoteNorm {
                return false
            }

            // Hide if it's a substantial prefix match
            if !sourceQuoteNorm.isEmpty && sourceQuoteNorm.count > 10 {
                let prefixLen = sourceQuoteNorm.count * 7 / 10
                if blockTextNorm.hasPrefix(String(sourceQuoteNorm.prefix(prefixLen))) {
                    return false
                }
            }

            // Hide if block text appears as a substring of the source full text
            if let doc = vm.sourceDocument {
                let extractedNorm = doc.extractedText
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                if extractedNorm.contains(blockTextNorm) && blockTextNorm.count > 20 {
                    return false
                }
            }

            return true
        }
    }

    private var userTextBlocks: [NoteBlock] {
        vm.blocks.filter { $0.kind == .text }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Editable title
            titleField.padding(.bottom, 16)

            Rectangle().fill(PT.divider).frame(height: 0.5).padding(.bottom, 20)

            // User-inserted quotes only (auto-generated source quotes hidden)
            ForEach(userQuoteBlocks) { block in
                quoteView(block: block)
                    .padding(.bottom, 16)
            }

            // User text blocks
            ForEach(userTextBlocks) { block in
                textParagraph(block: block)
                    .padding(.bottom, 12)
            }

            // Add content bar
            actionBar.padding(.top, 12).padding(.bottom, 20)

            // Knowledge tags
            if !vm.linkedKnowledgePoints.isEmpty {
                tagStrip.padding(.bottom, 16)
            }

            // Blank area — tapping here clears selection.
            // (Text creation is now handled by CanvasTextObjectsLayer tap-to-create.)
            Color.clear
                .frame(minHeight: 600)
                .contentShape(Rectangle())
                .onTapGesture {
                    DispatchQueue.main.async {
                        focusedBlockID = nil
                        vm.clearCanvasSelection()
                        if case .textBlock = editorSelection {
                            editorSelection = .none
                            vm.editingTextBlockID = nil
                        }
                    }
                }
                .allowsHitTesting(!isTextObjectInteractionMode)
        }
        .background(heightReader)
        .onPreferenceChange(HeightKey.self) { h in
            DispatchQueue.main.async { onHeightChange?(h) }
        }
        .onChange(of: focusedBlockID) { newID in
            DispatchQueue.main.async {
                if let newID, newID != Self.titleFocusID {
                    // Text block gained focus → update selection
                    vm.editingTextBlockID = newID
                    editorSelection = .textBlock(newID)
                } else {
                    // Focus lost or moved to title → clear text selection
                    vm.editingTextBlockID = nil
                    if case .textBlock = editorSelection {
                        editorSelection = .none
                    }
                }
            }
        }
        // Auto-focus new text blocks created by vm.addTextBlock()
        .onChange(of: vm.editingTextBlockID) { newID in
            if let newID, focusedBlockID != newID {
                DispatchQueue.main.async {
                    focusedBlockID = newID
                }
            }
        }
    }

    // MARK: Sub-views

    private var sourceHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "link").font(.system(size: 8, weight: .bold))
            Text(vm.sourceHint).font(.system(size: 10, weight: .semibold)).lineLimit(1)
            Spacer()
        }
        .foregroundStyle(PT.muted.opacity(0.55))
    }

    /// Sentinel UUID used exclusively for the title field focus.
    private static let titleFocusID = UUID(uuidString: "00000000-0000-0000-FFFF-000000000001")!

    private var titleField: some View {
        TextField("笔记标题", text: Binding(
            get: { vm.title },
            set: { vm.updateTitle($0) }
        ))
        .font(.system(size: 32, weight: .medium, design: .serif))
        .foregroundStyle(PT.ink)
        .textFieldStyle(.plain)
        .focused($focusedBlockID, equals: Self.titleFocusID)
    }

    private func quoteView(block: NoteBlock) -> some View {
        let font = BlockStyleMapping.font(for: block.resolvedTextStyle, kind: .quote, size: block.resolvedFontSize)
        let color = BlockStyleMapping.color(for: block.resolvedTextColor)
        let hlColor = BlockStyleMapping.highlightBackground(for: block.resolvedHighlight)

        return HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 1.5).fill(PT.quoteBar).frame(width: 3).padding(.vertical, 2)
            Text(block.text ?? "")
                .font(font)
                .italic()
                .foregroundStyle(color.opacity(0.85))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, hlColor != nil ? 4 : 0)
                .padding(.vertical, hlColor != nil ? 2 : 0)
                .background(
                    hlColor.map {
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill($0)
                    }
                )
        }
    }

    private func textParagraph(block: NoteBlock) -> some View {
        let font = BlockStyleMapping.font(for: block.resolvedTextStyle, kind: .text, size: block.resolvedFontSize)
        let color = BlockStyleMapping.color(for: block.resolvedTextColor)
        let hlColor = BlockStyleMapping.highlightBackground(for: block.resolvedHighlight)

        // Build a style fingerprint so that `.id()` changes when ANY style changes,
        // forcing SwiftUI to destroy & recreate the TextEditor (it caches text attributes).
        let styleFP = "\(block.id)-\(block.textStyle?.rawValue ?? "d")-\(block.textColor?.rawValue ?? "d")-\(block.fontSizePreset?.rawValue ?? "d")-\(block.highlightStyle?.rawValue ?? "d")"

        return TextEditor(text: Binding(
            get: { vm.blocks.first(where: { $0.id == block.id })?.text ?? "" },
            set: { vm.updateTextBlock(id: block.id, text: $0) }
        ))
        .font(font)
        .foregroundColor(color.opacity(0.9))
        .lineSpacing(6)
        .scrollContentBackground(.hidden)
        .background(
            hlColor.map {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill($0)
            }
        )
        .frame(minHeight: 44)
        .fixedSize(horizontal: false, vertical: true)
        .focused($focusedBlockID, equals: block.id)
        .id(styleFP)
    }

    private var actionBar: some View {
        EmptyView()
        // Legacy "添加文本" button removed.
        // New text is created by tapping the canvas in TEXT mode.
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(PT.accent.opacity(0.65))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PT.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var tagStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("关联概念")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(PT.muted.opacity(0.45))
            FlowLayout(spacing: 6) {
                ForEach(vm.linkedKnowledgePoints) { pt in
                    Text(pt.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PT.tagText)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule(style: .continuous).fill(PT.tagFill))
                }
            }
        }
    }

    private var heightReader: some View {
        GeometryReader { g in Color.clear.preference(key: HeightKey.self, value: g.size.height) }
    }
}

// MARK: - FlowLayout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = compute(proposal: proposal, subviews: subviews)
        return CGSize(width: proposal.width ?? 0, height: rows.reduce(0) { $0 + $1.h + ($0 > 0 ? spacing : 0) })
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in compute(proposal: proposal, subviews: subviews) {
            var x = bounds.minX
            for item in row.items { item.sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.sz)); x += item.sz.width + spacing }
            y += row.h + spacing
        }
    }
    private struct Item { let sv: LayoutSubviews.Element; let sz: CGSize }
    private struct Row { var items: [Item] = []; var h: CGFloat = 0 }
    private func compute(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxW = proposal.width ?? .infinity
        var rows: [Row] = [Row()]; var w: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if w + sz.width > maxW, !rows[rows.count-1].items.isEmpty { rows.append(Row()); w = 0 }
            rows[rows.count-1].items.append(Item(sv: sv, sz: sz))
            rows[rows.count-1].h = max(rows[rows.count-1].h, sz.height)
            w += sz.width + spacing
        }
        return rows
    }
}

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// ═══════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════
// MARK: - InkActionBridge
// ═══════════════════════════════════════════════════════════════

/// Bridges SwiftUI → PKCanvasView for ink selection actions (delete, copy, recolor).
final class InkActionBridge {
    weak var canvas: PKCanvasView?

    /// Cached bounds of the current lasso selection (set from coordinator).
    var selectionBounds: CGRect = .zero

    /// Returns the current drawing data for persistence.
    func currentDrawingData() -> Data? {
        canvas?.drawing.dataRepresentation()
    }

    /// Returns the current drawing bounds.
    func currentDrawingBounds() -> CGRect {
        canvas?.drawing.bounds ?? .zero
    }

    func deleteSelection() {
        guard let canvas = canvas else { return }
        canvas.becomeFirstResponder()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIApplication.shared.sendAction(
                #selector(UIResponderStandardEditActions.delete(_:)),
                to: nil, from: canvas, for: nil
            )
        }
    }

    func copySelection() {
        guard let canvas = canvas else { return }
        canvas.becomeFirstResponder()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIApplication.shared.sendAction(
                #selector(UIResponderStandardEditActions.copy(_:)),
                to: nil, from: canvas, for: nil
            )
        }
    }

    func duplicateSelection() {
        guard let canvas = canvas else { return }
        canvas.becomeFirstResponder()
        // Copy + Paste at offset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.copy(_:)), to: nil, from: canvas, for: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.paste(_:)), to: nil, from: canvas, for: nil)
            }
        }
    }

    /// Recolors all strokes that intersect the current selection bounds.
    /// Because PencilKit doesn't expose which strokes are "selected" by the lasso,
    /// we find strokes whose bounds overlap the selection bounds and rebuild them.
    func recolorSelection(to newColor: UIColor) {
        guard let canvas = canvas, !selectionBounds.isEmpty else { return }
        let drawing = canvas.drawing
        let expandedBounds = selectionBounds.insetBy(dx: -5, dy: -5)
        var newStrokes: [PKStroke] = []
        var changed = false

        for stroke in drawing.strokes {
            if stroke.renderBounds.intersects(expandedBounds) {
                let newInk = PKInk(stroke.ink.inkType, color: newColor)
                let rebuilt = PKStroke(ink: newInk, path: stroke.path, transform: stroke.transform, mask: stroke.mask)
                newStrokes.append(rebuilt)
                changed = true
            } else {
                newStrokes.append(stroke)
            }
        }

        if changed {
            var newDrawing = PKDrawing()
            newDrawing.strokes = newStrokes
            canvas.drawing = newDrawing
        }
    }

    /// Changes the width of strokes that intersect the selection bounds.
    /// Note: PKStroke doesn't directly support width change, so we rebuild with new ink width
    /// by scaling the path control points.
    func rewidthSelection(to newWidth: CGFloat) {
        guard let canvas = canvas, !selectionBounds.isEmpty else { return }
        let drawing = canvas.drawing
        let expandedBounds = selectionBounds.insetBy(dx: -5, dy: -5)
        var newStrokes: [PKStroke] = []
        var changed = false

        for stroke in drawing.strokes {
            if stroke.renderBounds.intersects(expandedBounds) {
                // Rebuild stroke with adjusted path (scale control point sizes)
                let originalPath = stroke.path
                var newPoints: [PKStrokePoint] = []
                for i in 0..<originalPath.count {
                    let pt = originalPath[i]
                    let newPt = PKStrokePoint(
                        location: pt.location,
                        timeOffset: pt.timeOffset,
                        size: CGSize(width: newWidth, height: newWidth),
                        opacity: pt.opacity,
                        force: pt.force,
                        azimuth: pt.azimuth,
                        altitude: pt.altitude
                    )
                    newPoints.append(newPt)
                }
                let newPath = PKStrokePath(controlPoints: newPoints, creationDate: originalPath.creationDate)
                let rebuilt = PKStroke(ink: stroke.ink, path: newPath, transform: stroke.transform, mask: stroke.mask)
                newStrokes.append(rebuilt)
                changed = true
            } else {
                newStrokes.append(stroke)
            }
        }

        if changed {
            var newDrawing = PKDrawing()
            newDrawing.strokes = newStrokes
            canvas.drawing = newDrawing
        }
    }
}

// MARK: - pkTool mapping
// ═══════════════════════════════════════════════════════════════

#if canImport(PencilKit)
private extension NoteInkToolState {
    var pkTool: PKTool {
        switch kind {
        case .pen:         return PKInkingTool(.pen, color: UIColor(colorChoice.color), width: width)
        case .pencil:      return PKInkingTool(.pencil, color: UIColor(colorChoice.color), width: width)
        case .ballpoint:   return PKInkingTool(.pen, color: UIColor(colorChoice.color), width: width)
        case .highlighter: return PKInkingTool(.marker, color: UIColor(colorChoice.color.opacity(0.45)), width: width)
        case .eraser:      return PKEraserTool(eraserPreset == .precise ? .vector : .bitmap, width: eraserWidth)
        case .lasso:       return PKLassoTool()
        }
    }
}
#endif

private extension String {
    var nonEmpty: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
