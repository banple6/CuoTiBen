import Foundation

actor SentenceAnalysisCacheStore {
    enum CacheSource {
        case memory
        case disk
    }

    struct CacheHit {
        let result: AIExplainSentenceResult
        let source: CacheSource
    }

    struct StoredSentenceAnalysis: Codable {
        let promptVersion: String
        let storedAt: Date
        let result: AIExplainSentenceResult
    }

    static let promptVersion = "sentence-explain.v2"

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let storageDirectoryURL: URL
    private let maxMemoryEntries = 128

    private var memoryCache: [String: StoredSentenceAnalysis] = [:]

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
            .appendingPathComponent("SentenceAnalysis", isDirectory: true)
    }

    func lookup(
        forKey key: String,
        allowDisk: Bool
    ) async -> CacheHit? {
        if let cached = memoryCache[key] {
            return CacheHit(result: cached.result, source: .memory)
        }

        guard allowDisk else { return nil }
        guard let record = await loadRecord(forKey: key) else { return nil }

        memoryCache[key] = record
        trimMemoryCacheIfNeeded()
        return CacheHit(result: record.result, source: .disk)
    }

    func store(
        _ result: AIExplainSentenceResult,
        forKey key: String,
        promptVersion: String = promptVersion,
        persistToDisk: Bool
    ) async {
        let record = StoredSentenceAnalysis(
            promptVersion: promptVersion,
            storedAt: Date(),
            result: result
        )
        memoryCache[key] = record
        trimMemoryCacheIfNeeded()

        guard persistToDisk else { return }
        await persist(record, forKey: key)
    }

    func remove(forKey key: String) {
        memoryCache.removeValue(forKey: key)
        try? fileManager.removeItem(at: fileURL(forKey: key))
    }

    private func loadRecord(forKey key: String) async -> StoredSentenceAnalysis? {
        let url = fileURL(forKey: key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            return try await MainActor.run {
                try decoder.decode(StoredSentenceAnalysis.self, from: data)
            }
        } catch {
            try? fileManager.removeItem(at: url)
            return nil
        }
    }

    private func persist(_ record: StoredSentenceAnalysis, forKey key: String) async {
        let directoryURL = storageDirectoryURL
        let fileURL = fileURL(forKey: key)

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try await MainActor.run {
                try encoder.encode(record)
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
        for context: ExplainSentenceContext,
        baseURL: String
    ) -> String {
        let normalizedBaseURL = normalize(baseURL)
        let identity = identityPayload(for: context)
        let rawKey = [
            promptVersion,
            normalizedBaseURL,
            identity.sourceSentenceID,
            identity.sourceSentenceTextHash,
            identity.sourceAnchorLabel
        ].joined(separator: "\u{1E}")

        return stableHash(of: rawKey)
    }

    private static func identityPayload(for context: ExplainSentenceContext) -> (
        sourceSentenceID: String,
        sourceSentenceTextHash: String,
        sourceAnchorLabel: String
    ) {
        let sentenceID = normalize(context.sentenceID)
        let anchorLabel = normalize(context.anchorLabel)
        return (
            sourceSentenceID: sentenceID.isEmpty ? stableHash(of: normalize(context.sentence)) : sentenceID,
            sourceSentenceTextHash: stableHash(of: normalize(context.sentence).lowercased()),
            sourceAnchorLabel: anchorLabel.isEmpty ? "unknown-anchor" : anchorLabel
        )
    }

    private static func normalize(_ value: String?) -> String {
        (value ?? "")
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
