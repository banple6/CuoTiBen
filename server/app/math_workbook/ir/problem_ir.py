from dataclasses import dataclass
from .expression_nodes import Node

IR_VERSION='v1'
@dataclass(frozen=True)
class MathProblemIR:
    problem_id:str; source_revision:int; problem_type:str; variables:tuple[dict,...]; relations:tuple[dict,...]; expressions:tuple[dict,...]; constraints:tuple[dict,...]; options:tuple[dict,...]; expected_answer_type:str; source_formula_ids:tuple[str,...]; warnings:tuple[str,...]; unsupported_features:tuple[str,...]; features:dict
    def to_dict(self):return {'ir_version':IR_VERSION,**self.__dict__}

def build_problem_ir(problem_id:str,source_revision:int,roots:list[Node],formula_ids:list[str],domains:dict[str,str]|None=None)->MathProblemIR:
    symbols=sorted(_symbols(roots)); domains=domains or {}
    variables=tuple({'name':name,'domain':domains.get(name,'real'),'domain_source':'user_provided' if name in domains else 'system_default'} for name in symbols)
    relation_types={'equation','lessthan','lessthanorequal','greaterthan','greaterthanorequal'}
    relations=tuple(root.to_dict() for root in roots if root.type in relation_types)
    expressions=tuple(root.to_dict() for root in roots if root.type not in relation_types)
    if any(x['type'].startswith(('lessthan','greaterthan')) for x in relations): kind='inequality_candidate'
    elif relations:kind='equation_candidate'
    elif not symbols:kind='numeric_expression_candidate'
    else:kind='algebraic_expression_candidate'
    raw=' '.join(str(x) for x in roots)
    features={'symbol_count':len(symbols),'relation_count':len(relations),'max_observed_power':_max_power(roots),'contains_division':_contains(roots,'divide'),'contains_square_root':_contains(roots,'squareroot'),'contains_decimal':_contains(roots,'decimal')}
    return MathProblemIR(problem_id,source_revision,kind,variables,relations,expressions,(),(),'unknown',tuple(formula_ids),(),(),features)
def _walk(nodes):
    for n in nodes:
        yield n
        for key in ('left','right','base','exponent','operand'):
            if hasattr(n,key):yield from _walk([getattr(n,key)])
def _symbols(nodes):return {n.name for n in _walk(nodes) if n.type=='symbol'}
def _contains(nodes,typ):return any(n.type==typ for n in _walk(nodes))
def _max_power(nodes):return max((n.exponent.value for n in _walk(nodes) if n.type=='power' and n.exponent.type=='integer'),default=0)
