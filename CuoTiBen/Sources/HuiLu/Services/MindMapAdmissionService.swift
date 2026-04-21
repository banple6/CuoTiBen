import Foundation

enum MindMapAdmissionService {
    static func buildPassageMap(
        from bundle: StructuredSourceBundle,
        documentID: String? = nil
    ) -> PassageMap {
        let resolvedDocumentID = documentID ?? bundle.source.id
        let overview = bundle.passageOverview
        let segmentIndex = Dictionary(uniqueKeysWithValues: bundle.segments.map { ($0.id, $0) })
        let generatedFrom = passageGeneratedFrom(bundle: bundle, overview: overview)
        let paragraphMaps = bundle.paragraphTeachingCards.map { card in
            let segment = segmentIndex[card.segmentID]
            return ParagraphMap(
                id: card.id,
                segmentID: card.segmentID,
                paragraphIndex: card.paragraphIndex,
                anchorLabel: card.anchorLabel,
                theme: truncate(card.displayedTheme.nonEmpty ?? card.theme, limit: 22),
                argumentRole: card.argumentRole,
                coreSentenceID: card.coreSentenceID,
                relationToPrevious: truncate(card.displayedRelationToPrevious.nonEmpty ?? card.relationToPrevious, limit: 50),
                examValue: truncate(card.displayedExamValue.nonEmpty ?? card.examValue, limit: 40),
                teachingFocuses: card.displayedTeachingFocuses.map { truncate($0, limit: 40) },
                studentBlindSpot: card.displayedStudentBlindSpot.map { truncate($0, limit: 40) },
                provenance: NodeProvenance(
                    sourceSegmentID: card.segmentID,
                    sourceSentenceID: card.coreSentenceID,
                    sourceBlockID: nil,
                    sourcePage: segment?.page,
                    sourceKind: segment?.provenance.sourceKind ?? .passageBody,
                    generatedFrom: generatedFrom,
                    hygieneScore: segment?.hygiene.score ?? 0.5,
                    consistencyScore: segment?.provenance.consistencyScore ?? 0.5,
                    rejectedReason: nil
                )
            )
        }

        let keySentenceIDs = Array(
            Array(
                Set(bundle.professorSentenceCards.filter(\.isKeySentence).map(\.sentenceID) + bundle.questionLinks.flatMap(\.supportingSentenceIDs))
            ).prefix(6)
        )

        return PassageMap(
            documentID: resolvedDocumentID,
            sourceID: bundle.source.id,
            title: truncate(bundle.source.title, limit: 22),
            articleTheme: truncate(overview?.displayedArticleTheme.nonEmpty ?? bundle.source.title, limit: 60),
            authorCoreQuestion: truncate(overview?.displayedAuthorCoreQuestion.nonEmpty ?? "当前材料真正要回答的问题仍待进一步归纳。", limit: 60),
            progressionPath: truncate(overview?.displayedProgressionPath.nonEmpty ?? fallbackProgressionPath(from: paragraphMaps), limit: 60),
            paragraphMaps: paragraphMaps,
            keySentenceIDs: keySentenceIDs,
            questionLinks: bundle.questionLinks,
            diagnostics: []
        )
    }

