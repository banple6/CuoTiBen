"""
PP-StructureV3 版面标签 → NormalizedBlockType 映射

PP-StructureV3 layout_parsing_result 中的 label 典型值:
  text, title, figure, figure_caption, table, table_caption,
  header, footer, reference, equation, seal, ...

我们将这些映射到 iOS 合约中的 13 个 NormalizedBlockType。
"""

from __future__ import annotations

import re

from app.utils.language_detector import analyze_language

# PP-StructureV3 label → NormalizedBlockType rawValue
_LABEL_MAP: dict[str, str] = {
    # 标题类
    "title":            "title",
    "section_title":    "heading",
    # 正文类 — 实际分类由语言分析决定
    "text":             "_auto_",
    "paragraph":        "_auto_",
    # 问答类
    "question":         "question_stem",
    "answer":           "english_body",
    # 列表
    "list":             "option_list",
    # 表格/图注
    "table":            "reference",
    "table_caption":    "reference",
    "figure":           "noise",
    "figure_caption":   "reference",
    # 公式
    "equation":         "reference",
    # 页眉页脚
    "header":           "page_header",
    "footer":           "page_footer",
    "page_header":      "page_header",
    "page_footer":      "page_footer",
    # 引用
    "reference":        "reference",
    "footnote":         "reference",
    # 印章/噪声
    "seal":             "noise",
    "watermark":        "noise",
}

_QUESTION_PATTERNS = (
    r"^\s*(\d{1,2}|[A-D])[.)、:：]\s+",
    r"\b(which of the following|what does .* mean|what can be inferred|according to the passage|the author (?:suggests|implies|believes)|the purpose of the passage|main idea)\b",
    r"^\s*[A-D][.)]\s+",
)

_ANSWER_KEY_PATTERNS = (
    r"(答案|参考答案|answer key|keys? to the questions?|解析)",
    r"^\s*(\d{1,2}[.)、:：]\s*[A-D]|[A-D][.)]\s*[\u4e00-\u9fffA-Za-z])",
    r"\b(correct answer|best answer)\b",
)

_VOCAB_PATTERNS = (
    r"(词汇|短语|搭配|vocabulary|glossary|phrase bank|word bank|词义|释义)",
    r"^[A-Za-z][A-Za-z -]{1,30}\s*[:：-]\s*[\u4e00-\u9fffA-Za-z]",
)

_META_PATTERNS = (
    r"(解题|技巧|策略|提示|注意|思路|定位|题干|先看题|阅读理解|做题|分析)",
    r"(注意事项|命题点|考点|易错|陷阱|总结|说明)",
)


def _matches_any(text: str, patterns: tuple[str, ...]) -> bool:
    lower = text.lower()
    return any(re.search(pattern, lower, re.IGNORECASE) for pattern in patterns)


def _infer_zone_role(
    label_lower: str,
    block_type: str,
    text: str,
    lang_info: dict,
) -> str:
    if block_type in {"noise", "page_header", "page_footer", "reference"}:
        return "unknown"

    if _matches_any(text, _ANSWER_KEY_PATTERNS):
        return "answer_key"

    if block_type in {"question_stem", "option_list"} or _matches_any(text, _QUESTION_PATTERNS):
        return "question"

    if block_type == "glossary" or _matches_any(text, _VOCAB_PATTERNS):
        return "vocabulary_support"

    if label_lower in {"header", "footer", "page_header", "page_footer"}:
        return "unknown"

    if lang_info["is_meta_text"] or _matches_any(text, _META_PATTERNS):
        return "meta_instruction"

    if block_type in {"title", "heading", "subheading", "english_body"}:
        return "passage"

    if lang_info["dominant"] == "en" and lang_info["english_ratio"] >= 0.45:
        return "passage"

    if lang_info["dominant"] in {"zh", "mixed"}:
        return "meta_instruction"

    return "unknown"


def classify_block(
    label: str,
    text: str,
    depth: int = 0,
) -> tuple[str, str, str, float]:
    """
    返回 (block_type, zone_role, language, confidence)
    """
    label_lower = label.lower().strip()
    mapped = _LABEL_MAP.get(label_lower, "_auto_")

    lang_info = analyze_language(text)
    lang = lang_info["dominant"]          # "en"/"zh"/"mixed"/"unknown"
    en_ratio = lang_info["english_ratio"]
    is_meta = lang_info["is_meta_text"]

    # 自动分类: 根据语言内容决定
    if mapped == "_auto_":
        if is_meta and lang_info["chinese_ratio"] > 0.5:
            mapped = "chinese_explanation"
        elif lang_info["is_contaminated"]:
            mapped = "bilingual_note"
        elif en_ratio > 0.6:
            mapped = "english_body"
        elif lang_info["chinese_ratio"] > 0.6:
            mapped = "chinese_explanation"
        else:
            mapped = "bilingual_note"

    # 标题层级: depth>0 的 title → heading/subheading
    if mapped == "title" and depth > 0:
        mapped = "heading" if depth == 1 else "subheading"

    # 置信度: layout 结果自身有 score, 这里给一个默认
    confidence = 0.75
    if mapped in ("noise", "page_header", "page_footer"):
        confidence = 0.4
    elif mapped in ("title", "heading"):
        confidence = 0.85

    zone_role = _infer_zone_role(label_lower, mapped, text, lang_info)

    # 答案区通常不应该再伪装成正文
    if zone_role == "answer_key" and mapped == "english_body" and lang_info["chinese_ratio"] > 0.2:
        confidence = min(confidence, 0.68)

    return mapped, zone_role, lang, confidence
