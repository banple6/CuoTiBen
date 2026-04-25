import SwiftUI

// MARK: - 文本管线诊断面板
// Debug 专用，显示管线各阶段日志和文本质量报告

struct TextPipelineDiagnosticsView: View {
    @State private var events: [TextPipelineDiagnostics.PipelineEvent] = []
    @State private var filterStage: String? = nil

    private var latestAdmissionSummary: MindMapAdmissionSummary? {
        events
            .filter { $0.stage == "导图准入" }
            .last
            .flatMap { event in
                MindMapAdmissionSummary(event: event)
            }
    }

    private var latestSentenceAIStatus: AIGatewayEventStatus? {
        events
            .filter { $0.stage == "AI" && ($0.message.contains("[AI][SentenceExplain]") || $0.message.contains("[AI][Sentence]")) }
            .last
            .flatMap { event in
                AIGatewayEventStatus(event: event)
            }
    }

    private var latestPassageAIStatus: AIGatewayEventStatus? {
        events
            .filter { $0.stage == "AI" && $0.message.contains("[AI][PassageMap]") }
            .last
            .flatMap { event in
                AIGatewayEventStatus(event: event)
            }
    }

    private var latestDocumentParseRouteStatus: DocumentParseRouteStatus? {
        DocumentParseRouteStatus(events: events)
    }

    private var latestMaterialGateStatus: MaterialGateStatus? {
        events
            .filter { $0.stage == "PP" && $0.message.contains("[PP][Gate]") }
            .last
            .flatMap { MaterialGateStatus(event: $0) }
    }

    private var latestAIGatewayStatus: AIGatewayEventStatus? {
        [latestSentenceAIStatus, latestPassageAIStatus]
            .compactMap { $0 }
            .sorted { $0.timestamp < $1.timestamp }
            .last
    }

    private var fallbackSummary: FallbackSummary? {
        FallbackSummary(
            sentenceStatus: latestSentenceAIStatus,
            passageStatus: latestPassageAIStatus
        )
    }

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
                    Section("Build") {
                        RuntimeBuildFingerprintCard(fingerprint: RuntimeBuildFingerprint.current)
                    }

                    if let documentParseStatus = latestDocumentParseRouteStatus {
                        Section("Document parse") {
                            DocumentParseRouteStatusCard(status: documentParseStatus)
                        }
                    }

                    if let materialGateStatus = latestMaterialGateStatus {
                        Section("Material gate") {
                            MaterialGateStatusCard(status: materialGateStatus)
                        }
                    }

                    Section("Cloud request probe") {
                        CloudRequestDiagnosticsView()
                    }

                    if let gatewayStatus = latestAIGatewayStatus {
                        Section("AI Gateway") {
                            AIGatewayStatusCard(status: gatewayStatus)
                        }
                    }

                    if let summary = latestAdmissionSummary {
                        Section("MindMap admission") {
                            MindMapAdmissionSummaryCard(summary: summary)
                        }
                    }

                    if let fallbackSummary {
                        Section("Fallback") {
                            FallbackSummaryCard(summary: fallbackSummary)
                        }
                    }

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

private struct RuntimeBuildFingerprintCard: View {
    let fingerprint: RuntimeBuildFingerprint

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DiagnosticKeyValueRow(label: "gitSHA", value: fingerprint.gitSHA)
            DiagnosticKeyValueRow(label: "branch", value: fingerprint.branchName)
            DiagnosticKeyValueRow(label: "buildTime", value: fingerprint.buildTime)
            DiagnosticKeyValueRow(label: "configuration", value: fingerprint.appConfiguration)
            DiagnosticKeyValueRow(label: "aiBackendBaseURL", value: fingerprint.aiBackendBaseURL)
            DiagnosticKeyValueRow(label: "documentParseEndpoint", value: fingerprint.documentParseEndpointStatus)
            DiagnosticKeyValueRow(label: "isDebugBuild", value: fingerprint.isDebugBuild ? "true" : "false")
        }
        .padding(.vertical, 4)
    }
}

