"""
将连续块合并为段落
"""

from __future__ import annotations

import re
import uuid

from app.models.normalized_document import NormalizedBlock, NormalizedParagraph

_ZONE_PRIORITY = {
    "answer_key": 5,
    "question": 4,
    "vocabulary_support": 3,
    "meta_instruction": 2,
    "passage": 1,
    "unknown": 0,
}


def build_paragraphs(blocks: list[NormalizedBlock]) -> list[NormalizedParagraph]:
    """
    基于 paragraph_start / paragraph_end 标记或按页分组将 blocks 合并为段落。
    """
    if not blocks:
        return []

    paragraphs: list[NormalizedParagraph] = []
    current_ids: list[str] = []
    current_texts: list[str] = []
    current_lang = "unknown"
    current_zone_role = "unknown"
    start_page = 1
    current_page = 1
    order = 0
    previous_block: NormalizedBlock | None = None

    for blk in blocks:
        # 噪声块不进入段落
        if blk.block_type in ("noise", "page_header", "page_footer"):
            continue

        # 开始新段落条件
        zone_changed = current_ids and blk.zone_role != current_zone_role
        should_start_new = (
            not current_ids
            or zone_changed
            or _should_break_paragraph(previous_block, blk)
        )

        if should_start_new:
            # 先提交上一个段落
            if current_ids:
                paragraphs.append(_make_paragraph(
                    current_ids, current_texts, current_lang, current_zone_role,
                    start_page, current_page, order,
                ))
                order += 1
            current_ids = [blk.id]
            current_texts = [blk.text]
            current_lang = blk.language
            current_zone_role = blk.zone_role
            start_page = blk.page
            current_page = blk.page
        else:
            current_ids.append(blk.id)
            current_texts.append(blk.text)
            current_page = blk.page

        previous_block = blk

    # 剩余块
    if current_ids:
        paragraphs.append(_make_paragraph(
            current_ids, current_texts, current_lang, current_zone_role,
            start_page, current_page, order,
        ))

    return paragraphs


def _make_paragraph(
    ids: list[str],
    texts: list[str],
    lang: str,
    zone_role: str,
    start_page: int,
    end_page: int,
    order: int,
) -> NormalizedParagraph:
    return NormalizedParagraph(
        id=f"para-{uuid.uuid4().hex[:12]}",
        block_ids=ids,
        page=start_page,
        end_page=end_page,
        text="\n".join(texts),
        language=lang,
        zone_role=zone_role,
        cross_page=(start_page != end_page),
        order=order,
    )


def _should_break_paragraph(previous: NormalizedBlock | None, current: NormalizedBlock) -> bool:
    if previous is None:
        return False

    if previous.zone_role != current.zone_role:
        return True

    prev_text = previous.text.strip()
    curr_text = current.text.strip()
    if not prev_text or not curr_text:
        return True

    if current.zone_role != "passage":
        return True

    if re.match(r"^\s*([A-D][.)]|[0-9]{1,2}[.)、:：])", curr_text):
        return True

    transition_starts = (
        "however", "but", "yet", "meanwhile", "moreover", "furthermore",
        "in conclusion", "overall", "therefore", "thus",
    )
    if curr_text.lower().startswith(transition_starts):
        return True

    if prev_text.endswith((".", "?", "!", "。", "？", "！")):
        return True

    if curr_text[:1].islower():
        return False

    if curr_text.lower().startswith(("which ", "that ", "who ", "whose ", "to ", "and ", "or ")):
        return False

    if previous.page != current.page and not prev_text.endswith((".", "?", "!")):
        return False

    return True
