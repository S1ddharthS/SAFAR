"""Phase 5 security regressions.

Each test pins one production-hardening guarantee so it cannot regress:
response headers, request correlation, body limits, host validation, upload
sniffing, rate limiting, CSRF, session rotation/revocation, anonymous
restrictions, mass assignment and malicious input handling.
"""

from __future__ import annotations

import uuid

import jwt
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core.config import settings
from app.core.ratelimit import RateLimitMiddleware
from app.main import app

DEMO_PASSWORD = "safar-demo-123"
DEMO_EMAIL = "mira@safar.demo"


def _browser() -> TestClient:
    """A cookie jar isolated from the shared session client."""
    return TestClient(app)


def _bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _register(client: TestClient) -> dict[str, str]:
    response = client.post(
        "/api/auth/register",
        json={
            "email": f"probe-{uuid.uuid4().hex[:10]}@safar-tests.com",
            "password": "probe-pass-123",
            "display_name": "Security Probe",
        },
    )
    assert response.status_code == 201, response.text
    return _bearer(response.json()["access_token"])


def test_responses_carry_security_headers_and_request_id(client):
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["x-frame-options"] == "DENY"
    assert response.headers["referrer-policy"] == "no-referrer"
    assert "frame-ancestors 'none'" in response.headers["content-security-policy"]
    assert response.headers["cross-origin-opener-policy"] == "same-origin"
    assert response.headers["cache-control"] == "no-store"
    assert len(response.headers["x-request-id"]) == 32

    echoed = client.get("/api/health", headers={"X-Request-Id": "client-supplied-1234"})
    assert echoed.headers["x-request-id"] == "client-supplied-1234"

    rejected = client.get("/api/health", headers={"X-Request-Id": "bad id with spaces"})
    assert rejected.headers["x-request-id"] != "bad id with spaces"


def test_health_and_ready_do_not_leak_internals(client):
    health = client.get("/api/health")
    body = health.json()
    assert body["status"] == "ok"
    assert body["database"] == "ok"
    assert body["external_ai"] is False
    assert "environment" not in body
    assert "auto_seed" not in body

    ready = client.get("/api/ready")
    assert ready.status_code == 200
    assert ready.json() == {"status": "ready", "database": "ok"}


def test_unknown_host_header_is_rejected(client):
    response = client.get("/api/health", headers={"Host": "evil.example.com"})
    assert response.status_code == 400


def test_oversized_body_is_rejected_before_validation(client):
    oversized = b"x" * (settings.max_request_bytes + 1)
    response = client.post(
        "/api/auth/login", content=oversized, headers={"content-type": "application/json"}
    )
    assert response.status_code == 413
    assert response.json()["detail"] == "Request body too large"
    assert "x-request-id" in response.headers


def test_anonymous_requests_reach_only_public_endpoints():
    anonymous = _browser()
    assert anonymous.get("/api/trips").status_code == 401
    assert anonymous.get("/api/auth/me").status_code == 401
    assert anonymous.get("/api/admin/stats").status_code == 401
    assert (
        anonymous.post(
            "/api/trips",
            json={
                "name": "Anonymous attempt",
                "start_date": "2027-01-01",
                "end_date": "2027-01-05",
            },
        ).status_code
        == 401
    )

    assert anonymous.get("/api/health").status_code == 200
    assert anonymous.get("/api/ready").status_code == 200
    assert anonymous.get("/api/assistant/capabilities").status_code == 200


def test_cookie_sessions_require_csrf_for_writes():
    browser = _browser()
    login = browser.post(
        "/api/auth/login", json={"email": DEMO_EMAIL, "password": DEMO_PASSWORD}
    )
    assert login.status_code == 200, login.text
    csrf = login.json()["csrf_token"]
    assert browser.cookies.get("safar_csrf") == csrf
    # Cookies alone authenticate safe reads.
    assert browser.get("/api/auth/me").status_code == 200

    payload = {
        "name": "CSRF probe",
        "start_date": "2027-04-01",
        "end_date": "2027-04-04",
    }
    assert browser.post("/api/trips", json=payload).status_code == 403
    assert (
        browser.post(
            "/api/trips", json=payload, headers={"X-CSRF-Token": "not-the-cookie"}
        ).status_code
        == 403
    )
    created = browser.post("/api/trips", json=payload, headers={"X-CSRF-Token": csrf})
    assert created.status_code == 201, created.text


