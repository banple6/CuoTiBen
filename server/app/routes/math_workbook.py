"""Review-first math workbook API. It is intentionally separate from /api/document/parse."""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import tempfile
import time
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, Depends, File, Header, HTTPException, UploadFile
from pydantic import BaseModel, ConfigDict, Field

from app import config
from app.math_workbook.service import MathWorkbookService
from app.math_workbook.storage import IdempotencyConflict, MathWorkbookStore, ParseEligibilityError, RevisionConflict
from app.math_workbook.explanation.provider import explanation_provider, ExplanationProviderError
from app.math_workbook.explanation.validator import validate_explanation

router = APIRouter(prefix="/api/v1", tags=["math-workbook"])


def _get_store() -> MathWorkbookStore:
    try:
        return MathWorkbookStore(config.MATH_WORKBOOK_DB_PATH, config.MATH_WORKBOOK_STORAGE_ROOT)
    except RuntimeError as error:
        raise HTTPException(503, detail="MATH_DATABASE_UNAVAILABLE") from error


def _get_service() -> MathWorkbookService:
    return MathWorkbookService(_get_store())


def _public_error_code(error: Exception, fallback: str = "MATH_REQUEST_REJECTED") -> str:
    """Expose stable error codes, never arbitrary internal exception text."""

    candidate = getattr(error, "code", None)
    if not isinstance(candidate, str):
        candidate = str(error).strip()
    try:
        payload = json.loads(candidate)
    except (TypeError, json.JSONDecodeError):
        payload = None
    if isinstance(payload, dict):
        reasons = payload.get("blocking_reasons")
        candidate = next((item for item in reasons if isinstance(item, str)), fallback) if isinstance(reasons, list) else fallback
    if isinstance(candidate, str) and re.fullmatch(r"[A-Z][A-Z0-9_]{2,80}", candidate):
        return candidate
    return fallback


def _public_explanation(row: dict) -> dict:
    return {
        "id": row["id"],
        "problem_id": row["problem_id"],
        "verification_report_id": row["verification_report_id"],
        "input_source_revision": row["input_source_revision"],
        "provider": row["provider"],
        "model": row["model_name"],
        "model_name": row["model_name"],
        "model_version": row["model_version"],
        "prompt_id": row["prompt_id"],
        "prompt_version": row["prompt_version"],
        "schema_version": row["schema_version"],
        "trace_version": row.get("trace_version"),
        "renderer_version": row.get("renderer_version"),
        "status": row["status"],
        "validated_explanation_json": row.get("validated_explanation_json") if row["status"] == "validated" else None,
        "quality": row.get("quality_json") if row["status"] == "validated" else None,
        "error_code": row.get("error_code"),
        "usage": {
            "input_tokens": row.get("input_tokens"),
            "output_tokens": row.get("output_tokens"),
            "cached_tokens": row.get("cached_tokens"),
            "estimated_cost": row.get("estimated_cost"),
            "attempts": row.get("attempts"),
            "provider_request_id": row.get("provider_request_id"),
            "actual_model_name": row.get("actual_model_name"),
            "pricing_version": row.get("pricing_version"),
        },
        "input_tokens": row.get("input_tokens"),
        "output_tokens": row.get("output_tokens"),
        "estimated_cost": row.get("estimated_cost"),
        "duration_ms": row.get("duration_ms"),
        "cache_hit": bool(row.get("cache_hit", 0)),
        "created_at": row["created_at"],
    }


class RegionPatch(BaseModel):
    region_type: str | None = None
    reading_order: int | None = None
    requires_review: bool | None = None
    review_reasons: list[str] | None = None


class FormulaPatch(BaseModel):
    user_confirmed_latex: str | None = Field(default=None, max_length=20_000)
    source_type: str | None = None
    role: str | None = None
    reading_order: int | None = None


class ProblemSource(BaseModel):
    source_kind: str
    source_id: str
    semantic_role: str
    reading_order: int


class ProblemCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    import_id: str
    page_id: str
    problem_bbox: list[float]
    sources: list[ProblemSource]
    problem_type_hint: str | None = None
    requires_review: bool = False
    review_reasons: list[str] = Field(default_factory=list)
    variable_domains: dict[str, str] = Field(default_factory=dict)


class ProblemPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")

    expected_revision: int
    problem_bbox: list[float] | None = None
    problem_type_hint: str | None = None
    requires_review: bool | None = None
    review_reasons: list[str] | None = None
    variable_domains: dict[str, str] | None = None
    sources: list[ProblemSource] | None = None


class ParseRequest(BaseModel):
    expected_revision: int


class SolveRequest(BaseModel):
    expected_revision: int


class VerificationRequest(BaseModel):
    expected_revision: int


class TeachingProfile(BaseModel):
    model_config = ConfigDict(extra="forbid")

    language: Literal["zh-CN", "en-US"] = "zh-CN"
    level: Literal["beginner", "intermediate", "advanced"] = "beginner"
    detail: Literal["brief", "detailed"] = "detailed"


class ExplanationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    expected_revision: int
    teaching_profile: TeachingProfile = Field(default_factory=TeachingProfile)


def require_math_user(x_user_id: str | None = Header(default=None, alias="X-User-Id")) -> str:
    """Resolve the one temporary math identity boundary used by every route."""

    if not config.MATH_ALLOW_DEV_USER_HEADER:
        raise HTTPException(status_code=401, detail="MATH_AUTH_REQUIRED")
    user_id = (x_user_id or "").strip()
    if not user_id or user_id.lower() == "anonymous":
        raise HTTPException(status_code=401, detail="MATH_USER_REQUIRED")
    return user_id


def public_payload(value):
    """Database paths are server implementation details, never API output."""
    if isinstance(value, list):
        return [public_payload(item) for item in value]
    if isinstance(value, dict):
        return {key: public_payload(item) for key, item in value.items() if not key.endswith("_path")}
    return value


@router.post("/math-imports")
async def create_math_import(file: UploadFile = File(...), source_type: str = "image", user_id: str = Depends(require_math_user), idempotency_key: str | None = Header(default=None, alias="Idempotency-Key")):
    suffix = Path(file.filename or "upload.jpg").suffix or ".jpg"
    with tempfile.TemporaryDirectory(prefix="cuotiben-math-") as temporary_dir:
        temp_path = Path(temporary_dir) / f"upload{suffix}"
        with temp_path.open("wb") as output:
            shutil.copyfileobj(file.file, output)
        if temp_path.stat().st_size > config.MAX_UPLOAD_SIZE:
            raise HTTPException(413, "文件过大")
        record = None
        if idempotency_key:
            body = {"source_type": source_type, "filename": file.filename or "", "source_sha256": hashlib.sha256(temp_path.read_bytes()).hexdigest()}
            try:
                record = _get_store().reserve_idempotency(user_id, "math_import", idempotency_key, body)
            except IdempotencyConflict as error:
                raise HTTPException(409, detail="IDEMPOTENCY_CONFLICT") from error
            if record.get("resource_id"):
                prior = _get_store().get_import(record["resource_id"], user_id)
                if prior:
                    return public_payload(prior)
            if record.get("status") == "processing" and not record.get("created"):
                return {"job_status": "processing"}
        try:
            result = await _get_service().import_page(temp_path, file.filename or temp_path.name, source_type, user_id)
        except ValueError as error:
            raise HTTPException(422, detail=_public_error_code(error, "MATH_IMPORT_REJECTED")) from error
    if record:
        _get_store().finish_idempotency(record["id"], 201, "math_import", result["id"], result)
    return public_payload(result)


@router.get("/math-imports/{import_id}")
async def get_math_import(import_id: str, user_id: str = Depends(require_math_user)):
    result = _get_store().get_import(import_id, user_id)
    if not result:
        raise HTTPException(404, "数学导入不存在")
    return public_payload(result)


