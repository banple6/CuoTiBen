import Foundation

struct ValidatedParagraphNodeContent {
    let anchorSentenceID: String?
    let title: String
    let summary: String
}

struct ValidatedSentenceNodeContent {
    let title: String
    let summary: String
}

enum AnchorConsistencyValidator {
    nonisolated static func validatedCoreSentenceID(
        preferred: String?,
        sentences: [Sentence]
    ) -> String? {
        let sentenceIDs = Set(sentences.map(\.id))
        if let preferred, sentenceIDs.contains(preferred) {
            return preferred
        }
        return sentences.first?.id
    }

    nonisolated static func validatedParagraphNodeContent(
        card: ParagraphTeachingCard,
        sentences: [Sentence],
        proposedTitle: String,
        proposedSummary: String
    ) -> ValidatedParagraphNodeContent {
        let anchorSentenceID = validatedCoreSentenceID(preferred: card.coreSentenceID, sentences: sentences)
        let fallbackTitle = fallbackParagraphTitle(card: card)
        let fallbackSummary = fallbackParagraphSummary(card: card)
        let reliability = paragraphReliabilityScore(card: card, sentences: sentences)

        let title = reliability >= 2 && isReadableMindMapTitle(proposedTitle)
            ? proposedTitle
            : fallbackTitle
        let summary = reliability >= 2 && isReadableMindMapSummary(proposedSummary)
            ? proposedSummary
            : fallbackSummary

        return ValidatedParagraphNodeContent(
            anchorSentenceID: anchorSentenceID,
            title: title,
            summary: summary
        )
    }

    nonisolated static func validatedFocusNodeContent(
        card: ParagraphTeachingCard,
        sentences: [Sentence],
        proposedTitle: String,
        proposedSummary: String
    ) -> ValidatedParagraphNodeContent {
        let anchorSentenceID = validatedCoreSentenceID(preferred: card.coreSentenceID, sentences: sentences)
        let fallbackTitle = fallbackFocusTitle(card: card)
        let fallbackSummary = fallbackFocusSummary(card: card)
        let reliability = paragraphReliabilityScore(card: card, sentences: sentences)

        let title = reliability >= 2 && isReadableMindMapTitle(proposedTitle)
            ? proposedTitle
            : fallbackTitle
        let summary = reliability >= 2 && isReadableMindMapSummary(proposedSummary)
            ? proposedSummary
            : fallbackSummary

        return ValidatedParagraphNodeContent(
            anchorSentenceID: anchorSentenceID,
            title: title,
            summary: summary
        )
    }

    nonisolated static func validatedSentenceNodeContent(
        sentence: Sentence,
        analysis: ProfessorSentenceAnalysis?,
        proposedTitle: String,
        proposedSummary: String
    ) -> ValidatedSentenceNodeContent {
        let analysisIsReliable = isReliableAnalysis(analysis, for: sentence)
        let fallbackTitle = fallbackSentenceTitle(sentence: sentence, analysis: analysisIsReliable ? analysis : nil)
        let fallbackSummary = fallbackSentenceSummary(sentence: sentence, analysis: analysisIsReliable ? analysis : nil)

        let title = analysisIsReliable && isReadableMindMapTitle(proposedTitle)
            ? proposedTitle
            : fallbackTitle
        let summary = analysisIsReliable && isReadableMindMapSummary(proposedSummary)
            ? proposedSummary
            : fallbackSummary

        return ValidatedSentenceNodeContent(title: title, summary: summary)
    }

    private nonisolated static func paragraphReliabilityScore(
        card: ParagraphTeachingCard,
        sentences: [Sentence]
    ) -> Int {
        var score = 0
        let paragraphText = sentences.map(\.text).joined(separator: " ")
        if validatedCoreSentenceID(preferred: card.coreSentenceID, sentences: sentences) != nil {
            score += 1
        }
        if !card.displayedTheme.isEmpty, isChineseDominant(card.displayedTheme) {
            score += 1
        }
        let keywordScore = englishTokenOverlap(
            lhs: card.keywords.joined(separator: " "),
            rhs: paragraphText
        )
        if keywordScore >= 0.16 || card.keywords.isEmpty {
            score += 1
        }
        return score
    }

    private nonisolated static func isReliableAnalysis(
        _ analysis: ProfessorSentenceAnalysis?,
        for sentence: Sentence
    ) -> Bool {
        guard let analysis else { return false }

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

        return true
    }