    static func admit(
        bundle: StructuredSourceBundle,
        passageMap: PassageMap
    ) -> MindMapAdmissionResult {
        let segmentIndex = Dictionary(uniqueKeysWithValues: bundle.segments.map { ($0.id, $0) })
        let sentenceIndex = Dictionary(uniqueKeysWithValues: bundle.sentences.map { ($0.id, $0) })
        let sentencesBySegment = Dictionary(grouping: bundle.sentences, by: \.segmentID)
        let sentenceCardIndex = Dictionary(uniqueKeysWithValues: bundle.professorSentenceCards.map { ($0.sentenceID, $0) })
        let paragraphCardIndex = Dictionary(uniqueKeysWithValues: bundle.paragraphTeachingCards.map { ($0.segmentID, $0) })
        let paragraphOrder = Dictionary(uniqueKeysWithValues: passageMap.paragraphMaps.map { ("mindmap.paragraph.\($0.segmentID)", $0.paragraphIndex) })

        var mainlineNodes: [MindMapNode] = []
        var auxiliaryNodes: [MindMapNode] = []
        var rejectedNodes: [MindMapNode] = []
        var diagnostics: [MindMapAdmissionDiagnostic] = []
        var paragraphChildrenByID: [String: [MindMapNode]] = [:]

        for paragraph in passageMap.paragraphMaps {
            guard let segment = segmentIndex[paragraph.segmentID] else { continue }
            let sentences = sentencesBySegment[paragraph.segmentID] ?? []
            let paragraphResult = AnchorConsistencyValidator.evaluateParagraphCandidate(
                paragraph: paragraph,
                segment: segment,
                sentences: sentences
            )
            let paragraphNode = node(
                id: "mindmap.paragraph.\(paragraph.segmentID)",
                kind: .paragraph,
                title: truncate(paragraph.theme, limit: 22),
                summary: truncate(paragraph.examValue.nonEmpty ?? paragraph.relationToPrevious, limit: 50),
                children: [],
                provenance: paragraph.provenance.withRejectedReason(paragraphResult.rejectedReason),
                admission: paragraphResult.admission
            )
            diagnostics.append(diagnostic(for: paragraphNode, result: paragraphResult))
            route(
                paragraphNode,
                into: paragraphResult.admission,
                mainline: &mainlineNodes,
                auxiliary: &auxiliaryNodes,
                rejected: &rejectedNodes
            )

            if let card = paragraphCardIndex[paragraph.segmentID],
               let firstFocus = card.displayedTeachingFocuses.first?.nonEmpty {
                let focusResult = AnchorConsistencyValidator.evaluateParagraphFocusCandidate(
                    paragraph: paragraph,
                    focusSummary: firstFocus,
                    segment: segment,
                    sentences: sentences
                )
                let focusNode = node(
                    id: "mindmap.focus.\(paragraph.segmentID)",
                    kind: .teachingFocus,
                    title: truncate(firstFocus, limit: 22),
                    summary: truncate(card.displayedStudentBlindSpot?.nonEmpty ?? card.displayedExamValue, limit: 40),
                    children: [],
                    provenance: NodeProvenance(
                        sourceSegmentID: paragraph.segmentID,
                        sourceSentenceID: paragraph.coreSentenceID,
                        sourcePage: segment.page,
                        sourceKind: paragraph.provenance.sourceKind,
                        generatedFrom: .paragraphCard,
                        hygieneScore: paragraph.provenance.hygieneScore,
                        consistencyScore: focusResult.consistencyScore,
                        rejectedReason: focusResult.rejectedReason
                    ),
                    admission: focusResult.admission
                )
                diagnostics.append(diagnostic(for: focusNode, result: focusResult))
                attachOrRoute(
                    focusNode,
                    parentID: paragraphNode.id,
                    parentAdmission: paragraphResult.admission,
                    childAdmission: focusResult.admission,
                    paragraphChildrenByID: &paragraphChildrenByID,
                    mainline: &mainlineNodes,
                    auxiliary: &auxiliaryNodes,
                    rejected: &rejectedNodes
                )
            }

            if let coreSentenceID = paragraph.coreSentenceID,
               let sentence = sentenceIndex[coreSentenceID] {
                let sentenceResult = AnchorConsistencyValidator.evaluateSentenceCandidate(
                    sentence: sentence,
                    segment: segment,
                    analysis: sentenceCardIndex[coreSentenceID]?.analysis
                )
                let sentenceSummary = sentenceCardIndex[coreSentenceID]?.analysis.renderedTeachingInterpretation.nonEmpty
                    ?? sentence.text
                let sentenceNode = node(
                    id: "mindmap.sentence.\(coreSentenceID)",
                    kind: .anchorSentence,
                    title: truncate("锚句｜\(sentence.anchorLabel)", limit: 22),
                    summary: truncate(sentenceSummary, limit: 36),
                    children: [],
                    provenance: NodeProvenance(
                        sourceSegmentID: sentence.segmentID,
                        sourceSentenceID: sentence.id,
                        sourcePage: sentence.page,
                        sourceKind: sentence.provenance.sourceKind,
                        generatedFrom: sentenceCardIndex[coreSentenceID] == nil ? .normalizedDocument : .sentenceCard,
                        hygieneScore: sentence.hygiene.score,
                        consistencyScore: sentenceResult.consistencyScore,
                        rejectedReason: sentenceResult.rejectedReason
                    ),
                    admission: sentenceResult.admission
                )
                diagnostics.append(diagnostic(for: sentenceNode, result: sentenceResult))
                attachOrRoute(
                    sentenceNode,
                    parentID: paragraphNode.id,
                    parentAdmission: paragraphResult.admission,
                    childAdmission: sentenceResult.admission,
                    paragraphChildrenByID: &paragraphChildrenByID,
                    mainline: &mainlineNodes,
                    auxiliary: &auxiliaryNodes,
                    rejected: &rejectedNodes
                )
            }
        }

        for link in passageMap.questionLinks {
            let relatedSegmentID = link.supportParagraphIDs.first
            let segment = relatedSegmentID.flatMap { segmentIndex[$0] }
            let evidenceText = link.paraphraseEvidence.first?.nonEmpty ?? link.questionText
            let sourceKind: SourceContentKind = link.answerKeySnippet == nil ? .question : .answerKey
            let evidenceResult = AnchorConsistencyValidator.evaluateAuxiliaryCandidate(
                title: link.trapType.nonEmpty ?? "题目证据",
                summary: evidenceText,
                sourceKind: sourceKind,
                hygieneScore: segment?.hygiene.score ?? 0.5,
                supportingSentenceID: link.supportingSentenceIDs.first,
                segmentID: relatedSegmentID,
                sentences: relatedSegmentID.flatMap { sentencesBySegment[$0] } ?? []
            )
            let evidenceNode = node(
                id: "mindmap.evidence.\(link.id)",
                kind: .evidence,
                title: truncate(link.trapType.nonEmpty ?? "题目证据", limit: 22),
                summary: truncate(evidenceText, limit: 40),
                children: [],
                provenance: NodeProvenance(
                    sourceSegmentID: relatedSegmentID,
                    sourceSentenceID: link.supportingSentenceIDs.first,
                    sourcePage: segment?.page,
                    sourceKind: sourceKind,
                    generatedFrom: .questionLink,
                    hygieneScore: segment?.hygiene.score ?? 0.5,
                    consistencyScore: evidenceResult.consistencyScore,
                    rejectedReason: evidenceResult.rejectedReason
                ),
                admission: evidenceResult.admission
            )
            diagnostics.append(diagnostic(for: evidenceNode, result: evidenceResult))
            route(
                evidenceNode,
                into: evidenceResult.admission,
                mainline: &mainlineNodes,
                auxiliary: &auxiliaryNodes,
                rejected: &rejectedNodes
            )
        }

        let nonPassageSegments = bundle.segments.filter { !$0.provenance.sourceKind.isAllowedForMainlineSource }
        for segment in nonPassageSegments {
            let mappedKind: MindMapNodeKind = segment.provenance.sourceKind == .vocabularySupport ? .vocabulary : .auxiliary
            let candidateResult = AnchorConsistencyValidator.evaluateAuxiliaryCandidate(
                title: segment.provenance.sourceKind.displayName,
                summary: segment.text,
                sourceKind: segment.provenance.sourceKind,
                hygieneScore: segment.hygiene.score,
                supportingSentenceID: segment.sentenceIDs.first,
                segmentID: segment.id,
                sentences: sentencesBySegment[segment.id] ?? []
            )
            let auxiliaryNode = node(
                id: "mindmap.aux.\(segment.id)",
                kind: mappedKind,
                title: truncate(segment.provenance.sourceKind.displayName, limit: 22),
                summary: truncate(segment.text, limit: 40),
                children: [],
                provenance: NodeProvenance(
                    sourceSegmentID: segment.id,
                    sourceSentenceID: segment.sentenceIDs.first,
                    sourcePage: segment.page,
                    sourceKind: segment.provenance.sourceKind,
                    generatedFrom: .normalizedDocument,
                    hygieneScore: segment.hygiene.score,
                    consistencyScore: candidateResult.consistencyScore,
                    rejectedReason: candidateResult.rejectedReason
                ),
                admission: candidateResult.admission
            )
            diagnostics.append(diagnostic(for: auxiliaryNode, result: candidateResult))
            route(
                auxiliaryNode,
                into: candidateResult.admission,
                mainline: &mainlineNodes,
                auxiliary: &auxiliaryNodes,
                rejected: &rejectedNodes
            )
        }

        let rootProvenance = rootProvenance(from: passageMap)
        let rootSummary = truncate(
            passageMap.authorCoreQuestion.nonEmpty ?? passageMap.progressionPath.nonEmpty ?? passageMap.articleTheme,
            limit: 60
        )
        let rootNode = MindMapNode(
            id: "mindmap.root.\(passageMap.documentID)",
            kind: .root,
            title: truncate(passageMap.articleTheme.nonEmpty ?? passageMap.title, limit: 22),
            summary: rootSummary,
            children: mainlineNodes
                .filter { $0.kind == .paragraph }
                .sorted {
                    let lhs = paragraphOrder[$0.id] ?? .max
                    let rhs = paragraphOrder[$1.id] ?? .max
                    if lhs != rhs { return lhs < rhs }
                    return $0.title < $1.title
                }
                .map { paragraph in
                    MindMapNode(
                        id: paragraph.id,
                        kind: paragraph.kind,
                        title: paragraph.title,
                        summary: paragraph.summary,
                        children: paragraphChildrenByID[paragraph.id] ?? [],
                        provenance: paragraph.provenance,
                        admission: paragraph.admission
                    )
                },
            provenance: rootProvenance,
            admission: .mainline
        )

        let rootDiagnostic = MindMapAdmissionDiagnostic(
            nodeID: rootNode.id,
            nodeType: .root,
            sourceSegmentID: rootProvenance.sourceSegmentID,
            sourceSentenceID: rootProvenance.sourceSentenceID,
            sourceKind: rootProvenance.sourceKind,
            hygieneScore: rootProvenance.hygieneScore,
            consistencyScore: rootProvenance.consistencyScore,
            admission: .mainline,
            rejectedReason: nil
        )

        let allMainline = [rootNode] + mainlineNodes
        let result = MindMapAdmissionResult(
            mainlineNodes: allMainline,
            auxiliaryNodes: auxiliaryNodes,
            rejectedNodes: rejectedNodes,
            diagnostics: [rootDiagnostic] + diagnostics
        )

        logDiagnosticsSummary(result)
        return result
    }

