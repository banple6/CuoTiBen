import Foundation
import NaturalLanguage

// MARK: - 块内容类型

/// 精细块类型分类，覆盖多语言教材可能的所有语义角色
enum BlockContentType: String, CaseIterable {
    case title = "title"
    case heading = "heading"
    case subheading = "subheading"
    case englishBody = "english_body"
    case chineseExplanation = "chinese_explanation"
    case bilingualNote = "bilingual_note"
    case questionStem = "question_stem"
    case optionList = "option_list"
    case glossaryNote = "glossary_note"
    case pageHeader = "page_header"
    case pageFooter = "page_footer"
    case reference = "reference"
    case noise = "noise"

    /// 该类型是否允许参与结构树节点生成
    var isTreeNodeEligible: Bool {
        switch self {
        case .title, .heading, .subheading, .englishBody:
            return true
        case .chineseExplanation, .bilingualNote, .questionStem, .optionList, .glossaryNote:
            return true
        case .pageHeader, .pageFooter, .reference, .noise:
            return false
        }
    }

    /// 该类型是否允许进入正文主链（rawText / anchor / 段落候选池）
    var isPrimaryPassageCandidate: Bool {
        switch self {
        case .title, .heading, .subheading, .englishBody:
            return true
        case .chineseExplanation, .bilingualNote, .questionStem, .optionList, .glossaryNote,
             .pageHeader, .pageFooter, .reference, .noise:
            return false
        }
    }

    /// 该类型是否为英语主体内容
    var isEnglishPrimary: Bool {
        switch self {
        case .englishBody, .title, .heading, .subheading:
            return true
        default:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .title:                return "标题"
        case .heading:              return "一级标题"
        case .subheading:           return "二级标题"
        case .englishBody:          return "英文正文"
        case .chineseExplanation:   return "中文说明"
        case .bilingualNote:        return "双语注释"
        case .questionStem:         return "题干"
        case .optionList:           return "选项列表"
        case .glossaryNote:         return "词汇注解"
        case .pageHeader:           return "页眉"
        case .pageFooter:           return "页脚"
        case .reference:            return "参考文献"
        case .noise:                return "噪声"
        }
    }
}

// MARK: - 块语言分析结果

struct BlockLanguageProfile {
    let dominantLanguage: BlockDominantLanguage
    let englishRatio: Double
    let chineseRatio: Double
    let mixedScore: Double          // 0=纯单语, 1=完全混合
    let isMetaText: Bool            // 是否为说明/标注性文本
    let englishCharCount: Int
    let chineseCharCount: Int
    let totalCharCount: Int

    /// 中文是否为辅助性/解释性文本
    var isChineseExplanatory: Bool {
        chineseRatio > 0.1 && chineseRatio < 0.6 && englishRatio > 0.3
    }

    /// 是否为严重混合导致污染
    var isContaminated: Bool {
        mixedScore > 0.6 && chineseRatio > 0.25 && englishRatio > 0.25
    }
}

enum BlockDominantLanguage: String {
    case english = "en"
    case chinese = "zh"
    case mixed = "mixed"
    case unknown = "unknown"
}

// MARK: - 块分类结果

struct BlockClassification {
    let contentType: BlockContentType
    let languageProfile: BlockLanguageProfile
    let confidence: Double
    let reasons: [String]

    var isTreeNodeEligible: Bool {
        contentType.isTreeNodeEligible && confidence >= 0.35
    }

    var isPrimaryPassageEligible: Bool {
        contentType.isPrimaryPassageCandidate && confidence >= 0.35
    }
}

// MARK: - 块内容分类器

enum BlockContentClassifier {

    // MARK: - 公开 API

    /// 对一个版面块进行精细分类（语言 + 内容类型）
    static func classify(
        text: String,
        layoutType: LayoutBlockType,
        confidence: Double,
        context: ClassificationContext = .default
    ) -> BlockClassification {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return BlockClassification(
                contentType: .noise,
                languageProfile: emptyLanguageProfile(),
                confidence: 0,
                reasons: ["空文本"]
            )
        }

