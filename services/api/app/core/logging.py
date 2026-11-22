"""Structured JSON logging with request correlation and sensitive-data redaction.

Request bodies, cookies, authorization headers and raw query tokens are never
logged. Companion, invitation and media signatures are redacted before reaching
the log stream.
"""

from contextvars import ContextVar
import json
import logging
import re
import sys
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from app.core.config import settings

request_id_var: ContextVar[str] = ContextVar("request_id", default="-")

REDACTED_SEGMENTS = {"companion", "invitations", "media", "invite"}
REDACTED = "<redacted>"

SENSITIVE_KEYS = {
    "password",
    "password_hash",
    "access_token",
    "refresh_token",
    "token",
    "ticket",
    "csrf_token",
    "authorization",
    "cookie",
    "secret",
    "secret_key",
    "sig",
    "signature",
    "text_content",
    "lat",
    "lon",
    "coordinates",
    "private_memory",
}

SENSITIVE_QUERY_PARAMS = {"token", "ticket", "sig", "signature", "key", "secret", "password"}


def redact_path(path: str) -> str:
    """Redacts sensitive path segments and query parameters."""
    if not path:
        return ""

    # Split off query string if present
    parts = urlsplit(path)
    clean_path = parts.path
    path_segments = clean_path.split("/")

    # /api/<segment>/<token>...
    if len(path_segments) > 3 and path_segments[1] == "api" and path_segments[2] in REDACTED_SEGMENTS:
        path_segments[3] = REDACTED
    # /api/trips/<trip_id>/invitations/<token>
    elif (
        len(path_segments) > 5
        and path_segments[1] == "api"
        and path_segments[2] == "trips"
        and path_segments[4] == "invitations"
    ):
        path_segments[5] = REDACTED

    sanitized_path = "/".join(path_segments)

    if parts.query:
        query_pairs = parse_qsl(parts.query, keep_blank_values=True)
        sanitized_pairs = [
            (k, REDACTED if k.lower() in SENSITIVE_QUERY_PARAMS else v)
            for k, v in query_pairs
        ]
        sanitized_query = urlencode(sanitized_pairs)
        return urlunsplit(("", "", sanitized_path, sanitized_query, ""))

    return sanitized_path


def redact_sensitive_dict(data: dict) -> dict:
    """Recursively redacts known sensitive fields from dictionaries."""
    sanitized = {}
    for k, v in data.items():
        if k.lower() in SENSITIVE_KEYS:
            sanitized[k] = REDACTED
        elif isinstance(v, dict):
            sanitized[k] = redact_sensitive_dict(v)
        elif isinstance(v, list):
            sanitized[k] = [
                redact_sensitive_dict(item) if isinstance(item, dict) else item
                for item in v
            ]
        else:
            sanitized[k] = v
    return sanitized


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "environment": settings.environment,
            "logger": record.name,
            "message": record.getMessage(),
            "request_id": request_id_var.get(),
        }
        for key in ("method", "path", "status", "duration_ms", "client", "operation", "category"):
            value = getattr(record, key, None)
            if value is not None:
                if key == "path" and isinstance(value, str):
                    payload[key] = redact_path(value)
                else:
                    payload[key] = value

        for extra_key in ("details", "alert", "security", "metrics"):
            extra_val = getattr(record, extra_key, None)
            if extra_val is not None and isinstance(extra_val, dict):
                payload[extra_key] = redact_sensitive_dict(extra_val)

        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False, default=str)


def configure_logging() -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(settings.log_level)
    # Uvicorn's access log would print raw paths (including one-use tokens),
    # so the request middleware emits the sanitised access log instead.
    access = logging.getLogger("uvicorn.access")
    access.handlers[:] = []
    access.propagate = False
    access.disabled = True


def install_error_monitor() -> None:
    """Initialise an error monitor when a provider is explicitly configured.

    SAFAR ships without a paid monitoring dependency. If ``sentry-sdk`` is
    installed and ``SENTRY_DSN`` is set, it is initialised; otherwise this is
    a no-op and operators can attach their own handler to the ``safar.error``
    logger documented in SECURITY.md.
    """
    dsn = settings.sentry_dsn
    if not dsn:
        return
    try:  # pragma: no cover - optional dependency
        import sentry_sdk

        sentry_sdk.init(
            dsn=dsn,
            environment=settings.environment,
            release=settings.release,
            traces_sample_rate=0.0,
            send_default_pii=False,
        )
    except Exception:  # pragma: no cover - never block startup on telemetry
        logging.getLogger("safar.error").warning(
            "sentry_not_initialised",
            extra={"reason": "sentry-sdk missing or invalid SENTRY_DSN"},
        )