@router.delete("/math-imports/{import_id}")
async def delete_math_import(import_id: str, user_id: str = Depends(require_math_user)):
    try:
        return _get_store().delete_import(import_id, user_id)
    except KeyError as error:
        raise HTTPException(404, "数学导入不存在") from error
    except ValueError as error:
        raise HTTPException(401, detail="MATH_USER_REQUIRED") from error


@router.get("/math-pages/{page_id}")
async def get_math_page(page_id: str, user_id: str = Depends(require_math_user)):
    result = _get_store().get_page(page_id, user_id)
    if not result:
        raise HTTPException(404, "页面不存在")
    return public_payload(result)


@router.post("/math-pages/{page_id}/segment")
async def segment_math_page(page_id: str, user_id: str = Depends(require_math_user)):
    """Segmentation is performed at import time in phase one; returns durable evidence."""
    return await get_math_page(page_id, user_id)


@router.post("/math-pages/{page_id}/recognize")
async def recognize_math_page(page_id: str, user_id: str = Depends(require_math_user)):
    """Recognition candidates are persisted at import time; later adapters may re-run here."""
    return await get_math_page(page_id, user_id)


@router.patch("/math-regions/{region_id}")
async def patch_math_region(region_id: str, patch: RegionPatch, user_id: str = Depends(require_math_user)):
    try:
        result = _get_store().update_region(region_id, patch.model_dump(exclude_none=True), user_id)
    except ValueError as error:
        raise HTTPException(422, detail=_public_error_code(error, "MATH_REGION_REJECTED")) from error
    except KeyError as error:
        raise HTTPException(404, "区域不存在") from error
    if not result:
        raise HTTPException(404, "区域不存在")
    return public_payload(result)


@router.patch("/math-formulas/{formula_id}")
async def patch_math_formula(formula_id: str, patch: FormulaPatch, user_id: str = Depends(require_math_user)):
    try:
        result = _get_store().update_formula(formula_id, patch.model_dump(exclude_none=True), user_id)
    except ValueError as error:
        raise HTTPException(422, detail=_public_error_code(error, "MATH_FORMULA_REJECTED")) from error
    except KeyError as error:
        raise HTTPException(404, "公式不存在") from error
    return public_payload(result)


@router.post("/math-problems")
async def create_math_problem(payload: ProblemCreate, user_id: str = Depends(require_math_user)):
    try:
        result = _get_store().create_problem(
            user_id,
            payload.import_id,
            payload.page_id,
            payload.problem_bbox,
            [item.model_dump() for item in payload.sources],
            **payload.model_dump(exclude={"import_id", "page_id", "problem_bbox", "sources"}),
        )
        return public_payload(result)
    except PermissionError as error:
        raise HTTPException(403, detail="RESOURCE_FORBIDDEN") from error
    except ValueError as error:
        raise HTTPException(422, detail=_public_error_code(error, "MATH_PROBLEM_REJECTED")) from error


@router.get("/math-problems/{problem_id}")
async def get_math_problem(problem_id: str, user_id: str = Depends(require_math_user)):
    result = _get_store().get_problem(problem_id, user_id)
    if not result:
        raise HTTPException(404, "题目不存在")
    return public_payload(result)


@router.delete("/math-problems/{problem_id}")
async def delete_math_problem(problem_id: str, user_id: str = Depends(require_math_user)):
    try:
        return _get_store().delete_problem(problem_id, user_id)
    except KeyError as error:
        raise HTTPException(404, "题目不存在") from error
    except ValueError as error:
        raise HTTPException(401, detail="MATH_USER_REQUIRED") from error


@router.delete("/math-account")
async def delete_math_account(user_id: str = Depends(require_math_user)):
    try:
        return _get_store().delete_user_data(user_id)
    except ValueError as error:
        raise HTTPException(401, detail="MATH_USER_REQUIRED") from error


