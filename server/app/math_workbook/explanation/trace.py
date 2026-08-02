"""Deterministic teaching traces for the currently verified math classes.

This module is the only place that turns a verified AST/candidate pair into
teaching steps.  The provider receives these steps as read-only input and can
only add prose around them.
"""

from __future__ import annotations

from typing import Any

import sympy

from app.math_workbook.ir.expression_nodes import (
    AddNode,
    DivideNode,
    EquationNode,
    GreaterThanNode,
    GreaterThanOrEqualNode,
    IntegerNode,
    LessThanNode,
    LessThanOrEqualNode,
    MultiplyNode,
    NegateNode,
    Node,
    PowerNode,
    SquareRootNode,
    SubtractNode,
    SymbolNode,
    from_dict,
)
from app.math_workbook.rendering.latex_renderer import RENDERER_VERSION, render_latex
from app.math_workbook.sympy_bridge.builder import AstSympyBuilder
from app.math_workbook.sympy_bridge.symbol_table import SymbolTable


TRACE_VERSION = "1"

TRACE_RULE_IDS = frozenset(
    {
        "evaluate_exact_expression",
        "normalize_linear_equation",
        "subtract_variable_term_both_sides",
        "subtract_constant_both_sides",
        "divide_both_sides_by_coefficient",
        "linear_unique_solution",
        "linear_identity_conclusion",
        "linear_no_solution_conclusion",
        "normalize_to_standard_form",
        "extract_quadratic_coefficients",
        "quadratic_discriminant",
        "quadratic_no_real_discriminant",
        "quadratic_formula_root",
        "inequality_constant_truth",
        "divide_by_positive_coefficient",
        "divide_by_negative_and_reverse_relation",
        "deterministic_solver_summary",
    }
)

# Human-readable documentation for the immutable rule identifiers.  These
# descriptions are server-owned metadata: a provider may explain a rule that
# appears in a trace, but it can never create a new rule identifier.
TRACE_RULE_DESCRIPTIONS = {
    "evaluate_exact_expression": "evaluate the exact numeric expression",
    "normalize_linear_equation": "normalize a linear equation without changing its solution set",
    "subtract_variable_term_both_sides": "subtract the same variable term from both sides",
    "subtract_constant_both_sides": "subtract the same constant from both sides",
    "divide_both_sides_by_coefficient": "divide both sides by a non-zero coefficient",
    "linear_unique_solution": "state the unique linear solution",
    "linear_identity_conclusion": "conclude that a linear identity holds for every permitted value",
    "linear_no_solution_conclusion": "conclude that a linear equation has no permitted solution",
    "normalize_to_standard_form": "normalize a quadratic equation to standard form",
    "extract_quadratic_coefficients": "extract the quadratic coefficients",
    "quadratic_discriminant": "compute the quadratic discriminant",
    "quadratic_no_real_discriminant": "use a negative discriminant to rule out real roots",
    "quadratic_formula_root": "evaluate one root from the quadratic formula",
    "inequality_constant_truth": "evaluate a constant inequality",
    "divide_by_positive_coefficient": "divide an inequality by a positive coefficient",
    "divide_by_negative_and_reverse_relation": "divide by a negative coefficient and reverse the relation",
    "deterministic_solver_summary": "summarize a server-verified result",
}


def _span() -> dict[str, int]:
    return {"start": 0, "end": 0}


def _node(cls: type[Node], *args: Any) -> Node:
    return cls(_span(), "", *args)


def _integer(value: int) -> IntegerNode:
    return _node(IntegerNode, int(value))  # type: ignore[return-value]


def _symbol(name: str) -> SymbolNode:
    return _node(SymbolNode, name)  # type: ignore[return-value]


def _from_sympy(value: sympy.Expr) -> Node:
    """Build a display AST from exact integer/rational values only."""

    value = sympy.cancel(value)
    if value.is_Integer:
        return _integer(int(value))
    if value.is_Rational:
        numerator, denominator = int(value.p), int(value.q)
        if denominator == 1:
            return _integer(numerator)
        return _node(DivideNode, _integer(numerator), _integer(denominator))
    raise ValueError("TRACE_REQUIRES_RATIONAL_VALUE")


