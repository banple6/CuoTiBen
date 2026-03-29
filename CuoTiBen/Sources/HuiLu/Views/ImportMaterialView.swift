import SwiftUI
import UniformTypeIdentifiers

struct ImportMaterialView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: AppViewModel

    @State private var selectedFiles: [URL] = []
    @State private var showingFilePicker = false
    @State private var importMode: ImportMode = .pdf
    @State private var flowState: FlowState = .selection
    @State private var importProgress = 0.0
    @State private var stageIndex = 0
    @State private var pagesProcessed = 0
    @State private var previewBlocks = 0
    @State private var parsedSections = 0
    @State private var importedPreviewDocumentID: UUID?
    @State private var importErrorMessage: String?
    @State private var progressTask: Task<Void, Never>?

    enum ImportMode: String, CaseIterable {
        case pdf = "文档"
        case album = "图片"
        case text = "文本"

        var title: String {
            switch self {
            case .pdf: return "文档文件"
            case .album: return "相册截图"
            case .text: return "文本笔记"
            }
        }

        var icon: String {
            switch self {
            case .pdf: return "doc.fill"
            case .album: return "photo.on.rectangle.angled"
            case .text: return "text.alignleft"
            }
        }

        var prompt: String {
            switch self {
            case .pdf: return "选择文档文件"
            case .album: return "选择图片"
            case .text: return "选择文本文件"
            }
        }

        var allowedTypes: [UTType] {
            switch self {
            case .pdf: return [.pdf]
            case .album: return [.image]
            case .text: return [.text, .plainText]
            }
        }

        var materialKind: MaterialImportKind {
            switch self {
            case .pdf: return .pdf
            case .album: return .image
            case .text: return .text
            }
        }
    }

    enum FlowState {
        case selection
        case processing
        case success
    }

    private let processingStages = [
        "创建资料记录",
        "提取正文文本",
        "识别章节与定位",
        "整理主题标签",
        "抽取候选知识点",
        "构建结构化预览"
    ]

    var body: some View {
        ZStack {
            AppBackground(style: flowState == .success ? .dark : .light)

            switch flowState {
            case .selection:
                selectionView
            case .processing:
                processingView
            case .success:
                successView
            }
        }
        .ignoresSafeArea()
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: importMode.allowedTypes,
            allowsMultipleSelection: true
        ) { result in
            handleFileSelection(result)
        }
        .onDisappear {
            progressTask?.cancel()
        }
    }

    private var selectionView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                HStack {
                    Spacer()

                    Text("智能资料导入")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.82))

                    Spacer()

                    Button(action: dismiss.callAsFunction) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.42))
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.6), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                GlassPanel(tone: .light, cornerRadius: 30, padding: 18) {
                    VStack(spacing: 18) {
                        Text("把原始资料先整理成结构化预览。系统会自动抽取正文、章节、来源定位、标签和候选知识点，确认后再按需生成卡片。")
                            .font(.system(size: 19, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)

                        ZStack {
                            Circle()
                                .stroke(Color.cyan.opacity(0.22), lineWidth: 14)
                                .frame(width: 184, height: 184)

                            Circle()
                                .trim(from: 0.05, to: 0.82)
                                .stroke(
                                    AngularGradient(
                                        colors: [Color.cyan.opacity(0.7), Color.blue.opacity(0.5), Color.mint.opacity(0.7)],
                                        center: .center
                                    ),
                                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                                )
                                .frame(width: 184, height: 184)
                                .rotationEffect(.degrees(-90))

                            VStack(spacing: 10) {
                                Image(systemName: importMode.icon)
                                    .font(.system(size: 34, weight: .semibold))
                                    .foregroundStyle(Color.blue.opacity(0.7))

                                Text(selectedFiles.isEmpty ? "已就绪" : "已选 \(selectedFiles.count) 项")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.black.opacity(0.76))

                                Text(importMode.title)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.45))
                            }
                        }

                        HStack(spacing: 10) {
                            ForEach(ImportMode.allCases, id: \.self) { mode in
                                ImportModeChip(
                                    mode: mode,
                                    isSelected: importMode == mode
                                ) {
                                    importMode = mode
                                    selectedFiles = []
                                    importErrorMessage = nil
                                }
                            }
                        }
                    }
                }

                if !selectedFiles.isEmpty {
                    GlassPanel(tone: .light, cornerRadius: 30, padding: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("已选资料")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.8))

                            ForEach(selectedFiles, id: \.self) { url in
                                HStack(spacing: 12) {
                                    FrostedOrb(icon: fileIcon(for: url), size: 38, tone: .light)

                                    Text(url.lastPathComponent)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Color.black.opacity(0.72))
                                        .lineLimit(1)

                                    Spacer()
                                }
                            }
                        }
                    }
                }

                if let importErrorMessage {
                    Text(importErrorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.red.opacity(0.78))
                        .padding(.horizontal, 6)
                }

                VStack(spacing: 14) {
                    PrimaryGlowButton(title: selectedFiles.isEmpty ? importMode.prompt : "开始智能导入", icon: selectedFiles.isEmpty ? "arrow.up.doc.fill" : "sparkles") {
                        handlePrimaryAction()
                    }

                    Button("取消") {
                        dismiss()
                    }
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.blue.opacity(0.76))
                }
                .padding(.top, 6)

                Spacer(minLength: 80)
            }
            .padding(.horizontal, 20)
            .padding(.top, 58)
        }
    }

    private var processingView: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Text("智能资料导入")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.82))
                Spacer()
                Circle()
                    .fill(Color.clear)
                    .frame(width: 38, height: 38)
            }

            GlassPanel(tone: .light, cornerRadius: 34, padding: 18) {
                VStack(spacing: 24) {
                    Text("系统会先创建资料记录，再异步抽正文、章节、定位、标签和候选知识点，最终整理成可确认的结构化预览。")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)

                    ZStack {
                        Circle()
                            .stroke(Color.cyan.opacity(0.15), lineWidth: 18)
                            .frame(width: 206, height: 206)

                        Circle()
                            .trim(from: 0.0, to: importProgress)
                            .stroke(
                                AngularGradient(
                                    colors: [Color.cyan, Color.blue, Color.mint, Color.cyan],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 22, lineCap: .round)
                            )
                            .frame(width: 206, height: 206)
                            .rotationEffect(.degrees(-90))
                            .shadow(color: Color.cyan.opacity(0.18), radius: 10)

                        VStack(spacing: 8) {
                            Text("\(Int(importProgress * 100))%")
                                .font(.system(size: 46, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.76))

                            Text("处理中...")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.46))
                        }
                    }
                    .padding(.top, 8)

                    GlassPanel(tone: .light, cornerRadius: 28, padding: 18) {
                        VStack(spacing: 18) {
                            Text("正在整理结构化预览")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.8))

                            Text(processingStages[stageIndex])
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.blue.opacity(0.7))

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 12)], spacing: 12) {
                                ForEach(processingStages, id: \.self) { stage in
                                    Text(stage)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(stage == processingStages[stageIndex] ? Color.white : Color.black.opacity(0.5))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(stage == processingStages[stageIndex] ? Color.blue.opacity(0.58) : Color.white.opacity(0.42))
                                        )
                                }
                            }
                        }
                    }
                }
            }

            Button("取消导入") {
                cancelImport()
            }
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(Color.blue.opacity(0.8))
            .padding(.horizontal, 34)
            .padding(.vertical, 14)
            .background(
                Capsule(style: .continuous)
                    .stroke(Color.blue.opacity(0.5), lineWidth: 1.5)
            )

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 58)
    }

    private var successView: some View {
        VStack(spacing: 26) {
            HStack {
                Spacer()
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppPalette.softText.opacity(0.72))
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 18)

            ImportSuccessIllustration()

            Text("导入成功")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(AppPalette.softText)

            Text("结构化预览已经整理完成。你可以先检查章节、标签和候选知识点，再决定是否生成卡片。")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppPalette.softMutedText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 22)

            HStack(spacing: 12) {
                SuccessMetricCard(value: "\(pagesProcessed)", label: "已处理\n页数")
                SuccessMetricCard(value: "\(parsedSections)", label: "解析章节\n数量")
                SuccessMetricCard(value: "\(previewBlocks)", label: "结构化预览\n知识块")
            }

            PrimaryGlowButton(title: "查看结构化预览", icon: "books.vertical.fill") {
                viewModel.pendingPreviewDocumentID = importedPreviewDocumentID
                NotificationCenter.default.post(name: .switchToLibraryTab, object: nil)
                dismiss()
            }
            .padding(.top, 8)

            Button {
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                    Text("完成")
                }
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AppPalette.cyan)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
    }

    private func handlePrimaryAction() {
        if selectedFiles.isEmpty {
            showingFilePicker = true
        } else {
            startImport()
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            selectedFiles = urls
            importErrorMessage = nil
        case .failure:
            importErrorMessage = "读取资料失败，请重新选择。"
        }
    }

    private func startImport() {
        importErrorMessage = nil
        flowState = .processing
        importProgress = 0.08
        stageIndex = 0
        pagesProcessed = 0
        parsedSections = 0
        previewBlocks = 0
        importedPreviewDocumentID = nil
        startProgressAnimation()

        Task {
            do {
                let summary = try await viewModel.importMaterials(from: selectedFiles, mode: importMode.materialKind)

                await MainActor.run {
                    progressTask?.cancel()
                    pagesProcessed = summary.processedPages
                    parsedSections = summary.parsedSectionCount
                    previewBlocks = summary.previewChunkCount
                    importedPreviewDocumentID = summary.documents.first?.id
                    importProgress = 1.0

                    withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                        flowState = .success
                    }
                }
            } catch {
                await MainActor.run {
                    progressTask?.cancel()
                    flowState = .selection
                    importErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func startProgressAnimation() {
        progressTask?.cancel()
        progressTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 420_000_000)
                await MainActor.run {
                    stageIndex = (stageIndex + 1) % processingStages.count
                    if importProgress < 0.9 {
                        importProgress += 0.09
                    }
                }
            }
        }
    }

    private func cancelImport() {
        progressTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            flowState = .selection
            importProgress = 0.0
            stageIndex = 0
            previewBlocks = 0
            importedPreviewDocumentID = nil
        }
    }

    private func fileIcon(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return "doc.fill"
        case "txt", "md", "text":
            return "text.alignleft"
        default:
            return "photo.fill"
        }
    }
}

