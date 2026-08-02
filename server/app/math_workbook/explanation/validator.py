from __future__ import annotations

import json
import re
from typing import Any

from .trace import TRACE_RULE_IDS


MAX_RESPONSE_CHARS = 64_000
MAX_STEPS = 32
MAX_TEXT_CHARS = 2_000
_IDENTIFIER_RE = re.compile(r"(?<![A-Za-z0-9_])[A-Za-z][A-Za-z0-9_]*(?![A-Za-z0-9_])")
_MATH_CLAIM_RE = re.compile(r"(?:[A-Za-z\\][A-Za-z0-9_\\{}^]*)\s*(?:=|<|>|≤|≥|\\le|\\ge)")
_MATH_EXPRESSION_RE = re.compile(r"(?:\\(?:frac|sqrt|Delta|[A-Za-z]+)|(?<![A-Za-z0-9_])[A-Za-z](?:\s*[+\-*/^]\s*[A-Za-z0-9(\\])|(?<![A-Za-z0-9_])\d+\s*[+\-*/^]\s*\d+)")
_FORBIDDEN_CLAIM_PATTERNS = (
    "手写步骤",
    "手写过程",
    "你的错误",
    "你错在",
    "你忘记",
    "你没有掌握",
    "从你的手写",
    "我看到了你的",
    "根据你的笔记",
    "检测到你",
    "你在第二步",
)
_SAFE_WORDS = {"JSON", "Schema", "LaTeX", "AST", "DeepSeek", "step", "rule", "check"}


def _fail(code: str) -> None:
    raise ValueError(code)


def _text(value: Any, code: str = "MODEL_RESPONSE_SCHEMA_INVALID") -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > MAX_TEXT_CHARS:
        _fail(code)
    return value


def _legacy_validate(data: dict, input_data: dict) -> dict:
    required_fields = {
        "schema_version", "answer_summary", "problem_restatement", "knowledge_points",
        "steps", "verification_explanation", "common_mistakes", "final_answer_latex", "limitations",
    }
    if not isinstance(data, dict) or set(data) != required_fields or data.get("schema_version") != "1":
        _fail("EXPLANATION_SCHEMA_INVALID")
    answer = input_data.get("answer_latex")
    if not isinstance(answer, str) or not answer:
        _fail("EXPLANATION_INPUT_INVALID")
    summary = data.get("answer_summary")
    if not isinstance(summary, dict) or set(summary) != {"display_latex", "plain_text"}:
        _fail("EXPLANATION_SCHEMA_INVALID")
    if summary.get("display_latex") != answer or not isinstance(summary.get("plain_text"), str) or data.get("final_answer_latex") != answer:
        _fail("EXPLANATION_OUTPUT_INCONSISTENT")
    _text(data.get("problem_restatement"))
    for field in ("knowledge_points", "common_mistakes", "limitations", "verification_explanation"):
        if not isinstance(data.get(field), list):
            _fail("EXPLANATION_SCHEMA_INVALID")
    raw_trace = input_data.get("deterministic_trace", [])
    trace = raw_trace.get("steps", []) if isinstance(raw_trace, dict) else raw_trace
    if not isinstance(trace, list):
        _fail("EXPLANATION_INPUT_INVALID")
    allowed_rules = {step.get("rule_id", step.get("operation")) for step in trace if isinstance(step, dict)}
    trace_by_index = {step.get("index", i + 1): step for i, step in enumerate(trace) if isinstance(step, dict)}
    steps = data["steps"]
    if not isinstance(steps, list) or len(steps) > MAX_STEPS or (trace and len(steps) != len(trace)):
        _fail("EXPLANATION_TRACE_INCOMPLETE")
    for index, step in enumerate(steps, 1):
        if not isinstance(step, dict) or set(step) != {"index", "title", "explanation", "before_latex", "after_latex", "rule_id"}:
            _fail("EXPLANATION_SCHEMA_INVALID")
        if step.get("index") != index or step.get("rule_id") not in allowed_rules:
            _fail("EXPLANATION_UNKNOWN_RULE")
        for field in ("title", "explanation", "before_latex", "after_latex"):
            if not isinstance(step.get(field), str) or len(step[field]) > MAX_TEXT_CHARS:
                _fail("EXPLANATION_SCHEMA_INVALID")
        source = trace_by_index.get(index)
        if source and (step["before_latex"] != source.get("before_latex", "") or step["after_latex"] != source.get("after_latex", "")):
            _fail("EXPLANATION_OUTPUT_INCONSISTENT")
    allowed_checks = set(input_data.get("passed_checks", input_data.get("verification_summary", {}).get("passed_checks", [])))
    seen_checks = set()
    for check in data["verification_explanation"]:
        if not isinstance(check, dict) or set(check) != {"check_type", "explanation"}:
            _fail("EXPLANATION_SCHEMA_INVALID")
        if check.get("check_type") not in allowed_checks:
            _fail("EXPLANATION_UNKNOWN_CHECK")
        seen_checks.add(check["check_type"])
        _text(check.get("explanation"))
    for item in data["knowledge_points"]:
        if not isinstance(item, dict) or set(item) != {"id", "name", "explanation"} or not isinstance(item["explanation"], str):
            _fail("EXPLANATION_SCHEMA_INVALID")
        if item["id"] != input_data.get("problem_type"):
            _fail("EXPLANATION_UNKNOWN_KNOWLEDGE_POINT")
    for item in data["common_mistakes"]:
        if not isinstance(item, dict) or set(item) != {"type", "description"}:
            _fail("EXPLANATION_SCHEMA_INVALID")
        _text(item.get("description"))
    if any(not isinstance(item, str) for item in data["limitations"]):
        _fail("EXPLANATION_SCHEMA_INVALID")
    serialized = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    if len(serialized) > MAX_RESPONSE_CHARS:
        _fail("EXPLANATION_RESPONSE_TOO_LARGE")
    if any(word in serialized for word in ("手写步骤", "我看到了你的笔记", "verified", "rejected", "traceback", "/Volumes/", "/Users/")):
        _fail("EXPLANATION_UNSAFE_CLAIM")
    return data


