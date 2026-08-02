-- Fifth-stage A.5: immutable content, privacy-safe retention.
-- UPDATE remains blocked. DELETE is intentionally allowed so a controlled
-- account/import/problem purge and parent FK cascades can remove all user data.
PRAGMA foreign_keys=OFF;

DROP TRIGGER IF EXISTS math_explanations_no_update;
DROP TRIGGER IF EXISTS math_explanations_no_delete;
DROP INDEX IF EXISTS idx_math_explanations_current;
DROP INDEX IF EXISTS idx_math_explanations_request;

ALTER TABLE math_explanations RENAME TO math_explanations_v9;

CREATE TABLE math_explanations (
    id TEXT PRIMARY KEY,
    problem_id TEXT NOT NULL REFERENCES math_problems(id) ON DELETE CASCADE,
    verification_report_id TEXT NOT NULL REFERENCES math_verification_reports(id) ON DELETE CASCADE,
    candidate_solution_result_id TEXT NOT NULL REFERENCES math_candidate_solution_results(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,
    request_id TEXT NOT NULL,
    input_source_revision INTEGER NOT NULL,
    input_hash TEXT NOT NULL,
    provider TEXT NOT NULL,
    model_name TEXT NOT NULL,
    model_version TEXT NOT NULL,
    prompt_id TEXT NOT NULL,
    prompt_version TEXT NOT NULL,
    prompt_content_hash TEXT NOT NULL,
    prompt_created_at TEXT NOT NULL,
    schema_version TEXT NOT NULL,
    trace_version TEXT NOT NULL DEFAULT '1',
    renderer_version TEXT NOT NULL DEFAULT '1',
    teaching_profile_hash TEXT NOT NULL,
    status TEXT NOT NULL,
    explanation_input_json TEXT NOT NULL,
    raw_model_response_json TEXT,
    validated_explanation_json TEXT,
    quality_json TEXT NOT NULL DEFAULT '{}',
    warnings_json TEXT NOT NULL DEFAULT '[]',
    errors_json TEXT NOT NULL DEFAULT '[]',
    error_code TEXT,
    input_tokens INTEGER,
    output_tokens INTEGER,
    cached_tokens INTEGER,
    provider_request_id TEXT,
    actual_model_name TEXT,
    pricing_version TEXT,
    estimated_cost REAL,
    duration_ms INTEGER,
    attempts INTEGER NOT NULL DEFAULT 1,
    cache_hit INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    UNIQUE(verification_report_id,input_hash,provider,model_name,model_version,prompt_version,schema_version,teaching_profile_hash,trace_version,renderer_version)
);

INSERT INTO math_explanations (
    id, problem_id, verification_report_id, candidate_solution_result_id,
    user_id, request_id, input_source_revision, input_hash, provider,
    model_name, model_version, prompt_id, prompt_version, prompt_content_hash,
    prompt_created_at, schema_version, teaching_profile_hash, status,
    explanation_input_json, raw_model_response_json, validated_explanation_json,
    warnings_json, errors_json, input_tokens, output_tokens, estimated_cost,
    duration_ms, cache_hit, created_at
)
SELECT
    id, problem_id, verification_report_id, candidate_solution_result_id,
    user_id, request_id, input_source_revision, input_hash, provider,
    model_name, model_version, prompt_id, prompt_version, prompt_content_hash,
    prompt_created_at, schema_version, teaching_profile_hash, status,
    explanation_input_json, raw_model_response_json, validated_explanation_json,
    warnings_json, errors_json, input_tokens, output_tokens, estimated_cost,
    duration_ms, cache_hit, created_at
FROM math_explanations_v9;

DROP TABLE math_explanations_v9;

CREATE INDEX idx_math_explanations_current
    ON math_explanations(problem_id,input_source_revision,created_at);
CREATE INDEX idx_math_explanations_request
    ON math_explanations(user_id,request_id);
CREATE INDEX idx_math_explanations_user
    ON math_explanations(user_id,created_at);

CREATE TRIGGER math_explanations_no_update
BEFORE UPDATE ON math_explanations
BEGIN
    SELECT RAISE(ABORT,'math_explanations_are_immutable');
END;

PRAGMA foreign_keys=ON;
