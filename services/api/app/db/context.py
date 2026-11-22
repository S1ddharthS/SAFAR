"""Per-request PostgreSQL context for row-level security.

The application connects as a non-owner role in production. Every transaction
sets the ``app.*`` GUCs below; policies use them through SECURITY DEFINER
helpers. With no context, policies deny access (fail closed).
"""

from contextlib import contextmanager

from sqlalchemy import event, text
from sqlalchemy.orm import Session

_GUC_NAMES = {
    "app_user_id": "app.user_id",
    "app_admin": "app.admin",
    "app_system": "app.system",
    "app_auth": "app.auth",
    "app_companion_link": "app.companion_link",
    "app_invitation_token": "app.invitation_token",
}

_SETTINGS_SQL = text(
    "SELECT "
    + ", ".join(
        f"set_config('{guc}', :{key}, true)" for key, guc in _GUC_NAMES.items()
    )
)


def _params(values: dict) -> dict:
    return {key: str(values.get(key) or "") for key in _GUC_NAMES}


def _apply(connection, values: dict) -> None:
    connection.execute(_SETTINGS_SQL, _params(values))


@event.listens_for(Session, "after_begin")
def _apply_on_begin(session, transaction, connection) -> None:
    if connection.dialect.name != "postgresql":
        return
    _apply(connection, session.info.get("safar_context", {}))


def set_context(db: Session, **values) -> None:
    merged = dict(db.info.get("safar_context", {}))
    for key, value in values.items():
        if key not in _GUC_NAMES:
            raise KeyError(f"Unknown database context key: {key}")
        merged[key] = value
    db.info["safar_context"] = merged
    bind = db.get_bind()
    if bind.dialect.name == "postgresql" and db.in_transaction():
        _apply(db.connection(), merged)


def set_user_context(db: Session, user_id: str, admin: bool = False) -> None:
    set_context(db, app_user_id=user_id, app_admin="on" if admin else "")


def auth_context(db: Session) -> None:
    set_context(db, app_auth="on")


def companion_context(db: Session, link_id: str) -> None:
    set_context(db, app_companion_link=link_id)


@contextmanager
def system_context(db: Session):
    """Temporarily mark the transaction as a trusted internal task."""
    previous = db.info.get("safar_context", {}).get("app_system")
    set_context(db, app_system="on")
    try:
        yield
    finally:
        set_context(db, app_system=previous or "")
