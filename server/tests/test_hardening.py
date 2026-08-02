from __future__ import annotations

import asyncio
import json
import multiprocessing
import shutil
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient
from pydantic import ValidationError

from app import config
from app.math_workbook.explanation.provider import MockExplanationProvider
from app.math_workbook.explanation.validator import validate_explanation
from app.math_workbook.migrations import runner
from app.math_workbook.storage import MathWorkbookStore
from app.routes import math_workbook as math_routes
from app.main import app


def _upgrade_worker(database_path: str) -> None:
    runner.upgrade(database_path)


class HardeningFixture:
    @staticmethod
    def create(root: Path, user_id: str = "owner") -> tuple[MathWorkbookStore, str, str, str, str]:
        db_path = root / "db.sqlite"
        runner.upgrade(str(db_path))
        store = MathWorkbookStore(str(db_path), str(root / "files"))
        import_id = store.create_import("image", "source.jpg", user_id)
        page_id = store.create_page(import_id, 0, "source.jpg", {}, "ready")
        region_id = store.add_region(page_id, {"region_type": "printed_problem_area", "bbox": (0, 0, 1, 1), "reading_order": 0})
        block_id = store.add_source_block(page_id, {"parent_region_id": region_id, "block_type": "formula_block", "bbox": (0, 0, 1, 1), "reading_order": 0})
        formula_id = store.add_formula(page_id, {"region_id": region_id, "source_block_id": block_id, "bbox": (0, 0, 1, 1), "source_type": "printed", "role": "problem_expression", "raw_latex": "2x+3=7", "reading_order": 0})
        return store, import_id, page_id, region_id, formula_id


class OwnershipHardeningTests(unittest.TestCase):
    def test_page_region_formula_and_page_actions_are_owned(self):
        with tempfile.TemporaryDirectory() as tmp:
            store, _, page_id, region_id, formula_id = HardeningFixture.create(Path(tmp))
            old_flag = config.MATH_ALLOW_DEV_USER_HEADER
            try:
                # The development identity header is opt-in even in tests.
                config.MATH_ALLOW_DEV_USER_HEADER = True
                with patch.object(math_routes, "_get_store", return_value=store):
                    client = TestClient(app)
                    page_response = client.get(f"/api/v1/math-pages/{page_id}", headers={"X-User-Id": "owner"})
                    self.assertEqual(page_response.status_code, 200)
                    self.assertFalse(any(key.endswith("_path") for key in json.dumps(page_response.json()).split('"')))
                    for path, method, payload in (
                        (f"/api/v1/math-pages/{page_id}", "get", None),
                        (f"/api/v1/math-pages/{page_id}/segment", "post", None),
                        (f"/api/v1/math-pages/{page_id}/recognize", "post", None),
                    ):
                        response = getattr(client, method)(path, headers={"X-User-Id": "other"})
                        self.assertEqual(response.status_code, 404)
                    self.assertEqual(client.patch(f"/api/v1/math-regions/{region_id}", headers={"X-User-Id": "other"}, json={"reading_order": 1}).status_code, 404)
                    self.assertEqual(client.patch(f"/api/v1/math-formulas/{formula_id}", headers={"X-User-Id": "other"}, json={"role": "condition"}).status_code, 404)
                    self.assertEqual(client.delete("/api/v1/math-account").status_code, 401)
                    self.assertEqual(client.delete("/api/v1/math-account", headers={"X-User-Id": "anonymous"}).status_code, 401)
                    config.MATH_ALLOW_DEV_USER_HEADER = False
                    self.assertEqual(client.get(f"/api/v1/math-pages/{page_id}", headers={"X-User-Id": "owner"}).status_code, 401)
            finally:
                config.MATH_ALLOW_DEV_USER_HEADER = old_flag
            self.assertIsNone(store.get_page(page_id, "other"))
            with self.assertRaises(KeyError):
                store.update_region(region_id, {"reading_order": 1}, "other")
            with self.assertRaises(KeyError):
                store.update_formula(formula_id, {"role": "condition"}, "other")

    def test_teaching_profile_is_strict_and_defaults_are_not_shared(self):
        from app.routes.math_workbook import ExplanationRequest

        first = ExplanationRequest(expected_revision=1)
        second = ExplanationRequest(expected_revision=1)
        self.assertEqual(first.teaching_profile.model_dump(), {"language": "zh-CN", "level": "beginner", "detail": "detailed"})
        self.assertIsNot(first.teaching_profile, second.teaching_profile)
        with self.assertRaises(ValidationError):
            ExplanationRequest(expected_revision=1, teaching_profile={"language": "zh-CN", "level": "beginner", "detail": "detailed", "extra": True})
        with self.assertRaises(ValidationError):
            ExplanationRequest(expected_revision=1, teaching_profile={"language": "fr-FR", "level": "beginner", "detail": "detailed"})


