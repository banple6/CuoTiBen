"""Formula-recognizer adapter boundary. No business route calls a provider directly."""

from __future__ import annotations

from typing import Protocol

from app.math_workbook.contracts import FormulaRecognitionInput, FormulaRecognitionResult


class FormulaRecognizer(Protocol):
    def recognize(self, request: FormulaRecognitionInput) -> FormulaRecognitionResult: ...


class PPStructureFormulaRecognizer:
    """Adapts PP-Structure candidates without inventing a formula confidence score."""

    def recognize(self, request: FormulaRecognitionInput) -> FormulaRecognitionResult:
        payload = request.provider_payload
        latex = payload.get("text") or payload.get("block_content") or payload.get("layout_text")
        score = payload.get("recognition_score")
        if not isinstance(score, (int, float)):
            score = None
        return FormulaRecognitionResult(
            raw_latex=str(latex).strip() if latex else None,
            recognition_score=float(score) if score is not None else None,
            recognition_score_type="formula_model" if score is not None else None,
            provider="paddleocr",
            model_name="PP-StructureV3",
            model_version=None,
            raw_output=payload,
            warnings=[] if score is not None else ["recognition_score_unavailable"],
        )
