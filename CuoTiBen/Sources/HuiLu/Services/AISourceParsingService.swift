import Foundation
import NaturalLanguage

private struct ParseSourceRequestAnchor: Encodable {
    let anchorID: String
    let page: Int?
    let label: String
    let text: String

    private enum CodingKeys: String, CodingKey {
        case anchorID = "anchor_id"
        case page
        case label
        case text
    }
}

private struct ParseSourceRequest: Encodable {
    let sourceID: String
    let title: String
    let rawText: String
    let sourceType: String
    let pageCount: Int
    let anchors: [ParseSourceRequestAnchor]

    private enum CodingKeys: String, CodingKey {
        case sourceID = "source_id"
        case title
        case rawText = "raw_text"
        case sourceType = "source_type"
        case pageCount = "page_count"
        case anchors
    }
}

private struct ParseSourceResponseEnvelope: Decodable {
    let success: Bool
    let data: StructuredSourceResponse?
    let error: String?
}

private struct StructuredSourceResponse: Decodable {
    let source: Source
    let sectionTitles: [String]
    let topicTags: [String]
    let candidateKnowledgePoints: [String]
    let segments: [Segment]
    let sentences: [Sentence]
    let outline: [OutlineNode]

    private enum CodingKeys: String, CodingKey {
        case source
        case sectionTitles = "section_titles"
        case topicTags = "topic_tags"
        case candidateKnowledgePoints = "candidate_knowledge_points"
        case segments
        case sentences
        case outline
    }
}

struct StructuredSourceParsePayload {
    let bundle: StructuredSourceBundle
    let sectionTitles: [String]
    let topicTags: [String]
    let candidateKnowledgePoints: [String]
}

enum AISourceParsingServiceError: LocalizedError {
    case invalidBaseURL
    case invalidServerResponse
    case requestFailed(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "结构化解析服务地址无效。"
        case .invalidServerResponse:
            return "结构化解析返回数据格式不正确。"
        case .requestFailed(let message):
            return message
        case .transport(let message):
            return message
        }
    }
}

enum AISourceParsingService {
    struct EnglishMaterialProfile {
        let englishLetterCount: Int
        let chineseCharacterCount: Int
        let englishWordCount: Int
        let contentWordCount: Int
        let englishRatio: Double

        var isEnglishEligible: Bool {
            guard englishWordCount >= 8 else { return false }

            return englishRatio >= 0.72 ||
                (englishRatio >= 0.55 && contentWordCount >= 8) ||
                (englishRatio >= 0.26 && contentWordCount >= 18 && englishLetterCount >= 120) ||
                (contentWordCount >= 30 && englishLetterCount >= 220)
        }

        var shouldPreferLocalFallback: Bool {
            chineseCharacterCount >= 12 && englishRatio < 0.62
        }

        var languageCode: String {
            if englishRatio >= 0.72 {
                return "en"
            }

            if isEnglishEligible {
                return "mixed"
            }

            return chineseCharacterCount > englishLetterCount ? "zh" : "unknown"
        }
    }

