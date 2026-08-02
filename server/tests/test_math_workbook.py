import os
import tempfile
import unittest
from pathlib import Path

os.environ.setdefault("AI_STUDIO_API_URL", "http://example.invalid")
os.environ.setdefault("AI_STUDIO_ACCESS_TOKEN", "test")

from PIL import Image, ImageDraw

from app.math_workbook.imaging.ink_segmenter import segment_colored_ink
from app.math_workbook.imaging.page_normalizer import normalize_page
from app.math_workbook.quality import formula_quality_flags
from app.math_workbook.storage import MathWorkbookStore
from app.math_workbook.migrations.runner import upgrade


class MathWorkbookTests(unittest.TestCase):
    def make_store(self, root: Path) -> MathWorkbookStore:
        upgrade(str(root / "store.sqlite3"))
        return MathWorkbookStore(str(root / "store.sqlite3"), str(root / "files"))
    def make_page(self, root: Path, colored: bool) -> Path:
        image = Image.new("RGB", (240, 160), "white")
        draw = ImageDraw.Draw(image)
        draw.text((12, 12), "f(x)=x^2", fill="black")
        if colored:
            draw.line((20, 90, 190, 110), fill=(230, 30, 50), width=5)
        path = root / "source.jpg"
        image.save(path)
        return path

    def test_colored_ink_and_no_colored_ink(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            normalized = normalize_page(self.make_page(root, True), root / "normalized.png")
            result = segment_colored_ink(Path(normalized.normalized_path), root / "color")
            self.assertTrue(result.has_colored_handwriting)
            self.assertGreater(result.mask_coverage_ratio, 0)
            plain = normalize_page(self.make_page(root, False), root / "plain.png")
            plain_result = segment_colored_ink(Path(plain.normalized_path), root / "plain-color")
            self.assertFalse(plain_result.has_colored_handwriting)

    def test_repetition_is_needs_review_signal(self):
        flags = formula_quality_flags("\\frac{1}{x}" * 80, 30, 20)
        self.assertIn("suspicious_repetition", flags)
        self.assertIn("abnormal_length", flags)

    def test_raw_and_user_latex_are_separate(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            store = self.make_store(root)
            import_id = store.create_import("image", "source.jpg")
            page_id = store.create_page(import_id, 0, "source.jpg", {}, "needs_review")
            region_id = store.add_region(page_id, {"region_type": "printed_problem_area", "bbox": (0, 0, 10, 10), "reading_order": 0})
            block_id = store.add_source_block(page_id, {"parent_region_id": region_id, "block_type": "formula_block", "bbox": (0, 0, 10, 10), "reading_order": 0})
            formula_id = store.add_formula(page_id, {"region_id": region_id, "source_block_id": block_id, "bbox": (0, 0, 10, 10), "raw_latex": "x+1", "recognition_score": None, "reading_order": 0})
            updated = store.update_formula(formula_id, {"user_confirmed_latex": "x+2"})
            self.assertEqual(updated["raw_latex"], "x+1")
            self.assertEqual(updated["user_confirmed_latex"], "x+2")

    def test_raw_provider_json_and_missing_score_are_preserved_without_default(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            store = self.make_store(root)
            import_id = store.create_import("image", "source.jpg")
            page_id = store.create_page(import_id, 0, "source.jpg", {}, "needs_review")
            path = store.save_raw_result(page_id, "paddleocr", "PP-StructureV3", {"result": {"layouts": [{"text": "x"}]}})
            self.assertTrue(Path(path).exists())
            region_id = store.add_region(page_id, {"region_type": "printed_problem_area", "bbox": (0, 0, 10, 10), "reading_order": 0})
            block_id = store.add_source_block(page_id, {"parent_region_id": region_id, "block_type": "formula_block", "bbox": (0, 0, 10, 10), "reading_order": 0})
            formula_id = store.add_formula(page_id, {"region_id": region_id, "source_block_id": block_id, "bbox": (0, 0, 10, 10), "raw_latex": "x", "recognition_score": None, "reading_order": 0})
            formula = store.get_formula(formula_id)
            self.assertIsNone(formula["recognition_score"])

    def test_idempotency_and_job_lease_and_problem_revision(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); store = self.make_store(root)
            first = store.reserve_idempotency("u1", "import", "key", {"a": 1})
            self.assertEqual(first["status"], "processing")
            self.assertEqual(store.reserve_idempotency("u1", "import", "key", {"a": 1})["id"], first["id"])
            with self.assertRaises(Exception): store.reserve_idempotency("u1", "import", "key", {"a": 2})
            job = store.enqueue_job("import", "x", "segment")
            self.assertEqual(store.claim_job("a")["id"], job)
            self.assertIsNone(store.claim_job("b"))
            self.assertFalse(store.complete_job(job, "b")); self.assertTrue(store.complete_job(job, "a"))
            imp = store.create_import("image", "source.jpg", "u1"); page = store.create_page(imp, 0, "source.jpg", {}, "ready")
            region = store.add_region(page, {"region_type":"printed_problem_area","bbox":(0,0,1,1),"reading_order":0})
            block = store.add_source_block(page, {"parent_region_id":region,"block_type":"formula_block","bbox":(0,0,1,1),"reading_order":0})
            formula = store.add_formula(page, {"region_id":region,"source_block_id":block,"bbox":(0,0,1,1),"raw_latex":"x","reading_order":0})
            problem = store.create_problem("u1", imp, page, [0,0,1,1], [{"source_kind":"formula","source_id":formula,"semantic_role":"prompt","reading_order":0}])
            store.update_formula(formula, {"user_confirmed_latex":"x"})
            self.assertGreater(store.get_problem(problem["id"], "u1")["source_revision"], 1)
            with self.assertRaises(Exception): store.update_problem(problem["id"], "u1", 1, {"problem_type_hint":"limit"})

    def test_migration_is_repeatable_and_legacy_upgrade(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); db = root / "legacy.sqlite3"
            import sqlite3
            con = sqlite3.connect(db)
            con.executescript((Path(__file__).parents[1] / "app/math_workbook/migrations/0001_initial.sql").read_text())
            con.commit(); con.close()
            self.assertEqual(upgrade(str(db)), 9); self.assertEqual(upgrade(str(db)), 9)
            with sqlite3.connect(db) as check:
                self.assertEqual(check.execute("SELECT MAX(version) FROM schema_migrations").fetchone()[0], 9)
                self.assertTrue(check.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='math_processing_jobs'").fetchone())


if __name__ == "__main__":
    unittest.main()
