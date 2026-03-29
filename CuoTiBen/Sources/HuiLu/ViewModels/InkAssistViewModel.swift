import Foundation
import Combine

@MainActor
final class InkAssistViewModel: ObservableObject {
    @Published var activeSuggestion: InkAssistSuggestion?
    @Published var highlightedKnowledgePointID: String?

    private let coordinator: InkAssistCoordinator
    private var autoDismissTask: Task<Void, Never>?

    init(coordinator: InkAssistCoordinator? = nil) {
        self.coordinator = coordinator ?? InkAssistCoordinator()
    }

    func handleDrawingDidSettle(
        block: NoteBlock,
        sourceAnchor: SourceAnchor?,
        knowledgePoints: [KnowledgePoint]
    ) {
        coordinator.scheduleSuggestion(
            for: block,
            sourceAnchor: sourceAnchor,
            knowledgePoints: knowledgePoints
        ) { [weak self] suggestion in
            guard let self else { return }
            activeSuggestion = suggestion
            highlightedKnowledgePointID = suggestion?.matchedKnowledgePointID
            scheduleAutoDismiss()
        }
    }

    func handleResumeWriting() {
        hideSuggestion()
    }

    func confirmSuggestion(apply: (InkAssistSuggestion) -> Void) {
        guard let activeSuggestion else { return }
        apply(activeSuggestion)
        hideSuggestion()
    }

    func hideSuggestion() {
        autoDismissTask?.cancel()
        activeSuggestion = nil
        highlightedKnowledgePointID = nil
        coordinator.cancel()
    }

    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()

        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5.0))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.activeSuggestion = nil
                self?.highlightedKnowledgePointID = nil
            }
        }
    }
}
