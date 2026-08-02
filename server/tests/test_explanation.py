import asyncio
import concurrent.futures
import json
import os
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault("AI_STUDIO_API_URL", "http://example.invalid")
os.environ.setdefault("AI_STUDIO_ACCESS_TOKEN", "test")

from app.math_workbook.explanation.provider import MockExplanationProvider
from app.math_workbook.explanation.validator import validate_explanation
from app.math_workbook.migrations.runner import upgrade
from app.math_workbook.solving.router import QuadraticEquationSolver
from app.math_workbook.storage import MathWorkbookStore
from app import config
from app.math_workbook.parsing.normalization import normalize
from app.math_workbook.parsing.tokenizer import tokenize
from app.math_workbook.parsing.parser import parse
from app.math_workbook.ir.problem_ir import build_problem_ir
from app.math_workbook.sympy_bridge.builder import AstSympyBuilder
from app.math_workbook.sympy_bridge.symbol_table import SymbolTable


class ExplanationTests(unittest.TestCase):
    def make_verified(self, root: Path, formula: str = "2x+3=7", user: str = "u"):
        db = root / "db.sqlite"
        upgrade(str(db))
        store = MathWorkbookStore(str(db), str(root / "files"))
        imp = store.create_import("image", "x", user)
        page = store.create_page(imp, 0, "x", {}, "ready")
        region = store.add_region(page, {"region_type": "printed_problem_area", "bbox": (0, 0, 1, 1), "reading_order": 0})
        block = store.add_source_block(page, {"parent_region_id": region, "block_type": "formula_block", "bbox": (0, 0, 1, 1), "reading_order": 0})
        fid = store.add_formula(page, {"region_id": region, "source_block_id": block, "bbox": (0, 0, 1, 1), "source_type": "printed", "role": "problem_expression", "raw_latex": formula, "reading_order": 0})
        store.update_formula(fid, {"user_confirmed_latex": formula})
        problem = store.create_problem(user, imp, page, [0, 0, 1, 1], [{"source_kind": "formula", "source_id": fid, "semantic_role": "prompt", "reading_order": 0}])
        store.parse_problem(problem["id"], user, problem["revision"])
        store.build_problem(problem["id"], user)
        store.analyze_problem(problem["id"], user)
        store.solve_problem(problem["id"], user, problem["revision"])
        store.verify_problem(problem["id"], user, problem["revision"])
        return store, problem, fid

    def test_input_is_minimized_and_mock_explanation_validated(self):
        with tempfile.TemporaryDirectory() as tmp:
            store, problem, _ = self.make_verified(Path(tmp))
            prepared = store.prepare_explanation(problem["id"], "u", problem["revision"], {"language": "zh-CN", "level": "beginner", "detail": "detailed"})
            serialized = json.dumps(prepared["input"], ensure_ascii=False)
            self.assertNotIn("raw_latex", serialized)
            self.assertNotIn("PP-StructureV3", serialized)
            self.assertNotIn("/Volumes/", serialized)
            self.assertNotIn('"user_id"', serialized)
            self.assertNotIn("source_formula_id", serialized)
            raw = asyncio.run(MockExplanationProvider().generate_explanation(prepared["input"]))
            validated = validate_explanation(raw, prepared["input"])
            saved = store.persist_explanation(prepared, "mock", "mock", "1", raw, validated, "validated", [], {"duration_ms": 1, "input_tokens": 10, "output_tokens": 20, "estimated_cost": 0.0})
            self.assertEqual(saved["status"], "validated")
            self.assertEqual(saved["prompt_id"], "verified-math-teaching")
            self.assertEqual(saved["request_id"], prepared["request_id"])
            self.assertEqual(saved["validated_explanation_json"]["final_answer_latex"], "x=2")

    def test_validator_rejects_inconsistent_rule_check_handwriting_and_large_output(self):
        input_data = {"answer_latex": "x=2", "problem_type": "unique_candidate", "deterministic_trace": [{"operation": "linear_coefficient_formula", "rule_id": "linear_coefficient_formula", "before_latex": "", "after_latex": ""}], "verification_summary": {"passed_checks": ["candidate_schema"]}}
        valid = asyncio.run(MockExplanationProvider().generate_explanation(input_data))
        bad_answer = dict(valid); bad_answer["final_answer_latex"] = "x=3"
        with self.assertRaisesRegex(ValueError, "EXPLANATION_OUTPUT_INCONSISTENT"): validate_explanation(bad_answer, input_data)
        bad_rule = json.loads(json.dumps(valid)); bad_rule["steps"][0]["rule_id"] = "invented"
        with self.assertRaisesRegex(ValueError, "EXPLANATION_UNKNOWN_RULE"): validate_explanation(bad_rule, input_data)
        bad_check = json.loads(json.dumps(valid)); bad_check["verification_explanation"][0]["check_type"] = "invented"
        with self.assertRaisesRegex(ValueError, "EXPLANATION_UNKNOWN_CHECK"): validate_explanation(bad_check, input_data)
        handwriting = json.loads(json.dumps(valid)); handwriting["problem_restatement"] = "我看到了你的笔记"
        with self.assertRaisesRegex(ValueError, "EXPLANATION_UNSAFE_CLAIM"): validate_explanation(handwriting, input_data)
        huge = json.loads(json.dumps(valid)); huge["limitations"] = ["x" * 70_000]
        with self.assertRaisesRegex(ValueError, "EXPLANATION_RESPONSE_TOO_LARGE"): validate_explanation(huge, input_data)

    def test_gate_blocks_non_verified_and_cross_user(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            # Build only through candidate stage: no current VerificationReport exists.
            db = root / "db.sqlite"; upgrade(str(db)); store = MathWorkbookStore(str(db), str(root / "files"))
            imp = store.create_import("image", "x", "u"); page = store.create_page(imp, 0, "x", {}, "ready")
            region = store.add_region(page, {"region_type": "printed_problem_area", "bbox": (0, 0, 1, 1), "reading_order": 0})
            block = store.add_source_block(page, {"parent_region_id": region, "block_type": "formula_block", "bbox": (0, 0, 1, 1), "reading_order": 0})
            fid = store.add_formula(page, {"region_id": region, "source_block_id": block, "bbox": (0, 0, 1, 1), "source_type": "printed", "role": "problem_expression", "raw_latex": "2x+3=7", "reading_order": 0})
            store.update_formula(fid, {"user_confirmed_latex": "2x+3=7"}); p = store.create_problem("u", imp, page, [0, 0, 1, 1], [{"source_kind": "formula", "source_id": fid, "semantic_role": "prompt", "reading_order": 0}])
            store.parse_problem(p["id"], "u", p["revision"]); store.build_problem(p["id"], "u"); store.analyze_problem(p["id"], "u"); store.solve_problem(p["id"], "u", p["revision"])
            with self.assertRaisesRegex(ValueError, "NO_CURRENT_VERIFIED_REPORT"): store.prepare_explanation(p["id"], "u", p["revision"], {})
            with self.assertRaises(KeyError): store.prepare_explanation(p["id"], "other", p["revision"], {})

    def test_same_input_dedupes_different_profile_versions_and_is_immutable(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); store, problem, _ = self.make_verified(root)
            profile = {"language": "zh-CN", "level": "beginner", "detail": "detailed"}; prepared = store.prepare_explanation(problem["id"], "u", problem["revision"], profile)
            provider = MockExplanationProvider(); raw = asyncio.run(provider.generate_explanation(prepared["input"])); valid = validate_explanation(raw, prepared["input"])
            first = store.persist_explanation(prepared, "mock", "mock", "1", raw, valid, "validated", [], {})
            second = store.persist_explanation(prepared, "mock", "mock", "1", raw, valid, "validated", [], {"cache_hit": True})
            self.assertEqual(first["id"], second["id"])
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                concurrent_rows = list(pool.map(lambda _: store.persist_explanation(prepared, "mock", "mock", "1", raw, valid, "validated", [], {}), range(2)))
            self.assertEqual({row["id"] for row in concurrent_rows}, {first["id"]})
            other = store.prepare_explanation(problem["id"], "u", problem["revision"], {"language": "zh-CN", "level": "advanced", "detail": "detailed"})
            other_raw = asyncio.run(provider.generate_explanation(other["input"])); other_valid = validate_explanation(other_raw, other["input"])
            self.assertNotEqual(first["id"], store.persist_explanation(other, "mock", "mock", "1", other_raw, other_valid, "validated", [], {})["id"])
            self.assertNotEqual(first["id"], store.persist_explanation(prepared, "deepseek", "deepseek-chat", "v2", raw, valid, "validated", [], {})["id"])
            with sqlite3.connect(root / "db.sqlite") as con:
                with self.assertRaises(sqlite3.IntegrityError): con.execute("UPDATE math_explanations SET status='failed' WHERE id=?", (first["id"],))
                con.execute("DELETE FROM math_explanations WHERE id=?", (first["id"],))
                self.assertIsNone(con.execute("SELECT 1 FROM math_explanations WHERE id=?", (first["id"],)).fetchone())

    def test_explanation_api_returns_only_validated_public_artifact(self):
        from fastapi.testclient import TestClient
        import app.routes.math_workbook as math_routes
        from app.main import app
        with tempfile.TemporaryDirectory() as tmp:
            store, problem, _ = self.make_verified(Path(tmp))
            old_flag = config.MATH_ALLOW_DEV_USER_HEADER
            try:
                config.MATH_ALLOW_DEV_USER_HEADER = True
                with patch.object(math_routes, "_get_store", return_value=store):
                    client = TestClient(app)
                    response = client.post(f"/api/v1/math-problems/{problem['id']}/explanation", headers={"X-User-Id": "u"}, json={"expected_revision": problem["revision"], "teaching_profile": {"language": "zh-CN", "level": "beginner", "detail": "detailed"}})
                    self.assertEqual(response.status_code, 200)
                    body = response.json(); self.assertEqual(body["status"], "validated"); self.assertEqual(body["explanation"]["final_answer_latex"], "x=2")
                    self.assertNotIn("raw_model_response_json", body["artifact"])
                    fetched = client.get(f"/api/v1/math-problems/{problem['id']}/explanation", headers={"X-User-Id": "u"})
                    self.assertEqual(fetched.status_code, 200); self.assertEqual(fetched.json()["current_explanation"]["status"], "validated")
                    self.assertNotIn("explanation_input_json", fetched.json()["current_explanation"])
                    self.assertEqual(client.get(f"/api/v1/math-problems/{problem['id']}/explanation", headers={"X-User-Id": "other"}).status_code, 404)
            finally:
                config.MATH_ALLOW_DEV_USER_HEADER = old_flag

    def test_quadratic_no_real_candidate_uses_allowed_explanation_type(self):
        root = parse(tokenize(normalize("x^2+1=0").normalized, "f")); ir = build_problem_ir("p", 1, [root], ["f"])
        expr = AstSympyBuilder(SymbolTable(list(ir.variables))).build(root)
        solver = QuadraticEquationSolver(); result = solver.solve_candidate(expr, {"symbol": next(iter(SymbolTable(list(ir.variables)).symbols.values()))})
        self.assertEqual(result["candidate_type"], "no_solution_candidate")

    def test_migration_explanation_columns_indexes_and_triggers(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = Path(tmp) / "db.sqlite"; self.assertEqual(upgrade(str(db)), 11)
            with sqlite3.connect(db) as con:
                cols = {row[1] for row in con.execute("PRAGMA table_info(math_explanations)")}
                self.assertTrue({"user_id", "request_id", "prompt_id", "prompt_content_hash", "cache_hit"}.issubset(cols))
                indexes = {row[1] for row in con.execute("PRAGMA index_list(math_explanations)")}
                self.assertIn("idx_math_explanations_current", indexes); self.assertIn("idx_math_explanations_request", indexes)
                triggers = {row[0] for row in con.execute("SELECT name FROM sqlite_master WHERE type='trigger'")}
                self.assertIn("math_explanations_no_update", triggers); self.assertNotIn("math_explanations_no_delete", triggers)

    def test_deepseek_provider_retries_with_same_request_id_and_bounds_response(self):
        from app.math_workbook.explanation.provider import DeepSeekExplanationProvider, ExplanationProviderError
        request = {"answer_latex": "x=2", "problem_type": "unique_candidate", "deterministic_trace": [], "verification_summary": {"passed_checks": []}}
        calls = []
        class Response:
            def __init__(self, status, body): self.status_code, self.content, self._body = status, body, body
            def json(self): return json.loads(self._body)
        class Client:
            def __init__(self, *args, **kwargs): pass
            async def __aenter__(self): return self
            async def __aexit__(self, *args): return False
            async def post(self, url, json, headers):
                calls.append(headers.get("X-Request-ID"))
                if len(calls) == 1: return Response(500, b"{}")
                return Response(200, json_module.dumps({"choices": [{"message": {"content": json_module.dumps({"ok": True})}}]}).encode())
        import app.math_workbook.explanation.provider as provider_module
        json_module = json
        old_retries, old_key = config.MATH_EXPLANATION_MAX_RETRIES, config.MATH_EXPLANATION_API_KEY
        config.MATH_EXPLANATION_MAX_RETRIES, config.MATH_EXPLANATION_API_KEY = 1, "test-only-key"
        try:
            with patch.object(provider_module.httpx, "AsyncClient", Client):
                result = asyncio.run(DeepSeekExplanationProvider().generate_explanation(request, "same-request"))
            self.assertEqual(result, {"ok": True}); self.assertEqual(calls, ["same-request", "same-request"])
        finally:
            config.MATH_EXPLANATION_MAX_RETRIES, config.MATH_EXPLANATION_API_KEY = old_retries, old_key

        class HugeClient(Client):
            async def post(self, url, json, headers): return Response(200, b"x" * 100)
        old_limit = config.MATH_EXPLANATION_MAX_RESPONSE_BYTES; config.MATH_EXPLANATION_MAX_RESPONSE_BYTES = 10
        try:
            with patch.object(provider_module.httpx, "AsyncClient", HugeClient):
                with self.assertRaises(ExplanationProviderError): asyncio.run(DeepSeekExplanationProvider().generate_explanation(request, "large"))
        finally:
            config.MATH_EXPLANATION_MAX_RESPONSE_BYTES = old_limit

        class InvalidJsonClient(Client):
            async def post(self, url, json, headers): return Response(200, b'{"choices":[{"message":{"content":"not-json"}}]}')
        with patch.object(provider_module.httpx, "AsyncClient", InvalidJsonClient):
            with self.assertRaises(ExplanationProviderError): asyncio.run(DeepSeekExplanationProvider().generate_explanation(request, "invalid-json"))

        class TimeoutClient(Client):
            async def post(self, url, json, headers): raise provider_module.httpx.ReadTimeout("read timeout")
        old_retries, old_key = config.MATH_EXPLANATION_MAX_RETRIES, config.MATH_EXPLANATION_API_KEY; config.MATH_EXPLANATION_MAX_RETRIES, config.MATH_EXPLANATION_API_KEY = 1, "test-only-key"
        try:
            with patch.object(provider_module.httpx, "AsyncClient", TimeoutClient):
                with self.assertRaisesRegex(ExplanationProviderError, "PROVIDER_TIMEOUT"): asyncio.run(DeepSeekExplanationProvider().generate_explanation(request, "timeout"))
        finally:
            config.MATH_EXPLANATION_MAX_RETRIES, config.MATH_EXPLANATION_API_KEY = old_retries, old_key


if __name__ == "__main__":
    unittest.main()