def _check_prose_constraints(text: str, input_data: dict) -> None:
    if any(pattern in text for pattern in _FORBIDDEN_CLAIM_PATTERNS):
        _fail("MODEL_RESPONSE_INCONSISTENT")
    if _MATH_CLAIM_RE.search(text) or _MATH_EXPRESSION_RE.search(text):
        _fail("MODEL_RESPONSE_INCONSISTENT")
    variables = {str(item.get("name")) for item in input_data.get("variables", []) if isinstance(item, dict)}
    for identifier in _IDENTIFIER_RE.findall(text):
        if identifier in _SAFE_WORDS or identifier in variables:
            continue
        # A single alphabetic token is a mathematical variable unless the
        # server explicitly supplied it in the IR.
        if len(identifier) == 1:
            _fail("MODEL_RESPONSE_INCONSISTENT")


def _quality(input_data: dict, *, step_count: int, explained_checks: set[str], required_checks: set[str], unknown_variables: list[str] | None = None, forbidden_claims: list[str] | None = None) -> dict[str, Any]:
    unknown_variables = unknown_variables or []
    forbidden_claims = forbidden_claims or []
    missing_checks = sorted(required_checks - explained_checks)
    extra_checks = sorted(explained_checks - required_checks)
    trace = input_data.get("deterministic_trace", {})
    steps = trace.get("steps", trace if isinstance(trace, list) else [])
    total = len(steps) if isinstance(steps, list) else 0
    quality_status = "passed" if not missing_checks and not extra_checks and not unknown_variables and not forbidden_claims else "rejected"
    return {
        "coverage": {
            "trace_steps_total": total,
            "trace_steps_explained": step_count,
            "verification_checks_total": len(required_checks),
            "verification_checks_explained": len(explained_checks & required_checks),
        },
        "constraints": {
        "extra_steps": max(0, step_count - total),
        "missing_steps": max(0, total - step_count),
            "unknown_variables": unknown_variables,
            "forbidden_claims": forbidden_claims,
            "unknown_checks": extra_checks,
        },
        "quality_status": quality_status,
    }


