from __future__ import annotations

import asyncio
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from app.math_workbook.explanation.provider import MockExplanationProvider, ExplanationProviderError, parse_model_json
from app.math_workbook.explanation.trace import build_deterministic_trace
from app.math_workbook.explanation.validator import validate_explanation
from app.math_workbook.ir.problem_ir import build_problem_ir
from app.math_workbook.migrations.runner import MIGRATIONS, upgrade
from app.math_workbook.parsing.normalization import normalize
from app.math_workbook.parsing.parser import parse
from app.math_workbook.parsing.tokenizer import tokenize
from app.math_workbook.rendering.latex_renderer import render_latex
from app.math_workbook.storage import MathWorkbookStore


def parsed(formula: str):
    root = parse(tokenize(normalize(formula).normalized, "fixture"))
    ir = build_problem_ir("p", 1, [root], ["fixture"]).to_dict()
    return root, ir


def candidate(kind: str, values: list[dict] | None = None) -> dict:
    return {"candidate_type": kind, "values": values or []}


class RendererAndTraceTests(unittest.TestCase):
    def test_renderer_is_stable_for_whitelist_ast(self):
        expected = {
            "2x+3=7": "2x+3=7",
            "-x^2": "-x^2",
            "(-x)^2": "(-x)^2",
            r"\frac{x+1}{x-1}": r"\frac{x+1}{x-1}",
            r"\sqrt{x+1}": r"\sqrt{x+1}",
            "-2x<4": "-2x<4",
            "2(x+1)": "2(x+1)",
            "(x+1)(x-1)": "(x+1)(x-1)",
        }
        for formula, display in expected.items():
            root, _ = parsed(formula)
            self.assertEqual(render_latex(root), display)
            self.assertEqual(render_latex(root), render_latex(root))

    def test_trace_linear_degenerate_and_unique(self):
        root, ir = parsed("2x+3=7")
        trace = build_deterministic_trace(root, candidate("unique_candidate", [{"value": {"kind": "integer", "value": 2}}]), ir)
        self.assertEqual([step["rule_id"] for step in trace["steps"]], ["subtract_constant_both_sides", "divide_both_sides_by_coefficient"])
        self.assertEqual(trace["steps"][-1]["after_latex"], "x=2")
        for formula, kind, conclusion in (("0x=0", "identity_candidate", "linear_identity_conclusion"), ("0x=1", "no_solution_candidate", "linear_no_solution_conclusion")):
            root, ir = parsed(formula)
            trace = build_deterministic_trace(root, candidate(kind), ir)
            self.assertEqual(trace["steps"][-1]["rule_id"], conclusion)

    def test_trace_quadratic_complete_matrix(self):
        cases = (
            ("x^2-5x+6=0", "two_real_candidates", [{"value": {"kind": "integer", "value": 2}}, {"value": {"kind": "integer", "value": 3}}], "quadratic_formula_root"),
            ("x^2-2x+1=0", "one_repeated_real_candidate", [{"value": {"kind": "integer", "value": 1}}], "quadratic_formula_root"),
            ("x^2+1=0", "no_solution_candidate", [], "quadratic_no_real_discriminant"),
        )
        for formula, kind, values, last_rule in cases:
            root, ir = parsed(formula)
            trace = build_deterministic_trace(root, candidate(kind, values), ir)
            self.assertEqual(trace["steps"][0]["rule_id"], "normalize_to_standard_form")
            self.assertEqual(trace["steps"][2]["rule_id"], "quadratic_discriminant")
            self.assertEqual(trace["steps"][-1]["rule_id"], last_rule)
            self.assertTrue(all("before_ast" in item and "after_ast" in item and item["rule_id"] for item in trace["steps"]))

    def test_trace_inequality_direction_and_endpoint(self):
        for formula, expected_rule, expected_latex in (("2x<4", "divide_by_positive_coefficient", "x<2"), ("-2x<4", "divide_by_negative_and_reverse_relation", "x>-2"), ("2x<=4", "divide_by_positive_coefficient", "x\\le2")):
            root, ir = parsed(formula)
            trace = build_deterministic_trace(root, candidate("interval_candidate"), ir)
            self.assertEqual(trace["steps"][-1]["rule_id"], expected_rule)
            self.assertEqual(trace["steps"][-1]["after_latex"], expected_latex)