private struct DocumentParseRouteStatus {
    let endpointConfigured: Bool
    let endpointURL: String
    let remoteStatus: String
    let skippedBecauseUnconfigured: Bool
    let cloudDocumentParseAttempted: Bool

    init?(events: [TextPipelineDiagnostics.PipelineEvent]) {
        let routeEvents = events.filter { $0.stage == "PP" && $0.message.contains("[PP][Route]") }
        guard !routeEvents.isEmpty else { return nil }

        let endpointEvent = routeEvents.last { $0.message.contains("document_parse_endpoint=") }
        let endpointValues = endpointEvent.map { DiagnosticsEventParser.parseKeyValuePairs(from: $0.message) } ?? [:]
        let endpoint = endpointValues["document_parse_endpoint"] ?? "unknown"

        endpointConfigured = endpoint != "unconfigured" && endpoint != "unknown"
        endpointURL = endpoint
        skippedBecauseUnconfigured = routeEvents.contains { $0.message.contains("skip remote document parse") }

        cloudDocumentParseAttempted = routeEvents.contains(where: { $0.message.contains("remote parse request start") })

        if cloudDocumentParseAttempted {
            remoteStatus = "request_started"
        } else if skippedBecauseUnconfigured {
            remoteStatus = "skipped_unconfigured"
        } else {
            remoteStatus = "unknown"
        }
    }
}

private struct DocumentParseRouteStatusCard: View {
    let status: DocumentParseRouteStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DiagnosticKeyValueRow(label: "documentParseEndpointConfigured", value: status.endpointConfigured ? "true" : "false")
            DiagnosticKeyValueRow(label: "documentParseEndpointURL", value: status.endpointURL)
            DiagnosticKeyValueRow(label: "documentParseRemoteStatus", value: status.remoteStatus)
            DiagnosticKeyValueRow(label: "skippedBecauseUnconfigured", value: status.skippedBecauseUnconfigured ? "true" : "false")
            DiagnosticKeyValueRow(label: "cloudDocumentParseAttempted", value: status.cloudDocumentParseAttempted ? "true" : "false")
        }
        .padding(.vertical, 4)
    }
}

private struct MaterialGateStatus {
    let materialMode: String
    let rawTextLength: String
    let sentenceDrafts: String
    let rawTextTooShort: Bool
    let sentenceDraftsZero: Bool
    let noPassageBody: Bool
    let mostlyQuestionBlocks: Bool
    let mostlyChineseInstruction: Bool
    let earlyFailConvertedToFallback: Bool
    let reason: String

    init?(event: TextPipelineDiagnostics.PipelineEvent) {
        let values = DiagnosticsEventParser.parseKeyValuePairs(from: event.message)
        guard let materialMode = values["material_mode"] else { return nil }
        let reason = values["reason"] ?? ""

        self.materialMode = materialMode
        rawTextLength = values["raw_text_length"] ?? "nil"
        sentenceDrafts = values["sentence_drafts"] ?? "nil"
        rawTextTooShort = reason.contains("rawTextTooShort")
        sentenceDraftsZero = reason.contains("sentenceDrafts=0")
        noPassageBody = reason.contains("noPassageBody")
        mostlyQuestionBlocks = reason.contains("mostlyQuestionBlocks")
        mostlyChineseInstruction = reason.contains("mostlyChineseInstruction")
        earlyFailConvertedToFallback = (values["early_fail_converted_to_fallback"] ?? "false") == "true"
        self.reason = reason.replacingOccurrences(of: "||", with: " | ")
    }
}

private struct MaterialGateStatusCard: View {
    let status: MaterialGateStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DiagnosticKeyValueRow(label: "materialMode", value: status.materialMode)
            DiagnosticKeyValueRow(label: "rawTextLength", value: status.rawTextLength)
            DiagnosticKeyValueRow(label: "sentenceDrafts", value: status.sentenceDrafts)
            DiagnosticKeyValueRow(label: "rawTextTooShort", value: status.rawTextTooShort ? "true" : "false")
            DiagnosticKeyValueRow(label: "sentenceDrafts=0", value: status.sentenceDraftsZero ? "true" : "false")
            DiagnosticKeyValueRow(label: "noPassageBody", value: status.noPassageBody ? "true" : "false")
            DiagnosticKeyValueRow(label: "mostlyQuestionBlocks", value: status.mostlyQuestionBlocks ? "true" : "false")
            DiagnosticKeyValueRow(label: "mostlyChineseInstruction", value: status.mostlyChineseInstruction ? "true" : "false")
            DiagnosticKeyValueRow(label: "earlyFailConverted", value: status.earlyFailConvertedToFallback ? "true" : "false")
            DiagnosticKeyValueRow(label: "reason", value: status.reason)
        }
        .padding(.vertical, 4)
    }
}

