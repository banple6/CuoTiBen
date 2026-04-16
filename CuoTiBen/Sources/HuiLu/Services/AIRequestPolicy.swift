import Foundation

enum AIAnalysisTrigger: String {
    case `import` = "import"
    case openProfessorView = "openProfessorView"
    case openReviewWorkbench = "openReviewWorkbench"
    case tapSentence = "tapSentence"
    case forceRefresh = "forceRefresh"
}

enum AIEnrichmentMode: String {
    case disabledOnImport = "disabledOnImport"
    case lazy = "lazy"
    case force = "force"
}

enum LegacyRemoteParseFallbackMode: String {
    case always = "always"
    case qualityGated = "qualityGated"
    case disabled = "disabled"
}

struct AIRequestPolicy {
    var autoProfessorAnalysisOnImport = false
    var enableSentenceExplainDiskCache = true
    var enableProfessorAnalysisDiskCache = true
    var legacyRemoteParseFallbackMode: LegacyRemoteParseFallbackMode = .qualityGated

    static let `default` = AIRequestPolicy()

    func professorEnrichmentMode(
        for trigger: AIAnalysisTrigger,
        force: Bool = false
    ) -> AIEnrichmentMode {
        if force || trigger == .forceRefresh {
            return .force
        }

        switch trigger {
        case .openProfessorView, .openReviewWorkbench:
            return .lazy
        case .`import`, .tapSentence:
            return .disabledOnImport
        case .forceRefresh:
            return .force
        }
    }

    func shouldAttemptProfessorAnalysis(
        for trigger: AIAnalysisTrigger,
        force: Bool = false
    ) -> Bool {
        professorEnrichmentMode(for: trigger, force: force) != .disabledOnImport
    }

    func shouldAllowLegacyRemoteParse(
        for report: StructuredSourceQualityReport,
        forceRemote: Bool = false
    ) -> Bool {
        if forceRemote {
            return true
        }

        switch legacyRemoteParseFallbackMode {
        case .always:
            return true
        case .qualityGated:
            return report.isTooWeakForLocalOnly
        case .disabled:
            return false
        }
    }
}
