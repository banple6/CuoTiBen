"""Opt-in DeepSeek canary for the seven currently supported verified classes.

This module is intentionally not named ``test_*.py`` and never runs during the
normal unit-test suite.  It prints metadata only; model text and credentials
are never emitted.
"""
from __future__ import annotations

import asyncio
import os
import tempfile
from pathlib import Path


def _guard() -> str | None:
    if os.environ.get("MATH_EXPLANATION_LIVE_TEST") != "1":
        return "MATH_EXPLANATION_LIVE_TEST is not 1"
    if os.environ.get("MATH_EXPLANATION_PROVIDER", "mock").strip().lower() != "deepseek":
        return "MATH_EXPLANATION_PROVIDER is not deepseek"
    if not (os.environ.get("MATH_EXPLANATION_API_KEY") or os.environ.get("DEEPSEEK_API_KEY")):
        return "DeepSeek API key is not configured"
    return None


async def _run() -> int:
    reason = _guard()
    if reason:
        print(f"SKIPPED: {reason}")
        return 0

    # Imports happen after the opt-in guard so a normal invocation cannot
    # initialize a provider or accidentally perform a network request.
    from app.math_workbook.explanation.provider import DeepSeekExplanationProvider
    from app.math_workbook.explanation.validator import validate_explanation
    from app.math_workbook.migrations.runner import upgrade
    from app.math_workbook.storage import MathWorkbookStore
    from tests.test_explanation import ExplanationTests

    samples = ["2x+3=7", "0x=1", "0x=0", "x^2-5x+6=0", "x^2-2x+1=0", "x^2+1=0", "-2x<4"]
    provider = DeepSeekExplanationProvider()
    passed = 0
    with tempfile.TemporaryDirectory(prefix="cuotiben-deepseek-canary-") as directory:
        root = Path(directory)
        for index, formula in enumerate(samples, start=1):
            # Reuse the production fixture construction, but retain no model
            # payload in logs or output.
            store, problem, _ = ExplanationTests().make_verified(root / str(index), formula)
            prepared = store.prepare_explanation(problem["id"], "u", problem["revision"], {"language": "zh-CN", "level": "beginner", "detail": "detailed"})
            raw = await provider.generate_explanation(prepared["input"], prepared["request_id"])
            validate_explanation(raw, prepared["input"])
            metrics = dict(provider.last_metrics)
            print({"sample": index, "status": "validated", "attempts": metrics.get("attempts"), "input_tokens": metrics.get("input_tokens"), "output_tokens": metrics.get("output_tokens"), "provider_request_id_present": bool(metrics.get("provider_request_id")), "estimated_cost": metrics.get("estimated_cost")})
            passed += 1
    print({"canary": "passed", "samples": passed})
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_run()))
