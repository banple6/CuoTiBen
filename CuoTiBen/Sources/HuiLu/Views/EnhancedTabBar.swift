import SwiftUI

// MARK: - Enhanced Tab Bar

struct EnhancedTabBar: View {
    @Binding var selectedTab: MainTab
    
    private let isLight: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                EnhancedTabBarItem(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    isLight: isLight
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        selectedTab = tab
                    }
                }
            }
        }
        .padding(10)
        .background(
            ZStack {
                // Glass background
                EnhancedGlassBackground(isLight: isLight)
                
                // Animated shine effect
                if !AppPerformance.prefersReducedEffects {
                    AnimatedShine()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(EnhancedPalette.glassBorder, lineWidth: 1.2)
            )
            .shadow(color: EnhancedPalette.electricBlue.opacity(0.15), radius: 16, y: 8)
            .shadow(color: Color.black.opacity(0.2), radius: 20, y: 12)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

struct EnhancedTabBarItem: View {
    let tab: MainTab
    let isSelected: Bool
    let isLight: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                    isPressed = false
                }
            }
            action()
        }) {
            VStack(spacing: 6) {
                // Icon with gradient
                ZStack {
                    Image(systemName: tab.icon)
                        .font(.system(size: 22, weight: isSelected ? .bold : .semibold))
                    
                    // Glow effect behind icon
                    if isSelected {
                        Circle()
                            .fill(tab.accentColor.opacity(0.2))
                            .frame(width: 44, height: 44)
                            .blur(radius: 12)
                            .offset(y: 2)
                    }
                }
                .foregroundStyle(
                    isSelected ? tab.gradient : (isLight ? EnhancedPalette.primaryTextLight.opacity(0.5) : EnhancedPalette.primaryTextDark.opacity(0.5))
                )
                .scaleEffect(isPressed ? 0.9 : 1)
                
                // Label
                Text(tab.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(
                        isSelected ? 
                            (isLight ? EnhancedPalette.primaryTextLight : EnhancedPalette.primaryTextDark) :
                            (isLight ? EnhancedPalette.primaryTextLight.opacity(0.5) : EnhancedPalette.primaryTextDark.opacity(0.5))
                    )
            }
            .frame(width: 72, height: 62)
            .background(
                ZStack {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(selectedBackground)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(EnhancedPalette.glassBorder.opacity(0.6), lineWidth: 1)
                            )
                    }
                }
                .clipShape(Capsule(style: .continuous))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isSelected ? EnhancedPalette.glassBorder.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
    
    private var selectedBackground: some View {
        LinearGradient(
            colors: [
                tab.accentColor.opacity(0.2),
                tab.accentColor.opacity(0.05)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Enhanced Glass Background

struct EnhancedGlassBackground: View {
    let isLight: Bool
    
    var body: some View {
        ZStack {
            // Base material
            if isLight {
                Color.white.opacity(0.65)
                    .background(.regularMaterial)
            } else {
                Color.black.opacity(0.65)
                    .background(.regularMaterial)
            }
            
            // Gradient overlay
            LinearGradient(
                colors: [
                    Color.white.opacity(isLight ? 0.2 : 0.1),
                    Color.white.opacity(0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Subtle color wash
            if !isLight {
                LinearGradient(
                    colors: [
                        EnhancedPalette.electricBlue.opacity(0.08),
                        EnhancedPalette.cyanGlow.opacity(0.05),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

// MARK: - Animated Shine Effect

struct AnimatedShine: View {
    @State private var animate = false
    
    var body: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0),
                Color.white.opacity(0.15),
                Color.white.opacity(0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .offset(x: animate ? 400 : -400)
        .animation(.easeInOut(duration: 3).repeatForever(autoreverses: false), value: animate)
        .onAppear {
            animate = true
        }
    }
}

// MARK: - MainTab Extension

extension MainTab {
    var gradient: LinearGradient {
        switch self {
        case .home:
            return LinearGradient(
                colors: [EnhancedPalette.electricBlue, EnhancedPalette.cyanGlow],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .library:
            return LinearGradient(
                colors: [EnhancedPalette.auroraGreen, EnhancedPalette.cyanGlow],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .notes:
            return LinearGradient(
                colors: [EnhancedPalette.magentaDream, EnhancedPalette.sunsetOrange],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .review:
            return LinearGradient(
                colors: [EnhancedPalette.sunsetOrange, EnhancedPalette.magentaDream],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
    
    var accentColor: Color {
        switch self {
        case .home:
            return EnhancedPalette.electricBlue
        case .library:
            return EnhancedPalette.auroraGreen
        case .notes:
            return EnhancedPalette.magentaDream
        case .review:
            return EnhancedPalette.sunsetOrange
        }
    }
}

// MARK: - Alternative: Vertical Sidebar for iPad

struct EnhancedSidebar: View {
    @Binding var selectedTab: MainTab
    var isCollapsed: Bool = false
    
    var body: some View {
        VStack(spacing: 8) {
            // App logo/icon
            if !isCollapsed {
                VStack(spacing: 4) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [EnhancedPalette.electricBlue, EnhancedPalette.cyanGlow],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text("错题本")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(EnhancedPalette.secondaryTextDark)
                }
                .frame(width: 72)
                .padding(.vertical, 16)
                
                Divider()
                    .background(EnhancedPalette.glassBorder)
            }
            
            // Tab items
            ForEach(MainTab.allCases, id: \.self) { tab in
                EnhancedSidebarItem(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    isCollapsed: isCollapsed
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selectedTab = tab
                    }
                }
            }
            
            Spacer()
            
            // Settings at bottom
            if !isCollapsed {
                Divider()
                    .background(EnhancedPalette.glassBorder)
                
                EnhancedSidebarItem(
                    tab: .settings,
                    isSelected: false,
                    isCollapsed: isCollapsed
                ) {}
            }
        }
        .padding(.vertical, 16)
        .background(
            EnhancedGlassBackground(isLight: true)
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(EnhancedPalette.glassBorder.opacity(0.5), lineWidth: 1)
                )
        )
    }
}

struct EnhancedSidebarItem: View {
    let tab: MainTab
    let isSelected: Bool
    let isCollapsed: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? tab.gradient : EnhancedPalette.primaryTextLight.opacity(0.5))
                
                if !isCollapsed {
                    Text(tab.title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? EnhancedPalette.primaryTextLight : EnhancedPalette.secondaryTextLight)
                }
            }
            .frame(width: isCollapsed ? 56 : nil, height: 48)
            .padding(.horizontal, isCollapsed ? 0 : 16)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(tab.accentColor.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(tab.accentColor.opacity(0.3), lineWidth: 1.2)
                            )
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

// Add settings tab for sidebar
extension MainTab {
    static var settings: MainTab {
        .home // Placeholder - would need actual settings tab
    }
}
