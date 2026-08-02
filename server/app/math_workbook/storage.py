"""Durable math-workbook records. Schema changes are only made by migrations."""
from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import uuid
from sympy import srepr as sympy_srepr
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterator

from app.math_workbook.migrations.runner import require_current
from app.math_workbook.parsing.errors import ParseError
from app.math_workbook.parsing.normalization import NORMALIZATION_VERSION, normalize
from app.math_workbook.parsing.tokenizer import tokenize
from app.math_workbook.parsing.parser import parse
from app.math_workbook.ir.problem_ir import IR_VERSION, build_problem_ir
from app.math_workbook.ir.expression_nodes import from_dict
from app.math_workbook.sympy_bridge.builder import AstSympyBuilder, BUILDER_VERSION, SYMPY_VERSION
from app.math_workbook.sympy_bridge.symbol_table import SymbolTable
from app.math_workbook.sympy_bridge.build_errors import BuildError
from app.math_workbook.analysis.structural_classifier import analyze
from app.math_workbook.analysis.domain_constraints import extract_constraints
from app.math_workbook.analysis.report import ANALYSIS_VERSION, AnalysisReport
from app.math_workbook.solving.router import SOLVER_VERSION
from app.math_workbook.solving.errors import SolverError
from app.math_workbook.execution.solver_executor import IsolatedSolverExecutor
from app.math_workbook.execution.verifier_executor import IsolatedVerifierExecutor
from app.math_workbook.verification.engine import VERIFIER_VERSION, required_checks, validate_report
from app.math_workbook.explanation.prompt import PROMPT_ID, PROMPT_VERSION, prompt_metadata, SCHEMA_VERSION as EXPLANATION_SCHEMA_VERSION, TRACE_VERSION as EXPLANATION_TRACE_VERSION, RENDERER_VERSION as EXPLANATION_RENDERER_VERSION
from app.math_workbook.explanation.trace import attach_trace_binding, validate_trace_artifact
from app.math_workbook.explanation.validator import validate_explanation


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def request_hash(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()


class IdempotencyConflict(ValueError):
    pass


class RevisionConflict(ValueError):
    pass


class ParseEligibilityError(ValueError):
    pass


class MathWorkbookStore:
    def __init__(self, database_path: str, storage_root: str):
        self.database_path, self.storage_root = Path(database_path), Path(storage_root)
        self.storage_root.mkdir(parents=True, exist_ok=True)
        require_current(str(self.database_path))

    @contextmanager
    def _connect(self, immediate: bool = False) -> Iterator[sqlite3.Connection]:
        connection = sqlite3.connect(self.database_path, timeout=5, isolation_level=None)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("BEGIN IMMEDIATE" if immediate else "BEGIN")
        try:
            yield connection
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    def create_import(self, source_type: str, source_file_path: str, user_id: str = "anonymous", *, source_sha256: str | None = None, source_size_bytes: int | None = None) -> str:
        record_id, now = str(uuid.uuid4()), utc_now()
        with self._connect() as db:
            db.execute("INSERT INTO math_imports(id,user_id,source_type,source_file_path,source_sha256,source_size_bytes,status,page_count,created_at,updated_at) VALUES(?,?,?,?,?,?,?,0,?,?)", (record_id,user_id,source_type,source_file_path,source_sha256,source_size_bytes,"uploaded",now,now))
        return record_id

    def set_import_source(self, import_id: str, user_id: str, path: Path) -> None:
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        with self._connect() as db:
            db.execute("UPDATE math_imports SET source_file_path=?,source_sha256=?,source_size_bytes=?,updated_at=? WHERE id=? AND user_id=?", (str(path),digest,path.stat().st_size,utc_now(),import_id,user_id))

    def create_page(self, import_id: str, page_index: int, original_image_path: str, metadata: dict, status: str) -> str:
        page_id, now = str(uuid.uuid4()), utc_now()
        with self._connect() as db:
            db.execute("INSERT INTO math_pages(id,import_id,page_index,original_image_path,transform_metadata,segmentation_status,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)", (page_id,import_id,page_index,original_image_path,json.dumps(metadata),status,now,now))
            db.execute("UPDATE math_imports SET page_count=page_count+1,status='processing',updated_at=? WHERE id=?", (now,import_id))
        return page_id

    def update_page_views(self, page_id: str, **v: Any) -> None:
        with self._connect() as db:
            db.execute("UPDATE math_pages SET normalized_image_path=?,print_view_path=?,handwriting_view_path=?,handwriting_mask_path=?,width=?,height=?,transform_metadata=?,segmentation_status=?,updated_at=?,revision=revision+1 WHERE id=?", (v['normalized'],v['print_view'],v['handwriting_view'],v['mask'],v['width'],v['height'],json.dumps(v['metadata']),v['status'],utc_now(),page_id))

    def save_raw_result(self, page_id: str, provider: str, pipeline: str, raw: dict) -> str:
        path = self.storage_root / "raw" / f"{page_id}-{uuid.uuid4()}.json"; path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp"); tmp.write_text(json.dumps(raw,ensure_ascii=False),encoding="utf-8"); os.replace(tmp,path)
        with self._connect() as db:
            db.execute("INSERT INTO math_raw_parse_results VALUES(?,?,?,?,NULL,?,?,?)", (str(uuid.uuid4()),page_id,provider,pipeline,str(path),json.dumps({'bytes':path.stat().st_size}),utc_now()))
        return str(path)

    def add_region(self, page_id: str, data: dict) -> str:
        ident, now = str(uuid.uuid4()), utc_now()
        with self._connect() as db:
            db.execute("INSERT INTO math_regions(id,page_id,region_type,bbox,polygon,crop_path,source_view,reading_order,layout_score,classification_score,occluded_by_handwriting,requires_review,review_reasons,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (ident,page_id,data['region_type'],json.dumps(data['bbox']),json.dumps(data.get('polygon',[])),data.get('crop_path'),data.get('source_view','original'),data['reading_order'],data.get('layout_score'),data.get('classification_score'),int(data.get('occluded_by_handwriting',False)),int(data.get('requires_review',False)),json.dumps(data.get('review_reasons',[])),now,now))
        return ident

    def add_source_block(self,page_id:str,data:dict)->str:
        ident,now=str(uuid.uuid4()),utc_now()
        with self._connect() as db: db.execute("INSERT INTO math_source_blocks(id,page_id,parent_region_id,block_type,bbox,crop_path,source_type,reading_order,previous_block_id,next_block_id,requires_review,review_reasons,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,NULL,NULL,?,?,?,?)",(ident,page_id,data.get('parent_region_id'),data['block_type'],json.dumps(data['bbox']),data.get('crop_path'),data.get('source_type','unknown'),data['reading_order'],int(data.get('requires_review',False)),json.dumps(data.get('review_reasons',[])),now,now))
        return ident

    def link_blocks(self, ids:list[str])->None:
        with self._connect() as db:
            for n, ident in enumerate(ids): db.execute("UPDATE math_source_blocks SET previous_block_id=?,next_block_id=?,updated_at=?,revision=revision+1 WHERE id=?",(ids[n-1] if n else None,ids[n+1] if n+1<len(ids) else None,utc_now(),ident))

    def add_formula(self,page_id:str,data:dict)->str:
        ident,now=str(uuid.uuid4()),utc_now()
        with self._connect() as db: db.execute("INSERT INTO math_formula_candidates VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",(ident,page_id,data.get('region_id'),data.get('source_block_id'),json.dumps(data['bbox']),json.dumps(data.get('polygon',[])),data.get('crop_path'),data.get('source_type','unknown'),data.get('role','unknown'),data.get('raw_latex'),data.get('normalized_latex'),None,data.get('layout_score'),data.get('recognition_score'),data.get('recognition_score_type'),data.get('parseable'),int(data.get('occluded_by_handwriting',False)),int(data.get('requires_review',False)),json.dumps(data.get('review_reasons',[])),data['reading_order'],now,now))
        return ident

    @staticmethod
    def _reject_anonymous(user_id: str | None) -> None:
        if user_id is not None and (not user_id.strip() or user_id.strip().lower() == "anonymous"):
            raise ValueError("MATH_USER_REQUIRED")

    @staticmethod
    def _owned_page_query() -> str:
        return """SELECT p.* FROM math_pages p
                  JOIN math_imports i ON i.id=p.import_id
                  WHERE p.id=? AND i.user_id=?"""

    @staticmethod
    def _owned_region_query() -> str:
        return """SELECT r.* FROM math_regions r
                  JOIN math_pages p ON p.id=r.page_id
                  JOIN math_imports i ON i.id=p.import_id
                  WHERE r.id=? AND i.user_id=?"""

    @staticmethod
    def _owned_formula_query() -> str:
        return """SELECT f.* FROM math_formula_candidates f
                  JOIN math_pages p ON p.id=f.page_id
                  JOIN math_imports i ON i.id=p.import_id
                  WHERE f.id=? AND i.user_id=?"""

    def update_formula(self,formula_id:str,changes:dict,user_id: str | None = None)->dict:
        allowed={'user_confirmed_latex','source_type','role','reading_order'}
        if set(changes)-allowed: raise ValueError('unsupported formula fields')
        self._reject_anonymous(user_id)
        with self._connect() as db:
            current_row = db.execute(self._owned_formula_query(), (formula_id, user_id)).fetchone() if user_id is not None else db.execute("SELECT * FROM math_formula_candidates WHERE id=?", (formula_id,)).fetchone()
            if not current_row: raise KeyError(formula_id)
            current = self._decode(dict(current_row))
            for key,value in changes.items():
                if current[key] != value:
                    db.execute("INSERT INTO math_formula_revisions(id,formula_id,field_name,before_value,after_value,edited_at,source_revision) VALUES(?,?,?,?,?,?,NULL)",(str(uuid.uuid4()),formula_id,key,current[key],value,utc_now()))
                    db.execute(f"UPDATE math_formula_candidates SET {key}=?,updated_at=? WHERE id=?",(value,utc_now(),formula_id))
                    self._bump_affected_problems(db,'formula',formula_id)
        return self.get_formula(formula_id, user_id) or {}

    def update_region(self,region_id:str,changes:dict,user_id: str | None = None)->dict:
        allowed={'region_type','reading_order','requires_review','review_reasons'}
        if set(changes)-allowed: raise ValueError('unsupported region fields')
        self._reject_anonymous(user_id)
        with self._connect() as db:
            current_row = db.execute(self._owned_region_query(), (region_id, user_id)).fetchone() if user_id is not None else db.execute("SELECT * FROM math_regions WHERE id=?", (region_id,)).fetchone()
            if not current_row: raise KeyError(region_id)
            for k,v in changes.items(): db.execute(f"UPDATE math_regions SET {k}=?,updated_at=?,revision=revision+1 WHERE id=?",(json.dumps(v) if k=='review_reasons' else v,utc_now(),region_id))
            self._bump_affected_problems(db,'region',region_id)
        return self.get_region(region_id, user_id) or {}

    def complete_import(self,import_id:str,status:str='ready')->None:
        with self._connect() as db: db.execute("UPDATE math_imports SET status=?,updated_at=? WHERE id=?",(status,utc_now(),import_id))

    def reserve_idempotency(self,user_id:str,operation:str,key:str,body:Any)->dict:
        digest=request_hash(body); now=utc_now()
        with self._connect(immediate=True) as db:
            row=db.execute("SELECT * FROM math_idempotency_records WHERE user_id=? AND operation_type=? AND idempotency_key=?",(user_id,operation,key)).fetchone()
            if row:
                result=self._decode(dict(row))
                if result['request_hash'] != digest: raise IdempotencyConflict('Idempotency-Key was reused with another request body')
                result['created'] = False
                return result
            ident=str(uuid.uuid4()); db.execute("INSERT INTO math_idempotency_records(id,user_id,operation_type,idempotency_key,request_hash,status,created_at,updated_at,expires_at) VALUES(?,?,?,?,?,'processing',?,?,?)",(ident,user_id,operation,key,digest,now,now,(datetime.now(timezone.utc)+timedelta(days=1)).strftime('%Y-%m-%dT%H:%M:%SZ')))
            return {'id':ident,'request_hash':digest,'status':'processing','created':True}

    def finish_idempotency(self,record_id:str,status:int,resource_type:str,resource_id:str,body:dict)->None:
        with self._connect() as db: db.execute("UPDATE math_idempotency_records SET status='completed',response_status=?,resource_type=?,resource_id=?,response_body=?,updated_at=? WHERE id=?",(status,resource_type,resource_id,json.dumps(body),utc_now(),record_id))

    def enqueue_job(self,resource_type:str,resource_id:str,job_type:str)->str:
        ident,now=str(uuid.uuid4()),utc_now()
        with self._connect() as db: db.execute("INSERT INTO math_processing_jobs(id,resource_type,resource_id,job_type,status,available_at,created_at,updated_at) VALUES(?,?,?,?,'queued',?,?,?)",(ident,resource_type,resource_id,job_type,now,now,now))
        return ident

    def claim_job(self,worker_id:str,lease_seconds:int=60)->dict|None:
        now=utc_now(); expires=(datetime.now(timezone.utc)+timedelta(seconds=lease_seconds)).strftime('%Y-%m-%dT%H:%M:%SZ')
        with self._connect(immediate=True) as db:
            row=db.execute("SELECT * FROM math_processing_jobs WHERE (status='queued' AND available_at<=?) OR (status='claimed' AND lease_expires_at<?) ORDER BY available_at,id LIMIT 1",(now,now)).fetchone()
            if not row:return None
            cur=db.execute("UPDATE math_processing_jobs SET status='claimed',claimed_by=?,claimed_at=?,lease_expires_at=?,attempt_count=attempt_count+1,updated_at=?,revision=revision+1 WHERE id=? AND ((status='queued') OR lease_expires_at<?)",(worker_id,now,expires,now,row['id'],now))
            return self._decode(dict(db.execute("SELECT * FROM math_processing_jobs WHERE id=?",(row['id'],)).fetchone())) if cur.rowcount else None

    def complete_job(self,job_id:str,worker_id:str)->bool:
        with self._connect(immediate=True) as db:
            return db.execute("UPDATE math_processing_jobs SET status='completed',updated_at=?,revision=revision+1 WHERE id=? AND status='claimed' AND claimed_by=? AND lease_expires_at>?",(utc_now(),job_id,worker_id,utc_now())).rowcount == 1

    def create_problem(self,user_id:str,import_id:str,page_id:str,bbox:Any,sources:list[dict],**extra:Any)->dict:
        ident,now=str(uuid.uuid4()),utc_now()
        with self._connect(immediate=True) as db:
            self._validate_problem_scope(db,user_id,import_id,page_id,sources)
            db.execute("INSERT INTO math_problems(id,user_id,import_id,page_id,problem_bbox,recognition_status,parse_status,solve_status,verification_status,problem_type_hint,requires_review,review_reasons,variable_domains_json,created_at,updated_at) VALUES(?,?,?,?,?,'review','not_started','not_started','not_started',?,?,?,?,?,?)",(ident,user_id,import_id,page_id,json.dumps(bbox),extra.get('problem_type_hint'),int(extra.get('requires_review',False)),json.dumps(extra.get('review_reasons',[])),json.dumps(extra.get('variable_domains',{})),now,now))
            self._replace_sources(db,ident,sources)
        return self.get_problem(ident,user_id) or {}

    def update_problem(self,ident:str,user_id:str,expected_revision:int,changes:dict)->dict:
        allowed={'problem_bbox','problem_type_hint','requires_review','review_reasons','variable_domains','sources'}
        if set(changes)-allowed:raise ValueError('unsupported problem fields')
        changes = dict(changes)
        with self._connect(immediate=True) as db:
            row=db.execute("SELECT * FROM math_problems WHERE id=? AND user_id=?",(ident,user_id)).fetchone()
            if not row: raise KeyError(ident)
            if row['revision'] != expected_revision: raise RevisionConflict('expected_revision does not match current revision')
            sources_changed = 'sources' in changes
            math_input_changed = sources_changed or 'variable_domains' in changes
            if sources_changed:
                self._validate_problem_scope(db,user_id,row['import_id'],row['page_id'],changes['sources'])
                self._replace_sources(db,ident,changes.pop('sources'))
            fields=[];values=[]
            for k,v in changes.items(): fields.append(('variable_domains_json' if k=='variable_domains' else k)+"=?");values.append(json.dumps(v) if k in {'problem_bbox','review_reasons','variable_domains'} else v)
            if fields:
                source_clause = ",source_revision=source_revision+1" if math_input_changed else ""
                state_clause = ",parse_status='not_started',solve_status='not_started',verification_status='not_started'" if math_input_changed else ""
                db.execute("UPDATE math_problems SET "+','.join(fields)+",revision=revision+1"+source_clause+",expected_revision=expected_revision+1"+state_clause+",updated_at=? WHERE id=?",(*values,utc_now(),ident))
            elif sources_changed: db.execute("UPDATE math_problems SET revision=revision+1,source_revision=source_revision+1,expected_revision=expected_revision+1,parse_status='not_started',solve_status='not_started',verification_status='not_started',updated_at=? WHERE id=?",(utc_now(),ident))
        return self.get_problem(ident,user_id) or {}

    def _replace_sources(self,db:sqlite3.Connection,problem_id:str,sources:list[dict])->None:
        db.execute("DELETE FROM math_problem_sources WHERE problem_id=?",(problem_id,))
        seen=set()
        for item in sources:
            key=(item['source_kind'],item['source_id'])
            if key in seen:raise ValueError('duplicate problem source')
            seen.add(key);db.execute("INSERT INTO math_problem_sources VALUES(?,?,?,?,?,?,?)",(str(uuid.uuid4()),problem_id,*key,item['semantic_role'],item['reading_order'],utc_now()))

    def _validate_problem_scope(self,db:sqlite3.Connection,user_id:str,import_id:str,page_id:str,sources:list[dict])->None:
        page=db.execute("SELECT i.user_id,i.id FROM math_pages p JOIN math_imports i ON i.id=p.import_id WHERE p.id=? AND i.id=?",(page_id,import_id)).fetchone()
        if not page or page['user_id'] != user_id:raise PermissionError('page/import not owned by user')
        for item in sources:
            table={'formula':'math_formula_candidates','source_block':'math_source_blocks','region':'math_regions'}.get(item.get('source_kind'))
            if not table:raise ValueError('unsupported source kind')
            found=db.execute(f"SELECT 1 FROM {table} WHERE id=? AND page_id=?",(item.get('source_id'),page_id)).fetchone()
            if not found:raise PermissionError('source is not on this page')

    def _bump_affected_problems(self,db:sqlite3.Connection,kind:str,source_id:str)->None:
        db.execute("UPDATE math_problems SET source_revision=source_revision+1,revision=revision+1,expected_revision=expected_revision+1,parse_status='not_started',solve_status='not_started',verification_status='not_started',updated_at=? WHERE id IN (SELECT problem_id FROM math_problem_sources WHERE source_kind=? AND source_id=?)",(utc_now(),kind,source_id))

    def get_problem(self,ident:str,user_id:str)->dict|None:
        with self._connect() as db:
            row=db.execute("SELECT * FROM math_problems WHERE id=? AND user_id=?",(ident,user_id)).fetchone()
            if not row:return None
            result=self._decode(dict(row));result['sources']=[self._decode(dict(x)) for x in db.execute("SELECT * FROM math_problem_sources WHERE problem_id=? ORDER BY reading_order",(ident,))];return result

    def _problem_input(self,db:sqlite3.Connection,ident:str,user_id:str)->tuple[sqlite3.Row,list[sqlite3.Row]]:
        p=db.execute("SELECT * FROM math_problems WHERE id=? AND user_id=?",(ident,user_id)).fetchone()
        if not p:raise KeyError(ident)
        return p,list(db.execute("SELECT * FROM math_problem_sources WHERE problem_id=? ORDER BY reading_order",(ident,)))

    def evaluate_parse_eligibility(self,ident:str,user_id:str,expected_revision:int|None=None)->dict:
        """One auditable gate shared by parse API and persistence; never consumes OCR raw_latex."""
        with self._connect() as db:
            p,sources=self._problem_input(db,ident,user_id)
            reasons=[];warnings=[]
            if expected_revision is not None and expected_revision != p['revision']: reasons.append('EXPECTED_REVISION_CONFLICT')
            if not any(s['semantic_role']=='prompt' for s in sources): reasons.append('PROMPT_SOURCE_REQUIRED')
            formulas=[]
            for s in sources:
                if s['semantic_role'] not in {'prompt','condition'}: continue
                if s['source_kind'] != 'formula': reasons.append('NON_FORMULA_PROMPT_UNSUPPORTED'); continue
                formula=db.execute("SELECT * FROM math_formula_candidates WHERE id=?",(s['source_id'],)).fetchone()
                if not formula: reasons.append('SOURCE_NOT_FOUND'); continue
                if formula['role'] not in {'problem_expression','condition'}: reasons.append('FORMULA_ROLE_NOT_PARSEABLE'); continue
                if not formula['user_confirmed_latex']: reasons.append('CONFIRMED_LATEX_REQUIRED'); continue
                formulas.append(formula)
            if p['requires_review']: reasons.append('BLOCKING_REVIEW_REQUIRED')
            if not formulas: reasons.append('PARSEABLE_FORMULA_REQUIRED')
            canonical=[{'formula_id':f['id'],'latex':f['user_confirmed_latex']} for f in formulas]
            return {'eligible':not reasons,'blocking_reasons':sorted(set(reasons)),'warnings':warnings,'source_revision':p['source_revision'],'input_hash':request_hash(canonical),'formulas':formulas,'problem':p}

    def parse_problem(self,ident:str,user_id:str,expected_revision:int|None=None)->dict:
        eligibility=self.evaluate_parse_eligibility(ident,user_id,expected_revision)
        if not eligibility['eligible']: raise ParseEligibilityError(json.dumps({k:v for k,v in eligibility.items() if k!='formulas' and k!='problem'}))
        p=eligibility['problem']; forms=eligibility['formulas']; digest=eligibility['input_hash']; parser_version='whitelist-v1'
        with self._connect(immediate=True) as db:
            existing = db.execute("SELECT * FROM math_parse_results WHERE problem_id=? AND input_source_revision=? AND input_hash=? AND parser_version=?", (ident, p['source_revision'], digest, parser_version)).fetchone()
            if existing:
                return self._decode(dict(existing))
            normalized=[];tokens=[];roots=[]
            try:
                for formula in forms:
                    item=normalize(formula['user_confirmed_latex']); normalized.append(item.to_dict())
                    formula_tokens=tokenize(item.normalized,formula['id']);tokens.extend(x.to_dict() for x in formula_tokens[:-1]);roots.append(parse(formula_tokens))
                ir=build_problem_ir(ident,p['source_revision'],roots,[f['id'] for f in forms],json.loads(p['variable_domains_json']))
                status='parsed'; errors=[];raw_ast=[x.to_dict() for x in roots];canonical_ast=raw_ast;ir_json=ir.to_dict()
            except ParseError as error:
                status='resource_limited' if error.code.endswith('LIMIT_EXCEEDED') else 'unsupported' if error.code.startswith('UNSUPPORTED') or error.code.startswith('FORBIDDEN') else 'failed'
                errors=[error.as_dict()];raw_ast=[];canonical_ast=[];ir_json=None
            ident2=str(uuid.uuid4());db.execute("INSERT INTO math_parse_results(id,problem_id,input_source_revision,input_hash,parser_version,status,ast_json,problem_ir_json,created_at,normalization_version,tokenizer_version,ir_version,normalized_input,tokens_json,raw_ast_json,canonical_ast_json,warnings_json,errors_json) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",(ident2,ident,p['source_revision'],digest,parser_version,status,json.dumps(raw_ast),json.dumps(ir_json) if ir_json else None,utc_now(),NORMALIZATION_VERSION,'whitelist-v1',IR_VERSION,json.dumps(normalized),json.dumps(tokens),json.dumps(raw_ast),json.dumps(canonical_ast),json.dumps([]),json.dumps(errors)))
            return self._decode(dict(db.execute("SELECT * FROM math_parse_results WHERE id=?",(ident2,)).fetchone()))

    def current_parse(self,ident:str,user_id:str)->dict|None:
        with self._connect() as db:
            p,_=self._problem_input(db,ident,user_id);row=db.execute("SELECT * FROM math_parse_results WHERE problem_id=? AND input_source_revision=? AND status='parsed' ORDER BY created_at DESC LIMIT 1",(ident,p['source_revision'])).fetchone();return self._decode(dict(row)) if row else None

    def current_solution(self,ident:str,user_id:str)->dict|None:return None
    def current_verification(self,ident:str,user_id:str)->dict|None:return None

    def build_problem(self,ident:str,user_id:str)->dict:
        with self._connect(immediate=True) as db:
            p,_=self._problem_input(db,ident,user_id)
            parse_row=db.execute("SELECT * FROM math_parse_results WHERE problem_id=? AND input_source_revision=? AND status='parsed' ORDER BY created_at DESC LIMIT 1",(ident,p['source_revision'])).fetchone()
            if not parse_row:raise ValueError('LATEST_PARSED_RESULT_REQUIRED')
            ast_json=json.loads(parse_row['canonical_ast_json']); ast_hash=request_hash(ast_json)
            existing=db.execute("SELECT * FROM math_sympy_build_results WHERE parse_result_id=? AND input_ast_hash=? AND builder_version=? AND sympy_version=?",(parse_row['id'],ast_hash,BUILDER_VERSION,SYMPY_VERSION)).fetchone()
            if existing:return self._decode(dict(existing))
            try:
                roots=[from_dict(item) for item in ast_json]
                ir=json.loads(parse_row['problem_ir_json']);table=SymbolTable(ir['variables'])
                if len(table.symbols)>32:raise BuildError('SYMBOL_LIMIT_EXCEEDED',{'limit':32})
                built=[AstSympyBuilder(table).build(node) for node in roots]
                artifact={'expression_repr':[repr(x) for x in built],'expression_srepr':[sympy_srepr(x) for x in built],'expression_kind':ir['problem_type'],'canonical_ast_hash':ast_hash}
                status='built';errors=[]
            except (ValueError,BuildError,KeyError,TypeError) as error:
                status='resource_limited' if 'LIMIT' in str(error) else 'unsupported' if 'UNKNOWN' in str(error) or 'UNSUPPORTED' in str(error) else 'failed';table=type('T',(),{'metadata':{}})();artifact={};errors=[error.as_dict() if isinstance(error,BuildError) else {'code':str(error)}]
            result_id=str(uuid.uuid4());db.execute("INSERT INTO math_sympy_build_results(id,problem_id,parse_result_id,input_ast_hash,source_revision,builder_version,sympy_version,status,symbol_table_json,artifact_json,warnings_json,errors_json,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",(result_id,ident,parse_row['id'],ast_hash,p['source_revision'],BUILDER_VERSION,SYMPY_VERSION,status,json.dumps(table.metadata),json.dumps(artifact),json.dumps([]),json.dumps(errors),utc_now()))
            return self._decode(dict(db.execute("SELECT * FROM math_sympy_build_results WHERE id=?",(result_id,)).fetchone()))

    def current_build(self,ident:str,user_id:str)->dict|None:
        with self._connect() as db:
            p,_=self._problem_input(db,ident,user_id);row=db.execute("SELECT * FROM math_sympy_build_results WHERE problem_id=? AND source_revision=? AND status='built' ORDER BY created_at DESC LIMIT 1",(ident,p['source_revision'])).fetchone();return self._decode(dict(row)) if row else None

    def analyze_problem(self,ident:str,user_id:str)->dict:
        with self._connect(immediate=True) as db:
            p,_=self._problem_input(db,ident,user_id);build=self.current_build(ident,user_id)
            if not build:raise ValueError('LATEST_BUILT_RESULT_REQUIRED')
            existing=db.execute("SELECT * FROM math_analysis_reports WHERE build_result_id=? AND input_ast_hash=? AND analysis_version=?",(build['id'],build['input_ast_hash'],ANALYSIS_VERSION)).fetchone()
            if existing:return self._decode(dict(existing))
            parse_row=db.execute("SELECT * FROM math_parse_results WHERE id=?",(build['parse_result_id'],)).fetchone();roots=[from_dict(item) for item in json.loads(parse_row['canonical_ast_json'])]
            features,classification=analyze(roots);constraints=extract_constraints(roots)
            ir=json.loads(parse_row['problem_ir_json']); constraint_table=SymbolTable(ir['variables'])
            for constraint in constraints:
                constraint['expression_srepr']=sympy_srepr(AstSympyBuilder(constraint_table).build(from_dict(constraint['expression_ast'])))
            report=AnalysisReport(ident,parse_row['id'],build['id'],'analyzed',features,classification,tuple(constraints),(),()).to_dict();report_id=str(uuid.uuid4())
            db.execute("INSERT INTO math_analysis_reports(id,problem_id,parse_result_id,build_result_id,input_ast_hash,source_revision,analysis_version,status,report_json,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)",(report_id,ident,parse_row['id'],build['id'],build['input_ast_hash'],p['source_revision'],ANALYSIS_VERSION,'analyzed',json.dumps(report),utc_now()))
            return self._decode(dict(db.execute("SELECT * FROM math_analysis_reports WHERE id=?",(report_id,)).fetchone()))

    def current_analysis(self,ident:str,user_id:str)->dict|None:
        with self._connect() as db:
            p,_=self._problem_input(db,ident,user_id);row=db.execute("SELECT * FROM math_analysis_reports WHERE problem_id=? AND source_revision=? AND status='analyzed' ORDER BY created_at DESC LIMIT 1",(ident,p['source_revision'])).fetchone();return self._decode(dict(row)) if row else None

    def evaluate_solve_eligibility(self,ident:str,user_id:str,expected_revision:int)->dict:
        with self._connect() as db:
            p,_=self._problem_input(db,ident,user_id);reasons=[]
            if p['revision']!=expected_revision:reasons.append('STALE_INPUT')
            parse=db.execute("SELECT * FROM math_parse_results WHERE problem_id=? AND input_source_revision=? AND status='parsed' ORDER BY created_at DESC LIMIT 1",(ident,p['source_revision'])).fetchone()
            build=db.execute("SELECT * FROM math_sympy_build_results WHERE problem_id=? AND source_revision=? AND status='built' ORDER BY created_at DESC LIMIT 1",(ident,p['source_revision'])).fetchone()
            analysis=db.execute("SELECT * FROM math_analysis_reports WHERE problem_id=? AND source_revision=? AND status='analyzed' ORDER BY created_at DESC LIMIT 1",(ident,p['source_revision'])).fetchone()
            if not parse:reasons.append('NO_CURRENT_PARSE_RESULT')
            if not build:reasons.append('NO_CURRENT_BUILD_RESULT')
            if not analysis:reasons.append('NO_CURRENT_ANALYSIS_REPORT')
            if build and parse and build['parse_result_id']!=parse['id']:reasons.append('STALE_INPUT')
            if analysis and build and analysis['build_result_id']!=build['id']:reasons.append('STALE_INPUT')
            return {'eligible':not reasons,'solver_id':None,'blocking_reasons':reasons,'warnings':[],'source_revision':p['source_revision'],'input_hash':build['input_ast_hash'] if build else '', 'problem':p,'parse':parse,'build':build,'analysis':analysis}

    def solve_problem(self,ident:str,user_id:str,expected_revision:int)->dict:
        gate=self.evaluate_solve_eligibility(ident,user_id,expected_revision)
        if not gate['eligible']:raise ValueError(json.dumps({k:v for k,v in gate.items() if k not in {'problem','parse','build','analysis'}}))
        with self._connect(immediate=True) as db:
            parse_row=gate['parse'];analysis=gate['analysis'];report=json.loads(analysis['report_json']);roots=[from_dict(x) for x in json.loads(parse_row['canonical_ast_json'])]
            if len(roots)!=1:raise ValueError('UNSUPPORTED_PROBLEM_CLASS')
            problem_ir=json.loads(parse_row['problem_ir_json'])
            primary=report['classification']['primary'];features=report['structural_features']
            solver_id={'numeric_expression_candidate':'numeric_exact','single_symbol_inequality_candidate':'linear_inequality'}.get(primary)
            if primary in {'single_symbol_equation_candidate','polynomial_equation_candidate'}:solver_id='quadratic_equation' if features.get('max_observed_integer_power')==2 else 'linear_equation'
            try:
                worker_request={'protocol_version':'1','solver_id':solver_id,'canonical_ast':json.loads(parse_row['canonical_ast_json']),'problem_ir':problem_ir,'analysis':{'structural_features':features},'constraints_snapshot':report['domain_constraints'],'limits':{}}
                execution=IsolatedSolverExecutor().execute(worker_request)
                if execution['status']=='timeout':raise SolverError('SOLVER_TIMEOUT',{})
                if execution['status']=='failed':raise SolverError(execution['errors'][0]['code'],{})
                candidate=execution['candidate_result'];status=candidate['status'];errors=execution.get('errors',[]);duration=execution['duration_ms'];solver=type('S',(),{'solver_id':solver_id,'solver_version':SOLVER_VERSION})()
            except SolverError as error:
                solver=type('S',(),{'solver_id':'none','solver_version':SOLVER_VERSION})();candidate={'status':'unsupported' if error.code in {'UNSUPPORTED_PROBLEM_CLASS','NO_SOLVER_MATCH'} else 'inconclusive','candidate_type':'none','values':[],'requires_checks':[]};status=candidate['status'];duration=0;errors=[error.as_dict()]
                execution={'execution_mode':'isolated_process','worker_exit_code':None,'timed_out':error.code=='SOLVER_TIMEOUT','termination_method':'terminate' if error.code=='SOLVER_TIMEOUT' else 'none'}
            candidate['original_domain_constraints']=report['domain_constraints'];candidate['requires_independent_verification']=True
            existing=db.execute("SELECT * FROM math_candidate_solution_results WHERE problem_id=? AND analysis_report_id=? AND input_hash=? AND solver_id=? AND solver_version=? AND sympy_version=?",(ident,analysis['id'],gate['input_hash'],solver.solver_id,solver.solver_version,SYMPY_VERSION)).fetchone()
            if existing:return self._decode(dict(existing))
            rid=str(uuid.uuid4());db.execute("INSERT INTO math_candidate_solution_results(id,problem_id,parse_result_id,build_result_id,analysis_report_id,input_source_revision,input_hash,solver_id,solver_version,sympy_version,status,problem_classification,candidate_result_json,constraints_snapshot_json,warnings_json,errors_json,duration_ms,created_at,execution_mode,worker_exit_code,timed_out,termination_method) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",(rid,ident,parse_row['id'],gate['build']['id'],analysis['id'],gate['source_revision'],gate['input_hash'],solver.solver_id,solver.solver_version,SYMPY_VERSION,status,report['classification']['primary'],json.dumps(candidate),json.dumps(report['domain_constraints']),json.dumps([]),json.dumps(errors),duration,utc_now(),execution['execution_mode'],execution['worker_exit_code'],int(execution['timed_out']),execution['termination_method']))
            return self._decode(dict(db.execute("SELECT * FROM math_candidate_solution_results WHERE id=?",(rid,)).fetchone()))

    def current_candidate_solution(self,ident:str,user_id:str)->dict|None:
        with self._connect() as db:
            p,_=self._problem_input(db,ident,user_id);row=db.execute("SELECT * FROM math_candidate_solution_results WHERE problem_id=? AND input_source_revision=? ORDER BY created_at DESC LIMIT 1",(ident,p['source_revision'])).fetchone();return self._decode(dict(row)) if row else None

    def evaluate_verification_eligibility(self,ident:str,user_id:str,expected_revision:int)->dict:
        with self._connect() as db:
            p,_=self._problem_input(db,ident,user_id);reasons=[]
            if p['revision']!=expected_revision:reasons.append('STALE_INPUT')
            candidate=db.execute("SELECT * FROM math_candidate_solution_results WHERE problem_id=? AND input_source_revision=? ORDER BY created_at DESC LIMIT 1",(ident,p['source_revision'])).fetchone()
            if not candidate:reasons.append('NO_CURRENT_CANDIDATE_RESULT')
            elif candidate['status']!='candidate':reasons.append('CANDIDATE_NOT_VERIFIABLE')
            parse=db.execute("SELECT * FROM math_parse_results WHERE id=?",(candidate['parse_result_id'],)).fetchone() if candidate else None
            build=db.execute("SELECT * FROM math_sympy_build_results WHERE id=?",(candidate['build_result_id'],)).fetchone() if candidate else None
            analysis=db.execute("SELECT * FROM math_analysis_reports WHERE id=?",(candidate['analysis_report_id'],)).fetchone() if candidate else None
            if not parse or parse['input_source_revision']!=p['source_revision']:reasons.append('NO_CURRENT_PARSE_RESULT')
            if not build or build['source_revision']!=p['source_revision']:reasons.append('NO_CURRENT_BUILD_RESULT')
            if not analysis or analysis['source_revision']!=p['source_revision']:reasons.append('NO_CURRENT_ANALYSIS_REPORT')
            if candidate and build and candidate['input_hash']!=build['input_ast_hash']:reasons.append('INPUT_HASH_MISMATCH')
            if candidate and parse and candidate['parse_result_id']!=parse['id']:reasons.append('STALE_INPUT')
            if candidate and build and candidate['build_result_id']!=build['id']:reasons.append('STALE_INPUT')
            if candidate and analysis and candidate['analysis_report_id']!=analysis['id']:reasons.append('STALE_INPUT')
            return {'eligible':not reasons,'blocking_reasons':reasons,'source_revision':p['source_revision'],'problem':p,'candidate':candidate,'parse':parse,'build':build,'analysis':analysis}

    def verify_problem(self,ident:str,user_id:str,expected_revision:int)->dict:
        gate=self.evaluate_verification_eligibility(ident,user_id,expected_revision)
        if not gate['eligible']:raise ValueError(json.dumps({k:v for k,v in gate.items() if k not in {'problem','candidate','parse','build','analysis'}}))
        with self._connect(immediate=True) as db:
            candidate,parse_row,build,analysis=gate['candidate'],gate['parse'],gate['build'],gate['analysis'];hash_value=candidate['input_hash']
            existing=db.execute("SELECT * FROM math_verification_reports WHERE candidate_solution_result_id=? AND input_hash=? AND verifier_version=?",(candidate['id'],hash_value,VERIFIER_VERSION)).fetchone()
            if existing:return self._decode(dict(existing))
            request={'protocol_version':'1','canonical_ast':json.loads(parse_row['canonical_ast_json']),'problem_ir':json.loads(parse_row['problem_ir_json']),'analysis':json.loads(analysis['report_json']),'constraints_snapshot':json.loads(candidate['constraints_snapshot_json']),'candidate':json.loads(candidate['candidate_result_json'])}
            execution=IsolatedVerifierExecutor().execute(request)
            if execution.get('status')=='timeout':result={'status':'timeout','checks':[],'verification_plan':{},'verified_result':None,'warnings':[],'errors':[{'code':'VERIFIER_TIMEOUT'}]}
            else:result=execution.get('result',{'status':'failed','checks':[],'verification_plan':{},'verified_result':None,'warnings':[],'errors':execution.get('errors',[])})
            if result.get('status')=='checks_passed':
                result['status']='verified';result['verified_result']={'status':'verified','is_verified':True}
            if not validate_report(result, json.loads(candidate['candidate_result_json']).get('candidate_type')):
                result={'status':'failed','checks':result.get('checks',[]),'verification_plan':result.get('verification_plan',{}),'verified_result':None,'warnings':[],'errors':[{'code':'INVALID_VERIFICATION_REPORT'}]}
            # Revision is checked again under the parent transaction before persisting a verdict.
            current=db.execute("SELECT revision,source_revision FROM math_problems WHERE id=?",(ident,)).fetchone()
            if current['revision']!=expected_revision or current['source_revision']!=gate['source_revision']:result={'status':'inconclusive','checks':[],'verification_plan':{},'verified_result':None,'warnings':[],'errors':[{'code':'VERIFICATION_INPUT_CHANGED'}]}
            rid=str(uuid.uuid4());db.execute("INSERT INTO math_verification_reports(id,problem_id,candidate_solution_result_id,parse_result_id,build_result_id,analysis_report_id,input_source_revision,input_hash,verifier_version,status,verification_plan_json,checks_json,verified_result_json,report_json,warnings_json,errors_json,duration_ms,execution_mode,worker_exit_code,timed_out,termination_method,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",(rid,ident,candidate['id'],parse_row['id'],build['id'],analysis['id'],gate['source_revision'],hash_value,VERIFIER_VERSION,result['status'],json.dumps(result['verification_plan']),json.dumps(result['checks']),json.dumps(result['verified_result']),json.dumps(result),json.dumps(result.get('warnings',[])),json.dumps(result.get('errors',[])),execution.get('duration_ms',0),execution.get('execution_mode','isolated_process'),execution.get('worker_exit_code'),int(execution.get('timed_out',False)),execution.get('termination_method','none'),utc_now()))
            return self._decode(dict(db.execute("SELECT * FROM math_verification_reports WHERE id=?",(rid,)).fetchone()))

    def current_verification(self,ident:str,user_id:str)->dict|None:
        with self._connect() as db:
            p,_=self._problem_input(db,ident,user_id);row=db.execute("SELECT * FROM math_verification_reports WHERE problem_id=? AND input_source_revision=? ORDER BY created_at DESC LIMIT 1",(ident,p['source_revision'])).fetchone();return self._decode(dict(row)) if row else None

    def evaluate_explanation_eligibility(self,ident:str,user_id:str,expected_revision:int,teaching_profile:dict)->dict:
        with self._connect() as db:
            p,_=self._problem_input(db,ident,user_id);reasons=[]
            # ``revision`` is the optimistic-lock token supplied by the
            # client.  ``source_revision`` is the immutable mathematical
            # input revision and may legitimately lag after a metadata-only
            # problem edit.
            if p['revision']!=expected_revision:reasons.append('EXPLANATION_INPUT_CHANGED')
            if p['requires_review']:reasons.append('BLOCKING_REVIEW_REQUIRED')
            verification=db.execute("SELECT * FROM math_verification_reports WHERE problem_id=? AND input_source_revision=? ORDER BY created_at DESC LIMIT 1",(ident,p['source_revision'])).fetchone()
            if not verification:reasons.append('NO_CURRENT_VERIFIED_REPORT')
            else:
                verified_result=json.loads(verification['verified_result_json'] or 'null')
                if verification['status']!='verified' or not isinstance(verified_result,dict) or not verified_result.get('is_verified',False):reasons.append('VERIFICATION_NOT_VERIFIED')
            candidate=db.execute("SELECT * FROM math_candidate_solution_results WHERE id=?",(verification['candidate_solution_result_id'],)).fetchone() if verification else None
            parse=db.execute("SELECT * FROM math_parse_results WHERE id=?",(verification['parse_result_id'],)).fetchone() if verification else None
            build=db.execute("SELECT * FROM math_sympy_build_results WHERE id=?",(verification['build_result_id'],)).fetchone() if verification else None
            analysis=db.execute("SELECT * FROM math_analysis_reports WHERE id=?",(verification['analysis_report_id'],)).fetchone() if verification else None
            for item,code in ((candidate,'NO_CURRENT_CANDIDATE_RESULT'),(parse,'NO_CURRENT_PARSE_RESULT'),(build,'NO_CURRENT_BUILD_RESULT'),(analysis,'NO_CURRENT_ANALYSIS_REPORT')):
                if not item:reasons.append(code)
            if parse and (parse['status']!='parsed' or parse['input_source_revision']!=p['source_revision']):reasons.append('STALE_VERIFICATION_REPORT')
            if build and (build['status']!='built' or build['source_revision']!=p['source_revision']):reasons.append('STALE_VERIFICATION_REPORT')
            if analysis and (analysis['status']!='analyzed' or analysis['source_revision']!=p['source_revision']):reasons.append('STALE_VERIFICATION_REPORT')
            if candidate and (candidate['status']!='candidate' or candidate['input_source_revision']!=p['source_revision']):reasons.append('STALE_VERIFICATION_REPORT')
            if verification and candidate and verification['candidate_solution_result_id']!=candidate['id']:reasons.append('EXPLANATION_INPUT_CHANGED')
            if verification and candidate and verification['input_hash']!=candidate['input_hash']:reasons.append('EXPLANATION_INPUT_CHANGED')
            if candidate and build and candidate['input_hash']!=build['input_ast_hash']:reasons.append('EXPLANATION_INPUT_CHANGED')
            if build and parse and build['parse_result_id']!=parse['id']:reasons.append('STALE_VERIFICATION_REPORT')
            if analysis and build and (analysis['build_result_id']!=build['id'] or analysis['input_ast_hash']!=build['input_ast_hash']):reasons.append('STALE_VERIFICATION_REPORT')
            if candidate and parse and candidate['parse_result_id']!=parse['id']:reasons.append('STALE_VERIFICATION_REPORT')
            if candidate and build and candidate['build_result_id']!=build['id']:reasons.append('STALE_VERIFICATION_REPORT')
            if candidate and analysis and candidate['analysis_report_id']!=analysis['id']:reasons.append('STALE_VERIFICATION_REPORT')
            candidate_type=json.loads(candidate['candidate_result_json']).get('candidate_type') if candidate else None
            allowed={'exact_value','unique_candidate','no_solution_candidate','identity_candidate','two_real_candidates','one_repeated_real_candidate','interval_candidate'}
            if candidate_type not in allowed:reasons.append('UNSUPPORTED_EXPLANATION_TYPE')
            if verification:
                report=json.loads(verification['report_json'] or '{}');checks=json.loads(verification['checks_json'] or '[]');required=set(required_checks(candidate_type))
                if set(report.get('verification_plan',{}).get('required_checks',[]))!=required:reasons.append('REQUIRED_CHECKS_MISMATCH')
                if {c.get('type') for c in checks if c.get('required')}!=required or any(c.get('status')!='passed' for c in checks if c.get('required')):reasons.append('REQUIRED_CHECKS_NOT_PASSED')
                if report.get('blocking_reasons') or report.get('blocking_review_reasons'):reasons.append('BLOCKING_REVIEW_REQUIRED')
            return {'eligible':not reasons,'blocking_reasons':sorted(set(reasons)),'source_revision':p['source_revision'],'problem':p,'verification':verification,'candidate':candidate,'parse':parse,'build':build,'analysis':analysis,'teaching_profile':teaching_profile}

    def prepare_explanation(self,ident:str,user_id:str,expected_revision:int,teaching_profile:dict)->dict:
        gate=self.evaluate_explanation_eligibility(ident,user_id,expected_revision,teaching_profile)
        if not gate['eligible']:raise ValueError(json.dumps({k:v for k,v in gate.items() if k not in {'problem','verification','candidate','parse','build','analysis'}}))
        candidate=json.loads(gate['candidate']['candidate_result_json']);ir=json.loads(gate['parse']['problem_ir_json']);normalized=json.loads(gate['parse']['normalized_input'] or '[]')
        canonical=json.loads(gate['parse']['canonical_ast_json'])
        if len(canonical) != 1:
            raise ValueError('EXPLANATION_CANONICAL_ROOT_REQUIRED')
        display=normalized[0].get('original','') if normalized else ''
        values=candidate.get('values',[]);answer=''
        def display_value(item):
            data=item.get('value',{});
            if data.get('kind')=='integer':return str(data['value'])
            if data.get('kind')=='rational':return str(data['numerator']) if data['denominator']==1 else f"\\frac{{{data['numerator']}}}{{{data['denominator']}}}"
            return ''
        names=[v['name'] for v in ir.get('variables',[])]
        if candidate.get('candidate_type')=='exact_value':answer=display_value(values[0]) if values else ''
        elif candidate.get('candidate_type') in {'unique_candidate','one_repeated_real_candidate'}:answer=f"{names[0]}={display_value(values[0])}" if names and values else ''
        elif candidate.get('candidate_type')=='two_real_candidates':answer=f"{names[0]}={display_value(values[0])} 或 {names[0]}={display_value(values[1])}" if names and len(values)>1 else ''
        elif candidate.get('candidate_type')=='no_solution_candidate':answer='无实数解'
        elif candidate.get('candidate_type')=='identity_candidate':answer='恒等成立'
        elif candidate.get('candidate_type')=='interval_candidate':
            interval=candidate.get('interval') or {};name=names[0] if names else 'x'
            lower,upper=interval.get('lower'),interval.get('upper')
            if lower:
                bound=display_value(lower) if isinstance(lower,dict) and 'value' in lower else lower.get('display_latex','')
                answer=f"{name} {'≥' if lower.get('inclusive') else '>'} {bound}"
            elif upper:
                bound=display_value(upper) if isinstance(upper,dict) and 'value' in upper else upper.get('display_latex','')
                answer=f"{name} {'≤' if upper.get('inclusive') else '<'} {bound}"
            else: answer='恒真或恒假需由验证报告说明'
        passed=[c['type'] for c in json.loads(gate['verification']['checks_json'] or '[]') if c.get('status')=='passed']
        deterministic = candidate.get('deterministic_trace')
        if not isinstance(deterministic, dict):
            raise ValueError('TRACE_MISSING')
        deterministic = validate_trace_artifact(deterministic, EXPLANATION_TRACE_VERSION, EXPLANATION_RENDERER_VERSION)
        existing_binding = deterministic.get('binding')
        if existing_binding is not None:
            expected_binding = {
                'problem_id': ident,
                'source_revision': gate['source_revision'],
                'candidate_solution_result_id': gate['candidate']['id'],
                'verification_report_id': gate['verification']['id'],
                'trace_version': EXPLANATION_TRACE_VERSION,
                'renderer_version': EXPLANATION_RENDERER_VERSION,
            }
            if any(existing_binding.get(key) != value for key, value in expected_binding.items()):
                raise ValueError('TRACE_INPUT_CHANGED')
        required=list(required_checks(candidate.get('candidate_type')))
        def public_ast(value):
            if isinstance(value, dict):
                return {key: public_ast(item) for key, item in value.items() if key not in {'source_formula_id', 'source_span'}}
            if isinstance(value, list):
                return [public_ast(item) for item in value]
            return value
        input_data={'schema_version':EXPLANATION_SCHEMA_VERSION,'prompt_version':PROMPT_VERSION,'trace_version':EXPLANATION_TRACE_VERSION,'renderer_version':EXPLANATION_RENDERER_VERSION,'problem_id':ident,'source_revision':gate['source_revision'],'problem_type':candidate.get('candidate_type'),'knowledge_point_ids':[candidate.get('candidate_type','math')],'confirmed_problem':{'display_latex':display,'structured_ast':public_ast(canonical)},'variables':ir.get('variables',[]),'verified_result':{'status':'verified','is_verified':True,'candidate_type':candidate.get('candidate_type'),'values':values},'deterministic_trace':deterministic,'verification_summary':{'status':'verified','required_checks':required,'passed_checks':sorted(set(passed))},'teaching_profile':teaching_profile,'answer_latex':answer}
        input_hash = request_hash({**input_data,'deterministic_trace':{**deterministic,'binding':{**deterministic.get('binding',{}),'input_hash':''}}})
        if existing_binding is not None and existing_binding.get('input_hash') not in {None, '', input_hash}:
            raise ValueError('TRACE_INPUT_CHANGED')
        input_data['deterministic_trace']=attach_trace_binding(deterministic,problem_id=ident,source_revision=gate['source_revision'],candidate_solution_result_id=gate['candidate']['id'],verification_report_id=gate['verification']['id'],input_hash=input_hash)
        input_data['input_hash'] = input_hash
        return {'gate':gate,'input':input_data,'input_hash':input_hash,'request_id':input_hash,'answer_latex':answer}

    def persist_explanation(self,prepared:dict,provider_name:str,model_name:str,model_version:str,raw:dict,validated:dict|None,status:str,errors:list,metrics:dict)->dict:
        gate=prepared['gate'];input_data=prepared['input'];now=utc_now();profile_hash=request_hash(input_data['teaching_profile'])
        if status == 'validated':
            try:
                # Re-validate the untrusted provider payload at the storage
                # boundary.  ``validated`` may already be the server-owned
                # artifact returned by the route and therefore contains
                # fields that are intentionally not accepted as model input.
                validated = validate_explanation(raw, input_data)
                validated['final_answer_latex'] = prepared['answer_latex']
                if isinstance(validated.get('answer_summary'), dict):
                    validated['answer_summary']['display_latex'] = prepared['answer_latex']
            except (TypeError, ValueError) as error:
                status = 'rejected'; validated = None; errors = [{'code': str(error)}]
        with self._connect(immediate=True) as db:
            current=db.execute("SELECT revision,source_revision FROM math_problems WHERE id=?",(gate['problem']['id'],)).fetchone()
            current_verification=db.execute("SELECT id,input_hash,candidate_solution_result_id,status,verified_result_json FROM math_verification_reports WHERE problem_id=? AND input_source_revision=? ORDER BY created_at DESC LIMIT 1",(gate['problem']['id'],gate['source_revision'])).fetchone()
            current_candidate=db.execute("SELECT id,input_hash FROM math_candidate_solution_results WHERE id=?",(gate['candidate']['id'],)).fetchone()
            current_verified = json.loads(current_verification['verified_result_json'] or 'null') if current_verification else None
            if (not current or current['revision']!=gate['problem']['revision'] or current['source_revision']!=gate['source_revision'] or not current_verification or current_verification['id']!=gate['verification']['id'] or current_verification['status']!='verified' or not isinstance(current_verified,dict) or not current_verified.get('is_verified',False) or current_verification['candidate_solution_result_id']!=gate['candidate']['id'] or current_verification['input_hash']!=gate['verification']['input_hash'] or not current_candidate or current_candidate['input_hash']!=gate['candidate']['input_hash']):
                status='stale';errors=[{'code':'EXPLANATION_INPUT_CHANGED'}];validated=None
            existing=db.execute("SELECT * FROM math_explanations WHERE verification_report_id=? AND input_hash=? AND provider=? AND model_name=? AND model_version=? AND prompt_version=? AND schema_version=? AND teaching_profile_hash=? AND trace_version=? AND renderer_version=?",(gate['verification']['id'],prepared['input_hash'],provider_name,model_name,model_version,PROMPT_VERSION,EXPLANATION_SCHEMA_VERSION,profile_hash,EXPLANATION_TRACE_VERSION,EXPLANATION_RENDERER_VERSION)).fetchone()
            if existing:
                cached = self._decode(dict(existing))
                if status == 'stale':
                    cached['status'] = 'stale'; cached['validated_explanation_json'] = None; cached['errors_json'] = errors
                    return cached
                cached['cache_hit'] = 1
                return cached
            prompt = prompt_metadata()
            quality = validated.get('quality', {}) if isinstance(validated, dict) else {}
            error_code = (errors[0].get('code') if errors and isinstance(errors[0], dict) else None)
            columns = "id,problem_id,verification_report_id,candidate_solution_result_id,user_id,request_id,input_source_revision,input_hash,provider,model_name,model_version,prompt_id,prompt_version,prompt_content_hash,prompt_created_at,schema_version,trace_version,renderer_version,teaching_profile_hash,status,explanation_input_json,raw_model_response_json,validated_explanation_json,quality_json,warnings_json,errors_json,error_code,input_tokens,output_tokens,cached_tokens,provider_request_id,actual_model_name,pricing_version,estimated_cost,duration_ms,attempts,cache_hit,created_at"
            explanation_id = str(uuid.uuid4())
            values = (explanation_id,gate['problem']['id'],gate['verification']['id'],gate['candidate']['id'],gate['problem']['user_id'],prepared['request_id'],gate['source_revision'],prepared['input_hash'],provider_name,model_name,model_version,PROMPT_ID,PROMPT_VERSION,prompt['content_hash'],prompt['created_at'],EXPLANATION_SCHEMA_VERSION,EXPLANATION_TRACE_VERSION,EXPLANATION_RENDERER_VERSION,profile_hash,status,json.dumps(input_data,ensure_ascii=False),json.dumps(raw,ensure_ascii=False),json.dumps(validated,ensure_ascii=False) if validated else None,json.dumps(quality,ensure_ascii=False),json.dumps([]),json.dumps(errors,ensure_ascii=False),error_code,metrics.get('input_tokens'),metrics.get('output_tokens'),metrics.get('cached_tokens'),metrics.get('provider_request_id'),metrics.get('actual_model_name'),metrics.get('pricing_version'),metrics.get('estimated_cost'),metrics.get('duration_ms',0),metrics.get('attempts',1),int(metrics.get('cache_hit',False)),now)
            db.execute(f"INSERT INTO math_explanations({columns}) VALUES({','.join('?' for _ in values)})", values)
            return self._decode(dict(db.execute("SELECT * FROM math_explanations WHERE id=?",(explanation_id,)).fetchone()))

    def current_explanation(self,ident:str,user_id:str)->dict|None:
        with self._connect() as db:
            p,_=self._problem_input(db,ident,user_id)
            verification=db.execute("SELECT id, status, verified_result_json FROM math_verification_reports WHERE problem_id=? AND input_source_revision=? ORDER BY created_at DESC LIMIT 1",(ident,p['source_revision'])).fetchone()
            if not verification or verification['status']!='verified': return None
            verified=json.loads(verification['verified_result_json'] or 'null')
            if not isinstance(verified,dict) or not verified.get('is_verified',False): return None
            row=db.execute("SELECT * FROM math_explanations WHERE problem_id=? AND input_source_revision=? AND verification_report_id=? AND status='validated' AND schema_version=? AND trace_version=? AND renderer_version=? ORDER BY created_at DESC LIMIT 1",(ident,p['source_revision'],verification['id'],EXPLANATION_SCHEMA_VERSION,EXPLANATION_TRACE_VERSION,EXPLANATION_RENDERER_VERSION)).fetchone()
            return self._decode(dict(row)) if row else None

    def _safe_delete_paths(self, paths: set[str]) -> int:
        """Remove only files contained by the configured workbook root."""
        root = self.storage_root.resolve()
        deleted = 0
        for raw in paths:
            if not raw:
                continue
            try:
                path = Path(raw).expanduser().resolve(strict=False)
                if root not in path.parents or not path.is_file():
                    continue
                path.unlink()
                deleted += 1
            except (OSError, RuntimeError):
                # A failed cleanup is observable through orphan_files(); it
                # must never turn a committed database deletion into a retry.
                continue
        return deleted

    @staticmethod
    def _row_ids(db: sqlite3.Connection, table: str, column: str, values: list[str]) -> list[str]:
        if not values:
            return []
        placeholders = ",".join("?" for _ in values)
        return [str(row[0]) for row in db.execute(f"SELECT id FROM {table} WHERE {column} IN ({placeholders})", values)]

    def _delete_problem_rows(self, db: sqlite3.Connection, problem_id: str, paths: set[str]) -> dict[str, int]:
        """Delete one problem graph while foreign-key checks remain enabled."""
        problem = db.execute("SELECT * FROM math_problems WHERE id=?", (problem_id,)).fetchone()
        if not problem:
            return {}
        paths.add(problem["problem_crop_path"])
        parse_ids = self._row_ids(db, "math_parse_results", "problem_id", [problem_id])
        build_ids = self._row_ids(db, "math_sympy_build_results", "problem_id", [problem_id])
        analysis_ids = self._row_ids(db, "math_analysis_reports", "problem_id", [problem_id])
        candidate_ids = self._row_ids(db, "math_candidate_solution_results", "problem_id", [problem_id])
        verification_ids = self._row_ids(db, "math_verification_reports", "problem_id", [problem_id])
        solve_ids = self._row_ids(db, "math_solve_results", "problem_id", [problem_id])
        child_ids = parse_ids + build_ids + analysis_ids + candidate_ids + verification_ids + solve_ids + [problem_id]
        if child_ids:
            marks = ",".join("?" for _ in child_ids)
            db.execute(f"DELETE FROM math_processing_jobs WHERE resource_id IN ({marks})", child_ids)
            idempotency_deleted = db.execute(f"DELETE FROM math_idempotency_records WHERE resource_id IN ({marks})", child_ids).rowcount
        else:
            idempotency_deleted = 0
        counts: dict[str, int] = {"math_idempotency_records": idempotency_deleted}
        for table, column, ids in (
            ("math_explanations", "verification_report_id", verification_ids),
            ("math_verification_reports", "id", verification_ids),
            ("math_candidate_solution_results", "id", candidate_ids),
            ("math_analysis_reports", "id", analysis_ids),
            ("math_sympy_build_results", "id", build_ids),
            ("math_solve_results", "id", solve_ids),
            ("math_parse_results", "id", parse_ids),
        ):
            if not ids:
                continue
            marks = ",".join("?" for _ in ids)
            cursor = db.execute(f"DELETE FROM {table} WHERE {column} IN ({marks})", ids)
            counts[table] = cursor.rowcount
        cursor = db.execute("DELETE FROM math_problem_sources WHERE problem_id=?", (problem_id,)); counts["math_problem_sources"] = cursor.rowcount
        cursor = db.execute("DELETE FROM math_problems WHERE id=?", (problem_id,)); counts["math_problems"] = cursor.rowcount
        return counts

    def delete_problem(self, problem_id: str, user_id: str) -> dict[str, Any]:
        """Controlled, owned problem deletion.  No single explanation delete API exists."""
        self._reject_anonymous(user_id)
        paths: set[str] = set()
        with self._connect(immediate=True) as db:
            problem = db.execute("SELECT * FROM math_problems WHERE id=? AND user_id=?", (problem_id, user_id)).fetchone()
            if not problem:
                raise KeyError(problem_id)
            counts = self._delete_problem_rows(db, problem_id, paths)
        counts["files"] = self._safe_delete_paths(paths)
        counts["problem_id"] = problem_id
        return counts

    def delete_import(self, import_id: str, user_id: str) -> dict[str, Any]:
        """Delete an owned import and every page/formula/problem artifact below it."""
        self._reject_anonymous(user_id)
        paths: set[str] = set()
        total: dict[str, int] = {}
        with self._connect(immediate=True) as db:
            imported = db.execute("SELECT * FROM math_imports WHERE id=? AND user_id=?", (import_id, user_id)).fetchone()
            if not imported:
                raise KeyError(import_id)
            paths.add(imported["source_file_path"])
            page_ids = [str(row[0]) for row in db.execute("SELECT id FROM math_pages WHERE import_id=?", (import_id,))]
            problem_ids = [str(row[0]) for row in db.execute("SELECT id FROM math_problems WHERE import_id=?", (import_id,))]
            region_ids = self._row_ids(db, "math_regions", "page_id", page_ids)
            block_ids = self._row_ids(db, "math_source_blocks", "page_id", page_ids)
            formula_ids = self._row_ids(db, "math_formula_candidates", "page_id", page_ids)
            if page_ids:
                marks = ",".join("?" for _ in page_ids)
                paths.update(value for (value,) in db.execute(f"SELECT raw_json_path FROM math_raw_parse_results WHERE page_id IN ({marks})", page_ids) if value)
            for table, column, ids, path_columns in (
                ("math_pages", "id", page_ids, ("original_image_path", "normalized_image_path", "print_view_path", "handwriting_view_path", "handwriting_mask_path")),
                ("math_regions", "id", region_ids, ("crop_path",)),
                ("math_source_blocks", "id", block_ids, ("crop_path",)),
                ("math_formula_candidates", "id", formula_ids, ("crop_path",)),
            ):
                if ids:
                    marks = ",".join("?" for _ in ids)
                    for row in db.execute(f"SELECT {','.join(path_columns)} FROM {table} WHERE {column} IN ({marks})", ids):
                        paths.update(value for value in row if value)
            for problem_id in problem_ids:
                for key, value in self._delete_problem_rows(db, problem_id, paths).items():
                    if isinstance(value, int): total[key] = total.get(key, 0) + value
            if formula_ids:
                marks = ",".join("?" for _ in formula_ids)
                total["math_formula_revisions"] = db.execute(f"DELETE FROM math_formula_revisions WHERE formula_id IN ({marks})", formula_ids).rowcount
                total["math_formula_candidates"] = db.execute(f"DELETE FROM math_formula_candidates WHERE id IN ({marks})", formula_ids).rowcount
            if block_ids:
                marks = ",".join("?" for _ in block_ids); total["math_source_blocks"] = db.execute(f"DELETE FROM math_source_blocks WHERE id IN ({marks})", block_ids).rowcount
            if region_ids:
                marks = ",".join("?" for _ in region_ids); total["math_regions"] = db.execute(f"DELETE FROM math_regions WHERE id IN ({marks})", region_ids).rowcount
            if page_ids:
                marks = ",".join("?" for _ in page_ids)
                total["math_raw_parse_results"] = db.execute(f"DELETE FROM math_raw_parse_results WHERE page_id IN ({marks})", page_ids).rowcount
                total["math_pages"] = db.execute(f"DELETE FROM math_pages WHERE id IN ({marks})", page_ids).rowcount
                db.execute(f"DELETE FROM math_processing_jobs WHERE resource_id IN ({marks})", page_ids)
            resource_ids = [import_id] + page_ids + region_ids + block_ids + formula_ids
            if resource_ids:
                marks = ",".join("?" for _ in resource_ids)
                total["math_processing_jobs"] = total.get("math_processing_jobs", 0) + db.execute(f"DELETE FROM math_processing_jobs WHERE resource_id IN ({marks})", resource_ids).rowcount
                total["math_idempotency_records"] = total.get("math_idempotency_records", 0) + db.execute(f"DELETE FROM math_idempotency_records WHERE resource_id IN ({marks})", resource_ids).rowcount
            total["math_imports"] = db.execute("DELETE FROM math_imports WHERE id=?", (import_id,)).rowcount
        total["files"] = self._safe_delete_paths(paths)
        total["import_id"] = import_id
        return total

    def delete_user_data(self, user_id: str) -> dict[str, Any]:
        """Privacy purge for all workbook records owned by a user."""
        self._reject_anonymous(user_id)
        paths: set[str] = set(); total: dict[str, int] = {}
        with self._connect(immediate=True) as db:
            import_ids = [str(row[0]) for row in db.execute("SELECT id FROM math_imports WHERE user_id=?", (user_id,))]
            problem_ids = [str(row[0]) for row in db.execute("SELECT id FROM math_problems WHERE user_id=?", (user_id,))]
            page_ids: list[str] = []; region_ids: list[str] = []; block_ids: list[str] = []; formula_ids: list[str] = []
            for import_id in import_ids:
                row = db.execute("SELECT source_file_path FROM math_imports WHERE id=?", (import_id,)).fetchone()
                if row: paths.add(row[0])
                page_ids.extend(str(x[0]) for x in db.execute("SELECT id FROM math_pages WHERE import_id=?", (import_id,)))
                for problem_id in [str(x[0]) for x in db.execute("SELECT id FROM math_problems WHERE import_id=?", (import_id,))]:
                    if problem_id not in problem_ids: problem_ids.append(problem_id)
            if page_ids:
                marks = ",".join("?" for _ in page_ids)
                for row in db.execute(f"SELECT original_image_path,normalized_image_path,print_view_path,handwriting_view_path,handwriting_mask_path FROM math_pages WHERE id IN ({marks})", page_ids): paths.update(value for value in row if value)
                for value, in db.execute(f"SELECT raw_json_path FROM math_raw_parse_results WHERE page_id IN ({marks})", page_ids):
                    if value: paths.add(value)
                region_ids = self._row_ids(db, "math_regions", "page_id", page_ids)
                block_ids = self._row_ids(db, "math_source_blocks", "page_id", page_ids)
                formula_ids = self._row_ids(db, "math_formula_candidates", "page_id", page_ids)
            if region_ids:
                marks = ",".join("?" for _ in region_ids)
                for value, in db.execute(f"SELECT crop_path FROM math_regions WHERE id IN ({marks})", region_ids):
                    if value: paths.add(value)
            if block_ids:
                marks = ",".join("?" for _ in block_ids)
                for value, in db.execute(f"SELECT crop_path FROM math_source_blocks WHERE id IN ({marks})", block_ids):
                    if value: paths.add(value)
            if formula_ids:
                marks = ",".join("?" for _ in formula_ids)
                for value, in db.execute(f"SELECT crop_path FROM math_formula_candidates WHERE id IN ({marks})", formula_ids):
                    if value: paths.add(value)
            resource_ids = import_ids + page_ids + region_ids + block_ids + formula_ids + problem_ids
            if resource_ids:
                marks = ",".join("?" for _ in resource_ids)
                total["math_processing_jobs"] = db.execute(f"DELETE FROM math_processing_jobs WHERE resource_id IN ({marks})", resource_ids).rowcount
            for problem_id in problem_ids:
                for key, value in self._delete_problem_rows(db, problem_id, paths).items():
                    if isinstance(value, int): total[key] = total.get(key, 0) + value
            if formula_ids:
                marks = ",".join("?" for _ in formula_ids)
                total["math_formula_revisions"] = db.execute(f"DELETE FROM math_formula_revisions WHERE formula_id IN ({marks})", formula_ids).rowcount
                total["math_formula_candidates"] = db.execute(f"DELETE FROM math_formula_candidates WHERE id IN ({marks})", formula_ids).rowcount
            if block_ids:
                marks = ",".join("?" for _ in block_ids); total["math_source_blocks"] = db.execute(f"DELETE FROM math_source_blocks WHERE id IN ({marks})", block_ids).rowcount
            if region_ids:
                marks = ",".join("?" for _ in region_ids); total["math_regions"] = db.execute(f"DELETE FROM math_regions WHERE id IN ({marks})", region_ids).rowcount
            if import_ids:
                marks = ",".join("?" for _ in import_ids)
                if page_ids:
                    pm = ",".join("?" for _ in page_ids); db.execute(f"DELETE FROM math_raw_parse_results WHERE page_id IN ({pm})", page_ids); db.execute(f"DELETE FROM math_pages WHERE id IN ({pm})", page_ids)
                total["math_imports"] = db.execute(f"DELETE FROM math_imports WHERE id IN ({marks})", import_ids).rowcount
            total["math_explanations"] = total.get("math_explanations", 0) + db.execute("DELETE FROM math_explanations WHERE user_id=?", (user_id,)).rowcount
            total["math_idempotency_records"] = db.execute("DELETE FROM math_idempotency_records WHERE user_id=?", (user_id,)).rowcount
        total["files"] = self._safe_delete_paths(paths)
        total["user_id"] = user_id
        return total

    def get_formula(self,i:str,user_id: str | None = None)->dict|None:
        if user_id is None:
            return self._one('math_formula_candidates',i)
        self._reject_anonymous(user_id)
        with self._connect() as db:
            row = db.execute(self._owned_formula_query(), (i, user_id)).fetchone()
            return self._decode(dict(row)) if row else None

    def get_region(self,i:str,user_id: str | None = None)->dict|None:
        if user_id is None:
            return self._one('math_regions',i)
        self._reject_anonymous(user_id)
        with self._connect() as db:
            row = db.execute(self._owned_region_query(), (i, user_id)).fetchone()
            return self._decode(dict(row)) if row else None
    def _one(self,t:str,i:str)->dict|None:
        with self._connect() as db:
            r=db.execute(f"SELECT * FROM {t} WHERE id=?",(i,)).fetchone();return self._decode(dict(r)) if r else None
    def get_import(self,i:str,user_id: str | None = None)->dict|None:
        with self._connect() as db:
            query = "SELECT * FROM math_imports WHERE id=?" if user_id is None else "SELECT * FROM math_imports WHERE id=? AND user_id=?"
            params = (i,) if user_id is None else (i, user_id)
            row=db.execute(query,params).fetchone()
            if not row:return None
            out=self._decode(dict(row));out['pages']=[self.get_page(x['id'], user_id) for x in db.execute("SELECT id FROM math_pages WHERE import_id=? ORDER BY page_index",(i,))];return out
    def get_page(self,i:str,user_id: str | None = None)->dict|None:
        with self._connect() as db:
            query = "SELECT * FROM math_pages WHERE id=?" if user_id is None else self._owned_page_query()
            params = (i,) if user_id is None else (i, user_id)
            r=db.execute(query,params).fetchone()
            if not r:return None
            out=self._decode(dict(r))
            for name,table in [('raw_parse_results','math_raw_parse_results'),('regions','math_regions'),('source_blocks','math_source_blocks'),('formulas','math_formula_candidates')]:out[name]=[self._decode(dict(x)) for x in db.execute(f"SELECT * FROM {table} WHERE page_id=? ORDER BY " + ('reading_order' if name!='raw_parse_results' else 'created_at'),(i,))]
            return out
    def orphan_files(self)->list[str]:
        with self._connect() as db: referenced={r[0] for r in db.execute("SELECT source_file_path FROM math_imports UNION SELECT original_image_path FROM math_pages UNION SELECT raw_json_path FROM math_raw_parse_results") if r[0]}
        return [str(p) for p in self.storage_root.rglob('*') if p.is_file() and str(p) not in referenced and p.suffix!='.tmp']
    @staticmethod
    def _decode(row:dict)->dict:
        for k in ('bbox','polygon','review_reasons','transform_metadata','raw_summary','variable_domains_json','response_body','report_json','artifact_json','symbol_table_json','warnings_json','errors_json','tokens_json','raw_ast_json','canonical_ast_json','normalized_input','problem_ir_json','ast_json','candidate_result_json','constraints_snapshot_json','verification_plan_json','checks_json','verified_result_json','explanation_input_json','raw_model_response_json','validated_explanation_json','quality_json'):
            if isinstance(row.get(k),str):
                try:row[k]=json.loads(row[k])
                except json.JSONDecodeError:pass
        for k in ('requires_review','occluded_by_handwriting','parseable'):
            if row.get(k) is not None:row[k]=bool(row[k])
        return row
