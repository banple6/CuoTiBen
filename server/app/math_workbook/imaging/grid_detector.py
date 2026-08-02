"""Conservative grid detector placeholder; phase one never infers grid certainty."""

from __future__ import annotations

from pathlib import Path


def detect_grid(_image_path: Path) -> dict:
    return {"detected": False, "score": None, "reason": "grid_detector_not_enabled_phase1"}
