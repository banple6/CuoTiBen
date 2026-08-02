"""Stable, non-parsing LaTeX rendering for the canonical AST.

The renderer is deliberately one way: it consumes AST nodes and never accepts
formula text.  This keeps presentation deterministic and prevents a display
string from becoming a second parser entry point.
"""

from __future__ import annotations

from app.math_workbook.ir.expression_nodes import (
    AddNode,
    DecimalNode,
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
)


RENDERER_VERSION = "1"

# Larger number means tighter binding.  Relations are deliberately weakest.
_PRECEDENCE = {
    EquationNode: 10,
    LessThanNode: 10,
    LessThanOrEqualNode: 10,
    GreaterThanNode: 10,
    GreaterThanOrEqualNode: 10,
    AddNode: 20,
    SubtractNode: 20,
    MultiplyNode: 30,
    DivideNode: 30,
    NegateNode: 40,
    PowerNode: 50,
    SquareRootNode: 60,
    IntegerNode: 70,
    DecimalNode: 70,
    SymbolNode: 70,
}


def _precedence(node: Node) -> int:
    try:
        return _PRECEDENCE[type(node)]
    except KeyError as exc:  # pragma: no cover - defensive AST boundary
        raise ValueError("UNSUPPORTED_RENDER_NODE") from exc


def _wrap(text: str, node: Node, parent: int, *, right: bool = False) -> str:
    child = _precedence(node)
    if child < parent or (right and child == parent):
        return f"({text})"
    return text


def _is_numeric_atom(node: Node) -> bool:
    """Whether *node* is a scalar literal that can be a coefficient.

    This is intentionally based on AST node types rather than rendered text.
    In particular, a fraction is not treated as a coefficient here: keeping
    ``\\frac{1}{2}\\cdot\\frac{3}{4}`` explicit avoids an ambiguous display.
    """

    if isinstance(node, (IntegerNode, DecimalNode)):
        return True
    return isinstance(node, NegateNode) and isinstance(node.operand, (IntegerNode, DecimalNode))


def _is_group(node: Node) -> bool:
    return isinstance(node, (AddNode, SubtractNode))


def _can_juxtapose(left: Node, right: Node) -> bool:
    """Return whether implicit multiplication is unambiguous for this AST.

    The safe whitelist is deliberately conservative: a scalar literal may sit
    before a symbol/power/root/group, and two grouped factors may be adjacent.
    Every other pair receives an explicit ``\\cdot``.
    """

    if _is_numeric_atom(left) and isinstance(right, (SymbolNode, PowerNode, SquareRootNode)):
        return True
    if _is_numeric_atom(left) and _is_group(right):
        return True
    return _is_group(left) and _is_group(right)


def _multiply_wrap(text: str, node: Node, *, right: bool) -> str:
    """Wrap multiplication operands without parenthesizing a fraction."""

    child = _precedence(node)
    if child < 30 or (right and isinstance(node, NegateNode)) or (right and child == 30 and not isinstance(node, DivideNode)):
        return f"({text})"
    return text


def _exponent_requires_braces(node: Node) -> bool:
    """Return whether an exponent must be grouped for an unambiguous TeX token.

    TeX consumes exactly one token after ``^``.  A one-digit integer and a
    single symbol are therefore safe without braces, while a multi-digit
    number, decimal, unary sign, fraction, or compound expression is not.
    Keeping this decision on AST types (rather than rendered strings) avoids
    accidentally treating text inside a symbol or literal as syntax.
    """

    if isinstance(node, IntegerNode):
        return node.value < 0 or abs(node.value) >= 10
    if isinstance(node, SymbolNode):
        return not (len(node.name) == 1 or node.name.startswith("\\"))
    return True


def _render(node: Node) -> str:
    if isinstance(node, IntegerNode):
        return str(node.value)
    if isinstance(node, DecimalNode):
        return node.value
    if isinstance(node, SymbolNode):
        return node.name
    if isinstance(node, NegateNode):
        operand = _render(node.operand)
        # -x^2 means -(x^2), while (-x)^2 is parenthesized by PowerNode.
        if isinstance(node.operand, (AddNode, SubtractNode, MultiplyNode, DivideNode)):
            operand = f"({operand})"
        return f"-{operand}"
    if isinstance(node, AddNode):
        left = _wrap(_render(node.left), node.left, 20)
        right = _wrap(_render(node.right), node.right, 20, right=True)
        return f"{left}+{right}"
    if isinstance(node, SubtractNode):
        left = _wrap(_render(node.left), node.left, 20)
        right = _wrap(_render(node.right), node.right, 20, right=True)
        return f"{left}-{right}"
    if isinstance(node, MultiplyNode):
        left = _multiply_wrap(_render(node.left), node.left, right=False)
        right = _multiply_wrap(_render(node.right), node.right, right=True)
        operator = "" if _can_juxtapose(node.left, node.right) else r"\cdot"
        return f"{left}{operator}{right}"
    if isinstance(node, DivideNode):
        return f"\\frac{{{_render(node.left)}}}{{{_render(node.right)}}}"
    if isinstance(node, PowerNode):
        base = _render(node.base)
        if isinstance(node.base, (NegateNode, AddNode, SubtractNode, MultiplyNode, DivideNode)):
            base = f"({base})"
        exponent = _render(node.exponent)
        if _exponent_requires_braces(node.exponent):
            exponent = f"{{{exponent}}}"
        return f"{base}^{exponent}"
    if isinstance(node, SquareRootNode):
        return f"\\sqrt{{{_render(node.operand)}}}"

    relation = {
        EquationNode: "=",
        LessThanNode: "<",
        LessThanOrEqualNode: "\\le",
        GreaterThanNode: ">",
        GreaterThanOrEqualNode: "\\ge",
    }
    for cls, operator in relation.items():
        if isinstance(node, cls):
            return f"{_render(node.left)}{operator}{_render(node.right)}"
    raise ValueError("UNSUPPORTED_RENDER_NODE")


def render_latex(node: Node) -> str:
    """Render a canonical AST node to stable LaTeX-like math text."""

    if not isinstance(node, Node):
        raise TypeError("AST_NODE_REQUIRED")
    return _render(node)
