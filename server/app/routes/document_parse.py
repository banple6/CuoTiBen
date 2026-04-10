"""
文档解析路由 — POST /api/document/parse

iOS 上传格式: multipart/form-data
    - file:         二进制文件
    - document_id:  UUID 字符串
    - title:        文档标题
    - file_type:    "PDF" / "Image" / "Scan"
"""

from __future__ import annotations

import logging
import time
import uuid

from fastapi import APIRouter, File, Form, HTTPException, UploadFile

from app import config
from app.models.normalized_document import DocumentParseResponse
from app.services.ai_studio_client import AIStudioError, call_pp_structure_v3
from app.services.normalizer import normalize

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post(
    "/api/document/parse",
    response_model=DocumentParseResponse,
    summary="上传文档并解析（同步）",
)
async def parse_document(
    file: UploadFile = File(...),
    document_id: str = Form(default=""),
    title: str = Form(default=""),
    file_type: str = Form(default=""),
):
    """
    接收 iOS 上传的 PDF/图片，转发到 AI Studio PP-StructureV3，
    归一化后以 NormalizedDocument 格式返回。
    """
    # 读取上传文件
    file_bytes = await file.read()
    if len(file_bytes) > config.MAX_UPLOAD_SIZE:
        raise HTTPException(
            status_code=413,
            detail=f"文件过大，最大允许 {config.MAX_UPLOAD_SIZE // (1024*1024)}MB",
        )
    if not file_bytes:
        raise HTTPException(status_code=400, detail="上传文件为空")

    doc_id = document_id or str(uuid.uuid4())
    doc_title = title or (file.filename or "untitled")
    file_name = file.filename or "upload.pdf"

    logger.info(
        "收到解析请求  doc_id=%s  title=%s  size=%dKB  file_type=%s",
        doc_id, doc_title, len(file_bytes) // 1024, file_type,
    )

    t0 = time.monotonic()

    try:
        # 1) 调用 AI Studio
        raw_result = await call_pp_structure_v3(file_bytes, file_name)

        # 2) 归一化
        document = normalize(
            raw=raw_result,
            document_id=doc_id,
            title=doc_title,
            file_type=file_type or "PDF",
        )

        elapsed_ms = int((time.monotonic() - t0) * 1000)
        logger.info("解析完成  doc_id=%s  总耗时=%dms", doc_id, elapsed_ms)

        return DocumentParseResponse(
            success=True,
            job_id=doc_id,
            status="completed",
            document=document,
            error=None,
        )

    except AIStudioError as e:
        logger.error("AI Studio 调用失败: %s", e)
        return DocumentParseResponse(
            success=False,
            job_id=doc_id,
            status="failed",
            document=None,
            error=f"AI Studio 错误: {e}",
        )
    except Exception as e:
        logger.exception("解析异常: %s", e)
        return DocumentParseResponse(
            success=False,
            job_id=doc_id,
            status="failed",
            document=None,
            error=f"服务器内部错误: {type(e).__name__}",
        )


@router.get(
    "/api/document/parse/{job_id}",
    response_model=DocumentParseResponse,
    summary="查询解析任务状态（预留）",
)
async def get_parse_status(job_id: str):
    """
    当前采用同步模式，此端点返回 completed 或 not_found。
    预留给将来的异步队列模式。
    """
    return DocumentParseResponse(
        success=False,
        job_id=job_id,
        status="completed",
        document=None,
        error="当前为同步模式，文档已在 POST 响应中返回",
    )
