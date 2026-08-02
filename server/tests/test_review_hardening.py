from __future__ import annotations

import asyncio
import concurrent.futures
import os
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, patch

os.environ.setdefault("AI_STUDIO_API_URL", "http://example.invalid")
os.environ.setdefault("AI_STUDIO_ACCESS_TOKEN", "test")

from fastapi.testclient import TestClient
from PIL import Image

from app import config
from app.main import app
from app.math_workbook.imaging.image_limits import ImageDimensionError, validate_image_dimensions
from app.math_workbook.migrations import runner
from app.math_workbook.migrations.runner import upgrade
from app.math_workbook.rendering.latex_renderer import render_latex
from app.math_workbook.explanation.trace import build_deterministic_trace
from app.math_workbook.ir.problem_ir import build_problem_ir
from app.math_workbook.service import MathWorkbookService
from app.math_workbook.storage import MathWorkbookStore
from app.math_workbook.execution.verifier_executor import IsolatedVerifierExecutor
from app.math_workbook.parsing.normalization import normalize
from app.math_workbook.parsing.parser import parse
from app.math_workbook.parsing.tokenizer import tokenize
from app.math_workbook.imaging.ink_segmenter import segment_colored_ink
import app.math_workbook.imaging.image_limits as image_limits
import app.routes.math_workbook as math_routes


def _store(root: Path) -> MathWorkbookStore:
    db = root / "db.sqlite"
    upgrade(str(db))
    return MathWorkbookStore(str(db), str(root / "files"))


class LatexAndImageLimitTests(unittest.TestCase):
    def test_multiplication_renderer_is_type_safe(self):
        expected = {
            "2*3": r"2\cdot3",
            "2*x": "2x",
            "-3*x": "-3x",
            "x*y": r"x\cdoty",
            "2*x^2": "2x^2",
            "2*(x+1)": "2(x+1)",
            "(x+1)*(x-1)": "(x+1)(x-1)",
            "(x+1)*2": r"(x+1)\cdot2",
            r"\frac{1}{2}*\frac{3}{4}": r"\frac{1}{2}\cdot\frac{3}{4}",
            r"\sqrt{x}*2": r"\sqrt{x}\cdot2",
        }
        for formula, display in expected.items():
            with self.subTest(formula=formula):
                root = parse(tokenize(normalize(formula).normalized, "review"))
                self.assertEqual(render_latex(root), display)
        self.assertNotEqual(render_latex(parse(tokenize(normalize("2*3").normalized, "review"))), "23")
        root = parse(tokenize(normalize("2*3").normalized, "review"))
        ir = build_problem_ir("p", 1, [root], ["review"]).to_dict()
        trace = build_deterministic_trace(root, {"candidate_type": "exact_value", "values": []}, ir)
        self.assertEqual(trace["steps"][0]["before_latex"], r"2\cdot3")
        self.assertEqual(trace["steps"][0]["after_latex"], "6")

    def test_dimensions_and_pixel_limit_are_checked_before_convert(self):
        with self.assertRaisesRegex(ImageDimensionError, "IMAGE_DIMENSION_INVALID"):
            validate_image_dimensions(0, 10)
        with self.assertRaisesRegex(ImageDimensionError, "IMAGE_DIMENSION_INVALID"):
            validate_image_dimensions(11, 2, max_width=10)
        with self.assertRaisesRegex(ImageDimensionError, "IMAGE_DIMENSION_INVALID"):
            validate_image_dimensions(2, 11, max_height=10)
        with self.assertRaisesRegex(ImageDimensionError, "IMAGE_PIXEL_LIMIT_EXCEEDED"):
            validate_image_dimensions(4, 4, max_pixels=15)
        validate_image_dimensions(2, 3, max_width=2, max_height=3, max_pixels=6)

        class FakeImage:
            size = (100, 100)

            def close(self):
                pass

            def convert(self, mode):
                raise AssertionError("convert must not run before the dimension gate")

        old_limit = image_limits.config.MATH_MAX_IMAGE_PIXELS
        try:
            image_limits.config.MATH_MAX_IMAGE_PIXELS = 1
            with patch.object(image_limits.Image, "open", return_value=FakeImage()):
                with self.assertRaisesRegex(ImageDimensionError, "IMAGE_PIXEL_LIMIT_EXCEEDED"):
                    segment_colored_ink(Path("compressed-large.jpg"), Path("out"))
        finally:
            image_limits.config.MATH_MAX_IMAGE_PIXELS = old_limit


