from __future__ import annotations
from dataclasses import dataclass
from typing import Any

@dataclass(frozen=True)
class Node:
    span: dict; source_formula_id: str
    @property
    def type(self): return self.__class__.__name__.replace('Node','').lower()
    def to_dict(self):
        result={'type':self.type,'source_span':self.span,'source_formula_id':self.source_formula_id}
        for k,v in self.__dict__.items():
            if k not in {'span','source_formula_id'}: result[k]=_encode(v)
        return result
def _encode(v): return v.to_dict() if isinstance(v,Node) else [_encode(x) for x in v] if isinstance(v,tuple) else v
@dataclass(frozen=True)
class IntegerNode(Node): value:int
@dataclass(frozen=True)
class DecimalNode(Node): value:str
@dataclass(frozen=True)
class SymbolNode(Node): name:str
@dataclass(frozen=True)
class NegateNode(Node): operand:Node
@dataclass(frozen=True)
class AddNode(Node): left:Node; right:Node
@dataclass(frozen=True)
class SubtractNode(Node): left:Node; right:Node
@dataclass(frozen=True)
class MultiplyNode(Node): left:Node; right:Node
@dataclass(frozen=True)
class DivideNode(Node): left:Node; right:Node
@dataclass(frozen=True)
class PowerNode(Node): base:Node; exponent:Node
@dataclass(frozen=True)
class SquareRootNode(Node): operand:Node
@dataclass(frozen=True)
class EquationNode(Node): left:Node; right:Node
@dataclass(frozen=True)
class LessThanNode(Node): left:Node; right:Node
@dataclass(frozen=True)
class LessThanOrEqualNode(Node): left:Node; right:Node
@dataclass(frozen=True)
class GreaterThanNode(Node): left:Node; right:Node
@dataclass(frozen=True)
class GreaterThanOrEqualNode(Node): left:Node; right:Node

_TYPES={c.__name__.replace('Node','').lower():c for c in (IntegerNode,DecimalNode,SymbolNode,NegateNode,AddNode,SubtractNode,MultiplyNode,DivideNode,PowerNode,SquareRootNode,EquationNode,LessThanNode,LessThanOrEqualNode,GreaterThanNode,GreaterThanOrEqualNode)}
_CHILDREN={'negate':('operand',),'add':('left','right'),'subtract':('left','right'),'multiply':('left','right'),'divide':('left','right'),'power':('base','exponent'),'squareroot':('operand',),'equation':('left','right'),'lessthan':('left','right'),'lessthanorequal':('left','right'),'greaterthan':('left','right'),'greaterthanorequal':('left','right')}
def from_dict(data:dict)->Node:
    typ=data.get('type'); cls=_TYPES.get(typ)
    if not cls: raise ValueError('UNKNOWN_AST_NODE_TYPE')
    kwargs={'span':data.get('source_span',{}),'source_formula_id':data.get('source_formula_id','')}
    for key in _CHILDREN.get(typ,()): kwargs[key]=from_dict(data[key])
    if typ=='integer':kwargs['value']=int(data['value'])
    elif typ=='decimal':kwargs['value']=str(data['value'])
    elif typ=='symbol':kwargs['name']=str(data['name'])
    return cls(**kwargs)
def node_count(node:Node)->int:return 1+sum(node_count(getattr(node,k)) for k in _CHILDREN.get(node.type,()))
def depth(node:Node)->int:return 1+max((depth(getattr(node,k)) for k in _CHILDREN.get(node.type,())),default=0)
def validate(node:Node,max_nodes:int=500,max_depth:int=64)->None:
    if node_count(node)>max_nodes:raise ValueError('AST_NODE_LIMIT_EXCEEDED')
    if depth(node)>max_depth:raise ValueError('AST_DEPTH_LIMIT_EXCEEDED')
    if not isinstance(node.span,dict):raise ValueError('INVALID_AST_SPAN')
