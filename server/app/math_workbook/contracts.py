"""Public contracts and safe intermediate representation for math workbook pages."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any

from pydantic import BaseModel, Field


class SegmentationStatus(StrEnum):
    SEGMENTED = "segmented"
    NEEDS_REVIEW = "needs_review"
    FAILED = "failed"


class RecognitionStatus(StrEnum):
    RECOGNIZED = "recognized"
    NEEDS_REVIEW = "needs_review"
    FAILED = "failed"


class ParseStatus(StrEnum):
    PARSED = "parsed"
    AMBIGUOUS = "ambiguous"
    UNSUPPORTED = "unsupported"
    FAILED = "failed"


class SolveStatus(StrEnum):
    NOT_STARTED = "not_started"
    SOLVED = "solved"
    UNSOLVED = "unsolved"
    UNSUPPORTED = "unsupported"
    TIMEOUT = "timeout"
    FAILED = "failed"


class VerificationStatus(StrEnum):
    NOT_STARTED = "not_started"
    VERIFIED = "verified"
    REJECTED = "rejected"
    INCONCLUSIVE = "inconclusive"
    NOT_APPLICABLE = "not_applicable"


class RegionType(StrEnum):
    PRINTED_PROBLEM_AREA = "printed_problem_area"
    HANDWRITTEN_SOLUTION_AREA = "handwritten_solution_area"
    FINAL_ANSWER_AREA = "final_answer_area"
    MARGIN_NOTE_AREA = "margin_note_area"
    GRID_AREA = "grid_area"
    MIXED_AREA = "mixed_area"
    IRRELEVANT_AREA = "irrelevant_area"
    UNKNOWN = "unknown"


class SourceBlockType(StrEnum):
    TEXT_BLOCK = "text_block"
    FORMULA_BLOCK = "formula_block"
    HANDWRITING_STEP = "handwriting_step"
    ANSWER_CANDIDATE = "answer_candidate"
    ANNOTATION = "annotation"
    UNKNOWN = "unknown"


class FormulaSourceType(StrEnum):
    PRINTED = "printed"
    HANDWRITTEN = "handwritten"
    MIXED = "mixed"
    USER_EDITED = "user_edited"
    UNKNOWN = "unknown"


class FormulaRole(StrEnum):
    PROBLEM_EXPRESSION = "problem_expression"
    CONDITION = "condition"
    USER_STEP = "user_step"
    USER_ANSWER = "user_answer"
    REFERENCE_ANSWER = "reference_answer"
    ANNOTATION = "annotation"
    UNKNOWN = "unknown"


class BoundingBox(BaseModel):
    x: float
    y: float
    width: float
    height: float


class MathExpressionNode(BaseModel):
    """Data only: later parsers may emit only nodes from the explicit whitelist."""
    kind: str
    value: str | None = None
    children: list["MathExpressionNode"] = Field(default_factory=list)


class MathRelation(BaseModel):
    operator: str
    left: MathExpressionNode
    right: MathExpressionNode


class MathVariable(BaseModel):
    name: str


class MathConstraint(BaseModel):
    relation: MathRelation


class MathProblemIR(BaseModel):
    expressions: list[MathExpressionNode] = Field(default_factory=list)
    constraints: list[MathConstraint] = Field(default_factory=list)
    variables: list[MathVariable] = Field(default_factory=list)


class MathSolutionTrace(BaseModel):
    steps: list[str] = Field(default_factory=list)


class MathVerificationReport(BaseModel):
    status: VerificationStatus = VerificationStatus.NOT_STARTED
    reasons: list[str] = Field(default_factory=list)


class FormulaRecognitionResult(BaseModel):
    raw_latex: str | None = None
    recognition_score: float | None = None
    recognition_score_type: str | None = None
    token_scores: list[float] | None = None
    provider: str
    model_name: str
    model_version: str | None = None
    raw_output: dict[str, Any] = Field(default_factory=dict)
    warnings: list[str] = Field(default_factory=list)


@dataclass(slots=True)
class FormulaRecognitionInput:
    image_path: str
    source_type: FormulaSourceType
    provider_payload: dict[str, Any] = field(default_factory=dict)
