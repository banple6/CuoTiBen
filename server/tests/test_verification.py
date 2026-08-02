import os,unittest
import time,sqlite3,tempfile
os.environ.setdefault('AI_STUDIO_API_URL','http://example.invalid');os.environ.setdefault('AI_STUDIO_ACCESS_TOKEN','test')
from app.math_workbook.verification.engine import verify
from app.math_workbook.parsing.normalization import normalize
from app.math_workbook.parsing.tokenizer import tokenize
from app.math_workbook.parsing.parser import parse
from app.math_workbook.ir.problem_ir import build_problem_ir
from app.math_workbook.execution.verifier_executor import IsolatedVerifierExecutor
from app.math_workbook.migrations.runner import upgrade

def bad_protocol_worker(request,queue): queue.put({'protocol_version':'999','result':{}})
def fake_verified_worker(request,queue): queue.put({'protocol_version':'1','result':{'status':'verified','checks':[],'verified_result':{'is_verified':True}}})
def oversized_worker(request,queue): queue.put({'protocol_version':'1','result':{'status':'inconclusive','checks':[],'verified_result':None,'padding':'x'*10000}})
def crash_worker(request,queue): raise RuntimeError('crash')
def slow_worker(request,queue): time.sleep(2)
class VerificationTests(unittest.TestCase):
    def request(self,values,formula='2x+3=7',domains=None,candidate_type='unique_candidate'):
        root=parse(tokenize(normalize(formula).normalized,'f'));ir=build_problem_ir('p',1,[root],['f'],domains)
        return {'canonical_ast':[root.to_dict()],'problem_ir':ir.to_dict(),'analysis':{'structural_features':{}},'constraints_snapshot':[],'candidate':{'candidate_type':candidate_type,'values':values}}
    def test_wrong_candidates_are_rejected(self):
        wrong={'value':{'kind':'integer','value':3}}
        self.assertEqual(verify(self.request([wrong]))['status'],'rejected')
        missing=self.request([]);self.assertEqual(verify(missing)['status'],'rejected')
    def test_correct_candidate_verified(self):
        correct={'value':{'kind':'integer','value':2}}
        self.assertEqual(verify(self.request([correct]))['status'],'verified')
    def test_quadratic_matrix(self):
        def value(n):return {'value':{'kind':'integer','value':n}}
        self.assertEqual(verify(self.request([value(2),value(3)],'x^2-5x+6=0',candidate_type='two_real_candidates'))['status'],'verified')
        self.assertEqual(verify(self.request([value(2)],'x^2-5x+6=0',candidate_type='two_real_candidates'))['status'],'rejected')
        self.assertEqual(verify(self.request([value(2),value(3),value(4)],'x^2-5x+6=0',candidate_type='two_real_candidates'))['status'],'rejected')
        self.assertEqual(verify(self.request([value(2)],'x^2-4x+4=0',candidate_type='one_repeated_real_candidate'))['status'],'verified')
        self.assertEqual(verify(self.request([], 'x^2+1=0',candidate_type='no_solution_candidate'))['status'],'verified')
    def test_linear_degenerate_and_domain_constraints(self):
        def value(n):return {'value':{'kind':'integer','value':n}}
        self.assertEqual(verify(self.request([], '0x=3',candidate_type='no_solution_candidate'))['status'],'verified')
        self.assertEqual(verify(self.request([], '0x=0',candidate_type='identity_candidate'))['status'],'verified')
        self.assertEqual(verify(self.request([value(3)], '0x=0'))['status'],'rejected')
        self.assertEqual(verify(self.request([value(0)], 'x/x=1'))['status'],'rejected')
        self.assertEqual(verify(self.request([value(-1)], '\\sqrt{x}=1'))['status'],'rejected')
        self.assertEqual(verify(self.request([value(-1)], 'x=-1', {'x':'positive_real'}))['status'],'rejected')
    def test_inequality_direction_and_endpoints(self):
        root=parse(tokenize(normalize('2x+3<7').normalized,'f'));ir=build_problem_ir('p',1,[root],['f']);
        candidate={'candidate_type':'interval_candidate','interval':{'type':'interval','lower':None,'upper':{'value':{'kind':'rational','numerator':2,'denominator':1},'inclusive':False}},'values':[]}
        request={'canonical_ast':[root.to_dict()],'problem_ir':ir.to_dict(),'analysis':{},'constraints_snapshot':[],'candidate':candidate};self.assertEqual(verify(request)['status'],'verified')
        candidate['interval']['upper']['inclusive']=True;self.assertEqual(verify(request)['status'],'rejected')
        root=parse(tokenize(normalize('-2x+3<7').normalized,'f'));ir=build_problem_ir('p',1,[root],['f']);candidate={'candidate_type':'interval_candidate','interval':{'type':'interval','lower':{'value':{'kind':'rational','numerator':-2,'denominator':1},'inclusive':False},'upper':None},'values':[]};request={'canonical_ast':[root.to_dict()],'problem_ir':ir.to_dict(),'analysis':{},'constraints_snapshot':[],'candidate':candidate};self.assertEqual(verify(request)['status'],'verified')
    def test_worker_protocol_crash_oversize_verified_and_timeout(self):
        request={'protocol_version':'1'}
        for worker in (bad_protocol_worker,fake_verified_worker,oversized_worker,crash_worker):
            result=IsolatedVerifierExecutor(total_timeout_ms=3000,max_result_bytes=1000,worker_target=worker).execute(request);self.assertEqual(result['status'],'failed')
        result=IsolatedVerifierExecutor(total_timeout_ms=30,worker_target=slow_worker).execute(request);self.assertEqual(result['status'],'timeout');self.assertTrue(result['timed_out']);self.assertFalse(result['worker_exit_code'] is None)
    def test_migration_v8_indexes_foreign_keys_and_unique_shape(self):
        with tempfile.TemporaryDirectory() as d:
            db=d+'/x.sqlite';self.assertEqual(upgrade(db),9)
            with sqlite3.connect(db) as con:
                columns={row[1] for row in con.execute('PRAGMA table_info(math_verification_reports)')};self.assertIn('candidate_solution_result_id',columns);self.assertIn('checks_json',columns)
                foreign={row[2] for row in con.execute('PRAGMA foreign_key_list(math_verification_reports)')};self.assertIn('math_problems',foreign);self.assertIn('math_candidate_solution_results',foreign)
                indexes={row[1] for row in con.execute('PRAGMA index_list(math_verification_reports)')};self.assertIn('idx_math_verify_dedupe',indexes);self.assertTrue(con.execute("SELECT sql FROM sqlite_master WHERE name='idx_math_verify_dedupe'").fetchone()[0].startswith('CREATE UNIQUE'))
