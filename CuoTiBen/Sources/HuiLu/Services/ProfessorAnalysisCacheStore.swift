import Foundation

struct ProfessorAnalysisDelta: Codable {
    let schemaVersion: String
    let storedAt: Date
    let passageOverview: PassageOverview?
    let paragraphCards: [ParagraphTeachingCard]
    let sentenceCards: [ProfessorSentenceCard]
    let passageAnalysisDiagnostics: PassageAnalysisDiagnostics?
    let passageAnalysisIdentity: PassageAnalysisIdentity?
}

actor ProfessorAnalysisCacheStore {
    enum CacheSource {
        case memory
        case disk
    }

    struct CacheHit {
        let delta: ProfessorAnalysisDelta
        let source: CacheSource
    }

    static let analysisSchemaVersion = "professor-analysis.v2"

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let storageDirectoryURL: URL
    private let maxMemoryEntries = 48

    private var memoryCache: [String: ProfessorAnalysisDelta] = [:]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.storageDirectoryURL = baseURL
            .appendingPathComponent("CuoTiBen", isDirectory: true)
            .appendingPathComponent("AIRequestCache", isDirectory: true)
            .appendingPathComponent("ProfessorAnalysis", isDirectory: true)
    }

    func lookup(
        forKey key: String,
        allowDisk: Bool
    ) async -> CacheHit? {
        if let cached = memoryCache[key] {
            return CacheHit(delta: cached, source: .memory)
        }

        guard allowDisk else { return nil }
        guard let delta = await loadDelta(forKey: key) else { return nil }

        memoryCache[key] = delta
        trimMemoryCacheIfNeeded()
        return CacheHit(delta: delta, source: .disk)
    }

    func store(
        _ delta: ProfessorAnalysisDelta,
        forKey key: String,
        persistToDisk: Bool
    ) async {
        memoryCache[key] = delta
        trimMemoryCacheIfNeeded()

        guard persistToDisk else { return }
        await persist(delta, forKey: key)
    }

    private func loadDelta(forKey key: String) async -> ProfessorAnalysisDelta? {
        let url = fileURL(forKey: key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            return try await MainActor.run {
                try decoder.decode(ProfessorAnalysisDelta.self, from: data)
            }
        } catch {
            try? fileManager.removeItem(at: url)
            return nil
        }
    }

    private func persist(_ delta: ProfessorAnalysisDelta, forKey key: String) async {
        let directoryURL = storageDirectoryURL
        let fileURL = fileURL(forKey: key)

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try await MainActor.run {
                try encoder.encode(delta)
            }
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }

    private func fileURL(forKey key: String) -> URL {
        storageDirectoryURL.appendingPathComponent("\(key).json", isDirectory: false)
    }

    private func trimMemoryCacheIfNeeded() {
        guard memoryCache.count > maxMemoryEntries else { return }

        let overflow = memoryCache.count - maxMemoryEntries
        let keysToRemove = memoryCache
            .sorted { lhs, rhs in
                lhs.value.storedAt < rhs.value.storedAt
            }
            .prefix(overflow)
            .map(\.key)

        for key in keysToRemove {
            memoryCache.removeValue(forKey: key)
        }
    }

    static func cacheKey(
        documentID: UUID,
        title: String,
        bundle: StructuredSourceBundle
    ) -> String {
        let rawKey = [
            analysisSchemaVersion,
            documentID.uuidString,
            normalize(title),
            stableHash(of: normalize(bundle.source.cleanedText))
        ].joined(separator: "\u{1E}")
        return stableHash(of: rawKey)
    }

    static func makeDelta(from enrichedBundle: StructuredSourceBundle) -> ProfessorAnalysisDelta {
        ProfessorAnalysisDelta(
            schemaVersion: analysisSchemaVersion,
            storedAt: Date(),
            passageOverview: enrichedBundle.passageOverview,
            paragraphCards: enrichedBundle.paragraphTeachingCards.filter(\.isAIGenerated),
            sentenceCards: enrichedBundle.professorSentenceCards.filter { $0.analysis.isAIGenerated },
            passageAnalysisDiagnostics: enrichedBundle.passageAnalysisDiagnostics,
            passageAnalysisIdentity: enrichedBundle.passageAnalysisIdentity
        )
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stableHash(of text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3

        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }

        return String(hash, radix: 16)
    }
}

extension StructuredSourceBundle {
    func removingProfessorAnalysis() -> StructuredSourceBundle {
        let provisionalBundle = StructuredSourceBundle(
            source: source,
            segments: segments,
            sentences: sentences,
            outline: outline,
            zoningSummary: zoningSummary
        )
        let passageMap = MindMapAdmissionService.buildPassageMap(from: provisionalBundle)
        let admissionResult = MindMapAdmissionService.admit(bundle: provisionalBundle, passageMap: passageMap)
        return StructuredSourceBundle(
            source: provisionalBundle.source,
            segments: provisionalBundle.segments,
            sentences: provisionalBundle.sentences,
            outline: provisionalBundle.outline,
            zoningSummary: provisionalBundle.zoningSummary,
            passageMap: passageMap.withDiagnostics(admissionResult.diagnostics),
            mindMapAdmissionResult: admissionResult
        )
    }

    func applyingProfessorAnalysis(_ delta: ProfessorAnalysisDelta) -> StructuredSourceBundle {
        enrichedWithAIAnalysis(
            overview: delta.passageOverview,
            paragraphCards: delta.paragraphCards,
            sentenceCards: delta.sentenceCards,
            passageAnalysisDiagnostics: delta.passageAnalysisDiagnostics,
            passageAnalysisIdentity: delta.passageAnalysisIdentity
        )
    }
}
