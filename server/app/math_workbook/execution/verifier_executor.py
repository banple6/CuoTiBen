from __future__ import annotations
import json,multiprocessing,time
from .worker_protocol import PROTOCOL_VERSION
def _worker(request,queue):
    try:
        if not isinstance(request,dict) or request.get('protocol_version')!=PROTOCOL_VERSION:raise ValueError('INVALID_VERIFIER_REQUEST')
        from app.math_workbook.verification.engine import verify
        result=verify(request)
        # A worker may report only that all checks passed; the parent alone can mint verified.
        if result.get('status')=='verified':
            result['status']='checks_passed';result['verified_result']=None
        queue.put({'protocol_version':PROTOCOL_VERSION,'result':result})
    except Exception as error:queue.put({'protocol_version':PROTOCOL_VERSION,'result':{'status':'failed','checks':[],'verification_plan':{},'verified_result':None,'warnings':[],'errors':[{'code':type(error).__name__}]}})
class IsolatedVerifierExecutor:
    def __init__(self,total_timeout_ms=10000,max_result_bytes=64000,worker_target=_worker):self.timeout=total_timeout_ms;self.max_bytes=max_result_bytes;self.worker_target=worker_target
    def execute(self,request):
        ctx=multiprocessing.get_context('spawn');queue=ctx.Queue(1);process=ctx.Process(target=self.worker_target,args=(request,queue));started=time.monotonic();process.start();process.join(self.timeout/1000)
        if process.is_alive():
            process.terminate();process.join(.5);method='terminate'
            if process.is_alive():process.kill();process.join();method='kill'
            return {'status':'timeout','timed_out':True,'termination_method':method,'worker_exit_code':process.exitcode,'duration_ms':int((time.monotonic()-started)*1000)}
        try:body=queue.get(timeout=.2)
        except Exception:return {'status':'failed','timed_out':False,'termination_method':'none','worker_exit_code':process.exitcode,'duration_ms':int((time.monotonic()-started)*1000),'errors':[{'code':'WORKER_NO_RESULT'}]}
        if not isinstance(body,dict) or body.get('protocol_version')!=PROTOCOL_VERSION or len(json.dumps(body).encode())>self.max_bytes:return {'status':'failed','timed_out':False,'termination_method':'none','worker_exit_code':process.exitcode,'duration_ms':0,'errors':[{'code':'INVALID_VERIFIER_RESPONSE'}]}
        result=body.get('result')
        verified_result=result.get('verified_result') if isinstance(result,dict) else None
        if not isinstance(result,dict) or result.get('status') not in {'checks_passed','rejected','inconclusive','timeout','failed','not_applicable'} or (isinstance(verified_result,dict) and verified_result.get('is_verified')):return {'status':'failed','timed_out':False,'termination_method':'none','worker_exit_code':process.exitcode,'duration_ms':0,'errors':[{'code':'INVALID_VERIFIER_RESULT'}]}
        return {**body,'timed_out':False,'termination_method':'none','worker_exit_code':process.exitcode,'duration_ms':int((time.monotonic()-started)*1000),'execution_mode':'isolated_process'}
