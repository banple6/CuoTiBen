import Foundation

@MainActor
final class LearningRecordContextService {
    private struct SentenceLocation {
        let documentID: UUID
        let bundle: StructuredSourceBundle
        let sentence: Sentence
    }

    private struct NotesRankingKey: Hashable {
        let sourceID: UUID?
        let sentenceID: String?
        let outlineNodeID: String?
        let termsKey: String
        let preferredKnowledgePointKey: String
    }

    private struct KnowledgePointRankingKey: Hashable {
        let sourceID: UUID?
        let sentenceID: String?
        let outlineNodeID: String?
        let termsKey: String
        let noteIDsKey: String
        let preferredKnowledgePointKey: String
    }

    private struct SentenceRankingKey: Hashable {
        let sourceID: UUID?
        let baseSentenceID: String?
        let outlineNodeID: String?
        let relatedNoteIDsKey: String
        let relatedKnowledgePointIDsKey: String
        let matchingTermsKey: String
    }

    private struct CardRankingKey: Hashable {
        let sourceID: UUID?
        let termsKey: String
        let preferredKnowledgePointKey: String
    }

    private let sourceDocuments: [SourceDocument]
    private let structuredSources: [UUID: StructuredSourceBundle]
    private let knowledgeChunks: [KnowledgeChunk]
    private let notes: [Note]
    private let knowledgePoints: [KnowledgePoint]
    private let reviewQueue: [Card]
    private let cardDrafts: [Card]

    private let sourceDocumentLookup: [UUID: SourceDocument]
    private let knowledgeChunkLookup: [UUID: KnowledgeChunk]
    private let knowledgePointLookup: [String: KnowledgePoint]
    private let noteLookup: [UUID: Note]
    private let sentenceLocationLookup: [String: SentenceLocation]
    private let allCards: [Card]

    private var sentenceContextCache: [String: LearningRecordContext] = [:]
    private var wordContextCache: [String: LearningRecordContext] = [:]
    private var noteContextCache: [UUID: LearningRecordContext] = [:]
    private var knowledgePointContextCache: [String: LearningRecordContext] = [:]
    private var rankedNotesCache: [NotesRankingKey: [Note]] = [:]
    private var rankedKnowledgePointsCache: [KnowledgePointRankingKey: [KnowledgePoint]] = [:]
    private var rankedSentencesCache: [SentenceRankingKey: [LearningRecordSentenceItem]] = [:]
    private var rankedCardsCache: [CardRankingKey: [LearningRecordCardItem]] = [:]

