import os,tempfile,unittest,concurrent.futures,sqlite3,asyncio,time
from pathlib import Path
os.environ.setdefault('AI_STUDIO_API_URL','http://example.invalid');os.environ.setdefault('AI_STUDIO_ACCESS_TOKEN','test')
import sympy
from app.math_workbook.parsing.normalization import normalize
from app.math_workbook.parsing.tokenizer import tokenize
from app.math_workbook.parsing.parser import parse
from app.math_workbook.ir.problem_ir import build_problem_ir
from app.math_workbook.sympy_bridge.builder import AstSympyBuilder
from app.math_workbook.sympy_bridge.symbol_table import SymbolTable
from app.math_workbook.sympy_bridge.build_errors import BuildError
from app.math_workbook.migrations.runner import upgrade,MIGRATIONS
from app.math_workbook.storage import MathWorkbookStore
from app.math_workbook.explanation.provider import MockExplanationProvider
from app.math_workbook.explanation.validator import validate_explanation

def tree(s):return parse(tokenize(normalize(s).normalized,'f'))
class SympyBridgeTests(unittest.TestCase):
    def build(self,s):
        root=tree(s);ir=build_problem_ir('p',1,[root],['f']);return AstSympyBuilder(SymbolTable(list(ir.variables))).build(root)
    def test_exact_decimals_and_structural_mapping(self):
        self.assertEqual(self.build('0.5'),sympy.Rational(1,2));self.assertEqual(self.build('1.25'),sympy.Rational(5,4));self.assertEqual(type(self.build('2x+3=7')).__name__,'Equality')
    def test_domains_and_malicious_symbols_rejected(self):
        with self.assertRaises(BuildError):SymbolTable([{'name':'__x','domain':'real'}])
        with self.assertRaises(BuildError):SymbolTable([{'name':'x','domain':'evil'}])
    def test_constraints_and_persistence(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);upgrade(str(root/'db.sqlite'));s=MathWorkbookStore(str(root/'db.sqlite'),str(root/'files'))
            imp=s.create_import('image','x','u');page=s.create_page(imp,0,'x',{},'ready');region=s.add_region(page,{'region_type':'printed_problem_area','bbox':(0,0,1,1),'reading_order':0});block=s.add_source_block(page,{'parent_region_id':region,'block_type':'formula_block','bbox':(0,0,1,1),'reading_order':0});formula=s.add_formula(page,{'region_id':region,'source_block_id':block,'bbox':(0,0,1,1),'source_type':'printed','role':'problem_expression','raw_latex':'\\frac{x}{x}','reading_order':0});s.update_formula(formula,{'user_confirmed_latex':'\\frac{x}{x}'})
            p=s.create_problem('u',imp,page,[0,0,1,1],[{'source_kind':'formula','source_id':formula,'semantic_role':'prompt','reading_order':0}]);s.parse_problem(p['id'],'u',p['revision']);build=s.build_problem(p['id'],'u');self.assertEqual(build['status'],'built');report=s.analyze_problem(p['id'],'u');self.assertEqual(report['status'],'analyzed');self.assertEqual(report['report_json']['domain_constraints'][0]['type'],'nonzero')
            s.update_formula(formula,{'user_confirmed_latex':'x'});self.assertIsNone(s.current_build(p['id'],'u'));self.assertIsNone(s.current_analysis(p['id'],'u'))
    def test_candidate_linear_solution_is_not_verified(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);upgrade(str(root/'db.sqlite'));s=MathWorkbookStore(str(root/'db.sqlite'),str(root/'files'))
            imp=s.create_import('image','x','u');page=s.create_page(imp,0,'x',{},'ready');region=s.add_region(page,{'region_type':'printed_problem_area','bbox':(0,0,1,1),'reading_order':0});block=s.add_source_block(page,{'parent_region_id':region,'block_type':'formula_block','bbox':(0,0,1,1),'reading_order':0});formula=s.add_formula(page,{'region_id':region,'source_block_id':block,'bbox':(0,0,1,1),'source_type':'printed','role':'problem_expression','raw_latex':'2x+3=7','reading_order':0});s.update_formula(formula,{'user_confirmed_latex':'2x+3=7'})
            p=s.create_problem('u',imp,page,[0,0,1,1],[{'source_kind':'formula','source_id':formula,'semantic_role':'prompt','reading_order':0}]);s.parse_problem(p['id'],'u',p['revision']);s.build_problem(p['id'],'u');s.analyze_problem(p['id'],'u');candidate=s.solve_problem(p['id'],'u',p['revision']);self.assertEqual(candidate['status'],'candidate');self.assertEqual(candidate['candidate_result_json']['candidate_type'],'unique_candidate');self.assertIsNotNone(s.current_candidate_solution(p['id'],'u'))
            verification=s.verify_problem(p['id'],'u',p['revision']);self.assertEqual(verification['status'],'verified');self.assertIsNotNone(s.current_verification(p['id'],'u'))
    def test_verify_concurrency_cross_user_and_revision_change(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);db=root/'db.sqlite';upgrade(str(db));s=MathWorkbookStore(str(db),str(root/'files'))
            imp=s.create_import('image','x','owner');page=s.create_page(imp,0,'x',{},'ready');region=s.add_region(page,{'region_type':'printed_problem_area','bbox':(0,0,1,1),'reading_order':0});block=s.add_source_block(page,{'parent_region_id':region,'block_type':'formula_block','bbox':(0,0,1,1),'reading_order':0});formula=s.add_formula(page,{'region_id':region,'source_block_id':block,'bbox':(0,0,1,1),'source_type':'printed','role':'problem_expression','raw_latex':'2x+3=7','reading_order':0});s.update_formula(formula,{'user_confirmed_latex':'2x+3=7'});p=s.create_problem('owner',imp,page,[0,0,1,1],[{'source_kind':'formula','source_id':formula,'semantic_role':'prompt','reading_order':0}]);s.parse_problem(p['id'],'owner',p['revision']);s.build_problem(p['id'],'owner');s.analyze_problem(p['id'],'owner');s.solve_problem(p['id'],'owner',p['revision'])
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool: reports=list(pool.map(lambda _:s.verify_problem(p['id'],'owner',p['revision']),range(2)))
            self.assertEqual({r['id'] for r in reports}, {reports[0]['id']});self.assertEqual(reports[0]['status'],'verified')
            with self.assertRaises(KeyError):s.verify_problem(p['id'],'other',p['revision'])
            with self.assertRaises(KeyError):s.current_verification(p['id'],'other')
            s.update_formula(formula,{'user_confirmed_latex':'2x+4=7'})
            with self.assertRaises(ValueError):s.verify_problem(p['id'],'owner',p['revision'])
            self.assertIsNone(s.current_verification(p['id'],'owner'))
    def test_migration_7_to_8_preserves_legacy_row(self):
        with tempfile.TemporaryDirectory() as d:
            db=Path(d)/'legacy.sqlite';con=sqlite3.connect(db);con.execute('CREATE TABLE schema_migrations(version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)')
            for version,filename in MIGRATIONS[:7]:
                con.executescript((Path(__file__).parents[1]/'app/math_workbook/migrations'/filename).read_text());con.execute('INSERT INTO schema_migrations(version) VALUES(?)',(version,))
            con.commit();con.execute("PRAGMA foreign_keys=OFF");con.execute("INSERT INTO math_verification_reports(id,problem_id,solve_result_id,input_solve_hash,verifier_version,status,report_json,created_at,revision) VALUES('old','p','s','h','legacy','inconclusive','{}','now',1)");con.commit();con.close()
            self.assertEqual(upgrade(str(db)),11)
            with sqlite3.connect(db) as check:self.assertEqual(check.execute("SELECT report_json FROM math_verification_reports WHERE id='old'").fetchone()[0],'{}')
    def test_verified_explanation_gate_mock_and_stale(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);db=root/'db.sqlite';upgrade(str(db));s=MathWorkbookStore(str(db),str(root/'files'));imp=s.create_import('image','x','u');page=s.create_page(imp,0,'x',{},'ready');region=s.add_region(page,{'region_type':'printed_problem_area','bbox':(0,0,1,1),'reading_order':0});block=s.add_source_block(page,{'parent_region_id':region,'block_type':'formula_block','bbox':(0,0,1,1),'reading_order':0});formula=s.add_formula(page,{'region_id':region,'source_block_id':block,'bbox':(0,0,1,1),'source_type':'printed','role':'problem_expression','raw_latex':'2x+3=7','reading_order':0});s.update_formula(formula,{'user_confirmed_latex':'2x+3=7'});p=s.create_problem('u',imp,page,[0,0,1,1],[{'source_kind':'formula','source_id':formula,'semantic_role':'prompt','reading_order':0}]);s.parse_problem(p['id'],'u',p['revision']);s.build_problem(p['id'],'u');s.analyze_problem(p['id'],'u');s.solve_problem(p['id'],'u',p['revision']);s.verify_problem(p['id'],'u',p['revision']);prepared=s.prepare_explanation(p['id'],'u',p['revision'],{'language':'zh-CN','level':'beginner','detail':'detailed'});raw=asyncio.run(MockExplanationProvider().generate_explanation(prepared['input']));validated=validate_explanation(raw,prepared['input']);saved=s.persist_explanation(prepared,'mock','mock','1',raw,validated,'validated',[],{'duration_ms':1});self.assertEqual(saved['status'],'validated');self.assertIsNotNone(s.current_explanation(p['id'],'u'))
            s.update_formula(formula,{'user_confirmed_latex':'2x+4=7'});self.assertIsNone(s.current_explanation(p['id'],'u'));stale=s.persist_explanation(prepared,'mock','mock','1',raw,validated,'validated',[],{});self.assertEqual(stale['status'],'stale');self.assertIsNone(s.current_explanation(p['id'],'u'))
            with self.assertRaises(KeyError):s.prepare_explanation(p['id'],'other',p['revision'],{})
if __name__=='__main__':unittest.main()
