import Foundation
import UIKit

// MARK: - 版面块分组模型

/// 版面块类型：标题 或 正文段落
enum LayoutBlockType: String {
    case heading = "heading"
    case body = "body"
}

/// 一行文本及其字体元信息
struct LayoutLine {
    let text: String
    let fontSize: CGFloat   // 0 = 未知
    let isBold: Bool
    let lineIndex: Int

    var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isEmpty: Bool { trimmed.isEmpty }
    var charCount: Int { trimmed.count }
}

/// 一个版面块（标题块 或 正文段落块）
struct LayoutBlock {
    let type: LayoutBlockType
    let text: String
    let lines: [LayoutLine]
    let confidence: Double
    let reason: String

    /// 块文本是否有效，可用于结构树节点生成
    var isEligibleForTreeNode: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return false }
        guard confidence >= 0.3 else { return false }
        // 排除明显无意义内容：纯数字、纯标点、过短片段
        let letterCount = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return letterCount >= 3
    }
}

/// 版面分组结果
struct LayoutGroupingResult {
    let blocks: [LayoutBlock]
    let rawLineCount: Int
    let decisions: [String]

    /// 所有满足结构树节点要求的块
    var eligibleBlocks: [LayoutBlock] {
        blocks.filter(\.isEligibleForTreeNode)
    }
}

// MARK: - 版面块分组器
/// 将 PDF 页面提取的原始文本 + 字体属性重建为标题块和正文段落块。
///
/// 管线设计：
///   原始行 → 字体分析 → 标题检测 → 正文行合并 → 块列表
///
/// 核心原则：
///   - 空行 = 显式段落分界
///   - 标题 = 独立块，不参与正文段落编号
///   - 连续正文行合并为一个段落
///   - 宁可少分段，不要把一个段落拆碎

enum LayoutBlockGrouper {

    // MARK: - 公开 API

    static func groupBlocks(
        from rawText: String,
        attributedString: NSAttributedString?
    ) -> LayoutGroupingResult {
        let lines = extractLines(from: rawText, attributedString: attributedString)
        guard !lines.isEmpty else {
            return LayoutGroupingResult(blocks: [], rawLineCount: 0, decisions: [])
        }

        let bodyFontSize = estimateBodyFontSize(lines: lines)
        let bodyIsBoldMajority = isBodyMajorityBold(lines: lines)

        var blocks: [LayoutBlock] = []
        var decisions: [String] = []
        var currentBodyLines: [LayoutLine] = []

        func flushBodyBlock() {
            guard !currentBodyLines.isEmpty else { return }
            let merged = currentBodyLines
                .map(\.trimmed)
                .joined(separator: " ")
            let normalized = collapseWhitespace(merged)
            guard !normalized.isEmpty else {
                currentBodyLines.removeAll()
                return
            }
            let firstIdx = currentBodyLines.first!.lineIndex
            let lastIdx = currentBodyLines.last!.lineIndex

            // 段落过长保护：超过 3000 字符时按行边界分割
            if normalized.count > 3000 {
                var subGroup: [LayoutLine] = []
                var subText = ""
                for line in currentBodyLines {
                    let lineText = line.trimmed
                    if !subText.isEmpty && (subText.count + lineText.count + 1) > 2500 {
                        let subNorm = collapseWhitespace(subText)
                        if !subNorm.isEmpty {
                            blocks.append(LayoutBlock(
                                type: .body,
                                text: subNorm,
                                lines: subGroup,
                                confidence: 0.75,
                                reason: "长段分割(行\(subGroup.first?.lineIndex ?? 0)-\(subGroup.last?.lineIndex ?? 0))"
                            ))
                        }
                        subGroup = []
                        subText = ""
                    }
                    subGroup.append(line)
                    subText += (subText.isEmpty ? "" : " ") + lineText
                }
                if !subText.isEmpty {
                    let subNorm = collapseWhitespace(subText)
                    if !subNorm.isEmpty {
                        blocks.append(LayoutBlock(
                            type: .body,
                            text: subNorm,
                            lines: subGroup,
                            confidence: 0.75,
                            reason: "长段分割(行\(subGroup.first?.lineIndex ?? 0)-\(subGroup.last?.lineIndex ?? 0))"
                        ))
                    }
                }
                decisions.append("行\(firstIdx)-\(lastIdx): 过长段落(\(normalized.count)字符) 已分割")
            } else {
                blocks.append(LayoutBlock(
                    type: .body,
                    text: normalized,
                    lines: currentBodyLines,
                    confidence: 0.85,
                    reason: "合并\(currentBodyLines.count)行正文(行\(firstIdx)-\(lastIdx))"
                ))
                decisions.append("行\(firstIdx)-\(lastIdx): 正文段落 (合并\(currentBodyLines.count)行)")
            }
            currentBodyLines.removeAll()
        }

        for (idx, line) in lines.enumerated() {
            // 空行 = 显式段落分界
            if line.isEmpty {
                flushBodyBlock()
                continue
            }

            let blankAbove = idx == 0 || lines[idx - 1].isEmpty
            let blankBelow = idx == lines.count - 1 || lines[idx + 1].isEmpty

            let (isHeading, confidence, reason) = classifyLine(
                line,
                bodyFontSize: bodyFontSize,
                bodyIsBoldMajority: bodyIsBoldMajority,
                blankAbove: blankAbove,
                blankBelow: blankBelow,
                allLines: lines
            )

            if isHeading {
                flushBodyBlock()
                blocks.append(LayoutBlock(
                    type: .heading,
                    text: line.trimmed,
                    lines: [line],
                    confidence: confidence,
                    reason: reason
                ))
                decisions.append("行\(idx): 标题 (\(reason))")
            } else {
                // 检查是否需要在此行之前断开段落
                if shouldBreakParagraphBefore(
                    nextLine: line,
                    currentLines: currentBodyLines,
                    bodyFontSize: bodyFontSize
                ) {
                    flushBodyBlock()
                }
                currentBodyLines.append(line)
            }
        }

        flushBodyBlock()

        return LayoutGroupingResult(
            blocks: blocks,
            rawLineCount: lines.count,
            decisions: decisions
        )
    }

