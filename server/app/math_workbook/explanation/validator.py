from __future__ import annotations

import json


REQUIRED_FIELDS = {
    "schema_version", "answer_summary", "problem_restatement", "knowledge_points",
    "steps", "verification_explanation", "common_mistakes", "final_answer_latex",
    "limitations",
}
MAX_RESPONSE_CHARS = 64_000
MAX_STEPS = 16
MAX_TEXT_CHARS = 2_000


def _fail(code: str) -> None:
    raise ValueError(code)


def validate_explanation(data: dict, input_data: dict) -> dict:
    """Validate only teaching prose; verified math remains server-owned.

    The model cannot introduce a new answer or an untrusted intermediate
    expression.  If a deterministic trace has a rendered before/after value,
    it must be copied exactly; otherwise those presentation fields must stay
    empty.
    """
    if not isinstance(data, dict) or set(data) != REQUIRED_FIELDS:
        _fail("EXPLANATION_SCHEMA_INVALID")
    if data.get("schema_version") != "1":
        _fail("EXPLANATION_SCHEMA_INVALID")
    answer = input_data.get("answer_latex")
    if not isinstance(answer, str) or not answer:
        _fail("EXPLANATION_INPUT_INVALID")

    summary = data.get("answer_summary")
    if not isinstance(summary, dict) or set(summary) != {"display_latex", "plain_text"}:
        _fail("EXPLANATION_SCHEMA_INVALID")
    if summary.get("display_latex") != answer or not isinstance(summary.get("plain_text"), str):
        _fail("EXPLANATION_OUTPUT_INCONSISTENT")
    if data.get("final_answer_latex") != answer:
        _fail("EXPLANATION_OUTPUT_INCONSISTENT")

    for field in ("problem_restatement",):
        if not isinstance(data.get(field), str) or len(data[field]) > MAX_TEXT_CHARS:
            _fail("EXPLANATION_SCHEMA_INVALID")
    for field in ("knowledge_points", "common_mistakes", "limitations", "verification_explanation"):
        if not isinstance(data.get(field), list):
            _fail("EXPLANATION_SCHEMA_INVALID")

    trace = input_data.get("deterministic_trace")
    if not isinstance(trace, list):
        _fail("EXPLANATION_INPUT_INVALID")
    allowed_rules = {step.get("rule_id", step.get("operation")) for step in trace if isinstance(step, dict)}
    trace_by_rule = {step.get("rule_id", step.get("operation")): step for step in trace if isinstance(step, dict)}
    steps = data["steps"]
    if not isinstance(steps, list) or len(steps) > MAX_STEPS:
        _fail("EXPLANATION_SCHEMA_INVALID")
    if trace and len(steps) != len(trace):
        _fail("EXPLANATION_TRACE_INCOMPLETE")
    for index, step in enumerate(steps, 1):
        if not isinstance(step, dict):
            _fail("EXPLANATION_SCHEMA_INVALID")
        if set(step) != {"index", "title", "explanation", "before_latex", "after_latex", "rule_id"}:
            _fail("EXPLANATION_SCHEMA_INVALID")
        if step.get("index") != index or step.get("rule_id") not in allowed_rules:
            _fail("EXPLANATION_UNKNOWN_RULE")
        for field in ("title", "explanation", "before_latex", "after_latex"):
            if not isinstance(step.get(field), str) or len(step[field]) > MAX_TEXT_CHARS:
                _fail("EXPLANATION_SCHEMA_INVALID")
        source = trace_by_rule[step["rule_id"]]
        if step["before_latex"] != source.get("before_latex", "") or step["after_latex"] != source.get("after_latex", ""):
            _fail("EXPLANATION_OUTPUT_INCONSISTENT")

    allowed_checks = set(input_data.get("passed_checks", input_data.get("verification_summary", {}).get("passed_checks", [])))
    for check in data["verification_explanation"]:
        if not isinstance(check, dict) or set(check) != {"check_type", "explanation"}:
            _fail("EXPLANATION_SCHEMA_INVALID")
        if check.get("check_type") not in allowed_checks:
            _fail("EXPLANATION_UNKNOWN_CHECK")
        if not isinstance(check.get("explanation"), str) or len(check["explanation"]) > MAX_TEXT_CHARS:
            _fail("EXPLANATION_SCHEMA_INVALID")
    for item in data["knowledge_points"]:
        if not isinstance(item, dict) or set(item) != {"id", "name", "explanation"} or not isinstance(item["explanation"], str):
            _fail("EXPLANATION_SCHEMA_INVALID")
        if item["id"] != input_data.get("problem_type"):
            _fail("EXPLANATION_UNKNOWN_KNOWLEDGE_POINT")
    for item in data["common_mistakes"]:
        if not isinstance(item, dict) or set(item) != {"type", "description"} or not isinstance(item["description"], str):
            _fail("EXPLANATION_SCHEMA_INVALID")
    if any(not isinstance(item, str) for item in data["limitations"]):
        _fail("EXPLANATION_SCHEMA_INVALID")

    serialized = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    if len(serialized) > MAX_RESPONSE_CHARS:
        _fail("EXPLANATION_RESPONSE_TOO_LARGE")
    forbidden = ("手写步骤", "我看到了你的笔记", "verified", "rejected", "traceback", "/Volumes/", "/Users/")
    if any(word in serialized for word in forbidden):
        _fail("EXPLANATION_UNSAFE_CLAIM")
    return data
