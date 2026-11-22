import logging
from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy.orm import Session

from app.core.alerting import AlertCategory, AlertSeverity, alert_manager
from app.core.config import settings
from app.core.cookies import clear_auth_cookies, set_auth_cookies
from app.core.deps import bearer, csrf_valid, get_current_user, get_db
from app.core.metrics import metrics
from app.core.security import (
    create_access_token,
    create_ws_ticket,
    decode_access_token,
    hash_client_ip,
    hash_password,
    new_csrf_token,
    verify_password,
)

auth_logger = logging.getLogger("safar.auth")
from app.db.context import auth_context, set_user_context
from app.models import ConsentRecord, JourneyDNA, Profile, User
from app.schemas.schemas import LoginIn, RegisterIn
from app.services.auth_sessions import (
    create_session,
    revoke_session,
    rotate_refresh_token,
)
from app.services.common import default_dna
from app.services.serializers import user_out

router = APIRouter(prefix="/api/auth", tags=["auth"])


def _start_session(
    response: Response, db: Session, user: User, request: Request
) -> dict:
    set_user_context(db, user.id, user.is_admin)
    session, refresh_token = create_session(db, user, request)
    access_token = create_access_token(user.id, user.email, session_id=session.id)
    csrf_token = new_csrf_token()
    db.commit()
    set_auth_cookies(response, access_token, refresh_token, csrf_token)
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "expires_in": settings.access_token_expire_minutes * 60,
        "csrf_token": csrf_token,
        "user": user_out(user),
    }


@router.post("/register", status_code=status.HTTP_201_CREATED)
def register(
    payload: RegisterIn,
    request: Request,
    response: Response,
    db: Session = Depends(get_db),
):
    auth_context(db)
    email = payload.email.lower().strip()
    if db.query(User).filter(User.email == email).first():
        raise HTTPException(status_code=409, detail="An account with this email already exists")
    user = User(
        email=email,
        password_hash=hash_password(payload.password),
        display_name=payload.display_name.strip(),
    )
    db.add(user)
    db.flush()
    set_user_context(db, user.id)
    db.add(Profile(user_id=user.id, interests=[]))
    db.add(JourneyDNA(user_id=user.id, scores=default_dna(), source="explicit"))
    db.add(
        ConsentRecord(
            user_id=user.id,
            kind="terms",
            granted=True,
            policy_version=settings.policy_version,
        )
    )
    for kind in ("personalization", "analytics", "location", "marketing"):
        db.add(
            ConsentRecord(
                user_id=user.id,
                kind=kind,
                granted=False,
                policy_version=settings.policy_version,
            )
        )
    db.commit()
    return _start_session(response, db, user, request)


@router.post("/login")
def login(
    payload: LoginIn,
    request: Request,
    response: Response,
    db: Session = Depends(get_db),
):
    auth_context(db)
    email = payload.email.lower().strip()
    user = db.query(User).filter(User.email == email).first()
    if not user or not verify_password(payload.password, user.password_hash):
        metrics.record_auth_event("login_failure")
        client_hash = hash_client_ip(request.client.host if request.client else "")[:16]
        auth_logger.warning("auth_login_failure", extra={"client": client_hash, "path": "/api/auth/login"})
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Incorrect email or password"
        )
    if not user.is_active or user.deleted_at:
        metrics.record_auth_event("login_failure")
        auth_logger.warning("auth_login_inactive", extra={"user_id": user.id, "path": "/api/auth/login"})
        raise HTTPException(status_code=403, detail="This account is no longer active")
    set_user_context(db, user.id, user.is_admin)
    metrics.record_auth_event("login_success")
    auth_logger.info("auth_login_success", extra={"user_id": user.id, "path": "/api/auth/login"})
    return _start_session(response, db, user, request)


@router.post("/refresh")
def refresh(request: Request, response: Response, db: Session = Depends(get_db)):
    auth_context(db)
    token = request.cookies.get(settings.refresh_cookie)
    if not token:
        metrics.record_auth_event("refresh_failure")
        auth_logger.info("auth_refresh_missing", extra={"path": "/api/auth/refresh"})
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="No refresh session"
        )
    session, new_refresh, user = rotate_refresh_token(db, token, request)
    if not session or not user:
        clear_auth_cookies(response)
        metrics.record_auth_event("refresh_failure")
        auth_logger.warning("auth_refresh_rejected", extra={"path": "/api/auth/refresh"})
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session expired or revoked. Sign in again.",
        )
    set_user_context(db, user.id, user.is_admin)
    access_token = create_access_token(user.id, user.email, session_id=session.id)
    csrf_token = new_csrf_token()
    set_auth_cookies(response, access_token, new_refresh, csrf_token)
    metrics.record_auth_event("refresh_success")
    auth_logger.info("auth_refresh_success", extra={"user_id": user.id, "path": "/api/auth/refresh"})
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "expires_in": settings.access_token_expire_minutes * 60,
        "csrf_token": csrf_token,
        "user": user_out(user),
    }


@router.get("/me")
def me(user: User = Depends(get_current_user)):
    return user_out(user)


@router.post("/ws-ticket")
def ws_ticket(
    request: Request,
    user: User = Depends(get_current_user),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
):
    from app.core.deps import _token_from_request

    token, _ = _token_from_request(request, credentials)
    payload = decode_access_token(token or "")
    session_id = payload.get("sid") if payload else None
    if not session_id:
        raise HTTPException(status_code=400, detail="Sign in again to open live updates")
    return {"ticket": create_ws_ticket(user.id, session_id), "expires_in": 120}


@router.post("/logout")
def logout(
    request: Request,
    response: Response,
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
):
    from app.core.deps import _token_from_request

    auth_context(db)
    token, source = _token_from_request(request, credentials)
    if source == "cookie" and not csrf_valid(request):
        raise HTTPException(status_code=403, detail="CSRF validation failed")

    revoked = False
    refresh_token = request.cookies.get(settings.refresh_cookie)
    if refresh_token:
        session_id = refresh_token.partition(".")[0]
        if session_id:
            revoke_session(db, session_id)
            revoked = True
    if token:
        payload = decode_access_token(token)
        session_id = payload.get("sid") if payload else None
        if session_id:
            revoke_session(db, session_id)
            revoked = True
    clear_auth_cookies(response)
    if revoked:
        metrics.record_auth_event("session_revoked")
    auth_logger.info("auth_logout", extra={"path": "/api/auth/logout", "revoked": revoked})
    # Idempotent on purpose: logging out an already-cleared browser must not fail.
    return {"ok": True, "revoked": revoked}
