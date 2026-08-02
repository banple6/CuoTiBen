import SwiftUI

enum MainTab: String, CaseIterable {
    case home
    case library
    case notes
    case review

    var title: String {
        switch self {
        case .home: return "首页"
        case .library: return "资料库"
        case .notes: return "笔记"
        case .review: return "复习"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .library: return "books.vertical.fill"
        case .notes: return "note.text"
        case .review: return "checklist"
        }
    }

    var usesLightChrome: Bool {
        self == .library || self == .notes
    }
}

extension Notification.Name {
    static let switchToReviewTab = Notification.Name("CuoTiBen.switchToReviewTab")
    static let switchToLibraryTab = Notification.Name("CuoTiBen.switchToLibraryTab")
}

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @State private var selectedTab: MainTab = .home
    @State private var showsSettings = false

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        Group {
            if isPad {
                HStack(spacing: 0) {
                    RootWorkspaceSidebar(
                        selectedTab: $selectedTab,
                        onOpenSettings: { showsSettings = true }
                    )

                    currentTabView
                        .environmentObject(viewModel)
                }
                .background(AppPalette.paperBackground.ignoresSafeArea())
            } else {
                ZStack(alignment: .bottom) {
                    currentTabView
                        .environmentObject(viewModel)
                        .padding(.bottom, 48)

                    BottomWorkspaceTabBar(selectedTab: $selectedTab)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToReviewTab)) { _ in
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                selectedTab = .review
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToLibraryTab)) { _ in
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                selectedTab = .library
            }
        }
        .sheet(isPresented: $showsSettings) {
            AppSettingsSheet()
                .environmentObject(viewModel)
        }
    }

    @ViewBuilder
    private var currentTabView: some View {
        switch selectedTab {
        case .home:
            HomeView(showsEmbeddedSidebar: !isPad)
        case .library:
            LibraryView(showsEmbeddedSidebar: !isPad)
        case .notes:
            NotesHomeView(onOpenSource: nil, showsCloseButton: false)
        case .review:
            ReviewListView()
        }
    }
}

private struct RootWorkspaceSidebar: View {
    @Binding var selectedTab: MainTab
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Digital Archivist")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(AppPalette.paperInk)

                Text("资料工作台")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.paperMuted)
            }
            .padding(.horizontal, 18)
            .padding(.top, 28)

            VStack(spacing: 8) {
                ForEach(MainTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            selectedTab = tab
                        }
                    } label: {
                        sidebarRow(icon: tab.icon, title: tab.title, selected: selectedTab == tab)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 20)

            Button(action: onOpenSettings) {
                sidebarRow(icon: "gearshape.fill", title: "设置", selected: false)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.bottom, 24)
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            AppPalette.paperBackgroundDeep
                .opacity(0.96)
                .ignoresSafeArea(edges: .vertical)
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppPalette.paperLine.opacity(0.55))
                .frame(width: 1)
                .ignoresSafeArea(edges: .vertical)
        }
    }

    private func sidebarRow(icon: String, title: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 22)

            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .serif))

            Spacer(minLength: 0)
        }
        .foregroundStyle(selected ? AppPalette.primary : AppPalette.paperInk.opacity(0.74))
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? AppPalette.primary.opacity(0.14) : Color.clear)
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
