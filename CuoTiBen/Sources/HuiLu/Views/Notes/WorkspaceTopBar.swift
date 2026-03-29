import SwiftUI
import UIKit

enum NoteWorkspaceAppearance: String, CaseIterable, Identifiable {
    case paper
    case night
    case eyeCare

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper:
            return "纸质"
        case .night:
            return "夜间"
        case .eyeCare:
            return "护眼"
        }
    }

    var icon: String {
        switch self {
        case .paper:
            return "doc.text"
        case .night:
            return "moon.stars"
        case .eyeCare:
            return "leaf"
        }
    }

    var isDark: Bool {
        self == .night
    }
}

enum NoteInkToolKind: String, CaseIterable, Identifiable {
    case pen
    case highlighter
    case eraser
    case lasso

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen:
            return "笔刷"
        case .highlighter:
            return "荧光笔"
        case .eraser:
            return "橡皮"
        case .lasso:
            return "套索"
        }
    }

    var icon: String {
        switch self {
        case .pen:
            return "pencil.tip"
        case .highlighter:
            return "highlighter"
        case .eraser:
            return "eraser"
        case .lasso:
            return "lasso"
        }
    }
}

enum NoteInkColorPreset: String, CaseIterable, Identifiable {
    case blue
    case black
    case red
    case green
    case yellow
    case purple

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue:
            return Color(red: 48 / 255, green: 126 / 255, blue: 255 / 255)
        case .black:
            return Color(red: 34 / 255, green: 37 / 255, blue: 43 / 255)
        case .red:
            return Color(red: 218 / 255, green: 72 / 255, blue: 63 / 255)
        case .green:
            return Color(red: 70 / 255, green: 155 / 255, blue: 86 / 255)
        case .yellow:
            return Color(red: 247 / 255, green: 204 / 255, blue: 70 / 255)
        case .purple:
            return Color(red: 147 / 255, green: 103 / 255, blue: 255 / 255)
        }
    }

    var title: String {
        switch self {
        case .blue:
            return "蓝"
        case .black:
            return "黑"
        case .red:
            return "红"
        case .green:
            return "绿"
        case .yellow:
            return "黄"
        case .purple:
            return "紫"
        }
    }
}

struct NoteInkColorChoice: Hashable, Identifiable {
    let token: String

    var id: String { token }

    static func preset(_ preset: NoteInkColorPreset) -> String {
        preset.rawValue
    }

    static func custom(_ hex: String) -> String {
        "custom:\(hex.uppercased())"
    }

    var preset: NoteInkColorPreset? {
        NoteInkColorPreset(rawValue: token)
    }

    var customHex: String? {
        token.hasPrefix("custom:") ? String(token.dropFirst("custom:".count)) : nil
    }

    var color: Color {
        if let preset {
            return preset.color
        }
        if let customHex, let color = Color(hex: customHex) {
            return color
        }
        return NoteInkColorPreset.blue.color
    }

    var title: String {
        if let preset {
            return preset.title
        }
        return "自定义"
    }

    var isCustom: Bool {
        customHex != nil
    }
}

enum NoteEraserPreset: String, CaseIterable, Identifiable {
    case precise
    case broad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .precise:
            return "细擦"
        case .broad:
            return "宽擦"
        }

    }

    var icon: String {
        switch self {
        case .precise:
            return "minus"
        case .broad:
            return "equal"
        }
    }
}

enum NotePencilDoubleTapBehavior: String, CaseIterable, Identifiable {
    case switchToEraser
    case switchToLasso
    case togglePenHighlighter
    case ignore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .switchToEraser:
            return "切到橡皮"
        case .switchToLasso:
            return "切到套索"
        case .togglePenHighlighter:
            return "笔刷 / 荧光笔"
        case .ignore:
            return "不处理"
        }
    }
}

