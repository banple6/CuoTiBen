from __future__ import annotations
import json,multiprocessing,time
from .limits import SolverExecutionLimits
from .worker_protocol import PROTOCOL_VERSION,validate_request,validate_response

def _worker(request,queue):
    try:
        validate_request(request)
        from app.math_workbook.ir.expression_nodes import from_dict
        from app.math_workbook.sympy_bridge.symbol_table import SymbolTable
        from app.math_workbook.sympy_bridge.builder import AstSympyBuilder
        from app.math_workbook.solving.router import execute_solver_id
        roots=[from_dict(x) for x in request['canonical_ast']]
        if len(roots)!=1:raise ValueError('UNSUPPORTED_PROBLEM_CLASS')
        table=SymbolTable(request['problem_ir']['variables']);expr=AstSympyBuilder(table).build(roots[0])
        result=execute_solver_id(request['solver_id'],expr,list(table.symbols.values()),request['analysis']['structural_features'])
        queue.put({'protocol_version':PROTOCOL_VERSION,'status':result['status'],'solver_id':request['solver_id'],'solver_version':'1','candidate_result':result,'warnings':[],'errors':[],'timings':{}})
    except Exception as error:
        queue.put({'protocol_version':PROTOCOL_VERSION,'status':'failed','solver_id':request.get('solver_id','numeric_exact') if isinstance(request,dict) else 'numeric_exact','solver_version':'1','candidate_result':{'status':'failed','candidate_type':'none','values':[]},'warnings':[],'errors':[{'code':type(error).__name__}],'timings':{}})

class IsolatedSolverExecutor:
    def __init__(self,limits=SolverExecutionLimits(),worker_target=_worker):self.limits=limits;self.worker_target=worker_target
    def execute(self,request):
        validate_request(request);ctx=multiprocessing.get_context('spawn');queue=ctx.Queue(maxsize=1);process=ctx.Process(target=self.worker_target,args=(request,queue));started=time.monotonic();process.start();process.join(self.limits.total_timeout_ms/1000)
        timed_out=process.is_alive();termination='none'
        if timed_out:
            process.terminate();process.join(0.5);termination='terminate'
            if process.is_alive():process.kill();process.join();termination='kill'
            return {'status':'timeout','errors':[{'code':'SOLVER_TIMEOUT'}],'duration_ms':int((time.monotonic()-started)*1000),'execution_mode':'isolated_process','worker_exit_code':process.exitcode,'timed_out':True,'termination_method':termination}
        try: response=queue.get(timeout=0.2)
        except Exception:return {'status':'failed','errors':[{'code':'WORKER_NO_RESULT'}],'duration_ms':int((time.monotonic()-started)*1000),'execution_mode':'isolated_process','worker_exit_code':process.exitcode,'timed_out':False,'termination_method':termination}
        encoded=json.dumps(response,separators=(',',':'))
        if len(encoded.encode())>self.limits.max_result_bytes:return {'status':'failed','errors':[{'code':'WORKER_RESULT_TOO_LARGE'}],'duration_ms':int((time.monotonic()-started)*1000),'execution_mode':'isolated_process','worker_exit_code':process.exitcode,'timed_out':False,'termination_method':termination}
        try:validate_response(response)
        except ValueError as error:return {'status':'failed','errors':[{'code':str(error)}],'duration_ms':int((time.monotonic()-started)*1000),'execution_mode':'isolated_process','worker_exit_code':process.exitcode,'timed_out':False,'termination_method':termination}
        return {**response,'duration_ms':int((time.monotonic()-started)*1000),'execution_mode':'isolated_process','worker_exit_code':process.exitcode,'timed_out':False,'termination_method':termination}