def _value_payload(value: sympy.Expr) -> dict[str, Any]:
    value = sympy.cancel(value)
    if value.is_Integer:
        return {"kind": "integer", "value": int(value)}
    if value.is_Rational:
        return {"kind": "rational", "numerator": int(value.p), "denominator": int(value.q)}
    return {"kind": "exact_symbolic", "display_latex": sympy.latex(value)}


def _candidate_sympy(item: dict[str, Any]) -> sympy.Expr | None:
    data = item.get("value", {}) if isinstance(item, dict) else {}
    if data.get("kind") == "integer":
        return sympy.Integer(data["value"])
    if data.get("kind") == "rational":
        return sympy.Rational(data["numerator"], data["denominator"])
    return None


def _public_ast(node: Node) -> dict[str, Any]:
    raw = node.to_dict()

    def clean(value: Any) -> Any:
        if isinstance(value, dict):
            return {key: clean(item) for key, item in value.items() if key not in {"source_span", "source_formula_id"}}
        if isinstance(value, list):
            return [clean(item) for item in value]
        return value

    return clean(raw)


def _step(
    index: int,
    rule_id: str,
    before: Node,
    after: Node,
    parameters: dict[str, Any] | None = None,
    justification_code: str = "equation_balance",
) -> dict[str, Any]:
    if rule_id not in TRACE_RULE_IDS:
        raise ValueError("TRACE_RULE_NOT_ALLOWED")
    return {
        "index": index,
        "rule_id": rule_id,
        "before_ast": _public_ast(before),
        "after_ast": _public_ast(after),
        "before_latex": render_latex(before),
        "after_latex": render_latex(after),
        "parameters": parameters or {},
        "justification_code": justification_code,
    }


def validate_trace_artifact(trace: Any, expected_trace_version: str = TRACE_VERSION, expected_renderer_version: str = RENDERER_VERSION) -> dict[str, Any]:
    """Validate a worker-produced trace without importing or executing SymPy."""

    if not isinstance(trace, dict):
        raise ValueError("TRACE_MISSING")
    if trace.get("trace_version") != expected_trace_version or trace.get("renderer_version") != expected_renderer_version:
        raise ValueError("TRACE_STALE")
    steps = trace.get("steps")
    if not isinstance(steps, list) or not steps:
        raise ValueError("TRACE_MISSING")
    for expected_index, step in enumerate(steps, start=1):
        if not isinstance(step, dict):
            raise ValueError("TRACE_INVALID")
        required = {"index", "rule_id", "before_ast", "after_ast", "before_latex", "after_latex", "parameters", "justification_code"}
        if set(step) != required:
            raise ValueError("TRACE_INVALID")
        if step["index"] != expected_index or step["rule_id"] not in TRACE_RULE_IDS:
            raise ValueError("TRACE_INVALID")
        if step["rule_id"] not in TRACE_RULE_DESCRIPTIONS:
            raise ValueError("TRACE_INVALID")
        if not isinstance(step["before_ast"], dict) or not isinstance(step["after_ast"], dict):
            raise ValueError("TRACE_INVALID")
        if not isinstance(step["before_latex"], str) or not isinstance(step["after_latex"], str):
            raise ValueError("TRACE_INVALID")
        if not isinstance(step["parameters"], dict) or not isinstance(step["justification_code"], str):
            raise ValueError("TRACE_INVALID")
    binding = trace.get("binding")
    if binding is not None and not isinstance(binding, dict):
        raise ValueError("TRACE_INVALID")
    return trace


def _linear_term(coefficient: sympy.Expr, symbol: SymbolNode) -> Node:
    coefficient = sympy.cancel(coefficient)
    if coefficient == 0:
        return _integer(0)
    symbol_node = _symbol(symbol.name)
    if coefficient == 1:
        return symbol_node
    if coefficient == -1:
        return _node(NegateNode, symbol_node)
    return _node(MultiplyNode, _from_sympy(coefficient), symbol_node)


def _add_constant(term: Node, constant: sympy.Expr) -> Node:
    constant = sympy.cancel(constant)
    if constant == 0:
        return term
    if constant.is_negative:
        return _node(SubtractNode, term, _from_sympy(-constant))
    return _node(AddNode, term, _from_sympy(constant))


