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
            let pageWidth = min(max(geo.size.width - 40, 820), 1280)
            let baseH = max(PT.lineSpacing * CGFloat(max(pageCount, 1)) * 30,
                            geo.size.height - 20)
            let pageH = min(max(baseH, contentHeight + 300), Self.maxPageHeight)

            NotebookScrollHost(
                initialInkData: initialInkData,
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
                }
            ) {
                ZStack(alignment: .topLeading) {
                    PaperBackground(pageWidth: pageWidth, pageHeight: pageH)

                    UserContentLayer(
                        vm: vm,
                        isTextObjectInteractionMode: isTextObjectInteractionMode,
                        editorSelection: $editorSelection,
                        onHeightChange: { h in
                            DispatchQueue.main.async { contentHeight = h }
                        }
                    )
                    .frame(width: pageWidth - PT.leading - PT.trailing)
                    .padding(.leading, PT.leading)
                    .padding(.trailing, PT.trailing)
                    .padding(.top, PT.topInset)

                    // Free-form text objects layer — sits above legacy content, below ink
                    CanvasTextObjectsLayer(
                        vm: vm,
                        isTextToolActive: isTextMode,
                        canManipulateTextObjects: isTextObjectInteractionMode,
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

        // In text mode: require 2-finger pan for scrolling, so single finger
        // can drag / resize text objects without the scroll view stealing the gesture.
        vc.scrollView.panGestureRecognizer.minimumNumberOfTouches = isTextObjectInteractionMode ? 2 : 1
        // canCancelContentTouches stays true (default) so 2-finger scroll works.
        // Single-finger drags are safe because minimumNumberOfTouches = 2 prevents
        // the scroll view from recognizing single-finger pan.
        vc.scrollView.isTextMode = isTextObjectInteractionMode
        vc.isTextMode = isTextObjectInteractionMode

        // NOTE: No drawing data sync here.
        // PKCanvasView is the sole source of truth for ink while the page is open.
        // Ink is synced to the data model only on save via syncInkFromBridge().
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
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
        scrollView.delaysContentTouches = false

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

    var body: some View {
        Canvas { ctx, size in
            var y = PT.topInset
            while y < size.height - 28 {
                ctx.stroke(
                    Path { p in p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: size.width, y: y)) },
                    with: .color(PT.ruleColor), lineWidth: 0.5
                )
                y += PT.lineSpacing
            }
            ctx.stroke(
                Path { p in p.move(to: .init(x: PT.marginX, y: 18)); p.addLine(to: .init(x: PT.marginX, y: size.height - 18)) },
                with: .color(PT.marginColor), lineWidth: 1.2
            )
        }
        .frame(width: pageWidth, height: pageHeight)
        .allowsHitTesting(false)
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
