from __future__ import annotations

import asyncio
import concurrent.futures
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

import sympy
from app.math_workbook.explanation.trace import build_deterministic_trace
from app.math_workbook.ir.problem_ir import build_problem_ir
from app.math_workbook.ir.expression_nodes import from_dict
from app.math_workbook.migrations.runner import upgrade
from app.math_workbook.parsing.normalization import normalize
from app.math_workbook.parsing.parser import parse
from app.math_workbook.parsing.tokenizer import tokenize
from app.math_workbook.rendering.latex_renderer import render_latex
from app.math_workbook.storage import MathWorkbookStore
from app.math_workbook.execution.solver_executor import IsolatedSolverExecutor
from app.math_workbook.sympy_bridge.builder import AstSympyBuilder
from app.math_workbook.sympy_bridge.symbol_table import SymbolTable
from app.routes import math_workbook as math_routes
from app.routes.math_workbook import SolveRequest


def _parsed(formula: str):
    root = parse(tokenize(normalize(formula).normalized, "post-merge"))
    ir = build_problem_ir("p", 1, [root], ["formula"]).to_dict()
    return root, ir


def _store_and_problem(root: Path, formula: str = "2x+3=7"):
    database = root / "db.sqlite"
    upgrade(str(database))
    store = MathWorkbookStore(str(database), str(root / "files"))
    import_id = store.create_import("image", "source.jpg", "u")
    page_id = store.create_page(import_id, 0, "source.jpg", {}, "ready")
    region_id = store.add_region(page_id, {"region_type": "printed_problem_area", "bbox": (0, 0, 1, 1), "reading_order": 0})
    block_id = store.add_source_block(page_id, {"parent_region_id": region_id, "block_type": "formula_block", "bbox": (0, 0, 1, 1), "reading_order": 0})
    formula_id = store.add_formula(page_id, {"region_id": region_id, "source_block_id": block_id, "bbox": (0, 0, 1, 1), "source_type": "printed", "role": "problem_expression", "raw_latex": formula, "reading_order": 0})
    store.update_formula(formula_id, {"user_confirmed_latex": formula}, "u")
    problem = store.create_problem("u", import_id, page_id, [0, 0, 1, 1], [{"source_kind": "formula", "source_id": formula_id, "semantic_role": "prompt", "reading_order": 0}])
    store.parse_problem(problem["id"], "u", problem["revision"])
    store.build_problem(problem["id"], "u")
    store.analyze_problem(problem["id"], "u")
    return store, problem, formula_id


def _with_safe_spans(value):
    if isinstance(value, dict):
        result = {key: _with_safe_spans(item) for key, item in value.items()}
        result.setdefault("source_span", {"start": 0, "end": 0})
        result.setdefault("source_formula_id", "")
        return result
    if isinstance(value, list):
        return [_with_safe_spans(item) for item in value]
    return value


class ExponentAndTraceHardeningTests(unittest.TestCase):
    def test_exponent_grouping_is_unambiguous(self):
        expected = {
            "2^2": "2^2",
            "2^10": "2^{10}",
            "2^-2": "2^{-2}",
            "x^n": "x^n",
            "x^(1/2)": r"x^{\frac{1}{2}}",
            "x^(a+b)": "x^{a+b}",
            "(-x)^2": "(-x)^2",
            "-x^2": "-x^2",
        }
        for formula, display in expected.items():
            with self.subTest(formula=formula):
                root, _ = _parsed(formula)
                self.assertEqual(render_latex(root), display)
        root, ir = _parsed("2^10")
        trace = build_deterministic_trace(root, {"candidate_type": "exact_value", "values": []}, ir)
        self.assertEqual(trace["steps"][0]["before_latex"], r"2^{10}")
        self.assertEqual(trace["steps"][0]["after_latex"], "1024")

    def test_linear_trace_contains_only_authentic_elementary_steps(self):
        cases = {
            "2x+3=7": ["subtract_constant_both_sides", "divide_both_sides_by_coefficient"],
            "2x+3=x+5": ["subtract_variable_term_both_sides", "subtract_constant_both_sides"],
            "2x+3=4x+7": ["subtract_variable_term_both_sides", "subtract_constant_both_sides", "divide_both_sides_by_coefficient"],
            "x+3=2x+3": ["subtract_variable_term_both_sides", "subtract_constant_both_sides", "divide_both_sides_by_coefficient"],
            "3-x=5": ["subtract_constant_both_sides", "divide_both_sides_by_coefficient"],
            "-x+3=7": ["subtract_constant_both_sides", "divide_both_sides_by_coefficient"],
        }
        values = {"2x+3=7": 2, "2x+3=x+5": 2, "2x+3=4x+7": -2, "x+3=2x+3": 0, "3-x=5": -2, "-x+3=7": -4}
        for formula, rules in cases.items():
            with self.subTest(formula=formula):
                root, ir = _parsed(formula)
                trace = build_deterministic_trace(root, {"candidate_type": "unique_candidate", "values": [{"value": {"kind": "integer", "value": values[formula]}}]}, ir)
                self.assertEqual([step["rule_id"] for step in trace["steps"]], rules)
                for before, after in zip(trace["steps"], trace["steps"][1:]):
                    self.assertEqual(before["after_latex"], after["before_latex"])
                    before_ast = from_dict(_with_safe_spans(before["before_ast"]))
                    after_ast = from_dict(_with_safe_spans(after["after_ast"]))
                    table = SymbolTable(ir["variables"])
                    before_expr = AstSympyBuilder(table).build(before_ast)
                    after_expr = AstSympyBuilder(table).build(after_ast)
                    symbol = next(iter(table.symbols.values()))
                    self.assertEqual(
                        sympy.solveset(before_expr.lhs - before_expr.rhs, symbol, domain=sympy.S.Reals),
                        sympy.solveset(after_expr.lhs - after_expr.rhs, symbol, domain=sympy.S.Reals),
                    )
                self.assertEqual(trace["steps"][0]["before_latex"], render_latex(root))


