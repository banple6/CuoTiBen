from __future__ import annotations

import asyncio
import json
import time
from typing import Protocol

import httpx

from app import config
from .prompt import SCHEMA_VERSION, SYSTEM_PROMPT


class ExplanationProviderError(Exception):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


class ExplanationModelProvider(Protocol):
    last_metrics: dict

    async def generate_explanation(self, request: dict, request_id: str | None = None) -> dict:
        ...


class MockExplanationProvider:
    def __init__(self):
        self.last_metrics = {"input_tokens": 0, "output_tokens": 0, "estimated_cost": 0.0}

    async def generate_explanation(self, request: dict, request_id: str | None = None) -> dict:
        answer = request["answer_latex"]
        rules = request["deterministic_trace"]
        passed_checks = request.get("passed_checks", request.get("verification_summary", {}).get("passed_checks", []))
        return {
            "schema_version": SCHEMA_VERSION,
            "answer_summary": {"display_latex": answer, "plain_text": answer},
            "problem_restatement": "根据已确认题干整理计算过程。",
            "knowledge_points": [{"id": request["problem_type"], "name": request["problem_type"], "explanation": "使用题目对应的确定性规则。"}],
            "steps": [
                {"index": i + 1, "title": step.get("operation", "计算"), "explanation": "按照已验证的确定性步骤整理。", "before_latex": step.get("before_latex", ""), "after_latex": step.get("after_latex", ""), "rule_id": step.get("rule_id", step.get("operation", ""))}
                for i, step in enumerate(rules)
            ],
            "verification_explanation": [{"check_type": check, "explanation": "该检查已由独立验证器通过。"} for check in passed_checks],
            "common_mistakes": [{"type": "general_risk", "description": "注意保持运算规则和定义域条件。"}],
            "final_answer_latex": answer,
            "limitations": [],
        }


class DeepSeekExplanationProvider:
    def __init__(self):
        self.last_metrics: dict = {}

    async def generate_explanation(self, request: dict, request_id: str | None = None) -> dict:
        payload = {
            "model": config.MATH_EXPLANATION_MODEL,
            "temperature": config.MATH_EXPLANATION_TEMPERATURE,
            "max_tokens": config.MATH_EXPLANATION_MAX_TOKENS,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": json.dumps(request, ensure_ascii=False)},
            ],
            "response_format": {"type": "json_object"},
        }
        headers = {"Authorization": f"Bearer {config.MATH_EXPLANATION_API_KEY}", "Content-Type": "application/json"}
        if request_id:
            headers["X-Request-ID"] = request_id
        last: Exception | None = None
        started = time.monotonic()
        deadline = started + config.MATH_EXPLANATION_TOTAL_TIMEOUT
        for attempt in range(config.MATH_EXPLANATION_MAX_RETRIES + 1):
            try:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise ExplanationProviderError("PROVIDER_TIMEOUT")
                timeout = httpx.Timeout(
                    min(config.MATH_EXPLANATION_TOTAL_TIMEOUT, remaining),
                    connect=min(config.MATH_EXPLANATION_CONNECT_TIMEOUT, remaining),
                    read=min(config.MATH_EXPLANATION_READ_TIMEOUT, remaining),
                    write=min(config.MATH_EXPLANATION_WRITE_TIMEOUT, remaining),
                    pool=min(config.MATH_EXPLANATION_CONNECT_TIMEOUT, remaining),
                )
                async with httpx.AsyncClient(timeout=timeout) as client:
                    response = await client.post(config.MATH_EXPLANATION_BASE_URL.rstrip("/") + "/chat/completions", json=payload, headers=headers)
                if len(response.content) > config.MATH_EXPLANATION_MAX_RESPONSE_BYTES:
                    raise ExplanationProviderError("PROVIDER_RESPONSE_TOO_LARGE")
                if response.status_code in {429, 500, 502, 503, 504} and attempt < config.MATH_EXPLANATION_MAX_RETRIES and time.monotonic() < deadline:
                    await asyncio.sleep(min(2**attempt, 4))
                    continue
                if response.status_code != 200:
                    raise ExplanationProviderError(f"PROVIDER_HTTP_{response.status_code}")
                body = response.json()
                content = body["choices"][0]["message"]["content"]
                data = json.loads(content)
                usage = body.get("usage", {})
                self.last_metrics = {
                    "input_tokens": usage.get("prompt_tokens", usage.get("input_tokens")),
                    "output_tokens": usage.get("completion_tokens", usage.get("output_tokens")),
                    "estimated_cost": None,
                    "duration_ms": int((time.monotonic() - started) * 1000),
                    "request_id": request_id,
                }
                return data
            except httpx.TimeoutException as error:
                last = ExplanationProviderError("PROVIDER_TIMEOUT")
                if attempt >= config.MATH_EXPLANATION_MAX_RETRIES:
                    break
                await asyncio.sleep(min(2**attempt, 4))
            except (httpx.HTTPError, KeyError, TypeError, ValueError, ExplanationProviderError) as error:
                last = error
                if attempt >= config.MATH_EXPLANATION_MAX_RETRIES:
                    break
        code = last.code if isinstance(last, ExplanationProviderError) else type(last).__name__ if last else "PROVIDER_FAILED"
        self.last_metrics = {"duration_ms": int((time.monotonic() - started) * 1000), "request_id": request_id}
        raise ExplanationProviderError(code)


def explanation_provider():
    return DeepSeekExplanationProvider() if config.MATH_EXPLANATION_PROVIDER == "deepseek" else MockExplanationProvider()
