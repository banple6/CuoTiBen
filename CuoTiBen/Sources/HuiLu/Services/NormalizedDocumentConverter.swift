import Foundation

// MARK: - NormalizedDocument → StructuredSourceBundle 转换器
// 将 PP-StructureV3 归一化输出转换为现有结构化数据模型

enum NormalizedDocumentConverter {

    // MARK: - 主转换入口

    /// 将后端返回的归一化文档转换为 app 现有的 StructuredSourceBundle
    static func convert(
        _ document: NormalizedDocument,
        documentID: UUID,
        title: String,
        documentType: String,
        pageCount: Int
    ) -> StructuredSourceParsePayload {
        let sourceID = documentID.uuidString

        // ── 1. 过滤块：只保留树节点合格的块 ──
        let eligibleBlocks = document.blocks.filter { $0.isTreeNodeEligible }
        let englishBlocks = eligibleBlocks.filter { $0.isEnglishPrimary }

        TextPipelineDiagnostics.log(
            "归一化转换",
            "总块数=\(document.blocks.count) 合格=\(eligibleBlocks.count) 英语=\(englishBlocks.count)",
            severity: .info
        )

        // ── 2. 构建段落 → Segment ──
        let (segments, sentencesBySegment) = buildSegments(
            from: document.paragraphs,
            blocks: document.blocks,
            sourceID: sourceID
        )

        // ── 3. 扁平化所有句子 ──
        let allSentences = sentencesBySegment.values.flatMap { $0 }
            .sorted { $0.index < $1.index }

        // ── 4. 构建大纲树 → OutlineNode ──
        let outline = buildOutline(
            from: document.structureCandidates,
            sourceID: sourceID,
            segments: segments,
            sentences: Array(allSentences)
        )

        // ── 5. 构建 Source 元数据 ──
        let englishBodyText = document.blocks
            .filter { $0.blockType == .englishBody }
            .map(\.text)
            .joined(separator: "\n\n")

        let source = Source(
            id: sourceID,
            title: title,
            sourceType: documentType,
            language: document.metadata.dominantLanguage,
            isEnglish: document.metadata.englishRatio > 0.5,
            cleanedText: englishBodyText.isEmpty ? fullText(from: document.blocks) : englishBodyText,
            pageCount: pageCount,
            segmentCount: segments.count,
            sentenceCount: allSentences.count,
            outlineNodeCount: countNodes(outline)
        )

        // ── 6. 提取元数据 ──
        let sectionTitles = document.blocks
            .filter { $0.blockType == .title || $0.blockType == .heading }
            .map(\.text)

        let topicTags = extractTopicTags(from: document.blocks)

        // ── 7. 构建 Bundle ──
        let bundle = StructuredSourceBundle(
            source: source,
            segments: segments,
            sentences: Array(allSentences),
            outline: outline
        )

        return StructuredSourceParsePayload(
            bundle: bundle,
            sectionTitles: sectionTitles,
            topicTags: topicTags,
            candidateKnowledgePoints: []
        )
    }

    // MARK: - 段落 → Segment + Sentence