struct NoteInkToolState: Equatable {
    var kind: NoteInkToolKind = .pen
    var colorToken = NoteInkColorChoice.preset(.blue)
    var width: CGFloat = 4
    var eraserPreset: NoteEraserPreset = .precise
    var eraserWidth: CGFloat = 18
    var recentColorTokens: [String] = [
        NoteInkColorChoice.preset(.blue),
        NoteInkColorChoice.preset(.black),
        NoteInkColorChoice.preset(.red),
        NoteInkColorChoice.preset(.green),
        NoteInkColorChoice.preset(.yellow),
        NoteInkColorChoice.preset(.purple)
    ]

    var colorChoice: NoteInkColorChoice {
        NoteInkColorChoice(token: colorToken)
    }
}

enum WorkspaceEditorTool: String, Identifiable {
    case outline
    case quote
    case ink
    case text
    case source
    case card
    case save

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .outline:
            return "sidebar.left"
        case .quote:
            return "quote.bubble"
        case .ink:
            return "pencil.tip"
        case .text:
            return "character.textbox"
        case .source:
            return "doc.text.magnifyingglass"
        case .card:
            return "rectangle.stack.badge.plus"
        case .save:
            return "checkmark.circle"
        }
    }

    var title: String {
        switch self {
        case .outline:
            return "结构树"
        case .quote:
            return "引用"
        case .ink:
            return "手写"
        case .text:
            return "文本"
        case .source:
            return "原文"
        case .card:
            return "卡片"
        case .save:
            return "保存"
        }
    }
}

struct WorkspaceTopBar: View {
    @Binding var title: String
    @Binding var activeTool: WorkspaceEditorTool
    @Binding var inkToolState: NoteInkToolState
    @Binding var doubleTapBehavior: NotePencilDoubleTapBehavior

    let appearance: NoteWorkspaceAppearance
    let saveStatus: String
    let sourceHint: String
    let notebookContextLine: String
    let contextTabTitle: String
    let onBack: () -> Void
    let onSave: () -> Void
    let onOpenSource: () -> Void
    let onGenerateCard: () -> Void
    let onInsertQuote: () -> Void
    let onAddTextBlock: () -> Void
    let onAddInkBlock: () -> Void
    let onToggleOutline: () -> Void
    let onSelectAppearance: (NoteWorkspaceAppearance) -> Void

    @State private var showsCustomColorPanel = false
    @State private var isAdjustingWidth = false
    @State private var isAdjustingEraserWidth = false

    var body: some View {
        VStack(spacing: 6) {
            tabStrip
            toolStrip
            if activeTool == .ink {
                inkToolStrip
            }
            if activeTool == .ink,
               (inkToolState.kind == .pen || inkToolState.kind == .highlighter),
               showsCustomColorPanel {
                expandedColorPalette
            }
            if !notebookContextLine.isEmpty {
                contextLine
            }
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 12) {
            squareButton(icon: "house") {
                onBack()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    chromeTab(label: sourceTabLabel, style: .passive)
                    editableTab
                    chromeTab(label: contextTabTitle.nonEmpty ?? "结构整理", style: .active)
                }
                .padding(.trailing, 8)
            }

            squareButton(icon: "xmark") {
                onBack()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(appearance.primaryBarFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(appearance.barStrokeColor, lineWidth: 1)
                )
        )
    }

