from __future__ import annotations

import asyncio
import hashlib
import json
import random
import re
import time
from typing import Any, Protocol

import httpx

from app import config
from .prompt import SCHEMA_VERSION, SYSTEM_PROMPT


MODEL_RESPONSE_CODES = {
    "MODEL_RESPONSE_NOT_JSON",
    "MODEL_RESPONSE_TRUNCATED",
    "MODEL_RESPONSE_SCHEMA_INVALID",
    "MODEL_RESPONSE_INCONSISTENT",
    "MODEL_RESPONSE_TOO_LARGE",
    "MODEL_RESPONSE_DUPLICATE_FIELD",
    "MODEL_RESPONSE_TRACE_MISMATCH",
}
_FENCE_RE = re.compile(r"^```(?:json)?\s*\n?(.*?)\n?```$", re.DOTALL | re.IGNORECASE)


class ExplanationProviderError(Exception):
    def __init__(self, code: str, *, retryable: bool = False):
        super().__init__(code)
        self.code = code
        self.retryable = retryable


class ExplanationModelProvider(Protocol):
    last_metrics: dict

    async def generate_explanation(self, request: dict, request_id: str | None = None) -> dict:
        ...


def _stable_request_id(request: dict, request_id: str | None) -> str:
    if request_id:
        return request_id
    return hashlib.sha256(json.dumps(request, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()[:32]


def _duplicate_reject(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ExplanationProviderError("MODEL_RESPONSE_DUPLICATE_FIELD")
        result[key] = value
    return result


def parse_model_json(content: Any) -> dict[str, Any]:
    """Conservative JSON compatibility; never repairs or extracts fragments."""

    if not isinstance(content, str):
        raise ExplanationProviderError("MODEL_RESPONSE_SCHEMA_INVALID")
    text = content.strip()
    fenced = _FENCE_RE.match(text)
    if fenced:
        text = fenced.group(1).strip()
    elif text.startswith("```") or text.endswith("```"):
        raise ExplanationProviderError("MODEL_RESPONSE_TRUNCATED")
    if not text:
        raise ExplanationProviderError("MODEL_RESPONSE_NOT_JSON")
    try:
        data = json.loads(text, object_pairs_hook=_duplicate_reject)
    except ExplanationProviderError:
        raise
    except json.JSONDecodeError as error:
        code = "MODEL_RESPONSE_TRUNCATED" if text.count("{") > text.count("}") or text.count("[") > text.count("]") else "MODEL_RESPONSE_NOT_JSON"
        raise ExplanationProviderError(code) from error
    if not isinstance(data, dict):
        raise ExplanationProviderError("MODEL_RESPONSE_SCHEMA_INVALID")
    return data


class MockExplanationProvider:
    """Deterministic local provider; it never contacts an external service."""

    def __init__(self):
        self.last_metrics = {
            "input_tokens": 0,
            "output_tokens": 0,
            "cached_tokens": None,
            "estimated_cost": 0.0,
            "provider_request_id": None,
            "actual_model_name": "mock",
            "pricing_version": None,
            "attempts": 1,
        }

    async def generate_explanation(self, request: dict, request_id: str | None = None) -> dict:
        trace = request.get("deterministic_trace", {})
        steps = trace.get("steps", []) if isinstance(trace, dict) else (trace if isinstance(trace, list) else [])
        passed_checks = request.get("verification_summary", {}).get("passed_checks", request.get("passed_checks", []))
        request_id = _stable_request_id(request, request_id)
        self.last_metrics.update({"request_id": request_id, "provider_request_id": request_id, "attempts": 1})
        # Keep the legacy shape available to old unit callers that did not
        # provide a v2 request.  Real explanation requests always carry v2.
        if request.get("schema_version") != "2":
            answer = request.get("answer_latex", "")
            return {
                "schema_version": "1",
                "answer_summary": {"display_latex": answer, "plain_text": answer},
                "problem_restatement": "根据已确认题干整理计算过程。",
                "knowledge_points": [{"id": request.get("problem_type", "math"), "name": request.get("problem_type", "math"), "explanation": "使用题目对应的确定性规则。"}],
                "steps": [{"index": i + 1, "title": step.get("operation", step.get("rule_id", "计算")), "explanation": "按照已生成的步骤整理。", "before_latex": step.get("before_latex", ""), "after_latex": step.get("after_latex", ""), "rule_id": step.get("rule_id", step.get("operation", ""))} for i, step in enumerate(steps)],
                "verification_explanation": [{"check_type": check, "explanation": "该检查已由独立验证器完成。"} for check in passed_checks],
                "common_mistakes": [{"type": "general_risk", "description": "注意保持运算规则和定义域条件。"}],
                "final_answer_latex": answer,
                "limitations": [],
            }
        return {
            "schema_version": SCHEMA_VERSION,
            "problem_restatement": "题干和数学步骤已由服务端确定，以下只说明这些步骤的含义。",
            "step_explanations": [{"index": step.get("index", i + 1), "title": "这一步做什么", "explanation": "按照该步已确定的数学规则变形，保持等式或不等式的语义。"} for i, step in enumerate(steps)],
            "knowledge_point_explanations": [{"knowledge_point_id": request.get("problem_type", "math"), "explanation": "重点是按给出的规则逐步保持数学关系。"}],
            "verification_explanations": [{"check_type": check, "explanation": "该检查由独立验证器完成，用于确认结果满足对应条件。"} for check in passed_checks],
            "common_mistakes": [{"type": "general_risk", "description": "这类题通常需要额外检查运算方向、端点和定义域。"}],
            "limitations": [],
        }


class DeepSeekExplanationProvider:
    def __init__(self):
        self.last_metrics: dict[str, Any] = {}

    @staticmethod
    def _retry_delay(attempt: int) -> float:
        # Bounded jitter avoids synchronized retries while keeping tests fast.
        return min(4.0, 0.25 * (2**attempt)) + random.uniform(0.0, 0.15)

    @staticmethod
    def _usage_metrics(body: dict[str, Any], response: Any, request_id: str, duration_ms: int, attempts: int) -> dict[str, Any]:
        usage = body.get("usage") if isinstance(body.get("usage"), dict) else {}
        input_tokens = usage.get("prompt_tokens", usage.get("input_tokens"))
        output_tokens = usage.get("completion_tokens", usage.get("output_tokens"))
        cached_tokens = usage.get("cached_tokens", usage.get("prompt_cache_hit_tokens"))
        estimated_cost = None
        if isinstance(input_tokens, int) and isinstance(output_tokens, int) and config.MATH_EXPLANATION_INPUT_PRICE_PER_MILLION is not None and config.MATH_EXPLANATION_OUTPUT_PRICE_PER_MILLION is not None:
            estimated_cost = input_tokens / 1_000_000 * config.MATH_EXPLANATION_INPUT_PRICE_PER_MILLION + output_tokens / 1_000_000 * config.MATH_EXPLANATION_OUTPUT_PRICE_PER_MILLION
        headers = getattr(response, "headers", {}) or {}
        provider_request_id = headers.get("x-request-id") or headers.get("X-Request-ID") or headers.get("request-id") or headers.get("Request-ID") or body.get("id") or request_id
        return {
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "cached_tokens": cached_tokens,
            "estimated_cost": estimated_cost,
            "provider_request_id": provider_request_id,
            "actual_model_name": body.get("model") or config.MATH_EXPLANATION_MODEL,
            "pricing_version": config.MATH_EXPLANATION_PRICING_VERSION,
            "duration_ms": duration_ms,
            "request_id": request_id,
            "attempts": attempts,
        }

    async def generate_explanation(self, request: dict, request_id: str | None = None) -> dict:
        request_id = _stable_request_id(request, request_id)
        if not config.MATH_EXPLANATION_API_KEY:
            self.last_metrics = {
                "request_id": request_id,
                "provider_request_id": None,
                "actual_model_name": config.MATH_EXPLANATION_MODEL,
                "pricing_version": config.MATH_EXPLANATION_PRICING_VERSION,
                "attempts": 0,
                "input_tokens": None,
                "output_tokens": None,
                "cached_tokens": None,
                "estimated_cost": None,
            }
            raise ExplanationProviderError("PROVIDER_API_KEY_MISSING")
        payload = {
            "model": config.MATH_EXPLANATION_MODEL,
            "temperature": config.MATH_EXPLANATION_TEMPERATURE,
            "max_tokens": config.MATH_EXPLANATION_MAX_TOKENS,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": json.dumps(request, ensure_ascii=False, separators=(",", ":"))},
            ],
            "response_format": {"type": "json_object"},
        }
        headers = {"Authorization": f"Bearer {config.MATH_EXPLANATION_API_KEY}", "Content-Type": "application/json", "X-Request-ID": request_id}
        started = time.monotonic()
        deadline = started + config.MATH_EXPLANATION_TOTAL_TIMEOUT
        attempts = 0
        last_error: ExplanationProviderError | None = None
        while attempts <= config.MATH_EXPLANATION_MAX_RETRIES:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                last_error = ExplanationProviderError("PROVIDER_TIMEOUT", retryable=False)
                break
            attempts += 1
            try:
                timeout = httpx.Timeout(
                    min(config.MATH_EXPLANATION_TOTAL_TIMEOUT, remaining),
                    connect=min(config.MATH_EXPLANATION_CONNECT_TIMEOUT, remaining),
                    read=min(config.MATH_EXPLANATION_READ_TIMEOUT, remaining),
                    write=min(config.MATH_EXPLANATION_WRITE_TIMEOUT, remaining),
                    pool=min(config.MATH_EXPLANATION_CONNECT_TIMEOUT, remaining),
                )
                async with httpx.AsyncClient(timeout=timeout) as client:
                    response = await client.post(config.MATH_EXPLANATION_BASE_URL.rstrip("/") + "/chat/completions", json=payload, headers=headers)
                content_bytes = getattr(response, "content", None)
                if content_bytes is None:
                    content_bytes = getattr(response, "text", "")
                if isinstance(content_bytes, str):
                    content_bytes = content_bytes.encode()
                if len(content_bytes) > config.MATH_EXPLANATION_MAX_RESPONSE_BYTES:
                    raise ExplanationProviderError("MODEL_RESPONSE_TOO_LARGE")
                status_code = int(getattr(response, "status_code", 0))
                if status_code != 200:
                    retryable = status_code == 429 or 500 <= status_code <= 599
                    raise ExplanationProviderError(f"PROVIDER_HTTP_{status_code}", retryable=retryable)
                try:
                    body = response.json()
                except (ValueError, TypeError) as error:
                    raise ExplanationProviderError("MODEL_RESPONSE_NOT_JSON") from error
                if not isinstance(body, dict):
                    raise ExplanationProviderError("MODEL_RESPONSE_SCHEMA_INVALID")
                try:
                    content = body["choices"][0]["message"]["content"]
                except (KeyError, IndexError, TypeError) as error:
                    raise ExplanationProviderError("MODEL_RESPONSE_SCHEMA_INVALID") from error
                result = parse_model_json(content)
                self.last_metrics = self._usage_metrics(body, response, request_id, int((time.monotonic() - started) * 1000), attempts)
                return result
            except ExplanationProviderError as error:
                last_error = error
                if not error.retryable or attempts > config.MATH_EXPLANATION_MAX_RETRIES:
                    break
            except httpx.TimeoutException as error:
                last_error = ExplanationProviderError("PROVIDER_TIMEOUT", retryable=True)
                if attempts > config.MATH_EXPLANATION_MAX_RETRIES:
                    break
            except httpx.HTTPError as error:
                last_error = ExplanationProviderError("PROVIDER_NETWORK_ERROR", retryable=True)
                if attempts > config.MATH_EXPLANATION_MAX_RETRIES:
                    break
            delay = self._retry_delay(attempts - 1)
            remaining = deadline - time.monotonic()
            if remaining <= delay:
                last_error = ExplanationProviderError("PROVIDER_TIMEOUT", retryable=False)
                break
            await asyncio.sleep(delay)
        error = last_error or ExplanationProviderError("PROVIDER_FAILED")
        self.last_metrics = {
            "duration_ms": int((time.monotonic() - started) * 1000),
            "request_id": request_id,
            "provider_request_id": request_id,
            "attempts": attempts,
            "input_tokens": None,
            "output_tokens": None,
            "cached_tokens": None,
            "estimated_cost": None,
            "pricing_version": config.MATH_EXPLANATION_PRICING_VERSION,
        }
        raise error


def explanation_provider():
    return DeepSeekExplanationProvider() if config.MATH_EXPLANATION_PROVIDER == "deepseek" else MockExplanationProvider()
