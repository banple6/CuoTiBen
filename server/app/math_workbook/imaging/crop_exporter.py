"""Crop helpers that retain coordinates in the original image coordinate space."""

from __future__ import annotations

from pathlib import Path

from app.math_workbook.imaging.image_limits import open_image_checked


def export_crop(image_path: Path, bbox: tuple[float, float, float, float], destination: Path) -> str:
    x, y, width, height = bbox
    with open_image_checked(image_path) as image:
        left = max(0, int(x))
        top = max(0, int(y))
        right = min(image.width, max(left + 1, int(x + width)))
        bottom = min(image.height, max(top + 1, int(y + height)))
        destination.parent.mkdir(parents=True, exist_ok=True)
        image.crop((left, top, right, bottom)).save(destination, format="PNG")
    return str(destination)