    private var toolStrip: some View {
        HStack(spacing: 10) {
            toolButton(.outline) {
                onToggleOutline()
            }

            Divider()
                .overlay(Color.white.opacity(0.14))
                .frame(height: 28)

            toolButton(.quote) {
                onInsertQuote()
            }

            toolButton(.ink) {
                onAddInkBlock()
            }

            toolButton(.text) {
                onAddTextBlock()
            }

            Divider()
                .overlay(Color.white.opacity(0.14))
                .frame(height: 28)

            toolButton(.source) {
                onOpenSource()
            }

            toolButton(.card) {
                onGenerateCard()
            }

            appearanceMenu

            Spacer(minLength: 12)

            Text(saveStatus)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(saveStatus == "已保存" ? appearance.successColor : appearance.warningColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(appearance.badgeFill)
                )

            toolButton(.save) {
                onSave()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(appearance.secondaryBarFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(appearance.barStrokeColor, lineWidth: 1)
                )
        )
    }

    private var contextLine: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(appearance.secondaryTextColor)

            Text(notebookContextLine)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(appearance.secondaryTextColor)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(appearance.contextFill)
        )
    }

    private var inkToolStrip: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(NoteInkToolKind.allCases) { kind in
                    Button {
                        selectTool(kind)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: kind.icon)
                            Text(kind.title)
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(appearance.primaryTextColor.opacity(0.94))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(inkToolState.kind == kind ? appearance.activeToolFill : appearance.iconButtonFill)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(inkToolState.kind == kind ? appearance.barStrokeColor : Color.clear, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .overlay(appearance.barStrokeColor)
                .frame(height: 26)

            if inkToolState.kind == .pen || inkToolState.kind == .highlighter {
                colorStrip

                Divider()
                    .overlay(appearance.barStrokeColor)
                    .frame(height: 26)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text("线宽")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(appearance.secondaryTextColor)
                        widthPreviewBubble
                    }
                    .padding(.leading, 2)

                    Slider(
                        value: widthBinding,
                        in: 2...14,
                        onEditingChanged: { editing in
                            isAdjustingWidth = editing
                        }
                    )
                    .tint(inkPreviewColor)
                    .frame(width: 220)
                }
            } else if inkToolState.kind == .eraser {
                eraserControls
            }

            Divider()
                .overlay(appearance.barStrokeColor)
                .frame(height: 26)

            doubleTapBehaviorMenu

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(appearance.secondaryBarFill.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(appearance.barStrokeColor, lineWidth: 1)
                )
        )
    }

    private var recentColorChoices: [NoteInkColorChoice] {
        let choices = inkToolState.recentColorTokens.map(NoteInkColorChoice.init(token:))
        return Array(choices.prefix(6))
    }

    private var inkPreviewColor: Color {
        inkToolState.kind == .highlighter
            ? inkToolState.colorChoice.color.opacity(0.45)
            : inkToolState.colorChoice.color
    }

    private var eraserPreviewColor: Color {
        appearance.primaryTextColor.opacity(0.94)
    }

    private func inkStrokePreviewHeight(for width: CGFloat) -> CGFloat {
        inkToolState.kind == .highlighter ? max(width * 1.45, 4) : width
    }

    private var widthBinding: Binding<Double> {
        Binding(
            get: { Double(inkToolState.width) },
            set: { newValue in
                inkToolState.width = CGFloat(newValue)
                if inkToolState.kind == .eraser || inkToolState.kind == .lasso {
                    inkToolState.kind = .pen
                }
            }
        )
    }

    private var eraserWidthBinding: Binding<Double> {
        Binding(
            get: { Double(inkToolState.eraserWidth) },
            set: { newValue in
                inkToolState.eraserWidth = CGFloat(newValue)
            }
        )
    }

    private var widthPreviewBubble: some View {
        HStack(spacing: 8) {
            Capsule(style: .continuous)
                .fill(inkPreviewColor)
                .frame(width: 36, height: inkStrokePreviewHeight(for: inkToolState.width))
            Text("\(Int(inkToolState.width.rounded())) pt")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(appearance.primaryTextColor.opacity(0.92))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(isAdjustingWidth ? appearance.activeToolFill : appearance.iconButtonFill)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(appearance.barStrokeColor, lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.16), value: inkToolState.width)
        .animation(.easeInOut(duration: 0.16), value: isAdjustingWidth)
    }

    private var eraserPreviewBubble: some View {
        HStack(spacing: 8) {
            Circle()
                .strokeBorder(eraserPreviewColor.opacity(0.85), lineWidth: 1.5)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.18))
                )
                .frame(
                    width: max(inkToolState.eraserWidth + 10, 20),
                    height: max(inkToolState.eraserWidth + 10, 20)
                )
            Text("\(Int(inkToolState.eraserWidth.rounded())) pt")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(appearance.primaryTextColor.opacity(0.92))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(isAdjustingEraserWidth ? appearance.activeToolFill : appearance.iconButtonFill)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(appearance.barStrokeColor, lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.16), value: inkToolState.eraserWidth)
        .animation(.easeInOut(duration: 0.16), value: isAdjustingEraserWidth)
    }

    private var colorStrip: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                ForEach(recentColorChoices) { choice in
                    colorSwatch(choice)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(appearance.iconButtonFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(appearance.barStrokeColor, lineWidth: 1)
                    )
            )

            HStack(spacing: 8) {
                ForEach(NoteInkColorPreset.allCases) { preset in
                    colorSwatch(NoteInkColorChoice(token: NoteInkColorChoice.preset(preset)), compact: true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(appearance.iconButtonFill.opacity(0.96))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(appearance.barStrokeColor, lineWidth: 1)
                    )
            )

            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                    showsCustomColorPanel.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(inkToolState.colorChoice.color)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.88), lineWidth: 1)
                        )
                    Text(showsCustomColorPanel ? "收起色盘" : "更多颜色")
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(appearance.primaryTextColor.opacity(0.94))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(showsCustomColorPanel ? appearance.activeToolFill : appearance.iconButtonFill)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(appearance.barStrokeColor, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var expandedColorPalette: some View {
        VStack(alignment: .leading, spacing: 12) {
            paletteRow(title: "最近颜色", choices: recentColorChoices)
            paletteRow(title: "扩展色盘", choices: expandedPaletteChoices)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(appearance.secondaryBarFill.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(appearance.barStrokeColor, lineWidth: 1)
                )
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var expandedPaletteChoices: [NoteInkColorChoice] {
        let extraTokens = [
            NoteInkColorChoice.custom("F97316"),
            NoteInkColorChoice.custom("EC4899"),
            NoteInkColorChoice.custom("14B8A6"),
            NoteInkColorChoice.custom("0EA5E9"),
            NoteInkColorChoice.custom("A855F7"),
            NoteInkColorChoice.custom("84CC16"),
            NoteInkColorChoice.custom("F59E0B"),
            NoteInkColorChoice.custom("DC2626"),
            NoteInkColorChoice.custom("7C3AED"),
            NoteInkColorChoice.custom("2563EB"),
            NoteInkColorChoice.custom("059669"),
            NoteInkColorChoice.custom("0891B2"),
            NoteInkColorChoice.custom("6B7280"),
            NoteInkColorChoice.custom("9A3412"),
            NoteInkColorChoice.custom("BE185D"),
            NoteInkColorChoice.custom("4338CA"),
            NoteInkColorChoice.custom("0F766E")
        ]
        let merged = recentColorChoices.map(\.token) + NoteInkColorPreset.allCases.map { NoteInkColorChoice.preset($0) } + extraTokens
        var seen = Set<String>()
        return merged.compactMap { token in
            guard seen.insert(token).inserted else { return nil }
            return NoteInkColorChoice(token: token)
        }
    }

    private func paletteRow(title: String, choices: [NoteInkColorChoice]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(appearance.secondaryTextColor)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(choices) { choice in
                        colorSwatch(choice)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var eraserControls: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(NoteEraserPreset.allCases) { preset in
                    Button {
                        inkToolState.eraserPreset = preset
                        inkToolState.eraserWidth = preset == .precise ? 16 : 28
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: preset.icon)
                            Text(preset.title)
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(appearance.primaryTextColor.opacity(0.94))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(inkToolState.eraserPreset == preset ? appearance.activeToolFill : appearance.iconButtonFill)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(inkToolState.eraserPreset == preset ? appearance.barStrokeColor : Color.clear, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .overlay(appearance.barStrokeColor)
                .frame(height: 26)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("橡皮大小")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(appearance.secondaryTextColor)
                    eraserPreviewBubble
                }
                .padding(.leading, 2)

                Slider(
                    value: eraserWidthBinding,
                    in: 8...42,
                    onEditingChanged: { editing in
                        isAdjustingEraserWidth = editing
                    }
                )
                .tint(eraserPreviewColor)
                .frame(width: 220)
            }
        }
    }

    private func colorSwatch(_ choice: NoteInkColorChoice, compact: Bool = false) -> some View {
        Button {
            selectColorToken(choice.token)
        } label: {
            Circle()
                .fill(choice.color)
                .frame(width: compact ? 18 : 24, height: compact ? 18 : 24)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.94), lineWidth: inkToolState.colorToken == choice.token ? 3 : 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: compact ? 3 : 6, y: 2)
        }
        .buttonStyle(.plain)
        .help("颜色 · \(choice.title)")
    }

    private var doubleTapBehaviorMenu: some View {
        Menu {
            ForEach(NotePencilDoubleTapBehavior.allCases) { behavior in
                Button {
                    doubleTapBehavior = behavior
                } label: {
                    Text(behavior.title)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "applepencil.tip")
                Text("双击：\(doubleTapBehavior.title)")
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(appearance.primaryTextColor.opacity(0.94))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(appearance.iconButtonFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(appearance.barStrokeColor, lineWidth: 1)
                    )
            )
        }
        .menuStyle(.button)
    }

    private func selectTool(_ kind: NoteInkToolKind) {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
            inkToolState.kind = kind
        }
        if kind == .eraser {
            showsCustomColorPanel = false
        }
    }

    private func selectColorToken(_ token: String) {
        inkToolState.colorToken = token
        if inkToolState.kind == .eraser || inkToolState.kind == .lasso {
            inkToolState.kind = .pen
        }
        inkToolState.recentColorTokens = [token] + inkToolState.recentColorTokens.filter { $0 != token }
        inkToolState.recentColorTokens = Array(inkToolState.recentColorTokens.prefix(6))
    }

    private var editableTab: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(appearance.primaryTextColor)

            TextField("未命名笔记", text: $title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(appearance.primaryTextColor)
                .textInputAutocapitalization(.never)
                .frame(minWidth: 220, maxWidth: 320)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(appearance.activeTabFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(appearance.barStrokeColor, lineWidth: 1)
                )
        )
    }

    private func chromeTab(label: String, style: WorkspaceTabStyle) -> some View {
        Text(label)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(appearance.primaryTextColor.opacity(style == .active ? 0.98 : 0.82))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(style.backgroundColor(for: appearance))
            )
    }

    private func toolButton(_ tool: WorkspaceEditorTool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                activeTool = tool
            }
            action()
        } label: {
            Image(systemName: tool.icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(appearance.primaryTextColor.opacity(0.96))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(activeTool == tool ? appearance.activeToolFill : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(activeTool == tool ? appearance.barStrokeColor : Color.clear, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(tool.title)
    }

    private func squareButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(appearance.primaryTextColor.opacity(0.92))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(appearance.iconButtonFill)
                )
        }
        .buttonStyle(.plain)
    }

    private var appearanceMenu: some View {
        Menu {
            ForEach(NoteWorkspaceAppearance.allCases) { mode in
                Button {
                    onSelectAppearance(mode)
                } label: {
                    Label(mode.title, systemImage: mode.icon)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: appearance.icon)
                Text(appearance.title)
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(appearance.primaryTextColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(appearance.iconButtonFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(appearance.barStrokeColor, lineWidth: 1)
                    )
            )
        }
        .menuStyle(.button)
    }

    private var sourceTabLabel: String {
        sourceHint.nonEmpty ?? "当前资料"
    }
}

