import Foundation

struct ValidatedParagraphNodeContent {
    let anchorSentenceID: String?
    let title: String
    let summary: String
    let consistencyScore: Double
}

struct ValidatedSentenceNodeContent {
    let title: String
    let summary: String
    let consistencyScore: Double
}

enum AnchorConsistencyValidator {
    static func validatedCoreSentenceID(
        preferred: String?,
        sentences: [Sentence]
    ) -> String? {
        let sentenceIDs = Set(sentences.map(\.id))
        if let preferred, sentenceIDs.contains(preferred) {
            return preferred
        }
        return sentences.first?.id
    }

    static func validatedParagraphNodeContent(
        card: ParagraphTeachingCard,
        sentences: [Sentence],
        proposedTitle: String,
        proposedSummary: String
    ) -> ValidatedParagraphNodeContent {
        let anchorSentenceID = validatedCoreSentenceID(preferred: card.coreSentenceID, sentences: sentences)
        let fallbackTitle = fallbackParagraphTitle(card: card)
        let fallbackSummary = fallbackParagraphSummary(card: card)
        let consistencyScore = paragraphConsistencyScore(
            card: card,
            sentences: sentences,
            proposedTitle: proposedTitle,
            proposedSummary: proposedSummary,
            fallbackTitle: fallbackTitle,
            fallbackSummary: fallbackSummary
        )

        let title = consistencyScore >= 0.62 && isReadableMindMapTitle(proposedTitle)
            ? proposedTitle
            : fallbackTitle
        let summary = consistencyScore >= 0.62 && isReadableMindMapSummary(proposedSummary)
            ? proposedSummary
            : fallbackSummary

        return ValidatedParagraphNodeContent(
            anchorSentenceID: anchorSentenceID,
            title: title,
            summary: summary,
            consistencyScore: consistencyScore
        )
    }

    static func validatedFocusNodeContent(
        card: ParagraphTeachingCard,
        sentences: [Sentence],
        proposedTitle: String,
        proposedSummary: String
    ) -> ValidatedParagraphNodeContent {
        let anchorSentenceID = validatedCoreSentenceID(preferred: card.coreSentenceID, sentences: sentences)
        let fallbackTitle = fallbackFocusTitle(card: card)
        let fallbackSummary = fallbackFocusSummary(card: card)
        let consistencyScore = paragraphConsistencyScore(
            card: card,
            sentences: sentences,
            proposedTitle: proposedTitle,
            proposedSummary: proposedSummary,
            fallbackTitle: fallbackTitle,
            fallbackSummary: fallbackSummary
        )

        let title = consistencyScore >= 0.6 && isReadableMindMapTitle(proposedTitle)
            ? proposedTitle
            : fallbackTitle
        let summary = consistencyScore >= 0.6 && isReadableMindMapSummary(proposedSummary)
            ? proposedSummary
            : fallbackSummary

        return ValidatedParagraphNodeContent(
            anchorSentenceID: anchorSentenceID,
            title: title,
            summary: summary,
            consistencyScore: consistencyScore
        )
    }

    static func validatedSentenceNodeContent(
        sentence: Sentence,
        analysis: ProfessorSentenceAnalysis?,
        proposedTitle: String,
        proposedSummary: String
    ) -> ValidatedSentenceNodeContent {
        let analysisIsReliable = isReliableAnalysis(analysis, for: sentence)
        let fallbackTitle = fallbackSentenceTitle(sentence: sentence, analysis: analysisIsReliable ? analysis : nil)
        let fallbackSummary = fallbackSentenceSummary(sentence: sentence, analysis: analysisIsReliable ? analysis : nil)
        let consistencyScore = sentenceConsistencyScore(
            sentence: sentence,
            analysis: analysis,
            proposedTitle: proposedTitle,
            proposedSummary: proposedSummary,
            fallbackTitle: fallbackTitle,
            fallbackSummary: fallbackSummary
        )

        let title = consistencyScore >= 0.62 && isReadableMindMapTitle(proposedTitle)
            ? proposedTitle
            : fallbackTitle
        let summary = consistencyScore >= 0.62 && isReadableMindMapSummary(proposedSummary)
            ? proposedSummary
            : fallbackSummary

        return ValidatedSentenceNodeContent(
            title: title,
            summary: summary,
            consistencyScore: consistencyScore
        )
    }

