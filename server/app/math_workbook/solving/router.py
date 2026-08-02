from __future__ import annotations
import time
import sympy
from app.math_workbook.solving.errors import SolverError
from app.math_workbook.solving.limits import SolverLimits

SOLVER_VERSION='1'
def _latex(value): return sympy.latex(value)
def _value(value):
    item={'display_latex':_latex(value),'exact':True}
    if value.is_Integer:item['value']={'kind':'integer','value':int(value)}
    elif value.is_Rational:item['value']={'kind':'rational','numerator':int(value.p),'denominator':int(value.q)}
    else:item['value']={'kind':'unsupported_exact'}
    return item
def _bound(value,inclusive):
    item=_value(value);return {'value':item.get('value'),'display_latex':_latex(value),'inclusive':inclusive}
class BaseSolver:
    solver_id='base';solver_version=SOLVER_VERSION; supported_classifications=()
    def supports(self,classification,features):return classification in self.supported_classifications

class NumericSolver(BaseSolver):
    solver_id='numeric_exact';supported_classifications=('numeric_expression_candidate',)
    def solve_candidate(self,expr,ctx):
        if expr.free_symbols:raise SolverError('UNEXPECTED_SYMBOL',{})
        value=sympy.cancel(expr)
        if value in (sympy.zoo,sympy.nan) or value.has(sympy.zoo,sympy.nan):raise SolverError('NUMERIC_DOMAIN_ERROR',{})
        if value.is_real is False:raise SolverError('NUMERIC_DOMAIN_ERROR',{})
        return {'status':'candidate','candidate_type':'exact_value','values':[_value(value)],'requires_checks':['domain_constraints'],'solver_trace':[{'operation':'exact_numeric_evaluation','rule_id':'exact_numeric_evaluation','input_artifact_ids':[],'output_summary':{}}]}

class LinearEquationSolver(BaseSolver):
    solver_id='linear_equation';supported_classifications=('single_symbol_equation_candidate','polynomial_equation_candidate')
    def solve_candidate(self,expr,ctx):
        if not isinstance(expr,sympy.Equality):raise SolverError('UNSUPPORTED_PROBLEM_CLASS',{})
        symbol=ctx['symbol']; poly=sympy.Poly(expr.lhs-expr.rhs,symbol)
        if poly.is_zero or poly.degree()==0:
            kind='identity_candidate' if poly.is_zero else 'no_solution_candidate'
            return {'status':'candidate','candidate_type':kind,'values':[],'requires_checks':['solution_completeness'],'solver_trace':[{'operation':'linear_degenerate_check','rule_id':'linear_degenerate_check','input_artifact_ids':[],'output_summary':{}}]}
        if poly.degree()!=1:raise SolverError('NOT_LINEAR',{})
        a,b=poly.all_coeffs()
        if a==0:
            kind='identity_candidate' if b==0 else 'no_solution_candidate';return {'status':'candidate','candidate_type':kind,'values':[],'requires_checks':['solution_completeness']}
        return {'status':'candidate','candidate_type':'unique_candidate','values':[_value(-b/a)],'requires_checks':['substitution','domain_constraints'],'solver_trace':[{'operation':'linear_coefficient_formula','rule_id':'linear_coefficient_formula','input_artifact_ids':[],'output_summary':{}}]}

class QuadraticEquationSolver(BaseSolver):
    solver_id='quadratic_equation';supported_classifications=('single_symbol_equation_candidate','polynomial_equation_candidate')
    def solve_candidate(self,expr,ctx):
        if not isinstance(expr,sympy.Equality):raise SolverError('UNSUPPORTED_PROBLEM_CLASS',{})
        symbol=ctx['symbol'];poly=sympy.Poly(expr.lhs-expr.rhs,symbol)
        if poly.degree() in (0, 1) or poly.is_zero:return LinearEquationSolver().solve_candidate(expr,ctx)
        if poly.degree()!=2:raise SolverError('NOT_QUADRATIC',{})
        a,b,c=poly.all_coeffs();disc=b*b-4*a*c
        if disc.is_negative:return {'status':'candidate','candidate_type':'no_solution_candidate','values':[],'requires_checks':['solution_completeness'],'solver_trace':[{'operation':'quadratic_negative_discriminant','rule_id':'quadratic_negative_discriminant','input_artifact_ids':[],'output_summary':{}}]}
        root=sympy.sqrt(disc);values=[_value((-b+root)/(2*a))]
        if disc!=0:values.append(_value((-b-root)/(2*a)));kind='two_real_candidates'
        else:kind='one_repeated_real_candidate'
        return {'status':'candidate','candidate_type':kind,'values':values,'requires_checks':['substitution','domain_constraints'],'solver_trace':[{'operation':'quadratic_formula','rule_id':'quadratic_formula','input_artifact_ids':[],'output_summary':{}}]}

