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

_RESULT_CONTAINER_KEYS = ("result", "data", "res", "output", "payload")
_PAGE_LIST_KEYS = (
    "parsing_result",
    "layoutParsingResults",
    "pages",
    "page_results",
    "pageResults",
    "results",
)
_LAYOUT_LIST_KEYS = (
    "layouts",
    "layout_parsing_result",
    "layoutElements",
    "parsing_res_list",
    "parsingResList",
    "blocks",
    "elements",
    "items",
)
_PAGE_NUMBER_KEYS = ("page_id", "pageId", "page_index", "pageIndex", "page_no", "pageNo")
_PAGE_WIDTH_KEYS = ("page_width", "pageWidth", "img_w", "imgWidth", "width")
_PAGE_HEIGHT_KEYS = ("page_height", "pageHeight", "img_h", "imgHeight", "height")
_LABEL_KEYS = ("layout_label", "block_label", "label", "type", "category")
_TEXT_KEYS = (
    "layout_text",
    "block_content",
    "text",
    "content",
    "rec_text",
    "words",
    "markdown",
    "html",
    "text_content",
)
_BBOX_KEYS = ("layout_bbox", "block_bbox", "bbox", "layout_location", "box", "coordinate", "coordinates", "points")
_SCORE_KEYS = ("layout_score", "block_score", "score", "confidence")
_NESTED_LAYOUT_CONTAINER_KEYS = ("prunedResult", "pruned_result", "result", "data")
_TEXT_SCAN_SKIP_KEYS = set(
    _PAGE_NUMBER_KEYS
    + _PAGE_WIDTH_KEYS
    + _PAGE_HEIGHT_KEYS
    + _LABEL_KEYS
    + _TEXT_KEYS
    + _BBOX_KEYS
    + _SCORE_KEYS
    + ("sub_layouts", "subLayouts", "order", "index", "block_order", "source")
)


def _iter_dict_candidates(root: Any, max_depth: int = 4):
    queue: list[tuple[str, Any, int]] = [("raw", root, 0)]
    visited: set[int] = set()

    while queue:
        path, node, depth = queue.pop(0)
        if not isinstance(node, dict):
            continue

        node_id = id(node)
        if node_id in visited:
            continue
        visited.add(node_id)

        yield path, node

        if depth >= max_depth:
            continue

        for key in _RESULT_CONTAINER_KEYS:
            nested = node.get(key)
            if isinstance(nested, dict):
                queue.append((f"{path}.{key}", nested, depth + 1))


def _looks_like_block(node: Any) -> bool:
    if not isinstance(node, dict):
        return False
    keys = set(node.keys())
    return bool(
        keys.intersection(set(_TEXT_KEYS) | set(_BBOX_KEYS) | set(_LABEL_KEYS) | {"sub_layouts", "subLayouts"})
    )


def _looks_like_page(node: Any) -> bool:
    if not isinstance(node, dict):
        return False
    keys = set(node.keys())
    return bool(
        keys.intersection(set(_PAGE_NUMBER_KEYS) | set(_LAYOUT_LIST_KEYS) | {"prunedResult", "pruned_result"})
    )


def _coerce_page_list(candidate: Any) -> list[dict[str, Any]] | None:
    if isinstance(candidate, list):
        if not candidate:
            return []
        if all(_looks_like_page(item) for item in candidate if isinstance(item, dict)):
            return [item for item in candidate if isinstance(item, dict)]
        if isinstance(candidate[0], dict) and _looks_like_block(candidate[0]):
            return [{"page_id": 0, "layouts": candidate}]
        return None

    if isinstance(candidate, dict):
        if _looks_like_page(candidate):
            return [candidate]
        values = [value for value in candidate.values() if isinstance(value, dict)]
        if values and all(_looks_like_page(value) for value in values):
            return values

    return None


def _extract_pages_raw(raw: dict[str, Any]) -> tuple[list[dict[str, Any]], str]:
    best_source = "none (all paths returned empty)"

    if isinstance(raw, list):
        coerced = _coerce_page_list(raw)
        if coerced is not None:
            return coerced, "raw (list)"

    for path, container in _iter_dict_candidates(raw):
        coerced_container = _coerce_page_list(container)
        if coerced_container is not None and coerced_container:
            return coerced_container, f"{path} (page-like)"

        for key in _PAGE_LIST_KEYS:
            candidate = container.get(key)
            coerced = _coerce_page_list(candidate)
            if coerced is None:
                continue
            source = f"{path}.{key}"
            if coerced:
                return coerced, source
            if best_source.startswith("none"):
                best_source = source

    return [], best_source