class MigrationAtomicityTests(unittest.TestCase):
    def test_failed_v10_rolls_back_and_retry_succeeds(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            db_path = root / "db.sqlite"
            original_migrations = runner.MIGRATIONS
            try:
                runner.MIGRATIONS = original_migrations[:9]
                self.assertEqual(runner.upgrade(str(db_path)), 9)
            finally:
                runner.MIGRATIONS = original_migrations
            bad_dir = root / "migrations"
            shutil.copytree(Path(__file__).parents[1] / "app/math_workbook/migrations", bad_dir)
            bad_file = bad_dir / "0010_math_explanation_retention.sql"
            bad_file.write_text(bad_file.read_text(encoding="utf-8") + "\nSELECT * FROM table_that_does_not_exist;\n", encoding="utf-8")
            with self.assertRaises(sqlite3.OperationalError):
                runner.upgrade(str(db_path), bad_dir)
            self.assertEqual(runner.current_version(str(db_path)), 9)
            with sqlite3.connect(db_path) as db:
                self.assertIsNotNone(db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='math_explanations'").fetchone())
                self.assertIsNone(db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='math_explanations_v9'").fetchone())
            self.assertEqual(runner.upgrade(str(db_path)), 10)
            with sqlite3.connect(db_path) as db:
                self.assertEqual(db.execute("PRAGMA foreign_key_check").fetchall(), [])

    def test_two_migration_processes_leave_one_valid_v10_database(self):
        with tempfile.TemporaryDirectory() as tmp:
            db_path = str(Path(tmp) / "concurrent.sqlite")
            context = multiprocessing.get_context("spawn")
            processes = [context.Process(target=_upgrade_worker, args=(db_path,)) for _ in range(2)]
            for process in processes:
                process.start()
            for process in processes:
                process.join(30)
                self.assertEqual(process.exitcode, 0)
            self.assertEqual(runner.current_version(db_path), 10)
            with sqlite3.connect(db_path) as db:
                self.assertEqual(db.execute("PRAGMA foreign_key_check").fetchall(), [])


class TraceBoundaryTests(unittest.TestCase):
    def test_explanation_reads_worker_trace_without_running_trace_sympy(self):
        from tests.test_explanation import ExplanationTests
        with tempfile.TemporaryDirectory() as tmp:
            store, problem, _ = ExplanationTests().make_verified(Path(tmp))
            candidate = store.current_candidate_solution(problem["id"], "u")
            self.assertIsInstance(candidate["candidate_result_json"], dict)
            self.assertIn("deterministic_trace", candidate["candidate_result_json"])
            with patch("app.math_workbook.explanation.trace.build_deterministic_trace", side_effect=AssertionError("request process must not build trace")):
                prepared = store.prepare_explanation(problem["id"], "u", problem["revision"], {"language": "zh-CN", "level": "beginner", "detail": "detailed"})
            self.assertEqual(prepared["input"]["deterministic_trace"]["binding"]["source_revision"], problem["source_revision"])

    def test_missing_or_mismatched_trace_is_rejected(self):
        from tests.test_explanation import ExplanationTests
        with tempfile.TemporaryDirectory() as tmp:
            store, problem, _ = ExplanationTests().make_verified(Path(tmp))
            with sqlite3.connect(Path(tmp) / "db.sqlite") as db:
                row = db.execute("SELECT id,candidate_result_json FROM math_candidate_solution_results WHERE problem_id=?", (problem["id"],)).fetchone()
                candidate = json.loads(row[1]); candidate.pop("deterministic_trace", None)
                db.execute("UPDATE math_candidate_solution_results SET candidate_result_json=? WHERE id=?", (json.dumps(candidate), row[0]))
            with self.assertRaisesRegex(ValueError, "TRACE_MISSING"):
                store.prepare_explanation(problem["id"], "u", problem["revision"], {"language": "zh-CN", "level": "beginner", "detail": "detailed"})

    def test_trace_binding_hash_mismatch_is_rejected(self):
        from tests.test_explanation import ExplanationTests

        with tempfile.TemporaryDirectory() as tmp:
            store, problem, _ = ExplanationTests().make_verified(Path(tmp))
            with sqlite3.connect(Path(tmp) / "db.sqlite") as db:
                row = db.execute("SELECT id,candidate_result_json FROM math_candidate_solution_results WHERE problem_id=?", (problem["id"],)).fetchone()
                candidate = json.loads(row[1])
                candidate["deterministic_trace"]["binding"] = {"input_hash": "wrong"}
                db.execute("UPDATE math_candidate_solution_results SET candidate_result_json=? WHERE id=?", (json.dumps(candidate), row[0]))
            with self.assertRaisesRegex(ValueError, "TRACE_INPUT_CHANGED"):
                store.prepare_explanation(problem["id"], "u", problem["revision"], {"language": "zh-CN", "level": "beginner", "detail": "detailed"})


if __name__ == "__main__":
    unittest.main()
