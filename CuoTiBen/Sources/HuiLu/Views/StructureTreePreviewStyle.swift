import SwiftUI

enum StructureTreePreviewDensityMode: String, CaseIterable, Identifiable {
    case detailed = "详解"
    case compact = "概览"

    var id: String { rawValue }
}

enum StructureTreePreviewNodeRole {
    case focus
    case mainPath
    case branch
}

struct StructureTreePreviewCanvasCommand: Equatable {
    enum Action: Equatable {
        case zoomIn
        case zoomOut
        case focus
    }

    let action: Action
    let token = UUID()
}

struct StructureTreePreviewMetrics {
    let densityMode: StructureTreePreviewDensityMode

    var canvasViewportHeight: CGFloat {
        switch densityMode {
        case .detailed:
            return 548
        case .compact:
            return 452
        }
    }

    var contentInset: CGSize {
        switch densityMode {
        case .detailed:
            return CGSize(width: 22, height: 22)
        case .compact:
            return CGSize(width: 18, height: 18)
        }
    }

    var mainColumnX: CGFloat { contentInset.width }

    var rowSpacing: CGFloat {
        switch densityMode {
        case .detailed: return 26
        case .compact: return 18
        }
    }

    var branchColumnSpacing: CGFloat {
        switch densityMode {
        case .detailed: return 20
        case .compact: return 14
        }
    }

    var branchNodeSpacing: CGFloat {
        switch densityMode {
        case .detailed: return 10
        case .compact: return 6
        }
    }

    var trailingInset: CGFloat {
        switch densityMode {
        case .detailed: return 20
        case .compact: return 16
        }
    }

    var bottomInset: CGFloat {
        switch densityMode {
        case .detailed: return 30
        case .compact: return 24
        }
    }

    var focusReadableScale: CGFloat {
        switch densityMode {
        case .detailed: return 0.98
        case .compact: return 0.94
        }
    }

    var defaultScale: CGFloat {
        switch densityMode {
        case .detailed: return 0.9
        case .compact: return 0.94
        }
    }

    var minimumScale: CGFloat { 0.72 }
    var maximumScale: CGFloat { 1.68 }

    var focusXRatio: CGFloat {
        switch densityMode {
        case .detailed: return 0.42
        case .compact: return 0.47
        }
    }

    var focusYRatio: CGFloat { 0.42 }

    var leadingViewportPadding: CGFloat {
        switch densityMode {
        case .detailed: return 26
        case .compact: return 20
        }
    }

    var trailingViewportPadding: CGFloat { 24 }
    var topViewportPadding: CGFloat { 20 }
    var bottomViewportPadding: CGFloat { 20 }

    var collapsedBranchLimit: Int {
        switch densityMode {
        case .detailed: return 2
        case .compact: return 1
        }
    }

    var focusedCollapsedBranchLimit: Int {
        switch densityMode {
        case .detailed: return 3
        case .compact: return 2
        }
    }

    var expandedBranchLimit: Int {
        switch densityMode {
        case .detailed: return 6
        case .compact: return 4
        }
    }

    var minimapWidth: CGFloat {
        switch densityMode {
        case .detailed: return 92
        case .compact: return 82
        }
    }

    var renderPadding: CGSize {
        switch densityMode {
        case .detailed:
            return CGSize(width: 190, height: 150)
        case .compact:
            return CGSize(width: 150, height: 116)
        }
    }

    func cardSize(for role: StructureTreePreviewNodeRole) -> CGSize {
        switch (densityMode, role) {
        case (.detailed, .focus):
            return CGSize(width: 320, height: 170)
        case (.detailed, .mainPath):
            return CGSize(width: 258, height: 128)
        case (.detailed, .branch):
            return CGSize(width: 212, height: 104)
        case (.compact, .focus):
            return CGSize(width: 274, height: 88)
        case (.compact, .mainPath):
            return CGSize(width: 220, height: 74)
        case (.compact, .branch):
            return CGSize(width: 188, height: 66)
        }
    }

