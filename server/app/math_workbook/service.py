"""Orchestrates evidence storage, preprocessing, conservative segmentation, and review data."""

from __future__ import annotations

import logging
import hashlib
import os
import shutil
from pathlib import Path
from typing import Any

from app.math_workbook.formula_recognizer import PPStructureFormulaRecognizer
from app.math_workbook.imaging.crop_exporter import export_crop
from app.math_workbook.imaging.image_limits import open_image_checked
from app.math_workbook.imaging.ink_segmenter import segment_colored_ink
from app.math_workbook.imaging.page_normalizer import normalize_page, write_transform_metadata
from app.math_workbook.quality import formula_quality_flags
from app.math_workbook.storage import MathWorkbookStore
from app.services.ai_studio_client import call_pp_structure_v3

logger = logging.getLogger(__name__)


class MathWorkbookService:
    def __init__(self, store: MathWorkbookStore):
        self.store = store
        self.recognizer = PPStructureFormulaRecognizer()

    async def import_page(self, file_path: Path, filename: str, source_type: str, user_id: str | None = None) -> dict:
        if source_type.lower() not in {"image", "scan"}:
            raise ValueError("phase one only accepts raster image pages; PDF is stored but requires a rasterizer")

        import_dir = self.store.storage_root / "imports"
        import_dir.mkdir(parents=True, exist_ok=True)
        import_id = self.store.create_import(source_type, "", user_id or "anonymous")
        try:
            page_dir = import_dir / import_id / "page_0"
            page_dir.mkdir(parents=True, exist_ok=True)
            original_path = page_dir / f"original{file_path.suffix.lower() or '.img'}"
            temporary_path = original_path.with_suffix(original_path.suffix + ".tmp")
            shutil.copyfile(file_path, temporary_path)
            os.replace(temporary_path, original_path)
            self.store.set_import_source(import_id, user_id or "anonymous", original_path)

            page_id = self.store.create_page(import_id, 0, str(original_path), {}, "needs_review")
            normalized = normalize_page(original_path, page_dir / "normalized.png")
            write_transform_metadata(page_dir / "transform.json", normalized.transform_metadata)
            ink = segment_colored_ink(Path(normalized.normalized_path), page_dir)
            metadata = {**normalized.transform_metadata, "ink_segmentation": ink.parameters, "mask_coverage_ratio": ink.mask_coverage_ratio}
            self.store.update_page_views(page_id, normalized=normalized.normalized_path, print_view=ink.print_view_path, handwriting_view=ink.handwriting_view_path, mask=ink.handwriting_mask_path, width=normalized.width, height=normalized.height, metadata=metadata, status=ink.segmentation_status)

            raw_result = await call_pp_structure_v3(original_path.read_bytes(), filename)
            self.store.save_raw_result(page_id, "paddleocr", "PP-StructureV3", raw_result)
            candidates = extract_layout_candidates(raw_result)
            self._segment_candidates(import_id, page_id, page_dir, normalized, ink, candidates)
            self.store.complete_import(import_id)
            logger.info("[MATH] import_id=%s page_id=%s stage=import status=ready candidates=%d", import_id, page_id, len(candidates))
            return self.store.get_import(import_id) or {}
        except Exception:
            # A failed import must not leave a committed graph or image tree
            # behind.  The store performs the controlled, owned cascade and
            # removes only paths belonging to this import.
            try:
                self.store.delete_import(import_id, user_id or "anonymous")
            except Exception:
                logger.exception("[MATH] failed import cleanup import_id=%s", import_id)
            raise

    def _segment_candidates(self, import_id: str, page_id: str, page_dir: Path, normalized: Any, ink: Any, candidates: list[dict]) -> None:
        color_rows = handwriting_row_bounds(Path(ink.handwriting_mask_path))
        block_ids: list[str] = []
        formula_order = 0
        for order, candidate in enumerate(sorted(candidates, key=lambda item: (item["bbox"][1], item["bbox"][0]))):
            bbox = candidate["bbox"]
            overlaps_handwriting = overlaps_rows(bbox, color_rows)
            is_formula = candidate["label"].lower() in {"formula", "equation"} or "\\" in candidate.get("text", "")
            region_type = "mixed_area" if overlaps_handwriting else "printed_problem_area"
            source_type = "mixed" if overlaps_handwriting else "printed"
            region_reasons = ["occluded_by_handwriting"] if overlaps_handwriting else []
            crop = export_crop(Path(normalized.original_path), bbox, page_dir / "crops" / f"region_{order}.png")
            region_id = self.store.add_region(page_id, {"region_type": region_type, "bbox": bbox, "crop_path": crop, "source_view": "original", "reading_order": order, "layout_score": candidate.get("layout_score"), "classification_score": None, "occluded_by_handwriting": overlaps_handwriting, "requires_review": overlaps_handwriting, "review_reasons": region_reasons})
            block_id = self.store.add_source_block(page_id, {"parent_region_id": region_id, "block_type": "formula_block" if is_formula else "text_block", "bbox": bbox, "crop_path": crop, "source_type": source_type, "reading_order": order, "requires_review": overlaps_handwriting, "review_reasons": region_reasons})
            block_ids.append(block_id)
            if is_formula:
                result = self.recognizer.recognize(type("Request", (), {"provider_payload": candidate, "source_type": source_type, "image_path": crop})())
                flags = formula_quality_flags(result.raw_latex, bbox[2], bbox[3])
                flags.extend(result.warnings)
                if overlaps_handwriting:
                    flags.append("occluded_by_handwriting")
                self.store.add_formula(page_id, {"region_id": region_id, "source_block_id": block_id, "bbox": bbox, "crop_path": crop, "source_type": source_type, "role": "problem_expression" if not overlaps_handwriting else "unknown", "raw_latex": result.raw_latex, "normalized_latex": None, "layout_score": candidate.get("layout_score"), "recognition_score": result.recognition_score, "recognition_score_type": result.recognition_score_type, "parseable": None, "occluded_by_handwriting": overlaps_handwriting, "requires_review": bool(flags), "review_reasons": flags, "reading_order": formula_order})
                formula_order += 1

        for line_order, bbox in enumerate(color_rows, start=len(block_ids)):
            crop = export_crop(Path(ink.handwriting_view_path), bbox, page_dir / "crops" / f"handwriting_{line_order}.png")
            region_id = self.store.add_region(page_id, {"region_type": "handwritten_solution_area", "bbox": bbox, "crop_path": crop, "source_view": "handwriting_view", "reading_order": line_order, "layout_score": None, "classification_score": None, "occluded_by_handwriting": False, "requires_review": True, "review_reasons": ["handwriting_recognizer_not_configured"]})
            block_ids.append(self.store.add_source_block(page_id, {"parent_region_id": region_id, "block_type": "handwriting_step", "bbox": bbox, "crop_path": crop, "source_type": "handwritten", "reading_order": line_order, "requires_review": True, "review_reasons": ["handwriting_recognizer_not_configured"]}))
        self.store.link_blocks(block_ids)