private struct MindMapAdmissionSummary {
    let mainlineCount: Int
    let auxiliaryCount: Int
    let rejectedCount: Int
    let averageHygiene: String
    let averageConsistency: String
    let topRejectedReasons: String
    let diagnosticsSample: String

    init?(event: TextPipelineDiagnostics.PipelineEvent) {
        let values = DiagnosticsEventParser.parseKeyValuePairs(from: event.message)
        guard let mainline = values["mainline_count"],
              let auxiliary = values["auxiliary_count"],
              let rejected = values["rejected_count"]
        else {
            return nil
        }

        self.mainlineCount = Int(mainline) ?? 0
        self.auxiliaryCount = Int(auxiliary) ?? 0
        self.rejectedCount = Int(rejected) ?? 0
        self.averageHygiene = values["average_hygiene"] ?? "0.00"
        self.averageConsistency = values["average_consistency"] ?? "0.00"
        self.topRejectedReasons = values["top_rejected_reasons"]?
            .replacingOccurrences(of: "||", with: " | ")
            ?? "none"
        self.diagnosticsSample = self.topRejectedReasons == "none"
            ? "暂无 rejected 样本，当前节点已通过准入。"
            : self.topRejectedReasons
    }
}

private struct MindMapAdmissionSummaryCard: View {
    let summary: MindMapAdmissionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                stat(title: "mainline", value: "\(summary.mainlineCount)", color: .green)
                Spacer()
                stat(title: "auxiliary", value: "\(summary.auxiliaryCount)", color: .orange)
                Spacer()
                stat(title: "rejected", value: "\(summary.rejectedCount)", color: .red)
            }

            HStack {
                Label("average hygiene", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(summary.averageHygiene)
                    .font(.caption.monospaced())
                Spacer()
                Label("average consistency", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(summary.averageConsistency)
                    .font(.caption.monospaced())
            }

            Text("top rejected reasons: \(summary.topRejectedReasons)")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("diagnostics sample：\(summary.diagnosticsSample)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func stat(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundColor(color)
        }
    }
}

private struct AIGatewayEventStatus {
    enum Scope: String {
        case sentence = "sentence"
        case passage = "passage"
    }

    let scope: Scope
    let timestamp: Date
    let requestID: String?
    let provider: String?
    let model: String?
    let configured: Bool?
    let errorCode: String?
    let retryCount: Int
    let usedCache: Bool
    let usedFallback: Bool
    let circuitState: String
    let fallbackMessage: String?
    let materialMode: String?
    let activeCallPath: String?
    let acceptedParagraphCount: Int?
    let rejectedParagraphCount: Int?
    let nonPassageRatio: String?
    let reason: String?
    let requestBuilderUsed: Bool?
    let clientRequestID: String?
    let documentID: String?
    let contentHash: String?
    let contractPreflightPassed: Bool?
    let missingFields: String?
    let selectionKind: String?
    let sentenceIdentityPresent: Bool?
    let passageIdentityPresent: Bool?
    let sentenceMissingFields: String?
    let passageMissingFields: String?
    let cloudExplainAttempted: Bool?
    let cloudPassageAttempted: Bool?
    let fallbackReason: String?
    let currentResultSource: String?