def _standard_polynomial(a: sympy.Expr, b: sympy.Expr, c: sympy.Expr | None, symbol: SymbolNode) -> Node:
    if c is None:
        return _add_constant(_linear_term(a, symbol), b)
    square = _node(PowerNode, _symbol(symbol.name), _integer(2))
    if a == 0:
        term: Node = _integer(0)
    elif a == 1:
        term = square
    elif a == -1:
        term = _node(NegateNode, square)
    else:
        term = _node(MultiplyNode, _from_sympy(a), square)
    if b != 0:
        if b.is_negative:
            term = _node(SubtractNode, term, _linear_term(-b, symbol))
        else:
            term = _node(AddNode, term, _linear_term(b, symbol))
    return _add_constant(term, c)


def _equation(left: Node, right: Node) -> EquationNode:
    return _node(EquationNode, left, right)  # type: ignore[return-value]


def _relation(left: Node, right: Node, original: Node, reverse: bool = False) -> Node:
    relation_classes = {
        LessThanNode: GreaterThanNode,
        LessThanOrEqualNode: GreaterThanOrEqualNode,
        GreaterThanNode: LessThanNode,
        GreaterThanOrEqualNode: LessThanOrEqualNode,
    }
    for cls in (LessThanNode, LessThanOrEqualNode, GreaterThanNode, GreaterThanOrEqualNode):
        if isinstance(original, cls):
            return _node(relation_classes[cls] if reverse else cls, left, right)
    return _equation(left, right)


def _symbol_from_ir(root: Node, problem_ir: dict[str, Any]) -> SymbolNode | None:
    variables = problem_ir.get("variables", []) if isinstance(problem_ir, dict) else []
    if variables:
        return _symbol(str(variables[0].get("name", "x")))
    stack = [root]
    while stack:
        node = stack.pop()
        if isinstance(node, SymbolNode):
            return _symbol(node.name)
        for key in ("left", "right", "base", "exponent", "operand"):
            if hasattr(node, key):
                stack.append(getattr(node, key))
    return None


def _numeric_trace(root: Node, problem_ir: dict[str, Any]) -> list[dict[str, Any]]:
    table = SymbolTable(problem_ir.get("variables", []))
    expression = AstSympyBuilder(table).build(root)
    # The safe AST builder deliberately constructs powers with
    # ``evaluate=False``.  ``doit``/``simplify`` is still exact here (the
    # numeric solver route has already established that no symbols remain),
    # and is required for values such as ``2^10`` to become the deterministic
    # integer 1024 rather than an unevaluated ``2**10``.
    value = sympy.cancel(sympy.simplify(expression.doit()))
    after = _from_sympy(value)
    return [_step(1, "evaluate_exact_expression", root, after, {"value": _value_payload(value)}, "exact_arithmetic")]