def extract_layout_candidates(raw: dict) -> list[dict]:
    """Read raw PP layout evidence without normalizer defaults or text concatenation."""
    results: list[dict] = []
    containers = [raw]
    if isinstance(raw.get("result"), dict):
        containers.append(raw["result"])
    for container in containers:
        pages = container.get("parsing_result") or container.get("layoutParsingResults") or []
        for page in pages if isinstance(pages, list) else []:
            layouts = page.get("layouts") or page.get("layout_parsing_result") or page.get("parsing_res_list") or []
            for layout in layouts if isinstance(layouts, list) else []:
                if not isinstance(layout, dict):
                    continue
                text = layout.get("layout_text") or layout.get("block_content") or layout.get("text") or ""
                raw_bbox = layout.get("layout_bbox") or layout.get("block_bbox") or layout.get("bbox")
                bbox = coerce_bbox(raw_bbox)
                if not text or bbox is None:
                    continue
                raw_score = layout.get("layout_score", layout.get("score"))
                results.append({"text": str(text), "label": str(layout.get("layout_label") or layout.get("block_label") or layout.get("label") or "text"), "bbox": bbox, "layout_score": float(raw_score) if isinstance(raw_score, (int, float)) else None, "raw": layout})
    return results


def coerce_bbox(value: Any) -> tuple[float, float, float, float] | None:
    if isinstance(value, list) and len(value) == 4 and all(isinstance(item, (int, float)) for item in value):
        x1, y1, x2, y2 = value
        return float(x1), float(y1), max(float(x2) - float(x1), 1), max(float(y2) - float(y1), 1)
    if isinstance(value, dict) and {"x", "y", "width", "height"} <= set(value):
        return float(value["x"]), float(value["y"]), float(value["width"]), float(value["height"])
    return None


def handwriting_row_bounds(mask_path: Path) -> list[tuple[float, float, float, float]]:
    with open_image_checked(mask_path) as mask:
        pixels = mask.convert("L")
        width, height = pixels.size
        rows = [sum(pixels.getpixel((x, y)) > 0 for x in range(width)) for y in range(height)]
    active = [index for index, count in enumerate(rows) if count >= max(3, width // 300)]
    groups: list[list[int]] = []
    for row in active:
        if not groups or row - groups[-1][-1] > 10:
            groups.append([row])
        else:
            groups[-1].append(row)
    bounds = []
    for group in groups:
        top, bottom = max(0, group[0] - 8), min(height, group[-1] + 9)
        bounds.append((0.0, float(top), float(width), float(bottom - top)))
    return bounds


def overlaps_rows(bbox: tuple[float, float, float, float], row_bounds: list[tuple[float, float, float, float]]) -> bool:
    _, y, _, height = bbox
    return any(y < row_y + row_height and row_y < y + height for _, row_y, _, row_height in row_bounds)
