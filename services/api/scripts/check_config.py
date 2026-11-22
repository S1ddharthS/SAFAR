"""Print a redacted startup-configuration summary.

Used by CI/preflight to prove that hosted environment variables satisfy the
fail-closed checks in :mod:`app.core.config` without printing credentials,
database URLs, cookies or member data.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.config import Settings  # noqa: E402


def main() -> int:
    config = Settings()
    summary = {
        "environment": config.environment,
        "database_driver": config.database_url.split(":", 1)[0],
        "media_backend": config.media_backend,
        "email_provider": config.email_provider,
        "cookie_secure": config.cookie_secure,
        "cookie_samesite": config.cookie_samesite,
        "api_docs_enabled": config.api_docs_enabled,
        "auto_seed": config.auto_seed,
        "create_schema": config.create_schema,
        "trusted_hosts": config.trusted_hosts,
        "cors_origins": config.cors_origins,
        "release": config.release,
    }
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