def test_refresh_rotation_rejects_a_replayed_token():
    browser = _browser()
    login = browser.post(
        "/api/auth/login", json={"email": DEMO_EMAIL, "password": DEMO_PASSWORD}
    )
    assert login.status_code == 200
    old_refresh = browser.cookies.get("safar_refresh")
    assert old_refresh

    rotated = browser.post("/api/auth/refresh")
    assert rotated.status_code == 200
    assert browser.cookies.get("safar_refresh") not in (None, old_refresh)

    replay = _browser().post(
        "/api/auth/refresh", headers={"cookie": f"safar_refresh={old_refresh}"}
    )
    assert replay.status_code == 401


def test_logout_revokes_the_session_for_existing_tokens():
    browser = _browser()
    login = browser.post(
        "/api/auth/login", json={"email": DEMO_EMAIL, "password": DEMO_PASSWORD}
    )
    assert login.status_code == 200
    access_token = login.json()["access_token"]
    csrf = login.json()["csrf_token"]

    logged_out = browser.post("/api/auth/logout", headers={"X-CSRF-Token": csrf})
    assert logged_out.status_code == 200
    assert logged_out.json()["revoked"] is True

    revoked = _browser().get("/api/auth/me", headers=_bearer(access_token))
    assert revoked.status_code == 401
    assert browser.post("/api/auth/refresh").status_code == 401
    # Logging out an already-cleared browser stays idempotent.
    assert browser.post("/api/auth/logout").status_code == 200


def test_expired_and_forged_tokens_are_rejected(client, mira):
    me = client.get("/api/auth/me", headers=mira)
    assert me.status_code == 200
    user_id = me.json()["id"]

    from app.core.security import create_access_token

    expired = create_access_token(user_id, DEMO_EMAIL, expires_minutes=-1)
    assert client.get("/api/auth/me", headers=_bearer(expired)).status_code == 401

    forged = jwt.encode(
        {
            "sub": user_id,
            "email": DEMO_EMAIL,
            "typ": "access",
            "iss": "safar",
            "exp": 9999999999,
        },
        "attacker-controlled-secret-key-with-enough-length",
        algorithm="HS256",
    )
    assert client.get("/api/auth/me", headers=_bearer(forged)).status_code == 401


def test_media_upload_rejects_a_spoofed_content_type(client, aiko, kyoto):
    fake = client.post(
        f"/api/trips/{kyoto['id']}/media",
        headers=aiko,
        files={"file": ("photo.png", b"<html>not an image</html>", "image/png")},
    )
    assert fake.status_code == 415, fake.text

    real = client.post(
        f"/api/trips/{kyoto['id']}/media",
        headers=aiko,
        files={
            "file": (
                "photo.png",
                b"\x89PNG\r\n\x1a\n" + b"\x00" * 32,
                "image/png",
            )
        },
    )
    assert real.status_code == 201, real.text
    assert "/media/" in real.json()["media_url"]


def test_cross_user_trip_access_is_hidden(client, kyoto):
    stranger = _register(client)
    assert client.get(f"/api/trips/{kyoto['id']}", headers=stranger).status_code == 404
    assert (
        client.get(f"/api/trips/{kyoto['id']}/expenses", headers=stranger).status_code
        == 404
    )
    assert (
        client.get(f"/api/trips/{kyoto['id']}/itinerary", headers=stranger).status_code
        == 404
    )
    assert (
        client.get(f"/api/trips/{kyoto['id']}/memories", headers=stranger).status_code
        == 404
    )


def test_unknown_companion_and_invitation_tokens_are_404(client):
    unknown = uuid.uuid4().hex
    assert client.get(f"/api/companion/{unknown}").status_code == 404
    assert (
        client.post(
            f"/api/companion/{unknown}/respond", json={"value": "accept"}
        ).status_code
        == 404
    )
    stranger = _register(client)
    assert (
        client.get(f"/api/invitations/{unknown}", headers=stranger).status_code == 404
    )


