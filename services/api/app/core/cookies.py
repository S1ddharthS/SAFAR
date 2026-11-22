"""HttpOnly session cookies and the readable CSRF double-submit token."""

from fastapi import Response

from app.core.config import settings

_ACCESS_MAX_AGE = settings.access_token_expire_minutes * 60
_REFRESH_MAX_AGE = settings.refresh_token_expire_days * 24 * 60 * 60


def _common(path: str, samesite: str) -> dict:
    values = {
        "path": path,
        "secure": settings.cookie_secure,
        "samesite": samesite,
    }
    if settings.cookie_domain:
        values["domain"] = settings.cookie_domain
    return values


def set_auth_cookies(
    response: Response,
    access_token: str,
    refresh_token: str,
    csrf_token: str,
) -> None:
    response.set_cookie(
        settings.access_cookie,
        access_token,
        max_age=_ACCESS_MAX_AGE,
        httponly=True,
        **_common("/", settings.cookie_samesite),
    )
    response.set_cookie(
        settings.refresh_cookie,
        refresh_token,
        max_age=_REFRESH_MAX_AGE,
        httponly=True,
        **_common("/api/auth", settings.cookie_samesite),
    )
    # Readable by the SPA so it can echo the value in X-CSRF-Token.
    response.set_cookie(
        settings.csrf_cookie,
        csrf_token,
        max_age=_REFRESH_MAX_AGE,
        httponly=False,
        **_common("/", settings.cookie_samesite),
    )


def clear_auth_cookies(response: Response) -> None:
    response.delete_cookie(
        settings.access_cookie, **_common("/", settings.cookie_samesite)
    )
    response.delete_cookie(
        settings.refresh_cookie, **_common("/api/auth", settings.cookie_samesite)
    )
    response.delete_cookie(
        settings.csrf_cookie, **_common("/", settings.cookie_samesite)
    )
