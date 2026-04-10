"""
将连续块合并为段落
"""

from __future__ import annotations

import uuid

from app.models.normalized_document import NormalizedBlock, NormalizedParagraph


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
    start_page = 1
    current_page = 1
    order = 0

    for blk in blocks:
        # 噪声块不进入段落
        if blk.block_type in ("noise", "page_header", "page_footer"):
            continue

        # 开始新段落条件
        if blk.paragraph_start or not current_ids:
            # 先提交上一个段落
            if current_ids:
                paragraphs.append(_make_paragraph(
                    current_ids, current_texts, current_lang,
                    start_page, current_page, order,
                ))
                order += 1
            current_ids = [blk.id]
            current_texts = [blk.text]
            current_lang = blk.language
            start_page = blk.page
            current_page = blk.page
        else:
            current_ids.append(blk.id)
            current_texts.append(blk.text)
            current_page = blk.page

        # 结束当前段落
        if blk.paragraph_end:
            paragraphs.append(_make_paragraph(
                current_ids, current_texts, current_lang,
                start_page, current_page, order,
            ))
            order += 1
            current_ids = []
            current_texts = []

    # 剩余块
    if current_ids:
        paragraphs.append(_make_paragraph(
            current_ids, current_texts, current_lang,
            start_page, current_page, order,
        ))

    return paragraphs


def _make_paragraph(
    ids: list[str],
    texts: list[str],
    lang: str,
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
        cross_page=(start_page != end_page),
        order=order,
    )
