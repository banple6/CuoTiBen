"""Versioned SQLite migrations; application code never mutates schema implicitly."""
from __future__ import annotations
import sqlite3
import sys
from pathlib import Path

MIGRATIONS = [(1, "0001_initial.sql"), (2, "0002_phase2_foundation.sql"), (3, "0003_parse_artifacts.sql"), (4, "0004_sympy_build_artifacts.sql"), (5, "0005_candidate_solution_results.sql"), (6, "0006_solver_execution_metadata.sql"), (7, "0007_verification_reports_v2.sql"), (8, "0008_rebuild_verification_reports.sql"), (9, "0009_math_explanations.sql")]

def upgrade(database_path: str, migrations_dir: Path | None = None) -> int:
    root = migrations_dir or Path(__file__).parent
    Path(database_path).parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(database_path)
    try:
        db.execute("CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)")
        # Phase one created these tables at runtime. Mark that exact schema as v1,
        # then let the ordinary v2 SQL upgrade it without dropping user evidence.
        has_phase_one = db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='math_imports'").fetchone()
        has_versions = db.execute("SELECT 1 FROM schema_migrations LIMIT 1").fetchone()
        if has_phase_one and not has_versions:
            db.execute("INSERT INTO schema_migrations(version) VALUES (1)")
        current = {row[0] for row in db.execute("SELECT version FROM schema_migrations")}
        for version, filename in MIGRATIONS:
            if version not in current:
                db.executescript((root / filename).read_text(encoding="utf-8"))
                db.execute("INSERT INTO schema_migrations(version) VALUES (?)", (version,))
        db.commit()
        return max((item[0] for item in MIGRATIONS), default=0)
    finally:
        db.close()


def current_version(database_path: str) -> int:
    path = Path(database_path)
    if not path.exists():
        return 0
    with sqlite3.connect(path) as db:
        try:
            row = db.execute("SELECT MAX(version) FROM schema_migrations").fetchone()
        except sqlite3.OperationalError:
            return 0
    return int(row[0] or 0)


def require_current(database_path: str) -> None:
    required = MIGRATIONS[-1][0]
    current = current_version(database_path)
    if current < required:
        raise RuntimeError(f"math workbook database schema is {current}; run: python -m app.math_workbook.migrations.runner --database {database_path}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", required=True)
    args = parser.parse_args()
    print(upgrade(args.database))
