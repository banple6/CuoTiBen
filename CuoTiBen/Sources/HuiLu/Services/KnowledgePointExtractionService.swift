import Foundation

final class KnowledgePointExtractionService {
    func extract(
        titles: [String],
        suggestedPoints: [KnowledgePoint],
        tags: [String],
        noteTitle: String,
        body: String,
        quote: String
    ) -> [KnowledgePoint] {
        let explicitTitles = splitAndNormalize(titles)
        let normalizedTags = splitAndNormalize(candidateTags(from: tags))
        let suggestedTitleMap = suggestedPoints.reduce(into: [String: KnowledgePoint]()) { partialResult, point in
            partialResult[KnowledgePoint.normalizedID(for: point.title)] = point
        }
        let explicitAliasMap = buildAliasMap(from: titles)

        var orderedCandidates: [(id: String, title: String)] = []
        var seen = Set<String>()

        func appendCandidate(_ raw: String) {
            guard let normalized = normalizeTitle(raw) else { return }
            let id = KnowledgePoint.normalizedID(for: normalized)
            guard !seen.contains(id) else { return }
            seen.insert(id)
            orderedCandidates.append((id: id, title: normalized))
        }

        explicitTitles.forEach(appendCandidate)
        suggestedPoints.map(\.title).forEach(appendCandidate)
        normalizedTags.forEach(appendCandidate)

        if orderedCandidates.isEmpty {
            inferredCandidates(from: [noteTitle, body, quote].joined(separator: "\n"))
                .forEach(appendCandidate)
        }

        let resolved = orderedCandidates.map { candidate -> KnowledgePoint in
            let suggestedDefinition = suggestedTitleMap[candidate.id]?.definition
            let definition = resolveDefinition(
                for: candidate.title,
                suggestedDefinition: suggestedDefinition,
                body: body,
                quote: quote
            )
            return KnowledgePoint(
                id: candidate.id,
                title: candidate.title,
                definition: definition,
                shortDefinition: makeShortDefinition(from: definition),
                aliases: mergeAliases(
                    explicitAliasMap[candidate.id] ?? [],
                    suggestedTitleMap[candidate.id]?.aliases ?? [],
                    defaultAliases(for: candidate.title)
                ),
                relatedKnowledgePointIDs: []
            )
        }

        let ids = resolved.map(\.id)
        return resolved.enumerated().map { index, point in
            KnowledgePoint(
                id: point.id,
                title: point.title,
                definition: point.definition,
                shortDefinition: point.shortDefinition,
                aliases: point.aliases,
                relatedKnowledgePointIDs: ids.enumerated().compactMap { relatedIndex, relatedID in
                    relatedIndex == index ? nil : relatedID
                }
            )
        }
    }

    func merge(points: [KnowledgePoint]) -> [KnowledgePoint] {
        var grouped: [String: [KnowledgePoint]] = [:]
        for point in points {
            grouped[point.id, default: []].append(point)
        }

        return grouped.values.compactMap { points -> KnowledgePoint? in
            guard let first = points.first else { return nil }

            let bestTitle = points
                .map(\.title)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted(by: preferredTitle(_:_:))
                .first ?? first.title

            let bestDefinition = points
                .map(\.definition)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted { $0.count > $1.count }
                .first ?? ""
            let bestShortDefinition = points
                .compactMap(\.shortDefinition)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted { $0.count > $1.count }
                .first ?? makeShortDefinition(from: bestDefinition)
            let aliases = mergeAliases(points.flatMap(\.aliases))

            let relatedIDs = Array(
                Set(points.flatMap(\.relatedKnowledgePointIDs))
            )
            .filter { $0 != first.id }
            .sorted()

            return KnowledgePoint(
                id: first.id,
                title: bestTitle,
                definition: bestDefinition,
                shortDefinition: bestShortDefinition,
                aliases: aliases,
                relatedKnowledgePointIDs: relatedIDs
            )
        }
        .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }
}

private extension KnowledgePointExtractionService {
    var blockedTitles: Set<String> {
        [
            "句子讲解", "单词讲解", "笔记", "来源句", "原文", "quote", "text", "ink",
            "noun", "verb", "adjective", "adverb", "pronoun", "article",
            "n", "v", "adj", "adv", "prep", "conj"
        ]
    }

    var aliasMap: [String: String] {
        [
            "object clause": "宾语从句",
            "noun clause": "名词性从句",
            "passive voice": "被动语态",
            "attributive clause": "定语从句",
            "policy expression": "政策表达",
            "long sentence": "长难句",
            "rewrite": "改写表达",
            "collocation": "固定搭配"
        ]
    }

    var reverseAliasMap: [String: [String]] {
        Dictionary(grouping: aliasMap, by: \.value)
            .mapValues { entries in entries.map(\.key).sorted() }
    }

    func candidateTags(from tags: [String]) -> [String] {
        tags.filter { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            if trimmed.range(of: #"[A-Za-z]{4,}|[\u4e00-\u9fa5]{2,}"#, options: .regularExpression) == nil {
                return false
            }
            return !blockedTitles.contains(trimmed.lowercased())
        }
    }

