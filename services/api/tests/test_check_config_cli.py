"""The preflight config checker must validate without leaking secrets."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

API_ROOT = Path(__file__).resolve().parents[1]

_HARDENED_ENV = {
    "ENVIRONMENT": "staging",
    "DATABASE_URL": (
        "postgresql+psycopg://safar:NEVER_PRINT_THIS@db:5432/safar"
    ),
    "SECRET_KEY": "STAGING_SECRET_NEVER_PRINT_THIS_0123456789abcdef",
    "CORS_ORIGINS": "https://staging.example.com",
    "TRUSTED_HOSTS": "staging.example.com,localhost",
    "COOKIE_SECURE": "true",
    "SAFAR_MEDIA_BACKEND": "local",
    "SAFAR_SEED": "false",
    "SAFAR_CREATE_SCHEMA": "false",
    "ENABLE_API_DOCS": "false",
}


def test_check_config_prints_redacted_json():
    env = os.environ.copy()
    env.update(_HARDENED_ENV)

    result = subprocess.run(
        [sys.executable, "scripts/check_config.py"],
        cwd=API_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert payload["environment"] == "staging"
    assert payload["database_driver"] == "postgresql+psycopg"
    assert payload["media_backend"] == "local"
    assert payload["cookie_secure"] is True
    assert payload["auto_seed"] is False
    assert payload["create_schema"] is False
    assert "NEVER_PRINT_THIS" not in result.stdout
    assert "NEVER_PRINT_THIS" not in result.stderr