    init?(event: TextPipelineDiagnostics.PipelineEvent) {
        guard event.stage == "AI" else { return nil }

        let scope: Scope
        if event.message.contains("[AI][SentenceExplain]") || event.message.contains("[AI][Sentence]") {
            scope = .sentence
        } else if event.message.contains("[AI][PassageMap]") {
            scope = .passage
        } else {
            return nil
        }

        let values = DiagnosticsEventParser.parseKeyValuePairs(from: event.message)
        guard values["used_fallback"] != nil || values["material_mode"] != nil || values["request_preflight_passed"] != nil else { return nil }

        self.scope = scope
        timestamp = event.timestamp
        requestID = values["request_id"]
        provider = values["provider"] ?? ((values["used_fallback"] == "true") ? "local_fallback" : nil)
        model = values["model"] ?? ((values["used_fallback"] == "true") ? "local_fallback" : nil)
        errorCode = values["error_code"]
        retryCount = Int(values["retry_count"] ?? "0") ?? 0
        usedCache = (values["used_cache"] ?? "false") == "true"
        usedFallback = (values["used_fallback"] ?? "false") == "true"
        if let rawCircuitState = values["circuit_state"], !rawCircuitState.isEmpty {
            circuitState = rawCircuitState
        } else if errorCode == "MODEL_CONFIG_MISSING" {
            circuitState = "closed"
        } else {
            circuitState = "unknown"
        }
        if errorCode == "MODEL_CONFIG_MISSING" {
            configured = false
        } else if provider != nil || model != nil || requestID != nil {
            configured = true
        } else {
            configured = nil
        }
        materialMode = values["material_mode"]
        activeCallPath = values["active_call_path"]
        acceptedParagraphCount = Int(values["accepted_paragraph_count"] ?? "")
        rejectedParagraphCount = Int(values["rejected_paragraph_count"] ?? "")
        nonPassageRatio = values["non_passage_ratio"]
        reason = values["reason"]?.replacingOccurrences(of: "||", with: " | ")
        requestBuilderUsed = (values["request_builder_used"] ?? values["requestBuilderUsed"]).map { $0 == "true" }
        clientRequestID = values["client_request_id"]
        documentID = values["document_id"]
        contentHash = values["content_hash"]
        contractPreflightPassed = (values["contract_preflight_passed"] ?? values["contractPreflightPassed"]).map { $0 == "true" }
        missingFields = (values["missing_fields"] ?? values["missingFields"])?
            .replacingOccurrences(of: ",", with: ", ")
        selectionKind = values["selection_kind"]
        sentenceIdentityPresent = values["sentence_identity_present"].map { $0 == "true" }
        passageIdentityPresent = contractPreflightPassed
        sentenceMissingFields = scope == .sentence ? missingFields : nil
        passageMissingFields = scope == .passage ? missingFields : nil
        cloudExplainAttempted = values["cloud_explain_attempted"].map { $0 == "true" }
        cloudPassageAttempted = values["cloud_passage_attempted"].map { $0 == "true" }
            ?? (scope == .passage ? (contractPreflightPassed ?? false) : nil)
        fallbackReason = values["fallback_reason"] ?? values["skip_remote_reason"] ?? reason
        currentResultSource = values["current_result_source"] ?? values["currentResultSource"]
        fallbackMessage = DiagnosticsEventParser.buildFallbackMessage(
            scope: scope,
            errorCode: errorCode,
            usedFallback: usedFallback,
            materialMode: materialMode
        )
    }
}

