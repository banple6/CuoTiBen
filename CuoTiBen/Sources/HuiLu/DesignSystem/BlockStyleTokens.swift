import SwiftUI

// ═══════════════════════════════════════════════════════════════
// Block-Level Style System — V1
//
// Provides serializable enums for text style, color, and highlight
// on a per-NoteBlock basis. All values are low-saturation and
// consistent with the Digital Archivist design language.
// ═══════════════════════════════════════════════════════════════

// MARK: - Text Style Preset

enum BlockTextStyle: String, Codable, CaseIterable, Identifiable {
    case classicSerif
    case modernSans
    case readingSerif
    case monoNote

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classicSerif:  return "经典衬线"
        case .modernSans:    return "现代无衬线"
        case .readingSerif:  return "阅读衬线"
        case .monoNote:      return "等宽批注"
        }
    }

    var previewText: String {
        switch self {
        case .classicSerif:  return "Aa 经典"
        case .modernSans:    return "Aa 现代"
        case .readingSerif:  return "Aa 阅读"
        case .monoNote:      return "Aa 批注"
        }
    }
}

// MARK: - Text Color Preset

enum BlockTextColor: String, Codable, CaseIterable, Identifiable {
    case inkBlack
    case archiveBlue
    case noteGreen
    case mutedRed
    case mutedPurple
    case graphiteGray

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inkBlack:     return "墨黑"
        case .archiveBlue:  return "档案蓝"
        case .noteGreen:    return "笔记绿"
        case .mutedRed:     return "批注红"
        case .mutedPurple:  return "引用紫"
        case .graphiteGray: return "石墨灰"
        }
    }
}

// MARK: - Highlight Preset

enum BlockHighlight: String, Codable, CaseIterable, Identifiable {
    case none
    case yellow
    case blue
    case green
    case pink
    case orange

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:   return "无"
        case .yellow: return "黄"
        case .blue:   return "蓝"
        case .green:  return "绿"
        case .pink:   return "粉"
        case .orange: return "橙"
        }
    }
}

// MARK: - Font Size Preset