    init(
        sourceDocuments: [SourceDocument],
        structuredSources: [UUID: StructuredSourceBundle],
        knowledgeChunks: [KnowledgeChunk],
        notes: [Note],
        knowledgePoints: [KnowledgePoint],
        reviewQueue: [Card],
        cardDrafts: [Card]
    ) {
        self.sourceDocuments = sourceDocuments
        self.structuredSources = structuredSources
        self.knowledgeChunks = knowledgeChunks
        self.notes = notes
        self.knowledgePoints = knowledgePoints
        self.reviewQueue = reviewQueue
        self.cardDrafts = cardDrafts

        self.sourceDocumentLookup = Dictionary(uniqueKeysWithValues: sourceDocuments.map { ($0.id, $0) })
        self.knowledgeChunkLookup = Dictionary(uniqueKeysWithValues: knowledgeChunks.map { ($0.id, $0) })
        self.knowledgePointLookup = Dictionary(uniqueKeysWithValues: knowledgePoints.map { ($0.id, $0) })
        self.noteLookup = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })

        var sentenceLookup: [String: SentenceLocation] = [:]
        for (documentID, bundle) in structuredSources {
            for sentence in bundle.sentences {
                sentenceLookup[sentence.id] = SentenceLocation(
                    documentID: documentID,
                    bundle: bundle,
                    sentence: sentence
                )
            }
        }
        self.sentenceLocationLookup = sentenceLookup
        self.allCards = Self.uniqueBy(reviewQueue + cardDrafts, id: \.id)
    }

    func context(forSentenceID sentenceID: String) -> LearningRecordContext {
        if let cached = sentenceContextCache[sentenceID] {
            return cached
        }

        let entryPoint = LearningRecordEntryPoint.sentence(sentenceID: sentenceID)
        let location = sentenceLocation(for: sentenceID)
        let primarySentence = location?.sentence
        let primaryAnchor = primarySentence.flatMap {
            guard let location else { return nil }
            return sourceAnchor(for: $0, documentID: location.documentID, bundle: location.bundle)
        } ?? notes.first(where: { $0.sourceAnchor.sentenceID == sentenceID })?.sourceAnchor
        let sourceID = location?.documentID ?? primaryAnchor?.sourceID
        let outlineNodeID = location?.bundle.bestOutlineNode(forSentenceID: sentenceID)?.id ?? primaryAnchor?.outlineNodeID
        let baseTerms = searchTerms(
            from: [
                primarySentence?.text,
                primaryAnchor?.quotedText
            ]
        )

        let relatedNotes = rankedNotes(
            sourceID: sourceID,
            sentenceID: sentenceID,
            outlineNodeID: outlineNodeID,
            terms: baseTerms,
            preferredKnowledgePointIDs: []
        )
        let relatedKnowledgePoints = rankedKnowledgePoints(
            sourceID: sourceID,
            sentenceID: sentenceID,
            outlineNodeID: outlineNodeID,
            terms: baseTerms,
            notes: relatedNotes,
            preferredKnowledgePointIDs: []
        )
        let relatedSentences = rankedSentences(
            sourceID: sourceID,
            baseSentenceID: sentenceID,
            outlineNodeID: outlineNodeID,
            relatedNotes: relatedNotes,
            relatedKnowledgePoints: relatedKnowledgePoints,
            matchingTerms: baseTerms
        )
        let relatedSourceAnchors = rankedSourceAnchors(
            primaryAnchor: primaryAnchor,
            relatedNotes: relatedNotes,
            relatedKnowledgePoints: relatedKnowledgePoints,
            relatedSentences: relatedSentences
        )
        let relatedCards = rankedCards(
            sourceID: sourceID,
            terms: baseTerms + relatedKnowledgePoints.flatMap { [$0.title] + $0.aliases },
            preferredKnowledgePointIDs: relatedKnowledgePoints.map(\.id)
        )

        let context = LearningRecordContext(
            entryPoint: entryPoint,
            primarySentence: primarySentence,
            primaryNote: nil,
            primaryKnowledgePoint: nil,
            primarySourceAnchor: primaryAnchor,
            relatedNotes: relatedNotes,
            relatedKnowledgePoints: relatedKnowledgePoints,
            relatedSentences: relatedSentences,
            relatedCards: relatedCards,
            relatedSourceAnchors: relatedSourceAnchors
        )
        sentenceContextCache[sentenceID] = context
        return context
    }

    func context(forWord term: String, lemma: String?, sentenceID: String) -> LearningRecordContext {
        let cacheKey = normalizedWordCacheKey(term: term, lemma: lemma, sentenceID: sentenceID)
        if let cached = wordContextCache[cacheKey] {
            return cached
        }

        let entryPoint = LearningRecordEntryPoint.word(term: term, lemma: lemma, sentenceID: sentenceID)
        let location = sentenceLocation(for: sentenceID)
        let primarySentence = location?.sentence
        let primaryAnchor = primarySentence.flatMap {
            guard let location else { return nil }
            return sourceAnchor(for: $0, documentID: location.documentID, bundle: location.bundle)
        } ?? notes.first(where: { $0.sourceAnchor.sentenceID == sentenceID })?.sourceAnchor
        let sourceID = location?.documentID ?? primaryAnchor?.sourceID
        let outlineNodeID = location?.bundle.bestOutlineNode(forSentenceID: sentenceID)?.id ?? primaryAnchor?.outlineNodeID
        let baseTerms = searchTerms(
            from: [
                term,
                lemma,
                primarySentence?.text
            ]
        )

        let relatedNotes = rankedNotes(
            sourceID: sourceID,
            sentenceID: sentenceID,
            outlineNodeID: outlineNodeID,
            terms: baseTerms,
            preferredKnowledgePointIDs: []
        )
        let relatedKnowledgePoints = rankedKnowledgePoints(
            sourceID: sourceID,
            sentenceID: sentenceID,
            outlineNodeID: outlineNodeID,
            terms: baseTerms,
            notes: relatedNotes,
            preferredKnowledgePointIDs: []
        )
        let relatedSentences = rankedSentences(
            sourceID: sourceID,
            baseSentenceID: sentenceID,
            outlineNodeID: outlineNodeID,
            relatedNotes: relatedNotes,
            relatedKnowledgePoints: relatedKnowledgePoints,
            matchingTerms: baseTerms
        )
        let relatedSourceAnchors = rankedSourceAnchors(
            primaryAnchor: primaryAnchor,
            relatedNotes: relatedNotes,
            relatedKnowledgePoints: relatedKnowledgePoints,
            relatedSentences: relatedSentences
        )
        let relatedCards = rankedCards(
            sourceID: sourceID,
            terms: baseTerms + relatedKnowledgePoints.flatMap { [$0.title] + $0.aliases },
            preferredKnowledgePointIDs: relatedKnowledgePoints.map(\.id)
        )

        let context = LearningRecordContext(
            entryPoint: entryPoint,
            primarySentence: primarySentence,
            primaryNote: nil,
            primaryKnowledgePoint: nil,
            primarySourceAnchor: primaryAnchor,
            relatedNotes: relatedNotes,
            relatedKnowledgePoints: relatedKnowledgePoints,
            relatedSentences: relatedSentences,
            relatedCards: relatedCards,
            relatedSourceAnchors: relatedSourceAnchors
        )
        wordContextCache[cacheKey] = context
        return context
    }

    func context(forNoteID noteID: UUID) -> LearningRecordContext {
        if let cached = noteContextCache[noteID] {
            return cached
        }

        let entryPoint = LearningRecordEntryPoint.note(noteID: noteID)
        guard let note = noteLookup[noteID] else {
            let empty = LearningRecordContext.empty(for: entryPoint)
            noteContextCache[noteID] = empty
            return empty
        }

        let sentenceID = note.sourceAnchor.sentenceID
        let outlineNodeID = note.sourceAnchor.outlineNodeID
        let sourceID = note.sourceAnchor.sourceID
        let primarySentence = sentenceID.flatMap { sentenceLocation(for: $0)?.sentence }
        let preferredKnowledgePointIDs = note.linkedKnowledgePointIDs
        let baseTerms = searchTerms(
            from: [
                note.title,
                note.summary,
                note.sourceAnchor.quotedText
            ]
        )

        let secondaryNotes = rankedNotes(
            sourceID: sourceID,
            sentenceID: sentenceID,
            outlineNodeID: outlineNodeID,
            terms: baseTerms,
            preferredKnowledgePointIDs: preferredKnowledgePointIDs
        )
        let relatedNotes = uniqueNotes([note] + secondaryNotes)
        let relatedKnowledgePoints = rankedKnowledgePoints(
            sourceID: sourceID,
            sentenceID: sentenceID,
            outlineNodeID: outlineNodeID,
            terms: baseTerms,
            notes: relatedNotes,
            preferredKnowledgePointIDs: preferredKnowledgePointIDs
        )
        let relatedSentences = rankedSentences(
            sourceID: sourceID,
            baseSentenceID: sentenceID,
            outlineNodeID: outlineNodeID,
            relatedNotes: relatedNotes,
            relatedKnowledgePoints: relatedKnowledgePoints,
            matchingTerms: baseTerms
        )
        let relatedSourceAnchors = rankedSourceAnchors(
            primaryAnchor: note.sourceAnchor,
            relatedNotes: relatedNotes,
            relatedKnowledgePoints: relatedKnowledgePoints,
            relatedSentences: relatedSentences
        )
        let relatedCards = rankedCards(
            sourceID: sourceID,
            terms: baseTerms + relatedKnowledgePoints.flatMap { [$0.title] + $0.aliases },
            preferredKnowledgePointIDs: relatedKnowledgePoints.map(\.id)
        )

        let context = LearningRecordContext(
            entryPoint: entryPoint,
            primarySentence: primarySentence,
            primaryNote: note,
            primaryKnowledgePoint: nil,
            primarySourceAnchor: note.sourceAnchor,
            relatedNotes: relatedNotes,
            relatedKnowledgePoints: relatedKnowledgePoints,
            relatedSentences: relatedSentences,
            relatedCards: relatedCards,
            relatedSourceAnchors: relatedSourceAnchors
        )
        noteContextCache[noteID] = context
        return context
    }

    func context(forKnowledgePointID knowledgePointID: String) -> LearningRecordContext {
        if let cached = knowledgePointContextCache[knowledgePointID] {
            return cached
        }

        let entryPoint = LearningRecordEntryPoint.knowledgePoint(knowledgePointID: knowledgePointID)
        guard let point = knowledgePointByID(knowledgePointID) else {
            let empty = LearningRecordContext.empty(for: entryPoint)
            knowledgePointContextCache[knowledgePointID] = empty
            return empty
        }

        let sourceID = point.sourceAnchors.first?.sourceID
        let sentenceID = point.sourceAnchors.first?.sentenceID
        let outlineNodeID = point.sourceAnchors.first?.outlineNodeID
        let baseTerms = searchTerms(
            from: [point.title, point.definition] + point.aliases + [point.shortDefinition].compactMap { $0 }
        )

        let relatedNotes = rankedNotes(
            sourceID: sourceID,
            sentenceID: sentenceID,
            outlineNodeID: outlineNodeID,
            terms: baseTerms,
            preferredKnowledgePointIDs: [point.id]
        )
        let relatedKnowledgePoints = rankedKnowledgePoints(
            sourceID: sourceID,
            sentenceID: sentenceID,
            outlineNodeID: outlineNodeID,
            terms: baseTerms,
            notes: relatedNotes,
            preferredKnowledgePointIDs: [point.id]
        )
        let relatedSentences = rankedSentences(
            sourceID: sourceID,
            baseSentenceID: sentenceID,
            outlineNodeID: outlineNodeID,
            relatedNotes: relatedNotes,
            relatedKnowledgePoints: relatedKnowledgePoints,
            matchingTerms: baseTerms
        )
        let relatedSourceAnchors = rankedSourceAnchors(
            primaryAnchor: point.sourceAnchors.first,
            relatedNotes: relatedNotes,
            relatedKnowledgePoints: relatedKnowledgePoints,
            relatedSentences: relatedSentences
        )
        let relatedCards = rankedCards(
            sourceID: sourceID,
            terms: baseTerms + relatedKnowledgePoints.flatMap { [$0.title] + $0.aliases },
            preferredKnowledgePointIDs: relatedKnowledgePoints.map(\.id)
        )

        let context = LearningRecordContext(
            entryPoint: entryPoint,
            primarySentence: sentenceID.flatMap { sentenceLocation(for: $0)?.sentence },
            primaryNote: nil,
            primaryKnowledgePoint: point,
            primarySourceAnchor: point.sourceAnchors.first,
            relatedNotes: relatedNotes,
            relatedKnowledgePoints: relatedKnowledgePoints,
            relatedSentences: relatedSentences,
            relatedCards: relatedCards,
            relatedSourceAnchors: relatedSourceAnchors
        )
        knowledgePointContextCache[knowledgePointID] = context
        return context
    }

    private func rankedNotes(
        sourceID: UUID?,
        sentenceID: String?,
        outlineNodeID: String?,
        terms: [String],
        preferredKnowledgePointIDs: [String]
    ) -> [Note] {
        let normalizedTerms = searchTerms(from: terms)
        let cacheKey = NotesRankingKey(
            sourceID: sourceID,
            sentenceID: sentenceID,
            outlineNodeID: outlineNodeID,
            termsKey: cacheToken(from: normalizedTerms),
            preferredKnowledgePointKey: cacheToken(from: preferredKnowledgePointIDs)
        )
        if let cached = rankedNotesCache[cacheKey] {
            return cached
        }
        let preferredIDs = Set(preferredKnowledgePointIDs)

        let scored = notes.compactMap { note -> (Note, Double)? in
            var score = 0.0

            if let sentenceID, note.sourceAnchor.sentenceID == sentenceID {
                score += 4
            }
            if let outlineNodeID, note.sourceAnchor.outlineNodeID == outlineNodeID {
                score += 3
            }
            if let sourceID, note.sourceAnchor.sourceID == sourceID {
                score += 1
            }

            let linkedPointIDs = Set(note.linkedKnowledgePointIDs)
            score += Double(linkedPointIDs.intersection(preferredIDs).count) * 2

            let corpus = searchTerms(
                from: [
                    note.title,
                    note.summary,
                    note.sourceAnchor.quotedText
                ] + note.tags + note.knowledgePoints.map(\.title) + note.blocks.compactMap(\.text) + note.blocks.compactMap(\.recognizedText)
            )
            score += Double(matchCount(terms: normalizedTerms, in: corpus)) * 0.85

            guard score > 0 else { return nil }
            return (note, score)
        }

        let ranked = scored
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.updatedAt > $1.0.updatedAt
            }
            .map(\.0)

        if ranked.isEmpty, let sourceID {
            let fallback = Array(notes.filter { $0.sourceAnchor.sourceID == sourceID }.prefix(6))
            rankedNotesCache[cacheKey] = fallback
            return fallback
        }

        let result = Array(uniqueNotes(ranked).prefix(8))
        rankedNotesCache[cacheKey] = result
        return result
    }

    private func rankedKnowledgePoints(
        sourceID: UUID?,
        sentenceID: String?,
        outlineNodeID: String?,
        terms: [String],
        notes: [Note],
        preferredKnowledgePointIDs: [String]
    ) -> [KnowledgePoint] {
        let normalizedTerms = searchTerms(from: terms)
        let cacheKey = KnowledgePointRankingKey(
            sourceID: sourceID,
            sentenceID: sentenceID,
            outlineNodeID: outlineNodeID,
            termsKey: cacheToken(from: normalizedTerms),
            noteIDsKey: cacheToken(from: notes.map(\.id.uuidString)),
            preferredKnowledgePointKey: cacheToken(from: preferredKnowledgePointIDs)
        )
        if let cached = rankedKnowledgePointsCache[cacheKey] {
            return cached
        }
        let notePointIDs = Set(notes.flatMap(\.linkedKnowledgePointIDs))
        let preferredIDs = Set(preferredKnowledgePointIDs)

        let scored = knowledgePoints.compactMap { point -> (KnowledgePoint, Double)? in
            var score = 0.0
            let anchors = point.sourceAnchors

            if preferredIDs.contains(point.id) {
                score += 4
            }
            if notePointIDs.contains(point.id) {
                score += 3
            }
            if let sentenceID, anchors.contains(where: { $0.sentenceID == sentenceID }) {
                score += 3.5
            }
            if let outlineNodeID, anchors.contains(where: { $0.outlineNodeID == outlineNodeID }) {
                score += 3
            }
            if let sourceID, anchors.contains(where: { $0.sourceID == sourceID }) {
                score += 1
            }

            let corpus = searchTerms(from: [point.title, point.definition] + point.aliases + [point.shortDefinition].compactMap { $0 })
            score += Double(matchCount(terms: normalizedTerms, in: corpus)) * 1.1

            guard score > 0 else { return nil }
            return (point, score)
        }

        let ranked = scored
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.title.localizedCompare($1.0.title) == .orderedAscending
            }
            .map(\.0)

        let result = Array(uniqueKnowledgePoints(ranked).prefix(8))
        rankedKnowledgePointsCache[cacheKey] = result
        return result
    }

    private func rankedSentences(
        sourceID: UUID?,
        baseSentenceID: String?,
        outlineNodeID: String?,
        relatedNotes: [Note],
        relatedKnowledgePoints: [KnowledgePoint],
        matchingTerms: [String]
    ) -> [LearningRecordSentenceItem] {
        let normalizedTerms = searchTerms(from: matchingTerms)
        let cacheKey = SentenceRankingKey(
            sourceID: sourceID,
            baseSentenceID: baseSentenceID,
            outlineNodeID: outlineNodeID,
            relatedNoteIDsKey: cacheToken(from: relatedNotes.map(\.id.uuidString)),
            relatedKnowledgePointIDsKey: cacheToken(from: relatedKnowledgePoints.map(\.id)),
            matchingTermsKey: cacheToken(from: normalizedTerms)
        )
        if let cached = rankedSentencesCache[cacheKey] {
            return cached
        }

        var items: [LearningRecordSentenceItem] = []

        if let baseSentenceID, let location = sentenceLocation(for: baseSentenceID) {
            items.append(sentenceItem(for: location.sentence, documentID: location.documentID, bundle: location.bundle))

            if let segment = location.bundle.segment(id: location.sentence.segmentID) {
                items.append(contentsOf: location.bundle.sentences(in: segment).map {
                    sentenceItem(for: $0, documentID: location.documentID, bundle: location.bundle)
                })
            }

            if let outlineNodeID,
               let node = location.bundle.outlineNode(id: outlineNodeID) {
                items.append(contentsOf: node.sourceSentenceIDs.compactMap { id in
                    guard let sentence = location.bundle.sentence(id: id) else { return nil }
                    return sentenceItem(for: sentence, documentID: location.documentID, bundle: location.bundle)
                })
            }
        }

        for note in relatedNotes {
            if let sentence = sentence(for: note.sourceAnchor),
               let location = sentenceLocation(for: sentence.id) {
                items.append(sentenceItem(for: sentence, documentID: location.documentID, bundle: location.bundle))
            }
        }

        for point in relatedKnowledgePoints {
            for anchor in point.sourceAnchors {
                if let sentence = sentence(for: anchor),
                   let location = sentenceLocation(for: sentence.id) {
                    items.append(sentenceItem(for: sentence, documentID: location.documentID, bundle: location.bundle))
                }
            }
        }

        if let sourceID,
           let bundle = structuredSources[sourceID] {
            let fuzzyMatches = bundle.sentences.filter { sentence in
                matchCount(terms: normalizedTerms, in: searchTerms(from: [sentence.text])) > 0
            }
            items.append(contentsOf: fuzzyMatches.prefix(6).compactMap { sentence in
                sentenceLocation(for: sentence.id).map {
                    sentenceItem(for: sentence, documentID: $0.documentID, bundle: $0.bundle)
                }
            })
        }

        let result = Array(
            uniqueSentenceItems(items)
                .sorted { lhs, rhs in
                    sentenceItemSort(lhs: lhs, rhs: rhs)
                }
                .prefix(10)
        )
        rankedSentencesCache[cacheKey] = result
        return result
    }

    private func rankedSourceAnchors(
        primaryAnchor: SourceAnchor?,
        relatedNotes: [Note],
        relatedKnowledgePoints: [KnowledgePoint],
        relatedSentences: [LearningRecordSentenceItem]
    ) -> [SourceAnchor] {
        var anchors: [SourceAnchor] = []

        if let primaryAnchor {
            anchors.append(primaryAnchor)
        }

        anchors.append(contentsOf: relatedNotes.map(\.sourceAnchor))
        anchors.append(contentsOf: relatedKnowledgePoints.flatMap(\.sourceAnchors))
        anchors.append(contentsOf: relatedSentences.map(\.anchor))

        return uniqueSourceAnchors(anchors)
    }

    private func rankedCards(
        sourceID: UUID?,
        terms: [String],
        preferredKnowledgePointIDs: [String]
    ) -> [LearningRecordCardItem] {
        let normalizedTerms = searchTerms(from: terms)
        let cacheKey = CardRankingKey(
            sourceID: sourceID,
            termsKey: cacheToken(from: normalizedTerms),
            preferredKnowledgePointKey: cacheToken(from: preferredKnowledgePointIDs)
        )
        if let cached = rankedCardsCache[cacheKey] {
            return cached
        }
        let preferredPointIDs = Set(preferredKnowledgePointIDs)
        var scored: [(LearningRecordCardItem, Double)] = []

        for card in allCards {
            let chunk = knowledgeChunk(for: card)
            let chunkSourceID = chunk?.sourceDocumentID
            let chunkSearchValues = [
                card.frontContent,
                card.backContent
            ] + card.keywords + (chunk?.tags ?? []) + (chunk?.candidateKnowledgePoints ?? []) + [
                chunk?.title,
                chunk?.content,
                chunk?.sourceLocator
            ]
            .compactMap { $0 }

            let chunkTerms = searchTerms(from: chunkSearchValues)

            var score = 0.0
            if let sourceID, chunkSourceID == sourceID {
                score += 2
            }
            score += Double(matchCount(terms: normalizedTerms, in: chunkTerms)) * 0.9

            if let chunk {
                let candidateIDs = Set(chunk.candidateKnowledgePoints.map(normalizedKnowledgePointID(for:)))
                score += Double(candidateIDs.intersection(preferredPointIDs).count) * 2
            }

            guard score > 0 else { continue }
            scored.append((makeCardItem(card: card, chunk: chunk), score))
        }

        let ranked = scored
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                if $0.0.card.isDraft != $1.0.card.isDraft { return !$0.0.card.isDraft }
                return $0.0.card.priorityScore > $1.0.card.priorityScore
            }
            .map(\.0)

        if ranked.isEmpty, let sourceID {
            let fallback = allCards.compactMap { card -> LearningRecordCardItem? in
                guard let chunk = knowledgeChunk(for: card), chunk.sourceDocumentID == sourceID else { return nil }
                return makeCardItem(card: card, chunk: chunk)
            }
            let result = Array(uniqueCardItems(fallback).prefix(6))
            rankedCardsCache[cacheKey] = result
            return result
        }

        let result = Array(uniqueCardItems(ranked).prefix(6))
        rankedCardsCache[cacheKey] = result
        return result
    }

    private func sentenceLocation(for sentenceID: String) -> SentenceLocation? {
        sentenceLocationLookup[sentenceID]
    }

    private func sentence(for anchor: SourceAnchor) -> Sentence? {
        if let sentenceID = anchor.sentenceID,
           let sentence = structuredSources[anchor.sourceID]?.sentence(id: sentenceID) {
            return sentence
        }

        if let outlineNodeID = anchor.outlineNodeID,
           let node = structuredSources[anchor.sourceID]?.outlineNode(id: outlineNodeID),
           let sentenceID = node.primarySentenceID {
            return structuredSources[anchor.sourceID]?.sentence(id: sentenceID)
        }

        return nil
    }

    private func sourceAnchor(
        for sentence: Sentence,
        documentID: UUID,
        bundle: StructuredSourceBundle
    ) -> SourceAnchor {
        let sourceTitle = sourceDocument(with: documentID)?.title ?? bundle.source.title
        let node = bundle.bestOutlineNode(forSentenceID: sentence.id)

        return SourceAnchor(
            sourceID: documentID,
            sourceTitle: sourceTitle,
            pageIndex: sentence.page,
            sentenceID: sentence.id,
            outlineNodeID: node?.id,
            quotedText: sentence.text,
            anchorLabel: sentence.anchorLabel
        )
    }

    private func sentenceItem(
        for sentence: Sentence,
        documentID: UUID,
        bundle: StructuredSourceBundle
    ) -> LearningRecordSentenceItem {
        LearningRecordSentenceItem(
            sentence: sentence,
            anchor: sourceAnchor(for: sentence, documentID: documentID, bundle: bundle),
            sourceDocumentID: documentID,
            sourceTitle: sourceDocument(with: documentID)?.title ?? bundle.source.title
        )
    }

    private func makeCardItem(card: Card, chunk: KnowledgeChunk?) -> LearningRecordCardItem {
        let sourceTitle: String
        let sourceAnchor: SourceAnchor?
        if let documentID = chunk?.sourceDocumentID {
            sourceTitle = sourceDocument(with: documentID)?.title ?? "资料卡片"
            sourceAnchor = SourceAnchor(
                sourceID: documentID,
                sourceTitle: sourceTitle,
                pageIndex: chunk?.startPosition,
                sentenceID: nil,
                outlineNodeID: nil,
                quotedText: (chunk?.content.nonEmpty ?? card.backContent).trimmingCharacters(in: .whitespacesAndNewlines),
                anchorLabel: chunk?.sourceLocator ?? "相关卡片来源"
            )
        } else {
            sourceTitle = "资料卡片"
            sourceAnchor = nil
        }

        return LearningRecordCardItem(
            card: card,
            sourceDocumentID: chunk?.sourceDocumentID,
            sourceTitle: sourceTitle,
            chunkTitle: chunk?.title ?? card.frontContent,
            chunkSummary: (chunk?.content.nonEmpty ?? card.backContent).trimmingCharacters(in: .whitespacesAndNewlines),
            anchorLabel: chunk?.sourceLocator,
            sourceAnchor: sourceAnchor
        )
    }

    private func knowledgeChunk(for card: Card) -> KnowledgeChunk? {
        knowledgeChunkLookup[card.knowledgeChunkID]
    }

    private func sourceDocument(with id: UUID) -> SourceDocument? {
        sourceDocumentLookup[id]
    }

    private func knowledgePointByID(_ id: String) -> KnowledgePoint? {
        knowledgePointLookup[id]
    }

    private func uniqueNotes(_ items: [Note]) -> [Note] {
        Self.uniqueBy(items, id: \.id)
    }

    private func uniqueKnowledgePoints(_ items: [KnowledgePoint]) -> [KnowledgePoint] {
        Self.uniqueBy(items, id: \.id)
    }

    private func uniqueSentenceItems(_ items: [LearningRecordSentenceItem]) -> [LearningRecordSentenceItem] {
        Self.uniqueBy(items, id: \.id)
    }

    private func uniqueCardItems(_ items: [LearningRecordCardItem]) -> [LearningRecordCardItem] {
        Self.uniqueBy(items, id: \.id)
    }

    private func uniqueSourceAnchors(_ items: [SourceAnchor]) -> [SourceAnchor] {
        var seen: Set<String> = []
        var results: [SourceAnchor] = []

        for anchor in items {
            let key = [
                anchor.sourceID.uuidString,
                anchor.sentenceID ?? "",
                anchor.outlineNodeID ?? "",
                anchor.pageIndex.map(String.init) ?? "",
                anchor.anchorLabel
            ].joined(separator: "|")
            if seen.insert(key).inserted {
                results.append(anchor)
            }
        }

        return results
    }

    private static func uniqueBy<T, ID: Hashable>(_ items: [T], id: KeyPath<T, ID>) -> [T] {
        var seen: Set<ID> = []
        var results: [T] = []

        for item in items {
            let value = item[keyPath: id]
            if seen.insert(value).inserted {
                results.append(item)
            }
        }

        return results
    }

    private func sentenceItemSort(lhs: LearningRecordSentenceItem, rhs: LearningRecordSentenceItem) -> Bool {
        if lhs.anchor.pageIndex != rhs.anchor.pageIndex {
            return (lhs.anchor.pageIndex ?? 0) < (rhs.anchor.pageIndex ?? 0)
        }

        if lhs.sentence.index != rhs.sentence.index {
            return lhs.sentence.index < rhs.sentence.index
        }

        return lhs.sourceTitle.localizedCompare(rhs.sourceTitle) == .orderedAscending
    }

    private func searchTerms(from values: [String?]) -> [String] {
        let tokens = values
            .compactMap { $0 }
            .flatMap { value -> [String] in
                value
                    .lowercased()
                    .replacingOccurrences(of: "[^a-z0-9\\u4e00-\\u9fa5]+", with: " ", options: .regularExpression)
                    .split(separator: " ")
                    .map(String.init)
            }
            .filter { $0.count >= 2 }

        return Self.uniqueBy(tokens, id: \.self)
    }

    private func searchTerms(from values: [String]) -> [String] {
        searchTerms(from: values.map(Optional.some))
    }

    private func matchCount(terms: [String], in corpus: [String]) -> Int {
        guard !terms.isEmpty, !corpus.isEmpty else { return 0 }

        return terms.filter { term in
            corpus.contains(where: { token in
                token.contains(term) || term.contains(token)
            })
        }
        .count
    }

    private func normalizedKnowledgePointID(for value: String) -> String {
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\u4e00-\\u9fa5]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return normalized.isEmpty ? value.lowercased() : normalized
    }

    private func normalizedWordCacheKey(term: String, lemma: String?, sentenceID: String) -> String {
        [
            sentenceID,
            term.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
            lemma?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        ].joined(separator: "|")
    }

    private func cacheToken(from values: [String]) -> String {
        values
            .map {
                $0
                    .lowercased()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: "|")
    }
}

private extension String {
    var nonEmpty: String? {
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
