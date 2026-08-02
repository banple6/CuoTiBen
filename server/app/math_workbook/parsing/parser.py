from __future__ import annotations
from .errors import ParseError
from .limits import ParserLimits
from .tokens import Token,TokenType
from app.math_workbook.ir.expression_nodes import *

_REL={TokenType.EQUAL:EquationNode,TokenType.LESS_THAN:LessThanNode,TokenType.LESS_THAN_OR_EQUAL:LessThanOrEqualNode,TokenType.GREATER_THAN:GreaterThanNode,TokenType.GREATER_THAN_OR_EQUAL:GreaterThanOrEqualNode}
class Parser:
    def __init__(self,tokens:list[Token],limits:ParserLimits=ParserLimits()):self.tokens=tokens;self.i=0;self.limits=limits
    @property
    def cur(self):return self.tokens[self.i]
    def take(self,typ=None):
        t=self.cur
        if typ and t.type != typ:raise ParseError('UNEXPECTED_TOKEN',t.start,{'expected':typ.value,'actual':t.type.value})
        self.i+=1;return t
    def parse(self):
        root=self.relation()
        if self.cur.type!=TokenType.EOF:raise ParseError('UNEXPECTED_TOKEN',self.cur.start,{'actual':self.cur.type.value})
        validate(root,self.limits.max_ast_nodes,self.limits.max_ast_depth);return root
    def relation(self):
        left=self.sum()
        if self.cur.type in _REL:
            tok=self.take();right=self.sum()
            if self.cur.type in _REL:raise ParseError('RELATION_CHAIN_UNSUPPORTED',self.cur.start,{})
            return _REL[tok.type](self._span(left,right),left.source_formula_id,left,right)
        return left
    def sum(self):
        node=self.product()
        while self.cur.type in (TokenType.PLUS,TokenType.MINUS):
            typ=self.take().type;right=self.product();node=(AddNode if typ==TokenType.PLUS else SubtractNode)(self._span(node,right),node.source_formula_id,node,right)
        return node
    def product(self):
        node=self.unary()
        while True:
            if self.cur.type in (TokenType.MULTIPLY,TokenType.DIVIDE):typ=self.take().type;right=self.unary();cls=MultiplyNode if typ==TokenType.MULTIPLY else DivideNode
            elif self._atom_start(self.cur.type):
                if node.type=='symbol' and self.cur.type==TokenType.SYMBOL:raise ParseError('AMBIGUOUS_IMPLICIT_MULTIPLICATION',self.cur.start,{'input':'xy'})
                right=self.unary();cls=MultiplyNode
            else:break
            node=cls(self._span(node,right),node.source_formula_id,node,right)
        return node
    def unary(self):
        if self.cur.type==TokenType.PLUS:self.take();return self.unary()
        if self.cur.type==TokenType.MINUS:
            token=self.take();operand=self.unary();return NegateNode({'start':token.start,'end':operand.span.get('end',token.end)},token.source_formula_id,operand)
        return self.power()
    def power(self):
        node=self.atom()
        if self.cur.type==TokenType.POWER:
            self.take();exp=self.unary()
            if exp.type=='integer' and abs(exp.value)>self.limits.max_power_abs_value:raise ParseError('POWER_LIMIT_EXCEEDED',exp.span.get('start',0),{'limit':self.limits.max_power_abs_value})
            return PowerNode(self._span(node,exp),node.source_formula_id,node,exp)
        return node
    def atom(self):
        t=self.cur
        if t.type==TokenType.INTEGER:self.take();return IntegerNode(t.source_span,t.source_formula_id,int(t.normalized_value))
        if t.type==TokenType.DECIMAL:self.take();return DecimalNode(t.source_span,t.source_formula_id,t.normalized_value)
        if t.type==TokenType.SYMBOL:self.take();return SymbolNode(t.source_span,t.source_formula_id,t.normalized_value)
        if t.type==TokenType.LEFT_PAREN:self.take();node=self.relation();self.take(TokenType.RIGHT_PAREN);return node
        if t.type==TokenType.FRAC:
            begin=self.take();self.take(TokenType.LEFT_BRACE);left=self.relation();self.take(TokenType.RIGHT_BRACE);self.take(TokenType.LEFT_BRACE);right=self.relation();end=self.take(TokenType.RIGHT_BRACE);return DivideNode({'start':begin.start,'end':end.end},begin.source_formula_id,left,right)
        if t.type==TokenType.SQRT:
            begin=self.take();self.take(TokenType.LEFT_BRACE);operand=self.relation();end=self.take(TokenType.RIGHT_BRACE);return SquareRootNode({'start':begin.start,'end':end.end},begin.source_formula_id,operand)
        raise ParseError('EXPECTED_EXPRESSION',t.start,{'actual':t.type.value})
    @staticmethod
    def _atom_start(typ):return typ in (TokenType.INTEGER,TokenType.DECIMAL,TokenType.SYMBOL,TokenType.LEFT_PAREN,TokenType.FRAC,TokenType.SQRT)
    @staticmethod
    def _span(a,b):return {'start':a.span.get('start',0),'end':b.span.get('end',0)}
def parse(tokens,limits=ParserLimits()):return Parser(tokens,limits).parse()
