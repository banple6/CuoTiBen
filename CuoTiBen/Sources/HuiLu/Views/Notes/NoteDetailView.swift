import SwiftUI

struct NoteDetailView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    let note: Note
    let onOpenSource: ((SourceAnchor) -> Void)?

    private var currentNote: Note {
        viewModel.note(with: note.id) ?? note
    }

    var body: some View {
        NoteDetailPane(
            note: currentNote,
            onOpenSource: onOpenSource
        )
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(
            Color(red: 251 / 255, green: 249 / 255, blue: 244 / 255), // surface
            for: .navigationBar
        )
    }
}

struct NoteDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NoteDetailPreview()
    }
}

private struct NoteDetailPreview: View {
    @StateObject private var appViewModel = AppViewModel()

    var body: some View {
        NavigationStack {
            if let note = appViewModel.notes.first {
                NoteDetailView(note: note, onOpenSource: nil)
                    .environmentObject(appViewModel)
            } else {
                Text("暂无预览笔记")
            }
        }
    }
}
