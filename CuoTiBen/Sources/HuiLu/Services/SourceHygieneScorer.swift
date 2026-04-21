import Foundation

struct SourceHygieneEvaluation {
    let score: Double
    let reasons: [String]
    let snapshot: SourceHygieneSnapshot
}

enum SourceHygieneScorer {
    static func evaluate(
        text: String,
        sourceKind: SourceContentKind,
        ocrConfidence: Double,
        reversedRepaired: Bool,
        hasMixedContamination: Bool,
        chineseRatio: Double,
        englishRatio: Double,
        blockTypes: [NormalizedBlockType] = [],
        zoneRole: DocumentZoneRole? = nil
    ) -> SourceHygieneEvaluation {
        let normalizedText = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = normalizedText.lowercased()

        var score = baselineScore(for: sourceKind)
        var reasons: [String] = []
        var flags: [String] = []

        if normalizedText.isEmpty {
            score = min(score, 0.05)
            reasons.append("文本为空，无法作为稳定来源。")
            flags.append("empty_text")
        }

        if normalizedText.count < 12 {
            score -= 0.18
            reasons.append("文本过短，正文承载不足。")
            flags.append("too_short")
        } else if normalizedText.count > 1400 {
            score -= 0.08
            reasons.append("文本过长，可能混入多个材料块。")
            flags.append("too_long")
        }

        if reversedRepaired {
            score -= 0.1
            reasons.append("文本曾经过反转修复，可靠性下调。")
            flags.append("reversed_repaired")
        }

        if hasMixedContamination {
            score -= 0.2
            reasons.append("检测到中英混杂或讲义污染。")
            flags.append("mixed_contamination")
        }

        if containsReversedEnglish(normalizedText) {
            score -= 0.18
            reasons.append("存在明显反转英文片段。")
            flags.append("reversed_english")
        }

        if containsLikelyGarbage(normalizedText) {
            score -= 0.22
            reasons.append("文本包含乱码或异常符号堆积。")
            flags.append("garbage")
        }

        if englishRatio >= 0.62, sourceKind == .passageBody {
            score += 0.08
            reasons.append("英文正文占比稳定，可作为主线来源。")
        } else if englishRatio < 0.42, sourceKind == .passageBody {
            score -= 0.14
            reasons.append("英文占比偏低，不像稳定正文。")
            flags.append("low_english_ratio")
        }

        if chineseRatio >= 0.28, sourceKind == .passageBody {
            score -= min((chineseRatio - 0.28) * 0.7, 0.2)
            reasons.append("中文占比偏高，正文纯度不足。")
            flags.append("high_chinese_ratio")
        }

        if ocrConfidence < 0.72 {
            score -= min((0.72 - ocrConfidence) * 0.5, 0.18)
            reasons.append("OCR 置信度偏低。")
            flags.append("low_ocr_confidence")
        }

        if sourceKind == .chineseInstruction || zoneRole == .metaInstruction {
            score -= 0.22
            reasons.append("这是中文说明块，不应直接进入正文主线。")
            flags.append("instructional")
        }

        if sourceKind == .bilingualNote {
            score -= 0.2
            reasons.append("这是双语注释块，适合辅助层。")
            flags.append("bilingual_note")
        }

        if sourceKind == .question || sourceKind == .answerKey || sourceKind == .vocabularySupport {
            score -= 0.24
            reasons.append("这是题目/答案/词汇支持区，不应充当正文主分支。")
            flags.append("auxiliary_source")
        }

        if sourceKind == .noise || zoneRole == .unknown {
            score -= 0.28
            reasons.append("来源噪声较重，建议拒绝进入主导图。")
            flags.append("noise")
        }

        if containsInstructionVocabulary(lowercased) {
            score -= 0.18
            reasons.append("文本带有明显题目或讲义指令词。")
            flags.append("instruction_vocabulary")
        }

        if containsAnswerVocabulary(lowercased) {
            score -= 0.12
            reasons.append("文本带有答案区特征词。")
            flags.append("answer_vocabulary")
        }

        let finalScore = min(max(score, 0.02), 0.99)
        let snapshot = SourceHygieneSnapshot(
            score: finalScore,
            reversedRepaired: reversedRepaired,
            hasMixedContamination: hasMixedContamination,
            chineseRatio: chineseRatio,
            englishRatio: englishRatio,
            ocrConfidence: ocrConfidence,
            flags: Array(Set(flags)).sorted()
        )

        return SourceHygieneEvaluation(
            score: finalScore,
            reasons: Array(Set(reasons)).sorted(),
            snapshot: snapshot
        )
    }

    private static func baselineScore(for sourceKind: SourceContentKind) -> Double {
        switch sourceKind {
        case .passageBody:
            return 0.82
        case .passageHeading:
            return 0.64
        case .question, .answerKey, .vocabularySupport:
            return 0.46
        case .chineseInstruction:
            return 0.38
        case .bilingualNote:
            return 0.42
        case .noise:
            return 0.18
        case .synthetic:
            return 0.58
        case .unknown:
            return 0.5
        }
    }

    private static func containsReversedEnglish(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        return compact.contains("eht") || compact.contains("dna") || compact.contains("fo") || compact.contains("si")
    }

    private static func containsLikelyGarbage(_ text: String) -> Bool {
        text.range(of: #"([#@*_=]{4,}|[�]{2,})"#, options: .regularExpression) != nil
    }

    private static func containsInstructionVocabulary(_ lowercased: String) -> Bool {
        let markers = [
            "answer the questions", "choose the correct", "questions 1-", "true false not given",
            "开始做题", "选出", "题目", "对照答案", "请判断", "将下列"
        ]
        return markers.contains(where: lowercased.contains)
    }

    private static func containsAnswerVocabulary(_ lowercased: String) -> Bool {
        let markers = [
            "answer key", "correct answer", "参考答案", "答案区", "答案：", "解析："
        ]
        return markers.contains(where: lowercased.contains)
    }
}