def _coerce_layout_list(candidate: Any) -> list[dict[str, Any]] | None:
    if isinstance(candidate, list):
        if not candidate:
            return []
        dict_items = [item for item in candidate if isinstance(item, dict)]
        if dict_items and all(_looks_like_block(item) or _looks_like_page(item) for item in dict_items):
            return dict_items
        return None

    if isinstance(candidate, dict):
        if _looks_like_block(candidate):
            return [candidate]
        values = [value for value in candidate.values() if isinstance(value, dict)]
        if values and all(_looks_like_block(value) for value in values):
            return values

    return None


def _extract_layouts(page_raw: dict[str, Any]) -> tuple[list[dict[str, Any]], str]:
    queue: list[tuple[str, Any]] = [("page", page_raw)]
    visited: set[int] = set()
    best_source = "none"

    while queue:
        path, node = queue.pop(0)
        if not isinstance(node, dict):
            continue

        node_id = id(node)
        if node_id in visited:
            continue
        visited.add(node_id)

        for key in _LAYOUT_LIST_KEYS:
            candidate = node.get(key)
            coerced = _coerce_layout_list(candidate)
            if coerced is None:
                continue
            source = f"{path}.{key}"
            if coerced:
                return coerced, source
            if best_source == "none":
                best_source = source

        for nested_key in _NESTED_LAYOUT_CONTAINER_KEYS:
            nested = node.get(nested_key)
            if isinstance(nested, dict):
                queue.append((f"{path}.{nested_key}", nested))

    if _looks_like_block(page_raw):
        return [page_raw], "page_as_block"

    return [], best_source


def _extract_string(value: Any) -> str:
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, (int, float)):
        return str(value).strip()
    if isinstance(value, list):
        parts = [_extract_string(item) for item in value]
        return "\n".join(part for part in parts if part).strip()
    if isinstance(value, dict):
        for key in _TEXT_KEYS:
            if key in value:
                text = _extract_string(value.get(key))
                if text:
                    return text
    return ""


def _extract_layout_text(layout: dict[str, Any]) -> tuple[str, str]:
    for key in _TEXT_KEYS:
        if key in layout:
            text = _extract_string(layout.get(key))
            if text:
                return text, key

    for key in ("sub_layouts", "subLayouts"):
        sub_layouts = layout.get(key)
        if isinstance(sub_layouts, list):
            parts = [_extract_layout_text(sub_layout)[0] for sub_layout in sub_layouts if isinstance(sub_layout, dict)]
            text = "\n".join(part for part in parts if part).strip()
            if text:
                return text, key

    label = str(next((layout.get(key) for key in _LABEL_KEYS if layout.get(key)), "")).strip().lower()
    if label and label in layout:
        text = _extract_string(layout.get(label))
        if text:
            return text, label

    for key, value in layout.items():
        if key in _TEXT_SCAN_SKIP_KEYS:
            continue
        text = _extract_string(value)
        if text:
            return text, key

    return "", "none"


def _to_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _parse_bbox(raw_bbox: Any) -> BoundingBox:
    if isinstance(raw_bbox, dict):
        if all(key in raw_bbox for key in ("x", "y", "width", "height")):
            return BoundingBox(
                x=_to_float(raw_bbox.get("x")),
                y=_to_float(raw_bbox.get("y")),
                width=_to_float(raw_bbox.get("width")),
                height=_to_float(raw_bbox.get("height")),
            )
        if all(key in raw_bbox for key in ("x1", "y1", "x2", "y2")):
            x1 = _to_float(raw_bbox.get("x1"))
            y1 = _to_float(raw_bbox.get("y1"))
            x2 = _to_float(raw_bbox.get("x2"))
            y2 = _to_float(raw_bbox.get("y2"))
            return BoundingBox(x=x1, y=y1, width=max(x2 - x1, 0.0), height=max(y2 - y1, 0.0))
        for key in _BBOX_KEYS:
            if key in raw_bbox:
                return _parse_bbox(raw_bbox.get(key))

    if isinstance(raw_bbox, list):
        numeric = [value for value in raw_bbox if isinstance(value, (int, float))]
        if len(numeric) == 4:
            x1, y1, v3, v4 = [float(value) for value in numeric]
            if v3 >= x1 and v4 >= y1:
                return BoundingBox(x=x1, y=y1, width=v3 - x1, height=v4 - y1)
            return BoundingBox(x=x1, y=y1, width=max(v3, 0.0), height=max(v4, 0.0))
        if len(numeric) >= 8 and len(numeric) % 2 == 0:
            xs = [float(numeric[index]) for index in range(0, len(numeric), 2)]
            ys = [float(numeric[index]) for index in range(1, len(numeric), 2)]
            return BoundingBox(x=min(xs), y=min(ys), width=max(xs) - min(xs), height=max(ys) - min(ys))
        if raw_bbox and all(isinstance(item, (list, tuple)) and len(item) >= 2 for item in raw_bbox):
            xs = [_to_float(item[0]) for item in raw_bbox]
            ys = [_to_float(item[1]) for item in raw_bbox]
            return BoundingBox(x=min(xs), y=min(ys), width=max(xs) - min(xs), height=max(ys) - min(ys))

    return BoundingBox()


