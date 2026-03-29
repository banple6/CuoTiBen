import SwiftUI

struct KnowledgePointDetailView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    let point: KnowledgePoint
    let onOpenSource: ((SourceAnchor) -> Void)?

    @State private var activeNote: Note?
    @State private var activeKnowledgePoint: KnowledgePoint?
    @State private var sourceJumpTarget: SourceJumpTarget?

    private var learningContext: LearningRecordContext {
        viewModel.learningRecordContext(forKnowledgePointID: point.id)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                SentenceExplainBlock(
                    title: point.title,
                    content: trimmedKnowledgePointText(point.definition) ?? "当前知识点尚未补充定义，可先通过相关原句和笔记回看上下文。",
                    tone: .structure
                )

                RelatedContextPanel(
                    context: learningContext,
                    hiddenKnowledgePointIDs: Set([point.id]),
                    onOpenNote: { note in
                        activeNote = note
                    },
                    onOpenKnowledgePoint: { relatedPoint in
                        activeKnowledgePoint = relatedPoint
                    },
                    onOpenSourceAnchor: { anchor in
                        openSource(anchor)
                    },
                    onOpenCard: { item in
                        if let anchor = item.sourceAnchor {
                            openSource(anchor)
                        }
                    }
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(AppBackground(style: .light))
        .navigationTitle("知识点")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeNote) { note in
            NavigationStack {
                NoteDetailView(note: note) { anchor in
                    openSource(anchor)
                }
                    .environmentObject(viewModel)
            }
        }
        .sheet(item: $activeKnowledgePoint) { point in
            NavigationStack {
                KnowledgePointDetailView(point: point) { anchor in
                    openSource(anchor)
                }
                    .environmentObject(viewModel)
            }
        }
        .fullScreenCover(item: $sourceJumpTarget) { target in
            ReviewWorkbenchView(document: target.document, initialAnchor: target.anchor) {
                sourceJumpTarget = nil
            }
            .environmentObject(viewModel)
        }
    }

    private func openSource(_ anchor: SourceAnchor) {
        if let target = viewModel.sourceJumpTarget(for: anchor) {
            if let onOpenSource {
                onOpenSource(target.anchor)
            } else {
                sourceJumpTarget = target
            }
            return
        }

        onOpenSource?(anchor)
    }
}

private func trimmedKnowledgePointText(_ value: String) -> String? {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
}
