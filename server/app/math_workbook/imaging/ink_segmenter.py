"""Color-aware handwriting segmentation with evidence-safe fallbacks."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageFilter

from app.math_workbook.imaging.image_limits import open_image_checked


@dataclass(frozen=True, slots=True)
class InkSegmentationResult:
    print_view_path: str
    handwriting_view_path: str
    handwriting_mask_path: str
    has_colored_handwriting: bool
    mask_coverage_ratio: float
    segmentation_status: str
    parameters: dict


def segment_colored_ink(normalized_path: Path, output_dir: Path) -> InkSegmentationResult:
    """Separate high-chroma pen marks without assuming a fixed red RGB value."""
    with open_image_checked(normalized_path) as source:
        image = source.convert("RGB")
    hsv = image.convert("HSV")
    pixels = list(hsv.getdata())
    # Saturated ink is robust to red/blue/purple pens; very dark graphite remains print.
    mask_values = [255 if saturation >= 72 and value >= 45 else 0 for _, saturation, value in pixels]
    mask = Image.new("L", image.size)
    mask.putdata(mask_values)
    mask = mask.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))

    colored_pixels = sum(value > 0 for value in mask.getdata())
    total_pixels = max(image.width * image.height, 1)
    coverage = colored_pixels / total_pixels
    has_colored = coverage >= 0.00025

    original_pixels = list(image.getdata())
    mask_pixels = list(mask.getdata())
    print_pixels = []
    handwriting_pixels = []
    for pixel, masked in zip(original_pixels, mask_pixels, strict=True):
        if masked:
            # OCR-assist view only. The original crop remains the evidence image.
            print_pixels.append((255, 255, 255))
            handwriting_pixels.append(pixel)
        else:
            print_pixels.append(pixel)
            handwriting_pixels.append((255, 255, 255))

    output_dir.mkdir(parents=True, exist_ok=True)
    print_view = Image.new("RGB", image.size)
    print_view.putdata(print_pixels)
    handwriting_view = Image.new("RGB", image.size)
    handwriting_view.putdata(handwriting_pixels)
    print_path = output_dir / "print_view.png"
    handwriting_path = output_dir / "handwriting_view.png"
    mask_path = output_dir / "handwriting_mask.png"
    print_view.save(print_path)
    handwriting_view.save(handwriting_path)
    mask.save(mask_path)

    return InkSegmentationResult(
        print_view_path=str(print_path),
        handwriting_view_path=str(handwriting_path),
        handwriting_mask_path=str(mask_path),
        has_colored_handwriting=has_colored,
        mask_coverage_ratio=round(coverage, 8),
        segmentation_status="segmented" if has_colored else "needs_review",
        parameters={"colorspace": "HSV", "saturation_min": 72, "value_min": 45, "morphology": "max3_min3"},
    )