struct ImportModeChip: View {
    let mode: ImportMaterialView.ImportMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.system(size: 18, weight: .semibold))

                Text(mode.rawValue)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Color.white : Color.black.opacity(0.62))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.7) : Color.white.opacity(0.52))
            )
        }
        .buttonStyle(.plain)
    }
}

struct SuccessMetricCard: View {
    let value: String
    let label: String

    var body: some View {
        GlassPanel(tone: .dark, cornerRadius: 28, padding: 18) {
            VStack(spacing: 8) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.softText)

                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppPalette.softMutedText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, minHeight: 124)
        }
    }
}

struct ImportSuccessIllustration: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(AppPalette.cyan.opacity(0.2))
                .frame(width: 212, height: 212)
                .blur(radius: 10)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .frame(width: 112, height: 146)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                )
                .rotationEffect(.degrees(-14))
                .offset(x: -42, y: 12)

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.84), AppPalette.primary.opacity(0.36)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 152)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                )
                .rotationEffect(.degrees(12))
                .offset(x: 46, y: 6)

            Ellipse()
                .stroke(
                    LinearGradient(
                        colors: [AppPalette.cyan.opacity(0.55), Color.white.opacity(0.2), AppPalette.amber.opacity(0.55)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 8
                )
                .frame(width: 168, height: 78)
                .rotationEffect(.degrees(16))

            Ellipse()
                .stroke(
                    LinearGradient(
                        colors: [AppPalette.primary.opacity(0.5), AppPalette.cyan.opacity(0.2), AppPalette.mint.opacity(0.45)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 8
                )
                .frame(width: 180, height: 84)
                .rotationEffect(.degrees(-18))

            Image(systemName: "trophy.fill")
                .font(.system(size: 92, weight: .regular))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white.opacity(0.95), AppPalette.cyan, AppPalette.primary],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: AppPalette.cyan.opacity(0.18), radius: 18)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [AppPalette.mint, AppPalette.cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppPalette.deepNavy)
                )
                .shadow(color: AppPalette.mint.opacity(0.24), radius: 12)
                .offset(x: 72, y: 48)

            Circle()
                .fill(AppPalette.amber.opacity(0.7))
                .frame(width: 10, height: 10)
                .blur(radius: 2)
                .offset(x: 70, y: -18)

            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 8, height: 8)
                .blur(radius: 1)
                .offset(x: -54, y: -26)

            Circle()
                .fill(AppPalette.primary.opacity(0.74))
                .frame(width: 12, height: 12)
                .blur(radius: 2)
                .offset(x: -76, y: 44)
        }
    }
}

#if DEBUG
struct ImportMaterialView_Previews: PreviewProvider {
    static var previews: some View {
        ImportMaterialView()
            .environmentObject(AppViewModel())
    }
}
#endif