def test_registration_ignores_privilege_fields(client):
    response = client.post(
        "/api/auth/register",
        json={
            "email": f"mass-{uuid.uuid4().hex[:10]}@safar-tests.com",
            "password": "mass-pass-123",
            "display_name": "Mass Probe",
            "is_admin": True,
            "role": "owner",
            "id": "0" * 32,
        },
    )
    assert response.status_code == 201, response.text
    user = response.json()["user"]
    assert user["is_admin"] is False
    assert user["id"] != "0" * 32


def test_account_deletion_erases_personal_data(client):
    from datetime import date

    from app.db.context import system_context
    from app.db.session import SessionLocal
    from app.models import (
        AuthSession,
        JourneyDNA,
        TripMember,
        TripMemory,
        TripPulse,
        User,
    )

    email = f"erase-{uuid.uuid4().hex[:10]}@safar-tests.com"
    created = client.post(
        "/api/auth/register",
        json={"email": email, "password": "erase-pass-123", "display_name": "Erase Me"},
    )
    assert created.status_code == 201, created.text
    headers = _bearer(created.json()["access_token"])
    me = client.get("/api/users/me", headers=headers)
    assert me.status_code == 200, me.text
    user_id = me.json()["user"]["id"]

    trip = client.post(
        "/api/trips",
        json={
            "name": "Erasure probe",
            "start_date": "2027-06-01",
            "end_date": "2027-06-05",
        },
        headers=headers,
    )
    assert trip.status_code == 201, trip.text
    trip_id = trip.json()["id"]

    memory = client.post(
        f"/api/trips/{trip_id}/memories",
        json={
            "kind": "text",
            "text_content": "private note with location",
            "lat": 35.0116,
            "lon": 135.7681,
            "visibility": "private",
        },
        headers=headers,
    )
    assert memory.status_code == 201, memory.text
    memory_id = memory.json()["id"]

    db = SessionLocal()
    try:
        with system_context(db):
            db.add(
                TripPulse(
                    trip_id=trip_id,
                    user_id=user_id,
                    pulse_date=date(2027, 6, 2),
                    energy=3,
                    interests=["food"],
                    budget_comfort=3,
                )
            )
            db.commit()
    finally:
        db.close()

    deleted = client.delete("/api/users/me", headers=headers)
    assert deleted.status_code == 200, deleted.text

    db = SessionLocal()
    try:
        with system_context(db):
            assert db.get(User, user_id).deleted_at is not None
            assert db.query(JourneyDNA).filter_by(user_id=user_id).count() == 0
            assert db.query(TripPulse).filter_by(user_id=user_id).count() == 0
            assert db.query(AuthSession).filter_by(user_id=user_id).count() == 0
            row = db.get(TripMemory, memory_id)
            assert row.text_content is None
            assert row.lat is None and row.lon is None
            assert row.deleted_at is not None
            membership = (
                db.query(TripMember)
                .filter_by(trip_id=trip_id, user_id=user_id)
                .one()
            )
            assert membership.status == "removed"
            assert membership.display_name == "Former traveller"
            assert membership.budget_limit is None
    finally:
        db.close()


def test_precise_location_requires_the_privacy_toggle(client):
    headers = _register(client)
    trip = client.post(
        "/api/trips",
        json={
            "name": "Location probe",
            "start_date": "2027-08-01",
            "end_date": "2027-08-03",
        },
        headers=headers,
    )
    assert trip.status_code == 201, trip.text
    trip_id = trip.json()["id"]

    denied = client.get(
        f"/api/trips/{trip_id}/nearby",
        params={"lat": 35.0, "lon": 135.77},
        headers=headers,
    )
    assert denied.status_code == 403, denied.text

    base_only = client.get(f"/api/trips/{trip_id}/nearby", headers=headers)
    assert base_only.status_code == 200
    assert base_only.json()["base"]["source"] == "shared trip base"

    enabled = client.patch(
        "/api/users/me/profile",
        json={"location_sharing": True},
        headers=headers,
    )
    assert enabled.status_code == 200, enabled.text

    allowed = client.get(
        f"/api/trips/{trip_id}/nearby",
        params={"lat": 35.0, "lon": 135.77},
        headers=headers,
    )
    assert allowed.status_code == 200
    assert allowed.json()["base"]["source"] == "requested point"

    half = client.get(
        f"/api/trips/{trip_id}/nearby", params={"lat": 35.0}, headers=headers
    )
    assert half.status_code == 422