class SolutionStateAndSolverIsolationTests(unittest.TestCase):
    def test_solution_state_and_post_solve_dedupe_preserve_verified_report(self):
        with tempfile.TemporaryDirectory() as temporary:
            store, problem, _ = _store_and_problem(Path(temporary))
            candidate = store.solve_problem(problem["id"], "u", problem["revision"])
            self.assertEqual(store.current_solution_state(problem["id"], "u")["verification_status"], "not_started")
            report = store.verify_problem(problem["id"], "u", problem["revision"])
            state = store.current_solution_state(problem["id"], "u")
            self.assertTrue(state["is_verified"])
            self.assertEqual(state["verification_status"], "verified")
            self.assertEqual(state["verification_report_id"], report["id"])
            again = store.solve_problem(problem["id"], "u", problem["revision"])
            self.assertEqual(again["id"], candidate["id"])
            self.assertTrue(store.current_solution_state(problem["id"], "u")["is_verified"])
            with patch.object(math_routes, "_get_store", return_value=store):
                response = asyncio.run(math_routes.get_math_solution(problem["id"], "u"))
            self.assertTrue(response["is_verified"])
            self.assertEqual(response["verification_status"], "verified")

    def test_old_verified_state_disappears_after_source_revision_change(self):
        with tempfile.TemporaryDirectory() as temporary:
            store, problem, formula_id = _store_and_problem(Path(temporary))
            store.solve_problem(problem["id"], "u", problem["revision"])
            store.verify_problem(problem["id"], "u", problem["revision"])
            store.update_formula(formula_id, {"user_confirmed_latex": "2x+4=7"}, "u")
            state = store.current_solution_state(problem["id"], "u")
            self.assertIsNone(state["current_result"])
            self.assertFalse(state["is_verified"])
            self.assertEqual(state["verification_status"], "not_started")

    def test_solver_worker_does_not_hold_write_lock(self):
        with tempfile.TemporaryDirectory() as temporary:
            store, problem, _ = _store_and_problem(Path(temporary))
            started, release = threading.Event(), threading.Event()
            original = IsolatedSolverExecutor.execute

            def slow(executor, request):
                started.set()
                self.assertTrue(release.wait(5))
                return original(executor, request)

            with patch.object(IsolatedSolverExecutor, "execute", slow):
                with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                    future = pool.submit(store.solve_problem, problem["id"], "u", problem["revision"])
                    self.assertTrue(started.wait(3))
                    other_import = store.create_import("image", "other.jpg", "other")
                    self.assertTrue(other_import)
                    release.set()
                    result = future.result(timeout=15)
            self.assertEqual(result["status"], "candidate")

    def test_solver_revision_race_rejects_old_worker_result(self):
        with tempfile.TemporaryDirectory() as temporary:
            store, problem, formula_id = _store_and_problem(Path(temporary))
            started, release = threading.Event(), threading.Event()
            original = IsolatedSolverExecutor.execute

            def slow(executor, request):
                started.set()
                self.assertTrue(release.wait(5))
                return original(executor, request)

            with patch.object(IsolatedSolverExecutor, "execute", slow):
                with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                    future = pool.submit(store.solve_problem, problem["id"], "u", problem["revision"])
                    self.assertTrue(started.wait(3))
                    store.update_formula(formula_id, {"user_confirmed_latex": "2x+4=7"}, "u")
                    release.set()
                    with self.assertRaisesRegex(ValueError, "SOLVE_INPUT_CHANGED"):
                        future.result(timeout=15)
            self.assertIsNone(store.current_solution_state(problem["id"], "u")["current_result"])

    def test_equal_solver_workers_dedupe_to_one_candidate(self):
        with tempfile.TemporaryDirectory() as temporary:
            store, problem, _ = _store_and_problem(Path(temporary))
            candidate_result = {"status": "candidate", "candidate_type": "unique_candidate", "values": [{"value": {"kind": "integer", "value": 2}}], "requires_checks": ["substitution", "domain_constraints"]}
            execution = {"status": "candidate", "candidate_result": candidate_result, "errors": [], "duration_ms": 1, "execution_mode": "isolated_process", "worker_exit_code": 0, "timed_out": False, "termination_method": "none"}
            with patch.object(IsolatedSolverExecutor, "execute", return_value=execution):
                with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                    results = list(pool.map(lambda _: store.solve_problem(problem["id"], "u", problem["revision"]), range(2)))
            self.assertEqual({result["id"] for result in results}, {results[0]["id"]})
            self.assertEqual(store.current_solution_state(problem["id"], "u")["current_result"]["id"], results[0]["id"])


if __name__ == "__main__":
    unittest.main()
