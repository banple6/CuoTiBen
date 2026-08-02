"""Versioned SQLite migrations with one atomic transaction per version."""

from __future__ import annotations

import re
import sqlite3
import sys
from pathlib import Path
from typing import Iterator


MIGRATIONS = [
    (1, "0001_initial.sql"),
    (2, "0002_phase2_foundation.sql"),
    (3, "0003_parse_artifacts.sql"),
    (4, "0004_sympy_build_artifacts.sql"),
    (5, "0005_candidate_solution_results.sql"),
    (6, "0006_solver_execution_metadata.sql"),
    (7, "0007_verification_reports_v2.sql"),
    (8, "0008_rebuild_verification_reports.sql"),
    (9, "0009_math_explanations.sql"),
    (10, "0010_math_explanation_retention.sql"),
]

_FOREIGN_KEYS_RE = re.compile(r"^\s*PRAGMA\s+foreign_keys\s*=", re.IGNORECASE)


class MigrationIntegrityError(RuntimeError):
    """Raised when a migration would leave an invalid foreign-key graph."""


def _statements(script: str) -> Iterator[str]:
    """Yield complete SQL statements without executescript's implicit commit."""

    buffer: list[str] = []
    for line in script.splitlines(keepends=True):
        buffer.append(line)
        joined = "".join(buffer)
        if sqlite3.complete_statement(joined):
            statement = joined.strip()
            buffer.clear()
            if statement:
                yield statement
    trailing = "".join(buffer).strip()
    if trailing and not trailing.startswith("--"):
        raise sqlite3.OperationalError("incomplete migration statement")


def _foreign_keys_off(script: str) -> bool:
    return any(
        _FOREIGN_KEYS_RE.match(statement) and re.search(r"=\s*OFF\b", statement, re.IGNORECASE)
        for statement in _statements(script)
    )


def _foreign_key_violations(db: sqlite3.Connection) -> set[tuple[object, ...]]:
    # The fourth PRAGMA column is the parent-column ordinal and can change
    # when a legacy table is rebuilt. Compare the stable table/row/parent
    # identity while still running the full check.
    return {tuple(row[:3]) for row in db.execute("PRAGMA foreign_key_check").fetchall()}


def _foreign_key_check(db: sqlite3.Connection, allowed: set[tuple[object, ...]] | None = None) -> None:
    violations = _foreign_key_violations(db)
    unexpected = violations - (allowed or set())
    if unexpected:
        raise MigrationIntegrityError(f"foreign_key_check failed: {sorted(unexpected)!r}")


def _apply_one(
    db: sqlite3.Connection,
    version: int,
    filename: str,
    root: Path,
    preexisting_foreign_key_violations: set[tuple[object, ...]],
) -> None:
    script = (root / filename).read_text(encoding="utf-8")
    # PRAGMA foreign_keys is a connection setting and is ignored inside an
    # active transaction. Apply it before BEGIN, and omit it from the script.
    db.execute("PRAGMA foreign_keys=OFF" if _foreign_keys_off(script) else "PRAGMA foreign_keys=ON")
    try:
        db.execute("BEGIN IMMEDIATE")
        if db.execute("SELECT 1 FROM schema_migrations WHERE version=?", (version,)).fetchone():
            db.commit()
            db.execute("PRAGMA foreign_keys=ON")
            return
        for statement in _statements(script):
            if _FOREIGN_KEYS_RE.match(statement):
                continue
            db.execute(statement)
        # Check before COMMIT so a failed migration can be rolled back as one unit.
        _foreign_key_check(db, preexisting_foreign_key_violations)
        db.execute("INSERT INTO schema_migrations(version) VALUES (?)", (version,))
        db.commit()
        db.execute("PRAGMA foreign_keys=ON")
        _foreign_key_check(db, preexisting_foreign_key_violations)
    except Exception:
        if db.in_transaction:
            db.rollback()
        # A failed migration must not leave the connection with relaxed checks.
        db.execute("PRAGMA foreign_keys=ON")
        raise


def upgrade(database_path: str, migrations_dir: Path | None = None) -> int:
    root = migrations_dir or Path(__file__).parent
    Path(database_path).parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(database_path, timeout=30, isolation_level=None)
    try:
        db.execute("PRAGMA busy_timeout=30000")
        db.execute("PRAGMA foreign_keys=ON")
        # Older releases allowed a legacy verification row to reference an
        # already-deleted problem. Preserve that historical row, but reject
        # every new violation introduced by a migration.
        preexisting_foreign_key_violations = _foreign_key_violations(db)
        db.execute("CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)")
        db.execute("BEGIN IMMEDIATE")
        has_phase_one = db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='math_imports'").fetchone()
        has_versions = db.execute("SELECT 1 FROM schema_migrations LIMIT 1").fetchone()
        if has_phase_one and not has_versions:
            db.execute("INSERT INTO schema_migrations(version) VALUES (1)")
        db.commit()
        for version, filename in MIGRATIONS:
            _apply_one(db, version, filename, root, preexisting_foreign_key_violations)
        db.execute("PRAGMA foreign_keys=ON")
        _foreign_key_check(db, preexisting_foreign_key_violations)
        return MIGRATIONS[-1][0] if MIGRATIONS else 0
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
