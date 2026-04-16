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
    let sectionTitles: [String]?
    let topicTags: [String]?
    let candidateKnowledgePoints: [String]?
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
    private static let parseSourceTimeout: TimeInterval = 90

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
        TextPipelineDiagnostics.log(
            "解析入口",
            "开始解析 \"\(title)\" rawText=\(draft.rawText.count)字符 anchors=\(draft.anchors.count) pages=\(pageCount) type=\(documentType.rawValue)"
        )

        // 入口处验证 rawText 质量
        let inputReport = TextPipelineValidator.assessQuality(of: draft.rawText)
        if !inputReport.isHealthy {
            TextPipelineDiagnostics.log(
                "解析入口",
                "输入文本质量异常: \(inputReport)",
                severity: .warning
            )
        }

        let localFallback = buildLocalFallbackPayload(
            documentID: documentID,
            title: title,
            documentType: documentType,
            pageCount: pageCount,
            draft: draft
        )

        TextPipelineDiagnostics.log(
            "本地回退",
            "本地回退已构建: \(localFallback.bundle.sentences.count)句 \(localFallback.bundle.segments.count)段"
        )

        let baseURLString = AIExplainSentenceService.storedBaseURL
        guard let endpointURL = URL(string: "\(baseURLString)/ai/parse-source") else {
            throw AISourceParsingServiceError.invalidBaseURL
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = parseSourceTimeout
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

            TextPipelineDiagnostics.log(
                "后端响应",
                "HTTP \(httpResponse.statusCode) 数据量=\(data.count)字节"
            )

            let decoded = try JSONDecoder().decode(ParseSourceResponseEnvelope.self, from: data)

            if httpResponse.statusCode == 200, decoded.success, let payload = decoded.data {
                TextPipelineDiagnostics.log(
                    "后端响应",
                    "解析成功: \(payload.sentences.count)句 \(payload.segments.count)段 \(payload.outline.count)大纲节点"
                )

                // 检测后端返回的句子是否存在反转
                let reversedSentences = payload.sentences.filter {
                    TextPipelineValidator.isLikelyReversedEnglish($0.text)
                }
                if !reversedSentences.isEmpty {
                    TextPipelineDiagnostics.log(
                        "后端响应",
                        "⚠️ 检测到 \(reversedSentences.count)/\(payload.sentences.count) 条后端句子疑似反转，将在合并时自动修复",
                        severity: .warning
                    )
                }

                let remotePayload = StructuredSourceParsePayload(
                    bundle: StructuredSourceBundle(
                        source: payload.source,
                        segments: payload.segments,
                        sentences: payload.sentences,
                        outline: payload.outline
                    ),
                    sectionTitles: payload.sectionTitles ?? [],
                    topicTags: payload.topicTags ?? [],
                    candidateKnowledgePoints: payload.candidateKnowledgePoints ?? []
                )
                let result = mergeRemotePayload(
                    remotePayload,
                    withLocalFallback: localFallback,
                    draft: draft
                )

                TextPipelineDiagnostics.log(
                    "合并完成",
                    "最终输出: \(result.bundle.sentences.count)句 \(result.bundle.segments.count)段"
                )

                return result
            }

            if let message = decoded.error, !message.isEmpty {
                TextPipelineDiagnostics.log("后端响应", "服务端错误: \(message)", severity: .error)
                throw AISourceParsingServiceError.requestFailed(message)
            }

            throw AISourceParsingServiceError.invalidServerResponse
        } catch let error as AISourceParsingServiceError {
            TextPipelineDiagnostics.log("解析异常", "服务异常: \(error.localizedDescription)", severity: .error)
            throw error
        } catch let error as DecodingError {
            TextPipelineDiagnostics.log("解析异常", "JSON解码失败: \(error)", severity: .error)
            print("[AISourceParsingService] decode failed: \(error)")
            throw AISourceParsingServiceError.invalidServerResponse
        } catch {
            TextPipelineDiagnostics.log("解析异常", "网络错误: \(error.localizedDescription)", severity: .error)
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
        var repairedCount = 0

        let merged = remote.map { sentence -> Sentence in
            let matchedFallback = fallbackByID[sentence.id] ?? bestFallbackSentence(for: sentence, in: fallback)
            let mergedText = preferredText(primary: sentence.text, fallback: matchedFallback?.text)

            // 反转文本检测与自动修复
            let (validatedText, wasRepaired) = TextPipelineValidator.validateAndRepairIfReversed(mergedText)
            if wasRepaired {
                repairedCount += 1
                TextPipelineDiagnostics.log(
                    "合并句子",
                    "检测到反转文本并已修复 [\(sentence.id)]: \"\(String(mergedText.prefix(40)))…\" → \"\(String(validatedText.prefix(40)))…\"",
                    severity: .repaired
                )
            }

            return Sentence(
                id: sentence.id,
                sourceID: sentence.sourceID,
                segmentID: sentence.segmentID,
                index: sentence.index,
                localIndex: sentence.localIndex,
                text: validatedText,
                anchorLabel: preferredLabel(primary: sentence.anchorLabel, fallback: matchedFallback?.anchorLabel, defaultValue: "原文定位"),
                page: sentence.page ?? matchedFallback?.page,
                geometry: sentence.geometry ?? matchedFallback?.geometry
            )
        }

        if repairedCount > 0 {
            TextPipelineDiagnostics.log(
                "合并句子",
                "共修复 \(repairedCount)/\(merged.count) 条反转句子",
                severity: .warning
            )
        }

        return merged
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
            let localSentences = mergeSentenceFragments(
                splitSentencesPreservingPunctuation(in: segment.text)
            )
            let fallbackSentences = localSentences.isEmpty ? [normalizedInlineWhitespace(segment.text)] : localSentences

            for (localIndex, sentenceText) in fallbackSentences.enumerated() {
                var normalizedText = normalizedInlineWhitespace(sentenceText)
                guard !normalizedText.isEmpty else { continue }

                // 句子长度保护：超过 600 字符截断到最近的句末标点
                if normalizedText.count > 600 {
                    let truncated = truncateToSentenceBoundary(normalizedText, maxLength: 600)
                    normalizedText = truncated
                }

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

    private static func mergeSentenceFragments(_ sentences: [String]) -> [String] {
        guard !sentences.isEmpty else { return [] }

        var merged: [String] = []
        var index = 0

        while index < sentences.count {
            let current = normalizedInlineWhitespace(sentences[index])
            guard !current.isEmpty else {
                index += 1
                continue
            }

            if index < sentences.count - 1, looksLikeSentenceFragment(current) {
                let combined = normalizedInlineWhitespace("\(current) \(sentences[index + 1])")
                merged.append(combined)
                index += 2
                continue
            }

            if var last = merged.last, looksLikeSentenceFragment(current) {
                last = normalizedInlineWhitespace("\(last) \(current)")
                merged[merged.count - 1] = last
            } else {
                merged.append(current)
            }

            index += 1
        }

        return merged
    }

    private static func looksLikeSentenceFragment(_ text: String) -> Bool {
        let normalized = normalizedInlineWhitespace(text)
        guard !normalized.isEmpty else { return true }
        if normalized.count >= 36 { return false }
        if normalized.last.map({ ".!?。！？;；:：".contains($0) }) == true { return false }

        let words = normalized.split(whereSeparator: \.isWhitespace)
        if words.count <= 3 { return true }

        let lower = normalized.lowercased()
        let connectorPrefixes = ["and ", "or ", "but ", "yet ", "so ", "because ", "while "]
        if connectorPrefixes.contains(where: { lower.hasPrefix($0) }) {
            return true
        }

        let verbPattern = #"\b(am|is|are|was|were|be|been|being|do|does|did|have|has|had|can|could|may|might|must|shall|should|will|would|become|became|means|mean|shows|show|suggests|suggests|suggest|indicates|indicate|remains|remain|appears|appear|\w+ed|\w+ing)\b"#
        let hasVerbLikeToken = lower.range(of: verbPattern, options: .regularExpression) != nil
        return !hasVerbLikeToken
    }

    /// 截断到最近的句末标点边界
    private static func truncateToSentenceBoundary(_ text: String, maxLength: Int) -> String {
        let prefix = String(text.prefix(maxLength))
        let terminators: [Character] = [".", "!", "?", "。", "！", "？", ";", "；"]
        if let lastTerminator = prefix.lastIndex(where: { terminators.contains($0) }) {
            let endIndex = prefix.index(after: lastTerminator)
            return String(prefix[prefix.startIndex..<endIndex])
        }
        return prefix
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

        let children = groupedSegments.enumerated().compactMap { groupIndex, group -> OutlineNode? in
            guard let leadSegment = group.first else { return nil }
            let sourceSegmentIDs = group.map(\.id)
            let sourceSentenceIDs = group.flatMap { sentenceMap[$0.id, default: []].map(\.id) }
            let representativeSentence = sentenceMap[leadSegment.id]?.first
            let summaryText = group
                .flatMap { splitSentencesPreservingPunctuation(in: $0.text).prefix(1) }
                .joined(separator: " ")
            let titleText = localNodeTitle(for: leadSegment, sentences: sentenceMap[leadSegment.id] ?? [])

            // ── 节点资格验证 ──

            // (1) 标题和摘要都太短或无意义的跳过
            let titleCleaned = cleanTerm(titleText)
            let summaryForNode = summaryText.isEmpty ? leadSegment.text : summaryText
            if titleCleaned.count < 2 && summaryForNode.trimmingCharacters(in: .whitespacesAndNewlines).count < 6 {
                TextPipelineDiagnostics.log(
                    "树节点",
                    "跳过低质节点 group=\(groupIndex) title=\"\(titleText)\" summary=\(summaryForNode.count)字符",
                    severity: .warning
                )
                return nil
            }

            // (2) 混合语言污染检测：中英混杂严重的块不做独立节点
            let langProfile = BlockContentClassifier.analyzeLanguage(leadSegment.text)
            if langProfile.isContaminated {
                TextPipelineDiagnostics.log(
                    "树节点",
                    "跳过混合语言污染节点 group=\(groupIndex) 混合度=\(String(format: "%.2f", langProfile.mixedScore)) en=\(String(format: "%.0f%%", langProfile.englishRatio * 100)) zh=\(String(format: "%.0f%%", langProfile.chineseRatio * 100))",
                    severity: .warning
                )
                return nil
            }

            // (3) 噪声/页眉页脚类型检测
            let classification = BlockContentClassifier.classify(
                text: leadSegment.text,
                layoutType: leadSegment.anchorLabel.contains("标题") ? .heading : .body,
                confidence: 0.7
            )
            if !classification.contentType.isTreeNodeEligible {
                TextPipelineDiagnostics.log(
                    "树节点",
                    "跳过非结构内容 group=\(groupIndex) 类型=\(classification.contentType.displayName)",
                    severity: .info
                )
                return nil
            }

            // (4) 明显截断检测：文本在单词中间断开
            let trimmedSummary = summaryForNode.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedSummary.count > 10, let lastChar = trimmedSummary.last,
               lastChar.isLetter && !lastChar.isPunctuation,
               trimmedSummary.count < 30 {
                // 短文本且末尾无标点 → 可能是截断碎片
                let letterCount = trimmedSummary.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
                if letterCount < 8 {
                    TextPipelineDiagnostics.log(
                        "树节点",
                        "跳过疑似截断碎片 group=\(groupIndex) text=\"\(String(trimmedSummary.prefix(30)))\"",
                        severity: .warning
                    )
                    return nil
                }
            }

            return OutlineNode(
                id: "node_\(groupIndex + 1)",
                sourceID: sourceID,
                parentID: rootID,
                depth: 1,
                order: groupIndex,
                title: titleText,
                summary: truncate(summaryForNode, limit: 100),
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
        flattenWithDepthLimit(outline, maxDepth: 20)
    }

    /// 带深度限制的树展平，防止循环引用导致无限递归
    private static func flattenWithDepthLimit(_ nodes: [OutlineNode], maxDepth: Int, currentDepth: Int = 0) -> [OutlineNode] {
        guard currentDepth < maxDepth else { return [] }
        return nodes.flatMap { [$0] + flattenWithDepthLimit($0.children, maxDepth: maxDepth, currentDepth: currentDepth + 1) }
    }

    static func groupedSegmentsForOutline(_ segments: [Segment]) -> [[Segment]] {
        guard !segments.isEmpty else { return [] }

        // 标题感知分组：以标题标签为分界点分组
        var groups: [[Segment]] = []
        var currentGroup: [Segment] = []

        for segment in segments {
            let isHeadingSegment = segment.anchorLabel.contains("标题")
            if isHeadingSegment && !currentGroup.isEmpty {
                groups.append(currentGroup)
                currentGroup = []
            }
            currentGroup.append(segment)
        }
        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        // 如果没有自然分组（全是 body、没有标题标签），按数量适度分组
        if groups.count <= 1 && segments.count > 8 {
            let groupSize = max(Int(ceil(Double(segments.count) / 6.0)), 2)
            groups = []
            var index = 0
            while index < segments.count {
                groups.append(Array(segments[index..<min(index + groupSize, segments.count)]))
                index += groupSize
            }
        } else if groups.count <= 1 {
            // ≤8 段，每段一组
            groups = segments.map { [$0] }
        }

        return groups
    }

    static func splitAnchorText(_ text: String) -> [String] {
        let normalized = normalizedWhitespace(text)
        guard !normalized.isEmpty else { return [] }

        // 显式双换行 = 段落分界
        let paragraphs = normalized
            .components(separatedBy: "\n\n")
            .map { normalizedWhitespace($0) }
            .filter { !$0.isEmpty }

        if paragraphs.count > 1 {
            return paragraphs
        }

        // 单换行是视觉行折行，不是段落分界。
        // 将所有行合并为一个段落块。
        let lines = normalized
            .components(separatedBy: CharacterSet.newlines)
            .map { normalizedInlineWhitespace($0) }
            .filter { !$0.isEmpty }

        if lines.count >= 2 {
            return [lines.joined(separator: " ")]
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

        // 首行为短行且非纯数字/标点→用作标题
        if !firstLine.isEmpty, firstLine.count <= 34 {
            let letterCount = firstLine.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            if letterCount >= 3 {
                return truncate(firstLine, limit: 34)
            }
        }

        // 取第一句作为标题
        if let firstSentence = sentences.first?.text {
            let trimmed = normalizedInlineWhitespace(firstSentence)
            if !trimmed.isEmpty {
                return truncate(trimmed, limit: 34)
            }
        }

        // 取 anchorLabel，但避免纯"第X段"之类的通用标签
        let label = segment.anchorLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty {
            return truncate(label, limit: 34)
        }

        // 最终回退：取段落文本前 34 字符
        let segText = normalizedInlineWhitespace(segment.text)
        if !segText.isEmpty {
            return truncate(segText, limit: 34)
        }

        return "段落 \(segment.index + 1)"
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
        } else if !generated.isEmpty, !isGenericOutlineTitle(generated) {
            candidate = generated
        } else if let sentenceText = sentence?.text, !sentenceText.isEmpty {
            candidate = sentenceText
        } else if let segmentText = segment?.text, !segmentText.isEmpty {
            candidate = String(segmentText.prefix(40))
        } else {
            candidate = depth == 0 ? "资料总览" : "段落 \(depth)"
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
