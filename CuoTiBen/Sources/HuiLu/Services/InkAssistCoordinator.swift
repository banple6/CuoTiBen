import Foundation
import CoreGraphics

final class InkAssistCoordinator {
    private let recognitionService: InkRecognitionService
    private let matcher: KnowledgePointMatcher
    private var pendingTask: Task<Void, Never>?
    private var lastSuggestedAtByBlockID: [UUID: Date] = [:]

    init(
        recognitionService: InkRecognitionService,
        matcher: KnowledgePointMatcher
    ) {
        self.recognitionService = recognitionService
        self.matcher = matcher
    }

    convenience init() {
        self.init(
            recognitionService: InkRecognitionService(),
            matcher: KnowledgePointMatcher()
        )
    }

    func scheduleSuggestion(
        for block: NoteBlock,
        sourceAnchor: SourceAnchor?,
        knowledgePoints: [KnowledgePoint],
        delay: TimeInterval = 1.0,
        cooldown: TimeInterval = 10,
        threshold: Double = 0.62,
        onSuggestion: @MainActor @escaping (InkAssistSuggestion?) -> Void
    ) {
        pendingTask?.cancel()

        pendingTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }

            if let lastSuggestedAt = lastSuggestedAtByBlockID[block.id],
               Date().timeIntervalSince(lastSuggestedAt) < cooldown {
                await MainActor.run {
                    onSuggestion(nil)
                }
                return
            }

            guard let inkData = block.inkData,
                  !inkData.isEmpty,
                  let recognition = await recognitionService.recognizeText(from: inkData),
                  let match = matcher.bestMatch(
                    recognizedText: recognition.text,
                    sourceAnchor: sourceAnchor,
                    knowledgePoints: knowledgePoints
                  ),
                  match.score >= threshold,
                  !block.linkedKnowledgePointIDs.contains(match.point.id) else {
                await MainActor.run {
                    onSuggestion(nil)
                }
                return
            }

            lastSuggestedAtByBlockID[block.id] = Date()

            let suggestion = InkAssistSuggestion(
                blockID: block.id,
                sourceAnchorID: sourceAnchor?.id,
                matchedKnowledgePointID: match.point.id,
                matchedKnowledgePointTitle: match.point.title,
                recognizedText: recognition.text,
                recognitionConfidence: recognition.confidence,
                score: match.score,
                normalizedAnchorRect: block.inkGeometry?.normalizedBounds ?? .zero
            )

            await MainActor.run {
                onSuggestion(suggestion)
            }
        }
    }

    func cancel() {
        pendingTask?.cancel()
    }
}
