import Foundation
import NaturalLanguage

// MARK: - 文本管线验证器
// 检测反转文本、乱码、异常编码等管线输出质量问题

enum TextPipelineValidator {

    // MARK: - 反转文本检测

    /// 检测文本是否为字符级反转（如 "wen yreve etanimod" 实为 "dominate every new"）
    static func isLikelyReversedEnglish(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 8 else { return false }

        let words = cleaned.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count >= 2 && $0.rangeOfCharacter(from: .letters) != nil }

        guard words.count >= 3 else { return false }

        let forwardHits = commonEnglishWordHits(in: words)

        let reversedText = String(cleaned.reversed())
        let reversedWords = reversedText.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count >= 2 && $0.rangeOfCharacter(from: .letters) != nil }

        let reverseHits = commonEnglishWordHits(in: reversedWords)

        // 反转后常见词命中显著多于正向：判定为反转
        if reverseHits >= 3 && reverseHits > forwardHits + 1 {
            return true
        }

        // NLLanguageRecognizer 辅助判定
        if forwardHits == 0 && reverseHits >= 2 {
            let forwardConfidence = englishConfidence(for: cleaned)
            let reverseConfidence = englishConfidence(for: reversedText)
            if reverseConfidence > forwardConfidence + 0.15 {
                return true
            }
        }

        return false
    }

    /// 修复反转文本：整体字符反转
    static func repairReversedText(_ text: String) -> String {
        String(text.reversed())
    }

    /// 对文本做反转检测，如果检测到反转则自动修复；否则原样返回
    static func validateAndRepairIfReversed(_ text: String) -> (text: String, wasRepaired: Bool) {
        guard isLikelyReversedEnglish(text) else {
            return (text, false)
        }
        let repaired = repairReversedText(text)
        return (repaired, true)
    }

    // MARK: - 文本质量评估

    struct TextQualityReport: CustomStringConvertible {
        let originalText: String
        let isReversed: Bool
        let repairedText: String?
        let englishWordRatio: Double
        let commonWordHits: Int
        let languageConfidence: Double
        let detectedLanguage: String
        let hasSuspiciousPatterns: Bool

        var isHealthy: Bool {
            !isReversed && !hasSuspiciousPatterns && englishWordRatio > 0.3
        }

        var description: String {
            var parts: [String] = []
            parts.append("质量:\(isHealthy ? "✅正常" : "⚠️异常")")
            if isReversed { parts.append("反转:已检测") }
            if hasSuspiciousPatterns { parts.append("异常模式:已检测") }
            parts.append("英文词比:\(String(format: "%.0f%%", englishWordRatio * 100))")
            parts.append("常见词:\(commonWordHits)")
            parts.append("语言:\(detectedLanguage)(\(String(format: "%.0f%%", languageConfidence * 100)))")
            return parts.joined(separator: " | ")
        }
    }

    /// 全面评估文本质量
    static func assessQuality(of text: String) -> TextQualityReport {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = cleaned.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count >= 2 && $0.rangeOfCharacter(from: .letters) != nil }

        let totalWords = max(words.count, 1)
        let englishWords = words.filter { isLikelyEnglishWord($0) }
        let englishWordRatio = Double(englishWords.count) / Double(totalWords)
        let hits = commonEnglishWordHits(in: words)
        let reversed = isLikelyReversedEnglish(cleaned)
        let repaired = reversed ? repairReversedText(cleaned) : nil
        let confidence = englishConfidence(for: cleaned)
        let language = detectedLanguageCode(for: cleaned)
        let suspicious = hasSuspiciousPatterns(cleaned)

        return TextQualityReport(
            originalText: String(cleaned.prefix(120)),
            isReversed: reversed,
            repairedText: repaired.map { String($0.prefix(120)) },
            englishWordRatio: englishWordRatio,
            commonWordHits: hits,
            languageConfidence: confidence,
            detectedLanguage: language,
            hasSuspiciousPatterns: suspicious
        )
    }

    // MARK: - 中文乱码检测

    /// 检测文本是否包含中文乱码特征（非CJK但被错误编码的字符）
    static func hasChineseGarbledText(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }

        // 检测大量不常见 Unicode 区段字符
        let suspiciousCount = cleaned.unicodeScalars.filter { scalar in
            // CJK兼容象形文字、私用区、代替字符
            (0xF900...0xFAFF).contains(scalar.value) ||
            (0xE000...0xF8FF).contains(scalar.value) ||
            scalar.value == 0xFFFD
        }.count

        return suspiciousCount > max(cleaned.count / 5, 2)
    }

    // MARK: - Private

    private static let highFrequencyEnglishWords: Set<String> = [
        "the", "be", "to", "of", "and", "a", "in", "that", "have", "i",
        "it", "for", "not", "on", "with", "he", "as", "you", "do", "at",
        "this", "but", "his", "by", "from", "they", "we", "say", "her", "she",
        "or", "an", "will", "my", "one", "all", "would", "there", "their",
        "what", "so", "up", "out", "if", "about", "who", "get", "which", "go",
        "me", "when", "make", "can", "like", "time", "no", "just", "him",
        "know", "take", "people", "into", "year", "your", "good", "some",
        "could", "them", "see", "other", "than", "then", "now", "look",
        "only", "come", "its", "over", "think", "also", "back", "after",
        "use", "two", "how", "our", "work", "first", "well", "way", "even",
        "new", "want", "because", "any", "these", "give", "day", "most", "us",
        "is", "are", "was", "were", "been", "being", "has", "had", "did",
        "does", "doing", "each", "every", "both", "few", "more", "many",
        "such", "very", "much", "own", "same", "still", "should", "must",
        "may", "might", "shall", "need", "here", "through", "between"
    ]

    private static func commonEnglishWordHits(in words: [String]) -> Int {
        words.filter { highFrequencyEnglishWords.contains($0) }.count
    }

    private static func isLikelyEnglishWord(_ word: String) -> Bool {
        let cleaned = word.lowercased()
        guard cleaned.count >= 2 else { return false }

        // 至少包含一个元音
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        let hasVowel = cleaned.contains(where: { vowels.contains($0) })

        // 全部为 ASCII 字母
        let allASCIILetters = cleaned.allSatisfy { $0.isASCII && $0.isLetter }

        return hasVowel && allASCIILetters
    }

    private static func englishConfidence(for text: String) -> Double {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.languageHypotheses(withMaximum: 3)[.english] ?? 0
    }

    private static func detectedLanguageCode(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "unknown"
    }

    private static func hasSuspiciousPatterns(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 6 else { return false }

        // 检测连续重复字符 (如 "aaaa" or "////")
        let repetitionPattern = #"(.)\1{4,}"#
        if cleaned.range(of: repetitionPattern, options: .regularExpression) != nil {
            return true
        }

        // 检测大量不可打印字符
        let controlCharCount = cleaned.unicodeScalars.filter {
            CharacterSet.controlCharacters.contains($0) && $0.value != 0x0A && $0.value != 0x0D
        }.count
        if controlCharCount > max(cleaned.count / 10, 2) {
            return true
        }

        return false
    }
}

// MARK: - 管线诊断日志

enum TextPipelineDiagnostics {
    struct PipelineEvent {
        let stage: String
        let message: String
        let timestamp: Date
        let severity: Severity

        enum Severity: String {
            case info = "ℹ️"
            case warning = "⚠️"
            case error = "❌"
            case repaired = "🔧"
        }
    }

    private static var events: [PipelineEvent] = []
    private static let maxEvents = 200

    static func log(_ stage: String, _ message: String, severity: PipelineEvent.Severity = .info) {
        let event = PipelineEvent(stage: stage, message: message, timestamp: Date(), severity: severity)
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        #if DEBUG
        print("[TextPipeline|\(severity.rawValue)|\(stage)] \(message)")
        #endif
    }

    static func recentEvents(limit: Int = 50) -> [PipelineEvent] {
        Array(events.suffix(limit))
    }

    static func clearEvents() {
        events.removeAll()
    }

    static func formattedLog(limit: Int = 30) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"

        return recentEvents(limit: limit).map { event in
            "\(formatter.string(from: event.timestamp)) \(event.severity.rawValue) [\(event.stage)] \(event.message)"
        }.joined(separator: "\n")
    }
}
