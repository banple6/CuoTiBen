"""
从标题块 + 段落信息生成 StructureCandidate 列表
"""

from __future__ import annotations

import uuid

from app.models.normalized_document import (
    NormalizedBlock,
    NormalizedParagraph,
    StructureCandidate,
)

_HEADING_TYPES = {"title", "heading", "subheading"}

_DEPTH_MAP = {
    "title": 0,
    "heading": 1,
    "subheading": 2,
}


def build_structure_candidates(
    blocks: list[NormalizedBlock],
    paragraphs: list[NormalizedParagraph],
) -> list[StructureCandidate]:
    """
    为每个标题类块创建一个 heading candidate，
    然后将标题之间的段落归入 section candidate。
    """
    candidates: list[StructureCandidate] = []
    passage_paragraphs = [p for p in paragraphs if p.zone_role == "passage"]
    para_map: dict[str, NormalizedParagraph] = {p.id: p for p in passage_paragraphs}
    # block_id → paragraph_id
    blk_to_para: dict[str, str] = {}
    for p in passage_paragraphs:
        for bid in p.block_ids:
            blk_to_para[bid] = p.id

    passage_blocks = [
        (i, b)
        for i, b in enumerate(blocks)
        if b.zone_role == "passage" and b.block_type not in {"noise", "page_header", "page_footer", "reference"}
    ]
    heading_blocks = [(i, b) for i, b in passage_blocks if b.block_type in _HEADING_TYPES]

    if not heading_blocks and passage_paragraphs:
        paragraph_ids = [p.id for p in passage_paragraphs]
        block_ids = [bid for p in passage_paragraphs for bid in p.block_ids]
        summary_text = " ".join(p.text for p in passage_paragraphs)[:300] or None
        title = (passage_paragraphs[0].text or "Passage").strip()[:80]
        return [
            StructureCandidate(
                id=f"sc-{uuid.uuid4().hex[:12]}",
                parent_id=None,
                depth=0,
                order=0,
                title=title,
                summary=summary_text,
                block_ids=block_ids,
                paragraph_ids=paragraph_ids,
                confidence=0.55,
                candidate_type="section",
            )
        ]

    order = 0
    parent_stack: list[str] = []  # (candidate_id) 栈，按 depth

    for idx, (blk_idx, hblk) in enumerate(heading_blocks):
        depth = _DEPTH_MAP.get(hblk.block_type, 0)

        # 确定 parent
        parent_id = None
        while parent_stack and len(parent_stack) > depth:
            parent_stack.pop()
        if parent_stack:
            parent_id = parent_stack[-1]

        heading_cid = f"sc-{uuid.uuid4().hex[:12]}"

        # heading candidate
        candidates.append(StructureCandidate(
            id=heading_cid,
            parent_id=parent_id,
            depth=depth,
            order=order,
            title=hblk.text.strip()[:200],
            summary=None,
            block_ids=[hblk.id],
            paragraph_ids=[blk_to_para[hblk.id]] if hblk.id in blk_to_para else [],
            confidence=hblk.confidence,
            candidate_type="heading",
        ))
        order += 1
        parent_stack.append(heading_cid)

        # section: 收集此标题到下一标题之间的块
        next_blk_idx = heading_blocks[idx + 1][0] if idx + 1 < len(heading_blocks) else len(blocks)
        section_block_ids = []
        section_para_ids_set: set[str] = set()
        section_text_parts: list[str] = []

        for bi in range(blk_idx + 1, next_blk_idx):
            b = blocks[bi]
            if b.zone_role != "passage" or b.block_type in ("noise", "page_header", "page_footer", "reference"):
                continue
            section_block_ids.append(b.id)
            section_text_parts.append(b.text)
            if b.id in blk_to_para:
                section_para_ids_set.add(blk_to_para[b.id])

        if section_block_ids:
            summary_text = " ".join(section_text_parts)[:300] or None
            candidates.append(StructureCandidate(
                id=f"sc-{uuid.uuid4().hex[:12]}",
                parent_id=heading_cid,
                depth=depth + 1,
                order=order,
                title=hblk.text.strip()[:200],
                summary=summary_text,
                block_ids=section_block_ids,
                paragraph_ids=list(section_para_ids_set),
                confidence=0.6,
                candidate_type="section",
            ))
            order += 1

    return candidates
