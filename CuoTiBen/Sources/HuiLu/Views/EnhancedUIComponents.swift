import SwiftUI

// MARK: - Enhanced Color System

enum EnhancedPalette {
    // Deep space gradients
    static let midnightNavy = Color(red: 0.05, green: 0.07, blue: 0.12)
    static let cosmicBlue = Color(red: 0.08, green: 0.15, blue: 0.35)
    static let nebulaPurple = Color(red: 0.25, green: 0.18, blue: 0.45)
    
    // Light airy gradients
    static let morningSky = Color(red: 0.95, green: 0.97, blue: 0.99)
    static let cloudWhite = Color(red: 0.98, green: 0.99, blue: 1.0)
    static let softDawn = Color(red: 0.92, green: 0.95, blue: 0.98)
    
    // Accent colors - more vibrant and modern
    static let electricBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
    static let auroraGreen = Color(red: 0.2, green: 0.85, blue: 0.65)
    static let sunsetOrange = Color(red: 1.0, green: 0.55, blue: 0.2)
    static let magentaDream = Color(red: 0.95, green: 0.3, blue: 0.7)
    static let cyanGlow = Color(red: 0.0, green: 0.85, blue: 0.95)
    
    // Text colors with better contrast
    static let primaryTextDark = Color.white.opacity(0.95)
    static let secondaryTextDark = Color.white.opacity(0.75)
    static let tertiaryTextDark = Color.white.opacity(0.55)
    
    static let primaryTextLight = Color.black.opacity(0.85)
    static let secondaryTextLight = Color.black.opacity(0.6)
    static let tertiaryTextLight = Color.black.opacity(0.4)
    
    // Surface tones
    static let glassDark = Color.white.opacity(0.08)
    static let glassLight = Color.white.opacity(0.72)
    static let glassBorder = Color.white.opacity(0.25)
}

// MARK: - Enhanced Gradients

struct EnhancedGradients {
    static func deepSpace(angle: Angle = .degrees(135)) -> LinearGradient {
        LinearGradient(
            colors: [EnhancedPalette.midnightNavy, EnhancedPalette.cosmicBlue, EnhancedPalette.nebulaPurple],
            startPoint: UnitPoint(angle: angle),
            endPoint: UnitPoint(angle: angle + .degrees(180))
        )
    }
    
    static func morningLight(angle: Angle = .degrees(135)) -> LinearGradient {
        LinearGradient(
            colors: [EnhancedPalette.morningSky, EnhancedPalette.cloudWhite, EnhancedPalette.softDawn],
            startPoint: UnitPoint(angle: angle),
            endPoint: UnitPoint(angle: angle + .degrees(180))
        )
    }
    
    static func accentFlow(colors: [Color]) -> LinearGradient {
        LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Animated Background Effects

struct AuroraBackground: View {
    enum Mode {
        case dark
        case light
    }
    
    let mode: Mode
    @State private var offset1 = CGSize.zero
    @State private var offset2 = CGSize.zero
    @State private var offset3 = CGSize.zero
    
    var body: some View {
        ZStack {
            if mode == .dark {
                EnhancedGradients.deepSpace()
            } else {
                EnhancedGradients.morningLight()
            }
            
            // Animated glow orbs
            AuroraOrb(color: mode == .dark ? EnhancedPalette.cyanGlow : EnhancedPalette.electricBlue,
                     size: 280, offset: $offset1)
                .offset(x: -150, y: -200)
            
            AuroraOrb(color: mode == .dark ? EnhancedPalette.auroraGreen : EnhancedPalette.magentaDream,
                     size: 220, offset: $offset2)
                .offset(x: 180, y: -80)
            
            AuroraOrb(color: mode == .dark ? EnhancedPalette.magentaDream : EnhancedPalette.auroraGreen,
                     size: 260, offset: $offset3)
                .offset(x: 80, y: 250)
        }
        .onAppear {
            startAnimations()
        }
        .ignoresSafeArea()
    }
    
    private func startAnimations() {
        withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
            offset1 = CGSize(width: 40, height: 30)
        }
        withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true).delay(0.5)) {
            offset2 = CGSize(width: -50, height: 40)
        }
        withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true).delay(1)) {
            offset3 = CGSize(width: 30, height: -50)
        }
    }
}

struct AuroraOrb: View {
    let color: Color
    let size: CGFloat
    @Binding var offset: CGSize
    
    var body: some View {
        Circle()
            .fill(color.opacity(0.15))
            .frame(width: size, height: size)
            .blur(radius: 60)
            .offset(offset)
    }
}

