import SwiftUI

struct BottomGlassTabBar: View {
    @Binding var selectedTab: MainTab

    private var isLight: Bool {
        selectedTab.usesLightChrome
    }

    private var compactMaxWidth: CGFloat {
        AppPerformance.prefersReducedEffects ? 340 : 362
    }

    private var containerPadding: EdgeInsets {
        EdgeInsets(top: 5, leading: 8, bottom: 7, trailing: 8)
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .frame(maxWidth: compactMaxWidth)
        .padding(containerPadding)
        .background(TabBarContainerBackground(isLight: isLight))
    }

    private func tabGlow(for tab: MainTab) -> LinearGradient {
        switch tab {
        case .home:
            return LinearGradient(colors: [AppPalette.mint.opacity(0.85), AppPalette.cyan.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .library:
            return LinearGradient(colors: [Color.blue.opacity(0.6), Color.cyan.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .notes:
            return LinearGradient(colors: [AppPalette.amber.opacity(0.75), AppPalette.primary.opacity(0.34)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .review:
            return LinearGradient(colors: [AppPalette.primary.opacity(0.85), AppPalette.cyan.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func tabButton(for tab: MainTab) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                selectedTab = tab
            }
        } label: {
            BottomGlassTabItem(
                tab: tab,
                isSelected: selectedTab == tab,
                isLight: isLight,
                glow: tabGlow(for: tab)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct BottomGlassTabItem: View {
    let tab: MainTab
    let isSelected: Bool
    let isLight: Bool
    let glow: LinearGradient

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(glow)
                        .frame(width: 38, height: 24)
                        .blur(radius: AppPerformance.prefersReducedEffects ? 5 : 8)
                }

                Image(systemName: tab.icon)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .frame(height: 24)

            Text(tab.title)
                .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(titleColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
        .background(activeBackground)
    }

    private var iconColor: Color {
        isSelected ? selectedForeground : defaultForeground
    }

    private var titleColor: Color {
        isSelected ? selectedForeground : defaultForeground.opacity(0.78)
    }

    private var selectedForeground: Color {
        isLight ? Color.blue : AppPalette.softText
    }

    private var defaultForeground: Color {
        isLight ? Color.black.opacity(0.55) : AppPalette.softMutedText
    }

    @ViewBuilder
    private var activeBackground: some View {
        if isSelected {
            Capsule(style: .continuous)
                .fill(isLight ? Color.white.opacity(0.82) : Color.white.opacity(0.08))
                .overlay(alignment: .top) {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isLight ? 0.84 : 0.24), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 12)
                }
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isLight ? Color.white.opacity(0.9) : Color.white.opacity(0.13), lineWidth: 0.9)
                )
                .shadow(color: isLight ? Color.blue.opacity(0.06) : AppPalette.cyan.opacity(0.1), radius: AppPerformance.prefersReducedEffects ? 5 : 9, y: AppPerformance.prefersReducedEffects ? 2 : 4)
        }
    }
}

private struct TabBarContainerBackground: View {
    let isLight: Bool

    private var usesEnhancedLiquidGlass: Bool {
        if #available(iOS 17.0, *) {
            return !AppPerformance.prefersReducedEffects
        }
        return false
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(baseFill)
            .overlay {
                if !AppPerformance.prefersReducedEffects {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(materialStyle)
                }
            }
            .overlay {
                if usesEnhancedLiquidGlass {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isLight ? 0.18 : 0.08),
                                    Color.white.opacity(0.02),
                                    Color.cyan.opacity(isLight ? 0.06 : 0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(topHighlight)
                    .frame(height: 14)
            }
            .overlay(alignment: .topLeading) {
                if usesEnhancedLiquidGlass {
                    Circle()
                        .fill(Color.white.opacity(isLight ? 0.52 : 0.13))
                        .frame(width: 96, height: 36)
                        .blur(radius: 12)
                        .offset(x: 22, y: -8)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if usesEnhancedLiquidGlass {
                    Circle()
                        .fill(AppPalette.cyan.opacity(isLight ? 0.12 : 0.16))
                        .frame(width: 74, height: 28)
                        .blur(radius: 16)
                        .offset(x: 12, y: 10)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(borderColor, lineWidth: 0.9)
            )
            .shadow(color: shadowColor, radius: AppPerformance.prefersReducedEffects ? 6 : 10, y: AppPerformance.prefersReducedEffects ? 2 : 4)
    }

    private var baseFill: Color {
        isLight ? Color.white.opacity(0.44) : Color.white.opacity(0.07)
    }

    private var materialStyle: AnyShapeStyle {
        isLight ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.thinMaterial)
    }

    private var topHighlight: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(isLight ? 0.6 : 0.16), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var borderColor: Color {
        isLight ? Color.white.opacity(0.72) : Color.white.opacity(0.16)
    }

    private var shadowColor: Color {
        isLight ? Color.black.opacity(0.05) : AppPalette.primary.opacity(0.09)
    }
}
