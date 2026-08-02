ALTER TABLE math_parse_results ADD COLUMN normalization_version TEXT;
ALTER TABLE math_parse_results ADD COLUMN tokenizer_version TEXT;
ALTER TABLE math_parse_results ADD COLUMN ir_version TEXT;
ALTER TABLE math_parse_results ADD COLUMN normalized_input TEXT;
ALTER TABLE math_parse_results ADD COLUMN tokens_json TEXT;
ALTER TABLE math_parse_results ADD COLUMN raw_ast_json TEXT;
ALTER TABLE math_parse_results ADD COLUMN canonical_ast_json TEXT;
ALTER TABLE math_parse_results ADD COLUMN warnings_json TEXT NOT NULL DEFAULT '[]';
ALTER TABLE math_parse_results ADD COLUMN errors_json TEXT NOT NULL DEFAULT '[]';