    // MARK: - 行提取 + 字体信息

    private static func extractLines(
        from rawText: String,
        attributedString: NSAttributedString?
    ) -> [LayoutLine] {
        let rawLines = rawText.components(separatedBy: "\n")

        guard let attrStr = attributedString else {
            return rawLines.enumerated().map { idx, text in
                LayoutLine(text: text, fontSize: 0, isBold: false, lineIndex: idx)
            }
        }

        // 从 attributedString 提取每行的主导字体
        let attrLines = attrStr.string.components(separatedBy: "\n")
        var fontInfo: [(CGFloat, Bool)] = []
        var offset = 0

        for attrLine in attrLines {
            let lineLen = (attrLine as NSString).length
            if lineLen == 0 || offset + lineLen > attrStr.length {
                fontInfo.append((0, false))
                offset += lineLen + 1
                continue
            }

            let range = NSRange(location: offset, length: lineLen)
            var maxSpan = 0
            var dominantSize: CGFloat = 0
            var dominantBold = false

            attrStr.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
                if let font = value as? UIFont, attrRange.length > maxSpan {
                    maxSpan = attrRange.length
                    dominantSize = font.pointSize
                    dominantBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
                }
            }

            fontInfo.append((dominantSize, dominantBold))
            offset += lineLen + 1
        }

