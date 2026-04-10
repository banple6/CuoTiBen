import Foundation

// MARK: - NormalizedDocument → StructuredSourceBundle 转换器
// 将 PP-StructureV3 归一化输出转换为现有结构化数据模型

enum NormalizedDocumentConverter {

    // MARK: - 质量阈值

    /// 块置信度低于此值视为噪声
    private static let minBlockConfidence: Double = 0.25
    /// 段落最短有效文本长度
    private static let minParagraphTextLength = 3
    /// 候选节点最低置信度
    private static let minCandidateConfidence: Double = 0.35
    /// 标题最短长度
    private static let minTitleLength = 2
    /// 标题最大长度（超出视为段落误分类）
    private static let maxTitleLength = 120

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

        // ── 0. 入口诊断日志 ──
        TextPipelineDiagnostics.log(
            "PP",
            "[PP][Converter] 入口: blocks=\(document.blocks.count) paragraphs=\(document.paragraphs.count) candidates=\(document.structureCandidates.count) doc=\(documentID)",
            severity: .info
        )

        // ── 1. 过滤块：移除噪声和低置信度块 ──
        var filterStats = (noise: 0, headerFooter: 0, lowConf: 0, emptyText: 0)
        let cleanedBlocks = document.blocks.filter { block in
            // 直接删除噪声类型
            guard block.blockType != .noise else {
                filterStats.noise += 1
                TextPipelineDiagnostics.log("PP", "[PP] 过滤噪声块 id=\(block.id) text=\"\(block.text.prefix(30))\"", severity: .info)
                return false
            }
            // 页眉页脚直接删除
            guard block.blockType != .pageHeader && block.blockType != .pageFooter else {
                filterStats.headerFooter += 1
                return false
            }
            // 低置信度抑制
            guard block.confidence >= minBlockConfidence else {
                filterStats.lowConf += 1
                TextPipelineDiagnostics.log("PP", "[PP] 过滤低置信度块 id=\(block.id) conf=\(String(format: "%.2f", block.confidence)) type=\(block.blockType.rawValue)", severity: .warning)
                return false
            }
            // 空文本排除
            guard !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                filterStats.emptyText += 1
                return false
            }
            return true
        }

        // ── 过滤统计 ──
        if cleanedBlocks.isEmpty && !document.blocks.isEmpty {
            TextPipelineDiagnostics.log(
                "PP",
                "[PP][Converter] ⚠️ 所有块被过滤! 原始=\(document.blocks.count) 噪声=\(filterStats.noise) 页眉页脚=\(filterStats.headerFooter) 低置信度=\(filterStats.lowConf) 空文本=\(filterStats.emptyText) doc=\(documentID)",
                severity: .error
            )
        } else {
            TextPipelineDiagnostics.log(
                "PP",
                "[PP][Converter] 过滤统计: 原始=\(document.blocks.count) 保留=\(cleanedBlocks.count) 噪声=\(filterStats.noise) 页眉页脚=\(filterStats.headerFooter) 低置信度=\(filterStats.lowConf) 空文本=\(filterStats.emptyText)",
                severity: .info
            )
        }

        let eligibleBlocks = cleanedBlocks.filter { $0.isTreeNodeEligible }
        let englishBlocks = cleanedBlocks.filter { $0.isEnglishPrimary }

        TextPipelineDiagnostics.log(
            "PP",
            "[PP] normalized blocks=\(document.blocks.count) cleaned=\(cleanedBlocks.count) eligible=\(eligibleBlocks.count) english=\(englishBlocks.count)",
            severity: .info
        )

        // ── 2. 构建段落 → Segment（保守合并） ──
        let cleanedParagraphs = filterAndRepairParagraphs(document.paragraphs, cleanedBlockIDs: Set(cleanedBlocks.map(\.id)))

        let (segments, sentencesBySegment) = buildSegments(
            from: cleanedParagraphs,
            blocks: cleanedBlocks,
            sourceID: sourceID
        )

        // ── 3. 扁平化所有句子 ──
        let allSentences = sentencesBySegment.values.flatMap { $0 }
            .sorted { $0.index < $1.index }

        // ── 4. 构建大纲树 → OutlineNode（加强过滤） ──
        let outline = buildOutline(
            from: document.structureCandidates,
            sourceID: sourceID,
            segments: segments,
            sentences: Array(allSentences)
        )

        TextPipelineDiagnostics.log(
            "PP",
            "[PP] paragraphs=\(cleanedParagraphs.count) segments=\(segments.count) sentences=\(allSentences.count) structure_candidates=\(document.structureCandidates.count) outline_nodes=\(countNodes(outline))",
            severity: .info
        )

        // ── 5. 构建 Source 元数据 ──
        let englishBodyText = cleanedBlocks
            .filter { $0.blockType == .englishBody }
            .map(\.text)
            .joined(separator: "\n\n")

        let source = Source(
            id: sourceID,
            title: title,
            sourceType: documentType,
            language: document.metadata.dominantLanguage,
            isEnglish: document.metadata.englishRatio > 0.5,
            cleanedText: englishBodyText.isEmpty ? fullText(from: cleanedBlocks) : englishBodyText,
            pageCount: pageCount,
            segmentCount: segments.count,
            sentenceCount: allSentences.count,
            outlineNodeCount: countNodes(outline)
        )

        // ── 6. 提取元数据 ──
        let sectionTitles = cleanedBlocks
            .filter { ($0.blockType == .title || $0.blockType == .heading) && $0.text.count <= maxTitleLength }
            .map(\.text)

        let topicTags = extractTopicTags(from: cleanedBlocks)

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

    // MARK: - 段落过滤与修复

    /// 过滤掉引用了已删除块的段落，跳过纯噪声段落
    private static func filterAndRepairParagraphs(
        _ paragraphs: [NormalizedParagraph],
        cleanedBlockIDs: Set<String>
    ) -> [NormalizedParagraph] {
        paragraphs.compactMap { paragraph in
            // 只保留仍存在的块引用
            let validBlockIDs = paragraph.blockIDs.filter { cleanedBlockIDs.contains($0) }
            guard !validBlockIDs.isEmpty else { return nil }
            // 短文本段落排除
            let trimmed = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= minParagraphTextLength else { return nil }
            return paragraph
        }
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
            guard candidate.confidence >= minCandidateConfidence else {
                TextPipelineDiagnostics.log(
                    "PP",
                    "[PP] 拒绝低置信度候选 title=\"\(candidate.title.prefix(30))\" conf=\(String(format: "%.2f", candidate.confidence))",
                    severity: .warning
                )
                return false
            }
            guard candidate.title.count >= minTitleLength else { return false }

            // 过长的标题视为段落误分类
            guard candidate.title.count <= maxTitleLength else {
                TextPipelineDiagnostics.log(
                    "PP",
                    "[PP] 拒绝过长候选标题 len=\(candidate.title.count) title=\"\(candidate.title.prefix(40))…\"",
                    severity: .warning
                )
                return false
            }

            // 语言污染检测
            let profile = BlockContentClassifier.analyzeLanguage(candidate.title)
            if profile.isContaminated {
                TextPipelineDiagnostics.log(
                    "PP",
                    "[PP] 拒绝语言污染候选 title=\"\(candidate.title.prefix(30))\" mixed=\(String(format: "%.2f", profile.mixedScore))",
                    severity: .warning
                )
                return false
            }

            // 纯数字/标点的标题排除
            let letterCount = candidate.title.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            guard letterCount >= 2 else {
                TextPipelineDiagnostics.log("PP", "[PP] 拒绝无字母候选 title=\"\(candidate.title.prefix(30))\"", severity: .warning)
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

    /// 按英文/中文句末标点拆分，保守策略：宁可少拆不多拆
    private static func splitIntoSentences(_ text: String) -> [String] {
        // 英文: 句号/感叹号/问号后跟空格和大写字母
        // 中文: 句号/感叹号/问号后直接分割
        let pattern = #"(?<=[.!?])\s+(?=[A-Z])|(?<=[。！？])\s*(?=\S)"#
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
            if !chunk.isEmpty && chunk.count >= 2 { results.append(chunk) }
            lastEnd = match.range.location + match.range.length
        }

        let remainder = nsString.substring(from: lastEnd).trimmingCharacters(in: .whitespacesAndNewlines)
        if !remainder.isEmpty && remainder.count >= 2 { results.append(remainder) }

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
