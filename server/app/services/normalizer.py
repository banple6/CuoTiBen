"""
核心归一化器 — 将 AI Studio PP-StructureV3 原始 JSON 转换为 NormalizedDocument

PP-StructureV3 layout_parsing_result 典型结构:
{
  "parsing_result": [   // 每页一个元素
    {
      "page_id": 0,
      "page_width": 595.0,
      "page_height": 842.0,
      "layouts": [
        {
          "layout_label": "text",
          "layout_bbox": [x1, y1, x2, y2],
          "layout_text": "...",
          "layout_score": 0.95,
          "sub_layouts": [...]
        },
        ...
      ]
    },
    ...
  ]
}

某些版本也可能使用 "result" 字段。
"""

from __future__ import annotations

import logging
import time
import uuid
from typing import Any

from app.models.normalized_document import (
    BoundingBox,
    DocumentMetadata,
    NormalizedBlock,
    NormalizedDocument,
    NormalizedPage,
)
from app.services.block_classifier import classify_block
from app.services.paragraph_builder import build_paragraphs
from app.services.structure_candidate_builder import build_structure_candidates
from app.utils.language_detector import analyze_language

logger = logging.getLogger(__name__)


def normalize(
    raw: dict[str, Any],
    document_id: str,
    title: str = "",
    file_type: str = "",
) -> NormalizedDocument:
    """
    将 AI Studio PP-StructureV3 原始响应归一化为 NormalizedDocument。
    """
    t0 = time.monotonic()

    # 提取页面列表 — 适配不同版本的字段名
    pages_raw = (
        raw.get("result", {}).get("parsing_result")
        or raw.get("result", {}).get("layoutParsingResults")
        or raw.get("parsing_result")
        or raw.get("layoutParsingResults")
        or raw.get("result", [])
    )

    if isinstance(pages_raw, dict):
        pages_raw = [pages_raw]
    if not isinstance(pages_raw, list):
        pages_raw = []

    all_blocks: list[NormalizedBlock] = []
    all_pages: list[NormalizedPage] = []
    global_order = 0

    for page_idx, page_raw in enumerate(pages_raw):
        page_num = page_raw.get("page_id", page_raw.get("pageId", page_idx)) + 1
        page_w = float(page_raw.get("page_width", page_raw.get("pageWidth", 0)))
        page_h = float(page_raw.get("page_height", page_raw.get("pageHeight", 0)))

        layouts = (
            page_raw.get("layouts")
            or page_raw.get("layout_parsing_result", [])
            or page_raw.get("layoutElements", [])
        )
        if not isinstance(layouts, list):
            layouts = []

        page_block_ids: list[str] = []

        for layout in layouts:
            label = (
                layout.get("layout_label")
                or layout.get("label")
                or layout.get("type", "text")
            )
            text = (
                layout.get("layout_text")
                or layout.get("text", "")
                or ""
            )

            # 跳过空文本
            if not text.strip():
                continue

            bbox_raw = (
                layout.get("layout_bbox")
                or layout.get("bbox")
                or [0, 0, 0, 0]
            )
            # PP-StructureV3 使用 [x1,y1,x2,y2]
            if len(bbox_raw) == 4:
                x1, y1, x2, y2 = [float(v) for v in bbox_raw]
                bbox = BoundingBox(x=x1, y=y1, width=x2 - x1, height=y2 - y1)
            else:
                bbox = BoundingBox()

            score = float(
                layout.get("layout_score")
                or layout.get("score", 0.75)
            )

            block_type, lang, confidence = classify_block(label, text)
            confidence = min(confidence, score)  # 不超过 layout 置信度

            block_id = f"blk-{uuid.uuid4().hex[:12]}"
            block = NormalizedBlock(
                id=block_id,
                page=page_num,
                order=global_order,
                bbox=bbox,
                block_type=block_type,
                sub_type=label if label != block_type else None,
                text=text,
                language=lang,
                confidence=round(confidence, 4),
                paragraph_start=True,
                paragraph_end=True,
                source="pp_structurev3",
            )
            all_blocks.append(block)
            page_block_ids.append(block_id)
            global_order += 1

        all_pages.append(NormalizedPage(
            page=page_num,
            width=page_w,
            height=page_h,
            block_ids=page_block_ids,
        ))

    # 段落合并
    paragraphs = build_paragraphs(all_blocks)

    # 结构候选
    structure_candidates = build_structure_candidates(all_blocks, paragraphs)

    # 全文语言分析
    all_text = " ".join(b.text for b in all_blocks if b.block_type not in ("noise", "page_header", "page_footer"))
    global_lang = analyze_language(all_text)

    elapsed_ms = int((time.monotonic() - t0) * 1000)

    metadata = DocumentMetadata(
        title=title,
        file_type=file_type,
        page_count=len(all_pages),
        total_blocks=len(all_blocks),
        total_paragraphs=len(paragraphs),
        dominant_language=global_lang["dominant"],
        english_ratio=round(global_lang["english_ratio"], 4),
        parse_engine="pp_structurev3",
        parse_version="1.0.0",
        parse_duration_ms=elapsed_ms,
    )

    doc = NormalizedDocument(
        document_id=document_id,
        metadata=metadata,
        pages=all_pages,
        blocks=all_blocks,
        paragraphs=paragraphs,
        structure_candidates=structure_candidates,
    )

    logger.info(
        "归一化完成: %d页 %d块 %d段落 %d候选  耗时=%dms",
        len(all_pages), len(all_blocks), len(paragraphs),
        len(structure_candidates), elapsed_ms,
    )

    return doc