@router.patch("/math-problems/{problem_id}")
async def patch_math_problem(problem_id: str, payload: ProblemPatch, user_id: str = Depends(require_math_user)):
    try:
        return _get_store().update_problem(problem_id, user_id, payload.expected_revision, payload.model_dump(exclude_none=True, exclude={"expected_revision"}))
    except KeyError as error:
        raise HTTPException(404, "题目不存在") from error
    except RevisionConflict as error:
        raise HTTPException(409, detail="REVISION_CONFLICT") from error
    except PermissionError as error:
        raise HTTPException(403, detail="RESOURCE_FORBIDDEN") from error
    except ValueError as error:
        raise HTTPException(422, detail=_public_error_code(error, "MATH_PROBLEM_REJECTED")) from error


@router.post("/math-problems/{problem_id}/parse")
async def parse_math_problem(problem_id: str, payload: ParseRequest, user_id: str = Depends(require_math_user)):
    try:
        return _get_store().parse_problem(problem_id, user_id, payload.expected_revision)
    except KeyError as error:
        raise HTTPException(404, "题目不存在") from error
    except ParseEligibilityError as error:
        raise HTTPException(409, detail=_public_error_code(error, "PARSE_NOT_ELIGIBLE")) from error


@router.get("/math-problems/{problem_id}/ir")
async def get_math_ir(problem_id: str, user_id: str = Depends(require_math_user)):
    result = _get_store().current_parse(problem_id, user_id)
    if not result:
        raise HTTPException(404, "没有当前有效的解析结果")
    return result


@router.post("/math-problems/{problem_id}/solve")
async def solve_math_problem(problem_id: str, payload: SolveRequest, user_id: str = Depends(require_math_user)):
    try:
        result = _get_store().solve_problem(problem_id, user_id, payload.expected_revision)
        return {**result, "verification_status": "not_started", "is_verified": False, "execution": {"mode": result.get("execution_mode", "isolated_process"), "timed_out": bool(result.get("timed_out", False))}}
    except KeyError as error:
        raise HTTPException(404, "题目不存在") from error
    except ValueError as error:
        raise HTTPException(409, detail=_public_error_code(error, "SOLVE_NOT_ELIGIBLE")) from error


@router.get("/math-problems/{problem_id}/solution")
async def get_math_solution(problem_id: str, user_id: str = Depends(require_math_user)):
    try:
        result = _get_store().current_candidate_solution(problem_id, user_id)
    except KeyError as error:
        raise HTTPException(404, "题目不存在") from error
    if not result:
        if not _get_store().get_problem(problem_id, user_id):
            raise HTTPException(404, "题目不存在")
        return {"current_result": None, "historical_results": [], "verification_status": "not_started", "is_verified": False}
    return {"current_result": result, "verification_status": "not_started", "is_verified": False}


@router.post("/math-problems/{problem_id}/verify")
async def verify_math_problem(problem_id: str, payload: VerificationRequest, user_id: str = Depends(require_math_user)):
    try:
        result = _get_store().verify_problem(problem_id, user_id, payload.expected_revision)
        return {**result, "is_verified": result["status"] == "verified"}
    except KeyError as error:
        raise HTTPException(404, "题目不存在") from error
    except ValueError as error:
        raise HTTPException(409, detail=_public_error_code(error, "VERIFICATION_NOT_ELIGIBLE")) from error


@router.get("/math-problems/{problem_id}/verification")
async def get_math_verification(problem_id: str, user_id: str = Depends(require_math_user)):
    try:
        result = _get_store().current_verification(problem_id, user_id)
    except KeyError as error:
        raise HTTPException(404, "题目不存在") from error
    if not result:
        if not _get_store().get_problem(problem_id, user_id):
            raise HTTPException(404, "题目不存在")
        return {"current_report": None, "historical_reports": [], "is_verified": False}
    return {"current_report": result, "is_verified": result["status"] == "verified"}


