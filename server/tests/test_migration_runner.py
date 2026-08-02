from __future__ import annotations

import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from app.math_workbook.migrations import runner


class _RecordingConnection:
    def __init__(self, connection: sqlite3.Connection, events: list[tuple[str, bool]]) -> None:
        self._connection = connection
        self._events = events

    def execute(self, sql, parameters=()):
        if isinstance(sql, str):
            self._events.append((sql, self._connection.in_transaction))
        return self._connection.execute(sql, parameters)

    def __getattr__(self, name):
        return getattr(self._connection, name)


class MigrationPragmaTests(unittest.TestCase):
    def test_leading_comment_classifier_handles_all_supported_prefixes(self):
        cases = (
            "PRAGMA foreign_keys=OFF;",
            "-- first\n-- second\n\nPRAGMA foreign_keys=OFF;",
            "/* block comment */\n\nPRAGMA foreign_keys=OFF;",
            "\n -- first\r\n /* second */ \n PRAGMA foreign_keys = OFF;",
        )
        for script in cases:
            with self.subTest(script=script):
                self.assertEqual(runner._pragma_kind(script), "foreign_keys_off")
                self.assertTrue(runner._foreign_keys_off(script))
        self.assertEqual(
            runner._pragma_kind("-- comment\n/* another */\nPRAGMA foreign_keys=ON;"),
            "foreign_keys_on",
        )

    def test_classifier_does_not_strip_comment_markers_inside_string_literals(self):
        statement = "/* prefix */ SELECT '-- not a comment /* literal */';"
        self.assertEqual(
            runner._strip_leading_sql_comments(statement),
            "SELECT '-- not a comment /* literal */';",
        )

    def test_pragma_is_applied_before_begin_and_never_inside_transaction(self):
        original_migrations = runner.MIGRATIONS
        original_connect = runner.sqlite3.connect
        try:
            runner.MIGRATIONS = [(1, "test.sql")]
            prefixes = (
                "",
                "-- migration description\n-- another comment\n\n",
                "/* migration description */\n\n",
            )
            for prefix in prefixes:
                with self.subTest(prefix=prefix), tempfile.TemporaryDirectory() as tmp:
                    root = Path(tmp) / "migrations"
                    root.mkdir()
                    (root / "test.sql").write_text(
                        prefix
                        + "PRAGMA foreign_keys=OFF;\n"
                        + "PRAGMA foreign_keys=ON;\n"
                        + "CREATE TABLE pragma_marker(id INTEGER PRIMARY KEY);\n",
                        encoding="utf-8",
                    )
                    db_path = Path(tmp) / "database.sqlite"
                    events: list[tuple[str, bool]] = []

                    def connect(*args, **kwargs):
                        return _RecordingConnection(original_connect(*args, **kwargs), events)

                    with patch.object(runner.sqlite3, "connect", side_effect=connect):
                        self.assertEqual(runner.upgrade(str(db_path), root), 1)

                    foreign_key_events = [event for event in events if event[0].lstrip().upper().startswith("PRAGMA FOREIGN_KEYS")]
                    self.assertTrue(foreign_key_events)
                    self.assertTrue(any("=OFF" in sql.upper() for sql, _ in foreign_key_events))
                    self.assertTrue(any("=ON" in sql.upper() for sql, _ in foreign_key_events))
                    self.assertTrue(all(not in_transaction for _, in_transaction in foreign_key_events))
                    off_index = next(i for i, (sql, _) in enumerate(events) if "PRAGMA foreign_keys=OFF" in sql)
                    # upgrade() has a separate bootstrap transaction.  The
                    # relevant migration transaction is the BEGIN following
                    # the OFF setting for this migration.
                    begin_index = next(i for i, (sql, _) in enumerate(events) if i > off_index and sql == "BEGIN IMMEDIATE")
                    self.assertLess(off_index, begin_index)
                    self.assertEqual(foreign_key_events[-1][0], "PRAGMA foreign_keys=ON")
                    with sqlite3.connect(db_path) as db:
                        db.execute("PRAGMA foreign_keys=ON")
                        self.assertEqual(db.execute("PRAGMA foreign_key_check").fetchall(), [])
        finally:
            runner.MIGRATIONS = original_migrations

    def test_failed_migration_rolls_back_and_restores_foreign_keys(self):
        original_migrations = runner.MIGRATIONS
        try:
            runner.MIGRATIONS = [(1, "broken.sql")]
            with tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp) / "migrations"
                root.mkdir()
                (root / "broken.sql").write_text(
                    "/* force the pre-transaction branch */\n"
                    "PRAGMA foreign_keys=OFF;\n"
                    "CREATE TABLE should_rollback(id INTEGER PRIMARY KEY);\n"
                    "SELECT * FROM missing_table;\n",
                    encoding="utf-8",
                )
                db_path = Path(tmp) / "database.sqlite"
                events: list[tuple[str, bool]] = []
                original_connect = runner.sqlite3.connect

                def connect(*args, **kwargs):
                    return _RecordingConnection(original_connect(*args, **kwargs), events)

                with patch.object(runner.sqlite3, "connect", side_effect=connect):
                    with self.assertRaises(sqlite3.OperationalError):
                        runner.upgrade(str(db_path), root)
                foreign_key_events = [event for event in events if event[0].lstrip().upper().startswith("PRAGMA FOREIGN_KEYS")]
                self.assertEqual(foreign_key_events[-1][0], "PRAGMA foreign_keys=ON")
                self.assertFalse(foreign_key_events[-1][1])
                self.assertEqual(runner.current_version(str(db_path)), 0)
                with sqlite3.connect(db_path) as db:
                    self.assertIsNone(db.execute("SELECT 1 FROM sqlite_master WHERE name='should_rollback'").fetchone())
                    db.execute("PRAGMA foreign_keys=ON")
                    self.assertEqual(db.execute("PRAGMA foreign_key_check").fetchall(), [])
        finally:
            runner.MIGRATIONS = original_migrations


if __name__ == "__main__":
    unittest.main()