        return rawLines.enumerated().map { idx, text in
            let (size, bold) = idx < fontInfo.count ? fontInfo[idx] : (0 as CGFloat, false)
            return LayoutLine(text: text, fontSize: size, isBold: bold, lineIndex: idx)
        }
    }

    // MARK: - 正文字体基线估算

    private static func estimateBodyFontSize(lines: [LayoutLine]) -> CGFloat {
        let sizes = lines
            .filter { !$0.isEmpty && $0.fontSize > 0 }
            .map { round($0.fontSize * 10) / 10 }
        guard !sizes.isEmpty else { return 0 }
        // 出现次数最多的字号 = 正文字号
        let freq = Dictionary(grouping: sizes, by: { $0 })
        return freq.max(by: { $0.value.count < $1.value.count })?.key ?? 0
    }

    private static func isBodyMajorityBold(lines: [LayoutLine]) -> Bool {
        let nonEmpty = lines.filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty else { return false }
        let boldCount = nonEmpty.filter(\.isBold).count
        return Double(boldCount) / Double(nonEmpty.count) > 0.5
    }

    // MARK: - 标题分类器

    private static func classifyLine(
        _ line: LayoutLine,
        bodyFontSize: CGFloat,
        bodyIsBoldMajority: Bool,
        blankAbove: Bool,
        blankBelow: Bool,
        allLines: [LayoutLine]
    ) -> (isHeading: Bool, confidence: Double, reason: String) {
        let text = line.trimmed
        guard !text.isEmpty else { return (false, 0, "空行") }

        var score: Double = 0
        var reasons: [String] = []

        // ── 正面信号 ──

        // (1) 字号大于正文
        if bodyFontSize > 0 && line.fontSize > 0 && line.fontSize > bodyFontSize * 1.15 {
            score += 2.5
            reasons.append("字号大(\(fmt(line.fontSize))>\(fmt(bodyFontSize)))")
        }

        // (2) 粗体（仅当正文非普遍粗体时有效）
        if line.isBold && !bodyIsBoldMajority {
            score += 1.5
            reasons.append("粗体")
        }

        // (3) 短行
        if text.count <= 80 {
            score += 0.6
            if text.count <= 50 {
                score += 0.4
            }
            reasons.append("短行\(text.count)字符")
        }

        // (4) 标题型大写 (Title Case)
        if isTitleCasePattern(text) {
            score += 1.2
            reasons.append("标题大写模式")
        }

        // (5) 全大写行（短）
        if text.count <= 60 && text == text.uppercased() && text.rangeOfCharacter(from: .letters) != nil {
            score += 1.0
            reasons.append("全大写")
        }

        // (6) 无末尾句子标点
        let last = text.last
        if last != "." && last != "," && last != ";" && last != ":" {
            score += 0.4
            reasons.append("无末尾标点")
        }

        // (7) 上下空行隔离
        if blankAbove && blankBelow {
            score += 1.5
            reasons.append("上下空行")
        } else if blankAbove {
            score += 0.8
            reasons.append("上方空行")
        }

        // ── 负面信号 ──

        // (8) 过长：不像标题
        if text.count > 120 {
            score -= 2.5
            reasons.append("过长(-2.5)")
        } else if text.count > 80 {
            score -= 1.0
            reasons.append("偏长(-1)")
        }

        // (9) 小写开头：连续正文延续
        if let first = text.first, first.isLowercase {
            score -= 2.5
            reasons.append("小写开头(-2.5)")
        }

        // (10) 末尾续行标点
        if last == "," || last == ";" {
            score -= 1.5
            reasons.append("续行标点(-1.5)")
        }

        // (11) 常见正文起始模式（非标题）
        let bodyStarters = ["For ", "In ", "The ", "However,", "Although ", "While ",
                            "But ", "And ", "Moreover,", "Furthermore,", "Additionally,",
                            "Nevertheless,", "Meanwhile,", "Therefore,", "Thus,"]
        if text.count > 80, bodyStarters.contains(where: { text.hasPrefix($0) }) {
            score -= 1.0
            reasons.append("正文起始词(-1)")
        }

        let threshold: Double = 3.0
        let isHeading = score >= threshold
        let confidence = min(max(score / 5.0, 0), 1.0)

        return (isHeading, confidence, reasons.joined(separator: " "))
    }

    // MARK: - 段落断开判定

    /// 判断是否应在下一行之前断开当前段落（不依赖空行的辅助规则）
    private static func shouldBreakParagraphBefore(
        nextLine: LayoutLine,
        currentLines: [LayoutLine],
        bodyFontSize: CGFloat
    ) -> Bool {
        guard let lastLine = currentLines.last else { return false }

        // 字号显著变化 → 新段落
        if bodyFontSize > 0 && lastLine.fontSize > 0 && nextLine.fontSize > 0 {
            let diff = abs(lastLine.fontSize - nextLine.fontSize) / bodyFontSize
            if diff > 0.15 {
                return true
            }
        }

        // 粗体状态变化（一侧粗体，一侧非粗体）→ 可能是新段落
        // 但保守处理：仅当字号也不同时才断开
        // （同字号的粗体变化可能只是行内强调）

        // 显著缩进变化（前导空格差异大）→ 新段落
        let lastIndent = lastLine.text.prefix(while: { $0 == " " || $0 == "\t" }).count
        let nextIndent = nextLine.text.prefix(while: { $0 == " " || $0 == "\t" }).count
        if abs(lastIndent - nextIndent) >= 4 && nextIndent > lastIndent {
            return true
        }

        return false
    }

    // MARK: - Title Case 检测

    private static func isTitleCasePattern(_ text: String) -> Bool {
        let words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard words.count >= 2, words.count <= 20 else { return false }

        let smallWords: Set<String> = [
            "a", "an", "the", "and", "or", "but", "in", "on", "at",
            "to", "for", "of", "with", "by", "from", "as", "is", "that",
            "not", "nor", "so", "yet", "into", "than"
        ]

        var significantCount = 0
        var capitalizedCount = 0

        for (index, word) in words.enumerated() {
            // 跳过中间位置的小词
            if index > 0 && smallWords.contains(word.lowercased()) {
                continue
            }
            significantCount += 1
            if word.first?.isUppercase == true {
                capitalizedCount += 1
            }
        }

        guard significantCount >= 2 else { return false }
        return Double(capitalizedCount) / Double(significantCount) >= 0.75
    }

    // MARK: - 工具

    private static func collapseWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fmt(_ v: CGFloat) -> String {
        String(format: "%.1f", v)
    }
}
