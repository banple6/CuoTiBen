ALTER TABLE math_candidate_solution_results ADD COLUMN execution_mode TEXT NOT NULL DEFAULT 'in_process_legacy';
ALTER TABLE math_candidate_solution_results ADD COLUMN worker_exit_code INTEGER;
ALTER TABLE math_candidate_solution_results ADD COLUMN timed_out INTEGER NOT NULL DEFAULT 0;
ALTER TABLE math_candidate_solution_results ADD COLUMN termination_method TEXT;
