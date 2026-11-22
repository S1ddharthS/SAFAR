"""Run SAFAR data-retention cleanup once.

Schedule daily, for example:
    docker compose run --rm api python scripts/retention.py
    # or a cron entry: 15 3 * * *  cd /srv/safar/services/api && .venv/bin/python scripts/retention.py
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.logging import configure_logging  # noqa: E402
from app.db.context import system_context  # noqa: E402
from app.db.session import SessionLocal  # noqa: E402
from app.services.retention import run_retention  # noqa: E402


def main() -> int:
    configure_logging()
    db = SessionLocal()
    try:
        with system_context(db):
            removed = run_retention(db)
            db.commit()
    finally:
        db.close()
    print(json.dumps({"retention": removed}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
