import SwiftUI

struct AppSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .light)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        GlassPanel(tone: .light, cornerRadius: 28, padding: 18) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("原文渲染模式")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.black.opacity(0.82))

                                Text("你可以选择更稳的阅读版 PDF，或者优先使用原始 PDF 页面。原始 PDF 模式在可选文字 PDF 上会尝试对齐句子高亮；扫描型资料如果无法对齐，会自动回退。")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.58))
                                    .lineSpacing(4)
                            }
                        }

                        VStack(spacing: 14) {
                            ForEach(SourceReaderMode.allCases) { mode in
                                Button {
                                    viewModel.updateSourceReaderMode(mode)
                                } label: {
                                    HStack(alignment: .top, spacing: 14) {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(mode.title)
                                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                                .foregroundStyle(Color.black.opacity(0.82))

                                            Text(mode.subtitle)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(Color.black.opacity(0.56))
                                                .lineSpacing(4)
                                        }

                                        Spacer(minLength: 12)

                                        Image(systemName: viewModel.sourceReaderMode == mode ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundStyle(viewModel.sourceReaderMode == mode ? Color.blue : Color.black.opacity(0.18))
                                    }
                                    .padding(18)
                                    .background(
                                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                                            .fill(viewModel.sourceReaderMode == mode ? Color.blue.opacity(0.08) : Color.white.opacity(0.76))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                                            .stroke(viewModel.sourceReaderMode == mode ? Color.blue.opacity(0.26) : Color.white.opacity(0.72), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#if DEBUG
struct AppSettingsSheet_Previews: PreviewProvider {
    static var previews: some View {
        AppSettingsSheet()
            .environmentObject(AppViewModel())
    }
}
#endif
