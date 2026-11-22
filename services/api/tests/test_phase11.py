"""Phase 11 release-readiness regressions.

Each test pins a product-wide audit finding so it cannot regress silently.
"""

from __future__ import annotations

import uuid
from datetime import date, timedelta

import pytest


def _register(client) -> tuple[dict[str, str], dict]:
    email = f"phase11-{uuid.uuid4().hex[:10]}@example.com"
    response = client.post(
        "/api/auth/register",
        json={
            "email": email,
            "password": "phase11-pass-123",
            "display_name": "Phase 11 Probe",
        },
    )
    assert response.status_code == 201, response.text
    body = response.json()
    return {"Authorization": f"Bearer {body['access_token']}"}, body["user"]


def _trip(client, headers: dict[str, str]) -> str:
    created = client.post(
        "/api/trips",
        headers=headers,
        json={
            "name": f"Phase 11 {uuid.uuid4().hex[:6]}",
            "start_date": date.today().isoformat(),
            "end_date": (date.today() + timedelta(days=3)).isoformat(),
            "group_size": 3,
            "currency": "EUR",
        },
    )
    assert created.status_code == 201, created.text
    return created.json()["id"]


def _invite(client, owner, trip_id, scope="full", email=None):
    created = client.post(
        f"/api/trips/{trip_id}/invitations",
        headers=owner,
        json={"email": email, "role": "member", "scope": scope},
    )
    assert created.status_code == 201, created.text
    return created.json()


def _members(client, headers, trip_id):
    response = client.get(f"/api/trips/{trip_id}/members", headers=headers)
    assert response.status_code == 200, response.text
    return response.json()["items"]


def test_removed_member_cannot_replay_an_old_invitation(client):
    owner, _ = _register(client)
    guest, guest_user = _register(client)
    trip_id = _trip(client, owner)
    invitation = _invite(client, owner, trip_id)

    accepted = client.post(
        f"/api/invitations/{invitation['token']}/accept", headers=guest
    )
    assert accepted.status_code == 200, accepted.text
    row = next(m for m in _members(client, owner, trip_id) if m["user"]["id"] == guest_user["id"])

    removed = client.delete(
        f"/api/trips/{trip_id}/members/{row['id']}", headers=owner
    )
    assert removed.status_code == 200, removed.text
    assert client.get(f"/api/trips/{trip_id}", headers=guest).status_code == 404

    replay = client.post(
        f"/api/invitations/{invitation['token']}/accept", headers=guest
    )
    assert replay.status_code == 409, replay.text
    assert client.get(f"/api/trips/{trip_id}", headers=guest).status_code == 404


def test_invitation_scope_limits_writes(client):
    owner, _ = _register(client)
    viewer, _ = _register(client)
    trip_id = _trip(client, owner)
    invitation = _invite(client, owner, trip_id, scope="view")
    accepted = client.post(
        f"/api/invitations/{invitation['token']}/accept", headers=viewer
    )
    assert accepted.status_code == 200, accepted.text

    assert client.get(f"/api/trips/{trip_id}", headers=viewer).status_code == 200
    assert (
        client.get(f"/api/trips/{trip_id}/itinerary", headers=viewer).status_code
        == 200
    )
    blocked = client.post(
        f"/api/trips/{trip_id}/tasks", headers=viewer, json={"title": "No writes"}
    )
    assert blocked.status_code == 403, blocked.text
    assert "scope" in blocked.json()["detail"].lower()

    voter, _ = _register(client)
    vote_invite = _invite(client, owner, trip_id, scope="vote")
    assert (
        client.post(
            f"/api/invitations/{vote_invite['token']}/accept", headers=voter
        ).status_code
        == 200
    )
    assert (
        client.post(
            f"/api/trips/{trip_id}/tasks", headers=voter, json={"title": "No writes"}
        ).status_code
        == 403
    )


def test_memory_rejects_media_from_another_trip(client):
    alice, _ = _register(client)
    bob, _ = _register(client)
    alice_trip = _trip(client, alice)
    bob_trip = _trip(client, bob)

    upload = client.post(
        f"/api/trips/{bob_trip}/media",
        headers=bob,
        files={"file": ("bob.png", b"\x89PNG\r\n\x1a\nphase11", "image/png")},
    )
    assert upload.status_code == 201, upload.text
    bob_media = upload.json()["media_url"]

    cross = client.post(
        f"/api/trips/{alice_trip}/memories",
        headers=alice,
        json={"kind": "photo", "media_url": bob_media},
    )
    assert cross.status_code == 422, cross.text
    assert "belong to this trip" in cross.json()["detail"]

    own = client.post(
        f"/api/trips/{alice_trip}/media",
        headers=alice,
        files={"file": ("alice.png", b"\x89PNG\r\n\x1a\nphase11", "image/png")},
    )
    assert own.status_code == 201, own.text
    memory = client.post(
        f"/api/trips/{alice_trip}/memories",
        headers=alice,
        json={"kind": "photo", "media_url": own.json()["media_url"]},
    )
    assert memory.status_code == 201, memory.text


def test_private_feedback_is_not_exposed_in_trip_activity(client, mira, aiko, kyoto):
    trip_id = kyoto["id"]
    itinerary = client.get(f"/api/trips/{trip_id}/itinerary", headers=mira)
    assert itinerary.status_code == 200, itinerary.text
    activity_id = itinerary.json()["items"][0]["activity_id"]

    feedback = client.post(
        f"/api/trips/{trip_id}/activities/{activity_id}/feedback",
        headers=aiko,
        json={"sentiment": "loved", "consented": True},
    )
    assert feedback.status_code == 200, feedback.text

    feed = client.get(f"/api/trips/{trip_id}/activity", headers=mira)
    assert feed.status_code == 200, feed.text
    for row in feed.json()["items"]:
        if row["action"] in {"recommendation.feedback", "activity.feedback"}:
            assert not row["detail"], "private feedback detail must be redacted"


def test_removed_member_socket_is_closed(client):
    from starlette.websockets import WebSocketDisconnect

    owner, _ = _register(client)
    guest, guest_user = _register(client)
    trip_id = _trip(client, owner)
    invitation = _invite(client, owner, trip_id)
    assert (
        client.post(
            f"/api/invitations/{invitation['token']}/accept", headers=guest
        ).status_code
        == 200
    )
    row = next(m for m in _members(client, owner, trip_id) if m["user"]["id"] == guest_user["id"])

    ticket = client.post("/api/auth/ws-ticket", headers=guest).json()["ticket"]
    with client.websocket_connect(f"/ws/trips/{trip_id}?token={ticket}") as socket:
        assert socket.receive_json()["event"] == "connected"
        removed = client.delete(
            f"/api/trips/{trip_id}/members/{row['id']}", headers=owner
        )
        assert removed.status_code == 200, removed.text
        with pytest.raises(WebSocketDisconnect):
            socket.receive_json()
