"""
AI Studio PP-StructureV3 云推理客户端
所有 token 从环境变量读取，绝不硬编码
"""

from __future__ import annotations

import base64
import logging
import time
from typing import Any

import httpx

from app import config

logger = logging.getLogger(__name__)


async def call_pp_structure_v3(
    file_bytes: bytes,
    file_name: str,
) -> dict[str, Any]:
    """
    调用 AI Studio PP-StructureV3 云 API。

    请求格式:
        POST  AI_STUDIO_API_URL
        Header: Authorization: token <ACCESS_TOKEN>
        Body (JSON): { "file": "<base64>", "fileType": 1 }

    返回: AI Studio 原始 JSON 响应 (dict)
    """
    file_b64 = base64.b64encode(file_bytes).decode("ascii")

    # file_type 推断: 1=PDF, 2=图片
    ext = file_name.rsplit(".", 1)[-1].lower() if "." in file_name else ""
    file_type = 1 if ext == "pdf" else 2

    payload = {
        "file": file_b64,
        "fileType": file_type,
    }

    headers = {
        "Authorization": f"token {config.AI_STUDIO_ACCESS_TOKEN}",
        "Content-Type": "application/json",
    }

    t0 = time.monotonic()
    async with httpx.AsyncClient(timeout=config.AI_STUDIO_TIMEOUT) as client:
        resp = await client.post(
            config.AI_STUDIO_API_URL,
            json=payload,
            headers=headers,
        )

    elapsed_ms = int((time.monotonic() - t0) * 1000)
    logger.info(
        "AI Studio 调用完成  status=%s  耗时=%dms  文件=%s",
        resp.status_code,
        elapsed_ms,
        file_name,
    )

    if resp.status_code != 200:
        body_preview = resp.text[:500]
        raise AIStudioError(
            f"AI Studio 返回 HTTP {resp.status_code}: {body_preview}"
        )

    data = resp.json()

    # AI Studio 产线 API 通常用 errorCode==0 表示成功
    error_code = data.get("errorCode", data.get("error_code", 0))
    if error_code != 0:
        error_msg = data.get("errorMsg", data.get("error_msg", "未知"))
        raise AIStudioError(f"AI Studio 业务错误 code={error_code}: {error_msg}")

    return data


class AIStudioError(Exception):
    """AI Studio API 调用失败"""