    private static func paragraphConsistencyScore(
        card: ParagraphTeachingCard,
        sentences: [Sentence],
        proposedTitle: String,
        proposedSummary: String,
        fallbackTitle: String,
        fallbackSummary: String
    ) -> Double {
        let anchorSentenceID = validatedCoreSentenceID(preferred: card.coreSentenceID, sentences: sentences)
        let paragraphText = sentences.map(\.text).joined(separator: " ")
        let avgHygiene = sentences.isEmpty
            ? 0.5
            : sentences.map(\.hygiene.score).reduce(0, +) / Double(sentences.count)
        let pollutedSentenceCount = sentences.filter { isPollutedSourceKind($0.provenance.sourceKind) }.count

        var score = 0.0
        if anchorSentenceID != nil {
            score += 0.28
        }
        if avgHygiene >= 0.78 {
            score += 0.2
        } else if avgHygiene >= 0.62 {
            score += 0.12
        } else if avgHygiene >= 0.48 {
            score += 0.05
        }
        if pollutedSentenceCount > 0 {
            score -= min(Double(pollutedSentenceCount) * 0.1, 0.22)
        }
        if !card.displayedTheme.isEmpty && isChineseDominant(card.displayedTheme) {
            score += 0.12
        }

        let titleOverlap = max(
            textTokenOverlap(lhs: proposedTitle, rhs: fallbackTitle),
            textTokenOverlap(lhs: proposedTitle, rhs: card.displayedTheme),
            textTokenOverlap(lhs: proposedTitle, rhs: card.displayedTeachingFocuses.first ?? "")
        )
        if titleOverlap >= 0.42 || sameSentenceLead(lhs: proposedTitle, rhs: fallbackTitle) {
            score += 0.16
        } else if titleOverlap >= 0.22 {
            score += 0.08
        }

        let summaryOverlap = max(
            textTokenOverlap(lhs: proposedSummary, rhs: fallbackSummary),
            textTokenOverlap(lhs: proposedSummary, rhs: card.displayedTeachingFocuses.first ?? ""),
            textTokenOverlap(lhs: proposedSummary, rhs: card.displayedExamValue),
            textTokenOverlap(lhs: proposedSummary, rhs: card.displayedStudentBlindSpot ?? "")
        )
        if summaryOverlap >= 0.34 {
            score += 0.16
        } else if summaryOverlap >= 0.18 {
            score += 0.08
        }

        let keywordScore = englishTokenOverlap(
            lhs: card.keywords.joined(separator: " "),
            rhs: paragraphText
        )
        if keywordScore >= 0.16 || card.keywords.isEmpty {
            score += 0.08
        }

        return min(max(score, 0.12), 0.98)
    }

    private static func sentenceConsistencyScore(
        sentence: Sentence,
        analysis: ProfessorSentenceAnalysis?,
        proposedTitle: String,
        proposedSummary: String,
        fallbackTitle: String,
        fallbackSummary: String
    ) -> Double {
        let reliableAnalysis = isReliableAnalysis(analysis, for: sentence)
        var score = reliableAnalysis ? 0.48 : 0.18

        if sentence.hygiene.score >= 0.78 {
            score += 0.18
        } else if sentence.hygiene.score >= 0.62 {
            score += 0.12
        } else if sentence.hygiene.score >= 0.48 {
            score += 0.06
        }

        if isPollutedSourceKind(sentence.provenance.sourceKind) {
            score -= 0.18
        }

        let titleOverlap = textTokenOverlap(lhs: proposedTitle, rhs: fallbackTitle)
        if titleOverlap >= 0.35 || sameSentenceLead(lhs: proposedTitle, rhs: fallbackTitle) {
            score += 0.12
        } else if isReadableMindMapTitle(proposedTitle) {
            score += 0.06
        }

        let summaryOverlap = max(
            textTokenOverlap(lhs: proposedSummary, rhs: fallbackSummary),
            textTokenOverlap(lhs: proposedSummary, rhs: analysis?.renderedFaithfulTranslation ?? ""),
            textTokenOverlap(lhs: proposedSummary, rhs: analysis?.renderedTeachingInterpretation ?? "")
        )
        if summaryOverlap >= 0.3 {
            score += 0.12
        } else if summaryOverlap >= 0.16 {
            score += 0.06
        }

        return min(max(score, 0.08), 0.98)
    }

