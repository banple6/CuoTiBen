"""Opt-in DeepSeek canary for the seven supported verified math classes.

The module is deliberately not named ``test_*.py``.  It exercises the same
production store/provider/validator path used by the API, but it never emits
provider text, request headers, credentials, or user data.  Without an
explicit key this command writes a truthful ``not_executed`` report and does
not construct a provider or make a network request.
"""

from __future__ import annotations

import asyncio
import json
import os
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SAMPLES: tuple[dict[str, str], ...] = (
    {"sample_id": "linear_unique", "formula": "2x+3=7"},
    {"sample_id": "linear_no_solution", "formula": "0x=1"},
    {"sample_id": "linear_identity", "formula": "0x=0"},
    {"sample_id": "quadratic_two_roots", "formula": "x^2-5x+6=0"},
    {"sample_id": "quadratic_repeated_root", "formula": "x^2-2x+1=0"},
    {"sample_id": "quadratic_no_real_root", "formula": "x^2+1=0"},
    {"sample_id": "linear_inequality_negative", "formula": "-2x<4"},
)

CANARY_CODES = frozenset(
    {
        "CANARY_AUTH_FAILED",
        "CANARY_PROVIDER_FAILED",
        "CANARY_TIMEOUT",
        "CANARY_RATE_LIMITED",
        "CANARY_HTTP_FAILED",
        "CANARY_RESPONSE_TOO_LARGE",
        "CANARY_RESPONSE_NOT_JSON",
        "CANARY_RESPONSE_TRUNCATED",
        "CANARY_DUPLICATE_FIELD",
        "CANARY_SCHEMA_REJECTED",
        "CANARY_TRACE_MISMATCH",
        "CANARY_MATH_INCONSISTENT",
        "CANARY_PERSIST_FAILED",
        "CANARY_READBACK_FAILED",
        "CANARY_QUALITY_REJECTED",
        "CANARY_VALIDATED",
    }
)


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _git_value(*args: str, fallback: str = "unknown") -> str:
    try:
        value = subprocess.run(
            ["git", *args],
            cwd=_repo_root(),
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return fallback
    return value or fallback


def _guard() -> str | None:
    if os.environ.get("MATH_EXPLANATION_LIVE_TEST") != "1":
        return "MATH_EXPLANATION_LIVE_TEST is not 1"
    if os.environ.get("MATH_EXPLANATION_PROVIDER", "mock").strip().lower() != "deepseek":
        return "MATH_EXPLANATION_PROVIDER is not deepseek"
    if not (os.environ.get("MATH_EXPLANATION_API_KEY", "").strip() or os.environ.get("DEEPSEEK_API_KEY", "").strip()):
        return "API key not configured"
    return None


def _empty_metrics() -> dict[str, Any]:
    return {
        "logical_requests": 0,
        "network_attempts": 0,
        "retries": 0,
        "input_tokens": None,
        "output_tokens": None,
        "cached_tokens": None,
        "estimated_cost": None,
        "duration_ms": None,
        "client_request_id": None,
        "provider_request_id_present": False,
        "provider_request_id_source": "none",
        "actual_model_name": None,
    }


def _not_executed_result(sample: dict[str, str]) -> dict[str, Any]:
    return {
        **sample,
        "status": "not_executed",
        "error_code": None,
        "schema_validated": False,
        "quality_review": None,
        "persisted": False,
        "readback": False,
        "cross_user_read_rejected": None,
        "failure_current_hidden": None,
        "metrics": _empty_metrics(),
    }


def _stable_error_code(error: BaseException) -> str:
    """Map every internal/provider failure to one of the report codes."""

    code = getattr(error, "code", "")
    if not isinstance(code, str):
        code = ""
    if code == "PROVIDER_API_KEY_MISSING":
        return "CANARY_AUTH_FAILED"
    if code == "PROVIDER_TIMEOUT":
        return "CANARY_TIMEOUT"
    if code == "PROVIDER_HTTP_429":
        return "CANARY_RATE_LIMITED"
    if code.startswith("PROVIDER_HTTP_"):
        return "CANARY_HTTP_FAILED"
    if code in {"PROVIDER_NETWORK_ERROR", "PROVIDER_FAILED"}:
        return "CANARY_PROVIDER_FAILED"
    if code == "MODEL_RESPONSE_TOO_LARGE":
        return "CANARY_RESPONSE_TOO_LARGE"
    if code == "MODEL_RESPONSE_NOT_JSON":
        return "CANARY_RESPONSE_NOT_JSON"
    if code == "MODEL_RESPONSE_TRUNCATED":
        return "CANARY_RESPONSE_TRUNCATED"
    if code == "MODEL_RESPONSE_DUPLICATE_FIELD":
        return "CANARY_DUPLICATE_FIELD"
    if code in {"MODEL_RESPONSE_SCHEMA_INVALID", "EXPLANATION_SCHEMA_INVALID"}:
        return "CANARY_SCHEMA_REJECTED"
    if code in {"MODEL_RESPONSE_TRACE_MISMATCH", "EXPLANATION_TRACE_INCOMPLETE"}:
        return "CANARY_TRACE_MISMATCH"
    if code in {"MODEL_RESPONSE_INCONSISTENT", "EXPLANATION_OUTPUT_INCONSISTENT", "EXPLANATION_INPUT_INVALID"}:
        return "CANARY_MATH_INCONSISTENT"
    return "CANARY_PROVIDER_FAILED"


def _storage_status(code: str) -> str:
    if code == "CANARY_TIMEOUT":
        return "timeout"
    if code in {"CANARY_SCHEMA_REJECTED", "CANARY_TRACE_MISMATCH", "CANARY_MATH_INCONSISTENT", "CANARY_QUALITY_REJECTED"}:
        return "rejected"
    return "failed"


def _report_metrics(provider_metrics: dict[str, Any], attempted: bool) -> dict[str, Any]:
    attempts = provider_metrics.get("attempts")
    attempts = int(attempts) if isinstance(attempts, int) and attempts >= 0 else 0
    provider_id = provider_metrics.get("provider_request_id")
    provider_source = provider_metrics.get("provider_request_id_source", "none")
    if provider_source not in {"x-request-id", "request-id", "response-body-id", "none"}:
        provider_source = "none"
    return {
        "logical_requests": 1 if attempted else 0,
        "network_attempts": attempts,
        "retries": max(0, attempts - 1),
        "input_tokens": provider_metrics.get("input_tokens"),
        "output_tokens": provider_metrics.get("output_tokens"),
        "cached_tokens": provider_metrics.get("cached_tokens"),
        "estimated_cost": provider_metrics.get("estimated_cost"),
        "duration_ms": provider_metrics.get("duration_ms"),
        "client_request_id": provider_metrics.get("client_request_id") or provider_metrics.get("request_id"),
        "provider_request_id_present": isinstance(provider_id, str) and bool(provider_id),
        "provider_request_id_source": provider_source,
        "actual_model_name": provider_metrics.get("actual_model_name"),
    }


def _human_quality_review(validated: dict[str, Any], prepared: dict[str, Any]) -> dict[str, Any]:
    """Record the fixed human checklist without asking a second model.

    The checks intentionally inspect only the server-owned validated artifact,
    its trace binding, and bounded prose.  They are a repeatable checklist for
    the operator's seven-sample review, not a new mathematical solver.
    """

    trace = prepared["input"].get("deterministic_trace", {})
    validated_trace = validated.get("deterministic_trace")
    texts: list[str] = [str(validated.get("problem_restatement", ""))]
    texts.extend(str(item.get("explanation", "")) for item in validated.get("step_explanations", []) if isinstance(item, dict))
    texts.extend(str(item.get("explanation", "")) for item in validated.get("knowledge_point_explanations", []) if isinstance(item, dict))
    texts.extend(str(item.get("explanation", "")) for item in validated.get("verification_explanations", []) if isinstance(item, dict))
    texts.extend(str(item.get("description", "")) for item in validated.get("common_mistakes", []) if isinstance(item, dict))
    forbidden = ("手写步骤", "手写过程", "你错在", "你的错误", "我看到了你的", "根据你的笔记")
    all_text = "\n".join(texts)
    required_checks = set(prepared["input"].get("verification_summary", {}).get("required_checks", []))
    explained_checks = {item.get("check_type") for item in validated.get("verification_explanations", []) if isinstance(item, dict)}
    checks = {
        "language_quality": bool(texts and all(text.strip() for text in texts)),
        "beginner_readability": bool(texts and all(len(text) <= 2000 for text in texts)),
        "trace_fidelity": validated_trace == trace,
        "mathematical_wording": validated.get("quality", {}).get("quality_status") == "passed",
        "verification_explanation": explained_checks == required_checks,
        "common_mistake_safety": not any(item in all_text for item in forbidden),
        "forbidden_claims": not any(item in all_text for item in forbidden),
        "generic_or_empty_prose": bool(texts and all(text.strip() for text in texts)),
    }
    result = {key: "passed" if value else "failed" for key, value in checks.items()}
    result.update({"review_status": "passed" if all(checks.values()) else "rejected", "review_method": "human_checklist_v1"})
    return result


def _row_readback_ok(saved: dict[str, Any], prepared: dict[str, Any]) -> bool:
    gate = prepared["gate"]
    return all(
        (
            saved.get("problem_id") == gate["problem"]["id"],
            saved.get("verification_report_id") == gate["verification"]["id"],
            saved.get("candidate_solution_result_id") == gate["candidate"]["id"],
            saved.get("input_source_revision") == gate["source_revision"],
            saved.get("input_hash") == prepared["input_hash"],
            saved.get("request_id") == prepared["request_id"],
            saved.get("prompt_version") == prepared["input"]["prompt_version"],
            saved.get("schema_version") == prepared["input"]["schema_version"],
            saved.get("trace_version") == prepared["input"]["trace_version"],
            saved.get("renderer_version") == prepared["input"]["renderer_version"],
        )
    )


async def _run_sample(sample: dict[str, str], root: Path) -> dict[str, Any]:
    # Imports are intentionally delayed until the live guard has passed.
    from app import config
    from app.math_workbook.explanation.provider import DeepSeekExplanationProvider
    from app.math_workbook.explanation.validator import validate_explanation
    from app.routes.math_workbook import _public_explanation
    from tests.test_explanation import ExplanationTests

    result: dict[str, Any] = {**sample, "status": "CANARY_PROVIDER_FAILED", "error_code": None, "schema_validated": False, "quality_review": None, "persisted": False, "readback": False, "cross_user_read_rejected": None, "failure_current_hidden": None, "metrics": _empty_metrics()}
    store = None
    prepared = None
    provider_metrics: dict[str, Any] = {}
    raw: dict[str, Any] = {}
    try:
        # This fixture performs create import/page/formula/confirmation/problem,
        # then the production parse/build/analyze/solve/trace/verify stages.
        store, problem, _ = ExplanationTests().make_verified(root / sample["sample_id"], sample["formula"])
        prepared = store.prepare_explanation(problem["id"], "u", problem["revision"], {"language": "zh-CN", "level": "beginner", "detail": "detailed"})
        provider = DeepSeekExplanationProvider()
        raw = await provider.generate_explanation(prepared["input"], prepared["request_id"])
        provider_metrics = dict(provider.last_metrics)
        validated = validate_explanation(raw, prepared["input"])
        result["schema_validated"] = True
        quality = _human_quality_review(validated, prepared)
        result["quality_review"] = quality
        if quality["review_status"] != "passed":
            result["error_code"] = "CANARY_QUALITY_REJECTED"
            saved = store.persist_explanation(prepared, config.MATH_EXPLANATION_PROVIDER, config.MATH_EXPLANATION_MODEL, config.MATH_EXPLANATION_MODEL_VERSION, raw, None, "rejected", [{"code": "CANARY_QUALITY_REJECTED"}], provider_metrics)
            result["status"] = "CANARY_QUALITY_REJECTED"
        else:
            saved = store.persist_explanation(prepared, config.MATH_EXPLANATION_PROVIDER, config.MATH_EXPLANATION_MODEL, config.MATH_EXPLANATION_MODEL_VERSION, raw, validated, "validated", [], provider_metrics)
            result["status"] = "CANARY_VALIDATED" if saved.get("status") == "validated" else "CANARY_PERSIST_FAILED"
            if result["status"] != "CANARY_VALIDATED":
                result["error_code"] = "CANARY_PERSIST_FAILED"
        result["persisted"] = True
        current = store.current_explanation(problem["id"], "u")
        result["readback"] = bool(current and _row_readback_ok(current, prepared) and _public_explanation(current).get("id") == current.get("id"))
        if result["status"] == "CANARY_VALIDATED" and not result["readback"]:
            result["status"] = "CANARY_READBACK_FAILED"
            result["error_code"] = "CANARY_READBACK_FAILED"
        try:
            store.current_explanation(problem["id"], "different-user")
        except KeyError:
            result["cross_user_read_rejected"] = True
        else:
            result["cross_user_read_rejected"] = False
        public = _public_explanation(saved)
        if any(key in public for key in ("raw_model_response_json", "explanation_input_json")):
            result["status"] = "CANARY_READBACK_FAILED"
            result["error_code"] = "CANARY_READBACK_FAILED"
        result["failure_current_hidden"] = current is None if result["status"] != "CANARY_VALIDATED" else None
    except Exception as error:  # report only the stable classification
        provider_metrics = provider_metrics or (dict(provider.last_metrics) if "provider" in locals() else {})
        result["error_code"] = _stable_error_code(error)
        result["status"] = result["error_code"]
        if store is not None and prepared is not None:
            from app import config
            try:
                saved = store.persist_explanation(prepared, config.MATH_EXPLANATION_PROVIDER, config.MATH_EXPLANATION_MODEL, config.MATH_EXPLANATION_MODEL_VERSION, raw, None, _storage_status(result["error_code"]), [{"code": result["error_code"]}], provider_metrics)
                result["persisted"] = True
                current = store.current_explanation(prepared["gate"]["problem"]["id"], "u")
                result["failure_current_hidden"] = current is None
                result["readback"] = current is None or _row_readback_ok(current, prepared)
            except Exception:
                result["error_code"] = "CANARY_PERSIST_FAILED"
                result["status"] = "CANARY_PERSIST_FAILED"
                result["failure_current_hidden"] = True
    result["metrics"] = _report_metrics(provider_metrics, attempted=True)
    if result["status"] == "CANARY_VALIDATED" and result["cross_user_read_rejected"] is not True:
        result["status"] = "CANARY_READBACK_FAILED"
        result["error_code"] = "CANARY_READBACK_FAILED"
    return result


def _sum_optional(results: list[dict[str, Any]], key: str) -> int | float | None:
    values = [item["metrics"].get(key) for item in results if isinstance(item.get("metrics", {}).get(key), (int, float))]
    return sum(values) if values else None


def _build_report(status: str, reason: str | None, results: list[dict[str, Any]], actual_models: list[str] | None = None) -> dict[str, Any]:
    from app.math_workbook.explanation.prompt import PROMPT_CONTENT_HASH, PROMPT_CREATED_AT, PROMPT_ID, PROMPT_VERSION, RENDERER_VERSION, SCHEMA_VERSION, TRACE_VERSION

    models = sorted({model for model in (actual_models or []) if model})
    return {
        "report_version": "1",
        "status": status,
        "reason": reason,
        "execution_date": datetime.now(timezone.utc).date().isoformat(),
        "commit_sha": _git_value("rev-parse", "HEAD"),
        "branch": _git_value("branch", "--show-current"),
        "provider": "deepseek",
        "provider_config": {"live_test": os.environ.get("MATH_EXPLANATION_LIVE_TEST", "0"), "key_source": "environment-only"},
        "configured_model": os.environ.get("MATH_EXPLANATION_MODEL", "deepseek-chat"),
        "actual_model_name": models[0] if len(models) == 1 else (models or None),
        "prompt": {"id": PROMPT_ID, "version": PROMPT_VERSION, "content_hash": PROMPT_CONTENT_HASH, "created_at": PROMPT_CREATED_AT},
        "schema_version": SCHEMA_VERSION,
        "trace_version": TRACE_VERSION,
        "renderer_version": RENDERER_VERSION,
        "samples": results,
        "totals": {
            "sample_count": len(results),
            "validated_samples": sum(item.get("status") == "CANARY_VALIDATED" for item in results),
            "failed_samples": sum(item.get("status") not in {"CANARY_VALIDATED", "not_executed"} for item in results),
            "not_executed_samples": sum(item.get("status") == "not_executed" for item in results),
            "logical_requests": sum(item["metrics"].get("logical_requests", 0) for item in results),
            "network_attempts": sum(item["metrics"].get("network_attempts", 0) for item in results),
            "retries": sum(item["metrics"].get("retries", 0) for item in results),
            "input_tokens": _sum_optional(results, "input_tokens"),
            "output_tokens": _sum_optional(results, "output_tokens"),
            "cached_tokens": _sum_optional(results, "cached_tokens"),
            "estimated_cost": _sum_optional(results, "estimated_cost"),
            "duration_ms": _sum_optional(results, "duration_ms"),
        },
    }


def _write_report(report: dict[str, Any]) -> None:
    target = _repo_root() / "docs" / "validation"
    target.mkdir(parents=True, exist_ok=True)
    (target / "math-explanation-live-canary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    lines = [
        "# Math explanation live canary",
        "",
        f"- Status: `{report['status']}`",
        f"- Execution date: `{report['execution_date']}`",
        f"- Commit: `{report['commit_sha']}`",
        f"- Branch: `{report['branch']}`",
        f"- Provider: `{report['provider']}`",
        f"- Configured model: `{report['configured_model']}`",
        f"- Actual model: `{report['actual_model_name']}`",
        f"- Prompt: `{report['prompt']['id']}` v`{report['prompt']['version']}` (`{report['prompt']['content_hash']}`)",
        f"- Prompt created at: `{report['prompt']['created_at']}`",
        f"- Schema/trace/renderer: `{report['schema_version']}`/`{report['trace_version']}`/`{report['renderer_version']}`",
        "",
    ]
    if report.get("reason"):
        lines.extend([f"Reason: `{report['reason']}`", ""])
    lines.extend(["## Seven fixed samples", "", "| Sample | Formula | Status | Logical requests | Network attempts | Retries | Provider id | Persisted | Readback |", "|---|---|---|---:|---:|---:|---|---|---|"])
    for item in report["samples"]:
        metrics = item["metrics"]
        lines.append(f"| `{item['sample_id']}` | `{item['formula']}` | `{item['status']}` | {metrics['logical_requests']} | {metrics['network_attempts']} | {metrics['retries']} | `{metrics['provider_request_id_source']}` / {metrics['provider_request_id_present']} | {item['persisted']} | {item['readback']} |")
    lines.extend(["", "## Totals", "", "```json", json.dumps(report["totals"], ensure_ascii=False, indent=2, sort_keys=True), "```", "", "The JSON artifact contains only redacted metrics and checklist statuses; it never contains an API key, Authorization header, raw model response, full explanation input, absolute path, or user data.", ""])
    (target / "math-explanation-live-canary.md").write_text("\n".join(lines), encoding="utf-8")


async def _run() -> int:
    reason = _guard()
    if reason:
        report = _build_report("not_executed", reason, [_not_executed_result(sample) for sample in SAMPLES])
        _write_report(report)
        print("LIVE_CANARY_NOT_EXECUTED")
        return 0

    results: list[dict[str, Any]] = []
    actual_models: list[str] = []
    with tempfile.TemporaryDirectory(prefix="cuotiben-deepseek-canary-") as directory:
        root = Path(directory)
        for sample in SAMPLES:
            result = await _run_sample(sample, root)
            results.append(result)
            model = result["metrics"].get("actual_model_name")
            if isinstance(model, str) and model:
                actual_models.append(model)
            print({"sample_id": sample["sample_id"], "status": result["status"], "error_code": result["error_code"], "network_attempts": result["metrics"]["network_attempts"], "retries": result["metrics"]["retries"], "provider_request_id_present": result["metrics"]["provider_request_id_present"], "provider_request_id_source": result["metrics"]["provider_request_id_source"]})
    report = _build_report("completed", None, results, actual_models)
    _write_report(report)
    return 0 if all(item["status"] == "CANARY_VALIDATED" for item in results) else 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_run()))