    private nonisolated static func fallbackParagraphTitle(card: ParagraphTeachingCard) -> String {
        let theme = trimmed(card.displayedTheme)
        if !theme.isEmpty {
            return "第\(card.paragraphIndex + 1)段｜\(truncate(theme, limit: 16))"
        }
        return "第\(card.paragraphIndex + 1)段｜\(card.argumentRole.displayName)"
    }

    private nonisolated static func fallbackParagraphSummary(card: ParagraphTeachingCard) -> String {
        if let firstFocus = card.displayedTeachingFocuses.first {
            return truncate(firstFocus, limit: 32)
        }
        let examValue = trimmed(card.displayedExamValue)
        if !examValue.isEmpty {
            return truncate(examValue, limit: 32)
        }
        return truncate(card.argumentRole.teachingDescription, limit: 32)
    }

    private nonisolated static func fallbackFocusTitle(card: ParagraphTeachingCard) -> String {
        if let firstFocus = card.displayedTeachingFocuses.first {
            return "教学重点｜\(truncate(firstFocus, limit: 16))"
        }
        return "教学重点｜\(card.argumentRole.displayName)"
    }

    private nonisolated static func fallbackFocusSummary(card: ParagraphTeachingCard) -> String {
        if let blindSpot = trimmed(card.displayedStudentBlindSpot ?? "").nonEmpty {
            return truncate("别读偏：\(blindSpot)", limit: 28)
        }
        let examValue = trimmed(card.displayedExamValue)
        if !examValue.isEmpty {
            return truncate(examValue, limit: 28)
        }
        return truncate(card.argumentRole.teachingDescription, limit: 28)
    }

    private nonisolated static func fallbackSentenceTitle(
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
            .map(trimmed) ?? ""
        if !sentenceFunctionHead.isEmpty {
            return "第\(sentence.localIndex + 1)句｜\(truncate(sentenceFunctionHead, limit: 8))"
        }

        return "第\(sentence.localIndex + 1)句关键句"
    }

    private nonisolated static func fallbackSentenceSummary(
        sentence: Sentence,
        analysis: ProfessorSentenceAnalysis?
    ) -> String {
        if let analysis {
            let faithful = trimmed(analysis.renderedFaithfulTranslation)
            if !faithful.isEmpty {
                return truncate(faithful, limit: 32)
            }

            let teaching = trimmed(analysis.renderedTeachingInterpretation)
            if !teaching.isEmpty {
                return truncate(teaching, limit: 32)
            }
        }

        return truncate(trimmed(sentence.text), limit: 36)
    }

    private nonisolated static func isReadableMindMapTitle(_ value: String) -> Bool {
        let normalized = trimmed(value)
        guard !normalized.isEmpty else { return false }
        if normalized.count > 26 { return false }
        if containsDenseSeparators(normalized) { return false }
        if normalized.contains("本段主要讲") || normalized.contains("文章主要讲") {
            return false
        }
        return true
    }

    private nonisolated static func isReadableMindMapSummary(_ value: String) -> Bool {
        let normalized = trimmed(value)
        guard !normalized.isEmpty else { return false }
        if normalized.count > 40 { return false }
        if containsDenseSeparators(normalized) { return false }
        if normalized.contains("本段主要讲") || normalized.contains("文章主要讲") {
            return false
        }
        return true
    }

    private nonisolated static func containsDenseSeparators(_ value: String) -> Bool {
        let separatorCount = value.filter { "｜；/".contains($0) }.count
        return separatorCount >= 3
    }

    private nonisolated static func truncate(_ value: String, limit: Int) -> String {
        let normalized = trimmed(value)
        guard !normalized.isEmpty, normalized.count > limit else { return normalized }
        return String(normalized.prefix(max(limit - 1, 0))) + "…"
    }

    private nonisolated static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func normalizedEnglishSource(_ value: String) -> String {
        trimmed(value)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private nonisolated static func englishTokenOverlap(lhs: String, rhs: String) -> Double {
        let left = tokenSet(from: lhs)
        let right = tokenSet(from: rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        return Double(left.intersection(right).count) / Double(max(left.count, right.count))
    }

    private nonisolated static func tokenSet(from text: String) -> Set<String> {
        Set(
            text
                .lowercased()
                .components(separatedBy: CharacterSet.letters.inverted)
                .filter { !$0.isEmpty && $0.count >= 2 }
        )
    }

    private nonisolated static func isChineseDominant(_ value: String) -> Bool {
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
