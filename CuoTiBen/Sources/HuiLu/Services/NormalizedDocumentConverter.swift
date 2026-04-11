import Foundation

// MARK: - NormalizedDocument → StructuredSourceBundle 转换器
// 将 PP-StructureV3 归一化输出转换为“教授式解析”所需的数据结构

enum NormalizedDocumentConverter {

    private static let minBlockConfidence: Double = 0.25
    private static let minParagraphTextLength = 3
    private static let minTitleLength = 2
    private static let maxTitleLength = 120
    private static let maxOutlineSupportingSentences = 2
    private static let stopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "being", "by", "for", "from",
        "had", "has", "have", "he", "her", "his", "in", "into", "is", "it", "its", "of",
        "on", "or", "that", "the", "their", "there", "they", "this", "to", "was", "were",
        "which", "with", "would", "should", "could", "can", "may", "might", "will", "not",
        "we", "our", "you", "your", "them", "these", "those", "than", "then", "after",
        "before", "during", "about", "also", "such", "very", "more", "most", "some",
        "many", "much", "other", "others", "one", "two", "three"
    ]

    static func convert(
        _ document: NormalizedDocument,
        documentID: UUID,
        title: String,
        documentType: String,
        pageCount: Int
    ) -> StructuredSourceParsePayload {
        let sourceID = documentID.uuidString

        TextPipelineDiagnostics.log(
            "PP",
            "[PP][Converter] 入口: blocks=\(document.blocks.count) paragraphs=\(document.paragraphs.count) candidates=\(document.structureCandidates.count) doc=\(documentID)",
            severity: .info
        )

        var filterStats = (noise: 0, headerFooter: 0, lowConf: 0, emptyText: 0, reference: 0)
        let cleanedBlocks = document.blocks.filter { block in
            guard block.blockType != .noise else {
                filterStats.noise += 1
                return false
            }
            guard block.blockType != .pageHeader && block.blockType != .pageFooter else {
                filterStats.headerFooter += 1
                return false
            }
            guard block.blockType != .reference else {
                filterStats.reference += 1
                return false
            }
            guard block.confidence >= minBlockConfidence else {
                filterStats.lowConf += 1
                return false
            }
            guard !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                filterStats.emptyText += 1
                return false
            }
            return true
        }

        // 语言统计（只在 cleaned 集合上计算）
        let langCounts = cleanedBlocks.reduce(into: [BlockLanguage: Int]()) { $0[$1.language, default: 0] += 1 }

        TextPipelineDiagnostics.log(
            "PP",
            "[PP][Converter] 过滤统计: 原始=\(document.blocks.count) 保留=\(cleanedBlocks.count) "
            + "噪声=\(filterStats.noise) 页眉页脚=\(filterStats.headerFooter) 参考文献=\(filterStats.reference) "
            + "低置信度=\(filterStats.lowConf) 空文本=\(filterStats.emptyText) "
            + "语言分布=\(langCounts.map { "\($0.key.rawValue):\($0.value)" }.joined(separator: ","))",
            severity: .info
        )

        let cleanedParagraphs = filterAndRepairParagraphs(
            document.paragraphs,
            cleanedBlockIDs: Set(cleanedBlocks.map(\.id))
        )

        let passageParagraphs = selectPassageParagraphs(from: cleanedParagraphs)
        let questionParagraphs = cleanedParagraphs.filter { $0.zoneRole == .question }
        let answerKeyParagraphs = cleanedParagraphs.filter { $0.zoneRole == .answerKey }
        let vocabularyParagraphs = cleanedParagraphs.filter { $0.zoneRole == .vocabularySupport }
        let instructionParagraphs = cleanedParagraphs.filter { $0.zoneRole == .metaInstruction }

        let effectivePassageParagraphs: [NormalizedParagraph]
        if !passageParagraphs.isEmpty {
            effectivePassageParagraphs = passageParagraphs
        } else {
            effectivePassageParagraphs = cleanedParagraphs.filter {
                $0.language == .english || $0.language == .mixed
            }
            TextPipelineDiagnostics.log(
                "PP",
                "[PP][Converter] 未检测到明确 passage 段落，退回英文/混合段落启发式正文选择",
                severity: .warning
            )
        }

        let (segments, sentencesBySegment) = buildSegments(
            from: effectivePassageParagraphs,
            blocks: cleanedBlocks,
            sourceID: sourceID
        )
        let allSentences = sentencesBySegment.values.flatMap { $0 }
            .sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.localIndex < rhs.localIndex
            }

        let paragraphCards = buildParagraphTeachingCards(
            segments: segments,
            sentencesBySegment: sentencesBySegment,
            title: title
        )
        let sentenceCards = buildProfessorSentenceCards(
            sentences: allSentences,
            paragraphCards: paragraphCards,
            sentenceIndex: sentencesBySegment
        )
        let questionLinks = buildQuestionLinks(
            questionParagraphs: questionParagraphs,
            answerKeyParagraphs: answerKeyParagraphs,
            paragraphCards: paragraphCards,
            segments: segments,
            sentences: allSentences
        )
        let overview = buildPassageOverview(
            title: title,
            paragraphCards: paragraphCards,
            sentenceCards: sentenceCards,
            questionLinks: questionLinks
        )
        let outline = buildPedagogicalOutline(
            sourceID: sourceID,
            segments: segments,
            sentencesBySegment: sentencesBySegment,
            paragraphCards: paragraphCards,
            sentenceCards: sentenceCards,
            overview: overview
        )

        let zoningSummary = DocumentZoningSummary(
            passageParagraphCount: effectivePassageParagraphs.count,
            questionParagraphCount: questionParagraphs.count,
            answerKeyParagraphCount: answerKeyParagraphs.count,
            vocabularyParagraphCount: vocabularyParagraphs.count,
            metaInstructionParagraphCount: instructionParagraphs.count
        )

        let cleanedPassageText = effectivePassageParagraphs
            .map(\.text)
            .joined(separator: "\n\n")

        let source = Source(
            id: sourceID,
            title: title,
            sourceType: documentType,
            language: document.metadata.dominantLanguage,
            isEnglish: document.metadata.englishRatio > 0.5,
            cleanedText: cleanedPassageText.nonEmpty ?? fullText(from: cleanedBlocks),
            pageCount: pageCount,
            segmentCount: segments.count,
            sentenceCount: allSentences.count,
            outlineNodeCount: countNodes(outline)
        )

        let sectionTitles = buildSectionTitles(title: title, paragraphCards: paragraphCards)
        let topicTags = extractTopicTags(
            title: title,
            paragraphCards: paragraphCards,
            sentenceCards: sentenceCards
        )
        let candidateKnowledgePoints = buildCandidateKnowledgePoints(
            paragraphCards: paragraphCards,
            sentenceCards: sentenceCards,
            questionLinks: questionLinks
        )

        TextPipelineDiagnostics.log(
            "PP",
            "[PP][Converter] passage=\(effectivePassageParagraphs.count) question=\(questionParagraphs.count) answerKey=\(answerKeyParagraphs.count) vocab=\(vocabularyParagraphs.count) sentences=\(allSentences.count) pedagogicalNodes=\(countNodes(outline))",
            severity: .info
        )

        let bundle = StructuredSourceBundle(
            source: source,
            segments: segments,
            sentences: allSentences,
            outline: outline,
            passageOverview: overview,
            paragraphTeachingCards: paragraphCards,
            professorSentenceCards: sentenceCards,
            questionLinks: questionLinks,
            zoningSummary: zoningSummary
        )

        return StructuredSourceParsePayload(
            bundle: bundle,
            sectionTitles: sectionTitles,
            topicTags: topicTags,
            candidateKnowledgePoints: candidateKnowledgePoints
        )
    }

    private static func filterAndRepairParagraphs(
        _ paragraphs: [NormalizedParagraph],
        cleanedBlockIDs: Set<String>
    ) -> [NormalizedParagraph] {
        paragraphs.compactMap { paragraph in
            let validBlockIDs = paragraph.blockIDs.filter { cleanedBlockIDs.contains($0) }
            guard !validBlockIDs.isEmpty else { return nil }
            let trimmed = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= minParagraphTextLength else { return nil }
            return NormalizedParagraph(
                id: paragraph.id,
                blockIDs: validBlockIDs,
                page: paragraph.page,
                endPage: paragraph.endPage,
                text: trimmed,
                language: paragraph.language,
                zoneRole: paragraph.zoneRole,
                crossPage: paragraph.crossPage,
                order: paragraph.order
            )
        }
    }

    private static func selectPassageParagraphs(from paragraphs: [NormalizedParagraph]) -> [NormalizedParagraph] {
        let explicitPassage = paragraphs.filter(\.isPassageParagraph)
        guard !explicitPassage.isEmpty else { return [] }
        return explicitPassage
    }

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
            let sentenceTexts = splitIntoSentences(paragraph.text)
            var sentenceIDs: [String] = []
            var localSentences: [Sentence] = []

            for (localIdx, sentenceText) in sentenceTexts.enumerated() {
                let trimmed = sentenceText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                let sentenceID = "sen_\(globalSentenceIndex)"
                let geometry = buildGeometry(for: paragraph, blockIndex: blockIndex)

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

    private static func buildParagraphTeachingCards(
        segments: [Segment],
        sentencesBySegment: [String: [Sentence]],
        title: String
    ) -> [ParagraphTeachingCard] {
        segments.map { segment in
            let sentences = sentencesBySegment[segment.id] ?? []
            let role = inferParagraphRole(
                text: segment.text,
                index: segment.index,
                total: segments.count
            )
            let coreSentence = selectCoreSentence(
                from: sentences,
                paragraphRole: role
            )
            let keywords = extractKeywordTerms(from: segment.text, limit: 5)
            let theme = buildParagraphTheme(
                text: segment.text,
                coreSentenceText: coreSentence?.text,
                role: role,
                index: segment.index
            )
            let blindSpot = buildStudentBlindSpot(
                role: role,
                coreSentenceText: coreSentence?.text ?? segment.text
            )

            return ParagraphTeachingCard(
                id: segment.id,
                segmentID: segment.id,
                paragraphIndex: segment.index,
                anchorLabel: segment.anchorLabel,
                theme: theme,
                argumentRole: role,
                coreSentenceID: coreSentence?.id,
                keywords: keywords,
                relationToPrevious: relationToPreviousParagraph(
                    currentRole: role,
                    currentIndex: segment.index
                ),
                examValue: examValue(for: role),
                teachingFocuses: teachingFocuses(
                    paragraphRole: role,
                    coreSentence: coreSentence,
                    paragraphText: segment.text
                ),
                studentBlindSpot: blindSpot,
                isAIGenerated: false
            )
        }
    }

    private static func buildProfessorSentenceCards(
        sentences: [Sentence],
        paragraphCards: [ParagraphTeachingCard],
        sentenceIndex: [String: [Sentence]]
    ) -> [ProfessorSentenceCard] {
        let paragraphCardIndex = Dictionary(uniqueKeysWithValues: paragraphCards.map { ($0.segmentID, $0) })

        return sentences.map { sentence in
            let paragraphCard = paragraphCardIndex[sentence.segmentID]
            let chunks = chunkSentence(sentence.text)
            let coreClause = extractCoreClause(from: sentence.text, chunks: chunks)
            let grammarPoints = detectGrammarPoints(in: sentence.text, coreClause: coreClause)
            let vocabulary = buildVocabularyInContext(
                sentence: sentence.text,
                paragraphTheme: paragraphCard?.theme
            )
            let misreadPoints = buildMisreadPoints(
                sentence: sentence.text,
                chunks: chunks,
                coreClause: coreClause
            )
            let examRewritePoints = buildExamRewritePoints(
                sentence: sentence.text,
                paragraphRole: paragraphCard?.argumentRole
            )
            let hierarchyRebuild = buildHierarchyRebuild(
                chunks: chunks,
                coreClause: coreClause
            )
            let simplifiedEnglish = buildSimplifiedEnglish(
                sentence: sentence.text,
                coreClause: coreClause,
                chunks: chunks
            )
            let analysis = ProfessorSentenceAnalysis(
                originalSentence: sentence.text,
                naturalChineseMeaning: buildNaturalChineseMeaning(
                    sentence: sentence.text,
                    paragraphCard: paragraphCard
                ),
                sentenceCore: "先抓主干：\(coreClause)",
                chunkBreakdown: chunks,
                grammarPoints: grammarPoints,
                vocabularyInContext: vocabulary,
                misreadPoints: misreadPoints,
                examRewritePoints: examRewritePoints,
                simplifiedEnglish: simplifiedEnglish,
                miniExercise: buildMiniExercise(grammarPoints: grammarPoints, chunks: chunks),
                hierarchyRebuild: hierarchyRebuild,
                syntacticVariation: buildSyntacticVariation(coreClause: coreClause, chunks: chunks)
            )

            let siblingSentences = sentenceIndex[sentence.segmentID] ?? []
            let isKeySentence = paragraphCard?.coreSentenceID == sentence.id ||
                sentence.localIndex == 0 ||
                sentence.text.count >= (siblingSentences.map(\.text.count).max() ?? 0)

            return ProfessorSentenceCard(
                id: sentence.id,
                sentenceID: sentence.id,
                segmentID: sentence.segmentID,
                isKeySentence: isKeySentence,
                analysis: analysis
            )
        }
    }

    private static func buildQuestionLinks(
        questionParagraphs: [NormalizedParagraph],
        answerKeyParagraphs: [NormalizedParagraph],
        paragraphCards: [ParagraphTeachingCard],
        segments: [Segment],
        sentences: [Sentence]
    ) -> [QuestionEvidenceLink] {
        let segmentIndex = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })

        return questionParagraphs.enumerated().compactMap { index, paragraph in
            let questionText = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard questionText.count >= 8 else { return nil }

            let rankedParagraphs = paragraphCards
                .map { card -> (ParagraphTeachingCard, Double) in
                    let haystack = (segmentIndex[card.segmentID]?.text ?? "") + " " + card.theme + " " + card.keywords.joined(separator: " ")
                    return (card, overlapScore(questionText, haystack))
                }
                .sorted { lhs, rhs in lhs.1 > rhs.1 }
            let supportCards = rankedParagraphs
                .filter { $0.1 > 0 }
                .prefix(2)
                .map(\.0)

            let rankedSentences = sentences
                .map { sentence -> (Sentence, Double) in
                    (sentence, overlapScore(questionText, sentence.text))
                }
                .sorted { lhs, rhs in lhs.1 > rhs.1 }
            let supportSentences = rankedSentences
                .filter { $0.1 > 0 }
                .prefix(2)
                .map(\.0)

            let evidence = buildParaphraseEvidence(
                questionText: questionText,
                supportSentences: supportSentences,
                supportCards: supportCards
            )
            let trapType = inferTrapType(from: questionText)
            let answerKey = matchAnswerKeySnippet(
                questionText: questionText,
                answerKeyParagraphs: answerKeyParagraphs
            )

            return QuestionEvidenceLink(
                id: "question_link_\(index)",
                questionText: questionText,
                supportParagraphIDs: supportCards.map(\.segmentID),
                supportingSentenceIDs: supportSentences.map(\.id),
                paraphraseEvidence: evidence,
                trapType: trapType,
                answerKeySnippet: answerKey
            )
        }
    }

    private static func buildPassageOverview(
        title: String,
        paragraphCards: [ParagraphTeachingCard],
        sentenceCards: [ProfessorSentenceCard],
        questionLinks: [QuestionEvidenceLink]
    ) -> PassageOverview? {
        guard !paragraphCards.isEmpty else { return nil }

        let themeSource = shortFocusText(from: title.nonEmpty ?? paragraphCards.first?.theme ?? "the passage")
        let articleTheme = "文章核心围绕“\(themeSource)”展开，重点不是零散事实，而是作者怎样一步步推进判断。"
        let authorCoreQuestion = "作者真正要回答的问题可以概括为：围绕“\(themeSource)”这一议题，读者应当如何理解其原因、证据与结论。"
        let progressionPath = paragraphCards
            .map { "第\($0.paragraphIndex + 1)段用\($0.argumentRole.displayName)推进：\($0.theme)" }
            .joined(separator: " → ")
        let paragraphFunctionMap = paragraphCards.map {
            "第\($0.paragraphIndex + 1)段｜\($0.argumentRole.displayName)｜\($0.theme)"
        }
        let grammarNames = sentenceCards.reduce(into: [String]()) { partialResult, card in
            partialResult.append(contentsOf: card.analysis.grammarPoints.map(\.name))
        }
        let misreadPoints = sentenceCards.reduce(into: [String]()) { partialResult, card in
            partialResult.append(contentsOf: card.analysis.misreadPoints)
        }
        let syntaxHighlights = NSOrderedSet(
            array: grammarNames
        ).array.compactMap { $0 as? String }.prefix(5).map { $0 }
        let readingTraps = NSOrderedSet(
            array: questionLinks.map(\.trapType) + misreadPoints
        ).array.compactMap { $0 as? String }.filter { !$0.isEmpty }.prefix(5).map { $0 }
        let vocabularyHighlights = NSOrderedSet(
            array: paragraphCards.flatMap(\.keywords)
        ).array.compactMap { $0 as? String }.prefix(5).map { $0 }

        return PassageOverview(
            articleTheme: articleTheme,
            authorCoreQuestion: authorCoreQuestion,
            progressionPath: progressionPath,
            paragraphFunctionMap: paragraphFunctionMap,
            syntaxHighlights: syntaxHighlights,
            readingTraps: readingTraps,
            vocabularyHighlights: vocabularyHighlights
        )
    }

    private static func buildPedagogicalOutline(
        sourceID: String,
        segments: [Segment],
        sentencesBySegment: [String: [Sentence]],
        paragraphCards: [ParagraphTeachingCard],
        sentenceCards: [ProfessorSentenceCard],
        overview: PassageOverview?
    ) -> [OutlineNode] {
        let sentenceCardIndex = Dictionary(uniqueKeysWithValues: sentenceCards.map { ($0.sentenceID, $0) })

        let paragraphNodes: [OutlineNode] = paragraphCards.map { card in
            let sentences = sentencesBySegment[card.segmentID] ?? []
            let supportingSentenceNodes = sentences
                .filter { sentence in
                    sentence.id == card.coreSentenceID || sentenceCardIndex[sentence.id]?.isKeySentence == true
                }
                .prefix(maxOutlineSupportingSentences)
                .enumerated()
                .map { _, sentence in
                    OutlineNode(
                        id: "support_\(sentence.id)",
                        sourceID: sourceID,
                        parentID: "para_\(card.segmentID)",
                        depth: 2,
                        order: sentence.index,
                        nodeType: .supportingSentence,
                        title: shortFocusText(from: sentence.text),
                        summary: sentenceCardIndex[sentence.id]?.analysis.sentenceCore ?? sentence.text,
                        anchor: OutlineAnchor(
                            segmentID: sentence.segmentID,
                            sentenceID: sentence.id,
                            page: sentence.page,
                            label: sentence.anchorLabel
                        ),
                        sourceSegmentIDs: [sentence.segmentID],
                        sourceSentenceIDs: [sentence.id],
                        children: []
                    )
                }

            let focusSummary = card.teachingFocuses.joined(separator: "；").nonEmpty ?? card.examValue
            let focusNode = OutlineNode(
                id: "focus_\(card.segmentID)",
                sourceID: sourceID,
                parentID: "para_\(card.segmentID)",
                depth: 2,
                order: card.paragraphIndex * 10,
                nodeType: .teachingFocus,
                title: "教学重点",
                summary: focusSummary,
                anchor: OutlineAnchor(
                    segmentID: card.segmentID,
                    sentenceID: card.coreSentenceID,
                    page: sentences.first?.page,
                    label: card.anchorLabel
                ),
                sourceSegmentIDs: [card.segmentID],
                sourceSentenceIDs: card.coreSentenceID.map { [$0] } ?? [],
                children: []
            )

            return OutlineNode(
                id: "para_\(card.segmentID)",
                sourceID: sourceID,
                parentID: "passage_root",
                depth: 1,
                order: card.paragraphIndex,
                nodeType: .paragraphTheme,
                title: "第\(card.paragraphIndex + 1)段：\(card.argumentRole.displayName)",
                summary: card.theme,
                anchor: OutlineAnchor(
                    segmentID: card.segmentID,
                    sentenceID: card.coreSentenceID,
                    page: sentences.first?.page,
                    label: card.anchorLabel
                ),
                sourceSegmentIDs: [card.segmentID],
                sourceSentenceIDs: sentences.map(\.id),
                children: [focusNode] + supportingSentenceNodes
            )
        }

        let rootNode = OutlineNode(
            id: "passage_root",
            sourceID: sourceID,
            parentID: nil,
            depth: 0,
            order: 0,
            nodeType: .passageRoot,
            title: "文章主题",
            summary: overview?.progressionPath ?? "正文教学树",
            anchor: OutlineAnchor(
                segmentID: segments.first?.id,
                sentenceID: segments.first.flatMap { sentencesBySegment[$0.id]?.first?.id },
                page: segments.first?.page,
                label: segments.first?.anchorLabel ?? "原文"
            ),
            sourceSegmentIDs: segments.map(\.id),
            sourceSentenceIDs: segments.flatMap { sentencesBySegment[$0.id]?.map(\.id) ?? [] },
            children: paragraphNodes
        )

        return [rootNode]
    }

    private static func splitIntoSentences(_ text: String) -> [String] {
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

    private static func inferParagraphRole(
        text: String,
        index: Int,
        total: Int
    ) -> ParagraphArgumentRole {
        let lower = text.lowercased()
        let evidenceMarkers = ["for example", "for instance", "such as", "specifically", "in one study", "data", "according to"]
        let contrastMarkers = ["however", "but", "yet", "nevertheless", "nonetheless", "instead", "rather"]
        let transitionMarkers = ["meanwhile", "therefore", "thus", "moreover", "furthermore", "in addition", "at the same time"]
        let conclusionMarkers = ["in conclusion", "overall", "ultimately", "in short", "to sum up", "therefore", "thus"]
        let backgroundMarkers = ["in recent years", "traditionally", "for decades", "today", "historically", "once", "at first"]

        if index == total - 1 && conclusionMarkers.contains(where: lower.contains) {
            return .conclusion
        }
        if evidenceMarkers.contains(where: lower.contains) || lower.range(of: #"\d+%|\d+\.\d+|\(\d+\)"#, options: .regularExpression) != nil {
            return .evidence
        }
        if contrastMarkers.contains(where: lower.contains) && index > 0 {
            return .objection
        }
        if transitionMarkers.contains(where: lower.contains) && index > 0 {
            return .transition
        }
        if index == 0 || backgroundMarkers.contains(where: lower.contains) {
            return .background
        }
        if index == total - 1 {
            return .conclusion
        }
        return .support
    }

    private static func selectCoreSentence(
        from sentences: [Sentence],
        paragraphRole: ParagraphArgumentRole
    ) -> Sentence? {
        guard !sentences.isEmpty else { return nil }

        return sentences.max { lhs, rhs in
            scoreSentence(lhs, for: paragraphRole) < scoreSentence(rhs, for: paragraphRole)
        }
    }

    private static func scoreSentence(_ sentence: Sentence, for role: ParagraphArgumentRole) -> Double {
        var score = Double(min(sentence.text.count, 180))
        let lower = sentence.text.lowercased()
        if sentence.localIndex == 0 { score += 20 }
        if lower.contains("however") || lower.contains("therefore") || lower.contains("because") { score += 18 }
        if lower.contains("which") || lower.contains("that") || lower.contains("while") { score += 10 }
        if role == .conclusion && (lower.contains("therefore") || lower.contains("thus")) { score += 25 }
        if role == .evidence && (lower.contains("for example") || lower.contains("for instance")) { score += 25 }
        return score
    }

    private static func relationToPreviousParagraph(
        currentRole: ParagraphArgumentRole,
        currentIndex: Int
    ) -> String {
        guard currentIndex > 0 else {
            return "首段先搭建阅读场景，提醒学生先抓主题问题而不是急着抠细节。"
        }

        switch currentRole {
        case .background:
            return "这一段回到背景层，作用是给后文论证提供理解前提。"
        case .support:
            return "这一段不是另起炉灶，而是在上一段基础上继续补足论据。"
        case .objection:
            return "这一段往往意味着真正重点出现，读题时要警惕转折后的信息。"
        case .transition:
            return "这一段承担承上启下功能，帮助学生看清作者论证如何换挡。"
        case .evidence:
            return "这一段把抽象观点落到例证或细节，适合做定位与同义替换训练。"
        case .conclusion:
            return "这一段负责收束全文，通常与主旨题、标题题和态度题高度相关。"
        }
    }

    private static func examValue(for role: ParagraphArgumentRole) -> String {
        switch role {
        case .background:
            return "常见于主旨题的铺垫背景，也可能为细节题提供前提条件。"
        case .support:
            return "常见于细节理解题、观点支持题和同义改写定位题。"
        case .objection:
            return "常见于转折后重点、态度判断题和是非反向陷阱。"
        case .transition:
            return "常见于段落关系题、写作思路题和结构判断题。"
        case .evidence:
            return "常见于例证作用题、数据细节题和论据定位题。"
        case .conclusion:
            return "常见于主旨题、标题题和作者结论态度题。"
        }
    }

    private static func teachingFocuses(
        paragraphRole: ParagraphArgumentRole,
        coreSentence: Sentence?,
        paragraphText: String
    ) -> [String] {
        let grammarNames = detectGrammarPoints(
            in: coreSentence?.text ?? paragraphText,
            coreClause: extractCoreClause(from: coreSentence?.text ?? paragraphText, chunks: chunkSentence(coreSentence?.text ?? paragraphText))
        ).map(\.name)
        var focuses: [String] = []

        switch paragraphRole {
        case .background:
            focuses.append("先判断作者是在铺背景还是正式下判断，避免把背景信息误当主旨。")
        case .support:
            focuses.append("本段要先抓中心句，再看其余句子如何补证，不要平均用力。")
        case .objection:
            focuses.append("遇到转折词要重新定位主句，真正观点往往落在后半句。")
        case .transition:
            focuses.append("承接段重点是看逻辑推进，而不是孤立翻译单句。")
        case .evidence:
            focuses.append("例证段不要只记例子，要回到它到底在支撑哪一个判断。")
        case .conclusion:
            focuses.append("结论段要和首段照应着读，常对应主旨和态度题。")
        }

        if let firstGrammar = grammarNames.first {
            focuses.append("句法上优先处理“\(firstGrammar)”这一层，否则容易看错修饰范围。")
        }

        return Array(focuses.prefix(3))
    }

    private static func chunkSentence(_ text: String) -> [String] {
        // Layer 1: split on parenthetical / em-dash / semicolons
        let normalized = text
            .replacingOccurrences(of: "\u{2014}", with: ", ")
            .replacingOccurrences(of: ";", with: ", ")
        let baseChunks = normalized
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !baseChunks.isEmpty else { return [text] }

        // Layer 2: split long chunks at subordinate conjunctions
        let subordinateMarkers = [" because ", " although ", " while ", " when ",
                                   " if ", " unless ", " whereas ", " since ",
                                   " as long as ", " provided that "]
        var afterSub: [String] = []
        for chunk in baseChunks {
            let lower = " " + chunk.lowercased() + " "
            if chunk.count > 30,
               let marker = subordinateMarkers.first(where: { lower.contains($0) }),
               let range = chunk.lowercased().range(of: marker.trimmingCharacters(in: .whitespaces)) {
                let head = String(chunk[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let tail = String(chunk[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !head.isEmpty { afterSub.append(head) }
                if !tail.isEmpty { afterSub.append(tail) }
            } else {
                afterSub.append(chunk)
            }
        }

        // Layer 3: split remaining long chunks (> 50 chars) at relative clause markers
        let relativeMarkers = [" which ", " who ", " that ", " whom ", " whose ", " where "]
        var afterRel: [String] = []
        for chunk in afterSub {
            let lower = " " + chunk.lowercased() + " "
            if chunk.count > 50,
               let marker = relativeMarkers.first(where: { lower.contains($0) }),
               let range = chunk.lowercased().range(of: marker.trimmingCharacters(in: .whitespaces)) {
                let head = String(chunk[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let tail = String(chunk[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !head.isEmpty { afterRel.append(head) }
                if !tail.isEmpty { afterRel.append(tail) }
            } else {
                afterRel.append(chunk)
            }
        }

        // Layer 4: split very long chunks (> 60 chars) at prepositional phrases
        let prepMarkers = [" by ", " with ", " through ", " despite ", " in order to ",
                           " according to ", " rather than ", " instead of "]
        var results: [String] = []
        for chunk in afterRel {
            let lower = " " + chunk.lowercased() + " "
            if chunk.count > 60,
               let marker = prepMarkers.first(where: { lower.contains($0) }),
               let range = chunk.lowercased().range(of: marker.trimmingCharacters(in: .whitespaces)) {
                let head = String(chunk[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let tail = String(chunk[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !head.isEmpty { results.append(head) }
                if !tail.isEmpty { results.append(tail) }
            } else {
                results.append(chunk)
            }
        }

        return results
    }

    private static func extractCoreClause(from sentence: String, chunks: [String]) -> String {
        guard !chunks.isEmpty else { return sentence }
        let subordinateLeads = [
            "although", "while", "when", "if", "because", "since",
            "as", "to ", "by ", "despite", "given that", "in order to",
            "whereas", "unless", "after", "before", "once"
        ]
        // Skip all leading subordinate/prepositional chunks to find the main clause
        var mainIndex = 0
        for (idx, chunk) in chunks.enumerated() {
            let lower = chunk.lowercased().trimmingCharacters(in: .whitespaces)
            let isSubordinate = subordinateLeads.contains(where: lower.hasPrefix)
            if isSubordinate && idx < chunks.count - 1 {
                mainIndex = idx + 1
            } else {
                break
            }
        }
        // If we skipped everything, use the longest chunk as fallback
        if mainIndex >= chunks.count {
            return chunks.max(by: { $0.count < $1.count }) ?? sentence
        }
        return chunks[mainIndex]
    }

    private static func detectGrammarPoints(in sentence: String, coreClause: String) -> [ProfessorGrammarPoint] {
        let lower = sentence.lowercased()
        var results: [ProfessorGrammarPoint] = []

        if lower.range(of: #"\b(which|that|who|whom|whose|where|when)\b"#, options: .regularExpression) != nil {
            results.append(
                ProfessorGrammarPoint(
                    name: "定语从句 / 后置修饰",
                    explanation: "本句含有后置修饰成分，阅读时先抓“\(coreClause)”这一主干，再回头判断 which / that / who 修饰谁。"
                )
            )
        }

        if lower.range(of: #"\bto\s+[a-z]+|\b[a-z]+ing\b"#, options: .regularExpression) != nil {
            results.append(
                ProfessorGrammarPoint(
                    name: "非谓语结构",
                    explanation: "这里的 to do / doing 更像压缩信息块，不是另起一个完整谓语，别把它误判成主句。"
                )
            )
        }

        if lower.range(of: #"\b(am|is|are|was|were|be|been|being)\s+\w+ed\b"#, options: .regularExpression) != nil {
            results.append(
                ProfessorGrammarPoint(
                    name: "被动结构",
                    explanation: "被动语态会把真正施动者后移或省略，做题时要注意主语并不一定是动作发出者。"
                )
            )
        }

        if lower.range(of: #"\b\w+(tion|sion|ment|ness|ity)\b"#, options: .regularExpression) != nil {
            results.append(
                ProfessorGrammarPoint(
                    name: "抽象名词表达",
                    explanation: "作者用抽象名词打包观点，阅读时要把名词化表达还原成“谁做了什么/发生了什么”。"
                )
            )
        }

        if lower.contains("not") || lower.contains("never") || lower.contains("no ") {
            results.append(
                ProfessorGrammarPoint(
                    name: "否定范围",
                    explanation: "本句带否定色彩，做题时要特别看清 not / never 到底否定的是谓语、比较项还是限定语。"
                )
            )
        }

        return Array(results.prefix(3))
    }

    private static func buildVocabularyInContext(
        sentence: String,
        paragraphTheme: String?
    ) -> [ProfessorVocabularyItem] {
        let terms = extractKeywordTerms(from: sentence, limit: 4)
        let lower = sentence.lowercased()
        return terms.map { term in
            let meaning = inferContextualMeaning(
                term: term,
                sentenceLower: lower,
                paragraphTheme: paragraphTheme
            )
            return ProfessorVocabularyItem(term: term, meaning: meaning)
        }
    }

    private static func inferContextualMeaning(
        term: String,
        sentenceLower: String,
        paragraphTheme: String?
    ) -> String {
        let lower = term.lowercased()

        // Abstract nouns
        let abstractSuffixes = ["tion", "sion", "ment", "ness", "ity", "ance", "ence", "ism"]
        if abstractSuffixes.contains(where: { lower.hasSuffix($0) }) {
            return "\u{62BD}\u{8C61}\u{540D}\u{8BCD}\u{FF0C}\u{5728}\u{672C}\u{53E5}\u{4E2D}\u{628A}\u{4E00}\u{4E2A}\u{52A8}\u{4F5C}\u{6216}\u{72B6}\u{6001}\u{6253}\u{5305}\u{6210}\u{540D}\u{8BCD}\u{FF0C}\u{9605}\u{8BFB}\u{65F6}\u{8981}\u{8FD8}\u{539F}\u{6210}\u{201C}\u{8C01}\u{505A}\u{4E86}\u{4EC0}\u{4E48}\u{201D}\u{3002}"
        }

        // Transition signals
        let transitions = ["however", "nevertheless", "moreover", "furthermore", "consequently",
                          "therefore", "thus", "hence", "meanwhile", "nonetheless",
                          "accordingly", "subsequently", "alternatively"]
        if transitions.contains(lower) {
            return "\u{8FDE}\u{63A5}\u{8BCD}\u{FF0C}\u{6807}\u{5FD7}\u{7740}\u{8BBA}\u{8BC1}\u{7684}\u{65B9}\u{5411}\u{8F6C}\u{6362}\u{FF0C}\u{505A}\u{9898}\u{65F6}\u{5173}\u{6CE8}\u{5B83}\u{524D}\u{540E}\u{7684}\u{89C2}\u{70B9}\u{53D8}\u{5316}\u{3002}"
        }

        // Cause-effect markers
        let causal = ["cause", "lead", "result", "contribute", "stem", "trigger",
                      "arise", "derive", "attribute", "due"]
        if causal.contains(where: { lower.hasPrefix($0) }) {
            return "\u{56E0}\u{679C}\u{5173}\u{7CFB}\u{8BCD}\u{FF0C}\u{8003}\u{9898}\u{5E38}\u{7528}\u{5B83}\u{8BBE}\u{7F6E}\u{56E0}\u{679C}\u{6DF7}\u{6DC6}\u{7684}\u{5E72}\u{6270}\u{9879}\u{FF0C}\u{6CE8}\u{610F}\u{533A}\u{5206}\u{539F}\u{56E0}\u{548C}\u{7ED3}\u{679C}\u{3002}"
        }

        // Attitude / hedging words
        let attitude = ["significant", "crucial", "essential", "merely", "arguably",
                       "presumably", "apparently", "allegedly", "primarily", "somewhat",
                       "largely", "predominantly", "inevitably"]
        if attitude.contains(lower) {
            return "\u{6001}\u{5EA6}\u{8BCD} / \u{7A0B}\u{5EA6}\u{9650}\u{5B9A}\u{8BCD}\u{FF0C}\u{53CD}\u{6620}\u{4F5C}\u{8005}\u{5BF9}\u{89C2}\u{70B9}\u{7684}\u{786E}\u{5B9A}\u{7A0B}\u{5EA6}\u{FF0C}\u{505A}\u{9898}\u{65F6}\u{4E0D}\u{80FD}\u{5FFD}\u{7565}\u{8FD9}\u{79CD}\u{5FAE}\u{5999}\u{7684}\u{8BED}\u{6C14}\u{5DEE}\u{5F02}\u{3002}"
        }

        // Scope limiters
        let limiters = ["only", "solely", "exclusively", "rarely", "seldom",
                       "hardly", "scarcely", "barely", "few", "little"]
        if limiters.contains(lower) {
            return "\u{8303}\u{56F4}\u{9650}\u{5B9A}\u{8BCD}\u{FF0C}\u{8003}\u{9898}\u{4E2D}\u{5E38}\u{88AB}\u{7528}\u{6765}\u{504F}\u{79FB}\u{539F}\u{6587}\u{8303}\u{56F4}\u{FF0C}\u{8981}\u{7279}\u{522B}\u{6CE8}\u{610F}\u{5B83}\u{7684}\u{9650}\u{5B9A}\u{5BF9}\u{8C61}\u{662F}\u{8C01}\u{3002}"
        }

        // Default: contextual meaning based on paragraph theme
        let themeRef = paragraphTheme.flatMap { shortFocusText(from: $0) } ?? ""
        if !themeRef.isEmpty {
            return "\u{5728}\u{672C}\u{6BB5}\u{8BED}\u{5883}\u{4E0B}\u{670D}\u{52A1}\u{4E8E}\u{201C}\(themeRef)\u{201D}\u{8FD9}\u{4E00}\u{5C42}\u{610F}\u{601D}\u{FF0C}\u{4E0D}\u{8981}\u{80CC}\u{5B64}\u{7ACB}\u{8BCD}\u{4E49}\u{3002}"
        }
        return "\u{7ED3}\u{5408}\u{4E0A}\u{4E0B}\u{6587}\u{8BED}\u{5883}\u{7406}\u{89E3}\u{5176}\u{5177}\u{4F53}\u{542B}\u{4E49}\u{FF0C}\u{800C}\u{975E}\u{7B80}\u{5355}\u{5957}\u{7528}\u{8BCD}\u{5178}\u{89E3}\u{91CA}\u{3002}"
    }

    private static func buildMisreadPoints(
        sentence: String,
        chunks: [String],
        coreClause: String
    ) -> [String] {
        let lower = sentence.lowercased()
        var points: [String] = []
        let corePreview = String(coreClause.prefix(40))

        if chunks.count >= 3 {
            points.append("\u{672C}\u{53E5}\u{4FE1}\u{606F}\u{5C42}\u{6B21}\u{591A}\u{FF08}\(chunks.count)\u{5C42}\u{FF09}\u{FF0C}\u{5B66}\u{751F}\u{6700}\u{5BB9}\u{6613}\u{4ECE}\u{5DE6}\u{5F80}\u{53F3}\u{5E73}\u{94FA}\u{7FFB}\u{8BD1}\u{FF0C}\u{5E94}\u{5148}\u{9501}\u{5B9A}\u{4E3B}\u{5E72}\u{201C}\(corePreview)\u{201D}\u{3002}")
        }
        if lower.hasPrefix("although") || lower.hasPrefix("while") || lower.hasPrefix("though") {
            points.append("\u{53E5}\u{9996}\u{4ECE}\u{5C5E}\u{6210}\u{5206}\u{4E0D}\u{662F}\u{4E3B}\u{53E5}\u{FF0C}\u{771F}\u{6B63}\u{5224}\u{65AD}\u{843D}\u{5728}\u{8F6C}\u{6298}\u{540E}\u{7684}\u{201C}\(corePreview)\u{201D}\u{3002}")
        }
        if lower.contains("not only") && lower.contains("but also") {
            points.append("\u{201C}not only...but also\u{201D}\u{7ED3}\u{6784}\u{FF0C}\u{91CD}\u{70B9}\u{5728} but also \u{540E}\u{9762}\u{FF0C}\u{4E0D}\u{8981}\u{628A}\u{4E24}\u{8005}\u{7B49}\u{540C}\u{5BF9}\u{5F85}\u{3002}")
        } else if lower.contains("not") || lower.contains("never") {
            if lower.contains("all ") || lower.contains("every ") || lower.contains("always") {
                points.append("\u{201C}not + all/every/always\u{201D}\u{662F}\u{90E8}\u{5206}\u{5426}\u{5B9A}\u{FF0C}\u{4E0D}\u{662F}\u{5168}\u{90E8}\u{5426}\u{5B9A}\u{FF0C}\u{8003}\u{9898}\u{5E38}\u{628A}\u{90E8}\u{5206}\u{5426}\u{5B9A}\u{5077}\u{6362}\u{6210}\u{5168}\u{90E8}\u{5426}\u{5B9A}\u{3002}")
            } else {
                points.append("\u{5426}\u{5B9A}\u{8303}\u{56F4}\u{8981}\u{7CBE}\u{786E}\u{65AD}\u{5B9A}\u{FF1A}not \u{5230}\u{5E95}\u{5426}\u{5B9A}\u{7684}\u{662F}\u{8C13}\u{8BED}\u{3001}\u{6BD4}\u{8F83}\u{9879}\u{8FD8}\u{662F}\u{9650}\u{5B9A}\u{8BED}\u{FF1F}")
            }
        }
        if lower.contains("which") || lower.contains("that") || lower.contains("who") {
            points.append("\u{4ECE}\u{53E5}\u{5148}\u{95EE}\u{201C}\u{5B83}\u{4FEE}\u{9970}\u{8C01}\u{201D}\u{FF0C}\u{628A}\u{4FEE}\u{9970}\u{8BED}\u{548C}\u{88AB}\u{4FEE}\u{9970}\u{540D}\u{8BCD}\u{914D}\u{5BF9}\u{540E}\u{518D}\u{8BFB}\u{4E0B}\u{53BB}\u{3002}")
        }

        if points.isEmpty {
            points.append("\u{5148}\u{627E}\u{5230}\u{4E3B}\u{8C13}\u{5BBE}\u{4E3B}\u{5E72}\u{FF0C}\u{518D}\u{4F9D}\u{6B21}\u{7406}\u{89E3}\u{6BCF}\u{4E2A}\u{4FEE}\u{9970}\u{6210}\u{5206}\u{FF0C}\u{4E0D}\u{8981}\u{5E73}\u{94FA}\u{7FFB}\u{8BD1}\u{6BCF}\u{4E2A}\u{8BCD}\u{3002}")
        }

        return Array(points.prefix(3))
    }

    private static func buildExamRewritePoints(
        sentence: String,
        paragraphRole: ParagraphArgumentRole?
    ) -> [String] {
        let lower = sentence.lowercased()
        var points: [String] = []

        // Extract key terms for specific examples
        let keyTerms = extractKeywordTerms(from: sentence, limit: 3)
        let termPreview = keyTerms.prefix(2).joined(separator: " / ")

        if lower.contains("however") || lower.contains("but") || lower.contains("yet") {
            points.append("\u{547D}\u{9898}\u{4EBA}\u{5E38}\u{62FF}\u{8F6C}\u{6298}\u{524D}\u{7684}\u{5185}\u{5BB9}\u{5192}\u{5145}\u{4F5C}\u{8005}\u{89C2}\u{70B9}\u{FF0C}\u{771F}\u{6B63}\u{7B54}\u{6848}\u{5728}\u{8F6C}\u{6298}\u{540E}\u{FF0C}\u{5373}\u{201C}\(termPreview)\u{201D}\u{76F8}\u{5173}\u{5185}\u{5BB9}\u{3002}")
        }
        if lower.contains("not") || lower.contains("never") || lower.contains("hardly") {
            points.append("\u{5E38}\u{89C1}\u{964D}\u{7EF4}\u{FF1A}\u{628A}\u{5426}\u{5B9A}\u{6539}\u{5199}\u{6210}\u{80AF}\u{5B9A}\u{FF0C}\u{6216}\u{628A}\u{8303}\u{56F4}\u{4ECE}\u{201C}\u{90E8}\u{5206}\u{201D}\u{5077}\u{6362}\u{6210}\u{201C}\u{5168}\u{90E8}\u{201D}\u{3002}")
        }
        if lower.contains("which") || lower.contains("that") {
            points.append("\u{540E}\u{7F6E}\u{4FEE}\u{9970}\u{5E38}\u{88AB}\u{62C6}\u{5F00}\u{91CD}\u{8BF4}\u{FF0C}\u{5B66}\u{751F}\u{8981}\u{8BA4}\u{51FA}\u{4E3B}\u{5E72}\u{4E0D}\u{53D8}\u{3001}\u{4FEE}\u{9970}\u{6362}\u{76AE}\u{7684}\u{540C}\u{4E49}\u{6539}\u{5199}\u{3002}")
        }
        if paragraphRole == .evidence {
            points.append("\u{4F8B}\u{8BC1}\u{53E5}\u{5E38}\u{88AB}\u{6539}\u{5199}\u{6210}\u{201C}\u{4F5C}\u{8005}\u{4E3E}\u{8FD9}\u{4E2A}\u{4F8B}\u{5B50}\u{662F}\u{4E3A}\u{4E86}\u{8BC1}\u{660E}\u{4EC0}\u{4E48}\u{201D}\u{FF0C}\u{7B54}\u{6848}\u{4E0D}\u{662F}\u{4F8B}\u{5B50}\u{672C}\u{8EAB}\u{800C}\u{662F}\u{5176}\u{6240}\u{652F}\u{6491}\u{7684}\u{8BBA}\u{70B9}\u{3002}")
        }
        if paragraphRole == .objection {
            points.append("\u{8BA9}\u{6B65}\u{53E5}\u{662F}\u{6700}\u{5927}\u{9677}\u{9631}\u{FF1A}\u{547D}\u{9898}\u{4EBA}\u{628A}\u{8BA9}\u{6B65}\u{5185}\u{5BB9}\u{5305}\u{88C5}\u{6210}\u{201C}\u{4F5C}\u{8005}\u{89C2}\u{70B9}\u{201D}\u{653E}\u{5728}\u{9009}\u{9879}\u{91CC}\u{FF0C}\u{8981}\u{770B}\u{6E05}\u{8BA9}\u{6B65}\u{548C}\u{7ACB}\u{573A}\u{7684}\u{533A}\u{522B}\u{3002}")
        }

        if !termPreview.isEmpty && points.isEmpty {
            points.append("\u{5E38}\u{89C1}\u{540C}\u{4E49}\u{66FF}\u{6362}\u{FF1A}\u{201C}\(termPreview)\u{201D}\u{53EF}\u{80FD}\u{88AB}\u{6362}\u{6210}\u{8FD1}\u{4E49}\u{8BCD}\u{6216}\u{4E0A}\u{4E0B}\u{4E49}\u{8BCD}\u{FF0C}\u{4E3B}\u{88AB}\u{52A8}\u{6362}\u{5199}\u{4E5F}\u{5F88}\u{5E38}\u{89C1}\u{3002}")
        }

        if points.isEmpty {
            points.append("\u{5E38}\u{89C1}\u{6539}\u{5199}\u{65B9}\u{5F0F}\u{FF1A}\u{540C}\u{4E49}\u{8BCD}\u{66FF}\u{6362}\u{3001}\u{4E3B}\u{88AB}\u{52A8}\u{5BF9}\u{8C03}\u{3001}\u{62BD}\u{8C61}\u{540D}\u{8BCD}\u{8FD8}\u{539F}\u{4E3A}\u{52A8}\u{8BCD}\u{77ED}\u{8BED}\u{3002}")
        }

        return Array(points.prefix(3))
    }

    private static func buildNaturalChineseMeaning(
        sentence: String,
        paragraphCard: ParagraphTeachingCard?
    ) -> String {
        let lower = sentence.lowercased()
        let focus = shortFocusText(from: sentence)
        var hints: [String] = []

        // Detect sentence structure patterns for more specific guidance
        if lower.contains("not ") && (lower.contains("but ") || lower.contains("rather ")) {
            hints.append("\u{8FD9}\u{662F}\u{201C}\u{4E0D}\u{662F}A\u{800C}\u{662F}B\u{201D}\u{7684}\u{90E8}\u{5206}\u{5426}\u{5B9A}\u{7ED3}\u{6784}")
        }
        if lower.contains("although") || lower.contains("though") || lower.contains("even if") {
            hints.append("\u{5148}\u{8BA9}\u{6B65}\u{518D}\u{8F6C}\u{6298}\u{FF0C}\u{91CD}\u{70B9}\u{5728}\u{8F6C}\u{6298}\u{540E}")
        }
        if lower.contains("however") || lower.contains("yet ") || lower.contains("but ") {
            hints.append("\u{8F6C}\u{6298}\u{540E}\u{624D}\u{662F}\u{4F5C}\u{8005}\u{7684}\u{771F}\u{6B63}\u{7ACB}\u{573A}")
        }
        if sentence.count > 120 {
            hints.append("\u{957F}\u{53E5}\u{FF0C}\u{5148}\u{627E}\u{4E3B}\u{5E72}\u{518D}\u{8865}\u{5145}\u{7EC6}\u{8282}")
        }

        let hintTag = hints.isEmpty ? "" : "\u{FF08}\(hints.joined(separator: "\u{FF0C}"))\u{FF09}"

        if let card = paragraphCard {
            let roleHint = card.argumentRole.displayName
            return "\u{8FD9}\u{53E5}\u{8BDD}\u{670D}\u{52A1}\u{4E8E}\u{672C}\u{6BB5}\u{201C}\(card.theme)\u{201D}\u{FF0C}\u{627F}\u{62C5}\(roleHint)\u{529F}\u{80FD}\u{3002}\u{6838}\u{5FC3}\u{610F}\u{601D}\u{662F}\u{56F4}\u{7ED5}\u{201C}\(focus)\u{201D}\u{63A8}\u{8FDB}\u{8BBA}\u{8BC1}\u{3002}\(hintTag)"
        }
        return "\u{8FD9}\u{53E5}\u{8BDD}\u{7684}\u{6838}\u{5FC3}\u{5224}\u{65AD}\u{843D}\u{5728}\u{201C}\(focus)\u{201D}\u{FF0C}\u{4E0D}\u{8981}\u{5E73}\u{5747}\u{7FFB}\u{8BD1}\u{6BCF}\u{4E2A}\u{8BCD}\u{3002}\(hintTag)"
    }

    private static func buildMiniExercise(
        grammarPoints: [ProfessorGrammarPoint],
        chunks: [String]
    ) -> String? {
        if grammarPoints.contains(where: { $0.name.contains("定语从句") }) {
            return "微练习：先只划出主句主语和谓语，再指出从句到底修饰哪个名词。"
        }
        if chunks.count >= 3 {
            return "微练习：请把这句话按“主干 / 条件或让步 / 补充解释”三层重新编号。"
        }
        return "微练习：请先口头复述主句，再说明其余成分是补充什么信息。"
    }

    private static func buildHierarchyRebuild(
        chunks: [String],
        coreClause: String
    ) -> [String] {
        guard chunks.count >= 3 else { return [] }

        var results = ["先只看主干：\(coreClause)"]
        for chunk in chunks where chunk != coreClause {
            results.append("再补充一层信息：\(chunk)")
        }
        return Array(results.prefix(4))
    }

    private static func buildSimplifiedEnglish(
        sentence: String,
        coreClause: String,
        chunks: [String]
    ) -> String {
        // Keep core clause + only the shortest supplementary chunk
        let supporting = chunks.filter { $0 != coreClause }
        guard !supporting.isEmpty else { return coreClause + "." }
        if let shortest = supporting.min(by: { $0.count < $1.count }) {
            return "\(coreClause), \(shortest)."
        }
        return coreClause + "."
    }

    private static func buildSyntacticVariation(coreClause: String, chunks: [String]) -> String? {
        let supporting = chunks.filter { $0 != coreClause }
        guard !supporting.isEmpty else { return coreClause }
        return "In simpler syntax: \(coreClause), and the rest of the sentence mainly adds \(supporting.prefix(2).joined(separator: " / "))."
    }

    private static func buildParaphraseEvidence(
        questionText: String,
        supportSentences: [Sentence],
        supportCards: [ParagraphTeachingCard]
    ) -> [String] {
        var evidence: [String] = []
        let overlapTerms = overlappingTerms(questionText, supportSentences.map(\.text).joined(separator: " "))

        if !overlapTerms.isEmpty {
            evidence.append("题干与原文围绕 \(overlapTerms.prefix(4).joined(separator: " / ")) 这一组关键词做同义定位。")
        }
        if let firstCard = supportCards.first {
            evidence.append("先回到“\(firstCard.theme)”这一段，再判断题干问的是细节、态度还是作用。")
        }
        if let firstSentence = supportSentences.first {
            evidence.append("最直接证据句落在：\(shortFocusText(from: firstSentence.text)).")
        }

        if evidence.isEmpty {
            evidence.append("先按关键词回原文定位，再看题干是否偷换了范围、态度或因果关系。")
        }

        return Array(evidence.prefix(3))
    }

    private static func inferTrapType(from questionText: String) -> String {
        let lower = questionText.lowercased()
        if lower.contains("not true") || lower.contains("except") || questionText.contains("错误") {
            return "反向排除陷阱"
        }
        if lower.contains("infer") || lower.contains("imply") || questionText.contains("推断") {
            return "推断越界陷阱"
        }
        if lower.contains("main idea") || questionText.contains("主旨") || questionText.contains("标题") {
            return "主旨概括陷阱"
        }
        if lower.contains("author") && (lower.contains("attitude") || questionText.contains("态度")) {
            return "作者态度弱化/强化陷阱"
        }
        if lower.contains("meaning") || questionText.contains("词义") {
            return "词义替换陷阱"
        }
        return "细节同义改写陷阱"
    }

    private static func matchAnswerKeySnippet(
        questionText: String,
        answerKeyParagraphs: [NormalizedParagraph]
    ) -> String? {
        let questionNumber = extractLeadingQuestionNumber(from: questionText)
        if let questionNumber {
            if let matched = answerKeyParagraphs.first(where: {
                extractLeadingQuestionNumber(from: $0.text) == questionNumber
            }) {
                return shortSnippet(from: matched.text)
            }
        }

        return answerKeyParagraphs.first.map { shortSnippet(from: $0.text) }
    }

    private static func extractLeadingQuestionNumber(from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*(\d{1,2}|[A-D])"#) else {
            return nil
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else {
            return nil
        }
        return (text as NSString).substring(with: match.range(at: 1))
    }

    private static func overlapScore(_ lhs: String, _ rhs: String) -> Double {
        let lhsTokens = Set(normalizedTokens(from: lhs))
        let rhsTokens = Set(normalizedTokens(from: rhs))
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }
        let intersection = lhsTokens.intersection(rhsTokens).count
        let union = lhsTokens.union(rhsTokens).count
        return Double(intersection) / Double(max(union, 1))
    }

    private static func overlappingTerms(_ lhs: String, _ rhs: String) -> [String] {
        let rhsTokenSet = Set(normalizedTokens(from: rhs))
        return normalizedTokens(from: lhs).filter { rhsTokenSet.contains($0) }
    }

    private static func normalizedTokens(from text: String) -> [String] {
        let pattern = #"[A-Za-z][A-Za-z'\-]{1,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var results: [String] = []
        var seen: Set<String> = []
        for match in matches {
            let token = nsText.substring(with: match.range).lowercased()
            guard token.count >= 3, !stopwords.contains(token), seen.insert(token).inserted else { continue }
            results.append(token)
        }
        return results
    }

    private static func extractKeywordTerms(from text: String, limit: Int) -> [String] {
        Array(normalizedTokens(from: text).prefix(limit))
    }

    // MARK: - Professor-grade paragraph helpers

    private static func buildParagraphTheme(
        text: String,
        coreSentenceText: String?,
        role: ParagraphArgumentRole,
        index: Int
    ) -> String {
        let focus = shortFocusText(from: coreSentenceText ?? text)
        let paraNum = index + 1

        switch role {
        case .support:
            return "\u{7B2C}\(paraNum)\u{6BB5}\u{627F}\u{62C5}\u{201C}\u{89C2}\u{70B9}\u{652F}\u{6491}\u{201D}\u{4F5C}\u{7528}\u{FF0C}\u{56F4}\u{7ED5}\u{201C}\(focus)\u{201D}\u{7EE7}\u{7EED}\u{63A8}\u{8FDB}\u{8BBA}\u{8BC1}\u{FF0C}\u{4E0D}\u{8981}\u{53EA}\u{770B}\u{96F6}\u{6563}\u{7EC6}\u{8282}\u{3002}"
        case .evidence:
            return "\u{7B2C}\(paraNum)\u{6BB5}\u{662F}\u{4E3E}\u{8BC1}\u{6BB5}\u{FF0C}\u{7528}\u{5177}\u{4F53}\u{4E8B}\u{5B9E}\u{6216}\u{6570}\u{636E}\u{652F}\u{6491}\u{201C}\(focus)\u{201D}\u{FF0C}\u{547D}\u{9898}\u{4EBA}\u{5E38}\u{628A}\u{4F8B}\u{5B50}\u{7EC6}\u{8282}\u{5305}\u{88C5}\u{6210}\u{5E72}\u{6270}\u{9879}\u{3002}"
        case .transition:
            return "\u{7B2C}\(paraNum)\u{6BB5}\u{662F}\u{8FC7}\u{6E21}\u{201C}\(focus)\u{201D}\u{FF0C}\u{8D77}\u{627F}\u{4E0A}\u{542F}\u{4E0B}\u{4F5C}\u{7528}\u{FF0C}\u{6CE8}\u{610F}\u{8F6C}\u{6298}\u{8BCD}\u{540E}\u{624D}\u{662F}\u{771F}\u{6B63}\u{7684}\u{8BBA}\u{70B9}\u{65B9}\u{5411}\u{3002}"
        case .objection:
            return "\u{7B2C}\(paraNum)\u{6BB5}\u{662F}\u{8BA9}\u{6B65}\u{6BB5}\u{FF0C}\u{5148}\u{627F}\u{8BA4}\u{201C}\(focus)\u{201D}\u{FF0C}\u{4F46}\u{4F5C}\u{8005}\u{771F}\u{6B63}\u{60F3}\u{8BF4}\u{7684}\u{5728}\u{540E}\u{9762}\u{2014}\u{2014}\u{505A}\u{9898}\u{5207}\u{52FF}\u{628A}\u{8BA9}\u{6B65}\u{5185}\u{5BB9}\u{5F53}\u{4F5C}\u{8005}\u{89C2}\u{70B9}\u{3002}"
        case .conclusion:
            return "\u{7B2C}\(paraNum)\u{6BB5}\u{662F}\u{603B}\u{7ED3}\u{FF0C}\u{56DE}\u{6536}\u{201C}\(focus)\u{201D}\u{8FD9}\u{4E00}\u{89C2}\u{70B9}\u{FF0C}\u{8003}\u{9898}\u{4E2D}\u{7684} main idea / purpose \u{9898}\u{8981}\u{5728}\u{8FD9}\u{91CC}\u{627E}\u{7EBF}\u{7D22}\u{3002}"
        case .background:
            return "\u{7B2C}\(paraNum)\u{6BB5}\u{63D0}\u{4F9B}\u{80CC}\u{666F}\u{FF0C}\u{56F4}\u{7ED5}\u{201C}\(focus)\u{201D}\u{94FA}\u{57AB}\u{FF0C}\u{5B83}\u{672C}\u{8EAB}\u{4E0D}\u{662F}\u{8BBA}\u{70B9}\u{FF0C}\u{4F46}\u{573A}\u{666F}\u{8BBE}\u{5B9A}\u{5F71}\u{54CD}\u{540E}\u{7EED}\u{8BBA}\u{8BC1}\u{65B9}\u{5411}\u{3002}"
        }
    }

    private static func buildStudentBlindSpot(
        role: ParagraphArgumentRole,
        coreSentenceText: String
    ) -> String {
        let focus = shortFocusText(from: coreSentenceText)
        switch role {
        case .support:
            return "\u{5B66}\u{751F}\u{5E38}\u{628A}\u{89C2}\u{70B9}\u{652F}\u{6491}\u{53E5}\u{5F53}\u{6210}\u{666E}\u{901A}\u{4FE1}\u{606F}\u{8BFB}\u{8FC7}\u{FF0C}\u{6CA1}\u{6709}\u{610F}\u{8BC6}\u{5230}\u{201C}\(focus)\u{201D}\u{5176}\u{5B9E}\u{662F}\u{8FD9}\u{6BB5}\u{7684}\u{5224}\u{65AD}\u{9521}\u{70B9}\u{3002}"
        case .evidence:
            return "\u{5B66}\u{751F}\u{5BB9}\u{6613}\u{8BB0}\u{4F4F}\u{4F8B}\u{5B50}\u{7EC6}\u{8282}\u{FF0C}\u{5374}\u{5FD8}\u{4E86}\u{4F8B}\u{5B50}\u{662F}\u{7528}\u{6765}\u{8BC1}\u{660E}\u{201C}\(focus)\u{201D}\u{8FD9}\u{4E2A}\u{8BBA}\u{70B9}\u{7684}\u{2014}\u{2014}\u{8003}\u{9898}\u{95EE}\u{7684}\u{662F}\u{8BBA}\u{70B9}\u{FF0C}\u{4E0D}\u{662F}\u{4F8B}\u{5B50}\u{672C}\u{8EAB}\u{3002}"
        case .transition:
            return "\u{8FC7}\u{6E21}\u{6BB5}\u{7684}\u{8F6C}\u{6298}\u{8BCD}\u{FF08}however / yet / but\u{FF09}\u{540E}\u{9762}\u{624D}\u{662F}\u{771F}\u{6B63}\u{7684}\u{65B9}\u{5411}\u{FF0C}\u{5B66}\u{751F}\u{5E38}\u{628A}\u{8F6C}\u{6298}\u{524D}\u{5185}\u{5BB9}\u{5F53}\u{7B54}\u{6848}\u{3002}"
        case .objection:
            return "\u{8BA9}\u{6B65}\u{6BB5}\u{662F}\u{6700}\u{5927}\u{9677}\u{9631}\u{FF1A}\u{5B66}\u{751F}\u{628A}\u{201C}\u{627F}\u{8BA4}\u{5BF9}\u{65B9}\u{89C2}\u{70B9}\u{201D}\u{8BFE}\u{89E3}\u{6210}\u{201C}\u{4F5C}\u{8005}\u{89C2}\u{70B9}\u{201D}\u{FF0C}\u{5BFC}\u{81F4}\u{7B54}\u{6848}\u{5B8C}\u{5168}\u{53CD}\u{8F6C}\u{3002}"
        case .conclusion:
            return "\u{603B}\u{7ED3}\u{6BB5}\u{5E38}\u{5305}\u{542B}\u{4E3B}\u{65E8}\u{9898}\u{7B54}\u{6848}\u{FF0C}\u{4F46}\u{5B66}\u{751F}\u{8BFB}\u{5230}\u{8FD9}\u{91CC}\u{65F6}\u{6CE8}\u{610F}\u{529B}\u{5DF2}\u{7ECF}\u{4E0B}\u{964D}\u{FF0C}\u{5BB9}\u{6613}\u{7B54}\u{9519}\u{5168}\u{5C40}\u{9898}\u{3002}"
        case .background:
            return "\u{80CC}\u{666F}\u{6BB5}\u{4FE1}\u{606F}\u{770B}\u{8D77}\u{6765}\u{91CD}\u{8981}\u{FF0C}\u{4F46}\u{901A}\u{5E38}\u{4E0D}\u{662F}\u{8003}\u{70B9}\u{FF0C}\u{5B66}\u{751F}\u{82B1}\u{592A}\u{591A}\u{65F6}\u{95F4}\u{5728}\u{8FD9}\u{91CC}\u{4F1A}\u{5F71}\u{54CD}\u{540E}\u{9762}\u{91CD}\u{70B9}\u{6BB5}\u{7684}\u{9605}\u{8BFB}\u{3002}"
        }
    }

    private static func shortFocusText(from text: String) -> String {
        let tokens = normalizedTokens(from: text)
        if !tokens.isEmpty {
            return tokens.prefix(6).joined(separator: " ")
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(32))
    }

    private static func shortSnippet(from text: String) -> String {
        let trimmed = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(120))
    }

    private static func buildSectionTitles(title: String, paragraphCards: [ParagraphTeachingCard]) -> [String] {
        var titles: [String] = []
        if let normalizedTitle = title.nonEmpty {
            titles.append(normalizedTitle)
        }
        titles.append(contentsOf: paragraphCards.prefix(4).map(\.theme))
        return NSOrderedSet(array: titles).array.compactMap { $0 as? String }
    }

    private static func extractTopicTags(
        title: String,
        paragraphCards: [ParagraphTeachingCard],
        sentenceCards: [ProfessorSentenceCard]
    ) -> [String] {
        var tags: [String] = []
        tags.append(contentsOf: normalizedTokens(from: title))
        tags.append(contentsOf: paragraphCards.flatMap(\.keywords))
        tags.append(
            contentsOf: sentenceCards.flatMap { card in
                card.analysis.vocabularyInContext.map { $0.term.lowercased() }
            }
        )
        let ordered = NSOrderedSet(array: tags).array.compactMap { $0 as? String }
        return Array(ordered.prefix(8))
    }

    private static func buildCandidateKnowledgePoints(
        paragraphCards: [ParagraphTeachingCard],
        sentenceCards: [ProfessorSentenceCard],
        questionLinks: [QuestionEvidenceLink]
    ) -> [String] {
        let points = paragraphCards.flatMap(\.teachingFocuses)
            + sentenceCards.flatMap { $0.analysis.grammarPoints.map(\.name) }
            + questionLinks.map(\.trapType)
        let ordered = NSOrderedSet(array: points).array.compactMap { $0 as? String }
        return Array(ordered.prefix(12))
    }

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
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