private enum WorkspaceTabStyle {
    case passive
    case active

    func backgroundColor(for appearance: NoteWorkspaceAppearance) -> Color {
        switch self {
        case .passive:
            return appearance.passiveTabFill
        case .active:
            return appearance.activeTabFill
        }
    }
}

private extension NoteWorkspaceAppearance {
    var primaryBarFill: Color {
        switch self {
        case .paper:
            return Color(red: 58 / 255, green: 103 / 255, blue: 178 / 255).opacity(0.96)
        case .night:
            return Color(red: 35 / 255, green: 43 / 255, blue: 64 / 255).opacity(0.96)
        case .eyeCare:
            return Color(red: 96 / 255, green: 128 / 255, blue: 102 / 255).opacity(0.96)
        }
    }

    var secondaryBarFill: Color {
        switch self {
        case .paper:
            return Color(red: 73 / 255, green: 122 / 255, blue: 201 / 255).opacity(0.96)
        case .night:
            return Color(red: 45 / 255, green: 54 / 255, blue: 78 / 255).opacity(0.96)
        case .eyeCare:
            return Color(red: 112 / 255, green: 144 / 255, blue: 109 / 255).opacity(0.96)
        }
    }

    var passiveTabFill: Color {
        switch self {
        case .paper:
            return Color(red: 90 / 255, green: 135 / 255, blue: 204 / 255).opacity(0.92)
        case .night:
            return Color.white.opacity(0.08)
        case .eyeCare:
            return Color(red: 154 / 255, green: 182 / 255, blue: 148 / 255).opacity(0.62)
        }
    }

