"""Server-side sessions with refresh-token rotation and reuse detection."""

from datetime import timedelta
import logging

from fastapi import Request
from sqlalchemy.orm import Session

from app.core.alerting import AlertCategory, AlertSeverity, alert_manager
from app.core.config import settings
from app.core.metrics import metrics
from app.core.security import (
    hash_client_ip,
    hash_refresh_secret,
    new_refresh_secret,
)
from app.models import AuthSession, User
from app.models.models import utcnow

security_logger = logging.getLogger("safar.security")


def _request_meta(request: Request | None) -> tuple[str | None, str | None]:
    if request is None:
        return None, None
    agent = (request.headers.get("user-agent") or "")[:200] or None
    client = request.client.host if request.client else None
    ip_hash = hash_client_ip(client) or None
    return agent, ip_hash


def create_session(
    db: Session, user: User, request: Request | None = None
) -> tuple[AuthSession, str]:
    secret = new_refresh_secret()
    agent, ip_hash = _request_meta(request)
    session = AuthSession(
        user_id=user.id,
        refresh_hash=hash_refresh_secret(secret),
        user_agent=agent,
        ip_hash=ip_hash,
        expires_at=utcnow() + timedelta(days=settings.refresh_token_expire_days),
    )
    db.add(session)
    db.flush()
    return session, f"{session.id}.{secret}"


def session_is_active(db: Session, session_id: str, user_id: str) -> bool:
    session = db.get(AuthSession, session_id)
    if not session or session.user_id != user_id:
        return False
    if session.revoked_at is not None:
        return False
    return session.expires_at > utcnow()


def rotate_refresh_token(
    db: Session, token: str, request: Request | None = None
) -> tuple[AuthSession | None, str | None, User | None]:
    """Returns (session, refresh_token, user). A mismatch revokes the session."""
    session_id, separator, secret = token.partition(".")
    if not separator or not session_id or not secret:
        return None, None, None
    session = db.get(AuthSession, session_id)
    if not session:
        return None, None, None
    if session.revoked_at is not None:
        return None, None, None
    if session.expires_at <= utcnow():
        session.revoked_at = utcnow()
        session.revoked_reason = "expired"
        db.commit()
        return None, None, None
    if session.refresh_hash != hash_refresh_secret(secret):
        # A previously rotated token was presented: treat as theft.
        session.revoked_at = utcnow()
        session.revoked_reason = "refresh_reuse"
        db.commit()
        metrics.record_auth_event("refresh_reuse")
        security_logger.critical(
            "auth_refresh_reuse_detected",
            extra={"session_id": session.id, "user_id": session.user_id},
        )
        alert_manager.trigger(
            AlertCategory.REFRESH_REUSE_DETECTED,
            AlertSeverity.CRITICAL,
            "Refresh Token Reuse (Theft Detected)",
            f"Session {session.id} for user {session.user_id} detected refresh token reuse. Session revoked.",
            details={"session_id": session.id, "user_id": session.user_id},
        )
        return None, None, None
    user = db.get(User, session.user_id)
    if not user or not user.is_active or user.deleted_at:
        session.revoked_at = utcnow()
        session.revoked_reason = "account_unavailable"
        db.commit()
        return None, None, None

    new_secret = new_refresh_secret()
    session.refresh_hash = hash_refresh_secret(new_secret)
    session.last_used_at = utcnow()
    session.expires_at = utcnow() + timedelta(
        days=settings.refresh_token_expire_days
    )
    agent, ip_hash = _request_meta(request)
    if agent:
        session.user_agent = agent
    if ip_hash:
        session.ip_hash = ip_hash
    db.commit()
    return session, f"{session.id}.{new_secret}", user


def revoke_session(db: Session, session_id: str, reason: str = "logout") -> None:
    session = db.get(AuthSession, session_id)
    if session and session.revoked_at is None:
        session.revoked_at = utcnow()
        session.revoked_reason = reason
        db.commit()


def revoke_all_sessions(db: Session, user_id: str, reason: str = "logout_all") -> None:
    now = utcnow()
    db.query(AuthSession).filter(
        AuthSession.user_id == user_id, AuthSession.revoked_at.is_(None)
    ).update(
        {"revoked_at": now, "revoked_reason": reason}, synchronize_session=False
    )
    db.commit()


def active_session_count(db: Session, user_id: str) -> int:
    return (
        db.query(AuthSession)
        .filter(
            AuthSession.user_id == user_id,
            AuthSession.revoked_at.is_(None),
            AuthSession.expires_at > utcnow(),
        )
        .count()
    )
