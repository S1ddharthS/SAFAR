import os
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(API_ROOT))

_TMP = Path(tempfile.mkdtemp(prefix="safar-tests-"))
_pg_url = os.environ.get("SAFAR_TEST_DATABASE_URL")
os.environ["DATABASE_URL"] = _pg_url or f"sqlite:///{(_TMP / 'safar-test.db').as_posix()}"
os.environ["SAFAR_SEED"] = "1"
os.environ["ENVIRONMENT"] = "test"
os.environ["SECRET_KEY"] = "test-only-secret-never-use-outside-tests"
os.environ["RATE_LIMIT_PER_MINUTE"] = "100000"
os.environ["AUTH_RATE_LIMIT_PER_MINUTE"] = "100000"
os.environ["COMPANION_RATE_LIMIT_PER_MINUTE"] = "100000"
os.environ["UPLOAD_RATE_LIMIT_PER_MINUTE"] = "100000"
os.environ["CORS_ORIGINS"] = "http://localhost:3000"


def _reset_postgres() -> None:
    """Drop and rebuild the PG schema, then apply the real migrations."""
    import psycopg

    with psycopg.connect(_pg_url.replace("postgresql+psycopg://", "postgresql://")) as conn:
        conn.execute("DROP SCHEMA IF EXISTS public CASCADE")
        conn.execute("CREATE SCHEMA public")
        conn.commit()

    from alembic import command
    from alembic.config import Config

    cfg = Config(str(API_ROOT / "alembic.ini"))
    cfg.set_main_option("script_location", str(API_ROOT / "migrations"))
    command.upgrade(cfg, "head")


if _pg_url:
    if not _pg_url.startswith("postgresql+psycopg://"):
        raise SystemExit("SAFAR_TEST_DATABASE_URL must use postgresql+psycopg://")
    if os.environ.get("SAFAR_TEST_PREPARED") == "1":
        # Prepared mode connects as the non-owner application role. Schema,
        # grants and RLS policies were applied beforehand by the runner.
        os.environ["SAFAR_CREATE_SCHEMA"] = "0"
    else:
        _reset_postgres()

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402

DEMO_PASSWORD = "safar-demo-123"


@contextmanager
def system_db():
    """Direct database access for assertions, outside any RLS identity."""
    from app.db.context import system_context
    from app.db.session import SessionLocal

    db = SessionLocal()
    try:
        with system_context(db):
            yield db
    finally:
        db.close()


@pytest.fixture(scope="session")
def client():
    with TestClient(app) as test_client:
        yield test_client


def login(client: TestClient, email: str, password: str = DEMO_PASSWORD) -> dict[str, str]:
    response = client.post(
        "/api/auth/login", json={"email": email, "password": password}
    )
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


@pytest.fixture(scope="session")
def mira(client):
    return login(client, "mira@safar.demo")


@pytest.fixture(scope="session")
def jonas(client):
    return login(client, "jonas@safar.demo")


@pytest.fixture(scope="session")
def aiko(client):
    return login(client, "aiko@safar.demo")


@pytest.fixture(scope="session")
def noor(client):
    return login(client, "noor@safar.demo")


@pytest.fixture(scope="session")
def kyoto(client, mira):
    response = client.get("/api/trips", headers=mira)
    assert response.status_code == 200, response.text
    for trip in response.json()["items"]:
        if trip["name"] == "Kyoto in Slow Bloom":
            return trip
    raise AssertionError("Seeded Kyoto trip is missing")
