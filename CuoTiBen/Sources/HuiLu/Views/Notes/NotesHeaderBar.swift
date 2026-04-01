import SwiftUI

struct NotesHeaderBar: View {
    @Binding var searchText: String
    @Binding var activeFilter: NotesFilterMode

    let totalCount: Int
    let filteredCount: Int
    var showsCloseButton: Bool = true
    let onClose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("记忆剪贴簿")
                        .font(.system(size: 46, weight: .bold, design: .serif))
                        .italic()
                        .foregroundStyle(AppPalette.paperInk)
                        .minimumScaleFactor(0.82)

                    Text(summaryText)
                        .font(.system(size: 15, weight: .medium, design: .serif))
                        .foregroundStyle(AppPalette.paperMuted)
                }

                Spacer(minLength: 0)

                if showsCloseButton, let onClose {
                    Button(action: onClose) {
                        Text("关闭")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(AppPalette.paperMuted)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(AppPalette.paperMuted.opacity(0.82))

                    TextField("搜索笔记与知识点…", text: $searchText)
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.72))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.9), lineWidth: 1)
                        )
                )

                Menu {
                    ForEach(NotesFilterMode.allCases) { filter in
                        Button {
                            activeFilter = filter
                        } label: {
                            HStack {
                                Text(filter.title)
                                if activeFilter == filter {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .semibold))
                        Text(activeFilter.title)
                            .font(.system(size: 15, weight: .medium, design: .serif))
                    }
                    .foregroundStyle(AppPalette.paperMuted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.72))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var summaryText: String {
        if filteredCount == totalCount || searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && activeFilter == .all {
            return "共 \(totalCount) 条学习笔记，按最近、资料和知识点回看。"
        }
        return "当前筛出 \(filteredCount) / \(totalCount) 条笔记。"
    }
}
