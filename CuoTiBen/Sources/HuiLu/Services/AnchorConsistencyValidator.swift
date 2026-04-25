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

struct AnchorConsistencyResult {
    let titleOverlapScore: Double
    let summaryOverlapScore: Double
    let sentenceBelongsToSegment: Bool
    let coreSentenceBelongsToParagraph: Bool
    let sourceKindAllowed: Bool
    let hygieneAllowed: Bool
    let consistencyScore: Double
    let reasons: [String]
    let admission: MindMapAdmission
    let rejectedReason: String?
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

    static func evaluateParagraphCandidate(
        paragraph: ParagraphMap,
        segment: Segment,
        sentences: [Sentence]
    ) -> AnchorConsistencyResult {
        evaluate(
            title: paragraph.theme,
            summary: paragraph.examValue.nonEmpty ?? paragraph.relationToPrevious,
            sourceText: segment.text,
            sourceKind: paragraph.provenance.sourceKind,
            hygieneScore: paragraph.provenance.hygieneScore,
            anchorSentenceID: paragraph.coreSentenceID,
            coreSentenceID: paragraph.coreSentenceID,
            sentences: sentences,
            analysisOriginalSentence: nil
        )
    }

    static func evaluateParagraphFocusCandidate(
        paragraph: ParagraphMap,
        focusSummary: String,
        segment: Segment,
        sentences: [Sentence]
    ) -> AnchorConsistencyResult {
        evaluate(
            title: paragraph.theme,
            summary: focusSummary,
            sourceText: segment.text,
            sourceKind: paragraph.provenance.sourceKind,
            hygieneScore: paragraph.provenance.hygieneScore,
            anchorSentenceID: paragraph.coreSentenceID,
            coreSentenceID: paragraph.coreSentenceID,
            sentences: sentences,
            analysisOriginalSentence: nil
        )
    }

    static func evaluateSentenceCandidate(
        sentence: Sentence,
        segment: Segment,
        analysis: ProfessorSentenceAnalysis?
    ) -> AnchorConsistencyResult {
        evaluate(
            title: fallbackSentenceTitle(sentence: sentence, analysis: analysis),
            summary: analysis?.renderedTeachingInterpretation.nonEmpty
                ?? analysis?.renderedFaithfulTranslation.nonEmpty
                ?? sentence.text,
            sourceText: segment.text,
            sourceKind: sentence.provenance.sourceKind,
            hygieneScore: sentence.hygiene.score,
            anchorSentenceID: sentence.id,
            coreSentenceID: sentence.id,
            sentences: [sentence],
            analysisOriginalSentence: analysis?.originalSentence
        )
    }

