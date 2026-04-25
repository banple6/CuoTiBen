import Foundation

enum MaterialAnalysisMode: String, Codable, Equatable, Hashable {
    case passageReading
    case learningMaterial
    case vocabularyNotes
    case questionSheet
    case auxiliaryOnlyMap
    case insufficientText

    var structureTitle: String {
        switch self {
        case .passageReading:
            return "正文结构"
        case .learningMaterial:
            return "学习资料结构"
        case .vocabularyNotes:
            return "词汇讲义结构"
        case .questionSheet:
            return "题目结构"
        case .auxiliaryOnlyMap:
            return "辅助资料结构"
        case .insufficientText:
            return "文本不足结构"
        }
    }

    var statusTitle: String {
        switch self {
        case .passageReading:
            return "AI 地图分析暂不可用，已展示本地结构骨架"
        case .learningMaterial:
            return "当前按学习资料结构展示"
        case .vocabularyNotes:
            return "当前按词汇讲义结构展示"
        case .questionSheet:
            return "当前按题目结构展示"
        case .auxiliaryOnlyMap:
            return "当前按辅助资料结构展示"
        case .insufficientText:
            return "当前按文本不足结构展示"
        }
    }

    var fallbackMessage: String {
        switch self {
        case .passageReading:
            return "AI 地图分析暂不可用，已展示本地结构骨架。"
        case .learningMaterial:
            return "这份资料主要是讲义、说明或中文解析，暂不适合生成正文级思维导图。已展示本地学习资料结构骨架。"
        case .vocabularyNotes:
            return "这份资料主要是词汇注释或双语说明，暂不适合生成正文级思维导图。已展示本地词汇讲义结构骨架。"
        case .questionSheet:
            return "这份资料主要是题干、选项或答案线索，暂不适合生成正文级思维导图。已展示本地题目结构骨架。"
        case .auxiliaryOnlyMap:
            return "这份资料主要由辅助信息组成，暂不适合生成正文级思维导图。已展示本地辅助资料结构骨架。"
        case .insufficientText:
            return "当前提取到的正文不足，暂不适合生成正文级思维导图。已展示本地结构骨架。"
        }
    }

    var progressionHint: String {
        switch self {
        case .passageReading:
            return "先看背景切入，再看段落推进，最后回到全文判断。"
        case .learningMaterial:
            return "先看说明脉络，再看概念归类，最后定位辅助材料。"
        case .vocabularyNotes:
            return "先看术语或双语注释，再回到对应知识点。"
        case .questionSheet:
            return "先看题干与选项，再回到对应证据和答案线索。"
        case .auxiliaryOnlyMap:
            return "先按辅助资料分类，再决定哪些信息需要回到正文核对。"
        case .insufficientText:
            return "当前正文不足，先保留结构骨架，等待补充完整材料。"
        }
    }

    var shouldRequestRemote: Bool {
        self == .passageReading
    }
}

struct MaterialAnalysisDecision: Codable, Equatable, Hashable {
    let mode: MaterialAnalysisMode
    let rawTextLength: Int
    let sentenceDraftCount: Int
    let finalSegmentsCount: Int
    let finalSentencesCount: Int
    let passageBodyParagraphCount: Int
    let passageParagraphCount: Int
    let questionParagraphCount: Int
    let answerParagraphCount: Int
    let vocabularyParagraphCount: Int
    let learningParagraphCount: Int
    let nonPassageRatio: Double
    let averagePassageHygiene: Double
    let sourceKindDistribution: [String: Int]
    let reasons: [String]

    var primaryReason: String {
        reasons.first ?? "passageEligible"
    }
}

enum MaterialAnalysisGate {
    private static let minimumRawTextLength = 300
    private static let minimumPassageParagraphCount = 2
    private static let maximumNonPassageRatio = 0.70
    private static let minimumPassageHygiene = 0.58