private struct AIGatewayStatusCard: View {
    let status: AIGatewayEventStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DiagnosticKeyValueRow(label: "provider", value: status.provider ?? "nil")
            DiagnosticKeyValueRow(label: "model", value: status.model ?? "nil")
            DiagnosticKeyValueRow(label: "configured", value: status.configured.map { $0 ? "true" : "false" } ?? "unknown")
            DiagnosticKeyValueRow(label: "error_code", value: status.errorCode ?? "nil")
            DiagnosticKeyValueRow(label: "request_id", value: status.requestID ?? "nil")
            DiagnosticKeyValueRow(label: "retry_count", value: "\(status.retryCount)")
            DiagnosticKeyValueRow(label: "used_cache", value: status.usedCache ? "true" : "false")
            DiagnosticKeyValueRow(label: "used_fallback", value: status.usedFallback ? "true" : "false")
            DiagnosticKeyValueRow(label: "circuit_state", value: status.circuitState)
            DiagnosticKeyValueRow(label: "currentResultSource", value: status.currentResultSource ?? "nil")
            DiagnosticKeyValueRow(label: "fallbackReason", value: status.fallbackReason ?? "nil")
            if status.scope == .sentence {
                DiagnosticKeyValueRow(label: "selectionKind", value: status.selectionKind ?? "nil")
                DiagnosticKeyValueRow(label: "sentenceIdentityPresent", value: status.sentenceIdentityPresent.map { $0 ? "true" : "false" } ?? "nil")
                DiagnosticKeyValueRow(label: "sentenceMissingFields", value: status.sentenceMissingFields ?? "nil")
                DiagnosticKeyValueRow(label: "cloudExplainAttempted", value: status.cloudExplainAttempted.map { $0 ? "true" : "false" } ?? "nil")
            }
            if status.scope == .passage {
                DiagnosticKeyValueRow(label: "material_mode", value: status.materialMode ?? "nil")
                DiagnosticKeyValueRow(label: "requestBuilderUsed", value: status.requestBuilderUsed.map { $0 ? "true" : "false" } ?? "nil")
                DiagnosticKeyValueRow(label: "clientRequestID", value: status.clientRequestID ?? "nil")
                DiagnosticKeyValueRow(label: "documentID", value: status.documentID ?? "nil")
                DiagnosticKeyValueRow(label: "contentHash", value: status.contentHash ?? "nil")
                DiagnosticKeyValueRow(label: "passageIdentityPresent", value: status.passageIdentityPresent.map { $0 ? "true" : "false" } ?? "nil")
                DiagnosticKeyValueRow(label: "contractPreflightPassed", value: status.contractPreflightPassed.map { $0 ? "true" : "false" } ?? "nil")
                DiagnosticKeyValueRow(label: "passageMissingFields", value: status.passageMissingFields ?? "nil")
                DiagnosticKeyValueRow(label: "missingFields", value: status.missingFields ?? "nil")
                DiagnosticKeyValueRow(label: "cloudPassageAttempted", value: status.cloudPassageAttempted.map { $0 ? "true" : "false" } ?? "nil")
                DiagnosticKeyValueRow(label: "activeCallPath", value: status.activeCallPath ?? "nil")
                DiagnosticKeyValueRow(label: "acceptedParagraphCount", value: status.acceptedParagraphCount.map(String.init) ?? "nil")
                DiagnosticKeyValueRow(label: "rejectedParagraphCount", value: status.rejectedParagraphCount.map(String.init) ?? "nil")
                DiagnosticKeyValueRow(label: "nonPassageRatio", value: status.nonPassageRatio ?? "nil")
                DiagnosticKeyValueRow(label: "reason", value: status.reason ?? "nil")
            }
        }
        .padding(.vertical, 4)
    }
}

private struct FallbackSummary {
    let usingSentenceFallback: Bool
    let usingPassageFallback: Bool
    let fallbackMessage: String

    init?(sentenceStatus: AIGatewayEventStatus?, passageStatus: AIGatewayEventStatus?) {
        let usingSentenceFallback = sentenceStatus?.usedFallback ?? false
        let usingPassageFallback = passageStatus?.usedFallback ?? false
        guard sentenceStatus != nil || passageStatus != nil else { return nil }

        self.usingSentenceFallback = usingSentenceFallback
        self.usingPassageFallback = usingPassageFallback

        let messages = [sentenceStatus?.fallbackMessage, passageStatus?.fallbackMessage]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        fallbackMessage = messages.isEmpty ? "none" : messages.joined(separator: "；")
    }
}

private struct FallbackSummaryCard: View {
    let summary: FallbackSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DiagnosticKeyValueRow(label: "using sentence fallback", value: summary.usingSentenceFallback ? "true" : "false")
            DiagnosticKeyValueRow(label: "using passage fallback", value: summary.usingPassageFallback ? "true" : "false")
            DiagnosticKeyValueRow(label: "fallback message", value: summary.fallbackMessage)
        }
        .padding(.vertical, 4)
    }
}