class ProviderAndValidatorA5Tests(unittest.TestCase):
    def test_json_compatibility_is_conservative(self):
        self.assertEqual(parse_model_json('{"a":1}'), {"a": 1})
        self.assertEqual(parse_model_json('```json\n{"a":1}\n```'), {"a": 1})
        for content, code in (("prefix {\"a\":1}", "MODEL_RESPONSE_NOT_JSON"), ('{"a":1,"a":2}', "MODEL_RESPONSE_DUPLICATE_FIELD"), ("```json\n{", "MODEL_RESPONSE_TRUNCATED")):
            with self.assertRaisesRegex(ExplanationProviderError, code):
                parse_model_json(content)

    def test_provider_retries_429_but_not_401_with_stable_request_id(self):
        import app.math_workbook.explanation.provider as provider_module
        from app import config

        class Response:
            def __init__(self, status: int, payload: bytes):
                self.status_code = status; self.content = payload; self.headers = {}
            def json(self): return json.loads(self.content)

        old_key, old_retries = config.MATH_EXPLANATION_API_KEY, config.MATH_EXPLANATION_MAX_RETRIES
        config.MATH_EXPLANATION_API_KEY, config.MATH_EXPLANATION_MAX_RETRIES = "test-only-key", 1
        try:
            calls: list[str] = []
            class RetryClient:
                def __init__(self, *args, **kwargs): pass
                async def __aenter__(self): return self
                async def __aexit__(self, *args): return False
                async def post(self, url, json, headers):
                    calls.append(headers["X-Request-ID"])
                    return Response(429, b"{}") if len(calls) == 1 else Response(200, b'{"choices":[{"message":{"content":"{\\"schema_version\\":\\"2\\"}"}}]}')
            with patch.object(provider_module.httpx, "AsyncClient", RetryClient), patch.object(provider_module.DeepSeekExplanationProvider, "_retry_delay", return_value=0):
                result = asyncio.run(provider_module.DeepSeekExplanationProvider().generate_explanation({"schema_version": "2"}, "stable"))
            self.assertEqual(result, {"schema_version": "2"}); self.assertEqual(calls, ["stable", "stable"])

            unauthorized_calls: list[int] = []
            class UnauthorizedClient(RetryClient):
                async def post(self, url, json, headers):
                    unauthorized_calls.append(1); return Response(401, b"{}")
            with patch.object(provider_module.httpx, "AsyncClient", UnauthorizedClient):
                with self.assertRaisesRegex(ExplanationProviderError, "PROVIDER_HTTP_401"):
                    asyncio.run(provider_module.DeepSeekExplanationProvider().generate_explanation({"schema_version": "2"}, "unauthorized"))
            self.assertEqual(len(unauthorized_calls), 1)
        finally:
            config.MATH_EXPLANATION_API_KEY, config.MATH_EXPLANATION_MAX_RETRIES = old_key, old_retries

    def test_v2_quality_rejects_extra_math_steps_checks_variables_and_claims(self):
        from tests.test_explanation import ExplanationTests
        with tempfile.TemporaryDirectory() as tmp:
            store, problem, _ = ExplanationTests().make_verified(Path(tmp))
            prepared = store.prepare_explanation(problem["id"], "u", problem["revision"], {"language": "zh-CN", "level": "beginner", "detail": "detailed"})
            raw = asyncio.run(MockExplanationProvider().generate_explanation(prepared["input"]))
            accepted = validate_explanation(raw, prepared["input"])
            self.assertEqual(accepted["quality"]["quality_status"], "passed")
            for mutate, code in (
                (lambda value: value.update(answer_latex="x=99"), "MODEL_RESPONSE_SCHEMA_INVALID"),
                (lambda value: value["step_explanations"].pop(), "MODEL_RESPONSE_TRACE_MISMATCH"),
                (lambda value: value["verification_explanations"].append({"check_type": "invented", "explanation": "该检查由服务端完成。"}), "MODEL_RESPONSE_TRACE_MISMATCH"),
                (lambda value: value.update(problem_restatement="你在第二步把 x^2 算错了"), "MODEL_RESPONSE_INCONSISTENT"),
            ):
                bad = json.loads(json.dumps(raw, ensure_ascii=False)); mutate(bad)
                with self.assertRaisesRegex(ValueError, code):
                    validate_explanation(bad, prepared["input"])

    def test_seven_supported_canary_inputs_validate_with_mock_without_network(self):
        from tests.test_explanation import ExplanationTests
        samples = ["2x+3=7", "0x=1", "0x=0", "x^2-5x+6=0", "x^2-2x+1=0", "x^2+1=0", "-2x<4"]
        with tempfile.TemporaryDirectory() as tmp:
            for index, formula in enumerate(samples):
                store, problem, _ = ExplanationTests().make_verified(Path(tmp) / str(index), formula)
                prepared = store.prepare_explanation(problem["id"], "u", problem["revision"], {"language": "zh-CN", "level": "beginner", "detail": "detailed"})
                raw = asyncio.run(MockExplanationProvider().generate_explanation(prepared["input"]))
                result = validate_explanation(raw, prepared["input"])
                self.assertEqual(result["quality"]["quality_status"], "passed")


