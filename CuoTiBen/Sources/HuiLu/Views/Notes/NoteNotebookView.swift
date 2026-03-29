import SwiftUI

struct NoteNotebookView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    let note: Note
    var onOpenSource: ((SourceAnchor) -> Void)? = nil

    var body: some View {
        NoteWorkspaceView(note: note, onOpenSource: onOpenSource)
            .environmentObject(appViewModel)
    }
}

struct NoteNotebookView_Previews: PreviewProvider {
    static var previews: some View {
        NoteNotebookPreview()
    }
}

private struct NoteNotebookPreview: View {
    @StateObject private var appViewModel = AppViewModel()

    var body: some View {
        if let note = appViewModel.notes.first {
            NoteNotebookView(note: note)
                .environmentObject(appViewModel)
        } else {
            Text("暂无预览笔记")
        }
    }
}
