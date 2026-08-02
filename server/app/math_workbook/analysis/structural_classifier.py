from app.math_workbook.ir.expression_nodes import *
def analyze(roots):
    nodes=list(_walk(roots)); symbols=sorted({n.name for n in nodes if isinstance(n,SymbolNode)});relations=[n for n in roots if isinstance(n,(EquationNode,LessThanNode,LessThanOrEqualNode,GreaterThanNode,GreaterThanOrEqualNode))]
    div=any(isinstance(n,DivideNode) for n in nodes);sqrt=any(isinstance(n,SquareRootNode) for n in nodes);decimal=any(isinstance(n,DecimalNode) for n in nodes);negative_power=any(isinstance(n,PowerNode) and isinstance(n.exponent,IntegerNode) and n.exponent.value<0 for n in nodes)
    kind='expression';secondary=[]
    if relations:
        inequality=isinstance(relations[0],(LessThanNode,LessThanOrEqualNode,GreaterThanNode,GreaterThanOrEqualNode));base='inequality' if inequality else 'equation'
        if sqrt:kind='radical_'+base+'_candidate'
        elif div or negative_power:kind='rational_'+base+'_candidate'
        elif len(symbols)==1:kind='single_symbol_'+base+'_candidate';secondary.append('polynomial_'+base+'_candidate')
        elif len(symbols)>1:kind='multi_symbol_'+base+'_candidate'
        else:kind='numeric_'+base
    features={'expression_kind':'relation' if relations else 'expression','relation_kind':relations[0].type if relations else None,'symbol_count':len(symbols),'symbols':symbols,'contains_division':div,'contains_square_root':sqrt,'contains_decimal':decimal,'contains_negative_power':negative_power,'max_observed_integer_power':max((n.exponent.value for n in nodes if isinstance(n,PowerNode) and isinstance(n.exponent,IntegerNode)),default=0),'node_count':len(nodes),'tree_depth':max((_depth(x) for x in roots),default=0),'is_polynomial_candidate':'unknown' if div or sqrt or negative_power else True,'polynomial_variables':symbols if not(div or sqrt or negative_power) else [],'total_degree':'unknown','degree_by_variable':{},'coefficient_domain':'QQ' if not decimal else 'QQ'}
    return features,{'primary':kind,'secondary':secondary,'confidence':None,'classification_source':'deterministic_rules'}
def _walk(nodes):
    for node in nodes:
        yield node
        for key in ('left','right','base','exponent','operand'):
            if hasattr(node,key):yield from _walk([getattr(node,key)])
def _depth(node):return 1+max((_depth(getattr(node,k)) for k in ('left','right','base','exponent','operand') if hasattr(node,k)),default=0)
