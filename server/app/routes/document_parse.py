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
from fastapi.responses import JSONResponse

from app import config
from app.models.normalized_document import DocumentParseResponse
from app.services.ai_studio_client import AIStudioError, call_pp_structure_v3
from app.services.normalizer import normalize

logger = logging.getLogger(__name__)
router = APIRouter()


def _json_response(payload: DocumentParseResponse) -> JSONResponse:
    if hasattr(payload, "model_dump"):
        content = payload.model_dump(exclude_none=True)
    else:
        content = payload.dict(exclude_none=True)
    content["schema_version"] = config.SCHEMA_VERSION
    return JSONResponse(content=content)


# ── 质量拒绝原因码 ──
class QualityReason:
    EMPTY_RAW_RESULT = "pp_empty_raw_result"
    EMPTY_NORMALIZED_BLOCKS = "pp_empty_normalized_blocks"
    EMPTY_PARAGRAPHS = "pp_empty_paragraphs"
    EMPTY_CANDIDATES = "pp_empty_candidates"
    RESPONSE_SHAPE_UNRECOGNIZED = "pp_response_shape_unrecognized"


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
        "[PP-REQ] 收到解析请求  doc_id=%s  title=%s  size=%dKB  file_type=%s  "
        "normalizer=%s  schema=%s",
        doc_id, doc_title, len(file_bytes) // 1024, file_type,
        config.NORMALIZER_VERSION, config.SCHEMA_VERSION,
    )

    t0 = time.monotonic()

    try:
        # 1) 调用 AI Studio
        raw_result = await call_pp_structure_v3(file_bytes, file_name)

        # 诊断: raw 结果是否为空
        raw_top_keys = list(raw_result.keys()) if isinstance(raw_result, dict) else []
        if not raw_top_keys:
            elapsed_ms = int((time.monotonic() - t0) * 1000)
            logger.warning(
                "[PP-REQ] RESULT doc_id=%s  quality_reason=%s  elapsed=%dms",
                doc_id, QualityReason.EMPTY_RAW_RESULT, elapsed_ms,
            )
            return _json_response(DocumentParseResponse(
                schema_version=config.SCHEMA_VERSION,
                success=False,
                job_id=doc_id,
                status="failed",
                document=None,
                error="AI Studio 返回空结果",
                quality_reason=QualityReason.EMPTY_RAW_RESULT,
            ))

        # 2) 归一化
        document = normalize(
            raw=raw_result,
            document_id=doc_id,
            title=doc_title,
            file_type=file_type or "PDF",
        )

        elapsed_ms = int((time.monotonic() - t0) * 1000)

        # 结构化请求摘要日志
        logger.info(
            "[PP-REQ] RESULT doc_id=%s  blocks=%d  paragraphs=%d  candidates=%d  "
            "pages=%d  dominant_lang=%s  english_ratio=%.2f  elapsed=%dms  "
            "normalizer=%s  schema=%s",
            doc_id,
            len(document.blocks),
            len(document.paragraphs),
            len(document.structure_candidates),
            len(document.pages),
            document.metadata.dominant_language,
            document.metadata.english_ratio,
            elapsed_ms,
            config.NORMALIZER_VERSION,
            config.SCHEMA_VERSION,
        )

        # ── 质量检查链 ──
        quality_reason = None

        if len(document.blocks) == 0:
            quality_reason = QualityReason.EMPTY_NORMALIZED_BLOCKS
            logger.warning(
                "[PP-REQ] QUALITY_REJECTED doc_id=%s  reason=%s  raw_keys=%s  elapsed=%dms",
                doc_id, quality_reason, raw_top_keys, elapsed_ms,
            )
            return _json_response(DocumentParseResponse(
                schema_version=config.SCHEMA_VERSION,
                success=False,
                job_id=doc_id,
                status="failed",
                document=document,
                error=f"归一化结果异常: blocks=0 (raw_keys={raw_top_keys})",
                quality_reason=quality_reason,
            ))

        if len(document.paragraphs) == 0:
            quality_reason = QualityReason.EMPTY_PARAGRAPHS
            logger.warning(
                "[PP-REQ] QUALITY_WARNING doc_id=%s  reason=%s  blocks=%d",
                doc_id, quality_reason, len(document.blocks),
            )

        if len(document.structure_candidates) == 0:
            if quality_reason is None:
                quality_reason = QualityReason.EMPTY_CANDIDATES
            logger.warning(
                "[PP-REQ] QUALITY_WARNING doc_id=%s  reason=%s  blocks=%d  paragraphs=%d",
                doc_id, quality_reason or QualityReason.EMPTY_CANDIDATES,
                len(document.blocks), len(document.paragraphs),
            )

        return _json_response(DocumentParseResponse(
            schema_version=config.SCHEMA_VERSION,
            success=True,
            job_id=doc_id,
            status="completed",
            document=document,
            error=None,
            quality_reason=quality_reason,
        ))

    except AIStudioError as e:
        elapsed_ms = int((time.monotonic() - t0) * 1000)
        logger.error(
            "[PP-REQ] AI_STUDIO_ERROR doc_id=%s  error=%s  elapsed=%dms",
            doc_id, e, elapsed_ms,
        )
        return _json_response(DocumentParseResponse(
            schema_version=config.SCHEMA_VERSION,
            success=False,
            job_id=doc_id,
            status="failed",
            document=None,
            error=f"AI Studio 错误: {e}",
            quality_reason=None,
        ))
    except Exception as e:
        elapsed_ms = int((time.monotonic() - t0) * 1000)
        logger.exception(
            "[PP-REQ] SERVER_ERROR doc_id=%s  error=%s  elapsed=%dms",
            doc_id, e, elapsed_ms,
        )
        return _json_response(DocumentParseResponse(
            schema_version=config.SCHEMA_VERSION,
            success=False,
            job_id=doc_id,
            status="failed",
            document=None,
            error=f"服务器内部错误: {type(e).__name__}",
            quality_reason=None,
        ))


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
    return _json_response(DocumentParseResponse(
        schema_version=config.SCHEMA_VERSION,
        success=False,
        job_id=job_id,
        status="completed",
        document=None,
        error="当前为同步模式，文档已在 POST 响应中返回",
    ))
