import SwiftUI

struct NoteDetailView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    let note: Note
    let onOpenSource: ((SourceAnchor) -> Void)?

    private var currentNote: Note {
        viewModel.note(with: note.id) ?? note
    }

    var body: some View {
        ZStack {
            AppBackground(style: .light)

            NoteDetailPane(
                note: currentNote,
                onOpenSource: onOpenSource
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .navigationTitle("笔记详情")
        .navigationBarTitleDisplayMode(.inline)
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
