import os
import tempfile
import unittest
from pathlib import Path
os.environ.setdefault('AI_STUDIO_API_URL','http://example.invalid');os.environ.setdefault('AI_STUDIO_ACCESS_TOKEN','test')
from app.math_workbook.parsing.normalization import normalize
from app.math_workbook.parsing.tokenizer import tokenize
from app.math_workbook.parsing.parser import parse
from app.math_workbook.parsing.errors import ParseError
from app.math_workbook.ir.expression_nodes import from_dict,node_count,depth
from app.math_workbook.migrations.runner import upgrade
from app.math_workbook.storage import MathWorkbookStore

class ParserTests(unittest.TestCase):
    def tree(self,text): return parse(tokenize(normalize(text).normalized,'f'))
    def test_normalization_and_equation(self):
        n=normalize('（2×x − 3）≤7');self.assertEqual(n.normalized,'(2*x - 3)<=7');self.assertTrue(n.transformations)
        root=self.tree('2x+3=7');self.assertEqual(root.type,'equation');self.assertEqual(root.left.type,'add')
    def test_precedence_fraction_root_and_power(self):
        self.assertEqual(self.tree('-x^2').type,'negate');self.assertEqual(self.tree('-x^2').operand.type,'power')
        self.assertEqual(self.tree('(-x)^2').type,'power');self.assertEqual(self.tree('\\frac{x+1}{x-1}').type,'divide')
        self.assertEqual(self.tree('3(x+2)').type,'multiply');self.assertEqual(self.tree('(x+1)(x-1)').type,'multiply');self.assertEqual(self.tree('\\sqrt{x+1}').type,'squareroot')
    def test_security_and_ambiguity_rejected(self):
        for text in ['__import__("os")','x.__class__','open("/etc/passwd")','lambda x:x','[1,2,3]','{"x":1}','x;import os','\\input{x}','x=y=z','xy']:
            with self.assertRaises(ParseError):self.tree(text)
    def test_ast_roundtrip_and_metrics(self):
        root=self.tree('2x+3=7');clone=from_dict(root.to_dict());self.assertEqual(clone.to_dict(),root.to_dict());self.assertGreater(node_count(root),1);self.assertGreater(depth(root),1)
        with self.assertRaises(ValueError):from_dict({'type':'evil'})
    def test_parse_result_stale_and_deduplicated(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);upgrade(str(root/'db.sqlite'));store=MathWorkbookStore(str(root/'db.sqlite'),str(root/'files'))
            imp=store.create_import('image','x','u');page=store.create_page(imp,0,'x',{},'ready');region=store.add_region(page,{'region_type':'printed_problem_area','bbox':(0,0,1,1),'reading_order':0});block=store.add_source_block(page,{'parent_region_id':region,'block_type':'formula_block','bbox':(0,0,1,1),'reading_order':0});formula=store.add_formula(page,{'region_id':region,'source_block_id':block,'bbox':(0,0,1,1),'source_type':'printed','role':'problem_expression','raw_latex':'2x+3=7','reading_order':0});store.update_formula(formula,{'user_confirmed_latex':'2x+3=7'})
            p=store.create_problem('u',imp,page,[0,0,1,1],[{'source_kind':'formula','source_id':formula,'semantic_role':'prompt','reading_order':0}]);a=store.parse_problem(p['id'],'u',p['revision']);b=store.parse_problem(p['id'],'u',p['revision']);self.assertEqual(a['id'],b['id']);self.assertEqual(a['status'],'parsed');self.assertIsNotNone(store.current_parse(p['id'],'u'))
            store.update_formula(formula,{'user_confirmed_latex':'2x+4=7'});self.assertIsNone(store.current_parse(p['id'],'u'))

if __name__=='__main__':unittest.main()
