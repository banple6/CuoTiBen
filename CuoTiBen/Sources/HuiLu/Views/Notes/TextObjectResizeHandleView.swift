import SwiftUI

struct TextObjectResizeHandle: View {
    private static let hitSize: CGFloat = 36
    private static let dotSize: CGFloat = 10

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: Self.hitSize, height: Self.hitSize)
                .contentShape(Rectangle())

            Circle()
                .fill(Color.accentColor)
                .frame(width: Self.dotSize, height: Self.dotSize)
                .overlay(
                    Circle().stroke(Color.white, lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .allowsHitTesting(false)
        }
    }
}

enum ResizeCorner: String, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }

    func apply(delta: CGSize, origin: CGPoint, size: CGSize, minW: CGFloat, minH: CGFloat) -> CGRect {
        var x = origin.x
        var y = origin.y
        var width = size.width
        var height = size.height

        switch self {
        case .topLeft:
            let nextWidth = width - delta.width
            let nextHeight = height - delta.height
            if nextWidth >= minW { x += delta.width; width = nextWidth } else { x += (width - minW); width = minW }
            if nextHeight >= minH { y += delta.height; height = nextHeight } else { y += (height - minH); height = minH }
        case .topRight:
            width = max(width + delta.width, minW)
            let nextHeight = height - delta.height
            if nextHeight >= minH { y += delta.height; height = nextHeight } else { y += (height - minH); height = minH }
        case .bottomLeft:
            let nextWidth = width - delta.width
            if nextWidth >= minW { x += delta.width; width = nextWidth } else { x += (width - minW); width = minW }
            height = max(height + delta.height, minH)
        case .bottomRight:
            width = max(width + delta.width, minW)
            height = max(height + delta.height, minH)
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    func xOffsetFromCenter(_ width: CGFloat) -> CGFloat {
        switch self {
        case .topLeft, .bottomLeft: return -width / 2
        case .topRight, .bottomRight: return width / 2
        }
    }

    func yOffsetFromCenter(_ height: CGFloat) -> CGFloat {
        switch self {
        case .topLeft, .topRight: return -height / 2
        case .bottomLeft, .bottomRight: return height / 2
        }
    }
}
