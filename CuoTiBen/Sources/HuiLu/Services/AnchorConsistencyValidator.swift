import Foundation

enum OutlineNodeAdmission {
    case mainline
    case auxiliary
    case rejected
}

struct ValidatedParagraphNodeContent {
    let anchorSentenceID: String?
    let title: String
    let summary: String
    let consistencyScore: Double
    let admission: OutlineNodeAdmission
    let rejectedReason: String?
}

struct ValidatedSentenceNodeContent {
    let title: String
    let summary: String
    let consistencyScore: Double
    let admission: OutlineNodeAdmission
    let rejectedReason: String?
}

enum AnchorConsistencyValidator {
    private static let mainlineThreshold = 0.75
    private static let auxiliaryThreshold = 0.45

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
        sourceKind: SourceContentKind,
        proposedTitle: String,
        proposedSummary: String
    ) -> ValidatedParagraphNodeContent {
        let anchorSentenceID = validatedCoreSentenceID(preferred: card.coreSentenceID, sentences: sentences)
        let fallbackTitle = fallbackParagraphTitle(card: card)
        let fallbackSummary = fallbackParagraphSummary(card: card)
        let rawScore = paragraphConsistencyScore(
            card: card,
            sentences: sentences,
            proposedTitle: proposedTitle,
            proposedSummary: proposedSummary,
            fallbackTitle: fallbackTitle,
            fallbackSummary: fallbackSummary
        )
        let title = rawScore >= mainlineThreshold && isReadableMindMapTitle(proposedTitle)
            ? proposedTitle
            : fallbackTitle
        let summary = rawScore >= mainlineThreshold && isReadableMindMapSummary(proposedSummary)
            ? proposedSummary
            : fallbackSummary

        let admission: OutlineNodeAdmission
        let rejectedReason: String?
        if !sourceKind.isMainlinePassageBody {
            admission = .auxiliary
            rejectedReason = "source_kind_\(sourceKind.rawValue)"
        } else if anchorSentenceID == nil {
            admission = .rejected
            rejectedReason = "missing_anchor_sentence"
        } else {
            admission = .mainline
            rejectedReason = rawScore < mainlineThreshold ? "used_local_fallback" : nil
        }

        logDecision(
            nodeID: "para_\(card.segmentID)",
            nodeType: .paragraphTheme,
            sourceSegmentID: card.segmentID,
            sourceSentenceID: anchorSentenceID,
            consistencyScore: rawScore,
            rejectedReason: rejectedReason
        )

        return ValidatedParagraphNodeContent(
            anchorSentenceID: anchorSentenceID,
            title: title,
            summary: summary,
            consistencyScore: rawScore,
            admission: admission,
            rejectedReason: rejectedReason
        )
    }

    static func validatedFocusNodeContent(
        card: ParagraphTeachingCard,
        sentences: [Sentence],
        sourceKind: SourceContentKind,
        proposedTitle: String,
        proposedSummary: String
    ) -> ValidatedParagraphNodeContent {
        let anchorSentenceID = validatedCoreSentenceID(preferred: card.coreSentenceID, sentences: sentences)
        let fallbackTitle = fallbackFocusTitle(card: card)
        let fallbackSummary = fallbackFocusSummary(card: card)
        let rawScore = paragraphConsistencyScore(
            card: card,
            sentences: sentences,
            proposedTitle: proposedTitle,
            proposedSummary: proposedSummary,
            fallbackTitle: fallbackTitle,
            fallbackSummary: fallbackSummary
        )

        let title = rawScore >= mainlineThreshold && isReadableMindMapTitle(proposedTitle)
            ? proposedTitle
            : fallbackTitle
        let summary = rawScore >= mainlineThreshold && isReadableMindMapSummary(proposedSummary)
            ? proposedSummary
            : fallbackSummary

        let admission: OutlineNodeAdmission
        let rejectedReason: String?
        if !sourceKind.isMainlinePassageBody {
            admission = .auxiliary
            rejectedReason = "source_kind_\(sourceKind.rawValue)"
        } else if anchorSentenceID == nil {
            admission = .rejected
            rejectedReason = "missing_anchor_sentence"
        } else if rawScore >= mainlineThreshold {
            admission = .mainline
            rejectedReason = nil
        } else if rawScore >= auxiliaryThreshold {
            admission = .auxiliary
            rejectedReason = "weak_consistency"
        } else {
            admission = .rejected
            rejectedReason = "low_consistency"
        }

        logDecision(
            nodeID: "focus_\(card.segmentID)",
            nodeType: .teachingFocus,
            sourceSegmentID: card.segmentID,
            sourceSentenceID: anchorSentenceID,
            consistencyScore: rawScore,
            rejectedReason: rejectedReason
        )

        return ValidatedParagraphNodeContent(
            anchorSentenceID: anchorSentenceID,
            title: title,
            summary: summary,
            consistencyScore: rawScore,
            admission: admission,
            rejectedReason: rejectedReason
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
        let rawScore = sentenceConsistencyScore(
            sentence: sentence,
            analysis: analysis,
            proposedTitle: proposedTitle,
            proposedSummary: proposedSummary,
            fallbackTitle: fallbackTitle,
            fallbackSummary: fallbackSummary
        )

        let title = rawScore >= mainlineThreshold && isReadableMindMapTitle(proposedTitle)
            ? proposedTitle
            : fallbackTitle
        let summary = rawScore >= mainlineThreshold && isReadableMindMapSummary(proposedSummary)
            ? proposedSummary
            : fallbackSummary

        let admission: OutlineNodeAdmission
        let rejectedReason: String?
        if !sentence.provenance.sourceKind.isMainlinePassageBody {
            admission = .auxiliary
            rejectedReason = "source_kind_\(sentence.provenance.sourceKind.rawValue)"
        } else if rawScore >= mainlineThreshold {
            admission = .mainline
            rejectedReason = nil
        } else if rawScore >= auxiliaryThreshold {
            admission = .auxiliary
            rejectedReason = "weak_consistency"
        } else {
            admission = .rejected
            rejectedReason = "low_consistency"
        }

        logDecision(
            nodeID: "support_\(sentence.id)",
            nodeType: .supportingSentence,
            sourceSegmentID: sentence.segmentID,
            sourceSentenceID: sentence.id,
            consistencyScore: rawScore,
            rejectedReason: rejectedReason
        )

        return ValidatedSentenceNodeContent(
            title: title,
            summary: summary,
            consistencyScore: rawScore,
            admission: admission,
            rejectedReason: rejectedReason
        )
    }

    static func validatedMisreadingNodeContent(
        card: ParagraphTeachingCard,
        sourceKind: SourceContentKind
    ) -> ValidatedParagraphNodeContent? {
        let title = fallbackMisreadingTitle(card: card)
        let summary = fallbackMisreadingSummary(card: card)
        guard !trimmed(summary).isEmpty else { return nil }

        let score = sourceKind.isMainlinePassageBody ? 0.78 : 0.38
        let admission: OutlineNodeAdmission = sourceKind.isMainlinePassageBody ? .mainline : .auxiliary
        let rejectedReason: String? = sourceKind.isMainlinePassageBody ? nil : "source_kind_\(sourceKind.rawValue)"

        logDecision(
            nodeID: "trap_\(card.segmentID)",
            nodeType: .misreadingTrap,
            sourceSegmentID: card.segmentID,
            sourceSentenceID: card.coreSentenceID,
            consistencyScore: score,
            rejectedReason: rejectedReason
        )

        return ValidatedParagraphNodeContent(
            anchorSentenceID: card.coreSentenceID,
            title: title,
            summary: summary,
            consistencyScore: score,
            admission: admission,
            rejectedReason: rejectedReason
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
            score += 0.22
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

        let titleOverlap = max(
            textTokenOverlap(lhs: proposedTitle, rhs: fallbackTitle),
            textTokenOverlap(lhs: proposedTitle, rhs: card.displayedTheme),
            englishTokenOverlap(lhs: proposedTitle, rhs: paragraphText)
        )
        if titleOverlap >= 0.38 || sameSentenceLead(lhs: proposedTitle, rhs: fallbackTitle) {
            score += 0.18
        } else if titleOverlap >= 0.2 {
            score += 0.08
        }

        let summaryOverlap = max(
            textTokenOverlap(lhs: proposedSummary, rhs: fallbackSummary),
            textTokenOverlap(lhs: proposedSummary, rhs: card.displayedRelationToPrevious),
            textTokenOverlap(lhs: proposedSummary, rhs: card.displayedTeachingFocuses.first ?? ""),
            textTokenOverlap(lhs: proposedSummary, rhs: card.displayedStudentBlindSpot ?? "")
        )
        if summaryOverlap >= 0.3 {
            score += 0.18
        } else if summaryOverlap >= 0.16 {
            score += 0.08
        }

        let paragraphOverlap = max(
            englishTokenOverlap(lhs: proposedTitle, rhs: paragraphText),
            englishTokenOverlap(lhs: proposedSummary, rhs: paragraphText)
        )
        if paragraphOverlap >= 0.14 {
            score += 0.1
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
        var score = reliableAnalysis ? 0.42 : 0.18

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

        let titleOverlap = max(
            textTokenOverlap(lhs: proposedTitle, rhs: fallbackTitle),
            englishTokenOverlap(lhs: proposedTitle, rhs: sentence.text)
        )
        if titleOverlap >= 0.28 || sameSentenceLead(lhs: proposedTitle, rhs: fallbackTitle) {
            score += 0.12
        } else if isReadableMindMapTitle(proposedTitle) {
            score += 0.06
        }

        let summaryOverlap = max(
            textTokenOverlap(lhs: proposedSummary, rhs: fallbackSummary),
            englishTokenOverlap(lhs: proposedSummary, rhs: sentence.text),
            textTokenOverlap(lhs: proposedSummary, rhs: analysis?.renderedFaithfulTranslation ?? ""),
            textTokenOverlap(lhs: proposedSummary, rhs: analysis?.renderedTeachingInterpretation ?? "")
        )
        if summaryOverlap >= 0.24 {
            score += 0.12
        } else if summaryOverlap >= 0.12 {
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
        kind.isAuxiliaryOnly
    }

    private static func fallbackParagraphTitle(card: ParagraphTeachingCard) -> String {
        let role = card.argumentRole.displayName
        let theme = truncate(trimmed(card.displayedTheme), limit: 10)
        if !theme.isEmpty {
            return "第\(card.paragraphIndex + 1)段｜\(role)｜\(theme)"
        }
        return "第\(card.paragraphIndex + 1)段｜\(role)"
    }

    private static func fallbackParagraphSummary(card: ParagraphTeachingCard) -> String {
        let relation = trimmed(card.displayedRelationToPrevious)
        if !relation.isEmpty {
            return truncate(relation, limit: 50)
        }
        return truncate(card.argumentRole.teachingDescription, limit: 50)
    }

    private static func fallbackFocusTitle(card: ParagraphTeachingCard) -> String {
        if let firstFocus = card.displayedTeachingFocuses.first, !trimmed(firstFocus).isEmpty {
            return "教学重点｜\(truncate(firstFocus, limit: 12))"
        }
        return "教学重点｜\(truncate(card.argumentRole.displayName, limit: 10))"
    }

    private static func fallbackFocusSummary(card: ParagraphTeachingCard) -> String {
        if let firstFocus = card.displayedTeachingFocuses.first, !trimmed(firstFocus).isEmpty {
            return truncate(firstFocus, limit: 40)
        }
        return truncate(card.argumentRole.teachingDescription, limit: 40)
    }

    private static func fallbackMisreadingTitle(card: ParagraphTeachingCard) -> String {
        if let blindSpot = trimmed(card.displayedStudentBlindSpot ?? "").nonEmpty {
            return "易错点｜\(truncate(blindSpot, limit: 12))"
        }
        return "易错点｜\(truncate(card.argumentRole.displayName, limit: 10))"
    }

    private static func fallbackMisreadingSummary(card: ParagraphTeachingCard) -> String {
        if let blindSpot = trimmed(card.displayedStudentBlindSpot ?? "").nonEmpty {
            return truncate(blindSpot, limit: 40)
        }
        let examValue = trimmed(card.displayedExamValue)
        if !examValue.isEmpty {
            return truncate(examValue, limit: 40)
        }
        return ""
    }

    private static func fallbackSentenceTitle(
        sentence: Sentence,
        analysis: ProfessorSentenceAnalysis?
    ) -> String {
        if let analysis,
           let roleLabel = professorSentenceRolePresentation(for: analysis.evidenceType)?.label,
           !trimmed(roleLabel).isEmpty {
            return "核心句｜第\(sentence.localIndex + 1)句"
        }
        return "核心句｜第\(sentence.localIndex + 1)句"
    }

    private static func fallbackSentenceSummary(
        sentence: Sentence,
        analysis: ProfessorSentenceAnalysis?
    ) -> String {
        if let analysis {
            let function = trimmed(analysis.renderedSentenceFunction)
            if !function.isEmpty {
                return truncate(function, limit: 36)
            }
            let teaching = trimmed(analysis.renderedTeachingInterpretation)
            if !teaching.isEmpty {
                return truncate(teaching, limit: 36)
            }
        }

        return truncate(sentence.text, limit: 36)
    }

    private static func isReadableMindMapTitle(_ value: String) -> Bool {
        let normalized = trimmed(value)
        guard !normalized.isEmpty else { return false }
        if normalized.count > 22 { return false }
        if containsDenseSeparators(normalized) { return false }
        if normalized.contains("本段主要讲") || normalized.contains("文章主要讲") {
            return false
        }
        if normalized.range(of: #"[A-Za-z]{8,}"#, options: .regularExpression) != nil {
            return false
        }
        return true
    }

    private static func isReadableMindMapSummary(_ value: String) -> Bool {
        let normalized = trimmed(value)
        guard !normalized.isEmpty else { return false }
        if normalized.count > 50 { return false }
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

    private static func logDecision(
        nodeID: String,
        nodeType: PedagogicalNodeType,
        sourceSegmentID: String?,
        sourceSentenceID: String?,
        consistencyScore: Double,
        rejectedReason: String?
    ) {
        let reason = rejectedReason ?? "accepted"
        TextPipelineDiagnostics.log(
            "AI",
            "[AI][AnchorConsistency] nodeID=\(nodeID) nodeType=\(nodeType.rawValue) sourceSegmentID=\(sourceSegmentID ?? "nil") sourceSentenceID=\(sourceSentenceID ?? "nil") consistencyScore=\(String(format: "%.2f", consistencyScore)) rejectedReason=\(reason)",
            severity: rejectedReason == nil ? .info : .warning
        )
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