    private static func isReliableAnalysis(
        _ analysis: ProfessorSentenceAnalysis?,
        for sentence: Sentence
    ) -> Bool {
        guard let analysis else { return false }
        guard !isPollutedSourceKind(sentence.provenance.sourceKind) else { return false }

        let source = normalizedEnglishSource(sentence.text)
        let original = normalizedEnglishSource(analysis.originalSentence)
        if !original.isEmpty, englishTokenOverlap(lhs: original, rhs: source) < 0.42 {
            return false
        }

        let faithful = trimmed(analysis.renderedFaithfulTranslation)
        let teaching = trimmed(analysis.renderedTeachingInterpretation)
        if faithful.isEmpty && teaching.isEmpty {
            return false
        }

        return sentence.hygiene.score >= 0.42
    }

    private static func isPollutedSourceKind(_ kind: SourceContentKind) -> Bool {
        switch kind {
        case .chineseExplanation, .bilingualAnnotation, .questionSupport, .answerSupport, .polluted:
            return true
        case .passageBody, .passageHeading, .synthetic, .unknown:
            return false
        }
    }

    private static func fallbackParagraphTitle(card: ParagraphTeachingCard) -> String {
        let theme = trimmed(card.displayedTheme)
        if !theme.isEmpty {
            return "第\(card.paragraphIndex + 1)段｜\(truncate(theme, limit: 16))"
        }
        return "第\(card.paragraphIndex + 1)段｜\(card.argumentRole.displayName)"
    }

    private static func fallbackParagraphSummary(card: ParagraphTeachingCard) -> String {
        if let firstFocus = card.displayedTeachingFocuses.first {
            return truncate(firstFocus, limit: 30)
        }
        let examValue = trimmed(card.displayedExamValue)
        if !examValue.isEmpty {
            return truncate(examValue, limit: 30)
        }
        return truncate(card.argumentRole.teachingDescription, limit: 30)
    }

    private static func fallbackFocusTitle(card: ParagraphTeachingCard) -> String {
        if let firstFocus = card.displayedTeachingFocuses.first {
            return "教学重点｜\(truncate(firstFocus, limit: 16))"
        }
        return "教学重点｜\(card.argumentRole.displayName)"
    }

    private static func fallbackFocusSummary(card: ParagraphTeachingCard) -> String {
        if let blindSpot = trimmed(card.displayedStudentBlindSpot ?? "").nonEmpty {
            return truncate("别读偏：\(blindSpot)", limit: 26)
        }
        let examValue = trimmed(card.displayedExamValue)
        if !examValue.isEmpty {
            return truncate(examValue, limit: 26)
        }
        return truncate(card.argumentRole.teachingDescription, limit: 26)
    }

    private static func fallbackSentenceTitle(
        sentence: Sentence,
        analysis: ProfessorSentenceAnalysis?
    ) -> String {
        if let analysis,
           let roleLabel = professorSentenceRolePresentation(for: analysis.evidenceType)?.label,
           !trimmed(roleLabel).isEmpty {
            return "第\(sentence.localIndex + 1)句｜\(truncate(roleLabel, limit: 8))"
        }

        let sentenceFunctionHead = analysis?.renderedSentenceFunction
            .split(separator: "：", maxSplits: 1)
            .first
            .map(String.init)
            .map { trimmed($0) } ?? ""
        if !sentenceFunctionHead.isEmpty {
            return "第\(sentence.localIndex + 1)句｜\(truncate(sentenceFunctionHead, limit: 8))"
        }

        return "第\(sentence.localIndex + 1)句关键句"
    }

