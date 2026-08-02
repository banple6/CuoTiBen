-- Recover failed and abandoned import reservations without changing the
-- request hash or ownership scope.
ALTER TABLE math_idempotency_records ADD COLUMN attempt_count INTEGER NOT NULL DEFAULT 1;
ALTER TABLE math_idempotency_records ADD COLUMN last_error_code TEXT;
ALTER TABLE math_idempotency_records ADD COLUMN last_failed_at TEXT;
CREATE INDEX IF NOT EXISTS idx_math_idempotency_reclaim
    ON math_idempotency_records(status, expires_at, updated_at);