enum BlockFontSize: String, Codable, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case xlarge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small:  return "小"
        case .medium: return "中"
        case .large:  return "大"
        case .xlarge: return "特大"
        }
    }

    var pointSize: CGFloat {
        switch self {
        case .small:  return 14
        case .medium: return 16
        case .large:  return 19
        case .xlarge: return 23
        }
    }

    /// Short label for toolbar inspector chips.
    var chipLabel: String {
        switch self {
        case .small:  return "S"
        case .medium: return "M"
        case .large:  return "L"
        case .xlarge: return "XL"
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Style Mapping
// ═══════════════════════════════════════════════════════════════

enum BlockStyleMapping {

    // MARK: Font

    static func font(for style: BlockTextStyle, kind: NoteBlockKind, size: BlockFontSize = .medium) -> Font {
        let baseSize = size.pointSize
        let adjustedSize: CGFloat = kind == .quote ? baseSize - 1 : baseSize
        switch style {
        case .classicSerif:
            return .system(size: adjustedSize, weight: .regular, design: .serif)
        case .modernSans:
            return .system(size: adjustedSize, weight: .regular, design: .default)
        case .readingSerif:
            return .system(size: adjustedSize + 0.5, weight: .regular, design: .serif)
        case .monoNote:
            return .system(size: adjustedSize - 1, weight: .regular, design: .monospaced)
        }
    }

    // MARK: Color

    static func color(for preset: BlockTextColor) -> Color {
        switch preset {
        case .inkBlack:
            return Color(red: 0.08, green: 0.08, blue: 0.06)
        case .archiveBlue:
            return Color(red: 0.12, green: 0.30, blue: 0.52)
        case .noteGreen:
            return Color(red: 0.18, green: 0.42, blue: 0.30)
        case .mutedRed:
            return Color(red: 0.55, green: 0.22, blue: 0.18)
        case .mutedPurple:
            return Color(red: 0.38, green: 0.26, blue: 0.50)
        case .graphiteGray:
            return Color(red: 0.35, green: 0.35, blue: 0.33)
        }
    }

    /// Swatch color for the picker UI (slightly more saturated for visibility)
    static func swatchColor(for preset: BlockTextColor) -> Color {
        switch preset {
        case .inkBlack:
            return Color(red: 0.10, green: 0.10, blue: 0.08)
        case .archiveBlue:
            return Color(red: 0.15, green: 0.38, blue: 0.65)
        case .noteGreen:
            return Color(red: 0.22, green: 0.52, blue: 0.36)
        case .mutedRed:
            return Color(red: 0.65, green: 0.28, blue: 0.22)
        case .mutedPurple:
            return Color(red: 0.48, green: 0.32, blue: 0.60)
        case .graphiteGray:
            return Color(red: 0.45, green: 0.45, blue: 0.42)
        }
    }

    // MARK: Highlight

    static func highlightBackground(for highlight: BlockHighlight) -> Color? {
        switch highlight {
        case .none:
            return nil
        case .yellow:
            return Color(red: 0.98, green: 0.95, blue: 0.82).opacity(0.55)
        case .blue:
            return Color(red: 0.88, green: 0.93, blue: 0.97).opacity(0.55)
        case .green:
            return Color(red: 0.88, green: 0.96, blue: 0.90).opacity(0.55)
        case .pink:
            return Color(red: 0.97, green: 0.90, blue: 0.93).opacity(0.55)
        case .orange:
            return Color(red: 0.98, green: 0.93, blue: 0.82).opacity(0.55)
        }
    }

    /// Swatch for the picker (more visible)
    static func highlightSwatchColor(for highlight: BlockHighlight) -> Color {
        switch highlight {
        case .none:
            return Color(red: 0.92, green: 0.92, blue: 0.90)
        case .yellow:
            return Color(red: 0.96, green: 0.92, blue: 0.72)
        case .blue:
            return Color(red: 0.80, green: 0.88, blue: 0.96)
        case .green:
            return Color(red: 0.80, green: 0.94, blue: 0.84)
        case .pink:
            return Color(red: 0.95, green: 0.84, blue: 0.90)
        case .orange:
            return Color(red: 0.96, green: 0.90, blue: 0.72)
        }
    }

    // MARK: Defaults per block kind

    static func defaultTextStyle(for kind: NoteBlockKind) -> BlockTextStyle {
        switch kind {
        case .quote: return .classicSerif
        case .text:  return .readingSerif
        case .ink:   return .readingSerif
        }
    }

    static func defaultTextColor(for kind: NoteBlockKind) -> BlockTextColor {
        switch kind {
        case .quote: return .archiveBlue
        case .text:  return .graphiteGray
        case .ink:   return .inkBlack
        }
    }

    static func defaultHighlight(for _: NoteBlockKind) -> BlockHighlight {
        return .none
    }

    static func defaultFontSize(for _: NoteBlockKind) -> BlockFontSize {
        return .medium
    }

    // MARK: - UIKit font mapping (for UITextView bridge)

    static func uiFont(for style: BlockTextStyle, size: BlockFontSize = .medium) -> UIFont {
        let pts = size.pointSize
        switch style {
        case .classicSerif:
            return UIFont(descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
                .withDesign(.serif)!, size: pts)
        case .modernSans:
            return UIFont.systemFont(ofSize: pts, weight: .regular)
        case .readingSerif:
            return UIFont(descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
                .withDesign(.serif)!, size: pts + 0.5)
        case .monoNote:
            return UIFont.monospacedSystemFont(ofSize: pts - 1, weight: .regular)
        }
    }

    static func uiColor(for preset: BlockTextColor) -> UIColor {
        switch preset {
        case .inkBlack:     return UIColor(red: 0.08, green: 0.08, blue: 0.06, alpha: 1)
        case .archiveBlue:  return UIColor(red: 0.12, green: 0.30, blue: 0.52, alpha: 1)
        case .noteGreen:    return UIColor(red: 0.18, green: 0.42, blue: 0.30, alpha: 1)
        case .mutedRed:     return UIColor(red: 0.55, green: 0.22, blue: 0.18, alpha: 1)
        case .mutedPurple:  return UIColor(red: 0.38, green: 0.26, blue: 0.50, alpha: 1)
        case .graphiteGray: return UIColor(red: 0.35, green: 0.35, blue: 0.33, alpha: 1)
        }
    }

    static func uiHighlightColor(for highlight: BlockHighlight) -> UIColor? {
        switch highlight {
        case .none:   return nil
        case .yellow: return UIColor(red: 0.98, green: 0.95, blue: 0.82, alpha: 0.55)
        case .blue:   return UIColor(red: 0.88, green: 0.93, blue: 0.97, alpha: 0.55)
        case .green:  return UIColor(red: 0.88, green: 0.96, blue: 0.90, alpha: 0.55)
        case .pink:   return UIColor(red: 0.97, green: 0.90, blue: 0.93, alpha: 0.55)
        case .orange: return UIColor(red: 0.98, green: 0.93, blue: 0.82, alpha: 0.55)
        }
    }
}