class DeletionAndMigrationA5Tests(unittest.TestCase):
    def _verified_explanation(self, root: Path):
        from tests.test_explanation import ExplanationTests
        store, problem, _ = ExplanationTests().make_verified(root)
        prepared = store.prepare_explanation(problem["id"], "u", problem["revision"], {"language": "zh-CN", "level": "beginner", "detail": "detailed"})
        raw = asyncio.run(MockExplanationProvider().generate_explanation(prepared["input"]))
        validated = validate_explanation(raw, prepared["input"])
        return store, problem, store.persist_explanation(prepared, "mock", "mock", "1", raw, validated, "validated", [], {"input_tokens": 4, "output_tokens": 5, "provider_request_id": "mock-1", "attempts": 1})

    def test_migration_v10_fk_trigger_unique_and_foreign_key_check(self):
        with tempfile.TemporaryDirectory() as tmp:
            db_path = str(Path(tmp) / "db.sqlite")
            self.assertEqual(upgrade(db_path), 10)
            with sqlite3.connect(db_path) as db:
                foreign_keys = {(row[2], row[6]) for row in db.execute("PRAGMA foreign_key_list(math_explanations)")}
                self.assertEqual(foreign_keys, {("math_problems", "CASCADE"), ("math_verification_reports", "CASCADE"), ("math_candidate_solution_results", "CASCADE")})
                self.assertIn("idx_math_explanations_user", {row[1] for row in db.execute("PRAGMA index_list(math_explanations)")})
                self.assertIn("math_explanations_no_update", {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='trigger'")})
                self.assertNotIn("math_explanations_no_delete", {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='trigger'")})
                self.assertEqual(db.execute("PRAGMA foreign_key_check").fetchall(), [])

    def test_migration_v9_to_v10_preserves_explanation_row(self):
        with tempfile.TemporaryDirectory() as tmp:
            db_path = str(Path(tmp) / "legacy.sqlite")
            with sqlite3.connect(db_path) as db:
                db.execute("CREATE TABLE schema_migrations(version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)")
                migration_root = Path(__file__).parents[1] / "app/math_workbook/migrations"
                for version, filename in MIGRATIONS[:9]:
                    db.executescript((migration_root / filename).read_text(encoding="utf-8")); db.execute("INSERT INTO schema_migrations(version) VALUES(?)", (version,))
                db.execute("INSERT INTO math_imports(id,user_id,source_type,source_file_path,status,created_at,updated_at) VALUES('i','u','image','outside','ready','now','now')")
                db.execute("INSERT INTO math_pages(id,import_id,page_index,original_image_path,transform_metadata,segmentation_status,created_at) VALUES('pge','i',0,'outside','{}','ready','now')")
                db.execute("INSERT INTO math_problems(id,import_id,page_id,problem_bbox,recognition_status,parse_status,solve_status,verification_status,review_reasons,created_at,updated_at,user_id) VALUES('p','i','pge','[]','confirmed','parsed','solved','verified','[]','now','now','u')")
                db.execute("INSERT INTO math_parse_results(id,problem_id,input_source_revision,input_hash,parser_version,status,created_at) VALUES('pr','p',1,'h','p','parsed','now')")
                db.execute("INSERT INTO math_sympy_build_results(id,problem_id,parse_result_id,input_ast_hash,source_revision,builder_version,sympy_version,status,symbol_table_json,artifact_json,created_at) VALUES('b','p','pr','h',1,'b','s','built','{}','{}','now')")
                db.execute("INSERT INTO math_analysis_reports(id,problem_id,parse_result_id,build_result_id,input_ast_hash,source_revision,analysis_version,status,report_json,created_at) VALUES('a','p','pr','b','h',1,'a','analyzed','{}','now')")
                db.execute("INSERT INTO math_candidate_solution_results(id,problem_id,parse_result_id,build_result_id,analysis_report_id,input_source_revision,input_hash,solver_id,solver_version,sympy_version,status,problem_classification,candidate_result_json,constraints_snapshot_json,duration_ms,created_at) VALUES('c','p','pr','b','a',1,'h','s','1','s','candidate','linear','{}','{}',0,'now')")
                db.execute("INSERT INTO math_verification_reports(id,problem_id,candidate_solution_result_id,parse_result_id,build_result_id,analysis_report_id,input_source_revision,input_hash,verifier_version,status,report_json,created_at) VALUES('v','p','c','pr','b','a',1,'h','v','verified','{}','now')")
                db.execute("INSERT INTO math_explanations(id,problem_id,verification_report_id,candidate_solution_result_id,user_id,request_id,input_source_revision,input_hash,provider,model_name,model_version,prompt_id,prompt_version,prompt_content_hash,prompt_created_at,schema_version,teaching_profile_hash,status,explanation_input_json,created_at) VALUES('e','p','v','c','u','r',1,'h','mock','mock','1','old','1','ph','now','1','th','validated','{}','now')")
                db.commit()
            self.assertEqual(upgrade(db_path), 10)
            with sqlite3.connect(db_path) as db:
                row = db.execute("SELECT id,problem_id,user_id,status,schema_version,trace_version,renderer_version FROM math_explanations WHERE id='e'").fetchone()
                self.assertEqual(row, ('e','p','u','validated','1','1','1'))
                self.assertEqual(db.execute("PRAGMA foreign_key_check").fetchall(), [])

    def test_problem_import_and_user_purge_have_no_orphans(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); store, problem, explanation = self._verified_explanation(root)
            with self.assertRaises(KeyError): store.delete_problem(problem["id"], "other")
            result = store.delete_user_data("u")
            self.assertEqual(result["user_id"], "u")
            self.assertIsNone(store.get_problem(problem["id"], "u"))
            with sqlite3.connect(root / "db.sqlite") as db:
                for table in ("math_imports", "math_pages", "math_formula_candidates", "math_problems", "math_parse_results", "math_candidate_solution_results", "math_verification_reports", "math_explanations"):
                    self.assertEqual(db.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0], 0, table)
                self.assertEqual(db.execute("PRAGMA foreign_key_check").fetchall(), [])

    def test_metadata_revision_does_not_change_math_source_revision(self):
        from tests.test_explanation import ExplanationTests
        with tempfile.TemporaryDirectory() as tmp:
            store, problem, _ = ExplanationTests().make_verified(Path(tmp))
            updated = store.update_problem(problem["id"], "u", problem["revision"], {"problem_type_hint": "linear"})
            self.assertEqual(updated["revision"], problem["revision"] + 1)
            self.assertEqual(updated["source_revision"], problem["source_revision"])

    def test_source_revision_change_rejects_old_explanation_as_stale(self):
        from tests.test_explanation import ExplanationTests
        with tempfile.TemporaryDirectory() as tmp:
            store, problem, formula_id = ExplanationTests().make_verified(Path(tmp))
            prepared = store.prepare_explanation(problem["id"], "u", problem["revision"], {"language": "zh-CN", "level": "beginner", "detail": "detailed"})
            raw = asyncio.run(MockExplanationProvider().generate_explanation(prepared["input"]))
            validated = validate_explanation(raw, prepared["input"])
            store.update_formula(formula_id, {"user_confirmed_latex": "2x+4=7"})
            stale = store.persist_explanation(prepared, "mock", "mock", "1", raw, validated, "validated", [], {})
            self.assertEqual(stale["status"], "stale")
            self.assertEqual(stale["error_code"], "EXPLANATION_INPUT_CHANGED")
            self.assertIsNone(store.current_explanation(problem["id"], "u"))

    def test_import_purge_cascades_explanation_and_get_is_gone(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); store, problem, explanation = self._verified_explanation(root)
            imported = store.get_problem(problem["id"], "u")["import_id"]
            deleted = store.delete_import(imported, "u")
            self.assertEqual(deleted["import_id"], imported)
            self.assertIsNone(store.get_import(imported)); self.assertIsNone(store.get_problem(problem["id"], "u"))
            with sqlite3.connect(root / "db.sqlite") as db:
                self.assertEqual(db.execute("SELECT COUNT(*) FROM math_explanations").fetchone()[0], 0)
                self.assertEqual(db.execute("PRAGMA foreign_key_check").fetchall(), [])

    def test_parent_delete_cascades_explanation_but_update_remains_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); store, problem, explanation = self._verified_explanation(root)
            with sqlite3.connect(root / "db.sqlite") as db:
                db.execute("PRAGMA foreign_keys=ON")
                with self.assertRaises(sqlite3.IntegrityError):
                    db.execute("UPDATE math_explanations SET status='failed' WHERE id=?", (explanation["id"],))
                db.execute("DELETE FROM math_verification_reports WHERE id=?", (explanation["verification_report_id"],))
                self.assertEqual(db.execute("SELECT COUNT(*) FROM math_explanations WHERE id=?", (explanation["id"],)).fetchone()[0], 0)
