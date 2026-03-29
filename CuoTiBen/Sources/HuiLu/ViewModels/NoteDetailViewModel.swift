import Foundation

@MainActor
struct NoteDetailViewModel {
    let note: Note
    let sourceDocument: SourceDocument?
    let context: LearningRecordContext
    let linkedKnowledgePoints: [KnowledgePoint]

    init(
        note: Note,
        sourceDocument: SourceDocument?,
        context: LearningRecordContext,
        linkedKnowledgePoints: [KnowledgePoint]
    ) {
        self.note = note
        self.sourceDocument = sourceDocument
        self.context = context
        self.linkedKnowledgePoints = linkedKnowledgePoints
    }

    init(note: Note, appViewModel: AppViewModel) {
        let resolvedNote = appViewModel.note(with: note.id) ?? note
        let linkedKnowledgePoints = NoteDetailViewModel.resolveLinkedKnowledgePoints(
            for: resolvedNote,
            using: appViewModel
        )
        self.init(
            note: resolvedNote,
            sourceDocument: appViewModel.sourceDocument(for: resolvedNote.sourceAnchor),
            context: appViewModel.learningRecordContext(forNoteID: resolvedNote.id),
            linkedKnowledgePoints: linkedKnowledgePoints
        )
    }

    var title: String {
        note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? note.sourceAnchor.anchorLabel
            : note.title
    }

    var sourceTitle: String {
        note.sourceAnchor.sourceTitle
    }

    var sourceSubtitle: String {
        [
            note.sourceAnchor.sourceTitle,
            pageLabel,
            note.sourceAnchor.anchorLabel
        ]
        .compactMap { $0?.trimmedNonEmpty }
        .joined(separator: " · ")
    }

    var pageLabel: String? {
        note.sourceAnchor.pageIndex.map { "第\($0)页" }
    }

    var anchorLabel: String {
        note.sourceAnchor.anchorLabel
    }

    var quoteText: String {
        note.quoteBlock?.text?.trimmedNonEmpty
            ?? note.sourceAnchor.quotedText
    }

    var quoteBlocks: [NoteBlock] {
        let blocks = note.blocks.filter { $0.kind == .quote }
        return blocks.isEmpty ? [.quote(quoteText)] : blocks
    }

    var textBlocks: [NoteBlock] {
        note.blocks.filter { $0.kind == .text }
    }

    var inkBlocks: [NoteBlock] {
        note.inkBlocks
    }

    var knowledgePoints: [KnowledgePoint] {
        linkedKnowledgePoints
    }

    var suggestedKnowledgePoints: [KnowledgePoint] {
        let linkedIDs = Set(linkedKnowledgePoints.map(\.id))
        return context.relatedKnowledgePoints.filter { !linkedIDs.contains($0.id) }
    }

    var relatedCards: [LearningRecordCardItem] {
        Array(context.relatedCards.prefix(4))
    }

    var relatedSourceAnchors: [SourceAnchor] {
        var seen: Set<String> = []
        return context.relatedSourceAnchors
            .filter { $0.id != note.sourceAnchor.id }
            .filter { seen.insert($0.id).inserted }
    }

    var relatedNotes: [Note] {
        context.relatedNotes.filter { $0.id != note.id }
    }

    var lastEditedText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: note.updatedAt, relativeTo: Date())
    }
}

extension NoteDetailViewModel {
    static func resolveLinkedKnowledgePoints(for note: Note, using appViewModel: AppViewModel) -> [KnowledgePoint] {
        let explicitPoints = note.knowledgePoints
        let resolvedPoints = appViewModel.linkedKnowledgePoints(for: note.linkedKnowledgePointIDs)
        let merged = explicitPoints + resolvedPoints

        var seen = Set<String>()
        return merged.filter { point in
            guard !point.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            return seen.insert(point.id).inserted
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