    private static func fallbackSentenceSummary(
        sentence: Sentence,
        analysis: ProfessorSentenceAnalysis?
    ) -> String {
        if let analysis {
            let faithful = trimmed(analysis.renderedFaithfulTranslation)
            if !faithful.isEmpty {
                return truncate(faithful, limit: 30)
            }

            let teaching = trimmed(analysis.renderedTeachingInterpretation)
            if !teaching.isEmpty {
                return truncate(teaching, limit: 30)
            }
        }

        return truncate(trimmed(sentence.text), limit: 36)
    }

    private static func isReadableMindMapTitle(_ value: String) -> Bool {
        let normalized = trimmed(value)
        guard !normalized.isEmpty else { return false }
        if normalized.count > 26 { return false }
        if containsDenseSeparators(normalized) { return false }
        if normalized.contains("本段主要讲") || normalized.contains("文章主要讲") {
            return false
        }
        return true
    }

    private static func isReadableMindMapSummary(_ value: String) -> Bool {
        let normalized = trimmed(value)
        guard !normalized.isEmpty else { return false }
        if normalized.count > 40 { return false }
        if containsDenseSeparators(normalized) { return false }
        if normalized.contains("本段主要讲") || normalized.contains("文章主要讲") {
            return false
        }
        return true
    }

    private static func containsDenseSeparators(_ value: String) -> Bool {
        let separatorCount = value.filter { "｜；/".contains($0) }.count
        return separatorCount >= 3
    }

    private static func truncate(_ value: String, limit: Int) -> String {
        let normalized = trimmed(value)
        guard !normalized.isEmpty, normalized.count > limit else { return normalized }
        return String(normalized.prefix(max(limit - 1, 0))) + "…"
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedEnglishSource(_ value: String) -> String {
        trimmed(value)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func englishTokenOverlap(lhs: String, rhs: String) -> Double {
        let left = englishTokenSet(from: lhs)
        let right = englishTokenSet(from: rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        return Double(left.intersection(right).count) / Double(max(left.count, right.count))
    }

    private static func textTokenOverlap(lhs: String, rhs: String) -> Double {
        let left = normalizedTokenSet(from: lhs)
        let right = normalizedTokenSet(from: rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        return Double(left.intersection(right).count) / Double(max(left.count, right.count))
    }

    private static func englishTokenSet(from text: String) -> Set<String> {
        Set(
            text
                .lowercased()
                .components(separatedBy: CharacterSet.letters.inverted)
                .filter { !$0.isEmpty && $0.count >= 2 }
        )
    }

    private static func normalizedTokenSet(from text: String) -> Set<String> {
        let normalized = trimmed(text)
        guard !normalized.isEmpty else { return [] }

        var tokens = englishTokenSet(from: normalized)
        let chineseRuns = regexMatches(in: normalized, pattern: #"[\u4e00-\u9fff]{2,}"#)
        for run in chineseRuns {
            let chars = Array(run)
            if chars.count <= 4 {
                tokens.insert(run)
            }
            if chars.count >= 2 {
                for index in 0..<(chars.count - 1) {
                    tokens.insert(String(chars[index...min(index + 1, chars.count - 1)]))
                }
            }
        }
        return tokens
    }

    private static func sameSentenceLead(lhs: String, rhs: String) -> Bool {
        let left = trimmed(lhs).split(separator: "｜", maxSplits: 1).first.map(String.init) ?? ""
        let right = trimmed(rhs).split(separator: "｜", maxSplits: 1).first.map(String.init) ?? ""
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right
    }

    private static func isChineseDominant(_ value: String) -> Bool {
        let normalized = trimmed(value)
        guard !normalized.isEmpty else { return false }

        let chineseCount = normalized.unicodeScalars.filter { scalar in
            scalar.value >= 0x4E00 && scalar.value <= 0x9FFF
        }.count
        let latinCount = normalized.unicodeScalars.filter { scalar in
            (scalar.value >= 0x41 && scalar.value <= 0x5A) ||
            (scalar.value >= 0x61 && scalar.value <= 0x7A)
        }.count

        return chineseCount >= max(6, latinCount * 2)
    }
}

private extension String {
    var nonEmpty: String? {
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

private func regexMatches(in text: String, pattern: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.matches(in: text, range: range).compactMap { match in
        guard let matchRange = Range(match.range, in: text) else { return nil }
        return String(text[matchRange])
    }
}