def _linear_equation_trace(root: Node, candidate: dict[str, Any], problem_ir: dict[str, Any]) -> list[dict[str, Any]]:
    symbol = _symbol_from_ir(root, problem_ir)
    if symbol is None or not isinstance(root, EquationNode):
        return [_step(1, "deterministic_solver_summary", root, root, {}, "verified_result")]
    table = SymbolTable(problem_ir.get("variables", []))
    expression = AstSympyBuilder(table).build(root)
    sym = next(iter(table.symbols.values()))
    poly = sympy.Poly(expression.lhs - expression.rhs, sym)
    coeffs = poly.all_coeffs()
    if poly.degree() == 0 or poly.is_zero:
        b = coeffs[0] if coeffs else sympy.Integer(0)
        standard = _equation(_integer(0), _from_sympy(-b))
        steps = [_step(1, "normalize_linear_equation", root, standard, {"coefficient": _value_payload(sympy.Integer(0)), "constant": _value_payload(b)}, "equation_normalization")]
        rule = "linear_identity_conclusion" if candidate.get("candidate_type") == "identity_candidate" else "linear_no_solution_conclusion"
        steps.append(_step(2, rule, standard, standard, {"candidate_type": candidate.get("candidate_type", "")}, "solution_completeness"))
        return steps
    a, b = coeffs
    left = sympy.expand(expression.lhs)
    right = sympy.expand(expression.rhs)
    right_coefficient = sympy.cancel(right.coeff(sym, 1))
    left_constant = sympy.cancel(left.subs(sym, 0))
    right_constant = sympy.cancel(right.subs(sym, 0))
    term = _linear_term(a, symbol)
    steps: list[dict[str, Any]] = []

    # Move the variable term from the right side first.  The previous trace
    # jumped directly to ``(left_coefficient-right_coefficient)x = ...`` and
    # labelled that jump as a constant subtraction, which was not an
    # authentic elementary transformation for equations containing x on both
    # sides.
    current: Node = root
    if right_coefficient != 0:
        variable_after = _equation(
            _add_constant(term, left_constant),
            _from_sympy(right_constant),
        )
        steps.append(
            _step(
                len(steps) + 1,
                "subtract_variable_term_both_sides",
                current,
                variable_after,
                {
                    "coefficient": _value_payload(right_coefficient),
                    "side": "right",
                    "term": _value_payload(right_coefficient * sym),
                },
                "equation_balance",
            )
        )
        current = variable_after

    target = _equation(term, _from_sympy(right_constant - left_constant))
    if left_constant != 0:
        steps.append(
            _step(
                len(steps) + 1,
                "subtract_constant_both_sides",
                current,
                target,
                {"constant": _value_payload(left_constant), "side": "left"},
                "equation_balance",
            )
        )
        current = target
    elif not steps or render_latex(current) != render_latex(target):
        steps.append(
            _step(
                len(steps) + 1,
                "normalize_linear_equation",
                current,
                target,
                {"coefficient": _value_payload(a), "constant": _value_payload(right_constant)},
                "equation_normalization",
            )
        )
        current = target
    values = [_candidate_sympy(item) for item in candidate.get("values", [])]
    value = values[0] if values else sympy.cancel(-b / a)
    if a != 1:
        solved = _equation(_symbol(symbol.name), _from_sympy(value))
        steps.append(_step(len(steps) + 1, "divide_both_sides_by_coefficient", current, solved, {"coefficient": _value_payload(a)}, "equation_balance_nonzero_divisor"))
    elif render_latex(current) != render_latex(_equation(_symbol(symbol.name), _from_sympy(value))):
        solved = _equation(_symbol(symbol.name), _from_sympy(value))
        steps.append(_step(len(steps) + 1, "linear_unique_solution", current, solved, {"value": _value_payload(value)}, "solution_completeness"))
    return steps


def _quadratic_trace(root: Node, candidate: dict[str, Any], problem_ir: dict[str, Any]) -> list[dict[str, Any]]:
    symbol = _symbol_from_ir(root, problem_ir)
    if symbol is None or not isinstance(root, EquationNode):
        return [_step(1, "deterministic_solver_summary", root, root, {}, "verified_result")]
    table = SymbolTable(problem_ir.get("variables", []))
    expression = AstSympyBuilder(table).build(root)
    sym = next(iter(table.symbols.values()))
    poly = sympy.Poly(expression.lhs - expression.rhs, sym)
    if poly.degree() != 2:
        return _linear_equation_trace(root, candidate, problem_ir)
    a, b, c = poly.all_coeffs()
    standard_expr = _standard_polynomial(a, b, c, symbol)
    standard = _equation(standard_expr, _integer(0))
    steps = [_step(1, "normalize_to_standard_form", root, standard, {}, "equation_normalization")]
    steps.append(_step(2, "extract_quadratic_coefficients", standard, standard, {"a": _value_payload(a), "b": _value_payload(b), "c": _value_payload(c)}, "quadratic_coefficient_extraction"))
    discriminant = sympy.cancel(b * b - 4 * a * c)
    delta = _equation(_symbol("\\Delta"), _from_sympy(discriminant))
    steps.append(_step(3, "quadratic_discriminant", standard, delta, {"a": _value_payload(a), "b": _value_payload(b), "c": _value_payload(c), "discriminant": _value_payload(discriminant)}, "quadratic_discriminant"))
    if discriminant.is_negative:
        negative = _node(LessThanNode, _symbol("\\Delta"), _integer(0))
        steps.append(_step(4, "quadratic_no_real_discriminant", delta, negative, {"discriminant": _value_payload(discriminant)}, "real_domain_constraint"))
        return steps
    values = [_candidate_sympy(item) for item in candidate.get("values", [])]
    if not values:
        values = [sympy.cancel((-b + sympy.sqrt(discriminant)) / (2 * a))] if discriminant == 0 else []
    for index, value in enumerate(values, start=1):
        if value is None:
            continue
        try:
            after = _equation(_symbol(symbol.name), _from_sympy(value))
        except ValueError:
            # The current verifier only accepts integer/rational candidates;
            # keep the trace deterministic if a future exact type is added.
            continue
        steps.append(_step(len(steps) + 1, "quadratic_formula_root", delta, after, {"root_index": index, "discriminant": _value_payload(discriminant), "value": _value_payload(value)}, "quadratic_formula"))
    return steps


