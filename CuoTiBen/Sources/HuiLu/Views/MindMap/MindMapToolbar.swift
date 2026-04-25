import SwiftUI

struct MindMapToolbar: View {
    let densityMode: MindMapDensityMode
    let showsAuxiliary: Bool
    let showsDiagnostics: Bool
    let isUsingFallback: Bool
    let onDensityChange: (MindMapDensityMode) -> Void
    let onFitToContent: () -> Void
    let onFocusCurrent: () -> Void
    let onToggleAuxiliary: () -> Void
    let onToggleDiagnostics: () -> Void
    let onRegenerate: () -> Void
    let onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            densityPicker

            Spacer(minLength: 0)

            if isUsingFallback {
                Label("本地骨架", systemImage: "sparkles.rectangle.stack")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.41, green: 0.47, blue: 0.2))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(red: 0.97, green: 0.95, blue: 0.77))
                    )
            }

            toolbarButton(title: "适配全图", systemName: "arrow.up.left.and.down.right.magnifyingglass", action: onFitToContent)
            toolbarButton(title: "聚焦当前", systemName: "scope", action: onFocusCurrent)
            toolbarButton(title: showsAuxiliary ? "隐藏辅助层" : "显示辅助层", systemName: "square.stack.3d.down.forward", action: onToggleAuxiliary)
            toolbarButton(title: showsDiagnostics ? "隐藏诊断" : "显示诊断", systemName: "exclamationmark.bubble", action: onToggleDiagnostics)
            toolbarButton(title: "重新生成地图", systemName: "arrow.clockwise", action: onRegenerate)

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.72))
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.88))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 1)
                )
        )
    }

    private var densityPicker: some View {
        HStack(spacing: 6) {
            ForEach(MindMapDensityMode.allCases) { mode in
                Button {
                    onDensityChange(mode)
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(mode == densityMode ? Color(red: 0.19, green: 0.32, blue: 0.52) : Color.black.opacity(0.62))
                        .padding(.horizontal, 16)
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
                .fill(Color(red: 0.92, green: 0.94, blue: 0.97).opacity(0.94))
        )
    }

    private func toolbarButton(title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                Text(title)
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.72))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.9))
            )
        }
        .buttonStyle(.plain)
    }
}