    static func parseSource(
        documentID: UUID,
        title: String,
        documentType: SourceDocumentType,
        pageCount: Int,
        draft: SourceTextDraft
    ) async throws -> StructuredSourceParsePayload {
        let localFallback = buildLocalFallbackPayload(
            documentID: documentID,
            title: title,
            documentType: documentType,
            pageCount: pageCount,
            draft: draft
        )
        let baseURLString = AIExplainSentenceService.storedBaseURL
        guard let endpointURL = URL(string: "\(baseURLString)/ai/parse-source") else {
            throw AISourceParsingServiceError.invalidBaseURL
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 40
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ParseSourceRequest(
                sourceID: documentID.uuidString,
                title: title,
                rawText: draft.rawText,
                sourceType: documentType.rawValue.lowercased(),
                pageCount: pageCount,
                anchors: draft.anchors.map {
                    ParseSourceRequestAnchor(
                        anchorID: $0.anchorID,
                        page: $0.page,
                        label: $0.label,
                        text: $0.text
                    )
                }
            )
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AISourceParsingServiceError.invalidServerResponse
            }

            let decoded = try JSONDecoder().decode(ParseSourceResponseEnvelope.self, from: data)

            if httpResponse.statusCode == 200, decoded.success, let payload = decoded.data {
                let remotePayload = StructuredSourceParsePayload(
                    bundle: StructuredSourceBundle(
                        source: payload.source,
                        segments: payload.segments,
                        sentences: payload.sentences,
                        outline: payload.outline
                    ),
                    sectionTitles: payload.sectionTitles,
                    topicTags: payload.topicTags,
                    candidateKnowledgePoints: payload.candidateKnowledgePoints
                )
                return mergeRemotePayload(
                    remotePayload,
                    withLocalFallback: localFallback,
                    draft: draft
                )
            }

            if let message = decoded.error, !message.isEmpty {
                throw AISourceParsingServiceError.requestFailed(message)
            }

            throw AISourceParsingServiceError.invalidServerResponse
        } catch let error as AISourceParsingServiceError {
            throw error
        } catch let error as DecodingError {
            print("[AISourceParsingService] decode failed: \(error)")
            throw AISourceParsingServiceError.invalidServerResponse
        } catch {
            throw AISourceParsingServiceError.transport(error.localizedDescription)
        }
    }

    static func materialProfile(for draft: SourceTextDraft) -> EnglishMaterialProfile {
        let text = draft.rawText
        let englishLetterCount = text.unicodeScalars.filter {
            CharacterSet.letters.contains($0) && $0.value < 128
        }.count
        let chineseCharacterCount = text.unicodeScalars.filter {
            ($0.value >= 0x4E00 && $0.value <= 0x9FFF)
        }.count
        let englishWords = text.matches(for: #"[A-Za-z]+(?:'[A-Za-z]+)?"#).map { $0.lowercased() }
        let contentWordCount = englishWords.filter {
            $0.count >= 3 && !englishStopwords.contains($0)
        }.count
        let ratioBase = max(englishLetterCount + chineseCharacterCount, 1)

        return EnglishMaterialProfile(
            englishLetterCount: englishLetterCount,
            chineseCharacterCount: chineseCharacterCount,
            englishWordCount: englishWords.count,
            contentWordCount: contentWordCount,
            englishRatio: Double(englishLetterCount) / Double(ratioBase)
        )
    }

    static func shouldAttemptEnglishParsing(for draft: SourceTextDraft) -> Bool {
        materialProfile(for: draft).isEnglishEligible
    }

    static func shouldPreferLocalFallback(for draft: SourceTextDraft) -> Bool {
        materialProfile(for: draft).shouldPreferLocalFallback
    }

    static func buildLocalFallbackPayload(
        documentID: UUID,
        title: String,
        documentType: SourceDocumentType,
        pageCount: Int,
        draft: SourceTextDraft
    ) -> StructuredSourceParsePayload {
        let profile = materialProfile(for: draft)
        let sourceID = documentID.uuidString
        let baseSegments = makeLocalSegments(
            sourceID: sourceID,
            anchors: draft.anchors
        )
        let sentences = makeLocalSentences(
            sourceID: sourceID,
            segments: baseSegments
        )
        let sentenceIDsBySegment = Dictionary(grouping: sentences, by: \.segmentID)
            .mapValues { $0.sorted { $0.localIndex < $1.localIndex }.map(\.id) }
        let localSegments = baseSegments.map { segment in
            Segment(
                id: segment.id,
                sourceID: segment.sourceID,
                index: segment.index,
                text: segment.text,
                anchorLabel: segment.anchorLabel,
                page: segment.page,
                sentenceIDs: sentenceIDsBySegment[segment.id] ?? []
            )
        }
        let outline = makeLocalOutline(
            sourceID: sourceID,
            title: title,
            segments: localSegments,
            sentences: sentences
        )

        let bundle = StructuredSourceBundle(
            source: Source(
                id: sourceID,
                title: title.isEmpty ? "未命名资料" : title,
                sourceType: documentType.rawValue.lowercased(),
                language: profile.languageCode,
                isEnglish: true,
                cleanedText: normalizedWhitespace(draft.rawText),
                pageCount: max(pageCount, draft.anchors.compactMap(\.page).max() ?? 1),
                segmentCount: localSegments.count,
                sentenceCount: sentences.count,
                outlineNodeCount: flatten(outline: outline).count
            ),
            segments: localSegments,
            sentences: sentences,
            outline: outline
        )

        let mergedBundle = mergeSentenceGeometry(into: bundle, using: draft)
        let metadata = makeLocalMetadata(bundle: mergedBundle)
        return StructuredSourceParsePayload(
            bundle: mergedBundle,
            sectionTitles: metadata.sectionTitles,
            topicTags: metadata.topicTags,
            candidateKnowledgePoints: metadata.candidateKnowledgePoints
        )
    }

    static func buildLocalFallbackBundle(
        documentID: UUID,
        title: String,
        documentType: SourceDocumentType,
        pageCount: Int,
        draft: SourceTextDraft
    ) -> StructuredSourceBundle {
        buildLocalFallbackPayload(
            documentID: documentID,
            title: title,
            documentType: documentType,
            pageCount: pageCount,
            draft: draft
        ).bundle
    }
}

private extension AISourceParsingService {
    struct LocalMetadata {
        let sectionTitles: [String]
        let topicTags: [String]
        let candidateKnowledgePoints: [String]
    }

    struct LocalSegmentSeed {
        let id: String
        let anchorLabel: String
        let page: Int?
        let text: String
    }

    static func mergeSentenceGeometry(
        into bundle: StructuredSourceBundle,
        using draft: SourceTextDraft
    ) -> StructuredSourceBundle {
        guard !draft.sentenceDrafts.isEmpty else { return bundle }

        var draftsByPage = Dictionary(grouping: draft.sentenceDrafts) { $0.page }
        var mergedCount = 0

        let mergedSentences = bundle.sentences.map { sentence -> Sentence in
            guard let page = sentence.page, var pageDrafts = draftsByPage[page], !pageDrafts.isEmpty else {
                return sentence
            }

            guard let matchIndex = bestDraftIndex(for: sentence, in: pageDrafts) else {
                return sentence
            }

            let matchedDraft = pageDrafts.remove(at: matchIndex)
            draftsByPage[page] = pageDrafts
            mergedCount += 1
            return sentence.withGeometry(matchedDraft.geometry)
        }

        if mergedCount > 0 {
            print("[AISourceParsingService] merged OCR geometry for \(mergedCount)/\(bundle.sentences.count) sentences")
        }

        return StructuredSourceBundle(
            source: bundle.source,
            segments: bundle.segments,
            sentences: mergedSentences,
            outline: bundle.outline
        )
    }

