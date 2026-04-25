import Foundation

struct RuntimeBuildFingerprint: Equatable {
    let gitSHA: String
    let branchName: String
    let buildTime: String
    let appConfiguration: String
    let aiBackendBaseURL: String
    let documentParseEndpointStatus: String
    let isDebugBuild: Bool

    private static let sourceGitSHA = "d8992416c22e634e9c906ee80377a1c1f67dca7a"
    private static let sourceBranchName = "codex/ai-core-rebuild"
    private static let sourceGeneratedAt = "2026-04-25T07:07:30Z"

    private static var didLogLaunchFingerprint = false

    static var current: RuntimeBuildFingerprint {
        let route = DocumentParseEndpointConfig.snapshot
        let endpointStatus = route.isConfigured
            ? (route.endpointURL?.absoluteString ?? "configured")
            : "unconfigured"

        return RuntimeBuildFingerprint(
            gitSHA: infoString("GIT_SHA") ?? infoString("GitSHA") ?? sourceGitSHA,
            branchName: infoString("GIT_BRANCH") ?? infoString("GitBranch") ?? sourceBranchName,
            buildTime: executableBuildTime() ?? infoString("BUILD_TIME") ?? sourceGeneratedAt,
            appConfiguration: infoString("APP_CONFIGURATION") ?? defaultConfiguration,
            aiBackendBaseURL: AIBackendConfig.resolvedBaseURL.isEmpty ? "unconfigured" : AIBackendConfig.resolvedBaseURL,
            documentParseEndpointStatus: endpointStatus,
            isDebugBuild: isDebug
        )
    }

    static func logAtLaunch() {
        guard !didLogLaunchFingerprint else { return }
        didLogLaunchFingerprint = true

        let fingerprint = current
        let lines = [
            "[Build] git_sha=\(fingerprint.gitSHA)",
            "[Build] branch=\(fingerprint.branchName)",
            "[Build] build_time=\(fingerprint.buildTime)",
            "[Build] configuration=\(fingerprint.appConfiguration)",
            "[Build] app_configuration=\(fingerprint.appConfiguration)",
            "[Build] ai_backend_base_url=\(fingerprint.aiBackendBaseURL)",
            "[Build] ai_backend=\(fingerprint.aiBackendBaseURL)",
            "[Build] document_parse_endpoint=\(fingerprint.documentParseEndpointStatus)",
            "[Build] is_debug_build=\(fingerprint.isDebugBuild)"
        ]

        for line in lines {
            print(line)
            TextPipelineDiagnostics.log("Build", line, severity: .info)
        }
    }

    private static func infoString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func executableBuildTime() -> String? {
        guard let executableURL = Bundle.main.executableURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: executableURL.path),
              let modificationDate = attributes[.modificationDate] as? Date
        else {
            return nil
        }
        return iso8601Formatter.string(from: modificationDate)
    }

    private static var defaultConfiguration: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }

    private static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
