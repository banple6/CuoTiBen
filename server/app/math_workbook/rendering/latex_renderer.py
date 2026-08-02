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
        left = _wrap(_render(node.left), node.left, 30)
        right = _wrap(_render(node.right), node.right, 30, right=True)
        # The canonical syntax uses implicit multiplication.  Parentheses are
        # supplied by _wrap for sums, relations and nested products.
        return f"{left}{right}"
    if isinstance(node, DivideNode):
        return f"\\frac{{{_render(node.left)}}}{{{_render(node.right)}}}"
    if isinstance(node, PowerNode):
        base = _render(node.base)
        if isinstance(node.base, (NegateNode, AddNode, SubtractNode, MultiplyNode, DivideNode)):
            base = f"({base})"
        exponent = _render(node.exponent)
        if isinstance(node.exponent, (AddNode, SubtractNode, MultiplyNode, DivideNode, NegateNode)):
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