    func splitAndNormalize(_ values: [String]) -> [String] {
        values
            .flatMap { value in
                value.split(whereSeparator: { ",，/、|".contains($0) }).map(String.init)
            }
            .compactMap(normalizeTitle)
    }

    func buildAliasMap(from values: [String]) -> [String: [String]] {
        var result: [String: Set<String>] = [:]

        for value in values {
            for rawPart in value.split(whereSeparator: { ",，/、|".contains($0) }).map(String.init) {
                guard let normalized = normalizeTitle(rawPart) else { continue }
                let candidateID = KnowledgePoint.normalizedID(for: normalized)
                guard let alias = normalizedAlias(rawPart), alias != normalized.lowercased() else { continue }
                result[candidateID, default: []].insert(alias)
            }
        }

        return result.mapValues { Array($0).sorted() }
    }

    func normalizeTitle(_ raw: String) -> String? {
        var value = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"^(知识点|关键词|语法点|关联知识点|概念|标签)\s*[:：-]?\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "·•-–—:：;；,.，。!?！？()[]{}<>《》\"' "))

        guard !value.isEmpty else { return nil }

        let lookup = value.lowercased()
        if let alias = aliasMap[lookup] {
            value = alias
        }

        guard !blockedTitles.contains(value.lowercased()) else { return nil }

        let isOnlyASCII = value.range(of: #"^[A-Za-z\s]+$"#, options: .regularExpression) != nil
        if isOnlyASCII {
            let compact = value.replacingOccurrences(of: " ", with: "")
            guard compact.count >= 4 else { return nil }
        } else {
            guard value.count >= 2 else { return nil }
        }

        return value
    }

    func normalizedAlias(_ raw: String) -> String? {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()

        guard !trimmed.isEmpty else { return nil }
        guard !blockedTitles.contains(trimmed) else { return nil }
        return trimmed
    }

    func defaultAliases(for title: String) -> [String] {
        reverseAliasMap[title] ?? []
    }

    func mergeAliases(_ groups: [String]...) -> [String] {
        mergeAliases(groups.flatMap { $0 })
    }

    func mergeAliases(_ values: [String]) -> [String] {
        Array(Set(values))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    func makeShortDefinition(from definition: String) -> String? {
        let trimmed = definition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(46))
    }

    func resolveDefinition(
        for title: String,
        suggestedDefinition: String?,
        body: String,
        quote: String
    ) -> String {
        if let suggestedDefinition = suggestedDefinition?.trimmingCharacters(in: .whitespacesAndNewlines),
           !suggestedDefinition.isEmpty {
            return suggestedDefinition
        }

        if let lineDefinition = definitionAfterLabel(title, in: body) {
            return lineDefinition
        }

        if let sentenceDefinition = sentenceContaining(title, in: body) {
            return sentenceDefinition
        }

        if let quoteDefinition = sentenceContaining(title, in: quote) {
            return quoteDefinition
        }

        if let fallback = firstMeaningfulSentence(in: body) ?? firstMeaningfulSentence(in: quote) {
            return fallback
        }

        return "围绕“\(title)”整理的学习记录。"
    }

    func definitionAfterLabel(_ title: String, in text: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: title)
        let patterns = [
            "\(escaped)\\s*[:：]\\s*([^\\n]+)",
            "([^\\n]+)\\s*[:：]\\s*\(escaped)"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  match.numberOfRanges > 1,
                  let resultRange = Range(match.range(at: 1), in: text) else {
                continue
            }

            let result = text[resultRange]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "：:;；,.，。"))
            if !result.isEmpty {
                return String(result.prefix(120))
            }
        }

        return nil
    }

    func sentenceContaining(_ title: String, in text: String) -> String? {
        let segments = text
            .components(separatedBy: CharacterSet(charactersIn: "\n。！？!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return segments.first(where: { $0.localizedCaseInsensitiveContains(title) }).map {
            String($0.prefix(120))
        }
    }

    func firstMeaningfulSentence(in text: String) -> String? {
        text
            .components(separatedBy: CharacterSet(charactersIn: "\n。！？!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.count >= 6 })
            .map { String($0.prefix(120)) }
    }

    func inferredCandidates(from text: String) -> [String] {
        let regexPatterns = [
            #"(宾语从句|定语从句|被动语态|长难句|政策表达|改写表达|固定搭配)"#,
            #"\b(object clause|noun clause|passive voice|long sentence|collocation)\b"#
        ]

        var results: [String] = []
        for pattern in regexPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)
            for match in matches {
                guard let resultRange = Range(match.range(at: 1), in: text) else { continue }
                results.append(String(text[resultRange]))
            }
        }
        return results
    }

    func preferredTitle(_ lhs: String, _ rhs: String) -> Bool {
        let lhsHasChinese = lhs.range(of: #"[\u4e00-\u9fa5]"#, options: .regularExpression) != nil
        let rhsHasChinese = rhs.range(of: #"[\u4e00-\u9fa5]"#, options: .regularExpression) != nil

        if lhsHasChinese != rhsHasChinese {
            return lhsHasChinese && !rhsHasChinese
        }

        return lhs.count > rhs.count
    }
}
