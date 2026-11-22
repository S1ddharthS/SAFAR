"""In-memory telemetry and operational metrics for SAFAR.

Provides thread-safe metrics collection across HTTP requests, database queries,
authentication events, WebSocket lifecycle, media uploads, and offline sync.
Exposes snapshots for administrative observability without external dependencies.
"""

from collections import deque
from datetime import datetime, timezone
import threading
import time
from typing import Any


class MetricsCollector:
    """Thread-safe in-memory operational metrics collector."""

    def __init__(self, max_latency_samples: int = 200) -> None:
        self._lock = threading.Lock()
        self.started_at: datetime = datetime.now(timezone.utc)
        self.start_monotonic: float = time.monotonic()
        self.max_latency_samples = max_latency_samples

        # HTTP request metrics
        self.requests_total: int = 0
        self.status_2xx: int = 0
        self.status_3xx: int = 0
        self.status_4xx: int = 0
        self.status_5xx: int = 0
        self._latencies: deque[float] = deque(maxlen=max_latency_samples)

        # Security & Auth metrics
        self.auth_login_success: int = 0
        self.auth_login_failure: int = 0
        self.auth_refresh_success: int = 0
        self.auth_refresh_failure: int = 0
        self.auth_refresh_reuse: int = 0
        self.auth_session_revoked: int = 0
        self.csrf_failures: int = 0
        self.rate_limit_exceeded: int = 0
        self.permission_denied: int = 0

        # Database metrics
        self.db_queries_total: int = 0
        self.db_slow_queries_total: int = 0
        self.db_errors_total: int = 0
        self.db_last_query_ms: float = 0.0

        # Realtime / WebSocket metrics
        self.ws_active_connections: int = 0
        self.ws_total_connected: int = 0
        self.ws_total_disconnected: int = 0
        self.ws_total_broadcasts: int = 0
        self.ws_auth_rejected: int = 0

        # Media metrics
        self.media_uploads_success: int = 0
        self.media_uploads_rejected_size: int = 0
        self.media_uploads_rejected_mime: int = 0

        # Offline sync metrics
        self.sync_batches_total: int = 0
        self.sync_items_applied: int = 0
        self.sync_items_rejected: int = 0
        self.sync_items_skipped: int = 0

    def record_http_request(self, method: str, path: str, status_code: int, duration_ms: float) -> None:
        with self._lock:
            self.requests_total += 1
            if 200 <= status_code < 300:
                self.status_2xx += 1
            elif 300 <= status_code < 400:
                self.status_3xx += 1
            elif 400 <= status_code < 500:
                self.status_4xx += 1
            elif status_code >= 500:
                self.status_5xx += 1
            self._latencies.append(duration_ms)

    def record_auth_event(self, event_type: str) -> None:
        with self._lock:
            if event_type == "login_success":
                self.auth_login_success += 1
            elif event_type == "login_failure":
                self.auth_login_failure += 1
            elif event_type == "refresh_success":
                self.auth_refresh_success += 1
            elif event_type == "refresh_failure":
                self.auth_refresh_failure += 1
            elif event_type == "refresh_reuse":
                self.auth_refresh_reuse += 1
            elif event_type == "session_revoked":
                self.auth_session_revoked += 1
            elif event_type == "csrf_failure":
                self.csrf_failures += 1
            elif event_type == "rate_limit_exceeded":
                self.rate_limit_exceeded += 1
            elif event_type == "permission_denied":
                self.permission_denied += 1

    def record_db_query(self, duration_ms: float, is_slow: bool = False) -> None:
        with self._lock:
            self.db_queries_total += 1
            self.db_last_query_ms = round(duration_ms, 2)
            if is_slow:
                self.db_slow_queries_total += 1

    def record_db_error(self) -> None:
        with self._lock:
            self.db_errors_total += 1

    def record_ws_connect(self) -> None:
        with self._lock:
            self.ws_active_connections += 1
            self.ws_total_connected += 1

    def record_ws_disconnect(self) -> None:
        with self._lock:
            if self.ws_active_connections > 0:
                self.ws_active_connections -= 1
            self.ws_total_disconnected += 1

    def record_ws_auth_rejected(self) -> None:
        with self._lock:
            self.ws_auth_rejected += 1

    def record_ws_broadcast(self) -> None:
        with self._lock:
            self.ws_total_broadcasts += 1

    def record_media_upload(self, status: str) -> None:
        with self._lock:
            if status == "success":
                self.media_uploads_success += 1
            elif status == "rejected_size":
                self.media_uploads_rejected_size += 1
            elif status == "rejected_mime":
                self.media_uploads_rejected_mime += 1

    def record_sync_batch(self, applied: int, rejected: int, skipped: int) -> None:
        with self._lock:
            self.sync_batches_total += 1
            self.sync_items_applied += applied
            self.sync_items_rejected += rejected
            self.sync_items_skipped += skipped

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            uptime_seconds = round(time.monotonic() - self.start_monotonic, 1)
            avg_latency = (
                round(sum(self._latencies) / len(self._latencies), 2)
                if self._latencies
                else 0.0
            )
            return {
                "started_at": self.started_at.isoformat(),
                "uptime_seconds": uptime_seconds,
                "http": {
                    "requests_total": self.requests_total,
                    "status_2xx": self.status_2xx,
                    "status_3xx": self.status_3xx,
                    "status_4xx": self.status_4xx,
                    "status_5xx": self.status_5xx,
                    "avg_latency_ms": avg_latency,
                },
                "security": {
                    "auth_login_success": self.auth_login_success,
                    "auth_login_failure": self.auth_login_failure,
                    "auth_refresh_success": self.auth_refresh_success,
                    "auth_refresh_failure": self.auth_refresh_failure,
                    "auth_refresh_reuse": self.auth_refresh_reuse,
                    "auth_session_revoked": self.auth_session_revoked,
                    "csrf_failures": self.csrf_failures,
                    "rate_limit_exceeded": self.rate_limit_exceeded,
                    "permission_denied": self.permission_denied,
                },
                "database": {
                    "queries_total": self.db_queries_total,
                    "slow_queries_total": self.db_slow_queries_total,
                    "errors_total": self.db_errors_total,
                    "last_query_ms": self.db_last_query_ms,
                },
                "realtime": {
                    "active_connections": self.ws_active_connections,
                    "total_connected": self.ws_total_connected,
                    "total_disconnected": self.ws_total_disconnected,
                    "total_broadcasts": self.ws_total_broadcasts,
                    "auth_rejected": self.ws_auth_rejected,
                },
                "media": {
                    "uploads_success": self.media_uploads_success,
                    "uploads_rejected_size": self.media_uploads_rejected_size,
                    "uploads_rejected_mime": self.media_uploads_rejected_mime,
                },
                "sync": {
                    "batches_total": self.sync_batches_total,
                    "items_applied": self.sync_items_applied,
                    "items_rejected": self.sync_items_rejected,
                    "items_skipped": self.sync_items_skipped,
                },
            }

    def reset_for_tests(self) -> None:
        with self._lock:
            self.requests_total = 0
            self.status_2xx = 0
            self.status_3xx = 0
            self.status_4xx = 0
            self.status_5xx = 0
            self._latencies.clear()
            self.auth_login_success = 0
            self.auth_login_failure = 0
            self.auth_refresh_success = 0
            self.auth_refresh_failure = 0
            self.auth_refresh_reuse = 0
            self.auth_session_revoked = 0
            self.csrf_failures = 0
            self.rate_limit_exceeded = 0
            self.permission_denied = 0
            self.db_queries_total = 0
            self.db_slow_queries_total = 0
            self.db_errors_total = 0
            self.db_last_query_ms = 0.0
            self.ws_active_connections = 0
            self.ws_total_connected = 0
            self.ws_total_disconnected = 0
            self.ws_total_broadcasts = 0
            self.ws_auth_rejected = 0
            self.media_uploads_success = 0
            self.media_uploads_rejected_size = 0
            self.media_uploads_rejected_mime = 0
            self.sync_batches_total = 0
            self.sync_items_applied = 0
            self.sync_items_rejected = 0
            self.sync_items_skipped = 0


metrics = MetricsCollector()