    static func evaluate(
        document: SourceDocument,
        bundle: StructuredSourceBundle
    ) -> MaterialAnalysisDecision {
        let nonEmptySegments = bundle.segments.filter { !$0.text.normalizedForPassageAnalysis.isEmpty }
        let passageSegments = nonEmptySegments.filter { $0.provenance.sourceKind == .passageBody }
        let questionSegments = nonEmptySegments.filter { $0.provenance.sourceKind == .question }
        let answerSegments = nonEmptySegments.filter { $0.provenance.sourceKind == .answerKey }
        let vocabularySegments = nonEmptySegments.filter {
            $0.provenance.sourceKind == .vocabularySupport || $0.provenance.sourceKind == .bilingualNote
        }
        let learningSegments = nonEmptySegments.filter {
            $0.provenance.sourceKind == .chineseInstruction || $0.provenance.sourceKind == .passageHeading
        }

        let totalSegmentCount = max(nonEmptySegments.count, 1)
        let nonPassageCount = nonEmptySegments.count - passageSegments.count
        let nonPassageRatio = Double(max(nonPassageCount, 0)) / Double(totalSegmentCount)
        let rawTextLength = bundle.source.cleanedText.normalizedForPassageAnalysis.count
        let finalSegmentsCount = nonEmptySegments.count
        let finalSentencesCount = bundle.sentences.count
        let sentenceDraftCount = finalSentencesCount
        let sourceKindDistribution = Dictionary(
            grouping: nonEmptySegments,
            by: { $0.provenance.sourceKind.rawValue }
        ).mapValues(\.count)
        let averagePassageHygiene = passageSegments.isEmpty
            ? 0
            : passageSegments.map(\.hygiene.score).reduce(0, +) / Double(passageSegments.count)

        var reasons: [String] = []
        var blockingReasons: [String] = []
        if rawTextLength < minimumRawTextLength {
            blockingReasons.append("rawTextTooShort")
        }
        if passageSegments.count < minimumPassageParagraphCount {
            blockingReasons.append("noPassageBody")
        }
        if finalSentencesCount == 0 {
            blockingReasons.append("finalSentences=0")
        }
        if nonPassageRatio > maximumNonPassageRatio {
            blockingReasons.append("nonPassageRatioHigh")
        }
        if !passageSegments.isEmpty, averagePassageHygiene < minimumPassageHygiene {
            blockingReasons.append("lowPassageHygiene")
        }
        reasons.append(contentsOf: blockingReasons)

        let questionLikeCount = questionSegments.count + answerSegments.count
        let vocabularyLikeCount = vocabularySegments.count
        let learningLikeCount = learningSegments.count
        let questionLikeRatio = Double(questionLikeCount) / Double(totalSegmentCount)
        let vocabularyLikeRatio = Double(vocabularyLikeCount) / Double(totalSegmentCount)
        let learningLikeRatio = Double(learningLikeCount) / Double(totalSegmentCount)

        let mode: MaterialAnalysisMode
        if blockingReasons.isEmpty {
            mode = .passageReading
        } else if questionLikeCount > 0,
                  questionLikeRatio >= 0.35,
                  questionLikeCount >= max(vocabularyLikeCount, learningLikeCount) {
            reasons.append("mostlyQuestionBlocks")
            mode = .questionSheet
        } else if vocabularyLikeCount > 0,
                  vocabularyLikeRatio >= 0.30,
                  vocabularyLikeCount >= max(questionLikeCount, learningLikeCount) {
            reasons.append("mostlyVocabularyNotes")
            mode = .vocabularyNotes
        } else if learningLikeCount > 0,
                  learningLikeRatio >= 0.30 || nonPassageRatio > maximumNonPassageRatio {
            reasons.append("mostlyLearningMaterial")
            mode = .learningMaterial
        } else if learningLikeCount > 0 || questionLikeCount > 0 || vocabularyLikeCount > 0 {
            reasons.append("auxiliaryOnlyMap")
            mode = .auxiliaryOnlyMap
        } else if rawTextLength < 120 || nonEmptySegments.isEmpty {
            reasons.append("insufficientText")
            mode = .insufficientText
        } else if questionLikeCount > 0 {
            reasons.append("mostlyQuestionBlocks")
            mode = .questionSheet
        } else if vocabularyLikeCount > 0 {
            reasons.append("mostlyVocabularyNotes")
            mode = .vocabularyNotes
        } else {
            reasons.append("insufficientText")
            mode = .insufficientText
        }

        return MaterialAnalysisDecision(
            mode: mode,
            rawTextLength: rawTextLength,
            sentenceDraftCount: sentenceDraftCount,
            finalSegmentsCount: finalSegmentsCount,
            finalSentencesCount: finalSentencesCount,
            passageBodyParagraphCount: passageSegments.count,
            passageParagraphCount: passageSegments.count,
            questionParagraphCount: questionSegments.count,
            answerParagraphCount: answerSegments.count,
            vocabularyParagraphCount: vocabularySegments.count,
            learningParagraphCount: learningSegments.count,
            nonPassageRatio: nonPassageRatio,
            averagePassageHygiene: averagePassageHygiene,
            sourceKindDistribution: sourceKindDistribution,
            reasons: Array(Set(reasons)).sorted()
        )
    }
}

private extension String {
    var normalizedForPassageAnalysis: String {
        replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
