"""Operational alerting abstraction for SAFAR.

Supports configurable alerting on critical operational failures:
- Database connectivity failures
- Repeated authentication failures (brute-force / credential stuffing)
- Refresh token reuse (session theft detection)
- High API error rates (5xx spikes)
- Repeated media upload failures
- Persistent offline synchronization errors
- Backup execution failures

Does NOT send real outbound network traffic unless ALERT_WEBHOOK_URL is
explicitly configured. Dispatches structured logs to 'safar.alert' with
automatic cooldown / rate-limiting to prevent alert fatigue.
"""

from collections import deque
from datetime import datetime, timezone
from enum import Enum
import json
import logging
import threading
import time
from typing import Any

alert_logger = logging.getLogger("safar.alert")


class AlertSeverity(str, Enum):
    INFO = "info"
    WARNING = "warning"
    CRITICAL = "critical"


class AlertCategory(str, Enum):
    DATABASE_DOWN = "database_down"
    SLOW_QUERY = "slow_query"
    HIGH_AUTH_FAILURES = "high_auth_failures"
    REFRESH_REUSE_DETECTED = "refresh_reuse_detected"
    HIGH_API_ERROR_RATE = "high_api_error_rate"
    SECURITY_VIOLATION = "security_violation"
    MEDIA_UPLOAD_FAILURES = "media_upload_failures"
    BACKUP_FAILED = "backup_failed"
    OFFLINE_SYNC_PERSISTENT_FAILURES = "offline_sync_persistent_failures"


class AlertRecord:
    def __init__(
        self,
        category: AlertCategory,
        severity: AlertSeverity,
        title: str,
        message: str,
        details: dict[str, Any] | None = None,
    ) -> None:
        self.timestamp = datetime.now(timezone.utc).isoformat()
        self.category = category.value
        self.severity = severity.value
        self.title = title
        self.message = message
        self.details = details or {}

    def to_dict(self) -> dict[str, Any]:
        return {
            "timestamp": self.timestamp,
            "category": self.category,
            "severity": self.severity,
            "title": self.title,
            "message": self.message,
            "details": self.details,
        }


class AlertManager:
    """Manages operational alerts with debounce and rate limiting."""

    def __init__(self, cooldown_seconds: float = 300.0, max_history: int = 50) -> None:
        self.cooldown_seconds = cooldown_seconds
        self.max_history = max_history
        self._lock = threading.Lock()
        self._last_alert_times: dict[str, float] = {}
        self._recent_alerts: deque[dict[str, Any]] = deque(maxlen=max_history)

    def trigger(
        self,
        category: AlertCategory,
        severity: AlertSeverity,
        title: str,
        message: str,
        details: dict[str, Any] | None = None,
        force: bool = False,
    ) -> bool:
        """Triggers an alert. Returns True if emitted, False if throttled by cooldown."""
        now = time.monotonic()
        with self._lock:
            last_time = self._last_alert_times.get(category.value, 0.0)
            if not force and (now - last_time < self.cooldown_seconds):
                return False
            self._last_alert_times[category.value] = now

            record = AlertRecord(category, severity, title, message, details)
            alert_dict = record.to_dict()
            self._recent_alerts.append(alert_dict)

        # Emit structured log
        log_level = logging.CRITICAL if severity == AlertSeverity.CRITICAL else logging.WARNING
        alert_logger.log(
            log_level,
            f"ALERT: {title} - {message}",
            extra={"alert": alert_dict},
        )

        # Webhook dispatch (optional, only when explicitly configured)
        from app.core.config import settings

        if getattr(settings, "alert_webhook_url", None):
            self._dispatch_webhook(settings.alert_webhook_url, alert_dict)

        return True

    def _dispatch_webhook(self, webhook_url: str, alert_dict: dict[str, Any]) -> None:
        """Best-effort webhook delivery in background thread without blocking."""
        import threading
        import urllib.request

        def _send() -> None:
            try:
                data = json.dumps(alert_dict).encode("utf-8")
                req = urllib.request.Request(
                    webhook_url,
                    data=data,
                    headers={"Content-Type": "application/json", "User-Agent": "SAFAR-AlertManager/1.0"},
                )
                with urllib.request.urlopen(req, timeout=3.0) as resp:
                    pass
            except Exception as exc:
                alert_logger.debug("webhook_dispatch_failed", extra={"error": str(exc)})

        threading.Thread(target=_send, daemon=True).start()

    def get_recent_alerts(self) -> list[dict[str, Any]]:
        with self._lock:
            return list(self._recent_alerts)

    def reset_for_tests(self) -> None:
        with self._lock:
            self._last_alert_times.clear()
            self._recent_alerts.clear()


alert_manager = AlertManager()
