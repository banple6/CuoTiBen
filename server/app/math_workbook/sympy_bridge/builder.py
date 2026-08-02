from __future__ import annotations
import time
import sympy
from app.math_workbook.ir.expression_nodes import *
from .build_errors import BuildError
from .build_limits import SympyBuildLimits
from .symbol_table import SymbolTable

BUILDER_VERSION='1'; SYMPY_VERSION=sympy.__version__
class AstSympyBuilder:
    def __init__(self,symbol_table:SymbolTable,limits:SympyBuildLimits=SympyBuildLimits()):self.table=symbol_table;self.limits=limits;self.start=time.monotonic();self.relations=0
    def build(self,node:Node):
        self._guard(node); return self._build(node)
    def _guard(self,node):
        validate(node,self.limits.max_nodes,self.limits.max_depth)
        if not isinstance(node.span,dict) or not isinstance(node.span.get('start'),int) or not isinstance(node.span.get('end'),int) or node.span['start']<0 or node.span['end']<node.span['start']:raise BuildError('INVALID_SOURCE_SPAN',{})
        if (time.monotonic()-self.start)*1000>self.limits.max_build_duration_ms:raise BuildError('BUILD_DURATION_LIMIT_EXCEEDED',{'limit':self.limits.max_build_duration_ms})
    def _build(self,n):
        self._guard(n)
        if isinstance(n,IntegerNode):
            if len(str(abs(n.value)))>self.limits.max_integer_digits:raise BuildError('INTEGER_DIGIT_LIMIT_EXCEEDED',{})
            return sympy.Integer(n.value)
        if isinstance(n,DecimalNode):
            if len(n.value.replace('.',''))>self.limits.max_decimal_digits:raise BuildError('DECIMAL_DIGIT_LIMIT_EXCEEDED',{})
            # Exact conversion from the finite decimal literal; no binary float is created.
            return sympy.Rational(n.value)
        if isinstance(n,SymbolNode):return self.table.get(n.name)
        if isinstance(n,NegateNode):return sympy.Mul(sympy.Integer(-1),self._build(n.operand),evaluate=False)
        if isinstance(n,AddNode):return sympy.Add(self._build(n.left),self._build(n.right),evaluate=False)
        if isinstance(n,SubtractNode):return sympy.Add(self._build(n.left),sympy.Mul(sympy.Integer(-1),self._build(n.right),evaluate=False),evaluate=False)
        if isinstance(n,MultiplyNode):return sympy.Mul(self._build(n.left),self._build(n.right),evaluate=False)
        if isinstance(n,DivideNode):return sympy.Mul(self._build(n.left),sympy.Pow(self._build(n.right),sympy.Integer(-1),evaluate=False),evaluate=False)
        if isinstance(n,PowerNode):
            if isinstance(n.exponent,IntegerNode) and abs(n.exponent.value)>self.limits.max_power_abs_value:raise BuildError('POWER_LIMIT_EXCEEDED',{})
            return sympy.Pow(self._build(n.base),self._build(n.exponent),evaluate=False)
        if isinstance(n,SquareRootNode):return sympy.Pow(self._build(n.operand),sympy.Rational(1,2),evaluate=False)
        if isinstance(n,(EquationNode,LessThanNode,LessThanOrEqualNode,GreaterThanNode,GreaterThanOrEqualNode)):
            self.relations+=1
            if self.relations>self.limits.max_relation_count:raise BuildError('RELATION_LIMIT_EXCEEDED',{})
            constructors={EquationNode:sympy.Eq,LessThanNode:sympy.Lt,LessThanOrEqualNode:sympy.Le,GreaterThanNode:sympy.Gt,GreaterThanOrEqualNode:sympy.Ge}
            return constructors[type(n)](self._build(n.left),self._build(n.right),evaluate=False)
        raise BuildError('UNSUPPORTED_AST_NODE',{'type':type(n).__name__})
