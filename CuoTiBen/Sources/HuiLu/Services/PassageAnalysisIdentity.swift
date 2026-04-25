import Foundation

struct PassageAnalysisIdentity: Codable, Equatable, Hashable {
    let documentID: String
    let contentHash: String
    let materialMode: MaterialAnalysisMode
    let acceptedParagraphCount: Int
    let sourceTitle: String

    private enum CodingKeys: String, CodingKey {
        case documentID = "document_id"
        case contentHash = "content_hash"
        case materialMode = "material_mode"
        case acceptedParagraphCount = "accepted_paragraph_count"
        case sourceTitle = "source_title"
    }

    init(
        documentID: String,
        contentHash: String,
        materialMode: MaterialAnalysisMode,
        acceptedParagraphCount: Int,
        sourceTitle: String
    ) {
        self.documentID = Self.normalize(documentID)
        self.contentHash = Self.normalize(contentHash)
        self.materialMode = materialMode
        self.acceptedParagraphCount = max(acceptedParagraphCount, 0)
        self.sourceTitle = Self.normalize(sourceTitle)
    }

    init?(dictionary: [String: Any]?) {
        guard let dictionary else { return nil }
        let documentID = Self.normalize(dictionary["document_id"] as? String)
        let contentHash = Self.normalize(dictionary["content_hash"] as? String)
        let materialModeRaw = Self.normalize(dictionary["material_mode"] as? String)
        guard !documentID.isEmpty,
              !contentHash.isEmpty,
              let materialMode = MaterialAnalysisMode(rawValue: materialModeRaw)
        else {
            return nil
        }

        self.init(
            documentID: documentID,
            contentHash: contentHash,
            materialMode: materialMode,
            acceptedParagraphCount: dictionary["accepted_paragraph_count"] as? Int ?? 0,
            sourceTitle: dictionary["source_title"] as? String ?? ""
        )
    }

    static func make(
        document: SourceDocument,
        bundle: StructuredSourceBundle,
        materialMode: MaterialAnalysisMode,
        acceptedParagraphCount: Int? = nil,
        contentHash overrideContentHash: String? = nil
    ) -> PassageAnalysisIdentity {
        let resolvedHash = normalize(overrideContentHash).nonEmpty
            ?? contentHash(for: bundle, materialMode: materialMode)
        return PassageAnalysisIdentity(
            documentID: document.id.uuidString,
            contentHash: resolvedHash,
            materialMode: materialMode,
            acceptedParagraphCount: acceptedParagraphCount ?? acceptedParagraphCountForIdentity(in: bundle, materialMode: materialMode),
            sourceTitle: document.title
        )
    }

    static func contentHash(
        for bundle: StructuredSourceBundle,
        materialMode: MaterialAnalysisMode
    ) -> String {
        let normalizedSegments = identitySegments(in: bundle, materialMode: materialMode)
            .map { segment in
                let normalized = segment.text.normalizedIdentityText
                return materialMode == .passageReading
                    ? String(normalized.prefix(700))
                    : normalized
            }
            .filter { !$0.isEmpty }

        if !normalizedSegments.isEmpty {
            return AIRequestIdentity.hash(text: normalizedSegments.joined(separator: "\n\n"))
        }

        return AIRequestIdentity.hash(text: bundle.source.cleanedText)
    }

    static func contentHash(forParagraphTexts texts: [String]) -> String {
        AIRequestIdentity.hash(
            text: texts
                .map { $0.normalizedIdentityText }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        )
    }

    private static func identitySegments(
        in bundle: StructuredSourceBundle,
        materialMode: MaterialAnalysisMode
    ) -> [Segment] {
        let nonEmptySegments = bundle.segments
            .filter { !$0.text.normalizedIdentityText.isEmpty }
            .sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.id < rhs.id
            }

        switch materialMode {
        case .passageReading:
            return Array(nonEmptySegments.filter { $0.provenance.sourceKind == .passageBody }.prefix(4))
        case .learningMaterial:
            return Array(nonEmptySegments.filter {
                $0.provenance.sourceKind == .chineseInstruction
                || $0.provenance.sourceKind == .passageHeading
                || $0.provenance.sourceKind == .bilingualNote
            }.prefix(4))
        case .vocabularyNotes:
            return Array(nonEmptySegments.filter {
                $0.provenance.sourceKind == .vocabularySupport
                || $0.provenance.sourceKind == .bilingualNote
                || $0.provenance.sourceKind == .chineseInstruction
            }.prefix(4))
        case .questionSheet:
            return Array(nonEmptySegments.filter {
                $0.provenance.sourceKind == .question
                || $0.provenance.sourceKind == .answerKey
            }.prefix(4))
        case .auxiliaryOnlyMap:
            return Array(nonEmptySegments.filter { $0.provenance.sourceKind != .passageBody }.prefix(4))
        case .insufficientText:
            return Array(nonEmptySegments.prefix(4))
        }
    }

    private static func acceptedParagraphCountForIdentity(
        in bundle: StructuredSourceBundle,
        materialMode: MaterialAnalysisMode
    ) -> Int {
        identitySegments(in: bundle, materialMode: materialMode).count
    }

    private static func normalize(_ value: String?) -> String {
        (value ?? "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var normalizedIdentityText: String {
        replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
