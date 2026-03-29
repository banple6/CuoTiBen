import SwiftUI
import UIKit

struct InkBlockWorkspaceView: View {
    @Binding var block: NoteBlock

    let sourceAnchor: SourceAnchor
    let candidateKnowledgePoints: [KnowledgePoint]
    let onLinkKnowledgePoint: (String) -> Void

    @State private var drawingData: Data
    @StateObject private var inkAssistViewModel = InkAssistViewModel()

    init(
        block: Binding<NoteBlock>,
        sourceAnchor: SourceAnchor,
        candidateKnowledgePoints: [KnowledgePoint],
        onLinkKnowledgePoint: @escaping (String) -> Void
    ) {
        _block = block
        self.sourceAnchor = sourceAnchor
        self.candidateKnowledgePoints = candidateKnowledgePoints
        self.onLinkKnowledgePoint = onLinkKnowledgePoint
        _drawingData = State(initialValue: block.wrappedValue.inkData ?? Data())
    }

    private var linkedTitles: [String] {
        let lookup = Dictionary(uniqueKeysWithValues: candidateKnowledgePoints.map { ($0.id, $0.title) })
        return block.linkedKnowledgePointIDs.compactMap { lookup[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                NotesMetaPill(text: "手写", tint: .purple)
                if let recognizedText = block.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !recognizedText.isEmpty {
                    NotesMetaPill(text: "已识别", tint: .blue)
                }
                Spacer()
                NotesMetaPill(text: "Pencil", tint: .green)
            }

            InkNoteCanvasView(
                drawingData: $drawingData,
                toolState: .constant(NoteInkToolState()),
                pageCount: .constant(1),
                appearance: .paper,
                suggestion: inkAssistViewModel.activeSuggestion,
                onStopDrawing: { data, bounds, canvasSize in
                    handleInkDidSettle(data: data, bounds: bounds, canvasSize: canvasSize)
                },
                onResumeDrawing: {
                    inkAssistViewModel.handleResumeWriting()
                },
                onDismissSuggestion: {
                    inkAssistViewModel.hideSuggestion()
                },
                onConfirmSuggestion: {
                    confirmSuggestion()
                }
            )
            .frame(height: 260)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.62))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.92), lineWidth: 1)
                    )
            )

            if let suggestion = inkAssistViewModel.activeSuggestion {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.blue.opacity(0.82))
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("可能关联知识点：\(suggestion.matchedKnowledgePointTitle)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.82))

                        if !suggestion.recognizedText.isEmpty {
                            Text("识别到：\(suggestion.recognizedText)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.56))
                                .lineLimit(2)
                        }
                    }

                    Spacer()

                    Button("关联") {
                        confirmSuggestion()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.blue.opacity(0.88))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.blue.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.blue.opacity(0.18), lineWidth: 1)
                        )
                )
            }

            if let recognizedText = block.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !recognizedText.isEmpty {
                Text("识别结果：\(recognizedText)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.56))
                    .lineLimit(2)
            }

            if !linkedTitles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(linkedTitles, id: \.self) { title in
                            NotesMetaPill(text: title, tint: .blue)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.92), lineWidth: 1)
                )
        )
        .onChange(of: block.inkData) { newValue in
            drawingData = newValue ?? Data()
        }
    }

    private func handleInkDidSettle(data: Data, bounds: CGRect, canvasSize: CGSize) {
        guard !data.isEmpty, canvasSize.width > 0, canvasSize.height > 0, !bounds.isEmpty else {
            inkAssistViewModel.hideSuggestion()
            return
        }

        block.inkData = data
        block.linkedSourceAnchorID = sourceAnchor.id
        block.inkGeometry = InkGeometry(
            normalizedBounds: normalizedBounds(bounds, in: canvasSize),
            pageIndex: sourceAnchor.pageIndex
        )
        block.lastRecognitionAt = Date()

        inkAssistViewModel.handleDrawingDidSettle(
            block: block,
            sourceAnchor: sourceAnchor,
            knowledgePoints: candidateKnowledgePoints
        )
    }

    private func confirmSuggestion() {
        inkAssistViewModel.confirmSuggestion { suggestion in
            block.recognizedText = suggestion.recognizedText
            block.recognitionConfidence = suggestion.recognitionConfidence
            block.linkedSourceAnchorID = suggestion.sourceAnchorID ?? sourceAnchor.id
            block.lastSuggestionAt = Date()

            if !block.linkedKnowledgePointIDs.contains(suggestion.matchedKnowledgePointID) {
                block.linkedKnowledgePointIDs.append(suggestion.matchedKnowledgePointID)
            }

            onLinkKnowledgePoint(suggestion.matchedKnowledgePointID)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func normalizedBounds(_ bounds: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: min(max(bounds.origin.x / size.width, 0), 1),
            y: min(max(bounds.origin.y / size.height, 0), 1),
            width: min(max(bounds.width / size.width, 0), 1),
            height: min(max(bounds.height / size.height, 0), 1)
        )
    }
}
