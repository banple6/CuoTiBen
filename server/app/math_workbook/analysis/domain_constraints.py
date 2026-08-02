from app.math_workbook.ir.expression_nodes import *
def extract_constraints(roots):
    out=[]
    def visit(node,path):
        if isinstance(node,DivideNode):out.append(_item('nonzero',node.right,path+'.right',node,'original_denominator'))
        if isinstance(node,PowerNode) and isinstance(node.exponent,IntegerNode) and node.exponent.value<0:out.append(_item('nonzero',node.base,path+'.base',node,'negative_power_denominator'))
        if isinstance(node,SquareRootNode):out.append(_item('nonnegative',node.operand,path+'.operand',node,'real_square_root'))
        for key in ('left','right','base','exponent','operand'):
            if hasattr(node,key):visit(getattr(node,key),path+'.'+key if path else key)
    for i,node in enumerate(roots):visit(node,f'roots[{i}]')
    return out
def _item(kind,expr,path,owner,reason):return {'type':kind,'expression_ast':expr.to_dict(),'source_node_path':path,'source_formula_id':owner.source_formula_id,'source_span':owner.span,'reason':reason}
