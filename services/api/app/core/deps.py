import hmac
import logging
from collections.abc import Callable

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.logging import redact_path
from app.core.metrics import metrics
from app.core.security import decode_access_token, hash_client_ip
from app.db.context import set_context, set_user_context
from app.db.session import SessionLocal
from app.models import Trip, TripMember, User
from app.services.auth_sessions import session_is_active

auth_logger = logging.getLogger("safar.auth")
security_logger = logging.getLogger("safar.security")

bearer = HTTPBearer(auto_error=False)

SAFE_METHODS = {"GET", "HEAD", "OPTIONS"}


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def _token_from_request(
    request: Request, credentials: HTTPAuthorizationCredentials | None
) -> tuple[str | None, str | None]:
    if credentials and credentials.scheme.lower() == "bearer":
        return credentials.credentials, "bearer"
    cookie = request.cookies.get(settings.access_cookie)
    if cookie:
        return cookie, "cookie"
    return None, None


def csrf_valid(request: Request) -> bool:
    cookie = request.cookies.get(settings.csrf_cookie)
    header = request.headers.get(settings.csrf_header)
    if not cookie or not header:
        return False
    return hmac.compare_digest(cookie, header)


def _resolve_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None,
    db: Session,
) -> User | None:
    token, source = _token_from_request(request, credentials)
    if not token:
        return None
    if (
        source == "cookie"
        and request.method not in SAFE_METHODS
        and not csrf_valid(request)
    ):
        metrics.record_auth_event("csrf_failure")
        client_hash = hash_client_ip(request.client.host if request.client else "")[:16]
        security_logger.warning("csrf_failure", extra={"path": redact_path(request.url.path), "client": client_hash})
        raise HTTPException(status_code=403, detail="CSRF validation failed")
    payload = decode_access_token(token)
    if not payload or not payload.get("sub"):
        metrics.record_auth_event("auth_failure")
        auth_logger.info("auth_token_invalid", extra={"path": redact_path(request.url.path)})
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired session",
            headers={"WWW-Authenticate": "Bearer"},
        )
    # Set the RLS identity from the verified token before reading any row.
    set_user_context(db, payload["sub"])
    user = db.get(User, payload["sub"])
    if not user or not user.is_active or user.deleted_at:
        metrics.record_auth_event("auth_failure")
        auth_logger.warning("auth_user_unavailable", extra={"sub": payload.get("sub"), "path": redact_path(request.url.path)})
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Account unavailable"
        )
    if user.is_admin:
        set_context(db, app_admin="on")
    session_id = payload.get("sid")
    if session_id and not session_is_active(db, session_id, user.id):
        metrics.record_auth_event("auth_failure")
        auth_logger.info("auth_session_expired", extra={"sub": user.id, "path": redact_path(request.url.path)})
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session expired or revoked",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user


def get_current_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
) -> User:
    user = _resolve_user(request, credentials, db)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user


def get_optional_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
) -> User | None:
    try:
        return _resolve_user(request, credentials, db)
    except HTTPException:
        return None


_SCOPE_SAFE_WRITES = {
    "vote": ("/vote",),
    "pulse": ("/pulse",),
    "view": (),
}


def trip_scope_guard(
    request: Request,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
) -> None:
    """Block writes that a limited invitation scope does not allow.

    Owners, admins and `full` members are unrestricted. Limited scopes may
    still read everything and leave the trip; `view` can never write.
    """
    if user is None or request.method in SAFE_METHODS:
        return
    trip_id = request.path_params.get("trip_id")
    if not trip_id:
        return
    member = (
        db.query(TripMember)
        .filter(
            TripMember.trip_id == trip_id,
            TripMember.user_id == user.id,
            TripMember.status == "active",
        )
        .first()
    )
    if not member or member.role in {"owner", "admin"}:
        return
    scope = member.scope or "full"
    if scope == "full":
        return
    path = request.url.path.rstrip("/")
    allowed = any(path.endswith(suffix) for suffix in _SCOPE_SAFE_WRITES.get(scope, ()))
    if request.method == "DELETE" and "/members/" in path:
        allowed = True
    if not allowed:
        metrics.record_auth_event("permission_denied")
        security_logger.warning("trip_scope_denied", extra={"user_id": user.id, "trip_id": trip_id, "path": redact_path(path)})
        raise HTTPException(
            status_code=403,
            detail="Your invitation scope does not allow this action",
        )


def require_admin(user: User = Depends(get_current_user)) -> User:
    if not user.is_admin:
        metrics.record_auth_event("permission_denied")
        security_logger.warning("admin_access_denied", extra={"user_id": user.id})
        raise HTTPException(status_code=403, detail="Administrator access required")
    return user


def get_trip_and_member(
    trip_id: str,
    db: Session,
    user: User,
    roles: set[str] | None = None,
) -> tuple[Trip, TripMember]:
    trip = db.get(Trip, trip_id)
    if not trip or trip.deleted_at:
        raise HTTPException(status_code=404, detail="Trip not found")
    member = (
        db.query(TripMember)
        .filter(
            TripMember.trip_id == trip_id,
            TripMember.user_id == user.id,
            TripMember.status == "active",
        )
        .first()
    )
    if not member:
        # Deliberately 404 rather than 403 so private trip existence is not leaked.
        raise HTTPException(status_code=404, detail="Trip not found")
    if roles and member.role not in roles:
        raise HTTPException(
            status_code=403, detail="Your trip role does not allow this action"
        )
    return trip, member


def trip_dependency(roles: set[str] | None = None) -> Callable:
    """Build a FastAPI dependency that resolves trip + membership."""

    def dependency(
        trip_id: str,
        db: Session = Depends(get_db),
        user: User = Depends(get_current_user),
    ) -> tuple[Trip, TripMember]:
        return get_trip_and_member(trip_id, db, user, roles)

    return dependency
