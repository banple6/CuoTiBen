import os,time,unittest
os.environ.setdefault('AI_STUDIO_API_URL','http://example.invalid');os.environ.setdefault('AI_STUDIO_ACCESS_TOKEN','test')
from app.math_workbook.execution.solver_executor import IsolatedSolverExecutor
from app.math_workbook.execution.limits import SolverExecutionLimits

def slow_worker(request,queue):
    time.sleep(2)

class ExecutorTests(unittest.TestCase):
    def request(self):return {'protocol_version':'1','solver_id':'numeric_exact','canonical_ast':[],'problem_ir':{},'analysis':{},'constraints_snapshot':[],'limits':{}}
    def test_hard_timeout_terminates_spawned_worker(self):
        result=IsolatedSolverExecutor(SolverExecutionLimits(total_timeout_ms=50),slow_worker).execute(self.request())
        self.assertTrue(result['timed_out']);self.assertEqual(result['execution_mode'],'isolated_process');self.assertFalse(result['worker_exit_code'] is None)