// MARK: - Premium Glass Panel

struct PremiumGlassPanel<Content: View>: View {
    enum Tone {
        case dark
        case light
        case ultraLight
    }
    
    let tone: Tone
    var cornerRadius: CGFloat = 32
    var borderWidth: CGFloat = 1.2
    var padding: CGFloat = 24
    var shadowRadius: CGFloat = 20
    var shadowY: CGFloat = 8
    @ViewBuilder var content: () -> Content
    
    @State private var isHovering = false
    
    var body: some View {
        content()
            .padding(padding)
            .background(
                ZStack {
                    // Base glass
                    glassBackground
                    
                    // Shimmer effect on hover
                    if #available(iOS 17.0, *) {
                        shimmerOverlay
                            .opacity(isHovering ? 0.3 : 0)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(borderGradient, lineWidth: borderWidth)
                )
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
                .shadow(color: ambientShadowColor, radius: shadowRadius * 0.5, y: shadowY * 0.5)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.3)) {
                    isHovering = hovering
                }
            }
    }
    
    private var glassBackground: some View {
        Group {
            switch tone {
            case .dark:
                EnhancedPalette.glassDark
            case .light:
                EnhancedPalette.glassLight
            case .ultraLight:
                Color.white.opacity(0.85)
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(tone == .dark ? 0.12 : 0.92),
                    Color.white.opacity(tone == .dark ? 0.04 : 0.65)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .background(.ultraThinMaterial, shouldRasterize: true)
    }
    
    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                EnhancedPalette.glassBorder,
                EnhancedPalette.glassBorder.opacity(0.3),
                EnhancedPalette.glassBorder
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var shimmerOverlay: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0),
                Color.white.opacity(0.2),
                Color.white.opacity(0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .mask(
            Rectangle()
                .blur(radius: 20)
        )
    }
    
    private var shadowColor: Color {
        switch tone {
        case .dark:
            return EnhancedPalette.cyanGlow.opacity(0.15)
        case .light, .ultraLight:
            return Color.black.opacity(0.08)
        }
    }
    
    private var ambientShadowColor: Color {
        switch tone {
        case .dark:
            return EnhancedPalette.electricBlue.opacity(0.08)
        case .light, .ultraLight:
            return Color.black.opacity(0.05)
        }
    }
}

// MARK: - Elegant Buttons

struct ElegantButton: View {
    enum Style {
        case primary
        case secondary
        case ghost
        case glass
    }
    
    enum Size {
        case small
        case medium
        case large
    }
    
    let title: String
    let icon: String?
    let style: Style
    let size: Size
    let action: () -> Void
    
    @State private var isPressed = false
    @State private var isHovering = false
    
