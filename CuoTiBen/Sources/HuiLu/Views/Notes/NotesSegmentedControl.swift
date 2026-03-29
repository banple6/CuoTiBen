import SwiftUI

enum NotesHomeTab: String, CaseIterable, Identifiable {
    case recent
    case source
    case concept

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent:
            return "最近"
        case .source:
            return "资料"
        case .concept:
            return "知识点"
        }
    }
}

struct NotesSegmentedControl: View {
    @Binding var selectedTab: NotesHomeTab

    var body: some View {
        HStack(spacing: 10) {
            ForEach(NotesHomeTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(selectedTab == tab ? Color.white : Color.black.opacity(0.62))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(selectedTab == tab ? Color.blue.opacity(0.82) : Color.white.opacity(0.72))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.88), lineWidth: 1)
                )
        )
    }
}