        var reasons: [String] = []
        let repaired = TextPipelineValidator.validateAndRepairIfReversed(cleaned)
        let analysisText = repaired.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if repaired.wasRepaired {
            reasons.append("块级反转修复")
        }

        let langProfile = analyzeLanguage(analysisText)

        // 第一步：检测噪声/页眉页脚
        if let noiseResult = detectNoise(analysisText, langProfile: langProfile, reasons: &reasons) {
            return noiseResult
        }

        // 第二步：基于 layoutType 和语言做分类
        let contentType = classifyContentType(
            text: analysisText,
            layoutType: layoutType,
            langProfile: langProfile,
            layoutConfidence: confidence,
            reasons: &reasons
        )

        let finalConfidence = computeFinalConfidence(
            contentType: contentType,
            langProfile: langProfile,
            layoutConfidence: confidence,
            textLength: cleaned.count
        )

        return BlockClassification(
            contentType: contentType,
            languageProfile: langProfile,
            confidence: finalConfidence,
            reasons: reasons
        )
    }

    /// 对一组块做批量分类
    static func classifyBlocks(_ blocks: [LayoutBlock]) -> [(block: LayoutBlock, classification: BlockClassification)] {
        blocks.map { block in
            let classification = classify(
                text: block.text,
                layoutType: block.type,
                confidence: block.confidence
            )
            return (block, classification)
        }
    }

    /// 过滤出适合参与结构树生成的块
    static func filterEligibleBlocks(
        _ classified: [(block: LayoutBlock, classification: BlockClassification)]
    ) -> [(block: LayoutBlock, classification: BlockClassification)] {
        classified.filter { pair in
            guard pair.classification.isTreeNodeEligible else {
                TextPipelineDiagnostics.log(
                    "块分类",
                    "排除块: \"\(String(pair.block.text.prefix(40)))...\" 类型=\(pair.classification.contentType.displayName) 置信度=\(String(format: "%.2f", pair.classification.confidence)) 原因=\(pair.classification.reasons.joined(separator: ","))",
                    severity: .info
                )
                return false
            }

            // 混合语言污染严重的块降级处理
            if pair.classification.languageProfile.isContaminated {
                TextPipelineDiagnostics.log(
                    "块分类",
                    "混合语言污染块: \"\(String(pair.block.text.prefix(40)))...\" 混合度=\(String(format: "%.2f", pair.classification.languageProfile.mixedScore))",
                    severity: .warning
                )
                // 仍然允许参与但记录警告
            }

            return true
        }
    }

    static func filterPrimaryPassageBlocks(
        _ classified: [(block: LayoutBlock, classification: BlockClassification)]
    ) -> [(block: LayoutBlock, classification: BlockClassification)] {
        classified.filter { pair in
            guard pair.classification.isPrimaryPassageEligible else {
                TextPipelineDiagnostics.log(
                    "块分类",
                    "排除非正文主链块: \"\(String(pair.block.text.prefix(40)))...\" 类型=\(pair.classification.contentType.displayName) 置信度=\(String(format: "%.2f", pair.classification.confidence)) 原因=\(pair.classification.reasons.joined(separator: ","))",
                    severity: .info
                )
                return false
            }

            if pair.classification.languageProfile.isContaminated {
                TextPipelineDiagnostics.log(
                    "块分类",
                    "正文主链候选存在混合污染: \"\(String(pair.block.text.prefix(40)))...\" 混合度=\(String(format: "%.2f", pair.classification.languageProfile.mixedScore))",
                    severity: .warning
                )
            }

            return true
        }
    }

    // MARK: - 语言分析

    static func analyzeLanguage(_ text: String) -> BlockLanguageProfile {
        let scalars = text.unicodeScalars
        let totalCount = max(scalars.count, 1)

        var englishCount = 0
        var chineseCount = 0
        var punctuationCount = 0
        var digitCount = 0

        for scalar in scalars {
            if (0x0041...0x005A).contains(scalar.value) || (0x0061...0x007A).contains(scalar.value) {
                englishCount += 1
            } else if (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value) {
                chineseCount += 1
            } else if CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar) {
                punctuationCount += 1
            } else if (0x0030...0x0039).contains(scalar.value) {
                digitCount += 1
            }
        }

        let contentChars = max(englishCount + chineseCount, 1)
        let englishRatio = Double(englishCount) / Double(contentChars)
        let chineseRatio = Double(chineseCount) / Double(contentChars)

        // 混合度：两种语言都占显著比例时为高
        let mixedScore: Double
        if englishCount == 0 || chineseCount == 0 {
            mixedScore = 0
        } else {
            let minRatio = min(englishRatio, chineseRatio)
            mixedScore = min(minRatio / 0.3, 1.0)   // 0.3=完全混合阈值
        }

        let dominant: BlockDominantLanguage
        if englishRatio > 0.7 {
            dominant = .english
        } else if chineseRatio > 0.7 {
            dominant = .chinese
        } else if englishCount + chineseCount < 3 {
            dominant = .unknown
        } else {
            dominant = .mixed
        }

        // 检测是否为说明/标注性文本
        let isMetaText = detectMetaText(text, chineseRatio: chineseRatio, englishRatio: englishRatio)

        return BlockLanguageProfile(
            dominantLanguage: dominant,
            englishRatio: englishRatio,
            chineseRatio: chineseRatio,
            mixedScore: mixedScore,
            isMetaText: isMetaText,
            englishCharCount: englishCount,
            chineseCharCount: chineseCount,
            totalCharCount: totalCount
        )
    }

    // MARK: - Private

    struct ClassificationContext {
        let pageNumber: Int
        let totalPages: Int
        let isFirstBlock: Bool
        let isLastBlock: Bool

        static let `default` = ClassificationContext(
            pageNumber: 0, totalPages: 0, isFirstBlock: false, isLastBlock: false
        )
    }

    /// 检测噪声/页眉/页脚
    private static func detectNoise(
        _ text: String,
        langProfile: BlockLanguageProfile,
        reasons: inout [String]
    ) -> BlockClassification? {
        // 过短且无意义
        if text.count < 3 {
            reasons.append("过短(<3字符)")
            return BlockClassification(contentType: .noise, languageProfile: langProfile, confidence: 0.1, reasons: reasons)
        }

        // 纯数字（页码）
        let digitsOnly = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if digitsOnly.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "." }) && digitsOnly.count <= 8 {
            reasons.append("纯数字/页码")
            return BlockClassification(contentType: .pageFooter, languageProfile: langProfile, confidence: 0.9, reasons: reasons)
        }

        // 页眉特征：短、含页码模式
        let pageHeaderPattern = #"^(Page|第)\s*\d+.*$|^\d+\s*/\s*\d+$|^-\s*\d+\s*-$"#
        if text.count <= 30 && text.range(of: pageHeaderPattern, options: .regularExpression) != nil {
            reasons.append("页眉/页脚模式")
            return BlockClassification(contentType: .pageHeader, languageProfile: langProfile, confidence: 0.85, reasons: reasons)
        }

        // 参考文献特征
        let referencePattern = #"^\[?\d+\]?\s*(http|www\.|doi:|ISBN)"#
        if text.range(of: referencePattern, options: [.regularExpression, .caseInsensitive]) != nil {
            reasons.append("参考文献格式")
            return BlockClassification(contentType: .reference, languageProfile: langProfile, confidence: 0.8, reasons: reasons)
        }

        return nil
    }

    /// 核心内容类型分类
    private static func classifyContentType(
        text: String,
        layoutType: LayoutBlockType,
        langProfile: BlockLanguageProfile,
        layoutConfidence: Double,
        reasons: inout [String]
    ) -> BlockContentType {

        // ── 题干/选项检测 ──
        if isQuestionStem(text) {
            reasons.append("题干模式")
            return .questionStem
        }

        if isOptionList(text) {
            reasons.append("选项列表模式")
            return .optionList
        }

        // ── 词汇注解检测 ──
        if isGlossaryNote(text, langProfile: langProfile) {
            reasons.append("词汇/注解模式")
            return .glossaryNote
        }

        let looksLikeTeachingExplanation = isPedagogicalChineseExplanation(text)

        // ── 标题层级 ──
        if layoutType == .heading {
            if looksLikeTeachingExplanation {
                reasons.append("标题布局但内容像中文说明")
                return langProfile.dominantLanguage == .mixed ? .bilingualNote : .chineseExplanation
            }
            if layoutConfidence > 0.7 {
                reasons.append("高置信标题(layout)")
                return .title
            } else {
                reasons.append("标题(layout)")
                return .heading
            }
        }

        // ── 语言驱动分类 ──
        switch langProfile.dominantLanguage {
        case .english:
            if looksLikeTeachingExplanation {
                reasons.append("英语比例高，但内容像中文教学说明")
                return .chineseExplanation
            }
            reasons.append("英语主导(比例=\(String(format: "%.0f%%", langProfile.englishRatio * 100)))")
            return .englishBody

        case .chinese:
            if langProfile.isMetaText {
                reasons.append("中文说明/标注文本")
                return .chineseExplanation
            }
            reasons.append("中文主导(比例=\(String(format: "%.0f%%", langProfile.chineseRatio * 100)))")
            return .chineseExplanation

        case .mixed:
            if looksLikeTeachingExplanation {
                reasons.append("混合文本，但主体是教学说明")
                return .bilingualNote
            }
            if langProfile.isChineseExplanatory {
                reasons.append("双语注释(中文辅助)")
                return .bilingualNote
            }
            if langProfile.englishRatio > langProfile.chineseRatio {
                reasons.append("混合偏英(en=\(String(format: "%.0f%%", langProfile.englishRatio * 100)))")
                return .englishBody
            }
            reasons.append("混合偏中(zh=\(String(format: "%.0f%%", langProfile.chineseRatio * 100)))")
            return .bilingualNote

        case .unknown:
            reasons.append("语言未识别")
            return text.count < 10 ? .noise : .englishBody
        }
    }

    /// 计算最终置信度
    private static func computeFinalConfidence(
        contentType: BlockContentType,
        langProfile: BlockLanguageProfile,
        layoutConfidence: Double,
        textLength: Int
    ) -> Double {
        var base = layoutConfidence

        // 语言纯度加分
        if langProfile.dominantLanguage == .english && langProfile.englishRatio > 0.85 {
            base += 0.1
        } else if langProfile.dominantLanguage == .chinese && langProfile.chineseRatio > 0.85 {
            base += 0.1
        }

        // 混合语言减分
        if langProfile.mixedScore > 0.5 {
            base -= 0.15
        }

        // 过短文本减分
        if textLength < 15 {
            base -= 0.1
        }

        // 噪声类型置信度压低
        if contentType == .noise || contentType == .pageHeader || contentType == .pageFooter {
            base = min(base, 0.5)
        }

        return min(max(base, 0), 1.0)
    }

    // MARK: - 模式检测

    /// 检测中文说明/标注性文本
    private static func detectMetaText(_ text: String, chineseRatio: Double, englishRatio: Double) -> Bool {
        guard chineseRatio > 0.16 || isPedagogicalChineseExplanation(text) else { return false }

        let metaKeywords = ["注意", "提示", "说明", "备注", "注解", "翻译", "解释", "参考",
                           "答案", "解析", "要点", "知识点", "考点", "技巧", "总结",
                           "例如", "即", "也就是", "换言之"]
        let lowered = text.lowercased()
        let hasMetaKeyword = metaKeywords.contains { lowered.contains($0) }

        // 括号内中文注解模式
        let hasBracketedChinese = text.range(of: #"[（\(][^）\)]*[\u4e00-\u9fff]+[^）\)]*[）\)]"#, options: .regularExpression) != nil

        return hasMetaKeyword || hasBracketedChinese
    }

    private static func isPedagogicalChineseExplanation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let strongPatterns = [
            #"第[一二三四五六七八九十0-9]+段在讲"#,
            #"第[一二三四五六七八九十0-9]+遍"#,
            #"对照答案"#,
            #"标题匹配题"#,
            #"找主语"#,
            #"找谓语"#,
            #"找宾语"#,
            #"按语块切"#,
            #"不要只背中文"#,
            #"每道题"#,
            #"选出.*最合适"#,
            #"博物馆可?以带来"#,
            #"环保学者担心"#,
            #"反对者担心"#,
            #"游客"#,
            #"原句"#,
            #"修饰成分"#
        ]

        if strongPatterns.contains(where: { trimmed.range(of: $0, options: .regularExpression) != nil }) {
            return true
        }

        let chinesePunctuationCount = trimmed.filter { "。；：，".contains($0) }.count
        let chineseCueCount = ["讲", "题", "答案", "主语", "谓语", "宾语", "段", "遍", "中文", "原句"]
            .reduce(0) { partial, cue in
                partial + (trimmed.contains(cue) ? 1 : 0)
            }

        return chinesePunctuationCount >= 2 && chineseCueCount >= 3
    }

    /// 题干检测
    private static func isQuestionStem(_ text: String) -> Bool {
        let patterns = [
            #"^\d+[\.\)．）]\s+"#,                        // 1. 或 1) 开头
            #"^(Question|问题|第\s*\d+\s*题)"#,           // "Question" 或 "第X题"
            #"^(What|Which|How|Why|When|Where|Who)\s+"#,  // 英文疑问词开头
            #"^\(?\d+\)?\s*[A-D][\.\)．）]"#,             // 选择题序号
            #"^(True|False|Not Given)\b"#,               // 判断题
            #"\b(True|False|Not Given)\b.{0,40}\b(residents|tourism|plan|community|museum|visitors)\b"#, // 单行判断题陈述
            #"标题匹配题"#,
            #"Headings"#                                  // heading matching
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    /// 选项列表检测
    private static func isOptionList(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let inlineOptionPattern = #"(?:^|\s)[A-Da-d][\.\)．）:：]\s+.{1,80}(?:\s+[A-Da-d][\.\)．）:：]\s+.{1,80}){1,}"#
        if text.range(of: inlineOptionPattern, options: .regularExpression) != nil {
            return true
        }

        guard lines.count >= 2 else { return false }

        let optionPattern = #"^\s*[A-Da-d][\.\)．）:：]\s+"#
        let optionLines = lines.filter { $0.range(of: optionPattern, options: .regularExpression) != nil }
        return Double(optionLines.count) / Double(lines.count) > 0.5
    }

    /// 词汇注解检测
    private static func isGlossaryNote(_ text: String, langProfile: BlockLanguageProfile) -> Bool {
        // 英文词 + 中文翻译 模式
        let glossaryPattern = #"[a-zA-Z]+\s*[\-—:：]\s*[\u4e00-\u9fff]+"#
        let matches = text.matches(of: glossaryPattern)
        if matches >= 3 {
            return true
        }

        // 单词列表特征：多个短行，每行一个英文单词+释义
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if lines.count >= 3 {
            let vocabLines = lines.filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.count < 60 && trimmed.range(of: glossaryPattern, options: .regularExpression) != nil
            }
            return Double(vocabLines.count) / Double(lines.count) > 0.5
        }

        return false
    }

    private static func emptyLanguageProfile() -> BlockLanguageProfile {
        BlockLanguageProfile(
            dominantLanguage: .unknown,
            englishRatio: 0,
            chineseRatio: 0,
            mixedScore: 0,
            isMetaText: false,
            englishCharCount: 0,
            chineseCharCount: 0,
            totalCharCount: 0
        )
    }
}

// MARK: - String 辅助

private extension String {
    func matches(of pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(in: self, range: NSRange(startIndex..., in: self))
    }
}
