import Foundation

enum NotesFilterMode: String, CaseIterable, Identifiable {
    case all
    case tagged
    case knowledgePoints
    case ink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .tagged:
            return "有标签"
        case .knowledgePoints:
            return "有关联知识点"
        case .ink:
            return "含手写"
        }
    }
}

struct NotesPaneItem: Identifiable, Equatable, Hashable {
    let id: UUID
    let noteID: UUID
    let title: String
    let subtitle: String
    let summary: String
    let updatedAt: Date
    let badges: [String]
}

@MainActor
struct NotesHomeViewModel {
    let recentItems: [NoteSummaryItem]
    let recentPaneItems: [NotesPaneItem]
    let sourcePaneItems: [NotesPaneItem]
    let conceptPaneItems: [NotesPaneItem]
    let sourceGroups: [SourceNoteGroup]
    let conceptItems: [ConceptSummaryItem]
    let totalNoteCount: Int
    let filteredNoteCount: Int
    let activeFilter: NotesFilterMode
    let searchText: String

    static var empty: NotesHomeViewModel {
        NotesHomeViewModel(
            notes: [],
            sourceDocuments: [],
            searchText: "",
            activeFilter: .all
        )
    }

    init(
        notes: [Note],
        sourceDocuments: [SourceDocument],
        searchText: String,
        activeFilter: NotesFilterMode
    ) {
        self.totalNoteCount = notes.count
        self.activeFilter = activeFilter
        self.searchText = searchText

        let filteredNotes = notes
            .filter { Self.matchesFilter($0, filter: activeFilter) }
            .filter { Self.matchesSearch($0, searchText: searchText) }
            .sorted { $0.updatedAt > $1.updatedAt }

        self.filteredNoteCount = filteredNotes.count

        let sourceTitleLookup = Dictionary(
            uniqueKeysWithValues: sourceDocuments.map { ($0.id, Self.preferredSourceTitle(for: $0)) }
        )
        let knowledgePointTitleLookup = notes
            .flatMap(\.knowledgePoints)
            .reduce(into: [String: String]()) { partialResult, point in
                guard !point.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                let current = partialResult[point.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
                let candidate = point.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if current == nil || (current?.isEmpty == true && !candidate.isEmpty) || candidate.count > (current?.count ?? 0) {
                    partialResult[point.id] = candidate
                }
            }

        self.recentItems = filteredNotes.map {
            Self.makeSummaryItem(note: $0, sourceTitle: sourceTitleLookup[$0.sourceAnchor.sourceID] ?? Self.fallbackSourceTitle(for: $0.sourceAnchor.sourceTitle))
        }
        self.recentPaneItems = filteredNotes.map {
            let sourceTitle = sourceTitleLookup[$0.sourceAnchor.sourceID] ?? Self.fallbackSourceTitle(for: $0.sourceAnchor.sourceTitle)
            return Self.makePaneItem(note: $0, sourceTitle: sourceTitle)
        }

        self.sourceGroups = Dictionary(grouping: filteredNotes, by: \.sourceAnchor.sourceID)
            .compactMap { sourceID, notes in
                guard let latest = notes.max(by: { $0.updatedAt < $1.updatedAt }) else { return nil }
                let document = sourceDocuments.first { $0.id == sourceID }
                let sourceTitle = document.map(Self.preferredSourceTitle(for:)) ?? Self.fallbackSourceTitle(for: latest.sourceAnchor.sourceTitle)
                let subtitle = Self.subtitle(for: document, latestNote: latest)
                let previewItems = notes
                    .sorted { $0.updatedAt > $1.updatedAt }
                    .prefix(3)
                    .map { Self.makeSummaryItem(note: $0, sourceTitle: sourceTitle) }

                return SourceNoteGroup(
                    id: sourceID,
                    sourceID: sourceID,
                    sourceTitle: sourceTitle,
                    subtitle: subtitle,
                    noteCount: notes.count,
                    updatedAt: latest.updatedAt,
                    previewItems: Array(previewItems)
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
        self.sourcePaneItems = filteredNotes
            .map { note in
                let sourceTitle = sourceTitleLookup[note.sourceAnchor.sourceID] ?? Self.fallbackSourceTitle(for: note.sourceAnchor.sourceTitle)
                return (note, sourceTitle)
            }
            .sorted { lhs, rhs in
                let titleOrder = lhs.1.localizedCompare(rhs.1)
                if titleOrder != .orderedSame {
                    return titleOrder == .orderedAscending
                }
                return lhs.0.updatedAt > rhs.0.updatedAt
            }
            .map { Self.makePaneItem(note: $0.0, sourceTitle: $0.1) }

        let groupedPoints = filteredNotes
            .flatMap { note in
                note.knowledgePoints.map { point in
                    (
                        point: point,
                        note: note,
                        sourceTitle: sourceTitleLookup[note.sourceAnchor.sourceID] ?? Self.fallbackSourceTitle(for: note.sourceAnchor.sourceTitle)
                    )
                }
            }
            .reduce(into: [String: [(point: KnowledgePoint, note: Note, sourceTitle: String)]]()) { partialResult, entry in
                partialResult[entry.point.id, default: []].append(entry)
            }

        self.conceptItems = groupedPoints.compactMap { pointID, entries in
            guard let first = entries.first else { return nil }
            let definitions = entries
                .map(\.point.definition)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted { $0.count > $1.count }
            let relatedTitles = Array(
                Set(entries.flatMap(\.point.relatedKnowledgePointIDs))
            )
            .filter { $0 != pointID }
            .compactMap { knowledgePointTitleLookup[$0] }
            .sorted()

            return ConceptSummaryItem(
                id: pointID,
                knowledgePointID: pointID,
                title: first.point.title,
                definition: definitions.first ?? "点击查看相关原句和笔记。",
                noteCount: entries.count,
                sourceCount: Set(entries.map { $0.note.sourceAnchor.sourceID }).count,
                previewSourceTitle: entries
                    .sorted { $0.note.updatedAt > $1.note.updatedAt }
                    .first?.sourceTitle,
                relatedPointTitles: Array(relatedTitles.prefix(3))
            )
        }
        .sorted { lhs, rhs in
            if lhs.noteCount != rhs.noteCount {
                return lhs.noteCount > rhs.noteCount
            }
            return lhs.title.localizedCompare(rhs.title) == .orderedAscending
        }

        self.conceptPaneItems = filteredNotes
            .filter { !$0.knowledgePoints.isEmpty }
            .map { note in
                let sourceTitle = sourceTitleLookup[note.sourceAnchor.sourceID] ?? Self.fallbackSourceTitle(for: note.sourceAnchor.sourceTitle)
                return (note, sourceTitle)
            }
            .sorted { lhs, rhs in
                let leftPoint = lhs.0.knowledgePoints.first?.title ?? ""
                let rightPoint = rhs.0.knowledgePoints.first?.title ?? ""
                let pointOrder = leftPoint.localizedCompare(rightPoint)
                if pointOrder != .orderedSame {
                    return pointOrder == .orderedAscending
                }
                return lhs.0.updatedAt > rhs.0.updatedAt
            }
            .map { Self.makePaneItem(note: $0.0, sourceTitle: $0.1) }
    }

    func paneItems(for tab: NotesHomeTab) -> [NotesPaneItem] {
        switch tab {
        case .recent:
            return recentPaneItems
        case .source:
            return sourcePaneItems
        case .concept:
            return conceptPaneItems
        }
    }

    func firstNoteID(for tab: NotesHomeTab) -> UUID? {
        paneItems(for: tab).first?.noteID
    }
}

private extension NotesHomeViewModel {
    static func matchesFilter(_ note: Note, filter: NotesFilterMode) -> Bool {
        switch filter {
        case .all:
            return true
        case .tagged:
            return !note.tags.isEmpty
        case .knowledgePoints:
            return !note.linkedKnowledgePointIDs.isEmpty
        case .ink:
            return !note.inkBlocks.isEmpty
        }
    }

    static func matchesSearch(_ note: Note, searchText: String) -> Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let haystack = [
            note.title,
            note.sourceAnchor.sourceTitle,
            note.sourceAnchor.anchorLabel,
            note.sourceAnchor.quotedText,
            note.textBlocks.compactMap(\.text).joined(separator: "\n"),
            note.tags.joined(separator: " "),
            note.knowledgePoints.map(\.title).joined(separator: " "),
            note.knowledgePoints.map(\.definition).joined(separator: " ")
        ]
        .joined(separator: "\n")

        return haystack.localizedCaseInsensitiveContains(trimmed)
    }

    static func makeSummaryItem(note: Note, sourceTitle: String) -> NoteSummaryItem {
        let snippet = note.textBlocks
            .compactMap(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
            ?? note.sourceAnchor.quotedText

        return NoteSummaryItem(
            id: note.id,
            noteID: note.id,
            title: preferredNoteTitle(note.title, fallback: note.sourceAnchor.anchorLabel),
            snippet: snippet,
            sourceTitle: sourceTitle,
            anchorLabel: note.sourceAnchor.anchorLabel,
            updatedAt: note.updatedAt,
            tags: note.tags,
            knowledgePointTitles: note.knowledgePoints.map(\.title),
            hasInk: !note.inkBlocks.isEmpty
        )
    }

    static func makePaneItem(note: Note, sourceTitle: String) -> NotesPaneItem {
        let title = preferredNoteTitle(note.title, fallback: note.sourceAnchor.anchorLabel)
        let summary = note.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? note.sourceAnchor.quotedText
            : note.summary

        var badges: [String] = []
        if !note.inkBlocks.isEmpty {
            badges.append("含手写")
        }
        if !note.knowledgePoints.isEmpty {
            badges.append("关联知识点")
        } else if let tag = note.tags
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            badges.append(tag)
        }

        return NotesPaneItem(
            id: note.id,
            noteID: note.id,
            title: title,
            subtitle: sourceTitle,
            summary: summary,
            updatedAt: note.updatedAt,
            badges: Array(badges.prefix(2))
        )
    }

    static func preferredNoteTitle(_ title: String, fallback: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    static func preferredSourceTitle(for document: SourceDocument) -> String {
        let candidates = [
            cleanDisplayTitle(document.title),
            document.sectionTitles
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty && !looksLikeRawTitle($0) }),
            prettifiedFileTitle(document.title)
        ].compactMap { $0 }

        return candidates.first ?? "英语资料"
    }

    static func fallbackSourceTitle(for rawTitle: String) -> String {
        cleanDisplayTitle(rawTitle)
            ?? prettifiedFileTitle(rawTitle)
            ?? "英语资料"
    }

    static func subtitle(for document: SourceDocument?, latestNote: Note) -> String {
        let typeLabel = document?.documentType.displayName ?? "学习资料"
        let pointCount = latestNote.knowledgePoints.count
        if pointCount > 0 {
            return "\(typeLabel) · \(pointCount) 个知识点"
        }
        if !latestNote.tags.isEmpty {
            return "\(typeLabel) · \(latestNote.tags.count) 个标签"
        }
        return typeLabel
    }

    static func cleanDisplayTitle(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if looksLikeRawTitle(trimmed) {
            return nil
        }
        return trimmed
    }

    static func looksLikeRawTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let rawPattern = #"^[A-Za-z0-9._/-]+$"#
        let onlyFileCharacters = trimmed.range(of: rawPattern, options: .regularExpression) != nil
        let hasFileSeparators = trimmed.contains("_") || trimmed.contains("/") || trimmed.contains("\\") || trimmed.contains(".pdf")
        let hasNoSpaces = !trimmed.contains(" ")
        return onlyFileCharacters && (hasFileSeparators || hasNoSpaces)
    }

    static func prettifiedFileTitle(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let noExtension = trimmed.replacingOccurrences(
            of: #"\.[A-Za-z0-9]{1,6}$"#,
            with: "",
            options: .regularExpression
        )
        let separated = noExtension
            .replacingOccurrences(of: #"[_\-]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !separated.isEmpty else { return nil }

        let asciiOnly = separated.range(of: #"^[A-Za-z0-9 ]+$"#, options: .regularExpression) != nil
        if asciiOnly {
            return separated
                .split(separator: " ")
                .map { word in
                    let lower = word.lowercased()
                    return lower.prefix(1).uppercased() + lower.dropFirst()
                }
                .joined(separator: " ")
        }

        return separated
    }
}
