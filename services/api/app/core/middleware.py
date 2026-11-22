"""Cross-cutting HTTP hardening: request correlation, headers, body limits."""

import json
import logging
import re
import time
import uuid

from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.alerting import AlertCategory, AlertSeverity, alert_manager
from app.core.config import settings
from app.core.logging import redact_path, request_id_var
from app.core.metrics import metrics
from app.core.security import hash_client_ip

REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]{8,64}$")
REQUEST_ID_HEADER = settings.request_id_header.lower().encode()
access_logger = logging.getLogger("safar.access")
error_logger = logging.getLogger("safar.error")

SECURITY_HEADERS = [
    (b"x-content-type-options", b"nosniff"),
    (b"x-frame-options", b"DENY"),
    (b"referrer-policy", b"no-referrer"),
    (
        b"permissions-policy",
        b"geolocation=(self), camera=(), microphone=(), payment=(), usb=()",
    ),
    (b"cross-origin-opener-policy", b"same-origin"),
    (b"cross-origin-resource-policy", b"same-site"),
    (
        b"content-security-policy",
        b"default-src 'none'; img-src 'self' data:; media-src 'self'; "
        b"style-src 'unsafe-inline'; base-uri 'none'; form-action 'self'; "
        b"frame-ancestors 'none'",
    ),
]

DOC_PATHS = ("/api/docs", "/api/openapi.json")


def _request_id(scope: Scope) -> str:
    for key, value in scope.get("headers", []):
        if key == REQUEST_ID_HEADER:
            candidate = value.decode("latin-1").strip()
            if REQUEST_ID_PATTERN.match(candidate):
                return candidate
    return uuid.uuid4().hex


class RequestContextMiddleware:
    """Outermost user middleware: request id, access log and safe errors."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        request_id = _request_id(scope)
        token = request_id_var.set(request_id)
        path = scope.get("path", "")
        method = scope.get("method", "")
        client = scope.get("client")
        client_hash = hash_client_ip(client[0])[:16] if client else "-"
        started = time.perf_counter()
        state = {"status": 500, "started": False}

        async def send_wrapper(message: Message) -> None:
            if message["type"] == "http.response.start":
                state["started"] = True
                state["status"] = message["status"]
                headers = list(message.get("headers", []))
                present = {key.lower() for key, _ in headers}
                headers.append((b"x-request-id", request_id.encode()))
                for key, value in SECURITY_HEADERS:
                    is_doc = any(path.startswith(prefix) for prefix in DOC_PATHS)
                    if key == b"content-security-policy" and is_doc:
                        continue
                    if key not in present:
                        headers.append((key, value))
                if path.startswith("/api") and b"cache-control" not in present:
                    headers.append((b"cache-control", b"no-store"))
                elif path.startswith("/media/") and b"cache-control" not in present:
                    headers.append((b"cache-control", b"private, no-store"))
                if settings.is_production and scope.get("scheme") == "https":
                    if b"strict-transport-security" not in present:
                        headers.append(
                            (
                                b"strict-transport-security",
                                b"max-age=31536000; includeSubDomains",
                            )
                        )
                message = {**message, "headers": headers}
            await send(message)

        try:
            await self.app(scope, receive, send_wrapper)
        except Exception:
            error_logger.exception(
                "unhandled_error",
                extra={"method": method, "path": redact_path(path), "client": client_hash},
            )
            if not state["started"]:
                payload = json.dumps(
                    {
                        "detail": "Internal server error",
                        "request_id": request_id,
                    }
                ).encode()
                await send(
                    {
                        "type": "http.response.start",
                        "status": 500,
                        "headers": [
                            (b"content-type", b"application/json"),
                            (b"content-length", str(len(payload)).encode()),
                            (b"x-request-id", request_id.encode()),
                        ],
                    }
                )
                await send({"type": "http.response.body", "body": payload})
            state["status"] = state["status"] if state["started"] else 500
        finally:
            duration_ms = round((time.perf_counter() - started) * 1000, 2)
            final_status = state["status"] if state["started"] else 500
            metrics.record_http_request(method, redact_path(path), final_status, duration_ms)
            if final_status >= 500:
                alert_manager.trigger(
                    AlertCategory.HIGH_API_ERROR_RATE,
                    AlertSeverity.WARNING,
                    "API 5xx Server Error",
                    f"HTTP {final_status} on {method} {redact_path(path)} ({duration_ms}ms)",
                    details={"method": method, "path": redact_path(path), "status": final_status},
                )
            access_logger.info(
                "request",
                extra={
                    "method": method,
                    "path": redact_path(path),
                    "status": final_status,
                    "duration_ms": duration_ms,
                    "client": client_hash,
                },
            )
            request_id_var.reset(token)


class BodyTooLarge(Exception):
    pass


class BodySizeLimitMiddleware:
    """Reject oversized bodies before they reach application code."""

    def __init__(self, app: ASGIApp, max_bytes: int | None = None) -> None:
        self.app = app
        self.max_bytes = max_bytes or settings.max_request_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        headers = {key.lower(): value for key, value in scope.get("headers", [])}
        declared = headers.get(b"content-length")
        if declared:
            try:
                if int(declared) > self.max_bytes:
                    await self._reject(send)
                    return
            except ValueError:
                await self._reject(send)
                return

        received = 0
        response_started = False

        async def limited_receive() -> Message:
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > self.max_bytes:
                    raise BodyTooLarge()
            return message

        async def tracking_send(message: Message) -> None:
            nonlocal response_started
            if message["type"] == "http.response.start":
                response_started = True
            await send(message)

        try:
            await self.app(scope, limited_receive, tracking_send)
        except BodyTooLarge:
            if not response_started:
                await self._reject(send)

    async def _reject(self, send: Send) -> None:
        payload = json.dumps({"detail": "Request body too large"}).encode()
        await send(
            {
                "type": "http.response.start",
                "status": 413,
                "headers": [
                    (b"content-type", b"application/json"),
                    (b"content-length", str(len(payload)).encode()),
                ],
            }
        )
        await send({"type": "http.response.body", "body": payload})
