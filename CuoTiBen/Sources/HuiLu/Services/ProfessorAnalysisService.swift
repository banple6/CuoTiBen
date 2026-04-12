import Foundation

// MARK: - 教授级全文教学分析服务
// 调用后端 /ai/analyze-passage 批量获取 AI 教学分析
// 一次调用产出：文章总览 + 段落教学卡 + 关键句教授卡

enum ProfessorAnalysisService {

    // MARK: - 请求/响应模型

    struct ParagraphInput: Encodable {
        let index: Int
        let text: String
    }

    struct KeySentenceInput: Encodable {
        let ref: String
        let text: String
        let paragraph_index: Int
    }

    struct AnalyzePassageRequest: Encodable {
        let title: String
        let paragraphs: [ParagraphInput]
        let key_sentences: [KeySentenceInput]
    }

    struct AnalyzePassageResponse: Decodable {
        let success: Bool?
        let data: AnalyzePassageData?
    }

    struct AnalyzePassageData: Decodable {
        let passage_overview: PassageOverviewDTO?
        let paragraph_cards: [ParagraphCardDTO]?
        let sentence_analyses: [SentenceAnalysisDTO]?
        let quality_warnings: [String]?
        let elapsed_ms: Int?
    }

    struct PassageOverviewDTO: Decodable {
        let article_theme: String?
        let author_core_question: String?
        let progression_path: String?
        let likely_question_types: [String]?
        let logic_pitfalls: [String]?
        let paragraph_function_map: [String]?
        let syntax_highlights: [String]?
        let reading_traps: [String]?
        let vocabulary_highlights: [String]?
    }

    struct ParagraphCardDTO: Decodable {
        let paragraph_index: Int?
        let theme: String?
        let argument_role: String?
        let core_sentence_local_index: Int?
        let keywords: [String]?
        let relation_to_previous: String?
        let exam_value: String?
        let teaching_focuses: [String]?
        let student_blind_spot: String?
    }

    struct SentenceAnalysisDTO: Decodable {
        let sentence_ref: String?
        let sentence_function: String?
        let core_skeleton: ProfessorCoreSkeleton?
        let chunk_layers: [ProfessorChunkLayer]?
        let grammar_focus: [ProfessorGrammarFocus]?
        let natural_chinese_meaning: String?
        let sentence_core: String?
        let chunk_breakdown: [String]?
        let grammar_points: [GrammarPointDTO]?
        let vocabulary_in_context: [VocabularyDTO]?
        let misread_points: [String]?
        let exam_rewrite_points: [String]?
        let misreading_traps: [String]?
        let exam_paraphrase_routes: [String]?
        let simplified_english: String?
        let simpler_rewrite: String?
        let mini_exercise: String?
        let mini_check: String?
        let hierarchy_rebuild: [String]?
        let syntactic_variation: String?
        let evidence_type: String?
    }

    struct GrammarPointDTO: Decodable {
        let name: String?
        let explanation: String?
    }

    struct VocabularyDTO: Decodable {
        let term: String?
        let meaning: String?
    }

    // MARK: - 错误类型

    enum AnalysisError: LocalizedError {
        case missingBaseURL
        case invalidBaseURL
        case invalidServerResponse
        case requestFailed(String)
        case noContent

        var errorDescription: String? {
            switch self {
            case .missingBaseURL: return "未配置后端地址"
            case .invalidBaseURL: return "后端地址格式错误"
            case .invalidServerResponse: return "服务器响应格式异常"
            case .requestFailed(let msg): return "请求失败: \(msg)"
            case .noContent: return "后端未返回分析内容"
            }
        }
    }

    // MARK: - 公开接口

