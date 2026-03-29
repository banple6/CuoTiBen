import SwiftUI

struct RelatedContextPanel: View {
    let context: LearningRecordContext
    var hiddenNoteIDs: Set<UUID> = []
    var hiddenKnowledgePointIDs: Set<String> = []
    var onOpenNote: (Note) -> Void
    var onOpenKnowledgePoint: (KnowledgePoint) -> Void
    var onOpenSourceAnchor: (SourceAnchor) -> Void
    var onOpenCard: (LearningRecordCardItem) -> Void

    private var visibleNotes: [Note] {
        context.relatedNotes.filter { !hiddenNoteIDs.contains($0.id) }
    }

    private var visibleKnowledgePoints: [KnowledgePoint] {
        context.relatedKnowledgePoints.filter { !hiddenKnowledgePointIDs.contains($0.id) }
    }

    private var visibleAnchors: [SourceAnchor] {
        context.relatedSourceAnchors
    }

    private var visibleCards: [LearningRecordCardItem] {
        context.relatedCards
    }

    private var hasContent: Bool {
        !visibleNotes.isEmpty ||
        !visibleKnowledgePoints.isEmpty ||
        !visibleAnchors.isEmpty ||
        !visibleCards.isEmpty
    }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("相关内容")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.82))

                    Spacer()

                    Text("联动")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.blue.opacity(0.72))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.blue.opacity(0.08)))
                }

                if !visibleNotes.isEmpty {
                    RelatedNotesSection(notes: visibleNotes, onOpenNote: onOpenNote)
                }

                if !visibleKnowledgePoints.isEmpty {
                    RelatedKnowledgePointsSection(
                        knowledgePoints: visibleKnowledgePoints,
                        onOpenKnowledgePoint: onOpenKnowledgePoint
                    )
                }

                if !visibleAnchors.isEmpty {
                    RelatedSourceAnchorsSection(
                        anchors: visibleAnchors,
                        onOpenSourceAnchor: onOpenSourceAnchor
                    )
                }

                if !visibleCards.isEmpty {
                    RelatedCardsSection(cards: visibleCards, onOpenCard: onOpenCard)
                }
            }
        }
    }
}

struct RelatedContextSectionContainer<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.72))

            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.86), lineWidth: 1)
                )
        )
    }
}

struct RelatedContextCompactRow<Leading: View, Trailing: View>: View {
    let leading: Leading
    let trailing: Trailing
    var isLast: Bool = false

    init(
        isLast: Bool = false,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.isLast = isLast
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                leading
                Spacer(minLength: 8)
                trailing
            }

            if !isLast {
                Divider()
                    .overlay(Color.black.opacity(0.06))
            }
        }
    }
}
