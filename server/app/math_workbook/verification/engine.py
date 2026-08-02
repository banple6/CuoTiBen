from __future__ import annotations
import sympy
from app.math_workbook.ir.expression_nodes import *
from app.math_workbook.sympy_bridge.symbol_table import SymbolTable
from app.math_workbook.sympy_bridge.builder import AstSympyBuilder

VERIFIER_VERSION='2'
CAPABILITY_MATRIX={
 'exact_value': ('candidate_schema','numeric_equality','domain_constraints'),
 'unique_candidate': ('candidate_schema','domain_constraints','substitution','solution_completeness'),
 'no_solution_candidate': ('candidate_schema','domain_constraints','solution_completeness'),
 'identity_candidate': ('candidate_schema','domain_constraints','solution_completeness'),
 'two_real_candidates': ('candidate_schema','domain_constraints','substitution','solution_completeness'),
 'one_repeated_real_candidate': ('candidate_schema','domain_constraints','substitution','solution_completeness'),
 'interval_candidate': ('candidate_schema','domain_constraints','inequality_direction','inequality_boundary','solution_completeness'),
}
def required_checks(candidate_type):return list(CAPABILITY_MATRIX.get(candidate_type,()))
def _check(kind,status,details=None,required=True):return {'check_id':kind+'_v2','type':kind,'verifier_id':kind+'_v2','verifier_version':VERIFIER_VERSION,'status':status,'required':required,'input_summary':{},'result_details':details or {},'blocking_reason':None if status=='passed' else kind,'warnings':[],'duration_ms':0}
def _candidate_value(item):
    data=item.get('value',{})
    if data.get('kind')=='integer':return sympy.Integer(data['value'])
    if data.get('kind')=='rational':return sympy.Rational(data['numerator'],data['denominator'])
    raise ValueError('UNSUPPORTED_CANDIDATE_VALUE')
def _domain_status(symbol,value,domain):
    if domain=='real':return bool(value.is_real)
    if domain=='integer':return bool(value.is_integer)
    if domain=='positive_real':return bool(value.is_real and value>0)
    if domain=='nonnegative_real':return bool(value.is_real and value>=0)
    return False
def _walk(node):
    yield node
    for key in ('left','right','base','exponent','operand'):
        if hasattr(node,key):yield from _walk(getattr(node,key))
def _constraints(roots,symbol,value):
    checks=[]
    for node in _walk(roots[0]):
        if isinstance(node,DivideNode):
            den=AstSympyBuilder(SymbolTable([{'name':symbol.name,'domain':'real'}])).build(node.right).subs(symbol,value)
            checks.append(('denominator_nonzero',den!=0))
        if isinstance(node,SquareRootNode):
            rad=AstSympyBuilder(SymbolTable([{'name':symbol.name,'domain':'real'}])).build(node.operand).subs(symbol,value)
            checks.append(('square_root_nonnegative',bool(rad.is_real and rad>=0)))
    return checks