private struct DiagnosticKeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .frame(width: 128, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundColor(.primary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

private enum DiagnosticsEventParser {
    static func parseKeyValuePairs(from message: String) -> [String: String] {
        let pairs = message
            .split(separator: " ")
            .compactMap { chunk -> (String, String)? in
                let parts = chunk.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return (parts[0], parts[1])
            }

        return Dictionary(uniqueKeysWithValues: pairs)
    }

    static func buildFallbackMessage(
        scope: AIGatewayEventStatus.Scope,
        errorCode: String?,
        usedFallback: Bool,
        materialMode: String?
    ) -> String? {
        guard usedFallback else { return nil }

        switch (scope, errorCode ?? "") {
        case (.sentence, "MODEL_CONFIG_MISSING"):
            return "AI 精讲获取失败，已展示本地骨架。"
        case (.sentence, "UPSTREAM_503"), (.sentence, "UPSTREAM_TIMEOUT"), (.sentence, "NETWORK_UNAVAILABLE"):
            return "AI 精讲获取失败，已展示本地骨架。"
        case (.sentence, "INVALID_MODEL_RESPONSE"):
            return "AI 精讲获取失败，已展示本地骨架。"
        case (.sentence, _):
            return "AI 精讲获取失败，已展示本地骨架。"
        case (.passage, _) where materialMode == MaterialAnalysisMode.learningMaterial.rawValue:
            return "这份资料主要是讲义、说明或中文解析，已展示本地学习资料结构骨架。"
        case (.passage, _) where materialMode == MaterialAnalysisMode.vocabularyNotes.rawValue:
            return "这份资料主要是词汇注释或双语说明，已展示本地词汇讲义结构骨架。"
        case (.passage, _) where materialMode == MaterialAnalysisMode.questionSheet.rawValue:
            return "这份资料主要是题干、选项或答案线索，已展示本地题目结构骨架。"
        case (.passage, _) where materialMode == MaterialAnalysisMode.auxiliaryOnlyMap.rawValue:
            return "这份资料主要由辅助信息组成，已展示本地辅助资料结构骨架。"
        case (.passage, _) where materialMode == MaterialAnalysisMode.insufficientText.rawValue:
            return "当前正文不足，已展示本地结构骨架。"
        case (.passage, "MODEL_CONFIG_MISSING"):
            return "AI 地图分析暂未配置，已展示本地结构骨架。"
        case (.passage, "UPSTREAM_503"), (.passage, "UPSTREAM_TIMEOUT"), (.passage, "NETWORK_UNAVAILABLE"):
            return "AI 地图分析暂不可用，已展示本地结构骨架。"
        case (.passage, "INVALID_MODEL_RESPONSE"):
            return "AI 地图分析返回内容不可用，已展示本地结构骨架。"
        case (.passage, _):
            return "全文地图已切回本地结构骨架。"
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
        if info.skippedBecauseUnconfigured || info.fallbackUsed {
            return "本地解析"
        }
        return info.source.rawValue
    }

    private var sourceColor: Color {
        guard let info else { return .gray }
        switch info.source {
        case .ppStructureV3:    return .green
        case .legacyRemote:     return .orange
        case .legacyLocal:      return .red
        case .materialLocalFallback: return .blue
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
                        debugRow("来源", sourceLabel)
                        debugRow("阶段", stage.displayName)
                        debugRow("远端文档解析", info.documentParseEndpointConfigured ? (info.documentParseRemoteStatus ?? "configured") : "未配置")
                        debugRow("本地结果", info.fallbackUsed || info.sentenceCount > 0 || info.segmentCount > 0 ? "可用" : "不可用")
                        debugRow("跳过PP", info.skippedBecauseUnconfigured ? "true" : "false")
                        if info.skippedBecauseUnconfigured {
                            debugRow("说明", "文档解析云接口未配置，已使用本地解析。")
                        }
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
                        debugRow("结构", info.fallbackUsed ? "本地骨架" : "云端结构")
                        debugRow("状态", info.fallbackUsed || info.ppSucceeded ? "可继续学习" : stage.displayName)
                        if let d = info.parseDurationMs {
                            debugRow("耗时", "\(d)ms")
                        }
                        if let url = info.requestURL ?? info.documentParseEndpointURL {
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