class LinearInequalitySolver(BaseSolver):
    solver_id='linear_inequality';supported_classifications=('single_symbol_inequality_candidate',)
    def solve_candidate(self,expr,ctx):
        symbol=ctx['symbol']
        if not isinstance(expr,(sympy.StrictLessThan,sympy.LessThan,sympy.StrictGreaterThan,sympy.GreaterThan)):raise SolverError('UNSUPPORTED_PROBLEM_CLASS',{})
        poly=sympy.Poly(expr.lhs-expr.rhs,symbol)
        if poly.degree()!=1:raise SolverError('NOT_LINEAR',{})
        if poly.is_zero or poly.degree()==0:return {'status':'candidate','candidate_type':'inconclusive','values':[],'requires_checks':['truth_condition'],'solver_trace':[{'operation':'inequality_degenerate_check','rule_id':'inequality_degenerate_check','input_artifact_ids':[],'output_summary':{}}]}
        a,b=poly.all_coeffs();boundary=-b/a
        less=isinstance(expr,(sympy.StrictLessThan,sympy.LessThan)); inclusive=isinstance(expr,(sympy.LessThan,sympy.GreaterThan))
        if a<0:less=not less
        interval={'type':'interval','lower':None,'upper':_bound(boundary,inclusive)} if less else {'type':'interval','lower':_bound(boundary,inclusive),'upper':None}
        return {'status':'candidate','candidate_type':'interval_candidate','interval':interval,'values':[],'requires_checks':['boundary','domain_constraints'],'solver_trace':[{'operation':'linear_inequality_sign_rule','rule_id':'linear_inequality_sign_rule','input_artifact_ids':[],'output_summary':{}}]}

SOLVER_REGISTRY={'numeric_expression_candidate':(NumericSolver(),),'single_symbol_equation_candidate':(LinearEquationSolver(),QuadraticEquationSolver()),'polynomial_equation_candidate':(LinearEquationSolver(),QuadraticEquationSolver()),'single_symbol_inequality_candidate':(LinearInequalitySolver(),)}
SOLVER_BY_ID={solver.solver_id:solver for solvers in SOLVER_REGISTRY.values() for solver in solvers}
def execute_solver_id(solver_id,expr,symbols,features):
    solver=SOLVER_BY_ID.get(solver_id)
    if not solver:raise SolverError('NO_SOLVER_MATCH',{})
    return solver.solve_candidate(expr,{'symbol':symbols[0] if symbols else None})
def routing_report(expr,classification,features,symbols):
    evaluated=[]
    for solver in SOLVER_REGISTRY.get(classification,()):
        matched=False;reasons=[]
        try:
            if solver.solver_id in {'linear_equation','quadratic_equation'}:
                if len(symbols)!=1:reasons.append('symbol_count_not_one')
                else:
                    degree=sympy.Poly(expr.lhs-expr.rhs,symbols[0]).degree();wanted=1 if solver.solver_id=='linear_equation' else 2
                    matched=degree==wanted;reasons=[] if matched else [f'polynomial_degree_not_{wanted}']
            else:matched=solver.supports(classification,features);reasons=[] if matched else ['classification_not_supported']
        except Exception:reasons=['structural_analysis_failed']
        evaluated.append({'solver_id':solver.solver_id+'_v1','matched':matched,'reasons':reasons})
    matches=[x for x in evaluated if x['matched']]
    return {'classification':classification,'evaluated_solvers':evaluated,'selected_solver_id':matches[0]['solver_id'] if len(matches)==1 else None},matches
def route_and_solve(expr,classification,features,symbols,limits=SolverLimits()):
    if len(symbols)>limits.max_symbols:raise SolverError('SOLVER_RESOURCE_LIMIT',{'max_symbols':limits.max_symbols})
    report,matches=routing_report(expr,classification,features,symbols)
    if not matches:raise SolverError('NO_SOLVER_MATCH',{'routing_report':report})
    if len(matches)>1:raise SolverError('MULTIPLE_SOLVERS_MATCH',{'routing_report':report})
    solvers=[SOLVER_BY_ID[matches[0]['solver_id'].removesuffix('_v1')]]
    started=time.monotonic();result=solvers[0].solve_candidate(expr,{'symbol':symbols[0] if symbols else None})
    elapsed=int((time.monotonic()-started)*1000)
    if elapsed>limits.max_solver_duration_ms:raise SolverError('SOLVER_TIMEOUT',{'limit':limits.max_solver_duration_ms})
    return solvers[0],result,elapsed