def test_retention_removes_only_expired_rows(client, kyoto):
    from datetime import timedelta

    from app.db.context import system_context
    from app.db.session import SessionLocal
    from app.models import (
        AuthSession,
        CompanionLink,
        Notification,
        OfflineSyncQueue,
        TripInvitation,
    )
    from app.models.models import utcnow
    from app.services.retention import run_retention

    now = utcnow()
    old = now - timedelta(days=400)
    mira = client.post(
        "/api/auth/login", json={"email": DEMO_EMAIL, "password": DEMO_PASSWORD}
    )
    assert mira.status_code == 200, mira.text
    user_id = mira.json()["user"]["id"]
    ids: dict[str, str] = {}
    db = SessionLocal()
    try:
        with system_context(db):
            session_row = AuthSession(
                user_id=user_id,
                refresh_hash="a" * 64,
                expires_at=now - timedelta(days=60),
            )
            invitation = TripInvitation(
                trip_id=kyoto["id"],
                token=uuid.uuid4().hex,
                created_by=user_id,
                expires_at=now - timedelta(days=60),
            )
            link = CompanionLink(
                trip_id=kyoto["id"],
                created_by=user_id,
                purpose="vote",
                target_id="probe-target",
                expires_at=now - timedelta(days=60),
            )
            notification = Notification(
                user_id=user_id, title="Old notice", created_at=old
            )
            queue_row = OfflineSyncQueue(
                user_id=user_id,
                trip_id=kyoto["id"],
                client_id=f"retention-{uuid.uuid4().hex[:8]}",
                operation="memory_create",
                status="applied",
                created_at=old,
                applied_at=old + timedelta(minutes=1),
            )
            db.add_all([session_row, invitation, link, notification, queue_row])
            db.commit()
            ids = {
                "session": session_row.id,
                "invitation": invitation.id,
                "link": link.id,
                "notification": notification.id,
                "queue": queue_row.id,
            }
            removed = run_retention(db, now=now)
            db.commit()
            db.expire_all()
            assert removed["auth_sessions"] >= 1
            assert removed["trip_invitations"] >= 1
            assert removed["companion_links"] >= 1
            assert removed["notifications"] >= 1
            assert removed["offline_sync_queue"] >= 1
            assert db.get(AuthSession, ids["session"]) is None
            assert db.get(TripInvitation, ids["invitation"]) is None
            assert db.get(CompanionLink, ids["link"]) is None
            assert db.get(Notification, ids["notification"]) is None
            assert db.get(OfflineSyncQueue, ids["queue"]) is None
    finally:
        db.close()


def test_malicious_inputs_are_handled_without_server_errors(client, mira):
    injection = "' OR 1=1 --"
    search = client.get(
        "/api/activities/search", params={"q": injection}, headers=mira
    )
    assert search.status_code == 200
    assert search.json()["items"] == []

    login = client.post(
        "/api/auth/login", json={"email": f"{injection}@example.com", "password": injection}
    )
    assert login.status_code in (401, 422)

    malformed = client.get(f"/api/trips/{'../' * 3}etc/passwd", headers=mira)
    assert malformed.status_code in (404, 405)


def test_error_bodies_do_not_leak_internals(client):
    response = client.get(f"/api/trips/{'0' * 32}", headers=_register(client))
    assert response.status_code == 404
    assert list(response.json()) == ["detail"]
    assert "Traceback" not in response.text
    assert response.headers["content-type"].startswith("application/json")


def test_rate_limiter_buckets_and_retry_after(monkeypatch):
    monkeypatch.setattr(settings, "auth_rate_limit_per_minute", 2)
    probe = FastAPI()
    probe.add_middleware(RateLimitMiddleware)

    @probe.get("/api/auth/login")
    def fake_login():
        return {"ok": True}

    @probe.get("/api/health")
    def fake_health():
        return {"status": "ok"}

    with TestClient(probe) as limited:
        assert limited.get("/api/auth/login").status_code == 200
        assert limited.get("/api/auth/login").status_code == 200
        blocked = limited.get("/api/auth/login")
        assert blocked.status_code == 429
        assert int(blocked.headers["retry-after"]) >= 1
        # Health probes are never rate limited.
        assert limited.get("/api/health").status_code == 200
