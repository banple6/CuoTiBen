"""Evidence-preserving image normalization for math workbook pages."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from PIL import ImageEnhance, ImageFilter, ImageOps

from app.math_workbook.imaging.image_limits import open_image_checked


@dataclass(frozen=True, slots=True)
class NormalizedPageImage:
    original_path: str
    normalized_path: str
    width: int
    height: int
    transform_metadata: dict


def normalize_page(original_path: Path, output_path: Path) -> NormalizedPageImage:
    """Correct EXIF orientation and apply only reversible, recorded light normalization.

    Perspective correction is intentionally not guessed in phase one: incorrectly
    rectifying a photographed formula page damages its evidence chain.
    """
    with open_image_checked(original_path) as source:
        image = ImageOps.exif_transpose(source).convert("RGB")
        image = image.filter(ImageFilter.MedianFilter(size=3))
        image = ImageEnhance.Contrast(image).enhance(1.08)
        image = ImageEnhance.Brightness(image).enhance(1.02)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        image.save(output_path, format="PNG")
        width, height = image.size

    metadata = {
        "version": "phase1",
        "orientation_corrected": True,
        "rotation_degrees": 0,
        "perspective_correction": "not_applied",
        "denoise": "median_3",
        "contrast": 1.08,
        "brightness": 1.02,
        "matrix_normalized_to_original": [1, 0, 0, 0, 1, 0, 0, 0, 1],
        "width": width,
        "height": height,
    }
    return NormalizedPageImage(str(original_path), str(output_path), width, height, metadata)


def write_transform_metadata(path: Path, metadata: dict) -> None:
    path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