    private static func rootProvenance(from passageMap: PassageMap) -> NodeProvenance {
        let paragraphProvenances = passageMap.paragraphMaps.map(\.provenance)
        let hygiene = paragraphProvenances.isEmpty
            ? 0.5
            : paragraphProvenances.map(\.hygieneScore).reduce(0, +) / Double(paragraphProvenances.count)
        let consistency = paragraphProvenances.isEmpty
            ? 0.5
            : paragraphProvenances.map(\.consistencyScore).reduce(0, +) / Double(paragraphProvenances.count)
        return NodeProvenance(
            sourceSegmentID: paragraphProvenances.first?.sourceSegmentID,
            sourceSentenceID: paragraphProvenances.first?.sourceSentenceID,
            sourcePage: paragraphProvenances.first?.sourcePage,
            sourceKind: .passageBody,
            generatedFrom: .aiPassageAnalysis,
            hygieneScore: hygiene,
            consistencyScore: max(consistency, 0.75),
            rejectedReason: nil
        )
    }

    private static func passageGeneratedFrom(
        bundle: StructuredSourceBundle,
        overview: PassageOverview?
    ) -> NodeGeneratedFrom {
        let question = overview?.displayedAuthorCoreQuestion.lowercased() ?? ""
        if question.contains("本地结构骨架") || question.contains("暂不可用") {
            return .localFallback
        }
        if bundle.paragraphTeachingCards.contains(where: \.isAIGenerated) {
            return .aiPassageAnalysis
        }
        return .normalizedDocument
    }