def _inequality_trace(root: Node, candidate: dict[str, Any], problem_ir: dict[str, Any]) -> list[dict[str, Any]]:
    symbol = _symbol_from_ir(root, problem_ir)
    if symbol is None:
        return [_step(1, "deterministic_solver_summary", root, root, {}, "verified_result")]
    table = SymbolTable(problem_ir.get("variables", []))
    expression = AstSympyBuilder(table).build(root)
    sym = next(iter(table.symbols.values()))
    poly = sympy.Poly(expression.lhs - expression.rhs, sym)
    if poly.degree() != 1:
        return [_step(1, "deterministic_solver_summary", root, root, {}, "verified_result")]
    a, b = poly.all_coeffs()
    left_constant = sympy.cancel(expression.lhs.subs(sym, 0))
    right_constant = sympy.cancel(expression.rhs.subs(sym, 0))
    moved_constant = left_constant if left_constant != 0 else right_constant
    standard = _relation(_linear_term(a, symbol), _from_sympy(-b), root)
    steps = [_step(1, "subtract_constant_both_sides", root, standard, {"constant": _value_payload(moved_constant)}, "relation_balance")]
    boundary = sympy.cancel(-b / a)
    solved = _relation(_symbol(symbol.name), _from_sympy(boundary), root, reverse=bool(a.is_negative))
    rule = "divide_by_negative_and_reverse_relation" if a.is_negative else "divide_by_positive_coefficient"
    justification = "inequality_division_negative" if a.is_negative else "inequality_division_positive"
    steps.append(_step(2, rule, standard, solved, {"coefficient": _value_payload(a), "boundary": _value_payload(boundary)}, justification))
    return steps


def build_deterministic_trace(root: Node | dict[str, Any], candidate: dict[str, Any], problem_ir: dict[str, Any]) -> dict[str, Any]:
    """Return a versioned trace with only server-generated mathematical data."""

    if isinstance(root, dict):
        root = from_dict(root)
    candidate_type = candidate.get("candidate_type")
    quadratic_no_real = False
    if candidate_type == "no_solution_candidate" and isinstance(root, EquationNode):
        try:
            table = SymbolTable(problem_ir.get("variables", []))
            expression = AstSympyBuilder(table).build(root)
            symbols = list(table.symbols.values())
            quadratic_no_real = bool(symbols and sympy.Poly(expression.lhs - expression.rhs, symbols[0]).degree() == 2)
        except Exception:
            quadratic_no_real = False
    if candidate_type == "exact_value":
        steps = _numeric_trace(root, problem_ir)
    elif candidate_type in {"unique_candidate", "identity_candidate"} or (candidate_type == "no_solution_candidate" and not quadratic_no_real):
        steps = _linear_equation_trace(root, candidate, problem_ir)
    elif candidate_type in {"two_real_candidates", "one_repeated_real_candidate"} or quadratic_no_real:
        steps = _quadratic_trace(root, candidate, problem_ir)
    elif candidate_type == "interval_candidate":
        steps = _inequality_trace(root, candidate, problem_ir)
    else:
        steps = [_step(1, "deterministic_solver_summary", root, root, {"candidate_type": candidate_type or ""}, "verified_result")]
    return {"trace_version": TRACE_VERSION, "renderer_version": RENDERER_VERSION, "steps": steps}


def attach_trace_binding(trace: dict[str, Any], *, problem_id: str, source_revision: int, candidate_solution_result_id: str, verification_report_id: str, input_hash: str) -> dict[str, Any]:
    return {
        **trace,
        "binding": {
            "problem_id": problem_id,
            "source_revision": source_revision,
            "candidate_solution_result_id": candidate_solution_result_id,
            "verification_report_id": verification_report_id,
            "input_hash": input_hash,
            "trace_version": trace["trace_version"],
            "renderer_version": trace["renderer_version"],
        },
    }
