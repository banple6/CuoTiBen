import SwiftUI
import UIKit

private enum CanvasTextVisualTokens {
    static let mutedText = Color(red: 0.45, green: 0.45, blue: 0.42)
}

struct CanvasTextObjectContainer: View {
    let obj: CanvasTextObject
    let isSelected: Bool
    let isEditing: Bool
    let allowsTransforms: Bool
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let onTextChange: (String) -> Void
    let onHeightChange: (CGFloat) -> Void
    let onSelect: () -> Void
    let onStartEditing: () -> Void
    let onEndEditing: () -> Void
    let onCommitMove: (CGPoint) -> Void
    let onCommitResize: (CGFloat, CGFloat, CGFloat, CGFloat) -> Void

    @State private var draftX: CGFloat = 0
    @State private var draftY: CGFloat = 0
    @State private var draftWidth: CGFloat = 260
    @State private var draftHeight: CGFloat = 44
    @State private var isDragging = false
    @State private var isResizing = false
    @State private var dragStartOrigin: CGPoint?
    @State private var resizeStartRect: CGRect?
    @State private var lastTapTime: Date = .distantPast

    private var uiFont: UIFont {
        BlockStyleMapping.uiFont(for: obj.resolvedTextStyle, size: obj.resolvedFontSize)
    }

    private var uiTextColor: UIColor {
        BlockStyleMapping.uiColor(for: obj.resolvedTextColor)
    }

    private var uiHighlightColor: UIColor? {
        BlockStyleMapping.uiHighlightColor(for: obj.resolvedHighlight)
    }

    private var swiftUITextColor: Color {
        BlockStyleMapping.color(for: obj.resolvedTextColor)
    }

    private var swiftUIFont: Font {
        BlockStyleMapping.font(for: obj.resolvedTextStyle, kind: .text, size: obj.resolvedFontSize)
    }

    private var highlightColor: Color? {
        BlockStyleMapping.highlightBackground(for: obj.resolvedHighlight)
    }

    var body: some View {
        ZStack {
            contentBody
                .frame(width: draftWidth, height: draftHeight)

            if !isEditing {
                Color.clear
                    .frame(width: draftWidth, height: draftHeight)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard isSelected, allowsTransforms else { return }
                                let distance = max(abs(value.translation.width), abs(value.translation.height))
                                if distance > 4 {
                                    if !isDragging {
                                        isDragging = true
                                        dragStartOrigin = CGPoint(x: draftX, y: draftY)
                                    }
                                    let base = dragStartOrigin ?? CGPoint(x: draftX, y: draftY)
                                    draftX = clampX(base.x + value.translation.width, width: draftWidth)
                                    draftY = clampY(base.y + value.translation.height, height: draftHeight)
                                }
                            }
                            .onEnded { value in
                                guard isDragging else {
                                    handleTap()
                                    return
                                }
                                let base = dragStartOrigin ?? CGPoint(x: draftX, y: draftY)
                                draftX = clampX(base.x + value.translation.width, width: draftWidth)
                                draftY = clampY(base.y + value.translation.height, height: draftHeight)
                                isDragging = false
                                dragStartOrigin = nil
                                onCommitMove(CGPoint(x: draftX, y: draftY))
                            }
                    )
            }

            if isSelected {
                TextObjectSelectionOverlay(
                    width: draftWidth,
                    height: draftHeight,
                    isEditing: isEditing,
                    onResizeChanged: { corner, value in
                        guard !isEditing, allowsTransforms else { return }
                        if !isResizing {
                            isResizing = true
                            resizeStartRect = CGRect(x: draftX, y: draftY, width: draftWidth, height: draftHeight)
                        }
                        let baseRect = resizeStartRect ?? CGRect(x: draftX, y: draftY, width: draftWidth, height: draftHeight)
                        let nextRect = corner.apply(
                            delta: value.translation,
                            origin: baseRect.origin,
                            size: baseRect.size,
                            minW: obj.minWidth,
                            minH: obj.minHeight
                        )
                        let clampedRect = clamp(rect: nextRect)
                        draftX = clampedRect.origin.x
                        draftY = clampedRect.origin.y
                        draftWidth = clampedRect.width
                        draftHeight = clampedRect.height
                    },
                    onResizeEnded: { corner, value in
                        guard !isEditing, allowsTransforms else { return }
                        let baseRect = resizeStartRect ?? CGRect(x: draftX, y: draftY, width: draftWidth, height: draftHeight)
                        let nextRect = corner.apply(
                            delta: value.translation,
                            origin: baseRect.origin,
                            size: baseRect.size,
                            minW: obj.minWidth,
                            minH: obj.minHeight
                        )
                        let clampedRect = clamp(rect: nextRect)
                        draftX = clampedRect.origin.x
                        draftY = clampedRect.origin.y
                        draftWidth = clampedRect.width
                        draftHeight = clampedRect.height
                        isResizing = false
                        resizeStartRect = nil
                        onCommitResize(draftX, draftY, draftWidth, draftHeight)
                    }
                )
            }
        }
        .position(x: draftX + draftWidth / 2, y: draftY + draftHeight / 2)
        .transaction { $0.animation = nil }
        .onAppear {
            draftX = obj.x
            draftY = obj.y
            draftWidth = obj.width
            draftHeight = obj.height
        }
        .onChange(of: obj.x) { value in
            if !isDragging && !isResizing { draftX = value }
        }
        .onChange(of: obj.y) { value in
            if !isDragging && !isResizing { draftY = value }
        }
        .onChange(of: obj.width) { value in
            if !isDragging && !isResizing { draftWidth = value }
        }
        .onChange(of: obj.height) { value in
            if !isDragging && !isResizing { draftHeight = value }
        }
    }

    private func clampX(_ x: CGFloat, width: CGFloat) -> CGFloat {
        max(0, min(x, pageWidth - width))
    }

    private func clampY(_ y: CGFloat, height: CGFloat) -> CGFloat {
        max(0, min(y, pageHeight - height))
    }

    private func clamp(rect: CGRect) -> CGRect {
        let width = min(max(rect.width, obj.minWidth), pageWidth)
        let height = min(max(rect.height, obj.minHeight), pageHeight)
        let x = clampX(rect.origin.x, width: width)
        let y = clampY(rect.origin.y, height: height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    @ViewBuilder
    private var contentBody: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(highlightColor ?? Color.clear)

            if isEditing {
                CanvasTextViewBridge(
                    text: obj.text,
                    font: uiFont,
                    textColor: uiTextColor,
                    alignment: obj.resolvedAlignment.nsAlignment,
                    highlightColor: uiHighlightColor,
                    isEditing: isEditing,
                    onTextChange: onTextChange,
                    onHeightChange: { newHeight in
                        guard !isDragging && !isResizing else { return }
                        onHeightChange(newHeight)
                        draftHeight = max(newHeight, obj.minHeight)
                    },
                    onEndEditing: onEndEditing
                )
            } else {
                Text(obj.text.isEmpty ? " " : obj.text)
                    .font(swiftUIFont)
                    .foregroundStyle(obj.text.isEmpty ? CanvasTextVisualTokens.mutedText.opacity(0.25) : swiftUITextColor.opacity(0.9))
                    .multilineTextAlignment(obj.resolvedAlignment.swiftUIAlignment)
                    .lineSpacing(4)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func handleTap() {
        let now = Date()
        let interval = now.timeIntervalSince(lastTapTime)
        lastTapTime = now

        if isSelected && !isEditing && interval < 0.4 {
            lastTapTime = .distantPast
            if allowsTransforms {
                onStartEditing()
            }
        } else if !isSelected {
            onSelect()
        }
    }
}