    private static func route(
        _ node: MindMapNode,
        into admission: MindMapAdmission,
        mainline: inout [MindMapNode],
        auxiliary: inout [MindMapNode],
        rejected: inout [MindMapNode]
    ) {
        switch admission {
        case .mainline:
            mainline.append(node)
        case .auxiliary:
            auxiliary.append(node)
        case .rejected:
            rejected.append(node)
        }
    }

    private static func attachOrRoute(
        _ node: MindMapNode,
        parentID: String,
        parentAdmission: MindMapAdmission,
        childAdmission: MindMapAdmission,
        paragraphChildrenByID: inout [String: [MindMapNode]],
        mainline: inout [MindMapNode],
        auxiliary: inout [MindMapNode],
        rejected: inout [MindMapNode]
    ) {
        if parentAdmission == .mainline, childAdmission == .mainline {
            paragraphChildrenByID[parentID, default: []].append(node)
            mainline.append(node)
            return
        }
        route(node, into: childAdmission, mainline: &mainline, auxiliary: &auxiliary, rejected: &rejected)
    }

    private static func node(
        id: String,
        kind: MindMapNodeKind,
        title: String,
        summary: String,
        children: [MindMapNode],
        provenance: NodeProvenance,
        admission: MindMapAdmission
    ) -> MindMapNode {
        MindMapNode(
            id: id,
            kind: kind,
            title: truncate(title, limit: 22),
            summary: summaryLimit(for: kind, text: summary),
            children: children,
            provenance: provenance,
            admission: admission
        )
    }

