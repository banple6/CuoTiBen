import Foundation

// MARK: - Card Generation Service Protocol
public protocol CardGenerationServiceProtocol {
    func generateCards(from chunk: KnowledgeChunk) async throws -> [Card]
    func regenerateCard(cardID: UUID) async throws -> Card
}

// MARK: - Card Generation Strategy
public enum CardGenerationStrategy: String, CaseIterable {
    case mvpThreeTypes = "三种卡型草稿"

    public var displayName: String {
        rawValue
    }
}

// MARK: - Card Generation Service Implementation
/// Generates card drafts from candidate knowledge points with three MVP card types only.
public final class CardGenerationService: CardGenerationServiceProtocol {
    private let strategy: CardGenerationStrategy

    public init(strategy: CardGenerationStrategy = .mvpThreeTypes) {
        self.strategy = strategy
    }

    public func generateCards(from chunk: KnowledgeChunk) async throws -> [Card] {
        guard !chunk.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CardGenerationError.noContent
        }

        switch strategy {
        case .mvpThreeTypes:
            return try await generateMVPDraftCards(from: chunk)
        }
    }

    public func regenerateCard(cardID: UUID) async throws -> Card {
        throw CardGenerationError.notImplemented("第一版暂不支持单卡重生成")
    }

    private func generateMVPDraftCards(from chunk: KnowledgeChunk) async throws -> [Card] {
        let focusPoints = chunk.candidateKnowledgePoints.isEmpty
            ? fallbackKnowledgePoints(from: chunk)
            : chunk.candidateKnowledgePoints

        guard let focus = focusPoints.first else {
            throw CardGenerationError.parsingFailed("未提取到候选知识点")
        }

        let supportingSentence = findSupportingSentence(for: focus, in: chunk.content) ?? chunk.content
        var cards: [Card] = []

        if let qaCard = buildQuestionAnswerCard(focus: focus, supportingSentence: supportingSentence, chunk: chunk) {
            cards.append(qaCard)
        }

        if let fillBlankCard = buildFillBlankCard(focus: focus, supportingSentence: supportingSentence, chunk: chunk) {
            cards.append(fillBlankCard)
        }

        if let choiceCard = buildTrueFalseChoiceCard(
            focus: focus,
            distractors: Array(focusPoints.dropFirst()),
            supportingSentence: supportingSentence,
            chunk: chunk
        ) {
            cards.append(choiceCard)
        }

        return cards
    }

    private func buildQuestionAnswerCard(
        focus: String,
        supportingSentence: String,
        chunk: KnowledgeChunk
    ) -> Card? {
        let answer = supportingSentence.cleanedCardText()
        guard !answer.isEmpty else { return nil }

        return Card(
            type: .questionAnswer,
            frontContent: "什么是\(focus)？",
            backContent: answer,
            keywords: Array((chunk.tags + [focus]).prefix(4)),
            knowledgeChunkID: chunk.id,
            difficultyLevel: difficultyLevel(for: answer),
            isDraft: true
        )
    }

    private func buildFillBlankCard(
        focus: String,
        supportingSentence: String,
        chunk: KnowledgeChunk
    ) -> Card? {
        guard focus.count >= 2 else { return nil }
        guard supportingSentence.contains(focus) else { return nil }

        let blanked = supportingSentence.replacingOccurrences(of: focus, with: "______", options: [], range: supportingSentence.range(of: focus))
        guard blanked != supportingSentence else { return nil }

        return Card(
            type: .fillInBlank,
            frontContent: blanked.cleanedCardText(),
            backContent: focus,
            keywords: Array((chunk.tags + [focus]).prefix(4)),
            knowledgeChunkID: chunk.id,
            difficultyLevel: difficultyLevel(for: focus),
            isDraft: true
        )
    }

    private func buildTrueFalseChoiceCard(
        focus: String,
        distractors: [String],
        supportingSentence: String,
        chunk: KnowledgeChunk
    ) -> Card? {
        let availableDistractors = deduplicated(distractors + chunk.tags)
            .filter { $0 != focus && $0.count >= 2 }

        if availableDistractors.count >= 2 {
            let options = Array(([focus] + availableDistractors.prefix(2)).shuffled())
            return Card(
                type: .trueFalseChoice,
                frontContent: """
                关于“\(chunk.title)”的核心知识点，以下哪一项最符合正文含义？

                A. \(options[safe: 0] ?? "")
                B. \(options[safe: 1] ?? "")
                C. \(options[safe: 2] ?? "")
                """.cleanedCardText(),
                backContent: "正确答案：\(focus)\n\(supportingSentence.cleanedCardText())",
                keywords: Array((chunk.tags + [focus]).prefix(4)),
                knowledgeChunkID: chunk.id,
                options: options,
                correctOption: focus,
                difficultyLevel: difficultyLevel(for: supportingSentence),
                isDraft: true
            )
        }

        let falseStatement = supportingSentence.replacingOccurrences(of: focus, with: chunk.title == focus ? "该概念" : chunk.title)
        let statement = falseStatement == supportingSentence ? supportingSentence : falseStatement

        return Card(
            type: .trueFalseChoice,
            frontContent: "判断正误：\(statement.cleanedCardText())",
            backContent: "正确答案：错误\n原表述：\(supportingSentence.cleanedCardText())",
            keywords: Array((chunk.tags + [focus]).prefix(4)),
            knowledgeChunkID: chunk.id,
            options: ["正确", "错误"],
            correctOption: "错误",
            difficultyLevel: difficultyLevel(for: statement),
            isDraft: true
        )
    }

    private func findSupportingSentence(for focus: String, in content: String) -> String? {
        content
            .splitIntoSentences()
            .first(where: { $0.contains(focus) && $0.count >= focus.count + 4 })
    }

    private func fallbackKnowledgePoints(from chunk: KnowledgeChunk) -> [String] {
        let firstSentences = chunk.content.splitIntoSentences()
        let fallback = firstSentences.compactMap { sentence -> String? in
            let cleaned = sentence.cleanedCardText()
            guard cleaned.count >= 2 else { return nil }
            return String(cleaned.prefix(16)).cleanedCardText()
        }

        return Array(deduplicated([chunk.title] + fallback).prefix(4))
    }

    private func difficultyLevel(for content: String) -> Int {
        switch content.count {
        case ..<12: return 2
        case ..<28: return 3
        case ..<56: return 4
        default: return 5
        }
    }

    private func deduplicated(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for value in values {
            let cleaned = value.cleanedCardText()
            guard !cleaned.isEmpty, !seen.contains(cleaned) else { continue }
            seen.insert(cleaned)
            result.append(cleaned)
        }

        return result
    }
}

// MARK: - Card Generation Errors
public enum CardGenerationError: LocalizedError {
    case noContent
    case parsingFailed(String)
    case notImplemented(String)

    public var errorDescription: String? {
        switch self {
        case .noContent:
            return "知识块内容为空"
        case .parsingFailed(let reason):
            return "卡片生成失败：\(reason)"
        case .notImplemented(let feature):
            return "功能尚未实现：\(feature)"
        }
    }
}

private extension String {
    func splitIntoSentences() -> [String] {
        components(separatedBy: CharacterSet(charactersIn: "。！？；\n"))
            .map { $0.cleanedCardText() }
            .filter { !$0.isEmpty }
    }

    func cleanedCardText() -> String {
        trimmingCharacters(in: CharacterSet(charactersIn: " \n\t，。！？；：“”‘’()（）[]【】"))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
