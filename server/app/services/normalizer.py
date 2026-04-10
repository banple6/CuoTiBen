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

    # ── 诊断日志: 记录原始响应结构 ──
    raw_top_keys = list(raw.keys()) if isinstance(raw, dict) else []
    logger.info(
        "归一化开始  doc_id=%s  raw top_keys=%s",
        document_id, raw_top_keys,
    )

    # 提取页面列表 — 适配不同版本的字段名，并记录命中的 key 路径
    _pages_raw_source = "none"
    pages_raw = None

    _result_obj = raw.get("result", {})
    if isinstance(_result_obj, dict):
        for _candidate_key in ("parsing_result", "layoutParsingResults"):
            _candidate = _result_obj.get(_candidate_key)
            if _candidate:
                pages_raw = _candidate
                _pages_raw_source = f"result.{_candidate_key}"
                break
    if pages_raw is None:
        for _candidate_key in ("parsing_result", "layoutParsingResults"):
            _candidate = raw.get(_candidate_key)
            if _candidate:
                pages_raw = _candidate
                _pages_raw_source = _candidate_key
                break
    if pages_raw is None and isinstance(_result_obj, list):
        pages_raw = _result_obj
        _pages_raw_source = "result (list)"
    if pages_raw is None:
        pages_raw = []
        _pages_raw_source = "none (all paths returned empty)"

    if isinstance(pages_raw, dict):
        pages_raw = [pages_raw]
    if not isinstance(pages_raw, list):
        logger.warning(
            "归一化: pages_raw 类型异常  type=%s  source=%s  doc_id=%s",
            type(pages_raw).__name__, _pages_raw_source, document_id,
        )
        pages_raw = []

    logger.info(
        "归一化页面提取  source=%s  page_count=%d  doc_id=%s",
        _pages_raw_source, len(pages_raw), document_id,
    )

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

        logger.info(
            "归一化 page=%d  raw_layout_count=%d  page_keys=%s  doc_id=%s",
            page_num, len(layouts),
            list(page_raw.keys()) if isinstance(page_raw, dict) else "non-dict",
            document_id,
        )

        page_block_ids: list[str] = []
        skipped_empty = 0

        for layout_idx, layout in enumerate(layouts):
            label = (
                layout.get("layout_label")
                or layout.get("label")
                or layout.get("type", "text")
            )

            # 适配多种 PP-StructureV3 版本的文本字段
            text = (
                layout.get("layout_text")
                or layout.get("text")
                or layout.get("content")
                or layout.get("rec_text")
                or layout.get("words")
                or ""
            )
            # sub_layouts 中可能藏着文本
            if not text.strip() and isinstance(layout.get("sub_layouts"), list):
                sub_texts = []
                for sub in layout["sub_layouts"]:
                    st = (
                        sub.get("layout_text")
                        or sub.get("text")
                        or sub.get("content")
                        or sub.get("rec_text")
                        or ""
                    )
                    if st.strip():
                        sub_texts.append(st.strip())
                text = "\n".join(sub_texts)

            # 跳过空文本
            if not text.strip():
                skipped_empty += 1
                # 首个被跳过的 layout 记录其 keys 帮助诊断
                if skipped_empty == 1 and isinstance(layout, dict):
                    logger.info(
                        "归一化 page=%d 首个空文本 layout  keys=%s  label=%s  doc_id=%s",
                        page_num, list(layout.keys()), label, document_id,
                    )
                continue

            bbox_raw = (
                layout.get("layout_bbox")
                or layout.get("bbox")
                or layout.get("layout_location")
                or [0, 0, 0, 0]
            )
            # PP-StructureV3 使用 [x1,y1,x2,y2]
            if isinstance(bbox_raw, list) and len(bbox_raw) == 4:
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

        # 每页统计
        if skipped_empty > 0:
            logger.info(
                "归一化 page=%d  生成blocks=%d  跳过空文本layout=%d/%d  doc_id=%s",
                page_num, len(page_block_ids), skipped_empty, len(layouts), document_id,
            )

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
        "归一化完成: %d页 %d块 %d段落 %d候选  耗时=%dms  doc_id=%s",
        len(all_pages), len(all_blocks), len(paragraphs),
        len(structure_candidates), elapsed_ms, document_id,
    )

    # ── 关键警告: blocks=0 详细原因诊断 ──
    if len(all_blocks) == 0:
        # 统计所有页的原始 layout 总数
        total_raw_layouts = 0
        for pr in pages_raw:
            if isinstance(pr, dict):
                for lk in ("layouts", "layout_parsing_result", "layoutElements"):
                    lv = pr.get(lk)
                    if isinstance(lv, list):
                        total_raw_layouts += len(lv)
                        break

        logger.warning(
            "❗归一化产生 0 个 blocks!  "
            "pages_raw_source=%s  pages_raw_count=%d  total_raw_layouts=%d  "
            "raw_top_keys=%s  doc_id=%s",
            _pages_raw_source, len(pages_raw), total_raw_layouts,
            raw_top_keys, document_id,
        )
        # dump 第一页的 keys
        if pages_raw and isinstance(pages_raw[0], dict):
            logger.warning(
                "❗归一化 blocks=0: 第一页 keys=%s  doc_id=%s",
                list(pages_raw[0].keys()), document_id,
            )
            # dump 第一个 layout 的 keys 以诊断文本字段名
            for lk in ("layouts", "layout_parsing_result", "layoutElements"):
                first_layouts = pages_raw[0].get(lk)
                if isinstance(first_layouts, list) and first_layouts:
                    first_layout = first_layouts[0]
                    if isinstance(first_layout, dict):
                        logger.warning(
                            "❗归一化 blocks=0: 第一个 layout[%s] keys=%s  sample_values=%s  doc_id=%s",
                            lk,
                            list(first_layout.keys()),
                            {k: str(v)[:80] for k, v in list(first_layout.items())[:6]},
                            document_id,
                        )
                    break

    return doc
