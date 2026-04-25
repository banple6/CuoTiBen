import SwiftUI

struct CloudRequestDiagnosticsView: View {
    @State private var results: [CloudRequestProbeResult.Scope: CloudRequestProbeResult] = [:]
    @State private var runningScopes: Set<CloudRequestProbeResult.Scope> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                probeButton(title: "Health", scope: .health) {
                    await CloudRequestProbeService.runHealthProbe()
                }
                probeButton(title: "Explain", scope: .explainSentence) {
                    await CloudRequestProbeService.runExplainProbe()
                }
                probeButton(title: "Analyze", scope: .analyzePassage) {
                    await CloudRequestProbeService.runAnalyzeProbe()
                }
            }

            ForEach(CloudRequestProbeResult.Scope.allCases, id: \.self) { scope in
                CloudProbeResultRow(
                    scope: scope,
                    result: results[scope],
                    isRunning: runningScopes.contains(scope)
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func probeButton(
        title: String,
        scope: CloudRequestProbeResult.Scope,
        action: @escaping () async -> CloudRequestProbeResult
    ) -> some View {
        Button {
            Task {
                runningScopes.insert(scope)
                let result = await action()
                results[scope] = result
                runningScopes.remove(scope)
            }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .disabled(runningScopes.contains(scope))
    }
}

private struct CloudProbeResultRow: View {
    let scope: CloudRequestProbeResult.Scope
    let result: CloudRequestProbeResult?
    let isRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(scope.displayName)
                    .font(.caption.monospaced().weight(.semibold))
                Spacer()
                Text(isRunning ? "running" : (result?.statusText ?? "not_run"))
                    .font(.caption.monospaced())
                    .foregroundColor(statusColor)
            }

            if let result {
                DiagnosticProbeRow(label: "endpoint", value: result.endpoint)
                DiagnosticProbeRow(label: "request_id", value: result.requestID ?? "nil")
                DiagnosticProbeRow(label: "error_code", value: result.errorCode ?? "nil")
                DiagnosticProbeRow(label: "retryable", value: result.retryable.map { $0 ? "true" : "false" } ?? "nil")
                DiagnosticProbeRow(label: "fallback_available", value: result.fallbackAvailable.map { $0 ? "true" : "false" } ?? "nil")
                DiagnosticProbeRow(label: "used_fallback", value: result.usedFallback.map { $0 ? "true" : "false" } ?? "nil")
                DiagnosticProbeRow(label: "latency", value: "\(result.latencyMs)ms")
                DiagnosticProbeRow(label: "identity_complete", value: result.identityComplete ? "true" : "false")
                DiagnosticProbeRow(label: "missing_fields", value: result.missingFields.isEmpty ? "[]" : result.missingFields.joined(separator: ", "))
                if let message = result.message, !message.isEmpty {
                    DiagnosticProbeRow(label: "message", value: message)
                }
            } else {
                Text("手动点击探针，不会自动频繁请求云端。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        guard let status = result?.httpStatus else {
            return isRunning ? .blue : .secondary
        }
        return (200..<300).contains(status) ? .green : .orange
    }
}

private struct DiagnosticProbeRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
                .frame(width: 112, alignment: .leading)
            Text(value)
                .font(.caption2.monospaced())
                .foregroundColor(.primary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
