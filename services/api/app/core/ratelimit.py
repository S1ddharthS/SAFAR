"""Per-IP sliding-window rate limiting.

Single-process in-memory limiter: adequate for one API instance. Horizontal
scaling needs a shared limiter at the gateway or a Redis-backed limiter; both
are documented in DEPLOYMENT.md. Health endpoints are exempt so probes never
consume the budget.
"""

import logging
import time
from collections import defaultdict, deque

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

from .alerting import AlertCategory, AlertSeverity, alert_manager
from .config import settings
from .logging import redact_path
from .metrics import metrics
from .security import hash_client_ip

security_logger = logging.getLogger("safar.security")

WINDOW_SECONDS = 60.0
MAX_TRACKED_CLIENTS = 20_000
EXEMPT_PATHS = {"/api/health", "/api/ready", "/api/openapi.json"}


def _client_ip(request: Request) -> str:
    if settings.trust_proxy_headers:
        forwarded = request.headers.get("x-forwarded-for")
        if forwarded:
            candidate = forwarded.split(",")[0].strip()
            if candidate:
                return candidate
    return request.client.host if request.client else "unknown"


def _bucket_for(path: str, method: str) -> tuple[str, int]:
    if path in {"/api/auth/login", "/api/auth/register", "/api/auth/refresh", "/api/auth/logout"}:
        return "auth", settings.auth_rate_limit_per_minute
    if path.startswith("/api/companion/") and path.endswith("/respond") and method == "POST":
        return "companion", settings.companion_rate_limit_per_minute
    if method == "POST" and (
        path.endswith("/media") or path.endswith("/memories") or path.endswith("/sync")
    ):
        return "upload", settings.upload_rate_limit_per_minute
    return "default", settings.rate_limit_per_minute


class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app):
        super().__init__(app)
        self._hits: dict[tuple[str, str], deque[float]] = defaultdict(deque)

    def _trim(self, now: float) -> None:
        if len(self._hits) <= MAX_TRACKED_CLIENTS:
            return
        for key in [key for key, window in self._hits.items() if not window]:
            self._hits.pop(key, None)
        while len(self._hits) > MAX_TRACKED_CLIENTS:
            self._hits.pop(next(iter(self._hits)))

    async def dispatch(self, request: Request, call_next):
        path = request.url.path
        if not path.startswith("/api") or request.method == "OPTIONS" or path in EXEMPT_PATHS:
            return await call_next(request)

        now = time.monotonic()
        bucket, limit = _bucket_for(path, request.method)
        key = (_client_ip(request), bucket)
        window = self._hits[key]
        while window and now - window[0] > WINDOW_SECONDS:
            window.popleft()
        if len(window) >= limit:
            retry_after = max(1, int(WINDOW_SECONDS - (now - window[0])) + 1)
            client_hash = hash_client_ip(_client_ip(request))[:16]
            metrics.record_auth_event("rate_limit_exceeded")
            security_logger.warning(
                "rate_limit_exceeded",
                extra={
                    "bucket": bucket,
                    "limit": limit,
                    "client": client_hash,
                    "path": redact_path(path),
                },
            )
            if bucket == "auth":
                alert_manager.trigger(
                    AlertCategory.HIGH_AUTH_FAILURES,
                    AlertSeverity.WARNING,
                    "Auth Rate Limit Triggered",
                    f"Client {client_hash} exceeded auth rate limit of {limit}/min on {redact_path(path)}",
                    details={"bucket": bucket, "client": client_hash, "path": redact_path(path)},
                )
            return JSONResponse(
                status_code=429,
                headers={"Retry-After": str(retry_after)},
                content={"detail": "Too many requests. Please slow down."},
            )
        window.append(now)
        self._trim(now)
        return await call_next(request)
