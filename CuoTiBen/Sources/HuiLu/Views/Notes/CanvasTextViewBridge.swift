import SwiftUI
import UIKit

struct CanvasTextViewBridge: UIViewRepresentable {
    let text: String
    let font: UIFont
    let textColor: UIColor
    let alignment: NSTextAlignment
    let highlightColor: UIColor?
    let isEditing: Bool
    let onTextChange: (String) -> Void
    let onHeightChange: (CGFloat) -> Void
    let onEndEditing: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = CanvasEditingTextView()
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.keyboardAppearance = .default
        applyStyle(textView)
        textView.text = text
        DispatchQueue.main.async {
            textView.becomeFirstResponder()
        }
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        if textView.text != text {
            textView.text = text
        }
        applyStyle(textView)

        if isEditing {
            let fitting = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
            let resolvedHeight = max(fitting.height, 32)
            if abs(resolvedHeight - textView.bounds.height) > 1 {
                DispatchQueue.main.async {
                    onHeightChange(resolvedHeight)
                }
            }
        }
    }

    static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) {
        uiView.resignFirstResponder()
    }

    private func applyStyle(_ textView: UITextView) {
        textView.font = font
        textView.textColor = textColor.withAlphaComponent(0.9)
        textView.textAlignment = alignment
        textView.backgroundColor = .clear
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CanvasTextViewBridge

        init(parent: CanvasTextViewBridge) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.onTextChange(textView.text)
            let fitting = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
            parent.onHeightChange(max(fitting.height, 32))
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onEndEditing()
        }
    }
}

final class CanvasEditingTextView: UITextView {
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configureForCanvasEditing()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureForCanvasEditing()
    }

    private func configureForCanvasEditing() {
        textDragInteraction?.isEnabled = false
        panGestureRecognizer.isEnabled = false
        gestureRecognizers?.forEach { recognizer in
            if recognizer is UIPanGestureRecognizer {
                recognizer.isEnabled = false
            }
        }
    }
}
