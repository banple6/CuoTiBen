"""Application-level limits for decoded math-workbook images.

Upload byte limits are not sufficient for compressed images.  This module
checks dimensions immediately after ``Image.open`` and before conversion,
loading, cropping, or any full-image materialization.
"""

from __future__ import annotations

import warnings
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

from PIL import Image

from app import config


class ImageDimensionError(ValueError):
    """Stable, public-safe image rejection error."""

    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def validate_image_dimensions(
    width: int,
    height: int,
    *,
    max_width: int | None = None,
    max_height: int | None = None,
    max_pixels: int | None = None,
) -> None:
    """Validate dimensions without allocating an image-sized object."""

    width_limit = config.MATH_MAX_IMAGE_WIDTH if max_width is None else max_width
    height_limit = config.MATH_MAX_IMAGE_HEIGHT if max_height is None else max_height
    pixel_limit = config.MATH_MAX_IMAGE_PIXELS if max_pixels is None else max_pixels
    if (
        isinstance(width, bool)
        or isinstance(height, bool)
        or not isinstance(width, int)
        or not isinstance(height, int)
        or width <= 0
        or height <= 0
    ):
        raise ImageDimensionError("IMAGE_DIMENSION_INVALID")
    if width > width_limit:
        raise ImageDimensionError("IMAGE_DIMENSION_INVALID")
    if height > height_limit:
        raise ImageDimensionError("IMAGE_DIMENSION_INVALID")
    try:
        pixels = width * height
    except (OverflowError, ValueError):
        raise ImageDimensionError("IMAGE_PIXEL_LIMIT_EXCEEDED") from None
    if pixels > pixel_limit:
        raise ImageDimensionError("IMAGE_PIXEL_LIMIT_EXCEEDED")


@contextmanager
def open_image_checked(path: Path | str) -> Iterator[Image.Image]:
    """Open an image and validate its dimensions before any decode work."""

    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            image = Image.open(path)
    except (Image.DecompressionBombError, Image.DecompressionBombWarning):
        raise ImageDimensionError("IMAGE_DECOMPRESSION_BOMB") from None
    try:
        validate_image_dimensions(*image.size)
        yield image
    finally:
        image.close()