    static func mergeRemotePayload(
        _ remote: StructuredSourceParsePayload,
        withLocalFallback fallback: StructuredSourceParsePayload,
        draft: SourceTextDraft
    ) -> StructuredSourceParsePayload {
        let remoteWithGeometry = mergeSentenceGeometry(into: remote.bundle, using: draft)
        let mergedSentences = mergeRemoteSentences(
            remote: remoteWithGeometry.sentences,
            fallback: fallback.bundle.sentences
        )
        let mergedSegments = mergeRemoteSegments(
            remote: remoteWithGeometry.segments,
            fallback: fallback.bundle.segments,
            mergedSentences: mergedSentences
        )
        let mergedOutline = mergeOutlineNodes(
            remote: shouldPreferFallbackOutline(remote: remoteWithGeometry.outline, fallback: fallback.bundle.outline)
                ? fallback.bundle.outline
                : remoteWithGeometry.outline,
            fallback: fallback.bundle.outline,
            segments: mergedSegments,
            sentences: mergedSentences
        )
        let mergedBundle = StructuredSourceBundle(
            source: mergeSource(
                remote: remoteWithGeometry.source,
                fallback: fallback.bundle.source,
                segments: mergedSegments,
                sentences: mergedSentences,
                outline: mergedOutline
            ),
            segments: mergedSegments,
            sentences: mergedSentences,
            outline: mergedOutline
        )
        let localMetadata = makeLocalMetadata(bundle: mergedBundle)

        return StructuredSourceParsePayload(
            bundle: mergedBundle,
            sectionTitles: mergeMetadataValues(
                remote.sectionTitles,
                fallback: fallback.sectionTitles + localMetadata.sectionTitles,
                limit: 6
            ),
            topicTags: mergeMetadataValues(
                remote.topicTags,
                fallback: fallback.topicTags + localMetadata.topicTags,
                limit: 8
            ),
            candidateKnowledgePoints: mergeMetadataValues(
                remote.candidateKnowledgePoints,
                fallback: fallback.candidateKnowledgePoints + localMetadata.candidateKnowledgePoints,
                limit: 12
            )
        )
    }

    static func mergeRemoteSentences(
        remote: [Sentence],
        fallback: [Sentence]
    ) -> [Sentence] {
        let fallbackByID = Dictionary(uniqueKeysWithValues: fallback.map { ($0.id, $0) })

        return remote.map { sentence in
            let matchedFallback = fallbackByID[sentence.id] ?? bestFallbackSentence(for: sentence, in: fallback)

            return Sentence(
                id: sentence.id,
                sourceID: sentence.sourceID,
                segmentID: sentence.segmentID,
                index: sentence.index,
                localIndex: sentence.localIndex,
                text: preferredText(primary: sentence.text, fallback: matchedFallback?.text),
                anchorLabel: preferredLabel(primary: sentence.anchorLabel, fallback: matchedFallback?.anchorLabel, defaultValue: "原文定位"),
                page: sentence.page ?? matchedFallback?.page,
                geometry: sentence.geometry ?? matchedFallback?.geometry
            )
        }
    }

    static func mergeRemoteSegments(
        remote: [Segment],
        fallback: [Segment],
        mergedSentences: [Sentence]
    ) -> [Segment] {
        let fallbackByID = Dictionary(uniqueKeysWithValues: fallback.map { ($0.id, $0) })
        let sentenceIDsBySegment = Dictionary(grouping: mergedSentences, by: \.segmentID)
            .mapValues { $0.sorted { $0.localIndex < $1.localIndex }.map(\.id) }

        return remote.enumerated().map { index, segment in
            let matchedFallback = fallbackByID[segment.id] ?? bestFallbackSegment(for: segment, in: fallback)

            return Segment(
                id: segment.id,
                sourceID: segment.sourceID,
                index: index,
                text: preferredText(primary: segment.text, fallback: matchedFallback?.text),
                anchorLabel: preferredLabel(
                    primary: segment.anchorLabel,
                    fallback: matchedFallback?.anchorLabel,
                    defaultValue: "原文段落"
                ),
                page: segment.page ?? matchedFallback?.page,
                sentenceIDs: sentenceIDsBySegment[segment.id] ?? segment.sentenceIDs
            )
        }
    }

