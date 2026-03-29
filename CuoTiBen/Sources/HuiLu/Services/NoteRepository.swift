import Foundation

final class NoteRepository {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let storageURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.storageURL = baseURL
            .appendingPathComponent("CuoTiBen", isDirectory: true)
            .appendingPathComponent("notes.json", isDirectory: false)
    }

    @discardableResult
    func createNote(from sentence: Sentence, anchor: SourceAnchor) throws -> Note {
        var notes = try fetchAllNotes()
        let note = Note(
            title: "笔记：\(anchor.anchorLabel)",
            sourceAnchor: anchor,
            blocks: [
                .quote(trimmed(anchor.quotedText) ?? sentence.text),
                .text("")
            ]
        )
        notes.insert(note, at: 0)
        try persist(notes)
        return note
    }

    func updateNote(_ note: Note) throws {
        var notes = try fetchAllNotes()

        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else {
            notes.insert(note, at: 0)
        }

        try persist(notes)
    }

    func fetchAllNotes() throws -> [Note] {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return []
        }

        let data = try Data(contentsOf: storageURL)
        let notes = try decoder.decode([Note].self, from: data)
        return notes.sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchNotes(for sourceID: UUID) throws -> [Note] {
        try fetchAllNotes().filter { $0.sourceAnchor.sourceID == sourceID }
    }

    func fetchNotes(for knowledgePointID: String) throws -> [Note] {
        try fetchAllNotes().filter { note in
            note.knowledgePoints.contains(where: { $0.id == knowledgePointID })
        }
    }

    func deleteNote(_ note: Note) throws {
        var notes = try fetchAllNotes()
        notes.removeAll { $0.id == note.id }
        try persist(notes)
    }

    private func persist(_ notes: [Note]) throws {
        let directoryURL = storageURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        let data = try encoder.encode(notes.sorted { $0.updatedAt > $1.updatedAt })
        try data.write(to: storageURL, options: .atomic)
    }

    private func trimmed(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