    static func evaluateAuxiliaryCandidate(
        title: String,
        summary: String,
        sourceKind: SourceContentKind,
        hygieneScore: Double,
        supportingSentenceID: String?,
        segmentID: String?,
        sentences: [Sentence]
    ) -> AnchorConsistencyResult {
        let scopedSentences = sentences.filter { supportingSentenceID == nil || $0.id == supportingSentenceID }
        return evaluate(
            title: title,
            summary: summary,
            sourceText: scopedSentences.map(\.text).joined(separator: " ").nonEmpty
                ?? sentences.map(\.text).joined(separator: " ").nonEmpty
                ?? summary,
            sourceKind: sourceKind,
            hygieneScore: hygieneScore,
            anchorSentenceID: supportingSentenceID,
            coreSentenceID: supportingSentenceID,
            sentences: segmentID == nil ? [] : sentences,
            analysisOriginalSentence: nil
        )
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
        let sourceText = sentences.map(\.text).joined(separator: " ").nonEmpty
            ?? proposedSummary
        let provenance = paragraphProvenance(for: sentences, preferredSentenceID: anchorSentenceID)
        let result = evaluate(
            title: proposedTitle,
            summary: proposedSummary,
            sourceText: sourceText,
            sourceKind: provenance.sourceKind,
            hygieneScore: provenance.hygieneScore,
            anchorSentenceID: anchorSentenceID,
            coreSentenceID: anchorSentenceID,
            sentences: sentences,
            analysisOriginalSentence: nil
        )

        let title = result.consistencyScore >= 0.62 && isReadableMindMapTitle(proposedTitle)
            ? proposedTitle
            : fallbackTitle
        let summary = result.consistencyScore >= 0.62 && isReadableMindMapSummary(proposedSummary)
            ? proposedSummary
            : fallbackSummary

        return ValidatedParagraphNodeContent(
            anchorSentenceID: anchorSentenceID,
            title: title,
            summary: summary,
            consistencyScore: result.consistencyScore
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
        let sourceText = sentences.map(\.text).joined(separator: " ").nonEmpty
            ?? proposedSummary
        let provenance = paragraphProvenance(for: sentences, preferredSentenceID: anchorSentenceID)
        let result = evaluate(
            title: proposedTitle,
            summary: proposedSummary,
            sourceText: sourceText,
            sourceKind: provenance.sourceKind,
            hygieneScore: provenance.hygieneScore,
            anchorSentenceID: anchorSentenceID,
            coreSentenceID: anchorSentenceID,
            sentences: sentences,
            analysisOriginalSentence: nil
        )

        let title = result.consistencyScore >= 0.6 && isReadableMindMapTitle(proposedTitle)
            ? proposedTitle
            : fallbackTitle
        let summary = result.consistencyScore >= 0.6 && isReadableMindMapSummary(proposedSummary)
            ? proposedSummary
            : fallbackSummary

        return ValidatedParagraphNodeContent(
            anchorSentenceID: anchorSentenceID,
            title: title,
            summary: summary,
            consistencyScore: result.consistencyScore
        )
    }

    static func validatedSentenceNodeContent(
        sentence: Sentence,
        analysis: ProfessorSentenceAnalysis?,
        proposedTitle: String,
        proposedSummary: String
    ) -> ValidatedSentenceNodeContent {
        let fallbackTitle = fallbackSentenceTitle(sentence: sentence, analysis: analysis)
        let fallbackSummary = fallbackSentenceSummary(sentence: sentence, analysis: analysis)
        let result = evaluate(
            title: proposedTitle,
            summary: proposedSummary,
            sourceText: sentence.text,
            sourceKind: sentence.provenance.sourceKind,
            hygieneScore: sentence.hygiene.score,
            anchorSentenceID: sentence.id,
            coreSentenceID: sentence.id,
            sentences: [sentence],
            analysisOriginalSentence: analysis?.originalSentence
        )

        let title = result.consistencyScore >= 0.62 && isReadableMindMapTitle(proposedTitle)
            ? proposedTitle
            : fallbackTitle
        let summary = result.consistencyScore >= 0.62 && isReadableMindMapSummary(proposedSummary)
            ? proposedSummary
            : fallbackSummary

        return ValidatedSentenceNodeContent(
            title: title,
            summary: summary,
            consistencyScore: result.consistencyScore
        )
    }

    private static func evaluate(
        title: String,
        summary: String,
        sourceText: String,
        sourceKind: SourceContentKind,
        hygieneScore: Double,
        anchorSentenceID: String?,
        coreSentenceID: String?,
        sentences: [Sentence],
        analysisOriginalSentence: String?
    ) -> AnchorConsistencyResult {
        let normalizedSource = trimmed(sourceText)
        let titleOverlap = textTokenOverlap(lhs: title, rhs: normalizedSource)
        let summaryOverlap = textTokenOverlap(lhs: summary, rhs: normalizedSource)
        let sentenceIDs = Set(sentences.map(\.id))
        let sentenceBelongs = anchorSentenceID.map { sentenceIDs.contains($0) } ?? false
        let coreBelongs = coreSentenceID.map { sentenceIDs.contains($0) } ?? false
        let sourceKindAllowed = sourceKind.isAllowedForMainlineSource
        let hygieneAllowed = hygieneScore >= 0.6
        let analysisMatches = analysisSentenceMatches(analysisOriginalSentence, sentences: sentences)

        var reasons: [String] = []

        if titleOverlap < 0.18 {
            reasons.append("标题与来源段落重叠不足。")
        }
        if summaryOverlap < 0.14 {
            reasons.append("摘要与来源段落重叠不足。")
        }
        if !sentenceBelongs {
            reasons.append("锚句不属于当前段。")
        }
        if !coreBelongs {
            reasons.append("coreSentenceID 不属于当前段。")
        }
        if !sourceKindAllowed {
            reasons.append("\(sourceKind.displayName) 不能进入主导图主线。")
        }
        if !hygieneAllowed {
            reasons.append("来源卫生分过低。")
        }
        if !analysisMatches {
            reasons.append("句子分析与原句重叠不足。")
        }

        var score = 0.0
        score += min(titleOverlap, 1) * 0.28
        score += min(summaryOverlap, 1) * 0.22
        if sentenceBelongs { score += 0.15 }
        if coreBelongs { score += 0.15 }
        if sourceKindAllowed { score += 0.1 }
        if hygieneAllowed { score += 0.1 }
        if analysisMatches { score += 0.05 }
        let consistencyScore = min(max(score, 0.02), 0.98)

        let admission = decideAdmission(
            sourceKind: sourceKind,
            hygieneAllowed: hygieneAllowed,
            consistencyScore: consistencyScore
        )
        let rejectedReason = admission == .rejected ? reasons.first ?? "一致性不足，未进入主导图。" : nil

        return AnchorConsistencyResult(
            titleOverlapScore: titleOverlap,
            summaryOverlapScore: summaryOverlap,
            sentenceBelongsToSegment: sentenceBelongs,
            coreSentenceBelongsToParagraph: coreBelongs,
            sourceKindAllowed: sourceKindAllowed,
            hygieneAllowed: hygieneAllowed,
            consistencyScore: consistencyScore,
            reasons: Array(Set(reasons)).sorted(),
            admission: admission,
            rejectedReason: rejectedReason
        )
    }

    private static func decideAdmission(
        sourceKind: SourceContentKind,
        hygieneAllowed: Bool,
        consistencyScore: Double
    ) -> MindMapAdmission {
        if sourceKind.defaultsToAuxiliary {
            return consistencyScore >= 0.45 ? .auxiliary : .rejected
        }
        if !sourceKind.isAllowedForMainlineSource {
            return consistencyScore >= 0.45 ? .auxiliary : .rejected
        }
        if consistencyScore >= 0.75, hygieneAllowed {
            return .mainline
        }
        if consistencyScore >= 0.45 {
            return .auxiliary
        }
        return .rejected
    }

    private static func paragraphProvenance(
        for sentences: [Sentence],
        preferredSentenceID: String?
    ) -> NodeProvenance {
        let averageHygiene = sentences.isEmpty
            ? 0.5
            : sentences.map(\.hygiene.score).reduce(0, +) / Double(sentences.count)
        return NodeProvenance(
            sourceSegmentID: sentences.first?.segmentID,
            sourceSentenceID: preferredSentenceID ?? sentences.first?.id,
            sourcePage: sentences.first?.page,
            sourceKind: sentences.first?.provenance.sourceKind ?? .passageBody,
            generatedFrom: .paragraphCard,
            hygieneScore: averageHygiene,
            consistencyScore: max(averageHygiene, 0.5),
            rejectedReason: nil
        )
    }

    private static func analysisSentenceMatches(
        _ originalSentence: String?,
        sentences: [Sentence]
    ) -> Bool {
        guard let originalSentence = originalSentence?.nonEmpty else { return true }
        let sourceText = sentences.map(\.text).joined(separator: " ")
        guard !sourceText.isEmpty else { return false }
        return englishTokenOverlap(lhs: originalSentence, rhs: sourceText) >= 0.42
            || textTokenOverlap(lhs: originalSentence, rhs: sourceText) >= 0.42
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