    var activeTabFill: Color {
        switch self {
        case .paper:
            return Color(red: 111 / 255, green: 154 / 255, blue: 220 / 255).opacity(0.96)
        case .night:
            return Color(red: 91 / 255, green: 121 / 255, blue: 193 / 255).opacity(0.72)
        case .eyeCare:
            return Color(red: 181 / 255, green: 205 / 255, blue: 171 / 255).opacity(0.86)
        }
    }

    var barStrokeColor: Color {
        isDark ? Color.white.opacity(0.14) : Color.white.opacity(0.18)
    }

    var primaryTextColor: Color {
        isDark ? Color.white : Color.white
    }

    var secondaryTextColor: Color {
        isDark ? Color.white.opacity(0.78) : Color.white.opacity(0.82)
    }

    var badgeFill: Color {
        isDark ? Color.white.opacity(0.10) : Color.white.opacity(0.16)
    }

    var iconButtonFill: Color {
        isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.14)
    }

    var activeToolFill: Color {
        isDark ? Color.white.opacity(0.16) : Color.white.opacity(0.22)
    }

    var successColor: Color {
        isDark ? Color.green.opacity(0.95) : Color.green.opacity(0.92)
    }

    var warningColor: Color {
        isDark ? Color.orange.opacity(0.96) : Color.orange.opacity(0.96)
    }

    var contextFill: Color {
        isDark ? Color.white.opacity(0.07) : Color.white.opacity(0.14)
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct WorkspaceTopBar_Previews: PreviewProvider {
    static var previews: some View {
        WorkspaceTopBarPreview()
    }
}

private struct WorkspaceTopBarPreview: View {
    @State private var title = "线性代数"
    @State private var activeTool: WorkspaceEditorTool = .ink

    var body: some View {
        WorkspaceTopBar(
            title: $title,
            activeTool: $activeTool,
            inkToolState: .constant(NoteInkToolState()),
            doubleTapBehavior: .constant(.switchToEraser),
            appearance: .paper,
            saveStatus: "已保存",
            sourceHint: "26武忠祥《高等数学辅导讲义》",
            notebookContextLine: "第43页 · 第2句 · 隐形基础设施的双重维度",
            contextTabTitle: "高等数学",
            onBack: {},
            onSave: {},
            onOpenSource: {},
            onGenerateCard: {},
            onInsertQuote: {},
            onAddTextBlock: {},
            onAddInkBlock: {},
            onToggleOutline: {},
            onSelectAppearance: { _ in }
        )
        .padding()
        .background(Color(red: 14 / 255, green: 31 / 255, blue: 58 / 255))
    }
}

private extension Color {
    init?(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard sanitized.count == 6 || sanitized.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: sanitized).scanHexInt64(&value) else { return nil }

        let hasAlpha = sanitized.count == 8
        let red = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? Double(value & 0xFF) / 255 : 1

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var hexString: String? {
        UIColor(self).hexString
    }
}

private extension UIColor {
    var hexString: String? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }

        return String(
            format: "%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }
}
