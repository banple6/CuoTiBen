import SwiftUI

struct BottomGlassTabBar: View {
    @Binding var selectedTab: MainTab

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var compactMaxWidth: CGFloat {
        isPad ? 620 : 382
    }

    private var containerPadding: EdgeInsets {
        EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
    }

    var body: some View {
        HStack(spacing: isPad ? 14 : 6) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .frame(maxWidth: compactMaxWidth)
        .padding(containerPadding)
        .background(TabBarContainerBackground())
    }

    private func tabButton(for tab: MainTab) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                selectedTab = tab
            }
        } label: {
            BottomGlassTabItem(
                tab: tab,
                isSelected: selectedTab == tab
            )
        }
        .buttonStyle(.plain)
    }
}

private struct BottomGlassTabItem: View {
    let tab: MainTab
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: tab.icon)
                .font(.system(size: 18, weight: isSelected ? .bold : .medium))
                .foregroundStyle(iconColor)
            Text(tab.title)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .foregroundStyle(titleColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(activeBackground)
    }

    private var iconColor: Color {
        isSelected ? AppPalette.paperInk : AppPalette.paperMuted
    }

    private var titleColor: Color {
        isSelected ? AppPalette.paperInk : AppPalette.paperMuted
    }

    @ViewBuilder
    private var activeBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.82), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)
        }
    }
}

private struct TabBarContainerBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(AppPalette.paperCard.opacity(0.96))
            .overlay {
                NotebookGrid(spacing: 14)
                    .opacity(0.12)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.95), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 16, y: 8)
    }
}
