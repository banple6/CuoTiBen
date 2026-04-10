import SwiftUI

// MARK: - 文本管线诊断面板
// Debug 专用，显示管线各阶段日志和文本质量报告

struct TextPipelineDiagnosticsView: View {
    @State private var events: [TextPipelineDiagnostics.PipelineEvent] = []
    @State private var filterStage: String? = nil

    private var filteredEvents: [TextPipelineDiagnostics.PipelineEvent] {
        guard let stage = filterStage else { return events }
        return events.filter { $0.stage == stage }
    }

    private var stageList: [String] {
        Array(Set(events.map(\.stage))).sorted()
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 阶段筛选栏
                if !stageList.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(label: "全部", isSelected: filterStage == nil) {
                                filterStage = nil
                            }
                            ForEach(stageList, id: \.self) { stage in
                                FilterChip(label: stage, isSelected: filterStage == stage) {
                                    filterStage = stage
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .background(Color(.systemGroupedBackground))
                }

                List {
                    if filteredEvents.isEmpty {
                        Text("暂无管线诊断事件")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(filteredEvents.indices, id: \.self) { index in
                            let event = filteredEvents[index]
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(event.severity.rawValue)
                                    Text(event.stage)
                                        .font(.caption.monospaced())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(stageColor(event.severity).opacity(0.15))
                                        .cornerRadius(4)
                                    Spacer()
                                    Text(formattedTime(event.timestamp))
                                        .font(.caption2.monospaced())
                                        .foregroundColor(.secondary)
                                }
                                Text(event.message)
                                    .font(.caption)
                                    .foregroundColor(.primary.opacity(0.85))
                                    .lineLimit(5)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("管线诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button("复制") {
                            copyEventsToClipboard()
                        }
                        Button("刷新") {
                            refreshEvents()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("清除") {
                        TextPipelineDiagnostics.clearEvents()
                        events = []
                    }
                }
            }
        }
        .onAppear {
            refreshEvents()
        }
    }

    private func refreshEvents() {
        events = TextPipelineDiagnostics.recentEvents(limit: 200)
    }

    private func copyEventsToClipboard() {
        let text = filteredEvents.map { event in
            "[\(formattedTime(event.timestamp))] [\(event.severity.rawValue)] [\(event.stage)] \(event.message)"
        }.joined(separator: "\n")
        UIPasteboard.general.string = text
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private func stageColor(_ severity: TextPipelineDiagnostics.PipelineEvent.Severity) -> Color {
        switch severity {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .repaired: return .green
        }
    }
}

// MARK: - 筛选标签

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .cornerRadius(12)
        }
    }
}

// MARK: - 文本质量快速检查视图

struct TextQualityBadge: View {
    let text: String

    var body: some View {
        let report = TextPipelineValidator.assessQuality(of: text)

        HStack(spacing: 4) {
            Circle()
                .fill(report.isHealthy ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(report.isHealthy ? "文本正常" : "文本异常")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 块分类统计视图

struct BlockClassificationSummaryView: View {
    let events: [TextPipelineDiagnostics.PipelineEvent]

    private var blockTypeDistribution: [(type: String, count: Int)] {
        let classEvents = events.filter { $0.stage == "块分类" }
        var counts: [String: Int] = [:]
        for event in classEvents {
            for typeName in BlockContentType.allCases {
                if event.message.contains(typeName.displayName) {
                    counts[typeName.displayName, default: 0] += 1
                    break
                }
            }
        }
        return counts.sorted { $0.value > $1.value }.map { (type: $0.key, count: $0.value) }
    }

    private var treeNodeStats: (accepted: Int, rejected: Int) {
        let treeEvents = events.filter { $0.stage == "树节点" }
        let rejected = treeEvents.filter { $0.severity == .warning }.count
        let accepted = treeEvents.count - rejected
        return (max(accepted, 0), rejected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("块分类分布")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            if blockTypeDistribution.isEmpty {
                Text("暂无分类数据")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                ForEach(blockTypeDistribution, id: \.type) { item in
                    HStack {
                        Text(item.type)
                            .font(.caption.monospaced())
                            .frame(width: 80, alignment: .leading)
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.3))
                            .frame(width: CGFloat(item.count) * 20, height: 14)
                            .cornerRadius(3)
                        Text("\(item.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                Label("树节点接受", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundColor(.green)
                Text("\(treeNodeStats.accepted)")
                    .font(.caption.bold())
                Spacer()
                Label("树节点拒绝", systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("\(treeNodeStats.rejected)")
                    .font(.caption.bold())
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
}

// MARK: - 加载阶段指示器

struct StructuredLoadingStageView: View {
    let stage: StructuredLoadingStage
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if !stage.isTerminal {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if stage == .ready {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }
                Text(stage.displayName)
                    .font(.subheadline)
                    .foregroundColor(stage.isTerminal && stage != .ready ? .orange : .primary)
            }

            if let message = error ?? stage.failSafeMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            if stage.isRetryable {
                Text("可点击重试")
                    .font(.caption2)
                    .foregroundColor(.accentColor)
            }
        }
    }
}

// MARK: - 解析来源 Debug 徽标

/// 在结构化预览工作区角落显示的 debug 信息面板
/// 显示解析来源（PP-StructureV3 vs Legacy）、块/段落/大纲统计、回退原因等
struct ParseSourceDebugBadge: View {
    let info: ParseSessionInfo?
    let stage: StructuredLoadingStage
    let error: String?

    @State private var isExpanded = false

    private var sourceLabel: String {
        guard let info else { return "未知" }
        return info.source.rawValue
    }

    private var sourceColor: Color {
        guard let info else { return .gray }
        switch info.source {
        case .ppStructureV3:    return .green
        case .legacyRemote:     return .orange
        case .legacyLocal:      return .red
        }
    }

    var body: some View {
        #if DEBUG
        VStack(alignment: .leading, spacing: 0) {
            // 折叠状态：紧凑徽标
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(sourceColor)
                        .frame(width: 7, height: 7)
                    Text(sourceLabel)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.8))
                    if info?.fallbackUsed == true {
                        Text("⚠️")
                            .font(.system(size: 9))
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Divider().padding(.vertical, 2)

                    if let info {
                        debugRow("来源", info.source.rawValue)
                        debugRow("阶段", stage.displayName)
                        if info.ppAttempted {
                            debugRow("PP尝试", info.ppSucceeded ? "✅ 成功" : "❌ 失败")
                        }
                        if info.fallbackUsed, let reason = info.fallbackReason {
                            debugRow("回退原因", reason)
                        }
                        if let fc = info.failureClass {
                            debugRow("失败分类", fc.rawValue)
                        }
                        debugRow("块", "\(info.normalizedBlockCount)")
                        debugRow("段落", "\(info.paragraphCount)")
                        debugRow("候选", "\(info.structureCandidateCount)")
                        debugRow("句子", "\(info.sentenceCount)")
                        debugRow("大纲", "\(info.outlineNodeCount)")
                        debugRow("分段", "\(info.segmentCount)")
                        if let d = info.parseDurationMs {
                            debugRow("耗时", "\(d)ms")
                        }
                        if let url = info.requestURL {
                            debugRow("URL", url)
                        }
                    } else {
                        debugRow("阶段", stage.displayName)
                        if let err = error {
                            Text(err)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.red.opacity(0.8))
                                .lineLimit(3)
                        }
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: 260, alignment: .leading)
        #endif
    }

    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 48, alignment: .trailing)
            Text(value)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.primary.opacity(0.8))
                .lineLimit(2)
        }
    }
}
