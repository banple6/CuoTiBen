import SwiftUI

// MARK: - 文本管线诊断面板
// Debug 专用，显示管线各阶段日志和文本质量报告

struct TextPipelineDiagnosticsView: View {
    @State private var events: [TextPipelineDiagnostics.PipelineEvent] = []
    @State private var selectedEvent: TextPipelineDiagnostics.PipelineEvent?

    var body: some View {
        NavigationView {
            List {
                if events.isEmpty {
                    Text("暂无管线诊断事件")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(events.indices, id: \.self) { index in
                        let event = events[index]
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
                                .lineLimit(3)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("管线诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("刷新") {
                        refreshEvents()
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
        events = TextPipelineDiagnostics.recentEvents(limit: 100)
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