    static func mergeOutlineNodes(
        remote: [OutlineNode],
        fallback: [OutlineNode],
        segments: [Segment],
        sentences: [Sentence]
    ) -> [OutlineNode] {
        guard !remote.isEmpty else { return fallback }

        let fallbackNodes = flatten(outline: fallback)
        let segmentMap = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
        let sentenceMap = Dictionary(uniqueKeysWithValues: sentences.map { ($0.id, $0) })

        func mergeNode(_ node: OutlineNode) -> OutlineNode {
            let fallbackMatch = bestFallbackNode(for: node, in: fallbackNodes)
            let mergedChildren = node.children.enumerated().map { childIndex, child in
                let mergedChild = mergeNode(child)
                return OutlineNode(
                    id: mergedChild.id,
                    sourceID: mergedChild.sourceID,
                    parentID: node.id,
                    depth: node.depth + 1,
                    order: childIndex,
                    title: mergedChild.title,
                    summary: mergedChild.summary,
                    anchor: mergedChild.anchor,
                    sourceSegmentIDs: mergedChild.sourceSegmentIDs,
                    sourceSentenceIDs: mergedChild.sourceSentenceIDs,
                    children: mergedChild.children
                )
            }

            let sourceSegmentIDs = deduplicatedStrings(
                node.sourceSegmentIDs + (fallbackMatch?.sourceSegmentIDs ?? [])
            ).filter { segmentMap[$0] != nil }
            let sourceSentenceIDs = deduplicatedStrings(
                node.sourceSentenceIDs + (fallbackMatch?.sourceSentenceIDs ?? [])
            ).filter { sentenceMap[$0] != nil }
            let representativeSentence = pickRepresentativeSentence(
                sentenceIDs: sourceSentenceIDs,
                segmentIDs: sourceSegmentIDs,
                fallbackSentenceID: node.anchor.sentenceID ?? fallbackMatch?.anchor.sentenceID,
                sentenceMap: sentenceMap,
                segmentMap: segmentMap
            )
            let representativeSegment = pickRepresentativeSegment(
                segmentIDs: sourceSegmentIDs,
                fallbackSegmentID: node.anchor.segmentID ?? fallbackMatch?.anchor.segmentID,
                sentence: representativeSentence,
                segmentMap: segmentMap
            )
            let summary = preferredSummary(
                primary: node.summary,
                fallback: fallbackMatch?.summary,
                title: node.title,
                segment: representativeSegment,
                sentence: representativeSentence,
                childSummaries: mergedChildren.map(\.summary)
            )

            return OutlineNode(
                id: node.id,
                sourceID: node.sourceID,
                parentID: node.parentID,
                depth: node.depth,
                order: node.order,
                title: preferredOutlineTitle(
                    primary: node.title,
                    fallback: fallbackMatch?.title,
                    segment: representativeSegment,
                    sentence: representativeSentence,
                    depth: node.depth
                ),
                summary: summary,
                anchor: OutlineAnchor(
                    segmentID: representativeSegment?.id ?? fallbackMatch?.anchor.segmentID ?? node.anchor.segmentID,
                    sentenceID: representativeSentence?.id ?? fallbackMatch?.anchor.sentenceID ?? node.anchor.sentenceID,
                    page: representativeSentence?.page ?? representativeSegment?.page ?? fallbackMatch?.anchor.page ?? node.anchor.page,
                    label: preferredLabel(
                        primary: node.anchor.label,
                        fallback: fallbackMatch?.anchor.label ?? representativeSentence?.anchorLabel ?? representativeSegment?.anchorLabel,
                        defaultValue: "原文锚点"
                    )
                ),
                sourceSegmentIDs: deduplicatedStrings(sourceSegmentIDs + [representativeSegment?.id].compactMap { $0 }),
                sourceSentenceIDs: deduplicatedStrings(sourceSentenceIDs + [representativeSentence?.id].compactMap { $0 }),
                children: mergedChildren
            )
        }

        return remote.enumerated().map { index, node in
            let mergedNode = mergeNode(node)
            return OutlineNode(
                id: mergedNode.id,
                sourceID: mergedNode.sourceID,
                parentID: nil,
                depth: 0,
                order: index,
                title: mergedNode.title,
                summary: mergedNode.summary,
                anchor: mergedNode.anchor,
                sourceSegmentIDs: mergedNode.sourceSegmentIDs,
                sourceSentenceIDs: mergedNode.sourceSentenceIDs,
                children: mergedNode.children
            )
        }
    }

    static func mergeSource(
        remote: Source,
        fallback: Source,
        segments: [Segment],
        sentences: [Sentence],
        outline: [OutlineNode]
    ) -> Source {
        Source(
            id: remote.id,
            title: preferredLabel(primary: remote.title, fallback: fallback.title, defaultValue: "未命名资料"),
            sourceType: remote.sourceType,
            language: remote.language.isEmpty ? fallback.language : remote.language,
            isEnglish: remote.isEnglish || fallback.isEnglish,
            cleanedText: preferredText(primary: remote.cleanedText, fallback: fallback.cleanedText),
            pageCount: max(remote.pageCount, fallback.pageCount),
            segmentCount: segments.count,
            sentenceCount: sentences.count,
            outlineNodeCount: flatten(outline: outline).count
        )
    }

    static func shouldPreferFallbackOutline(
        remote: [OutlineNode],
        fallback: [OutlineNode]
    ) -> Bool {
        let remoteNodes = flatten(outline: remote)
        let fallbackNodes = flatten(outline: fallback)

        guard !remoteNodes.isEmpty else { return true }
        guard remoteNodes.count > 1 else { return fallbackNodes.count > 1 }

        let remoteMeaningfulTitles = remoteNodes.filter { !isGenericOutlineTitle($0.title) }
        let remoteHasNestedNodes = remoteNodes.contains { $0.depth >= 2 }
        let fallbackHasNestedNodes = fallbackNodes.contains { $0.depth >= 2 }

        if remoteMeaningfulTitles.count <= 1 && fallbackNodes.count > remoteNodes.count {
            return true
        }

        if !remoteHasNestedNodes && fallbackHasNestedNodes && remoteNodes.count < fallbackNodes.count {
            return true
        }

        return false
    }