class IdempotencyRecoveryTests(unittest.TestCase):
    def test_v10_to_v11_preserves_rows_and_adds_reclaim_index(self):
        with tempfile.TemporaryDirectory() as temporary:
            db_path = Path(temporary) / "legacy.sqlite"
            original = runner.MIGRATIONS
            try:
                runner.MIGRATIONS = original[:10]
                self.assertEqual(runner.upgrade(str(db_path)), 10)
            finally:
                runner.MIGRATIONS = original
            with sqlite3.connect(db_path) as db:
                db.execute("INSERT INTO math_idempotency_records(id,user_id,operation_type,idempotency_key,request_hash,status,created_at,updated_at,expires_at) VALUES('legacy','u','import','k','h','processing','now','now','2099-01-01T00:00:00Z')")
                db.commit()
            self.assertEqual(runner.upgrade(str(db_path)), 11)
            with sqlite3.connect(db_path) as db:
                columns = {row[1] for row in db.execute("PRAGMA table_info(math_idempotency_records)")}
                indexes = {row[1] for row in db.execute("PRAGMA index_list(math_idempotency_records)")}
                self.assertTrue({"attempt_count", "last_error_code", "last_failed_at"} <= columns)
                self.assertIn("idx_math_idempotency_reclaim", indexes)
                self.assertEqual(db.execute("SELECT status,attempt_count FROM math_idempotency_records WHERE id='legacy'").fetchone(), ("processing", 1))
                self.assertEqual(db.execute("PRAGMA foreign_key_check").fetchall(), [])

    def test_failed_expired_and_competing_reservations_recover_atomically(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            store = _store(root)
            first = store.reserve_idempotency("u", "import", "key", {"body": 1})
            self.assertFalse(store.reserve_idempotency("u", "import", "key", {"body": 1})["created"])
            with self.assertRaises(Exception):
                store.reserve_idempotency("u", "import", "key", {"body": 2})

            self.assertTrue(store.fail_idempotency(first["id"], 422, "IMAGE_PIXEL_LIMIT_EXCEEDED", first["attempt_count"]))
            failed = store.reserve_idempotency("u", "import", "key", {"body": 1})
            self.assertTrue(failed["created"])
            self.assertEqual(failed["attempt_count"], 2)

            with sqlite3.connect(root / "db.sqlite") as db:
                db.execute("UPDATE math_idempotency_records SET expires_at='2000-01-01T00:00:00Z' WHERE id=?", (failed["id"],))
            contenders = concurrent.futures.ThreadPoolExecutor(max_workers=2)
            try:
                claims = list(contenders.map(lambda _: store.reserve_idempotency("u", "import", "key", {"body": 1}), range(2)))
            finally:
                contenders.shutdown(wait=True)
            self.assertEqual({item["id"] for item in claims}, {failed["id"]})
            self.assertEqual(sum(bool(item["created"]) for item in claims), 1)
            winner = next(item for item in claims if item["created"])
            self.assertEqual(winner["attempt_count"], 3)
            self.assertTrue(store.finish_idempotency(winner["id"], 201, "math_import", "resource", {"id": "resource"}, winner["attempt_count"]))
            completed = store.reserve_idempotency("u", "import", "key", {"body": 1})
            self.assertFalse(completed["created"])
            self.assertEqual(completed["status"], "completed")

    def test_failed_route_can_retry_and_service_failure_cleans_import_graph(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            store = _store(root)
            old_flag = config.MATH_ALLOW_DEV_USER_HEADER
            try:
                config.MATH_ALLOW_DEV_USER_HEADER = True

                class FailingService:
                    async def import_page(self, *args, **kwargs):
                        raise ValueError("IMAGE_PIXEL_LIMIT_EXCEEDED")

                with patch.object(math_routes, "_get_store", return_value=store), patch.object(math_routes, "_get_service", return_value=FailingService()):
                    response = TestClient(app).post(
                        "/api/v1/math-imports",
                        headers={"X-User-Id": "u", "Idempotency-Key": "retry-key"},
                        files={"file": ("page.png", b"not-an-image", "image/png")},
                    )
                self.assertEqual(response.status_code, 422)
                self.assertEqual(response.json()["detail"], "IMAGE_PIXEL_LIMIT_EXCEEDED")
                with sqlite3.connect(root / "db.sqlite") as db:
                    row = db.execute("SELECT status,last_error_code,response_body FROM math_idempotency_records").fetchone()
                self.assertEqual(row, ("failed", "IMAGE_PIXEL_LIMIT_EXCEEDED", None))

                class SucceedingService:
                    calls = 0

                    async def import_page(self, *args, **kwargs):
                        self.calls += 1
                        return {"id": "import-retry"}

                succeeding = SucceedingService()
                with patch.object(math_routes, "_get_store", return_value=store), patch.object(math_routes, "_get_service", return_value=succeeding):
                    response = TestClient(app).post(
                        "/api/v1/math-imports",
                        headers={"X-User-Id": "u", "Idempotency-Key": "retry-key"},
                        files={"file": ("page.png", b"not-an-image", "image/png")},
                    )
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.json()["id"], "import-retry")
                self.assertEqual(succeeding.calls, 1)
                with sqlite3.connect(root / "db.sqlite") as db:
                    self.assertEqual(db.execute("SELECT status,attempt_count,resource_id FROM math_idempotency_records").fetchone(), ("completed", 2, "import-retry"))
            finally:
                config.MATH_ALLOW_DEV_USER_HEADER = old_flag

    def test_service_cleans_persisted_import_when_upstream_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            store = _store(root)
            source = root / "source.png"
            Image.new("RGB", (16, 16), "white").save(source)
            service = MathWorkbookService(store)
            with patch("app.math_workbook.service.call_pp_structure_v3", new=AsyncMock(side_effect=RuntimeError("upstream"))):
                with self.assertRaises(RuntimeError):
                    asyncio.run(service.import_page(source, "source.png", "image", "u"))
            with sqlite3.connect(root / "db.sqlite") as db:
                self.assertEqual(db.execute("SELECT COUNT(*) FROM math_imports").fetchone()[0], 0)
                self.assertEqual(db.execute("SELECT COUNT(*) FROM math_pages").fetchone()[0], 0)


class VerificationLockTests(unittest.TestCase):
    @staticmethod
    def _problem(root: Path) -> tuple[MathWorkbookStore, dict, str]:
        store = _store(root)
        import_id = store.create_import("image", "source.jpg", "u")
        page_id = store.create_page(import_id, 0, "source.jpg", {}, "ready")
        region_id = store.add_region(page_id, {"region_type": "printed_problem_area", "bbox": (0, 0, 1, 1), "reading_order": 0})
        block_id = store.add_source_block(page_id, {"parent_region_id": region_id, "block_type": "formula_block", "bbox": (0, 0, 1, 1), "reading_order": 0})
        formula_id = store.add_formula(page_id, {"region_id": region_id, "source_block_id": block_id, "bbox": (0, 0, 1, 1), "source_type": "printed", "role": "problem_expression", "raw_latex": "2x+3=7", "reading_order": 0})
        store.update_formula(formula_id, {"user_confirmed_latex": "2x+3=7"})
        problem = store.create_problem("u", import_id, page_id, [0, 0, 1, 1], [{"source_kind": "formula", "source_id": formula_id, "semantic_role": "prompt", "reading_order": 0}])
        store.parse_problem(problem["id"], "u", problem["revision"])
        store.build_problem(problem["id"], "u")
        store.analyze_problem(problem["id"], "u")
        store.solve_problem(problem["id"], "u", problem["revision"])
        return store, problem, formula_id

    def test_slow_verifier_does_not_hold_sqlite_write_lock(self):
        with tempfile.TemporaryDirectory() as temporary:
            store, problem, _ = self._problem(Path(temporary))
            started = __import__("threading").Event()
            release = __import__("threading").Event()
            original_execute = IsolatedVerifierExecutor.execute

            def slow_execute(executor, request):
                started.set()
                if not release.wait(5):
                    raise TimeoutError("test verifier release timeout")
                return original_execute(executor, request)

            with patch.object(IsolatedVerifierExecutor, "execute", slow_execute):
                with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
                    verify_future = pool.submit(store.verify_problem, problem["id"], "u", problem["revision"])
                    self.assertTrue(started.wait(3))
                    # This write must complete while the worker is blocked;
                    # the old BEGIN IMMEDIATE implementation timed out here.
                    import_future = pool.submit(store.create_import, "image", "other.jpg", "other")
                    imported_id = import_future.result(timeout=1)
                    self.assertTrue(imported_id)
                    other_page = store.create_page(imported_id, 0, "other.jpg", {}, "ready")
                    other_region = store.add_region(other_page, {"region_type": "printed_problem_area", "bbox": (0, 0, 1, 1), "reading_order": 0})
                    other_block = store.add_source_block(other_page, {"parent_region_id": other_region, "block_type": "formula_block", "bbox": (0, 0, 1, 1), "reading_order": 0})
                    other_formula = store.add_formula(other_page, {"region_id": other_region, "source_block_id": other_block, "bbox": (0, 0, 1, 1), "raw_latex": "x", "reading_order": 0})
                    other_problem = store.create_problem("other", imported_id, other_page, [0, 0, 1, 1], [{"source_kind": "formula", "source_id": other_formula, "semantic_role": "prompt", "reading_order": 0}])
                    store.update_formula(other_formula, {"user_confirmed_latex": "x+1"}, "other")
                    self.assertEqual(store.delete_problem(other_problem["id"], "other")["problem_id"], other_problem["id"])
                    idem = store.reserve_idempotency("other", "import", "during-verify", {"x": 1})
                    self.assertTrue(idem["created"])
                    release.set()
                    report = verify_future.result(timeout=15)
            self.assertEqual(report["status"], "verified")

    def test_source_revision_change_during_worker_cannot_become_current(self):
        with tempfile.TemporaryDirectory() as temporary:
            store, problem, formula_id = self._problem(Path(temporary))
            started = __import__("threading").Event()
            release = __import__("threading").Event()
            original_execute = IsolatedVerifierExecutor.execute

            def slow_execute(executor, request):
                started.set()
                self.assertTrue(release.wait(5))
                return original_execute(executor, request)

            with patch.object(IsolatedVerifierExecutor, "execute", slow_execute):
                with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                    verify_future = pool.submit(store.verify_problem, problem["id"], "u", problem["revision"])
                    self.assertTrue(started.wait(3))
                    store.update_formula(formula_id, {"user_confirmed_latex": "2x+4=7"})
                    release.set()
                    report = verify_future.result(timeout=15)
            self.assertEqual(report["status"], "inconclusive")
            self.assertIsNone(store.current_verification(problem["id"], "u"))


if __name__ == "__main__":
    unittest.main()