    private static func diagnostic(
        for node: MindMapNode,
        result: AnchorConsistencyResult
    ) -> MindMapAdmissionDiagnostic {
        MindMapAdmissionDiagnostic(
            nodeID: node.id,
            nodeType: node.kind,
            sourceSegmentID: node.provenance.sourceSegmentID,
            sourceSentenceID: node.provenance.sourceSentenceID,
            sourceKind: node.provenance.sourceKind,
            hygieneScore: node.provenance.hygieneScore,
            consistencyScore: result.consistencyScore,
            admission: result.admission,
            rejectedReason: result.rejectedReason
        )
    }

    private static func summaryLimit(for kind: MindMapNodeKind, text: String) -> String {
        switch kind {
        case .root:
            return truncate(text, limit: 60)
        case .paragraph:
            return truncate(text, limit: 50)
        case .teachingFocus, .evidence, .vocabulary, .auxiliary:
            return truncate(text, limit: 40)
        case .anchorSentence:
            return truncate(text, limit: 36)
        case .diagnostic:
            return truncate(text, limit: 40)
        }
    }

    private static func fallbackProgressionPath(from paragraphMaps: [ParagraphMap]) -> String {
        guard !paragraphMaps.isEmpty else {
            return "当前材料尚未形成稳定段落地图。"
        }
        return paragraphMaps
            .sorted { $0.paragraphIndex < $1.paragraphIndex }
            .map { "第\($0.paragraphIndex + 1)段：\($0.argumentRole.displayName)" }
            .joined(separator: " → ")
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(max(limit - 1, 0))) + "…"
    }

    private static func logDiagnosticsSummary(_ result: MindMapAdmissionResult) {
        let topReasons = result.topRejectedReasons
            .prefix(3)
            .map { "\($0.reason):\($0.count)" }
            .joined(separator: "||")
        TextPipelineDiagnostics.log(
            "导图准入",
            [
                "mainline_count=\(result.mainlineCount)",
                "auxiliary_count=\(result.auxiliaryCount)",
                "rejected_count=\(result.rejectedCount)",
                String(format: "average_hygiene=%.2f", result.averageHygieneScore),
                String(format: "average_consistency=%.2f", result.averageConsistencyScore),
                "top_rejected_reasons=\(topReasons.isEmpty ? "none" : topReasons)"
            ].joined(separator: " "),
            severity: result.rejectedCount > 0 ? .warning : .info
        )
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
