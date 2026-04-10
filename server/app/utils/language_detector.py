"""
语言检测工具 — Unicode 标量级别分析英/中比例
"""

import re
import unicodedata


def analyze_language(text: str) -> dict:
    """
    返回:
        {
            "dominant": "en" | "zh" | "mixed" | "unknown",
            "english_ratio": float,
            "chinese_ratio": float,
            "mixed_score": float,   # 0=纯单语, 1=完全混合
            "is_meta_text": bool,
            "is_contaminated": bool,
        }
    """
    if not text or not text.strip():
        return _empty()

    en_count = 0
    zh_count = 0
    total = 0
    for ch in text:
        cp = ord(ch)
        if (0x0041 <= cp <= 0x005A) or (0x0061 <= cp <= 0x007A):
            en_count += 1
            total += 1
        elif (0x4E00 <= cp <= 0x9FFF) or (0x3400 <= cp <= 0x4DBF):
            zh_count += 1
            total += 1
        elif not unicodedata.category(ch).startswith(("P", "Z", "S", "N", "C")):
            total += 1

    content = max(en_count + zh_count, 1)
    en_ratio = en_count / content
    zh_ratio = zh_count / content

    if en_count == 0 or zh_count == 0:
        mixed = 0.0
    else:
        mixed = min(min(en_ratio, zh_ratio) / 0.3, 1.0)

    if en_ratio > 0.7:
        dom = "en"
    elif zh_ratio > 0.7:
        dom = "zh"
    elif en_count + zh_count < 3:
        dom = "unknown"
    else:
        dom = "mixed"

    is_meta = _detect_meta(text, zh_ratio)
    is_contaminated = mixed > 0.6 and zh_ratio > 0.25 and en_ratio > 0.25

    return {
        "dominant": dom,
        "english_ratio": round(en_ratio, 4),
        "chinese_ratio": round(zh_ratio, 4),
        "mixed_score": round(mixed, 4),
        "is_meta_text": is_meta,
        "is_contaminated": is_contaminated,
    }


_META_KEYWORDS = (
    "注意", "提示", "说明", "备注", "注解", "翻译", "解释", "参考",
    "答案", "解析", "要点", "知识点", "考点", "技巧", "总结",
    "例如", "即", "也就是", "换言之",
)


def _detect_meta(text: str, zh_ratio: float) -> bool:
    if zh_ratio < 0.3:
        return False
    lower = text.lower()
    if any(kw in lower for kw in _META_KEYWORDS):
        return True
    if re.search(r"[（(][^）)]*[\u4e00-\u9fff]+[^）)]*[）)]", text):
        return True
    return False


def _empty() -> dict:
    return {
        "dominant": "unknown",
        "english_ratio": 0.0,
        "chinese_ratio": 0.0,
        "mixed_score": 0.0,
        "is_meta_text": False,
        "is_contaminated": False,
    }