def _extract_bbox(layout: dict[str, Any]) -> BoundingBox:
    for key in _BBOX_KEYS:
        if key in layout:
            return _parse_bbox(layout.get(key))
    return BoundingBox()


def _extract_label(layout: dict[str, Any]) -> str:
    for key in _LABEL_KEYS:
        value = layout.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return "text"


def _extract_score(layout: dict[str, Any], default: float = 0.75) -> float:
    for key in _SCORE_KEYS:
        if key in layout:
            return _to_float(layout.get(key), default)
    return default


def _extract_page_index(page_raw: dict[str, Any], fallback_index: int) -> int:
    for key in _PAGE_NUMBER_KEYS:
        if key in page_raw:
            try:
                value = int(page_raw.get(key))
                return value + 1 if value == fallback_index or value == fallback_index - 1 else value if value >= 1 else fallback_index + 1
            except (TypeError, ValueError):
                break
    return fallback_index + 1


def _extract_page_size(page_raw: dict[str, Any]) -> tuple[float, float]:
    width = 0.0
    height = 0.0
    for key in _PAGE_WIDTH_KEYS:
        if key in page_raw:
            width = _to_float(page_raw.get(key))
            if width:
                break
    for key in _PAGE_HEIGHT_KEYS:
        if key in page_raw:
            height = _to_float(page_raw.get(key))
            if height:
                break
    return width, height


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
    pages_raw, _pages_raw_source = _extract_pages_raw(raw)

    logger.info(
        "归一化页面提取  source=%s  page_count=%d  doc_id=%s",
        _pages_raw_source, len(pages_raw), document_id,
    )

    all_blocks: list[NormalizedBlock] = []
    all_pages: list[NormalizedPage] = []
    global_order = 0

    for page_idx, page_raw in enumerate(pages_raw):
        page_num = _extract_page_index(page_raw, page_idx)
        page_w, page_h = _extract_page_size(page_raw)
        layouts, layout_source = _extract_layouts(page_raw)

        logger.info(
            "归一化 page=%d  raw_layout_count=%d  layout_source=%s  page_keys=%s  doc_id=%s",
            page_num, len(layouts), layout_source,
            list(page_raw.keys()) if isinstance(page_raw, dict) else "non-dict",
            document_id,
        )

        page_block_ids: list[str] = []
        skipped_empty = 0

        for layout_idx, layout in enumerate(layouts):
            label = _extract_label(layout)
            text, text_source = _extract_layout_text(layout)

            # 跳过空文本
            if not text.strip():
                skipped_empty += 1
                # 首个被跳过的 layout 记录其 keys 帮助诊断
                if skipped_empty == 1 and isinstance(layout, dict):
                    logger.info(
                        "归一化 page=%d 首个空文本 layout  keys=%s  label=%s  text_source=%s  doc_id=%s",
                        page_num, list(layout.keys()), label, text_source, document_id,
                    )
                continue

            bbox = _extract_bbox(layout)
            score = _extract_score(layout)

            block_type, zone_role, lang, confidence = classify_block(label, text)
            confidence = min(confidence, score)  # 不超过 layout 置信度

            block_id = f"blk-{uuid.uuid4().hex[:12]}"
            block = NormalizedBlock(
                id=block_id,
                page=page_num,
                order=global_order,
                bbox=bbox,
                block_type=block_type,
                zone_role=zone_role,
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
