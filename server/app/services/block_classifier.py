"""
PP-StructureV3 版面标签 → NormalizedBlockType 映射

PP-StructureV3 layout_parsing_result 中的 label 典型值:
  text, title, figure, figure_caption, table, table_caption,
  header, footer, reference, equation, seal, ...

我们将这些映射到 iOS 合约中的 13 个 NormalizedBlockType。
"""

from __future__ import annotations

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


def classify_block(
    label: str,
    text: str,
    depth: int = 0,
) -> tuple[str, str, float]:
    """
    返回 (block_type, language, confidence)
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

    return mapped, lang, confidence
