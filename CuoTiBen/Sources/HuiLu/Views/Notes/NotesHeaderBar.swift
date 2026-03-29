import SwiftUI

struct NotesHeaderBar: View {
    @Binding var searchText: String
    @Binding var activeFilter: NotesFilterMode

    let totalCount: Int
    let filteredCount: Int
    var showsCloseButton: Bool = true
    let onClose: (() -> Void)?

    var body: some View {
        GlassPanel(tone: .light, cornerRadius: 28, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("我的笔记")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.84))

                        Text(summaryText)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.54))
                    }

                    Spacer(minLength: 0)

                    if showsCloseButton, let onClose {
                        Button(action: onClose) {
                            Label("关闭", systemImage: "xmark.circle.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.56))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.42))

                        TextField("搜索标题、原句、标签、知识点", text: $searchText)
                            .font(.system(size: 15, weight: .medium))
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.8))
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
                                .font(.system(size: 14, weight: .bold))
                            Text(activeFilter.title)
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(Color.blue.opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.blue.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var summaryText: String {
        if filteredCount == totalCount || searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && activeFilter == .all {
            return "共 \(totalCount) 条学习笔记，按最近、资料和知识点浏览。"
        }
        return "当前筛出 \(filteredCount) / \(totalCount) 条笔记。"
    }
}
