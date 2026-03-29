import SwiftUI

enum MainTab: String, CaseIterable {
    case home
    case library
    case notes
    case review

    var title: String {
        switch self {
        case .home: return "首页"
        case .library: return "知识库"
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

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .home:
                    HomeView()
                case .library:
                    LibraryView()
                case .notes:
                    NotesHomeView(onOpenSource: nil, showsCloseButton: false)
                case .review:
                    ReviewListView()
                }
            }
            .environmentObject(viewModel)

            BottomGlassTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 18)
                .padding(.bottom, 4)
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
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
