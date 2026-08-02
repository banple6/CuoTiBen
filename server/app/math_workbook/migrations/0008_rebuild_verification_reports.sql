PRAGMA foreign_keys=OFF;
ALTER TABLE math_verification_reports RENAME TO math_verification_reports_legacy;
CREATE TABLE math_verification_reports (id TEXT PRIMARY KEY, problem_id TEXT NOT NULL REFERENCES math_problems(id), candidate_solution_result_id TEXT REFERENCES math_candidate_solution_results(id), parse_result_id TEXT REFERENCES math_parse_results(id), build_result_id TEXT REFERENCES math_sympy_build_results(id), analysis_report_id TEXT REFERENCES math_analysis_reports(id), input_source_revision INTEGER, input_hash TEXT, verifier_version TEXT NOT NULL, status TEXT NOT NULL, verification_plan_json TEXT, checks_json TEXT, verified_result_json TEXT, report_json TEXT, warnings_json TEXT NOT NULL DEFAULT '[]', errors_json TEXT NOT NULL DEFAULT '[]', duration_ms INTEGER, execution_mode TEXT, worker_exit_code INTEGER, timed_out INTEGER NOT NULL DEFAULT 0, termination_method TEXT, created_at TEXT NOT NULL);
INSERT INTO math_verification_reports(id,problem_id,verifier_version,status,report_json,created_at) SELECT id,problem_id,COALESCE(verifier_version,'legacy'),status,report_json,created_at FROM math_verification_reports_legacy;
DROP TABLE math_verification_reports_legacy;
CREATE UNIQUE INDEX idx_math_verify_dedupe ON math_verification_reports(candidate_solution_result_id,input_hash,verifier_version);
CREATE INDEX idx_math_verify_current ON math_verification_reports(problem_id,input_source_revision,created_at);
PRAGMA foreign_keys=ON;
