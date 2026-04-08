import SwiftUI

// ═══════════════════════════════════════════════════════════════
// BlockStylePicker — Lightweight per-block style popover
//
// Shows three rows:
//   1. Font style (4 presets)
//   2. Text color (6 swatches)
//   3. Highlight  (5 swatches including "none")
//
// The picker is designed to be attached as a popover via
// .popover(isPresented:) on each text or quote block.
// ═══════════════════════════════════════════════════════════════

struct BlockStylePicker: View {
    let blockKind: NoteBlockKind
    @Binding var textStyle: BlockTextStyle?
    @Binding var textColor: BlockTextColor?
    @Binding var highlightStyle: BlockHighlight?
    @Binding var fontSizePreset: BlockFontSize?

    private var resolvedStyle: BlockTextStyle {
        textStyle ?? BlockStyleMapping.defaultTextStyle(for: blockKind)
    }
    private var resolvedColor: BlockTextColor {
        textColor ?? BlockStyleMapping.defaultTextColor(for: blockKind)
    }
    private var resolvedHighlight: BlockHighlight {
        highlightStyle ?? .none
    }
    private var resolvedSize: BlockFontSize {
        fontSizePreset ?? .medium
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // ── Font Style ──
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("字体")
                HStack(spacing: 8) {
                    ForEach(BlockTextStyle.allCases) { style in
                        fontChip(style)
                    }
                }
            }

            Divider().opacity(0.3)

            // ── Font Size ──
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("字号")
                HStack(spacing: 8) {
                    ForEach(BlockFontSize.allCases) { size in
                        fontSizeChip(size)
                    }
                }
            }

            Divider().opacity(0.3)

            // ── Text Color ──
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("颜色")
                HStack(spacing: 8) {
                    ForEach(BlockTextColor.allCases) { color in
                        colorSwatch(color)
                    }
                }
            }

            Divider().opacity(0.3)

            // ── Highlight ──
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("高亮")
                HStack(spacing: 8) {
                    ForEach(BlockHighlight.allCases) { hl in
                        highlightSwatch(hl)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: - Sub-views

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(.secondary.opacity(0.6))
    }

    private func fontChip(_ style: BlockTextStyle) -> some View {
        let isSelected = resolvedStyle == style
        return Button {
            textStyle = style
        } label: {
            Text(style.previewText)
                .font(BlockStyleMapping.font(for: style, kind: blockKind, size: resolvedSize))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    private func fontSizeChip(_ size: BlockFontSize) -> some View {
        let isSelected = resolvedSize == size
        return Button {
            fontSizePreset = size
        } label: {
            Text(size.displayName)
                .font(.system(size: size.pointSize * 0.7, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.7))
                .frame(width: 44, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    private func colorSwatch(_ color: BlockTextColor) -> some View {
        let isSelected = resolvedColor == color
        return Button {
            textColor = color
        } label: {
            Circle()
                .fill(BlockStyleMapping.swatchColor(for: color))
                .frame(width: 24, height: 24)
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 2)
                            .frame(width: 18, height: 18)
                    }
                }
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(BlockStyleMapping.swatchColor(for: color), lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.displayName)
    }

    private func highlightSwatch(_ hl: BlockHighlight) -> some View {
        let isSelected = resolvedHighlight == hl
        return Button {
            highlightStyle = hl
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(BlockStyleMapping.highlightSwatchColor(for: hl))
                    .frame(width: 32, height: 22)
                if hl == .none {
                    Image(systemName: "nosign")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.4))
                } else {
                    Text(hl.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.5))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hl.displayName)
    }
}