    static func makeLocalMetadata(bundle: StructuredSourceBundle) -> LocalMetadata {
        let flattenedNodes = flatten(outline: bundle.outline)
        let sectionTitles = mergeMetadataValues(
            bundle.outline.flatMap(\.children).map(\.title),
            fallback: flattenedNodes.filter { $0.depth > 0 }.map(\.title),
            limit: 6
        )
        let topicTags = mergeMetadataValues(
            flattenedNodes.filter { $0.depth <= 1 }.map(\.title),
            fallback: bundle.segments.prefix(4).map { localNodeTitle(for: $0, sentences: bundle.sentences(in: $0)) },
            limit: 8
        )
        let candidateKnowledgePoints = mergeMetadataValues(
            flattenedNodes.filter { $0.depth > 0 }.flatMap { node in
                let summaryTerms = Array(node.summary
                    .components(separatedBy: CharacterSet(charactersIn: "，。；、,:;()（）\n "))
                    .map(cleanTerm)
                    .filter { $0.count >= 2 && $0.count <= 18 }
                    .prefix(2))
                return [node.title] + summaryTerms
            },
            fallback: bundle.sentences.prefix(6).map { sentence in
                truncate(sentence.text, limit: 20)
            },
            limit: 12
        )

        return LocalMetadata(
            sectionTitles: sectionTitles,
            topicTags: topicTags,
            candidateKnowledgePoints: candidateKnowledgePoints
        )
    }

    static func mergeMetadataValues(
        _ primary: [String],
        fallback: [String],
        limit: Int
    ) -> [String] {
        var groups: [[String]] = []

        for value in primary + fallback {
            let cleaned = cleanTerm(value)
            guard !cleaned.isEmpty else { continue }

            if let index = groups.firstIndex(where: { existing in
                existing.contains { candidate in
                    let lhs = normalizedTermKey(candidate)
                    let rhs = normalizedTermKey(cleaned)
                    return lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs) || tokenOverlapScore(lhs, rhs) >= 0.74
                }
            }) {
                groups[index].append(cleaned)
            } else {
                groups.append([cleaned])
            }
        }

