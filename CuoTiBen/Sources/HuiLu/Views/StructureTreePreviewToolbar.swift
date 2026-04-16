import SwiftUI

struct StructureTreePreviewToolbar: View {
    let densityMode: StructureTreePreviewDensityMode
    let scalePercentage: Int
    let onDensityChange: (StructureTreePreviewDensityMode) -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onFocus: () -> Void
    let onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            densitySegment

            Spacer(minLength: 0)

            Text("\(scalePercentage)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(StructureTreePreviewPalette.mutedText)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.54))
                )

            HStack(spacing: 8) {
                toolbarIconButton(systemName: "minus.magnifyingglass", action: onZoomOut)
                toolbarIconButton(systemName: "plus.magnifyingglass", action: onZoomIn)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(StructureTreePreviewPalette.toolbarGlass)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(StructureTreePreviewPalette.toolbarStroke, lineWidth: 1)
                    )
            )

            Button(action: onFocus) {
                Text("聚焦当前")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(
                        Capsule(style: .continuous)
                            .fill(StructureTreePreviewPalette.focusAction)
                    )
            }
            .buttonStyle(.plain)

            if let onClose {
                toolbarIconButton(systemName: "xmark", action: onClose)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(StructureTreePreviewPalette.toolbarGlass)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(StructureTreePreviewPalette.toolbarStroke, lineWidth: 1)
                )
        )
    }

    private var densitySegment: some View {
        HStack(spacing: 6) {
            ForEach(StructureTreePreviewDensityMode.allCases) { mode in
                Button {
                    onDensityChange(mode)
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(mode == densityMode ? StructureTreePreviewPalette.focusAction : StructureTreePreviewPalette.toolbarText)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(mode == densityMode ? Color.white.opacity(0.96) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            Capsule(style: .continuous)
                .fill(Color(red: 0.9, green: 0.92, blue: 0.96).opacity(0.9))
        )
    }

    private func toolbarIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(StructureTreePreviewPalette.toolbarText)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.86))
                )
        }
        .buttonStyle(.plain)
    }
}
