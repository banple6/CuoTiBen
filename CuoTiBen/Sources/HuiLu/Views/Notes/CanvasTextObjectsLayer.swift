import SwiftUI
import UIKit

struct CanvasTextObjectsLayer: View {
    @ObservedObject var vm: NoteWorkspaceViewModel
    let appViewModel: AppViewModel
    let isTextToolActive: Bool
    let canManipulateTextObjects: Bool
    @Binding var editorSelection: EditorSelection
    let pageWidth: CGFloat
    let pageHeight: CGFloat

    @State private var editingObjectID: UUID?
    @State private var lastEditDismissTime: Date = .distantPast

    private enum InteractionState: Equatable {
        case idle
        case selected(UUID)
        case editing(UUID)
    }

    private var interactionState: InteractionState {
        if let editingObjectID {
            return .editing(editingObjectID)
        }
        if case .textObject(let id) = editorSelection {
            return .selected(id)
        }
        return .idle
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if canManipulateTextObjects {
                Color.clear
                    .frame(width: pageWidth, height: pageHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let hitExisting = vm.textObjects.contains { obj in
                            obj.frame.insetBy(dx: -14, dy: -14).contains(location)
                        }
                        if hitExisting { return }

                        if Date().timeIntervalSince(lastEditDismissTime) < 0.4 {
                            return
                        }

                        switch interactionState {
                        case .editing(let currentID):
                            requestExitEditing(selectedID: currentID)
                            return
                        case .selected:
                            editorSelection = .none
                            return
                        case .idle:
                            break
                        }

                        guard isTextToolActive else { return }

                        let defaultWidth = min(260.0, pageWidth - location.x - 20)
                        let newID = vm.createTextObject(
                            at: CGPoint(x: location.x, y: location.y),
                            width: max(defaultWidth, 120)
                        )
                        DispatchQueue.main.async {
                            editingObjectID = newID
                            editorSelection = .textObject(newID)
                        }
                    }
                    .allowsHitTesting(canManipulateTextObjects)
            }

            ForEach(vm.textObjects.filter { !$0.isHidden }.sorted(by: { $0.zIndex < $1.zIndex })) { obj in
                CanvasTextObjectContainer(
                    obj: obj,
                    isSelected: isSelected(obj.id),
                    isEditing: isEditing(obj.id),
                    allowsTransforms: !obj.isLocked,
                    pageWidth: pageWidth,
                    pageHeight: pageHeight,
                    onTextChange: { vm.updateTextObject(id: obj.id, text: $0) },
                    onHeightChange: { newHeight in
                        guard editingObjectID == obj.id else { return }
                        vm.resizeTextObject(id: obj.id, width: obj.width, height: max(newHeight, obj.minHeight))
                    },
                    onSelect: {
                        editingObjectID = nil
                        editorSelection = .textObject(obj.id)
                    },
                    onStartEditing: {
                        guard !obj.isLocked else { return }
                        editingObjectID = obj.id
                        editorSelection = .textObject(obj.id)
                    },
                    onEndEditing: {
                        guard editingObjectID == obj.id else { return }
                        editingObjectID = nil
                        lastEditDismissTime = Date()
                        vm.scheduleAutosave(using: appViewModel)
                    },
                    onCommitMove: { newPosition in
                        vm.moveTextObject(id: obj.id, to: newPosition)
                        vm.scheduleAutosave(using: appViewModel)
                    },
                    onCommitResize: { newX, newY, newWidth, newHeight in
                        vm.resizeTextObject(
                            id: obj.id,
                            x: newX,
                            y: newY,
                            width: newWidth,
                            height: newHeight
                        )
                        vm.scheduleAutosave(using: appViewModel)
                    }
                )
                .zIndex(isSelected(obj.id) || isEditing(obj.id) ? 10_000 : Double(obj.zIndex))
            }
            .allowsHitTesting(canManipulateTextObjects)
        }
        .frame(width: pageWidth, height: pageHeight)
        .onChange(of: editorSelection) { newSelection in
            if case .textObject = newSelection { return }
            editingObjectID = nil
        }
    }

    private func isSelected(_ id: UUID) -> Bool {
        if case .textObject(let selectedID) = editorSelection {
            return selectedID == id
        }
        return false
    }

    private func isEditing(_ id: UUID) -> Bool {
        editingObjectID == id
    }

    private func requestExitEditing(selectedID: UUID) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        editingObjectID = nil
        lastEditDismissTime = Date()
        editorSelection = .textObject(selectedID)
    }
}
