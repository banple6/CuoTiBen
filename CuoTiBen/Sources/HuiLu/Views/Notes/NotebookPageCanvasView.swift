import SwiftUI

#if canImport(PencilKit)
import PencilKit
#endif

// ╔══════════════════════════════════════════════════════════════╗
// ║  NotebookPageCanvasView — Blank Notebook Page                ║
// ║                                                              ║
// ║  Architecture (UIKit-based):                                 ║
// ║    UIScrollView (finger-only pan)                            ║
// ║      contentWrapper UIView                                   ║
// ║        paper SwiftUI host                                    ║
// ║        PencilOnlyCanvasView (PKCanvasView subclass)          ║
// ║                                                              ║
// ║  Pencil draws. Finger scrolls/taps. No gesture conflict.    ║
// ╚══════════════════════════════════════════════════════════════╝

// MARK: - Design Tokens

private enum PageTokens {
    static let paperFill    = Color(red: 0.995, green: 0.992, blue: 0.978)
    static let ruleColor    = Color(red: 0.82, green: 0.82, blue: 0.78).opacity(0.35)
    static let marginColor  = Color(red: 0.85, green: 0.25, blue: 0.25).opacity(0.18)
    static let ink          = Color(red: 0.08, green: 0.08, blue: 0.06)
    static let inkSecondary = Color(red: 0.08, green: 0.08, blue: 0.06).opacity(0.55)
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
// MARK: - NotebookPageCanvasView (main SwiftUI entry)
// ═══════════════════════════════════════════════════════════════

struct NotebookPageCanvasView: View {
    @ObservedObject var vm: NoteWorkspaceViewModel
    let appViewModel: AppViewModel
    @Binding var inkToolState: NoteInkToolState
    let isTextMode: Bool
    let doubleTapBehavior: NotePencilDoubleTapBehavior
    let onOpenSource: (SourceAnchor) -> Void

    @State private var fullPageDrawing: Data = Data()
    @State private var pageCount: Int = 1
    @State private var contentHeight: CGFloat = 800

    var body: some View {
        GeometryReader { geo in
            let pageWidth = min(max(geo.size.width - 40, 820), 1280)
            let pageH = max(PageTokens.lineSpacing * CGFloat(max(pageCount, 1)) * 30,
                            contentHeight + 600,
                            geo.size.height - 20)

            #if canImport(PencilKit)
            CanvasPageScrollContainer(
                drawingData: $fullPageDrawing,
                inkToolState: $inkToolState,
                pageWidth: pageWidth,
                pageHeight: pageH,
                isTextMode: isTextMode,
                doubleTapBehavior: doubleTapBehavior,
                onDrawingChanged: { data, bounds, size in
                    persistInkToBlock(data: data, bounds: bounds, size: size)
                },
                paperContent: {
                    ZStack(alignment: .topLeading) {
                        PaperBackgroundLayer(pageWidth: pageWidth, pageHeight: pageH)

                        EditableTextLayer(
                            vm: vm,
                            isTextMode: isTextMode,
                            onContentHeightChange: { h in contentHeight = max(h, contentHeight) }
                        )
                        .frame(width: pageWidth - PageTokens.leading - PageTokens.trailing)
                        .padding(.leading, PageTokens.leading)
                        .padding(.trailing, PageTokens.trailing)
                        .padding(.top, PageTokens.topInset)
                        .allowsHitTesting(true)
                    }
                    .frame(width: pageWidth, height: pageH)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(PageTokens.paperFill)
                            .shadow(color: Color.black.opacity(0.06), radius: 24, y: 12)
                    )
                }
            )
            .padding(.horizontal, max((geo.size.width - pageWidth) / 2, 12))
            .padding(.vertical, 12)
            #else
            Text("PencilKit not available")
            #endif
        }
        .onAppear(perform: loadInkFromBlock)
        .onChange(of: vm.note.id) { _ in loadInkFromBlock() }
    }

    // MARK: - Ink <-> Block Bridge

    private func loadInkFromBlock() {
        if let inkBlock = vm.blocks.first(where: { $0.kind == .ink }) {
            fullPageDrawing = inkBlock.inkData ?? Data()
            pageCount = inkBlock.inkGeometry?.pageCount ?? 1
        } else {
            fullPageDrawing = Data()
            pageCount = 1
        }
    }

