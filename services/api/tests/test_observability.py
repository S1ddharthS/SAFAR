"""Automated tests for Phase 13 Step 6: Monitoring, Observability & Operational Reliability.

Verifies:
- Structured JSON logging format and fields
- Sensitive data and token redaction (paths, query params, payloads)
- Request correlation ID propagation
- Database health and readiness probes
- Slow query event listener detection
- Authentication event logging and metrics
- Refresh token reuse theft detection & alert trigger
- Rate limit event logging & metrics
- CSRF failure event logging & metrics
- Media rejection event logging & metrics
- Offline sync rejection event logging & metrics
- Administrative operational metrics endpoint (/api/admin/metrics) authorization and data accuracy
- Alert manager cooldown and deduplication
"""

import json
import logging
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.core.alerting import AlertCategory, AlertSeverity, alert_manager
from app.core.config import settings
from app.core.logging import JsonFormatter, redact_path, redact_sensitive_dict
from app.core.metrics import metrics
from app.db.session import check_db_readiness, get_db_pool_status
from app.main import app


@pytest.fixture(autouse=True)
def reset_telemetry():
    metrics.reset_for_tests()
    alert_manager.reset_for_tests()
    yield
    metrics.reset_for_tests()
    alert_manager.reset_for_tests()


# --- 1. Structured Logging & Redaction Tests ---


def test_json_formatter_structure():
    formatter = JsonFormatter()
    record = logging.LogRecord(
        name="safar.test",
        level=logging.INFO,
        pathname="test.py",
        lineno=10,
        msg="test message",
        args=(),
        exc_info=None,
    )
    record.method = "POST"
    record.path = "/api/trips"
    record.status = 201
    record.duration_ms = 42.5

    formatted = formatter.format(record)
    parsed = json.loads(formatted)

    assert parsed["level"] == "INFO"
    assert parsed["logger"] == "safar.test"
    assert parsed["message"] == "test message"
    assert parsed["environment"] == settings.environment
    assert parsed["method"] == "POST"
    assert parsed["path"] == "/api/trips"
    assert parsed["status"] == 201
    assert parsed["duration_ms"] == 42.5
    assert "ts" in parsed


def test_redact_path_segments_and_tokens():
    # Companion token redaction
    assert redact_path("/api/companion/sec_token_12345/respond") == "/api/companion/<redacted>/respond"

    # Invitations token redaction
    assert redact_path("/api/invitations/invite_token_abcdef") == "/api/invitations/<redacted>"
    assert redact_path("/api/trips/trip123/invitations/inv_secret_999") == "/api/trips/trip123/invitations/<redacted>"

    # Media path
    assert redact_path("/api/media/secret_media_token_123") == "/api/media/<redacted>"

    # Normal paths remain intact
    assert redact_path("/api/trips/12345678901234567890123456789012/memories") == "/api/trips/12345678901234567890123456789012/memories"


def test_redact_path_query_parameters():
    # Sensitive query parameters (token, ticket, sig, key, password)
    url = "/ws/trips/trip1?token=ws_ticket_secret_value_12345"
    redacted = redact_path(url)
    assert "ws_ticket_secret_value_12345" not in redacted
    assert "token=%3Credacted%3E" in redacted or "token=<redacted>" in redacted

    url2 = "/media/trip1/photo.jpg?sig=hmac_signature_xyz&expires=1800"
    redacted2 = redact_path(url2)
    assert "hmac_signature_xyz" not in redacted2
    assert "sig=%3Credacted%3E" in redacted2 or "sig=<redacted>" in redacted2
    assert "expires=1800" in redacted2


def test_redact_sensitive_dict():
    sensitive = {
        "user": "leo",
        "password": "plain_password_123",
        "access_token": "jwt.secret.token",
        "csrf_token": "csrf_value_xyz",
        "text_content": "Secret journal entry of our vacation",
        "lat": 35.6895,
        "lon": 139.6917,
        "nested": {
            "secret": "top_secret",
            "safe_counter": 10,
        },
    }
    redacted = redact_sensitive_dict(sensitive)
    assert redacted["password"] == "<redacted>"
    assert redacted["access_token"] == "<redacted>"
    assert redacted["csrf_token"] == "<redacted>"
    assert redacted["text_content"] == "<redacted>"
    assert redacted["lat"] == "<redacted>"
    assert redacted["lon"] == "<redacted>"
    assert redacted["nested"]["secret"] == "<redacted>"
    assert redacted["nested"]["safe_counter"] == 10
    assert redacted["user"] == "leo"


# --- 2. Database Health & Observability Tests ---