        return groups
            .map(preferredMetadataLabel(for:))
            .filter { !$0.isEmpty && !isGenericOutlineTitle($0) }
            .prefix(limit)
            .map { $0 }
    }

    static func bestDraftIndex(for sentence: Sentence, in drafts: [SourceSentenceDraft]) -> Int? {
        let targetKey = normalizedLookupKey(for: sentence.text)
        guard !targetKey.isEmpty else { return nil }

        if let exactIndex = drafts.firstIndex(where: { normalizedLookupKey(for: $0.text) == targetKey }) {
            return exactIndex
        }

        return drafts.enumerated()
            .compactMap { index, draft -> (Int, Double)? in
                let score = overlapScore(
                    between: targetKey,
                    and: normalizedLookupKey(for: draft.text)
                )
                guard score >= 0.72 else { return nil }
                return (index, score)
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    static func bestFallbackSentence(for sentence: Sentence, in fallback: [Sentence]) -> Sentence? {
        let targetKey = normalizedLookupKey(for: sentence.text)
        guard !targetKey.isEmpty else { return nil }

        return fallback
            .compactMap { candidate -> (Sentence, Double)? in
                let score = overlapScore(
                    between: targetKey,
                    and: normalizedLookupKey(for: candidate.text)
                )
                guard score >= 0.72 else { return nil }
                let pageBoost = candidate.page == sentence.page ? 0.08 : 0
                return (candidate, score + pageBoost)
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    static func bestFallbackSegment(for segment: Segment, in fallback: [Segment]) -> Segment? {
        let targetKey = normalizedLookupKey(for: segment.text)
        guard !targetKey.isEmpty else { return nil }

        return fallback
            .compactMap { candidate -> (Segment, Double)? in
                let score = overlapScore(
                    between: targetKey,
                    and: normalizedLookupKey(for: candidate.text)
                )
                guard score >= 0.6 else { return nil }
                let pageBoost = candidate.page == segment.page ? 0.08 : 0
                return (candidate, score + pageBoost)
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    static func bestFallbackNode(for node: OutlineNode, in fallback: [OutlineNode]) -> OutlineNode? {
        let targetTitle = normalizedTermKey(node.title)
        let targetSummary = normalizedLookupKey(for: node.summary)

        return fallback
            .compactMap { candidate -> (OutlineNode, Double)? in
                var score = 0.0

                if !targetTitle.isEmpty {
                    let candidateTitle = normalizedTermKey(candidate.title)
                    if candidateTitle == targetTitle {
                        score += 1
                    } else {
                        score += tokenOverlapScore(candidateTitle, targetTitle)
                    }
                }

                if !targetSummary.isEmpty {
                    score += overlapScore(
                        between: targetSummary,
                        and: normalizedLookupKey(for: candidate.summary)
                    ) * 0.5
                }

                let sentenceOverlap = Set(node.sourceSentenceIDs).intersection(candidate.sourceSentenceIDs).count
                let segmentOverlap = Set(node.sourceSegmentIDs).intersection(candidate.sourceSegmentIDs).count
                score += Double(sentenceOverlap) * 0.25
                score += Double(segmentOverlap) * 0.15

                guard score >= 0.65 else { return nil }
                return (candidate, score)
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    static func pickRepresentativeSentence(
        sentenceIDs: [String],
        segmentIDs: [String],
        fallbackSentenceID: String?,
        sentenceMap: [String: Sentence],
        segmentMap: [String: Segment]
    ) -> Sentence? {
        if let fallbackSentenceID, let sentence = sentenceMap[fallbackSentenceID] {
            return sentence
        }

        if let sentence = sentenceIDs.compactMap({ sentenceMap[$0] }).sorted(by: {
            if $0.page != $1.page {
                return ($0.page ?? 0) < ($1.page ?? 0)
            }
            return $0.index < $1.index
        }).first {
            return sentence
        }

        if let firstSegment = segmentIDs.compactMap({ segmentMap[$0] }).sorted(by: { $0.index < $1.index }).first {
            return sentenceMap[firstSegment.sentenceIDs.first ?? ""]
        }

        return nil
    }

    static func pickRepresentativeSegment(
        segmentIDs: [String],
        fallbackSegmentID: String?,
        sentence: Sentence?,
        segmentMap: [String: Segment]
    ) -> Segment? {
        if let fallbackSegmentID, let segment = segmentMap[fallbackSegmentID] {
            return segment
        }

        if let sentence, let segment = segmentMap[sentence.segmentID] {
            return segment
        }

        return segmentIDs.compactMap { segmentMap[$0] }.sorted(by: { $0.index < $1.index }).first
    }

    static func normalizedLookupKey(for text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\u4e00-\\u9fff]+", with: "", options: .regularExpression)
    }

    static func overlapScore(between lhs: String, and rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs { return 1 }

        if lhs.contains(rhs) || rhs.contains(lhs) {
            return Double(min(lhs.count, rhs.count)) / Double(max(lhs.count, rhs.count))
        }

        return 0
    }

    static func makeLocalSegments(
        sourceID: String,
        anchors: [SourceTextAnchorDraft]
    ) -> [Segment] {
        let seeds = anchors.enumerated().flatMap { anchorIndex, anchor -> [LocalSegmentSeed] in
            let paragraphs = splitAnchorText(anchor.text)
            let baseLabel = anchor.label.isEmpty ? "第\(anchorIndex + 1)段" : anchor.label

            if paragraphs.isEmpty {
                return []
            }

            if paragraphs.count == 1 {
                return [
                    LocalSegmentSeed(
                        id: "seg_\(String(anchorIndex + 1).leftPadded(to: 3))",
                        anchorLabel: baseLabel,
                        page: anchor.page,
                        text: paragraphs[0]
                    )
                ]
            }

            return paragraphs.enumerated().map { paragraphIndex, paragraph in
                LocalSegmentSeed(
                    id: "seg_\(String(anchorIndex + 1).leftPadded(to: 3))_\(paragraphIndex + 1)",
                    anchorLabel: "\(baseLabel) 第\(paragraphIndex + 1)段",
                    page: anchor.page,
                    text: paragraph
                )
            }
        }

        return seeds.enumerated().map { index, seed in
            Segment(
                id: seed.id,
                sourceID: sourceID,
                index: index,
                text: seed.text,
                anchorLabel: seed.anchorLabel,
                page: seed.page,
                sentenceIDs: []
            )
        }
    }

    static func makeLocalSentences(
        sourceID: String,
        segments: [Segment]
    ) -> [Sentence] {
        var sentences: [Sentence] = []
        var sentenceIndex = 0

        for segment in segments {
            let localSentences = splitSentencesPreservingPunctuation(in: segment.text)
            let fallbackSentences = localSentences.isEmpty ? [normalizedInlineWhitespace(segment.text)] : localSentences

            for (localIndex, sentenceText) in fallbackSentences.enumerated() {
                let normalizedText = normalizedInlineWhitespace(sentenceText)
                guard !normalizedText.isEmpty else { continue }

                let sentenceID = "sen_\(String(sentenceIndex + 1).leftPadded(to: 3))"
                let anchorTail = "第\(localIndex + 1)句"
                let anchorLabel = segment.anchorLabel.contains(anchorTail)
                    ? segment.anchorLabel
                    : "\(segment.anchorLabel) \(anchorTail)"

                sentences.append(
                    Sentence(
                        id: sentenceID,
                        sourceID: sourceID,
                        segmentID: segment.id,
                        index: sentenceIndex,
                        localIndex: localIndex,
                        text: normalizedText,
                        anchorLabel: anchorLabel,
                        page: segment.page
                    )
                )
                sentenceIndex += 1
            }
        }

        return sentences
    }

    static func makeLocalOutline(
        sourceID: String,
        title: String,
        segments: [Segment],
        sentences: [Sentence]
    ) -> [OutlineNode] {
        guard let firstSegment = segments.first else { return [] }
        let sentenceMap = Dictionary(grouping: sentences, by: \.segmentID)
        let groupedSegments = groupedSegmentsForOutline(segments)
        let rootID = "node_root"

        let children = groupedSegments.enumerated().map { groupIndex, group in
            let leadSegment = group[0]
            let sourceSegmentIDs = group.map(\.id)
            let sourceSentenceIDs = group.flatMap { sentenceMap[$0.id, default: []].map(\.id) }
            let representativeSentence = sentenceMap[leadSegment.id]?.first
            let summaryText = group
                .flatMap { splitSentencesPreservingPunctuation(in: $0.text).prefix(1) }
                .joined(separator: " ")
            let titleText = localNodeTitle(for: leadSegment, sentences: sentenceMap[leadSegment.id] ?? [])

            return OutlineNode(
                id: "node_\(groupIndex + 1)",
                sourceID: sourceID,
                parentID: rootID,
                depth: 1,
                order: groupIndex,
                title: titleText,
                summary: truncate(summaryText.isEmpty ? leadSegment.text : summaryText, limit: 100),
                anchor: OutlineAnchor(
                    segmentID: leadSegment.id,
                    sentenceID: representativeSentence?.id,
                    page: representativeSentence?.page ?? leadSegment.page,
                    label: representativeSentence?.anchorLabel ?? leadSegment.anchorLabel
                ),
                sourceSegmentIDs: sourceSegmentIDs,
                sourceSentenceIDs: sourceSentenceIDs,
                children: []
            )
        }

        let rootSentence = sentenceMap[firstSegment.id]?.first
        return [
            OutlineNode(
                id: rootID,
                sourceID: sourceID,
                parentID: nil,
                depth: 0,
                order: 0,
                title: title.isEmpty ? "资料总览" : title,
                summary: truncate(
                    segments
                        .prefix(3)
                        .map { splitSentencesPreservingPunctuation(in: $0.text).first ?? $0.text }
                        .joined(separator: " "),
                    limit: 180
                ),
                anchor: OutlineAnchor(
                    segmentID: firstSegment.id,
                    sentenceID: rootSentence?.id,
                    page: rootSentence?.page ?? firstSegment.page,
                    label: rootSentence?.anchorLabel ?? firstSegment.anchorLabel
                ),
                sourceSegmentIDs: segments.map(\.id),
                sourceSentenceIDs: sentences.map(\.id),
                children: children
            )
        ]
    }

    static func flatten(outline: [OutlineNode]) -> [OutlineNode] {
        outline.flatMap { [$0] + flatten(outline: $0.children) }
    }

    static func groupedSegmentsForOutline(_ segments: [Segment]) -> [[Segment]] {
        guard segments.count > 8 else {
            return segments.map { [$0] }
        }

        let groupSize = Int(ceil(Double(segments.count) / 6.0))
        var groups: [[Segment]] = []
        var index = 0

        while index < segments.count {
            groups.append(Array(segments[index..<min(index + groupSize, segments.count)]))
            index += groupSize
        }

        return groups
    }

    static func splitAnchorText(_ text: String) -> [String] {
        let normalized = normalizedWhitespace(text)
        guard !normalized.isEmpty else { return [] }

        let paragraphs = normalized
            .components(separatedBy: "\n\n")
            .map { normalizedWhitespace($0) }
            .filter { !$0.isEmpty }

        if paragraphs.count > 1 {
            return paragraphs
        }

        let lineGrouped = normalized
            .components(separatedBy: CharacterSet.newlines)
            .map { normalizedInlineWhitespace($0) }
            .filter { !$0.isEmpty }

        if lineGrouped.count >= 2 {
            return lineGrouped
        }

        return [normalized]
    }

    static func splitSentencesPreservingPunctuation(in text: String) -> [String] {
        let normalized = normalizedWhitespace(text)
        guard !normalized.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = normalized
        var results: [String] = []

        tokenizer.enumerateTokens(in: normalized.startIndex..<normalized.endIndex) { range, _ in
            let sentence = normalizedInlineWhitespace(String(normalized[range]))
            if !sentence.isEmpty {
                results.append(sentence)
            }
            return true
        }

        if !results.isEmpty {
            return results
        }

        return normalized
            .components(separatedBy: CharacterSet(charactersIn: "\n"))
            .flatMap { chunk -> [String] in
                let pattern = #"[^。！？!?;；]+[。！？!?;；]?"#
                let matches = chunk.matches(for: pattern)
                return matches.isEmpty ? [normalizedInlineWhitespace(chunk)] : matches.map { normalizedInlineWhitespace($0) }
            }
            .filter { !$0.isEmpty }
    }

    static func localNodeTitle(for segment: Segment, sentences: [Sentence]) -> String {
        let firstLine = segment.text
            .components(separatedBy: .newlines)
            .first
            .map { normalizedInlineWhitespace($0) } ?? ""

        if !firstLine.isEmpty, firstLine.count <= 34, !firstLine.allSatisfy({ $0.isNumber }) {
            return truncate(firstLine, limit: 34)
        }

        if let firstSentence = sentences.first?.text {
            return truncate(firstSentence, limit: 34)
        }

        return truncate(segment.anchorLabel, limit: 34)
    }

    static func preferredOutlineTitle(
        primary: String,
        fallback: String?,
        segment: Segment?,
        sentence: Sentence?,
        depth: Int
    ) -> String {
        let primaryClean = cleanTerm(primary)
        let fallbackClean = cleanTerm(fallback ?? "")
        let generated = cleanTerm(segment.map { localNodeTitle(for: $0, sentences: sentence.map { [$0] } ?? []) } ?? sentence?.text ?? "")

        let candidate: String
        if !primaryClean.isEmpty, !isGenericOutlineTitle(primaryClean) {
            candidate = primaryClean
        } else if !fallbackClean.isEmpty, !isGenericOutlineTitle(fallbackClean) {
            candidate = fallbackClean
        } else if !generated.isEmpty {
            candidate = generated
        } else {
            candidate = depth == 0 ? "资料总览" : "资料节点"
        }

        return truncate(candidate, limit: depth == 0 ? 28 : 24)
    }

    static func preferredSummary(
        primary: String,
        fallback: String?,
        title: String,
        segment: Segment?,
        sentence: Sentence?,
        childSummaries: [String]
    ) -> String {
        let primaryClean = normalizedInlineWhitespace(primary)
        let fallbackClean = normalizedInlineWhitespace(fallback ?? "")
        let synthesized = normalizedInlineWhitespace(
            ([segment?.text, sentence?.text] + childSummaries).compactMap { $0 }.joined(separator: " ")
        )

        var summary = primaryClean
        if summary.count < 18 {
            summary = fallbackClean.count > summary.count ? fallbackClean : summary
        }
        if summary.count < 18 {
            summary = truncate(synthesized, limit: 140)
        }
        if summary.isEmpty {
            summary = "\(title)的核心内容概述。"
        }
        if !summary.hasSuffix("。"), !summary.hasSuffix("."), !summary.hasSuffix("！"), !summary.hasSuffix("!") {
            summary += "。"
        }

        return truncate(summary, limit: 140)
    }

    static func preferredText(primary: String, fallback: String?) -> String {
        let primaryClean = normalizedInlineWhitespace(primary)
        let fallbackClean = normalizedInlineWhitespace(fallback ?? "")
        if primaryClean.isEmpty {
            return fallbackClean
        }
        if fallbackClean.count > primaryClean.count * 2, overlapScore(between: normalizedLookupKey(for: primaryClean), and: normalizedLookupKey(for: fallbackClean)) >= 0.72 {
            return fallbackClean
        }
        return primaryClean
    }

    static func preferredLabel(primary: String, fallback: String?, defaultValue: String) -> String {
        let primaryClean = normalizedInlineWhitespace(primary)
        let fallbackClean = normalizedInlineWhitespace(fallback ?? "")
        if !primaryClean.isEmpty {
            return primaryClean
        }
        if !fallbackClean.isEmpty {
            return fallbackClean
        }
        return defaultValue
    }

    static func deduplicatedStrings(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var results: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            results.append(trimmed)
        }

        return results
    }

    nonisolated static func cleanTerm(_ value: String) -> String {
        normalizedInlineWhitespace(
            value
                .replacingOccurrences(of: #"^[\s\dIVXivx一二三四五六七八九十]+[.、):：\-]?\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^(section|part|chapter|paragraph)\s+\d+[:：\-]?\s*"#, with: "", options: .regularExpression)
        )
    }

    nonisolated static func normalizedTermKey(_ value: String) -> String {
        cleanTerm(value)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\u4e00-\\u9fff]+", with: " ", options: .regularExpression)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map(singularized)
            .joined(separator: " ")
    }

    nonisolated static func singularized(_ value: String) -> String {
        guard value.count > 4 else { return value }
        if value.hasSuffix("ies") {
            return String(value.dropLast(3)) + "y"
        }
        if value.hasSuffix("sses") || value.hasSuffix("ss") {
            return value
        }
        if value.hasSuffix("s") {
            return String(value.dropLast())
        }
        return value
    }

    nonisolated static func tokenOverlapScore(_ lhs: String, _ rhs: String) -> Double {
        let lhsSet = Set(lhs.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        let rhsSet = Set(rhs.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })

        guard !lhsSet.isEmpty, !rhsSet.isEmpty else { return 0 }
        let intersection = lhsSet.intersection(rhsSet).count
        let union = lhsSet.union(rhsSet).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    nonisolated static func isGenericOutlineTitle(_ value: String) -> Bool {
        let normalized = cleanTerm(value).lowercased()
        guard !normalized.isEmpty else { return true }

        let genericValues = [
            "section", "part", "chapter", "paragraph", "node",
            "资料总览", "资料节点", "正文", "引言", "结论", "背景", "分析", "总结"
        ]
        return genericValues.contains(normalized)
    }

    nonisolated static func preferredMetadataLabel(for group: [String]) -> String {
        group
            .map(cleanTerm)
            .filter { !$0.isEmpty }
            .sorted { lhs, rhs in
                let lhsChinese = lhs.containsChineseCharacters ? 1 : 0
                let rhsChinese = rhs.containsChineseCharacters ? 1 : 0
                if lhsChinese != rhsChinese {
                    return lhsChinese > rhsChinese
                }

                let lhsGeneric = isGenericOutlineTitle(lhs) ? 1 : 0
                let rhsGeneric = isGenericOutlineTitle(rhs) ? 1 : 0
                if lhsGeneric != rhsGeneric {
                    return lhsGeneric < rhsGeneric
                }

                if lhs.count != rhs.count {
                    return abs(lhs.count - 10) < abs(rhs.count - 10)
                }

                return lhs < rhs
            }
            .first ?? ""
    }

    static func truncate(_ value: String, limit: Int) -> String {
        let trimmed = normalizedInlineWhitespace(value)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit - 1)) + "…"
    }

    static let englishStopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "being", "by", "for", "from",
        "had", "has", "have", "he", "her", "his", "in", "into", "is", "it", "its", "of",
        "on", "or", "that", "the", "their", "there", "they", "this", "to", "was", "were",
        "which", "with", "would", "should", "could", "can", "may", "might", "will", "not",
        "we", "our", "you", "your", "them", "these", "those", "than", "then", "after",
        "before", "during", "about"
    ]

    nonisolated static func normalizedWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func normalizedInlineWhitespace(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    nonisolated var containsChineseCharacters: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
    }

    func matches(for pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = self as NSString
        let range = NSRange(location: 0, length: nsText.length)

        return regex.matches(in: self, range: range).compactMap { match in
            guard match.range.location != NSNotFound else { return nil }
            return nsText.substring(with: match.range)
        }
    }

    func leftPadded(to length: Int) -> String {
        guard count < length else { return self }
        return String(repeating: "0", count: length - count) + self
    }
}