    private func persistInkToBlock(data: Data, bounds: CGRect, size: CGSize) {
        let existingInk = vm.blocks.first(where: { $0.kind == .ink })
        if var block = existingInk {
            block.inkData = data
            block.inkGeometry = InkGeometry(normalizedBounds: bounds, pageCount: pageCount)
            block.updatedAt = Date()
            vm.updateInkBlock(block)
        } else {
            var newBlock = NoteBlock(kind: .ink, inkData: data, linkedSourceAnchorID: vm.sourceAnchor.id)
            newBlock.inkGeometry = InkGeometry(normalizedBounds: bounds, pageCount: pageCount)
            vm.blocks.append(newBlock)
            vm.isDirty = true
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - CanvasPageScrollContainer (UIKit-based scroll + ink)
// ═══════════════════════════════════════════════════════════════
//
// Architecture:
//   UIScrollView  [panGesture.allowedTouchTypes = finger only]
//     ┣─ paperHostView  (UIHostingController → SwiftUI paper + text)
//     ┗─ canvasView     (PKCanvasView, drawingPolicy = .pencilOnly)
//
//  • Finger drag  → UIScrollView scrolls (pan only responds to finger)
//  • Pencil       → PKCanvasView draws (only pencil activates drawing)
//  • Finger tap   → passes through canvas hitTest → reaches paper/text

#if canImport(PencilKit)

struct CanvasPageScrollContainer<PaperContent: View>: UIViewRepresentable {
    @Binding var drawingData: Data
    @Binding var inkToolState: NoteInkToolState
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let isTextMode: Bool
    let doubleTapBehavior: NotePencilDoubleTapBehavior
    var onDrawingChanged: ((Data, CGRect, CGSize) -> Void)?
    @ViewBuilder let paperContent: () -> PaperContent

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .clear
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.delaysContentTouches = true
        scrollView.canCancelContentTouches = true

        // ── CRITICAL: Only finger touches trigger scrolling ──
        scrollView.panGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]
        if let pinch = scrollView.pinchGestureRecognizer {
            pinch.allowedTouchTypes = [
                NSNumber(value: UITouch.TouchType.direct.rawValue)
            ]
        }

        // ── Content wrapper ──
        let contentWrapper = UIView()
        contentWrapper.backgroundColor = .clear
        scrollView.addSubview(contentWrapper)

        // ── Paper + text (SwiftUI hosted) ──
        let host = UIHostingController(rootView: AnyView(paperContent()))
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = true
        contentWrapper.addSubview(host.view)

        // ── PKCanvasView (on top, pencil-only) ──
        let canvas = PencilOnlyCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .pencilOnly
        canvas.isScrollEnabled = false
        canvas.isUserInteractionEnabled = true
        canvas.tool = inkToolState.pkTool
        canvas.delegate = context.coordinator

        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        canvas.addInteraction(pencilInteraction)

        if !drawingData.isEmpty,
           let drawing = try? PKDrawing(data: drawingData) {
            canvas.drawing = drawing
        }

        contentWrapper.addSubview(canvas)

        // ── Store references ──
        context.coordinator.scrollView = scrollView
        context.coordinator.contentWrapper = contentWrapper
        context.coordinator.hostingController = host
        context.coordinator.canvasView = canvas

        // ── Apply initial layout ──
        let contentSize = CGSize(width: pageWidth, height: pageHeight)
        scrollView.contentSize = contentSize
        contentWrapper.frame = CGRect(origin: .zero, size: contentSize)
        host.view.frame = CGRect(origin: .zero, size: contentSize)
        canvas.frame = CGRect(origin: .zero, size: contentSize)

        // ── Debug ──
        print("[INK-DEBUG] makeUIView: canvas=\(canvas.frame), scrollContentSize=\(contentSize), drawingPolicy=\(canvas.drawingPolicy.rawValue), isUserInteraction=\(canvas.isUserInteractionEnabled)")

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let c = context.coordinator

        // ── Update content size ──
        let contentSize = CGSize(width: pageWidth, height: pageHeight)
        if scrollView.contentSize != contentSize {
            scrollView.contentSize = contentSize
            c.contentWrapper?.frame = CGRect(origin: .zero, size: contentSize)
            c.hostingController?.view.frame = CGRect(origin: .zero, size: contentSize)
            c.canvasView?.frame = CGRect(origin: .zero, size: contentSize)
            print("[INK-DEBUG] updateUIView: resized to \(contentSize)")
        }

        // ── Update hosted SwiftUI ──
        c.hostingController?.rootView = AnyView(paperContent())

        // ── Update canvas tool ──
        c.canvasView?.tool = inkToolState.pkTool
        c.canvasView?.isUserInteractionEnabled = !isTextMode

        // ── Update drawing (skip if user is actively drawing) ──
        guard !c.isUpdatingFromDraw else { return }
        guard let canvas = c.canvasView else { return }

        if drawingData.isEmpty && !canvas.drawing.bounds.isEmpty {
            canvas.drawing = PKDrawing()
        } else if !drawingData.isEmpty {
            if let drawing = try? PKDrawing(data: drawingData),
               drawing.dataRepresentation() != canvas.drawing.dataRepresentation() {
                canvas.drawing = drawing
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        let parent: CanvasPageScrollContainer
        weak var scrollView: UIScrollView?
        weak var contentWrapper: UIView?
        var hostingController: UIHostingController<AnyView>?
        weak var canvasView: PKCanvasView?
        var isUpdatingFromDraw = false
        private var debounceWorkItem: DispatchWorkItem?
        private var lastDrawingToolState: NoteInkToolState

        init(parent: CanvasPageScrollContainer) {
            self.parent = parent
            self.lastDrawingToolState = parent.inkToolState
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            isUpdatingFromDraw = true
            parent.drawingData = canvasView.drawing.dataRepresentation()

            debounceWorkItem?.cancel()
            let data = canvasView.drawing.dataRepresentation()
            let bounds = canvasView.drawing.bounds
            let size = canvasView.bounds.size
            let callback = parent.onDrawingChanged
            let item = DispatchWorkItem { [weak self] in
                callback?(data, bounds, size)
                self?.isUpdatingFromDraw = false
            }
            debounceWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: item)
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            print("[INK-DEBUG] canvasViewDidBeginUsingTool: tool=\(canvasView.tool)")
        }

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            let behavior = parent.doubleTapBehavior
            switch behavior {
            case .switchToEraser:
                if parent.inkToolState.kind == .eraser {
                    parent.inkToolState = lastDrawingToolState
                } else {
                    if parent.inkToolState.kind == .pen || parent.inkToolState.kind == .highlighter {
                        lastDrawingToolState = parent.inkToolState
                    }
                    parent.inkToolState.kind = .eraser
                }
            case .switchToLasso:
                if parent.inkToolState.kind == .lasso {
                    parent.inkToolState = lastDrawingToolState
                } else {
                    if parent.inkToolState.kind == .pen || parent.inkToolState.kind == .highlighter {
                        lastDrawingToolState = parent.inkToolState
                    }
                    parent.inkToolState.kind = .lasso
                }
            case .togglePenHighlighter:
                if parent.inkToolState.kind == .highlighter {
                    parent.inkToolState = lastDrawingToolState
                } else {
                    if parent.inkToolState.kind == .pen {
                        lastDrawingToolState = parent.inkToolState
                    }
                    parent.inkToolState.kind = .highlighter
                }
            case .ignore:
                break
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - PencilOnlyCanvasView (PKCanvasView subclass)
// ═══════════════════════════════════════════════════════════════
//
// Sits on top of the paper content. Pencil always draws.
// Finger taps pass through to the paper/text host below.
// Finger drags are ignored here; the parent UIScrollView handles scrolling.

final class PencilOnlyCanvasView: PKCanvasView {

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // ── Check for Apple Pencil ──
        if let touches = event?.allTouches {
            for touch in touches {
                if touch.type == .pencil {
                    print("[INK-DEBUG] hitTest: PENCIL detected at \(point), returning self (frame=\(frame))")
                    return self
                }
            }
        }

        // ── Not a pencil touch → pass through to paper/text below ──
        print("[INK-DEBUG] hitTest: FINGER at \(point), returning nil (pass-through)")
        return nil
    }

    override var canBecomeFirstResponder: Bool { true }
}

#endif

// ═══════════════════════════════════════════════════════════════
// MARK: - Layer 0: Paper Background
// ═══════════════════════════════════════════════════════════════

private struct PaperBackgroundLayer: View {
    let pageWidth: CGFloat
    let pageHeight: CGFloat

    var body: some View {
        Canvas { context, size in
            var y = PageTokens.topInset
            while y < size.height - 28 {
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(PageTokens.ruleColor), lineWidth: 0.5)
                y += PageTokens.lineSpacing
            }
            let margin = Path { p in
                p.move(to: CGPoint(x: PageTokens.marginX, y: 18))
                p.addLine(to: CGPoint(x: PageTokens.marginX, y: size.height - 18))
            }
            context.stroke(margin, with: .color(PageTokens.marginColor), lineWidth: 1.2)
        }
        .frame(width: pageWidth, height: pageHeight)
        .allowsHitTesting(false)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Layer 1: Editable Text Layer (user's OWN content only)
// ═══════════════════════════════════════════════════════════════
//
// Shows ONLY:
//   - Tiny source hint (metadata, not source text)
//   - Editable title
//   - User-created text paragraphs
//   - User-inserted quotes (via ReferencePanel → "插入引用")
//   - "Add content" affordances
//   - Knowledge point tags
//
// Does NOT show:
//   - Source document text
//   - Auto-generated source previews
//   - Imported material

private struct EditableTextLayer: View {
    @ObservedObject var vm: NoteWorkspaceViewModel
    let isTextMode: Bool
    var onContentHeightChange: ((CGFloat) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sourceHintLine
                .padding(.bottom, 16)

            titleField
                .padding(.bottom, 16)

            thinDivider
                .padding(.bottom, 20)

            // ── User-inserted quote blocks ──
            ForEach(vm.blocks.filter { $0.kind == .quote }) { block in
                if let text = block.text?.nonEmpty {
                    quoteBlockView(text)
                        .padding(.bottom, 16)
                }
            }

            // ── User text paragraphs ──
            ForEach(vm.blocks.filter { $0.kind == .text }) { block in
                editableTextParagraph(block: block)
                    .padding(.bottom, 12)
            }

            // ── Add content actions ──
            addContentBar
                .padding(.top, 12)
                .padding(.bottom, 20)

            // ── Knowledge point tags ──
            if !vm.linkedKnowledgePoints.isEmpty {
                knowledgeTagStrip
                    .padding(.bottom, 16)
            }

            Spacer(minLength: 600)
        }
        .background(sizeReader)
        .onPreferenceChange(ContentHeightKey.self) { onContentHeightChange?($0) }
    }

    // MARK: - Source Hint (single line metadata, NOT source content)

    private var sourceHintLine: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 8, weight: .bold))
            Text(vm.sourceHint)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
            Spacer()
        }
        .foregroundStyle(PageTokens.muted.opacity(0.55))
    }

    // MARK: - Title

    private var titleField: some View {
        TextField("笔记标题", text: Binding(
            get: { vm.title },
            set: { vm.updateTitle($0) }
        ))
        .font(.system(size: 32, weight: .medium, design: .serif))
        .foregroundStyle(PageTokens.ink)
        .textFieldStyle(.plain)
    }

    // MARK: - Divider

    private var thinDivider: some View {
        Rectangle()
            .fill(PageTokens.divider)
            .frame(height: 0.5)
    }

    // MARK: - Quote Block

    private func quoteBlockView(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(PageTokens.quoteBar)
                .frame(width: 3)
                .padding(.vertical, 2)

            Text(text)
                .font(.system(size: 16, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(PageTokens.ink.opacity(0.7))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Text Paragraph

    private func editableTextParagraph(block: NoteBlock) -> some View {
        TextEditor(text: Binding(
            get: { block.text ?? "" },
            set: { vm.updateTextBlock(id: block.id, text: $0) }
        ))
        .font(.system(size: 16, weight: .regular, design: .serif))
        .foregroundStyle(PageTokens.ink.opacity(0.85))
        .lineSpacing(6)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .frame(minHeight: 44)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Add Content Bar

    private var addContentBar: some View {
        HStack(spacing: 14) {
            addContentButton(icon: "text.alignleft", label: "添加文本") {
                vm.addTextBlock()
            }
            addContentButton(icon: "quote.bubble", label: "插入引用") {
                // User adds quotes via ReferencePanel; this adds a text block
                vm.addTextBlock()
            }
            Spacer()
        }
    }

    private func addContentButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(PageTokens.accent.opacity(0.65))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(PageTokens.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Knowledge Tags

    private var knowledgeTagStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("关联概念")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(PageTokens.muted.opacity(0.45))

            FlowLayout(spacing: 6) {
                ForEach(vm.linkedKnowledgePoints) { point in
                    Text(point.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PageTokens.tagText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule(style: .continuous).fill(PageTokens.tagFill))
                }
            }
        }
    }

    // MARK: - Size Reader

    private var sizeReader: some View {
        GeometryReader { geo in
            Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - FlowLayout
// ═══════════════════════════════════════════════════════════════

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.reduce(CGFloat(0)) { r, row in
            r + row.height + (r > 0 ? spacing : 0)
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct RowItem { let subview: LayoutSubviews.Element; let size: CGSize }
    private struct Row { var items: [RowItem] = []; var height: CGFloat = 0 }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxW = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        var curW: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if curW + size.width > maxW, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
                curW = 0
            }
            rows[rows.count - 1].items.append(RowItem(subview: sv, size: size))
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            curW += size.width + spacing
        }
        return rows
    }
}

// MARK: - Preference Key

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - pkTool mapping
// ═══════════════════════════════════════════════════════════════

#if canImport(PencilKit)

private extension NoteInkToolState {
    var pkTool: PKTool {
        switch kind {
        case .pen:
            return PKInkingTool(.pen, color: UIColor(colorChoice.color), width: width)
        case .highlighter:
            return PKInkingTool(.marker, color: UIColor(colorChoice.color.opacity(0.45)), width: width * 1.45)
        case .eraser:
            return PKEraserTool(eraserPreset == .precise ? .vector : .bitmap, width: eraserWidth)
        case .lasso:
            return PKLassoTool()
        }
    }
}

#endif

// MARK: - String helper

private extension String {
    var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
