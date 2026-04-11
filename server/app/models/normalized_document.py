"""
Pydantic 模型 — 与 iOS NormalizedDocumentModels.swift 一一对应
"""

from __future__ import annotations
from typing import Optional
from pydantic import BaseModel, Field


# ── BoundingBox ──

class BoundingBox(BaseModel):
    x: float = 0.0
    y: float = 0.0
    width: float = 0.0
    height: float = 0.0


# ── NormalizedBlock ──

class NormalizedBlock(BaseModel):
    id: str
    page: int
    order: int
    bbox: BoundingBox
    block_type: str               # NormalizedBlockType rawValue
    zone_role: str = "unknown"    # "passage" / "question" / "answer_key" / "vocabulary_support" / "meta_instruction" / "unknown"
    sub_type: Optional[str] = None
    text: str
    language: str                  # "en" / "zh" / "mixed" / "unknown"
    confidence: float = 0.5
    paragraph_start: bool = False
    paragraph_end: bool = False
    source: str = "pp_structurev3"


# ── NormalizedPage ──

class NormalizedPage(BaseModel):
    page: int
    width: float = 0.0
    height: float = 0.0
    block_ids: list[str] = Field(default_factory=list)


# ── NormalizedParagraph ──

class NormalizedParagraph(BaseModel):
    id: str
    block_ids: list[str] = Field(default_factory=list)
    page: int = 1
    end_page: int = 1
    text: str = ""
    language: str = "unknown"
    zone_role: str = "unknown"
    cross_page: bool = False
    order: int = 0


# ── StructureCandidate ──

class StructureCandidate(BaseModel):
    id: str
    parent_id: Optional[str] = None
    depth: int = 0
    order: int = 0
    title: str = ""
    summary: Optional[str] = None
    block_ids: list[str] = Field(default_factory=list)
    paragraph_ids: list[str] = Field(default_factory=list)
    confidence: float = 0.5
    candidate_type: str = "section"   # "heading" / "section" / "paragraph"


# ── DocumentMetadata ──

class DocumentMetadata(BaseModel):
    title: str = ""
    file_type: str = ""
    page_count: int = 0
    total_blocks: int = 0
    total_paragraphs: int = 0
    dominant_language: str = "unknown"
    english_ratio: float = 0.0
    parse_engine: str = "pp_structurev3"
    parse_version: str = "1.0.0"
    parse_duration_ms: int = 0


# ── NormalizedDocument（顶级容器）──

class NormalizedDocument(BaseModel):
    document_id: str
    metadata: DocumentMetadata
    pages: list[NormalizedPage] = Field(default_factory=list)
    blocks: list[NormalizedBlock] = Field(default_factory=list)
    paragraphs: list[NormalizedParagraph] = Field(default_factory=list)
    structure_candidates: list[StructureCandidate] = Field(default_factory=list)


# ── API 响应 ──

class DocumentParseResponse(BaseModel):
    schema_version: str = "v2"
    success: bool
    job_id: Optional[str] = None
    status: Optional[str] = None   # ParseJobStatus rawValue
    document: Optional[NormalizedDocument] = None
    error: Optional[str] = None
    quality_reason: Optional[str] = None  # 机器可读的质量拒绝原因码
