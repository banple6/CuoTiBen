import SwiftUI

struct AppSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var documentParserBaseURL = DocumentParseService.backendBaseURL
    @State private var documentParserMessage: String?

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

                        GlassPanel(tone: .light, cornerRadius: 28, padding: 18) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("远端文档解析")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.black.opacity(0.82))

                                Text("这里配置的是 PP/FastAPI 文档解析网关，不是 AI 后端。服务默认端口是 8900，App 会自动请求 /api/document/parse。")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.58))
                                    .lineSpacing(4)

                                TextField("例如 http://192.168.1.10:8900", text: $documentParserBaseURL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.URL)
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color.white.opacity(0.84))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                    )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("当前端点：\(DocumentParseEndpointConfig.parseEndpointURL?.absoluteString ?? "未配置")")
                                    Text("真机不要填 127.0.0.1，需填 Mac 局域网 IP 或线上解析服务器地址。")
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.52))

                                HStack(spacing: 10) {
                                    Button {
                                        let input = documentParserBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                                        DocumentParseService.saveBackendURL(input)
                                        documentParserBaseURL = DocumentParseService.backendBaseURL
                                        if input.isEmpty {
                                            documentParserMessage = "已恢复构建默认解析网关。"
                                        } else if DocumentParseEndpointConfig.isValidRuntimeBaseURL(input) {
                                            documentParserMessage = "已启用远端文档解析。"
                                        } else {
                                            documentParserMessage = "解析网关地址格式无效，仍使用当前可用配置。"
                                        }
                                    } label: {
                                        Label("保存解析网关", systemImage: "checkmark.circle.fill")
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button {
                                        documentParserBaseURL = ""
                                        DocumentParseService.saveBackendURL("")
                                        documentParserBaseURL = DocumentParseService.backendBaseURL
                                        documentParserMessage = "已恢复构建默认解析网关。"
                                    } label: {
                                        Label("恢复默认", systemImage: "arrow.counterclockwise.circle")
                                    }
                                    .buttonStyle(.bordered)
                                }

                                if let documentParserMessage {
                                    Text(documentParserMessage)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.blue.opacity(0.82))
                                }
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