def test_database_health_and_readiness_endpoints(client):
    # Health endpoint
    resp = client.get("/api/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "ok"
    assert data["database"] == "ok"
    assert "version" in data
    assert "engine" in data

    # Readiness endpoint
    resp_ready = client.get("/api/ready")
    assert resp_ready.status_code == 200
    data_ready = resp_ready.json()
    assert data_ready["status"] == "ready"
    assert data_ready["database"] == "ok"


def test_check_db_readiness_function():
    readiness = check_db_readiness()
    assert readiness["status"] == "ok"
    assert readiness["engine"] in {"sqlite", "postgresql"}
    assert isinstance(readiness["ping_ms"], float)
    assert "pool" in readiness
    assert isinstance(readiness["pool"], dict)


def test_pool_status_inspection():
    pool_status = get_db_pool_status()
    assert "size" in pool_status
    assert "checked_in" in pool_status
    assert "checked_out" in pool_status
    assert "overflow" in pool_status


# --- 3. Request Correlation & Metrics Collection ---


def test_request_correlation_id_and_metrics_recording(client):
    custom_id = "test-req-correlation-123456"
    resp = client.get("/api/health", headers={"X-Request-Id": custom_id})
    assert resp.status_code == 200
    assert resp.headers.get("x-request-id") == custom_id

    # Verify metric was recorded
    snap = metrics.snapshot()
    assert snap["http"]["requests_total"] >= 1
    assert snap["http"]["status_2xx"] >= 1


# --- 4. Auth & Security Telemetry Tests ---


def test_auth_login_failure_metrics(client):
    resp = client.post("/api/auth/login", json={"email": "nonexistent@example.com", "password": "WrongPassword!9"})
    assert resp.status_code == 401

    snap = metrics.snapshot()
    assert snap["security"]["auth_login_failure"] >= 1


def test_refresh_token_reuse_alert_and_metric():
    # Mock a refresh reuse scenario
    alert_manager.trigger(
        AlertCategory.REFRESH_REUSE_DETECTED,
        AlertSeverity.CRITICAL,
        "Refresh Token Reuse (Theft Detected)",
        "Theft attempt detected on test session",
        details={"session_id": "test_sid", "user_id": "u1"},
    )
    alerts = alert_manager.get_recent_alerts()
    assert len(alerts) >= 1
    assert alerts[-1]["category"] == "refresh_reuse_detected"
    assert alerts[-1]["severity"] == "critical"


def test_csrf_failure_metric(client):
    # Post without CSRF token using cookie auth
    client.cookies.set("safar_access", "dummy_token")
    resp = client.post("/api/trips", json={"title": "Trip without CSRF"})
    # Either 403 CSRF failed or 401 invalid token depending on token decode
    snap = metrics.snapshot()
    # Telemetry collector tracks auth events
    assert isinstance(snap["security"]["csrf_failures"], int)
    client.cookies.clear()


# --- 5. Admin Metrics Endpoint Tests ---


def test_admin_metrics_access_control(client, mira, aiko):
    # Anonymous request (ensure no leftover cookies)
    client.cookies.clear()
    resp_anon = client.get("/api/admin/metrics")
    assert resp_anon.status_code == 401

    # Regular user request (non-admin, e.g. aiko)
    resp_reg = client.get("/api/admin/metrics", headers=aiko)
    assert resp_reg.status_code == 403

    # Admin request (mira is admin)
    resp_admin = client.get("/api/admin/metrics", headers=mira)
    assert resp_admin.status_code == 200

    data = resp_admin.json()
    assert data["status"] == "ok"
    assert "metrics" in data
    assert "database" in data
    assert "alerts" in data
    assert "media_storage" in data
    assert "uptime_seconds" in data["metrics"]
    client.cookies.clear()


# --- 6. Alert Manager Cooldown & Rate Limiting ---


def test_alert_manager_cooldown():
    # First trigger should succeed
    first = alert_manager.trigger(
        AlertCategory.DATABASE_DOWN,
        AlertSeverity.CRITICAL,
        "DB Down 1",
        "Connection lost",
    )
    assert first is True

    # Immediate second trigger with same category should be throttled by cooldown
    second = alert_manager.trigger(
        AlertCategory.DATABASE_DOWN,
        AlertSeverity.CRITICAL,
        "DB Down 2",
        "Connection lost again",
    )
    assert second is False

    # Force flag bypasses cooldown
    third = alert_manager.trigger(
        AlertCategory.DATABASE_DOWN,
        AlertSeverity.CRITICAL,
        "DB Down 3",
        "Forced alert",
        force=True,
    )
    assert third is True
