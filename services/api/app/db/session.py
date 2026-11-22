import logging
import time
from typing import Any

from sqlalchemy import create_engine, event, text
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from app.core.alerting import AlertCategory, AlertSeverity, alert_manager
from app.core.config import settings
from app.core.metrics import metrics

db_logger = logging.getLogger("safar.db")


class Base(DeclarativeBase):
    pass


_is_sqlite = settings.database_url.startswith("sqlite")
engine = create_engine(
    settings.database_url,
    connect_args={"check_same_thread": False} if _is_sqlite else {},
    pool_pre_ping=True,
)

if _is_sqlite:

    @event.listens_for(engine, "connect")
    def _enable_sqlite_foreign_keys(dbapi_connection, _connection_record):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()


@event.listens_for(engine, "before_cursor_execute")
def _before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
    if context:
        context._query_start_time = time.perf_counter()


@event.listens_for(engine, "after_cursor_execute")
def _after_cursor_execute(conn, cursor, statement, parameters, context, executemany):
    start = getattr(context, "_query_start_time", None) if context else None
    if start is not None:
        elapsed_ms = (time.perf_counter() - start) * 1000
        is_slow = elapsed_ms > settings.slow_query_threshold_ms
        metrics.record_db_query(elapsed_ms, is_slow=is_slow)
        if is_slow:
            # Redact statement by only taking first 120 chars of query keyword/table
            short_stmt = " ".join(statement.split()[:8])
            db_logger.warning(
                "slow_query_detected",
                extra={"duration_ms": round(elapsed_ms, 2), "statement": short_stmt},
            )


@event.listens_for(engine, "handle_error")
def _handle_db_error(exception_context):
    metrics.record_db_error()
    stmt = getattr(exception_context, "statement", None)
    short_stmt = " ".join(stmt.split()[:8]) if stmt else "unknown"
    db_logger.error("db_statement_error", extra={"statement": short_stmt})
    # Connection-level errors trigger alert
    if exception_context.is_disconnect:
        alert_manager.trigger(
            AlertCategory.DATABASE_DOWN,
            AlertSeverity.CRITICAL,
            "Database Disconnected",
            "Database connection disconnect detected on query execution.",
        )


def get_db_pool_status() -> dict[str, int]:
    """Inspects connection pool usage safely."""
    pool = engine.pool
    size = pool.size() if hasattr(pool, "size") and callable(pool.size) else 0
    checked_in = pool.checkedin() if hasattr(pool, "checkedin") and callable(pool.checkedin) else 0
    checked_out = pool.checkedout() if hasattr(pool, "checkedout") and callable(pool.checkedout) else 0
    overflow = pool.overflow() if hasattr(pool, "overflow") and callable(pool.overflow) else 0
    return {
        "size": size,
        "checked_in": checked_in,
        "checked_out": checked_out,
        "overflow": overflow,
    }


def check_db_readiness() -> dict[str, Any]:
    """Readiness probe: verifies database connectivity, latency, and migration status."""
    t0 = time.perf_counter()
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
            ping_ms = round((time.perf_counter() - t0) * 1000, 2)
            rev = None
            try:
                res = conn.execute(text("SELECT version_num FROM alembic_version LIMIT 1")).fetchone()
                if res:
                    rev = res[0]
            except Exception:
                pass
            return {
                "status": "ok",
                "engine": "sqlite" if _is_sqlite else "postgresql",
                "ping_ms": ping_ms,
                "migration_revision": rev or "untracked",
                "pool": get_db_pool_status(),
            }
    except Exception:
        metrics.record_db_error()
        alert_manager.trigger(
            AlertCategory.DATABASE_DOWN,
            AlertSeverity.CRITICAL,
            "Database Unreachable",
            "Readiness probe failed to connect to database.",
        )
        return {
            "status": "unavailable",
            "engine": "sqlite" if _is_sqlite else "postgresql",
            "ping_ms": round((time.perf_counter() - t0) * 1000, 2),
            "migration_revision": "unknown",
            "pool": get_db_pool_status(),
            "error": "Database unreachable",
        }


SessionLocal = sessionmaker(
    bind=engine, autocommit=False, autoflush=False, expire_on_commit=False
)

# Registers the after_begin hook that applies app.* GUCs for RLS.
from app.db import context  # noqa: E402,F401
