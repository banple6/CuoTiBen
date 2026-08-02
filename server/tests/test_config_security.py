from __future__ import annotations

import os
import subprocess
import sys
import unittest
from pathlib import Path


class AuthConfigurationTests(unittest.TestCase):
    """Import-time configuration checks run in isolated Python processes."""

    @staticmethod
    def read_config(**overrides: str) -> tuple[str, bool]:
        server_root = Path(__file__).parents[1]
        environment = os.environ.copy()
        for name in ("APP_ENV", "MATH_ALLOW_DEV_USER_HEADER"):
            environment.pop(name, None)
        environment.update(
            {
                "AI_STUDIO_API_URL": "http://example.invalid",
                "AI_STUDIO_ACCESS_TOKEN": "ci-placeholder",
                # Do not let a developer's untracked .env affect this test.
                "PYTHON_DOTENV_DISABLED": "true",
                "PYTHONPATH": str(server_root),
                **overrides,
            }
        )
        result = subprocess.run(
            [
                sys.executable,
                "-c",
                "from app import config; print(config.APP_ENV); print(int(config.MATH_ALLOW_DEV_USER_HEADER))",
            ],
            cwd=server_root,
            env=environment,
            check=True,
            capture_output=True,
            text=True,
        )
        lines = result.stdout.strip().splitlines()
        return lines[-2], lines[-1] == "1"

    def test_default_is_production_and_header_is_disabled(self):
        self.assertEqual(self.read_config(), ("production", False))

    def test_production_and_staging_never_enable_header(self):
        for app_env in ("production", "staging"):
            with self.subTest(app_env=app_env):
                self.assertEqual(
                    self.read_config(APP_ENV=app_env, MATH_ALLOW_DEV_USER_HEADER="true"),
                    (app_env, False),
                )

    def test_development_and_test_require_explicit_true(self):
        for app_env in ("development", "test"):
            with self.subTest(app_env=app_env):
                self.assertEqual(self.read_config(APP_ENV=app_env), (app_env, False))
                self.assertEqual(
                    self.read_config(APP_ENV=app_env, MATH_ALLOW_DEV_USER_HEADER="true"),
                    (app_env, True),
                )


if __name__ == "__main__":
    unittest.main()