    /// 从 StructuredSourceBundle 中提取段落和关键句，调用后端批量分析，返回增强后的 Bundle
    static func enrichBundle(
        _ bundle: StructuredSourceBundle,
        title: String,
        overrideBaseURL: String? = nil
    ) async throws -> StructuredSourceBundle {
        let endpointURLs = AIExplainSentenceService.endpointCandidates(
            path: "ai/analyze-passage",
            overrideBaseURL: overrideBaseURL
        )
        guard !endpointURLs.isEmpty else { throw AnalysisError.missingBaseURL }

        // 从 bundle 构建请求
        let paragraphInputs = bundle.segments.enumerated().map { idx, segment in
            ParagraphInput(index: idx, text: segment.text)
        }

        // 选取关键句（每段核心句 + 所有 isKeySentence  + 超长句）
        let keySentenceInputs = selectKeySentences(from: bundle)

        TextPipelineDiagnostics.log(
            "AI",
            "[AI][ProfessorAnalysis] 开始批量教学分析: paragraphs=\(paragraphInputs.count) keySentences=\(keySentenceInputs.count) title=\(title)",
            severity: .info
        )

        let requestBody = AnalyzePassageRequest(
            title: title,
            paragraphs: paragraphInputs,
            key_sentences: keySentenceInputs
        )

        let requestData = try JSONEncoder().encode(requestBody)
        var payload: AnalyzePassageData?
        var lastError: Error?

        for (index, url) in endpointURLs.enumerated() {
            for attempt in 0..<2 {
                var request = URLRequest(url: url, timeoutInterval: 90)
                request.httpMethod = "POST"
                request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
                request.httpBody = requestData

                do {
                    try Task.checkCancellation()
                    let (data, httpResponse) = try await URLSession.shared.data(for: request)

                    guard let http = httpResponse as? HTTPURLResponse else {
                        throw AnalysisError.invalidServerResponse
                    }

                    if !(200 ..< 300).contains(http.statusCode) {
                        let bodySnippet = String(data: data.prefix(500), encoding: .utf8) ?? ""
                        TextPipelineDiagnostics.log(
                            "AI",
                            "[AI][ProfessorAnalysis] 后端返回 HTTP \(http.statusCode): \(bodySnippet)",
                            severity: .error
                        )

                        if AIExplainSentenceService.shouldRetrySameEndpoint(statusCode: http.statusCode), attempt == 0 {
                            TextPipelineDiagnostics.log(
                                "AI",
                                "[AI][ProfessorAnalysis] 端点瞬时失败，准备重试: \(url.absoluteString) status=\(http.statusCode)",
                                severity: .warning
                            )
                            try await Task.sleep(nanoseconds: AIExplainSentenceService.retryDelayNanoseconds(for: attempt))
                            continue
                        }

                        if AIExplainSentenceService.shouldRetryEndpoint(statusCode: http.statusCode), index < endpointURLs.count - 1 {
                            let nextURL = endpointURLs[index + 1].absoluteString
                            TextPipelineDiagnostics.log(
                                "AI",
                                "[AI][ProfessorAnalysis] 切换候选地址: \(url.absoluteString) -> \(nextURL) status=\(http.statusCode)",
                                severity: .warning
                            )
                            lastError = AnalysisError.requestFailed("HTTP \(http.statusCode)")
                            break
                        }

                        throw AnalysisError.requestFailed("HTTP \(http.statusCode)")
                    }

                    let response = try JSONDecoder().decode(AnalyzePassageResponse.self, from: data)

                    guard let data = response.data else {
                        throw AnalysisError.noContent
                    }

                    payload = data
                    break
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as URLError {
                    if error.code == .cancelled || Task.isCancelled {
                        throw CancellationError()
                    }
                    if AIExplainSentenceService.shouldRetrySameEndpoint(for: error), attempt == 0 {
                        TextPipelineDiagnostics.log(
                            "AI",
                            "[AI][ProfessorAnalysis] 端点连接瞬断，准备重试: \(url.absoluteString) error=\(error.localizedDescription)",
                            severity: .warning
                        )
                        try await Task.sleep(nanoseconds: AIExplainSentenceService.retryDelayNanoseconds(for: attempt))
                        continue
                    }
                    if AIExplainSentenceService.shouldRetryEndpoint(for: error), index < endpointURLs.count - 1 {
                        let nextURL = endpointURLs[index + 1].absoluteString
                        TextPipelineDiagnostics.log(
                            "AI",
                            "[AI][ProfessorAnalysis] 端点连接失败，切换候选地址: \(url.absoluteString) -> \(nextURL) error=\(error.localizedDescription)",
                            severity: .warning
                        )
                        lastError = AnalysisError.requestFailed(error.localizedDescription)
                        break
                    }
                    throw AnalysisError.requestFailed(error.localizedDescription)
                } catch let error as AnalysisError {
                    if case .invalidServerResponse = error, index < endpointURLs.count - 1 {
                        let nextURL = endpointURLs[index + 1].absoluteString
                        TextPipelineDiagnostics.log(
                            "AI",
                            "[AI][ProfessorAnalysis] 端点响应异常，切换候选地址: \(url.absoluteString) -> \(nextURL)",
                            severity: .warning
                        )
                        lastError = error
                        break
                    }
                    throw error
                } catch {
                    if index < endpointURLs.count - 1 {
                        lastError = error
                        break
                    }
                    throw AnalysisError.invalidServerResponse
                }
            }

            if payload != nil {
                break
            }
        }

        guard let payload else {
            if let error = lastError as? AnalysisError {
                throw error
            }
            throw AnalysisError.noContent
        }

        if let warnings = payload.quality_warnings, !warnings.isEmpty {
            TextPipelineDiagnostics.log(
                "AI",
                "[AI][ProfessorAnalysis] 质量警告: \(warnings.joined(separator: "; "))",
                severity: .warning
            )
        }

        TextPipelineDiagnostics.log(
            "AI",
            "[AI][ProfessorAnalysis] 分析完成: paragraphCards=\(payload.paragraph_cards?.count ?? 0) sentenceAnalyses=\(payload.sentence_analyses?.count ?? 0) elapsed=\(payload.elapsed_ms ?? 0)ms",
            severity: .info
        )

        // 转换为本地模型并合并到 bundle
        let aiOverview = convertOverview(payload.passage_overview)
        let aiParagraphCards = convertParagraphCards(
            payload.paragraph_cards ?? [],
            segments: bundle.segments,
            sentencesBySegment: Dictionary(grouping: bundle.sentences, by: { $0.segmentID })
        )
        let aiSentenceCards = convertSentenceCards(
            payload.sentence_analyses ?? [],
            existingCards: bundle.professorSentenceCards,
            sentences: bundle.sentences,
            segments: bundle.segments
        )

        return bundle.enrichedWithAIAnalysis(
            overview: aiOverview,
            paragraphCards: aiParagraphCards,
            sentenceCards: aiSentenceCards
        )
    }

    // MARK: - 关键句选取

    private static func selectKeySentences(from bundle: StructuredSourceBundle) -> [KeySentenceInput] {
        var selected: [KeySentenceInput] = []
        var seenIDs: Set<String> = []

        let sentencesBySegment = Dictionary(grouping: bundle.sentences, by: { $0.segmentID })

        for (segIdx, segment) in bundle.segments.enumerated() {
            let sentences = sentencesBySegment[segment.id] ?? []
            let paragraphCard = bundle.paragraphCard(forSegmentID: segment.id)

            for sentence in sentences {
                let isCore = sentence.id == paragraphCard?.coreSentenceID
                let isKey = bundle.sentenceCard(id: sentence.id)?.isKeySentence == true
                let isLong = sentence.text.count >= 80

                guard isCore || isKey || isLong else { continue }
                guard seenIDs.insert(sentence.id).inserted else { continue }

                let ref = "S_\(segIdx)_\(sentence.localIndex)"
                selected.append(KeySentenceInput(
                    ref: ref,
                    text: sentence.text,
                    paragraph_index: segIdx
                ))
            }
        }

        // 限制最大数量
        return Array(selected.prefix(12))
    }

    // MARK: - DTO → 本地模型转换

    private static func convertOverview(_ dto: PassageOverviewDTO?) -> PassageOverview? {
        guard let dto else { return nil }
        return PassageOverview(
            articleTheme: dto.article_theme ?? "",
            authorCoreQuestion: dto.author_core_question ?? "",
            progressionPath: dto.progression_path ?? "",
            likelyQuestionTypes: dto.likely_question_types ?? [],
            logicPitfalls: dto.logic_pitfalls ?? [],
            paragraphFunctionMap: dto.paragraph_function_map ?? [],
            syntaxHighlights: dto.syntax_highlights ?? [],
            readingTraps: dto.reading_traps ?? [],
            vocabularyHighlights: dto.vocabulary_highlights ?? []
        )
    }

    private static func convertParagraphCards(
        _ dtos: [ParagraphCardDTO],
        segments: [Segment],
        sentencesBySegment: [String: [Sentence]]
    ) -> [ParagraphTeachingCard] {
        dtos.compactMap { dto in
            guard let paragraphIndex = dto.paragraph_index,
                  paragraphIndex < segments.count else { return nil }

            let segment = segments[paragraphIndex]
            let sentences = sentencesBySegment[segment.id] ?? []

            let roleString = dto.argument_role ?? "support"
            let role = ParagraphArgumentRole(rawValue: roleString) ?? .support

            let coreLocalIndex = dto.core_sentence_local_index ?? 0
            let coreSentenceID = sentences.first { $0.localIndex == coreLocalIndex }?.id
                ?? sentences.first?.id

            return ParagraphTeachingCard(
                id: segment.id,
                segmentID: segment.id,
                paragraphIndex: paragraphIndex,
                anchorLabel: segment.anchorLabel,
                theme: dto.theme ?? "",
                argumentRole: role,
                coreSentenceID: coreSentenceID,
                keywords: dto.keywords ?? [],
                relationToPrevious: dto.relation_to_previous ?? "",
                examValue: dto.exam_value ?? "",
                teachingFocuses: dto.teaching_focuses ?? [],
                studentBlindSpot: dto.student_blind_spot,
                isAIGenerated: true
            )
        }
    }

    private static func convertSentenceCards(
        _ dtos: [SentenceAnalysisDTO],
        existingCards: [ProfessorSentenceCard],
        sentences: [Sentence],
        segments: [Segment]
    ) -> [ProfessorSentenceCard] {
        let sentencesBySegment = Dictionary(grouping: sentences, by: { $0.segmentID })

        var refToSentences: [String: Sentence] = [:]
        for (segIdx, segment) in segments.enumerated() {
            let segmentID = segment.id
            for sentence in sentencesBySegment[segmentID] ?? [] {
                let ref = "S_\(segIdx)_\(sentence.localIndex)"
                refToSentences[ref] = sentence
            }
        }

        return dtos.compactMap { dto in
            guard let ref = dto.sentence_ref,
                  let sentence = refToSentences[ref] else { return nil }

            let analysis = ProfessorSentenceAnalysis(
                originalSentence: sentence.text,
                sentenceFunction: dto.sentence_function ?? "",
                coreSkeleton: dto.core_skeleton,
                chunkLayers: dto.chunk_layers ?? [],
                grammarFocus: dto.grammar_focus ?? [],
                naturalChineseMeaning: dto.natural_chinese_meaning ?? "",
                sentenceCore: dto.sentence_core ?? "",
                chunkBreakdown: dto.chunk_breakdown ?? [],
                grammarPoints: (dto.grammar_points ?? []).map {
                    ProfessorGrammarPoint(name: $0.name ?? "", explanation: $0.explanation ?? "")
                },
                vocabularyInContext: (dto.vocabulary_in_context ?? []).map {
                    ProfessorVocabularyItem(term: $0.term ?? "", meaning: $0.meaning ?? "")
                },
                misreadPoints: dto.misread_points ?? [],
                examRewritePoints: dto.exam_rewrite_points ?? [],
                misreadingTraps: dto.misreading_traps ?? [],
                examParaphraseRoutes: dto.exam_paraphrase_routes ?? [],
                simplifiedEnglish: dto.simplified_english ?? "",
                simplerRewrite: dto.simpler_rewrite ?? "",
                miniExercise: dto.mini_exercise,
                miniCheck: dto.mini_check,
                hierarchyRebuild: dto.hierarchy_rebuild ?? [],
                syntacticVariation: dto.syntactic_variation,
                evidenceType: dto.evidence_type,
                isAIGenerated: true
            )

            let existingCard = existingCards.first { $0.sentenceID == sentence.id }

            return ProfessorSentenceCard(
                id: sentence.id,
                sentenceID: sentence.id,
                segmentID: sentence.segmentID,
                isKeySentence: existingCard?.isKeySentence ?? true,
                analysis: analysis
            )
        }
    }
}
