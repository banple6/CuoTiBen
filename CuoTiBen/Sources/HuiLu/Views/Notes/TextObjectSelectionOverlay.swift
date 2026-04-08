import SwiftUI

struct TextObjectSelectionOverlay: View {
    let width: CGFloat
    let height: CGFloat
    let isEditing: Bool
    let onResizeChanged: (ResizeCorner, DragGesture.Value) -> Void
    let onResizeEnded: (ResizeCorner, DragGesture.Value) -> Void

    var body: some View {
        ZStack {
            if isEditing {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(
                        Color.accentColor.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                    )
                    .frame(width: width, height: height)
                    .allowsHitTesting(false)

                ForEach(ResizeCorner.allCases) { corner in
                    Circle()
                        .fill(Color.accentColor.opacity(0.25))
                        .frame(width: 7, height: 7)
                        .offset(
                            x: corner.xOffsetFromCenter(width),
                            y: corner.yOffsetFromCenter(height)
                        )
                        .allowsHitTesting(false)
                }
            } else {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 1.5)
                    .frame(width: width, height: height)
                    .allowsHitTesting(false)

                ForEach(ResizeCorner.allCases) { corner in
                    TextObjectResizeHandle()
                        .offset(
                            x: corner.xOffsetFromCenter(width),
                            y: corner.yOffsetFromCenter(height)
                        )
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    onResizeChanged(corner, value)
                                }
                                .onEnded { value in
                                    onResizeEnded(corner, value)
                                }
                        )
                }
            }
        }
    }
}
