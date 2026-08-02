"""Versioned prompts and schema metadata for verified-math teaching."""

from __future__ import annotations

import hashlib
from datetime import datetime, timezone


PROMPT_ID = "verified-math-teaching"
PROMPT_VERSION = "2"
SCHEMA_VERSION = "2"
TRACE_VERSION = "1"
RENDERER_VERSION = "1"

# Kept for reading old MathExplanation rows.  New requests never use this
# prompt, but its identity remains stable for historical audit data.
LEGACY_PROMPT_VERSION = "1"
LEGACY_SCHEMA_VERSION = "1"
LEGACY_SYSTEM_PROMPT = (
    "你是数学教学讲解整理器，不是求解器。数学答案只能来自 verified_result，"
    "不得重新计算、修改或质疑它。只能根据 deterministic_trace 组织步骤；"
    "信息不足时返回 limitations，不得补算。不得声称读取手写步骤或诊断学生真实错因。"
    "输出严格 JSON，不输出新的答案、变式题或 verified/rejected 状态。"
)

SYSTEM_PROMPT = """你是已验证数学工件的教学语言整理器，不是数学求解器。
答案、变量、确定性步骤、before_latex、after_latex、rule_id、verification check 和数学状态已经由服务端数学引擎生成并验证。
你不得重新计算、修改、质疑或补充任何数学结论；只能逐条解释输入 deterministic_trace 中已有的步骤。
step_explanations 的数量必须与 deterministic_trace.steps 完全一致，index 必须逐一匹配；不得增加、删除、重排或改写步骤。
不得增加变量、答案、数学表达式、rule_id、check_type、验证状态或 AST；不得输出 before_latex、after_latex 或 final_answer_latex。
不得声称看过手写过程，不得把常见易错点写成用户确定犯过的错误，不得生成变式题。
信息不足时只能在 limitations 中说明，不得猜测；只输出符合 Schema v2 的纯 JSON，不输出 Markdown 代码围栏或内部推理过程。"""

PROMPT_CONTENT_HASH = hashlib.sha256(SYSTEM_PROMPT.encode("utf-8")).hexdigest()
LEGACY_PROMPT_CONTENT_HASH = hashlib.sha256(LEGACY_SYSTEM_PROMPT.encode("utf-8")).hexdigest()
# The creation timestamp is metadata, not a prompt input.  A stable process
# value prevents two requests in one process from changing the input hash.
PROMPT_CREATED_AT = datetime.now(timezone.utc).isoformat()


def prompt_metadata(version: str = PROMPT_VERSION) -> dict[str, str]:
    if version == LEGACY_PROMPT_VERSION:
        return {
            "prompt_id": PROMPT_ID,
            "prompt_version": LEGACY_PROMPT_VERSION,
            "content_hash": LEGACY_PROMPT_CONTENT_HASH,
            "created_at": PROMPT_CREATED_AT,
        }
    return {
        "prompt_id": PROMPT_ID,
        "prompt_version": PROMPT_VERSION,
        "content_hash": PROMPT_CONTENT_HASH,
        "created_at": PROMPT_CREATED_AT,
    }