    func titleLineLimit(for role: StructureTreePreviewNodeRole) -> Int {
        switch (densityMode, role) {
        case (.compact, .branch):
            return 1
        case (.compact, _):
            return 2
        default:
            return 2
        }
    }

    func summaryLineLimit(for role: StructureTreePreviewNodeRole) -> Int {
        switch densityMode {
        case .detailed:
            return role == .branch ? 1 : 2
        case .compact:
            return 0
        }
    }

    func titleCharacterLimit(for role: StructureTreePreviewNodeRole) -> Int {
        switch (densityMode, role) {
        case (.detailed, .focus):
            return 34
        case (.detailed, .mainPath):
            return 26
        case (.detailed, .branch):
            return 22
        case (.compact, .focus):
            return 28
        case (.compact, .mainPath):
            return 22
        case (.compact, .branch):
            return 18
        }
    }

    func summaryCharacterLimit(for role: StructureTreePreviewNodeRole) -> Int {
        switch (densityMode, role) {
        case (.detailed, .focus):
            return 62
        case (.detailed, .mainPath):
            return 46
        case (.detailed, .branch):
            return 34
        case (.compact, _):
            return 0
        }
    }
}

enum StructureTreePreviewPalette {
    static let canvasFill = Color(red: 0.975, green: 0.981, blue: 0.992)
    static let canvasStroke = Color(red: 0.79, green: 0.83, blue: 0.92).opacity(0.24)
    static let canvasShadow = Color.black.opacity(0.08)

    static let toolbarGlass = Color.white.opacity(0.66)
    static let toolbarStroke = Color(red: 0.72, green: 0.78, blue: 0.88).opacity(0.24)
    static let toolbarText = Color.black.opacity(0.72)
    static let mutedText = Color.black.opacity(0.56)

    static let focusAction = Color(red: 0.25, green: 0.43, blue: 0.86)
    static let connector = Color(red: 0.64, green: 0.72, blue: 0.86).opacity(0.5)
    static let branchConnector = Color(red: 0.74, green: 0.79, blue: 0.9).opacity(0.46)

    static let minimapFill = Color.white.opacity(0.5)
    static let minimapStroke = Color(red: 0.74, green: 0.79, blue: 0.88).opacity(0.18)
    static let minimapViewport = Color.black.opacity(0.34)

    static func accent(for nodeType: PedagogicalNodeType) -> Color {
        switch nodeType {
        case .passageRoot:
            return Color(red: 0.36, green: 0.49, blue: 0.78)
        case .paragraphTheme:
            return Color(red: 0.42, green: 0.53, blue: 0.78)
        case .teachingFocus:
            return Color(red: 0.79, green: 0.62, blue: 0.32)
        case .supportingSentence:
            return Color(red: 0.45, green: 0.67, blue: 0.82)
        case .questionLink:
            return Color(red: 0.77, green: 0.55, blue: 0.67)
        case .vocabularySupport:
            return Color(red: 0.39, green: 0.67, blue: 0.62)
        case .metaInstruction:
            return Color(red: 0.56, green: 0.6, blue: 0.68)
        case .answerKey:
            return Color(red: 0.82, green: 0.67, blue: 0.35)
        }
    }

    static func iconName(for nodeType: PedagogicalNodeType) -> String {
        switch nodeType {
        case .passageRoot:
            return "book.closed.fill"
        case .paragraphTheme:
            return "bookmark.fill"
        case .teachingFocus:
            return "lightbulb.fill"
        case .supportingSentence:
            return "doc.text.fill"
        case .questionLink:
            return "questionmark.bubble.fill"
        case .vocabularySupport:
            return "character.book.closed.fill"
        case .metaInstruction:
            return "info.circle.fill"
        case .answerKey:
            return "checkmark.seal.fill"
        }
    }
}