@router.post("/math-problems/{problem_id}/explanation")
async def create_math_explanation(problem_id: str, payload: ExplanationRequest, user_id: str = Depends(require_math_user)):
    store = _get_store()
    try:
        prepared = store.prepare_explanation(
            problem_id,
            user_id,
            payload.expected_revision,
            payload.teaching_profile.model_dump(),
        )
    except KeyError as error:
        raise HTTPException(404, "题目不存在") from error
    except ValueError as error:
        raise HTTPException(409, detail=_public_error_code(error, "EXPLANATION_NOT_ELIGIBLE")) from error

    started = time.monotonic()
    provider = explanation_provider()
    raw: dict = {}
    validated = None
    status = "failed"
    errors: list[dict[str, str]] = []
    try:
        raw = await provider.generate_explanation(prepared["input"], prepared["request_id"])
        validated = validate_explanation(raw, prepared["input"])
        validated["final_answer_latex"] = prepared["answer_latex"]
        if isinstance(validated.get("answer_summary"), dict):
            validated["answer_summary"]["display_latex"] = prepared["answer_latex"]
        status = "validated"
    except (ExplanationProviderError, ValueError, TypeError) as error:
        code = _public_error_code(error, type(error).__name__.upper())
        errors = [{"code": code}]
        if code == "PROVIDER_TIMEOUT":
            status = "timeout"
        elif code.startswith("MODEL_RESPONSE_") or not isinstance(error, ExplanationProviderError):
            status = "rejected"

    metrics = {
        **getattr(provider, "last_metrics", {}),
        "duration_ms": int((time.monotonic() - started) * 1000),
    }
    result = store.persist_explanation(
        prepared,
        config.MATH_EXPLANATION_PROVIDER,
        config.MATH_EXPLANATION_MODEL,
        config.MATH_EXPLANATION_MODEL_VERSION,
        raw,
        validated,
        status,
        errors,
        metrics,
    )
    current = result["status"] == "validated" and result.get("input_source_revision") == prepared["gate"]["source_revision"]
    public = _public_explanation(result)
    return {
        "status": result["status"],
        "provider": public["provider"],
        "model": public["model"],
        "prompt_version": public["prompt_version"],
        "schema_version": public["schema_version"],
        "trace_version": public["trace_version"],
        "renderer_version": public["renderer_version"],
        "quality": public["quality"],
        "usage": public["usage"],
        "explanation": result.get("validated_explanation_json") if current else None,
        "artifact": public,
        "is_verified": current,
        "verification_status": "verified" if current else "stale",
    }


@router.get("/math-problems/{problem_id}/explanation")
async def get_math_explanation(problem_id: str, user_id: str = Depends(require_math_user)):
    try:
        result = _get_store().current_explanation(problem_id, user_id)
    except KeyError as error:
        raise HTTPException(404, "题目不存在") from error
    if not result:
        return {"current_explanation": None, "historical_explanations": []}
    return {"current_explanation": _public_explanation(result), "historical_explanations": []}


@router.post("/math-problems/{problem_id}/build")
async def build_math_problem(problem_id: str, user_id: str = Depends(require_math_user)):
    try:
        return _get_store().build_problem(problem_id, user_id)
    except KeyError as error:
        raise HTTPException(404, "题目不存在") from error
    except ValueError as error:
        raise HTTPException(409, detail=_public_error_code(error, "BUILD_NOT_ELIGIBLE")) from error


@router.get("/math-problems/{problem_id}/build")
async def get_math_build(problem_id: str, user_id: str = Depends(require_math_user)):
    result = _get_store().current_build(problem_id, user_id)
    if not result:
        raise HTTPException(404, "没有当前有效的构造结果")
    return result


@router.post("/math-problems/{problem_id}/analyze")
async def analyze_math_problem(problem_id: str, user_id: str = Depends(require_math_user)):
    try:
        return _get_store().analyze_problem(problem_id, user_id)
    except KeyError as error:
        raise HTTPException(404, "题目不存在") from error
    except ValueError as error:
        raise HTTPException(409, detail=_public_error_code(error, "ANALYSIS_NOT_ELIGIBLE")) from error


@router.get("/math-problems/{problem_id}/analysis")
async def get_math_analysis(problem_id: str, user_id: str = Depends(require_math_user)):
    result = _get_store().current_analysis(problem_id, user_id)
    if not result:
        raise HTTPException(404, "没有当前有效的分析结果")
    return result