def validate_explanation(data: dict, input_data: dict) -> dict:
    """Validate provider prose and merge it with server-owned math fields."""

    if isinstance(data, dict) and data.get("schema_version") == "1":
        return _legacy_validate(data, input_data)
    if not isinstance(data, dict):
        _fail("MODEL_RESPONSE_SCHEMA_INVALID")
    required_fields = {
        "schema_version", "problem_restatement", "step_explanations",
        "knowledge_point_explanations", "verification_explanations",
        "common_mistakes", "limitations",
    }
    if data.get("schema_version") != "2" or set(data) != required_fields:
        _fail("MODEL_RESPONSE_SCHEMA_INVALID")
    trace = input_data.get("deterministic_trace")
    if not isinstance(trace, dict) or trace.get("trace_version") != "1" or trace.get("renderer_version") != "1":
        _fail("MODEL_RESPONSE_TRACE_MISMATCH")
    binding = trace.get("binding")
    if not isinstance(binding, dict) or {"problem_id", "source_revision", "candidate_solution_result_id", "verification_report_id", "input_hash", "trace_version", "renderer_version"} - set(binding):
        _fail("MODEL_RESPONSE_TRACE_MISMATCH")
    if binding.get("problem_id") != input_data.get("problem_id") or binding.get("source_revision") != input_data.get("source_revision") or binding.get("trace_version") != trace.get("trace_version") or binding.get("renderer_version") != trace.get("renderer_version") or not all(isinstance(binding.get(key), str) and binding.get(key) for key in ("candidate_solution_result_id", "verification_report_id", "input_hash")):
        _fail("MODEL_RESPONSE_TRACE_MISMATCH")
    trace_steps = trace.get("steps")
    if not isinstance(trace_steps, list) or len(trace_steps) > MAX_STEPS:
        _fail("MODEL_RESPONSE_TRACE_MISMATCH")
    if any(
        not isinstance(step, dict) or step.get("rule_id") not in TRACE_RULE_IDS
        for step in trace_steps
    ):
        _fail("MODEL_RESPONSE_TRACE_MISMATCH")
    _text(data["problem_restatement"])
    _check_prose_constraints(data["problem_restatement"], input_data)
    for item in (data["step_explanations"], data["knowledge_point_explanations"], data["verification_explanations"], data["common_mistakes"], data["limitations"]):
        if not isinstance(item, list):
            _fail("MODEL_RESPONSE_SCHEMA_INVALID")

    step_explanations = data["step_explanations"]
    if len(step_explanations) != len(trace_steps):
        _fail("MODEL_RESPONSE_TRACE_MISMATCH")
    indices: list[int] = []
    for item, source in zip(step_explanations, trace_steps):
        if not isinstance(item, dict) or set(item) != {"index", "title", "explanation"}:
            _fail("MODEL_RESPONSE_SCHEMA_INVALID")
        if item.get("index") != source.get("index") or item.get("index") in indices:
            _fail("MODEL_RESPONSE_TRACE_MISMATCH")
        indices.append(item["index"])
        _text(item.get("title")); explanation = _text(item.get("explanation")); _check_prose_constraints(explanation, input_data)
        _check_prose_constraints(item["title"], input_data)
    if indices != [step.get("index") for step in trace_steps]:
        _fail("MODEL_RESPONSE_TRACE_MISMATCH")

    expected_knowledge = set(input_data.get("knowledge_point_ids", [input_data.get("problem_type", "math")]))
    knowledge_ids: set[str] = set()
    for item in data["knowledge_point_explanations"]:
        if not isinstance(item, dict) or set(item) != {"knowledge_point_id", "explanation"}:
            _fail("MODEL_RESPONSE_SCHEMA_INVALID")
        if item.get("knowledge_point_id") not in expected_knowledge:
            _fail("MODEL_RESPONSE_INCONSISTENT")
        if item.get("knowledge_point_id") in knowledge_ids:
            _fail("MODEL_RESPONSE_TRACE_MISMATCH")
        knowledge_ids.add(item["knowledge_point_id"])
        _check_prose_constraints(_text(item.get("explanation")), input_data)
    if knowledge_ids != expected_knowledge:
        _fail("MODEL_RESPONSE_TRACE_MISMATCH")

    summary = input_data.get("verification_summary", {})
    required_checks = set(summary.get("required_checks", summary.get("passed_checks", [])))
    explained_checks: set[str] = set()
    for item in data["verification_explanations"]:
        if not isinstance(item, dict) or set(item) != {"check_type", "explanation"}:
            _fail("MODEL_RESPONSE_SCHEMA_INVALID")
        check_type = item.get("check_type")
        if check_type in explained_checks or check_type not in required_checks:
            _fail("MODEL_RESPONSE_TRACE_MISMATCH")
        explained_checks.add(check_type)
        _check_prose_constraints(_text(item.get("explanation")), input_data)
    if explained_checks != required_checks:
        _fail("MODEL_RESPONSE_TRACE_MISMATCH")

    mistakes: list[dict[str, str]] = []
    for item in data["common_mistakes"]:
        if not isinstance(item, dict) or set(item) != {"type", "description"}:
            _fail("MODEL_RESPONSE_SCHEMA_INVALID")
        _text(item.get("type")); _check_prose_constraints(item.get("type"), input_data); description = _text(item.get("description")); _check_prose_constraints(description, input_data)
        mistakes.append({"type": item["type"], "description": description})
    limitations: list[str] = []
    for item in data["limitations"]:
        limitations.append(_text(item))
        _check_prose_constraints(item, input_data)
    quality = _quality(input_data, step_count=len(step_explanations), explained_checks=explained_checks, required_checks=required_checks)
    if quality["quality_status"] != "passed":
        _fail("MODEL_RESPONSE_INCONSISTENT")
    answer = input_data.get("answer_latex")
    if not isinstance(answer, str) or not answer:
        _fail("EXPLANATION_INPUT_INVALID")
    serialized = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    if len(serialized) > MAX_RESPONSE_CHARS:
        _fail("MODEL_RESPONSE_TOO_LARGE")
    return {
        "schema_version": "2",
        "trace_version": trace["trace_version"],
        "renderer_version": trace["renderer_version"],
        "final_answer_latex": answer,
        "deterministic_trace": trace,
        "problem_restatement": data["problem_restatement"],
        "step_explanations": step_explanations,
        "knowledge_point_explanations": data["knowledge_point_explanations"],
        "verification_explanations": data["verification_explanations"],
        "common_mistakes": mistakes,
        "limitations": limitations,
        "quality": quality,
    }
