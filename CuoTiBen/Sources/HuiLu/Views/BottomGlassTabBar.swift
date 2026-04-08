import SwiftUI

// ╔══════════════════════════════════════════════════════════════╗
// ║  BottomWorkspaceTabBar — Global root navigation              ║
// ║                                                              ║
// ║  Lightweight dock-style bar. Always visible, including       ║
// ║  inside the Notes workspace. Must never compete with the     ║
// ║  center notebook page or the workspace toolbar.              ║
// ║                                                              ║
// ║  Tabs: 首页 · 知识库 · 笔记 · 复习                            ║
// ╚══════════════════════════════════════════════════════════════╝

struct BottomWorkspaceTabBar: View {
    @Binding var selectedTab: MainTab

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        selectedTab = tab
                    }
                } label: {
                    tabLabel(tab)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: isPad ? 480 : .infinity)
        .frame(height: 44)
        .background(barBackground)
        .padding(.horizontal, isPad ? 0 : 8)
        .padding(.bottom, 2)
    }

    // MARK: - Tab Label

    private func tabLabel(_ tab: MainTab) -> some View {
        let active = selectedTab == tab
        return VStack(spacing: 2) {
            Image(systemName: tab.icon)
                .font(.system(size: 14, weight: active ? .semibold : .regular))
                .symbolVariant(active ? .fill : .none)
            Text(tab.title)
                .font(.system(size: 9, weight: active ? .bold : .medium))
        }
        .foregroundStyle(active ? DockTokens.accentActive : DockTokens.inactive)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
            active
                ? RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DockTokens.activeBg)
                : nil
        )
    }

    // MARK: - Bar Background

    private var barBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(DockTokens.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DockTokens.border, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
    }
}

// MARK: - Design Tokens (lightweight academic dock)

private enum DockTokens {
    static let surface      = Color(red: 248/255, green: 246/255, blue: 242/255).opacity(0.95)
    static let border       = Color(red: 200/255, green: 198/255, blue: 192/255).opacity(0.35)
    static let accentActive = Color(red: 0/255,   green: 80/255,  blue: 148/255)
    static let inactive     = Color(red: 140/255, green: 142/255, blue: 148/255).opacity(0.6)
    static let activeBg     = Color(red: 0/255,   green: 80/255,  blue: 148/255).opacity(0.06)
}

// MARK: - Legacy alias (keep old call-sites compiling)
typealias BottomGlassTabBar = BottomWorkspaceTabBar