    init(
        title: String,
        icon: String? = nil,
        style: Style = .primary,
        size: Size = .medium,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.size = size
        self.action = action
    }
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    isPressed = false
                }
            }
            action()
        }) {
            HStack(spacing: icon != nil ? 8 : 0) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: fontSize, weight: .semibold))
            }
            .frame(height: height)
            .padding(.horizontal, horizontalPadding)
            .background(buttonBackground, shouldRasterize: true)
            .foregroundColor(foregroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .scaleEffect(isPressed ? 0.96 : 1)
            .shadow(color: shadowColor, radius: isPressed ? 4 : 8, y: isPressed ? 2 : 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
    
    private var buttonBackground: some View {
        Group {
            switch style {
            case .primary:
                LinearGradient(
                    colors: [EnhancedPalette.electricBlue, EnhancedPalette.cyanGlow],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            case .secondary:
                EnhancedPalette.glassDark
            case .ghost:
                Color.clear
            case .glass:
                EnhancedPalette.glassLight
                    .background(.ultraThinMaterial)
            }
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary, .glass:
            return .white
        case .secondary:
            return EnhancedPalette.primaryTextDark
        case .ghost:
            return EnhancedPalette.electricBlue
        }
    }
    
    private var borderColor: Color {
        switch style {
        case .primary:
            return Color.clear
        case .secondary:
            return EnhancedPalette.glassBorder
        case .ghost:
            return Color.clear
        case .glass:
            return EnhancedPalette.glassBorder
        }
    }
    
    private var borderWidth: CGFloat {
        style == .secondary || style == .glass ? 1.2 : 0
    }
    
    private var shadowColor: Color {
        switch style {
        case .primary:
            return EnhancedPalette.electricBlue.opacity(isHovering ? 0.4 : 0.25)
        case .secondary:
            return EnhancedPalette.cyanGlow.opacity(0.15)
        case .ghost:
            return Color.clear
        case .glass:
            return Color.black.opacity(0.1)
        }
    }
    
    // Size calculations
    private var height: CGFloat {
        switch size {
        case .small: return 36
        case .medium: return 48
        case .large: return 56
        }
    }
    
    private var fontSize: CGFloat {
        switch size {
        case .small: return 14
        case .medium: return 16
        case .large: return 18
        }
    }
    
    private var iconSize: CGFloat {
        switch size {
        case .small: return 14
        case .medium: return 16
        case .large: return 18
        }
    }
    
    private var horizontalPadding: CGFloat {
        switch size {
        case .small: return 16
        case .medium: return 24
        case .large: return 32
        }
    }
    
    private var cornerRadius: CGFloat {
        switch size {
        case .small: return 14
        case .medium: return 18
        case .large: return 22
        }
    }
}

// MARK: - Floating Action Button

struct FloatingActionButton: View {
    let icon: String
    let backgroundColor: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    isPressed = false
                }
            }
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(
                    ZStack {
                        Circle().fill(backgroundColor)
                        Circle().fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                )
                .scaleEffect(isPressed ? 0.92 : 1)
                .shadow(color: backgroundColor.opacity(0.4), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Modern Cards

struct ModernCard<Content: View>: View {
    enum Style {
        case elevated
        case flat
        case highlighted
    }
    
    let style: Style
    var accentColor: Color = EnhancedPalette.electricBlue
    @ViewBuilder var content: () -> Content
    
    @State private var isHovering = false
    
    var body: some View {
        content()
            .padding(20)
            .background(
                Group {
                    switch style {
                    case .elevated:
                        CardBackground(accentColor: accentColor, isHovering: isHovering)
                    case .flat:
                        Color.white.opacity(0.5)
                            .background(.ultraThinMaterial)
                    case .highlighted:
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.15),
                                accentColor.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        style == .highlighted ? accentColor.opacity(0.4) : EnhancedPalette.glassBorder,
                        lineWidth: style == .highlighted ? 1.5 : 1
                    )
            )
            .shadow(
                color: style == .elevated ? accentColor.opacity(isHovering ? 0.2 : 0.1) : Color.clear,
                radius: isHovering && style == .elevated ? 16 : 12,
                y: isHovering && style == .elevated ? 8 : 6
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.25)) {
                    isHovering = hovering
                }
            }
    }
}

struct CardBackground: View {
    let accentColor: Color
    let isHovering: Bool
    
    var body: some View {
        ZStack {
            EnhancedPalette.glassLight
            
            LinearGradient(
                colors: [
                    Color.white.opacity(0.92),
                    Color.white.opacity(0.65)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Subtle gradient overlay
            LinearGradient(
                colors: [
                    accentColor.opacity(0.08),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .background(.ultraThinMaterial, shouldRasterize: true)
    }
}

// MARK: - Chip/Pill Components

struct ModernChip: View {
    let text: String
    let icon: String?
    var accentColor: Color = EnhancedPalette.electricBlue
    var size: CGFloat = 32
    
    var body: some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: size * 0.45, weight: .semibold))
            }
            Text(text)
                .font(.system(size: size * 0.42, weight: .semibold))
        }
        .foregroundColor(accentColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(accentColor.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(accentColor.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Section Headers

struct ElegantSectionHeader: View {
    let title: String
    let subtitle: String?
    let icon: String
    var accentColor: Color = EnhancedPalette.electricBlue
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accentColor, EnhancedPalette.cyanGlow],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(EnhancedPalette.primaryTextDark)
            }
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(EnhancedPalette.secondaryTextDark)
            }
        }
    }
}

// MARK: - Loading States

struct ElegantLoadingIndicator: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(EnhancedPalette.glassBorder, lineWidth: 3)
                .frame(width: 40, height: 40)
            
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    LinearGradient(
                        colors: [EnhancedPalette.electricBlue, EnhancedPalette.cyanGlow],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 3
                )
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Empty States

struct ElegantEmptyState: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 60, weight: .light))
                .foregroundColor(EnhancedPalette.tertiaryTextDark)
            
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(EnhancedPalette.primaryTextDark)
            
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(EnhancedPalette.secondaryTextDark)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            
            if let actionTitle = actionTitle, let action = action {
                ElegantButton(title: actionTitle, icon: "plus", style: .primary) {
                    action()
                }
            }
        }
        .padding(40)
    }
}