    private static func buildSegments(
        from paragraphs: [NormalizedParagraph],
        blocks: [NormalizedBlock],
        sourceID: String
    ) -> ([Segment], [String: [Sentence]]) {
        var segments: [Segment] = []
        var sentencesBySegment: [String: [Sentence]] = [:]
        var globalSentenceIndex = 0

        let blockIndex = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })

        for (paragraphIdx, paragraph) in paragraphs.enumerated() {
            let segmentID = "seg_\(paragraphIdx)"

            // 将段落文本按句子拆分
            let sentenceTexts = splitIntoSentences(paragraph.text)
            var sentenceIDs: [String] = []
            var localSentences: [Sentence] = []

            for (localIdx, sentenceText) in sentenceTexts.enumerated() {
                let trimmed = sentenceText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                let sentenceID = "sen_\(globalSentenceIndex)"

                // 尝试从块的 bbox 构建几何信息
                let geometry = buildGeometry(
                    for: paragraph,
                    blockIndex: blockIndex
                )

                let sentence = Sentence(
                    id: sentenceID,
                    sourceID: sourceID,
                    segmentID: segmentID,
                    index: globalSentenceIndex,
                    localIndex: localIdx,
                    text: trimmed,
                    anchorLabel: "第\(paragraph.page)页 第\(localIdx + 1)句",
                    page: paragraph.page,
                    geometry: geometry
                )

                localSentences.append(sentence)
                sentenceIDs.append(sentenceID)
                globalSentenceIndex += 1
            }

            let segment = Segment(
                id: segmentID,
                sourceID: sourceID,
                index: paragraphIdx,
                text: paragraph.text,
                anchorLabel: "第\(paragraph.page)页",
                page: paragraph.page,
                sentenceIDs: sentenceIDs
            )

            segments.append(segment)
            sentencesBySegment[segmentID] = localSentences
        }

        return (segments, sentencesBySegment)
    }

    // MARK: - 结构候选 → OutlineNode

    private static func buildOutline(
        from candidates: [StructureCandidate],
        sourceID: String,
        segments: [Segment],
        sentences: [Sentence]
    ) -> [OutlineNode] {
        // 过滤低质量候选
        let validCandidates = candidates.filter { candidate in
            guard candidate.confidence >= 0.35 else {
                TextPipelineDiagnostics.log(
                    "归一化转换",
                    "拒绝低置信度候选 title=\"\(candidate.title.prefix(30))\" conf=\(String(format: "%.2f", candidate.confidence))",
                    severity: .warning
                )
                return false
            }
            guard candidate.title.count >= 2 else { return false }

            // 语言污染检测
            let profile = BlockContentClassifier.analyzeLanguage(candidate.title)
            if profile.isContaminated {
                TextPipelineDiagnostics.log(
                    "归一化转换",
                    "拒绝语言污染候选 title=\"\(candidate.title.prefix(30))\" mixed=\(String(format: "%.2f", profile.mixedScore))",
                    severity: .warning
                )
                return false
            }

            return true
        }

        // 构建段落 ID → Segment 映射
        let segmentIDSet = Set(segments.map(\.id))

        // 按深度分层构建
        let rootCandidates = validCandidates.filter { $0.parentID == nil }
            .sorted { $0.order < $1.order }

        return rootCandidates.map { candidate in
            buildNode(
                from: candidate,
                allCandidates: validCandidates,
                sourceID: sourceID,
                segmentIDSet: segmentIDSet,
                sentences: sentences,
                depth: 0
            )
        }
    }

    private static func buildNode(
        from candidate: StructureCandidate,
        allCandidates: [StructureCandidate],
        sourceID: String,
        segmentIDSet: Set<String>,
        sentences: [Sentence],
        depth: Int
    ) -> OutlineNode {
        let nodeChildren = allCandidates
            .filter { $0.parentID == candidate.id }
            .sorted { $0.order < $1.order }

        let childNodes: [OutlineNode]
        if depth < 5 { // 最大深度保护
            childNodes = nodeChildren.map { child in
                buildNode(
                    from: child,
                    allCandidates: allCandidates,
                    sourceID: sourceID,
                    segmentIDSet: segmentIDSet,
                    sentences: sentences,
                    depth: depth + 1
                )
            }
        } else {
            childNodes = []
        }

        // 映射 blockIDs → segmentIDs（通过序号近似匹配）
        let mappedSegmentIDs = candidate.paragraphIDs.filter { segmentIDSet.contains($0) }

        // 找到关联句子
        let relatedSentences = sentences.filter { s in
            mappedSegmentIDs.contains(s.segmentID)
        }

        let anchor = OutlineAnchor(
            segmentID: mappedSegmentIDs.first,
            sentenceID: relatedSentences.first?.id,
            page: relatedSentences.first?.page,
            label: "第\(relatedSentences.first?.page ?? 1)页"
        )

        return OutlineNode(
            id: candidate.id,
            sourceID: sourceID,
            parentID: candidate.parentID,
            depth: depth,
            order: candidate.order,
            title: candidate.title,
            summary: candidate.summary ?? "",
            anchor: anchor,
            sourceSegmentIDs: mappedSegmentIDs,
            sourceSentenceIDs: relatedSentences.map(\.id),
            children: childNodes
        )
    }

    // MARK: - 句子拆分

    /// 按英文句末标点拆分
    private static func splitIntoSentences(_ text: String) -> [String] {
        let pattern = #"(?<=[.!?])\s+(?=[A-Z])"#
        let parts = text.components(separatedBy: .newlines)
            .joined(separator: " ")

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }

        var results: [String] = []
        let nsString = parts as NSString
        var lastEnd = 0

        let matches = regex.matches(in: parts, range: NSRange(location: 0, length: nsString.length))
        for match in matches {
            let range = NSRange(location: lastEnd, length: match.range.location - lastEnd)
            let chunk = nsString.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty { results.append(chunk) }
            lastEnd = match.range.location + match.range.length
        }

        let remainder = nsString.substring(from: lastEnd).trimmingCharacters(in: .whitespacesAndNewlines)
        if !remainder.isEmpty { results.append(remainder) }

        return results.isEmpty ? [text] : results
    }

    // MARK: - 几何信息

    private static func buildGeometry(
        for paragraph: NormalizedParagraph,
        blockIndex: [String: NormalizedBlock]
    ) -> SentenceGeometry? {
        let blockBoxes = paragraph.blockIDs.compactMap { blockIndex[$0]?.bbox }
        guard !blockBoxes.isEmpty else { return nil }

        let regions = blockBoxes.map { box in
            SentenceRegion(x: box.x, y: box.y, width: box.width, height: box.height)
        }

        return SentenceGeometry(
            page: paragraph.page,
            regions: regions,
            source: .pdfText
        )
    }

    // MARK: - 辅助

    private static func fullText(from blocks: [NormalizedBlock]) -> String {
        blocks
            .filter { $0.blockType != .pageHeader && $0.blockType != .pageFooter && $0.blockType != .noise }
            .sorted { $0.order < $1.order }
            .map(\.text)
            .joined(separator: "\n\n")
    }

    private static func countNodes(_ nodes: [OutlineNode]) -> Int {
        nodes.reduce(0) { $0 + 1 + countNodes($1.children) }
    }

    private static func extractTopicTags(from blocks: [NormalizedBlock]) -> [String] {
        // 从标题和一级标题中提取关键词作为标签
        blocks
            .filter { $0.blockType == .title || $0.blockType == .heading }
            .prefix(10)
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 && $0.count <= 50 }
    }
}
