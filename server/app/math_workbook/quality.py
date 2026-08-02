"""Explainable quality flags for formula candidates; never a fake confidence score."""

from __future__ import annotations

import re


def formula_quality_flags(latex: str | None, crop_width: float, crop_height: float) -> list[str]:
    if not latex or not latex.strip():
        return ["latex_non_empty"]

    value = latex.strip()
    flags: list[str] = []
    if value.count("{") != value.count("}") or value.count("[") != value.count("]") or value.count("(") != value.count(")"):
        flags.append("unbalanced_brackets")
    if len(value) > max(350, int(max(crop_width, 1) * max(crop_height, 1) / 180)):
        flags.append("abnormal_length")
    if _has_repeated_subsequence(value):
        flags.append("suspicious_repetition")
    if re.search(r"(?:\\int|\\frac)\{0\}\^\{x\}[^$]{0,80}", value) and value.count("\\int") >= 4:
        flags.append("duplicate_subsequence")
    if re.search(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", value) or "…" in value:
        flags.append("contains_unknown_tokens")
    if crop_width < 12 or crop_height < 12:
        flags.append("crop_too_small")
    return flags


def _has_repeated_subsequence(value: str) -> bool:
    compact = re.sub(r"\s+", "", value)
    for size in (12, 20, 32, 48):
        for index in range(0, max(len(compact) - size * 3 + 1, 0), max(size // 2, 1)):
            part = compact[index:index + size]
            if part and compact.count(part) >= 3:
                return True
    return False