def verify(request):
    roots=[from_dict(x) for x in request['canonical_ast']];ir=request['problem_ir'];candidate=request['candidate'];ctype=candidate.get('candidate_type');checks=[]
    required=required_checks(ctype)
    if not required:return _report('inconclusive',[_check('candidate_schema','failed',{'reason':'NO_VERIFIER_MATCH'})],ctype)
    table=SymbolTable(ir['variables']);expr=AstSympyBuilder(table).build(roots[0]);
    expected_constraint_count=sum(isinstance(n,(DivideNode,SquareRootNode)) for n in _walk(roots[0]))
    values=[]
    try:values=[_candidate_value(x) for x in candidate.get('values',[])]
    except Exception:checks.append(_check('candidate_schema','failed',{'reason':'candidate value is not structured'}));return _report('rejected',checks,ctype)
    symbols=list(table.symbols.values())
    if len(symbols)>1 and ctype not in {'exact_value'}:return _report('inconclusive',[_check('candidate_schema','failed',{'reason':'multi_symbol'})],ctype)
    symbol=symbols[0] if symbols else None
    domain=ir['variables'][0].get('domain','real') if ir.get('variables') else 'real'
    domain_results=[]
    for value in values:
        domain_results.append(_domain_status(symbol,value,domain) if symbol else bool(value.is_real))
    constraints_ok=True
    if symbol:
        for value in values:
            for name,passed in _constraints(roots,symbol,value):
                constraints_ok=constraints_ok and bool(passed);checks.append(_check(name,'passed' if passed else 'failed',{'candidate':str(value)}))
    checks.insert(0,_check('candidate_schema','passed'))
    if expected_constraint_count and not request.get('constraints_snapshot'):
        checks.insert(1,_check('domain_constraints','inconclusive',{'reason':'missing_original_constraint_snapshot'}))
    elif values or ctype in {'no_solution_candidate','identity_candidate'}:
        domain_pass=all(domain_results) and constraints_ok
        checks.insert(1,_check('domain_constraints','passed' if domain_pass else 'failed',{'domain':domain}))
    if ctype=='exact_value':
        try:actual=sympy.cancel(expr);passed=bool(values and actual==values[0]);checks.append(_check('numeric_equality','passed' if passed else 'failed'));return _report_from(checks,ctype)
        except Exception:return _report('inconclusive',checks+[ _check('numeric_equality','inconclusive')],ctype)
    if isinstance(expr,sympy.Equality) and ctype in {'unique_candidate','two_real_candidates','one_repeated_real_candidate','no_solution_candidate','identity_candidate'}:
        if any(c['status']=='failed' for c in checks if c['type'] in {'domain_constraints','denominator_nonzero','square_root_nonnegative'}):return _report_from(checks,ctype)
        if not symbol:return _report('inconclusive',checks+[ _check('solution_completeness','inconclusive')],ctype)
        try:
            poly=sympy.Poly(expr.lhs-expr.rhs,symbol);degree=poly.degree();a_b_c=poly.all_coeffs()
            if poly.is_zero: degree=0;a_b_c=[sympy.Integer(0)]
        except Exception:return _report('inconclusive',checks+[_check('solution_completeness','inconclusive')],ctype)
        for value in values:
            passed=sympy.simplify(expr.lhs.subs(symbol,value)-expr.rhs.subs(symbol,value))==0;checks.append(_check('substitution','passed' if passed else 'failed',{'candidate':str(value)}))
        expected=[]
        if degree==0:
            constant=a_b_c[0] if a_b_c else sympy.Integer(0);expected=[];expected_type='identity_candidate' if constant==0 else 'no_solution_candidate'
        elif degree==1:
            a,b=a_b_c;expected=[] if a==0 else [-b/a]
            expected_type='unique_candidate' if a!=0 else ('identity_candidate' if b==0 else 'no_solution_candidate')
        elif degree==2:
            a,b,c=a_b_c;disc=b*b-4*a*c
            expected=[] if disc<0 else [(-b+sympy.sqrt(disc))/(2*a)] if disc==0 else [(-b+sympy.sqrt(disc))/(2*a),(-b-sympy.sqrt(disc))/(2*a)]
            expected_type='no_solution_candidate' if disc<0 else 'one_repeated_real_candidate' if disc==0 else 'two_real_candidates'
        else:return _report('inconclusive',checks+[_check('solution_completeness','inconclusive')],ctype)
        complete=(ctype==expected_type and set(map(sympy.srepr,values))==set(map(sympy.srepr,expected)) and (ctype!='one_repeated_real_candidate' or len(values)==1))
        checks.append(_check('solution_completeness','passed' if complete else 'failed',{'expected_type':expected_type,'candidate_type':ctype,'expected_count':len(expected),'candidate_count':len(values)}));return _report_from(checks,ctype)
    if isinstance(expr,(sympy.StrictLessThan,sympy.LessThan,sympy.StrictGreaterThan,sympy.GreaterThan)) and ctype=='interval_candidate':
        if domain=='integer':return _report('inconclusive',checks+[_check('candidate_schema','passed'),_check('domain_constraints','inconclusive',{'reason':'integer interval representation unsupported'}),_check('solution_completeness','inconclusive')],ctype)
        checks.append(_check('domain_constraints','passed',{'domain':domain}))
        if not symbol:return _report('inconclusive',checks+[_check('inequality_direction','inconclusive'),_check('inequality_boundary','inconclusive'),_check('solution_completeness','inconclusive')],ctype)
        try:poly=sympy.Poly(expr.lhs-expr.rhs,symbol);degree=poly.degree()
        except Exception:return _report('inconclusive',checks+[_check('inequality_direction','inconclusive'),_check('inequality_boundary','inconclusive'),_check('solution_completeness','inconclusive')],ctype)
        if degree!=1:return _report('inconclusive',checks+[_check('inequality_direction','inconclusive'),_check('inequality_boundary','inconclusive'),_check('solution_completeness','inconclusive')],ctype)
        a,b=poly.all_coeffs();boundary=-b/a;less=isinstance(expr,(sympy.StrictLessThan,sympy.LessThan));inclusive=isinstance(expr,(sympy.LessThan,sympy.GreaterThan))
        if a<0:less=not less
        if boundary.is_Integer:
            boundary_payload = {'kind': 'integer', 'value': int(boundary)}
        elif boundary.is_Rational:
            boundary_payload = {'kind': 'rational', 'numerator': int(boundary.p), 'denominator': int(boundary.q)}
        else:
            boundary_payload = None
        expected={'type':'interval','lower':None,'upper':{'value':boundary_payload,'inclusive':inclusive}} if less else {'type':'interval','lower':{'value':boundary_payload,'inclusive':inclusive},'upper':None}
        actual=candidate.get('interval',{})
        def value_sig(value):
            if not isinstance(value, dict): return value
            kind=value.get('kind')
            if kind=='integer': return ('rational', int(value.get('value', 0)), 1)
            if kind=='rational': return ('rational', int(value.get('numerator', 0)), int(value.get('denominator', 1)))
            return tuple(sorted(value.items()))
        def sig(bound): return None if bound is None else (value_sig(bound.get('value')),bound.get('inclusive'))
        boundary_pass=sig(actual.get('lower'))==sig(expected.get('lower')) and sig(actual.get('upper'))==sig(expected.get('upper'))
        checks.extend([_check('inequality_direction','passed' if boundary_pass else 'failed'),_check('inequality_boundary','passed' if boundary_pass else 'failed'),_check('solution_completeness','passed' if boundary_pass else 'failed')]);return _report_from(checks,ctype)
    return _report('inconclusive',checks+[_check('solution_completeness','inconclusive')],ctype)
def validate_report(result,candidate_type):
    required=set(required_checks(candidate_type));checks=result.get('checks',[])
    if result.get('status')=='verified' and (not required or {x.get('type') for x in checks if x.get('required')}!=required or any(x.get('status')!='passed' for x in checks if x.get('required'))):return False
    return all(x.get('status') in {'passed','failed','inconclusive','not_applicable','error'} for x in checks)
def _report_from(checks,ctype):
    required=[c for c in checks if c['required']]
    if any(c['status']=='failed' for c in required):status='rejected'
    elif any(c['status'] in {'inconclusive','error','timeout'} for c in required):status='inconclusive'
    else:status='verified' if required else 'inconclusive'
    return _report(status,checks,ctype)
def _report(status,checks,ctype):return {'status':status,'checks':checks,'verification_plan':{'candidate_type':ctype,'required_checks':required_checks(ctype),'selected_verifiers':sorted({c['verifier_id'] for c in checks})},'verified_result':{'status':'verified','is_verified':True} if status=='verified' else None,'warnings':[],'errors':[]}
