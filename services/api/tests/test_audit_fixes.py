"""Regression tests for issues found in the deep audit.

Each test pins one previously broken rule so it cannot regress silently.
"""

from __future__ import annotations

import uuid
from datetime import date
from pathlib import Path
from types import SimpleNamespace
from urllib.parse import urlsplit

from app.services.engine import MemberContext, rank_activity


def _register(client, email: str) -> dict[str, str]:
    response = client.post(
        "/api/auth/register",
        json={
            "email": email,
            "password": "audit-pass-123",
            "display_name": "Audit Probe",
        },
    )
    assert response.status_code == 201, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_invitation_is_single_use_and_email_bound(client, mira, kyoto):
    trip_id = kyoto["id"]
    created = client.post(
        f"/api/trips/{trip_id}/invitations",
        headers=mira,
        json={"email": None, "role": "member", "scope": "full"},
    )
    assert created.status_code == 201, created.text
    token = created.json()["token"]

    first = _register(client, f"first-{uuid.uuid4().hex[:8]}@example.com")
    assert client.post(f"/api/invitations/{token}/accept", headers=first).status_code == 200

    second = _register(client, f"second-{uuid.uuid4().hex[:8]}@example.com")
    reused = client.post(f"/api/invitations/{token}/accept", headers=second)
    assert reused.status_code == 409, reused.text

    bound_email = f"bound-{uuid.uuid4().hex[:8]}@example.com"
    bound = client.post(
        f"/api/trips/{trip_id}/invitations",
        headers=mira,
        json={"email": bound_email, "role": "member", "scope": "full"},
    )
    assert bound.status_code == 201, bound.text
    bound_token = bound.json()["token"]

    wrong = _register(client, f"wrong-{uuid.uuid4().hex[:8]}@example.com")
    assert (
        client.post(f"/api/invitations/{bound_token}/accept", headers=wrong).status_code
        == 403
    )

    right = _register(client, bound_email)
    assert (
        client.post(f"/api/invitations/{bound_token}/accept", headers=right).status_code
        == 200
    )


def test_media_requires_a_valid_signature(client, aiko, kyoto):
    trip_id = kyoto["id"]
    upload = client.post(
        f"/api/trips/{trip_id}/media",
        headers=aiko,
        files={"file": ("probe.png", b"\x89PNG\r\n\x1a\nprobe", "image/png")},
    )
    assert upload.status_code == 201, upload.text
    signed_url = upload.json()["media_url"]
    assert signed_url.startswith("/media/")
    raw_path = urlsplit(signed_url).path

    unsigned = client.get(raw_path)
    assert unsigned.status_code == 403

    signed = client.get(signed_url)
    assert signed.status_code == 200
    assert signed.content.startswith(b"\x89PNG")

    tampered = client.get(f"{raw_path}?exp=9999999999&sig=deadbeef")
    assert tampered.status_code == 403

    # Persisting a signed URL must not store the expiring signature.
    memory = client.post(
        f"/api/trips/{trip_id}/memories",
        headers=aiko,
        json={"kind": "photo", "media_url": signed_url, "captured_at": "2026-02-10T09:00:00"},
    )
    assert memory.status_code == 201, memory.text
    stored_url = memory.json()["media_url"]
    assert "exp=" in stored_url and "sig=" in stored_url
    assert client.get(stored_url).status_code == 200
    assert client.get(raw_path).status_code == 403

    from app.main import MEDIA_DIR

    stored_file = MEDIA_DIR / trip_id / raw_path.rsplit("/", 1)[-1]
    Path(stored_file).unlink(missing_ok=True)


def test_private_memory_events_do_not_leak_metadata(client, mira, aiko, kyoto):
    trip_id = kyoto["id"]
    created = client.post(
        f"/api/trips/{trip_id}/memories",
        headers=aiko,
        json={
            "kind": "text",
            "text_content": "Private event-metadata probe.",
            "visibility": "private",
            "captured_at": "2026-02-10T09:15:00",
        },
    )
    assert created.status_code == 201, created.text
    memory_id = created.json()["id"]

    suggested = client.post(
        f"/api/trips/{trip_id}/memory-studio/suggest-events", headers=aiko
    )
    assert suggested.status_code == 201, suggested.text
    matching = [
        event
        for event in suggested.json()["created"]
        if memory_id in event["memory_ids"]
    ]
    assert matching, "expected a suggested event for the private memory"
    event_id = matching[0]["id"]
    assert (
        client.post(
            f"/api/trips/{trip_id}/memory-events/{event_id}/approve", headers=aiko
        ).status_code
        == 200
    )

    other_studio = client.get(f"/api/trips/{trip_id}/memory-studio", headers=mira)
    assert other_studio.status_code == 200
    assert not any(
        memory_id in event["memory_ids"] for event in other_studio.json()["events"]
    )

    other_replay = client.get(f"/api/trips/{trip_id}/replay", headers=mira).json()
    assert not any(
        memory_id in event["memory_ids"]
        for day in other_replay["days"]
        for event in day["events"]
    )

    own_replay = client.get(f"/api/trips/{trip_id}/replay", headers=aiko).json()
    assert any(
        memory_id in event["memory_ids"]
        for day in own_replay["days"]
        for event in day["events"]
    )


def test_default_budget_comfort_is_not_a_hard_filter():
    context = MemberContext(
        member_id="member-1",
        user_id=None,
        label="Member 1",
        display_name="Member 1",
        dna={"food": 8.0},
        budget_limit=None,
        accessibility=[],
        budget_comfort=3,
    )
    assert context.hard_budget is None
    assert context.soft_budget == 70.0

    activity = SimpleNamespace(
        price_estimate=100.0,
        currency="EUR",
        duration_minutes=60,
        effort=2,
        popularity=0.5,
        tags=["food"],
        indoor=True,
        wheelchair_accessible=None,
        iconic=False,
        source_type="seed_catalog",
        last_verified_at=None,
    )
    ranked = rank_activity(
        activity,
        [context],
        base_lat=0.0,
        base_lon=0.0,
        coords=(0.0, 0.0),
        target_member_index=None,
        mode="everyone_wins",
    )
    assert ranked is not None, "an inferred comfort score must not exclude the activity"

    stated = MemberContext(
        member_id="member-2",
        user_id=None,
        label="Member 2",
        display_name="Member 2",
        dna={"food": 8.0},
        budget_limit=80.0,
        accessibility=[],
    )
    assert (
        rank_activity(
            activity,
            [stated],
            base_lat=0.0,
            base_lon=0.0,
            coords=(0.0, 0.0),
            target_member_index=None,
            mode="everyone_wins",
        )
        is None
    )


def test_expense_without_currency_uses_the_trip_currency(client, mira):
    created = client.post(
        "/api/trips",
        headers=mira,
        json={
            "name": f"JPY probe {uuid.uuid4().hex[:6]}",
            "start_date": "2027-05-01",
            "end_date": "2027-05-05",
            "group_size": 2,
            "currency": "JPY",
        },
    )
    assert created.status_code == 201, created.text
    trip_id = created.json()["id"]

    expense = client.post(
        f"/api/trips/{trip_id}/expenses",
        headers=mira,
        json={"title": "Rail pass", "amount": 12000, "split": "equal", "participants": []},
    )
    assert expense.status_code == 201, expense.text
    assert expense.json()["currency"] == "JPY"


def test_rescue_proposal_requires_replacements_and_never_touches_confirmed_plan(
    client, mira, kyoto
):
    trip_id = kyoto["id"]
    itinerary = client.get(f"/api/trips/{trip_id}/itinerary", headers=mira).json()
    confirmed_before = itinerary["confirmed_version"]
    assert itinerary["items"], "seeded trip needs confirmed items for this probe"
    today = date.today().isoformat()
    upcoming = [item for item in itinerary["items"] if item["day"] >= today]
    assert upcoming, "seeded trip needs an upcoming confirmed item for this probe"
    target = upcoming[0]

    empty = client.post(
        f"/api/trips/{trip_id}/rescue/propose",
        headers=mira,
        json={"kind": "rain", "item_id": target["id"], "items": []},
    )
    assert empty.status_code == 422, empty.text

    analysis = client.post(
        f"/api/trips/{trip_id}/rescue/analyze",
        headers=mira,
        json={"kind": "rain", "item_id": target["id"]},
    )
    assert analysis.status_code == 200, analysis.text
    body = analysis.json()
    assert body["requires_approval"] is True

    choice = None
    for proposal in body["proposals"]:
        for option in proposal["options"]:
            if option["ready"] and option["activity_id"]:
                choice = (proposal, option)
                break
        if choice:
            break
    assert choice, "expected at least one feasible replacement in the seeded data"
    proposal, option = choice

    created = client.post(
        f"/api/trips/{trip_id}/rescue/propose",
        headers=mira,
        json={
            "kind": "rain",
            "item_id": proposal["item_id"],
            "items": [
                {
                    "item_id": proposal["item_id"],
                    "activity_id": option["activity_id"],
                    "day": proposal["day"],
                    "start_time": proposal["start_time"],
                }
            ],
        },
    )
    assert created.status_code == 201, created.text
    assert created.json()["kind"] == "rescue"

    after = client.get(f"/api/trips/{trip_id}/itinerary", headers=mira).json()
    assert after["confirmed_version"] == confirmed_before
    assert any(item["id"] == target["id"] for item in after["items"])


def test_inspiration_import_is_trip_scoped_202(client, mira, kyoto):
    trip_id = kyoto["id"]
    imported = client.post(
        f"/api/trips/{trip_id}/inspirations",
        headers=mira,
        json={
            "source_type": "text",
            "content": "I dream of quiet moss gardens and a lantern-lit evening walk.",
        },
    )
    assert imported.status_code == 201, imported.text
    body = imported.json()
    assert body["status"] == "extracted"
    assert "matches" in body["extraction"]

    listing = client.get(f"/api/trips/{trip_id}/inspirations", headers=mira)
    assert listing.status_code == 200
    assert any(row["id"] == body["id"] for row in listing.json()["items"])


def test_all_three_engine_modes_explain_and_never_mutate(client, mira, kyoto):
    trip_id = kyoto["id"]
    before = client.get(f"/api/trips/{trip_id}/itinerary", headers=mira).json()

    for mode, marker in (
        ("everyone_wins", "everyone wins pick"),
        ("your_turn", "your turn pick"),
        ("surprise_us", "surprise us pick"),
    ):
        response = client.post(
            f"/api/trips/{trip_id}/engine/recommend",
            headers=mira,
            json={"mode": mode, "for_date": kyoto["start_date"], "limit": 5},
        )
        assert response.status_code == 201, response.text
        batch = response.json()
        assert batch["mode"] == mode
        assert batch["meta"]["model_version"] == "safar-group-engine-1.5"
        assert batch["meta"]["hard_constraints"]
        assert "estimates" in batch["meta"]["disclosure"]
        assert batch["items"], f"{mode} returned no recommendations"
        assert marker in batch["items"][0]["explanation"]["summary"]
        assert batch["items"][0]["explanation"]["uncertainties"] is not None
        assert batch["items"][0]["fairness_spread"] is not None
        assert batch["items"][0]["status"] == "suggested"
        assert "/" in batch["meta"]["pulse_coverage"]
        assert "clarifying_question" in batch["meta"]

    after = client.get(f"/api/trips/{trip_id}/itinerary", headers=mira).json()
    assert after["confirmed_version"] == before["confirmed_version"]
    assert [item["id"] for item in after["items"]] == [item["id"] for item in before["items"]]


def test_engine_without_a_destination_returns_an_explicit_error_not_results(client):
    headers = _register(client, f"no-destination-{uuid.uuid4().hex[:8]}@example.com")
    trip = client.post(
        "/api/trips",
        headers=headers,
        json={
            "name": f"Empty probe {uuid.uuid4().hex[:6]}",
            "start_date": "2027-06-01",
            "end_date": "2027-06-03",
            "group_size": 2,
        },
    )
    assert trip.status_code == 201, trip.text
    response = client.post(
        f"/api/trips/{trip.json()['id']}/engine/recommend",
        headers=headers,
        json={"mode": "everyone_wins", "limit": 4, "for_date": "2027-06-01"},
    )
    assert response.status_code == 422, response.text
    assert "destination" in response.json()["detail"].lower()


def test_journey_dna_is_editable_and_feedback_only_changes_it_with_consent(
    client, aiko, kyoto
):
    from app.services.common import DNA_DIMENSIONS, normalize_tag

    trip_id = kyoto["id"]

    explicit = client.put(
        "/api/users/me/dna", headers=aiko, json={"scores": {"food": 99}}
    )
    assert explicit.status_code == 200, explicit.text
    assert explicit.json()["scores"]["food"] == 10
    assert explicit.json()["source"] == "explicit"
    assert (
        client.put(
            "/api/users/me/dna", headers=aiko, json={"scores": {"telepathy": 3}}
        ).status_code
        == 422
    )

    itinerary = client.get(f"/api/trips/{trip_id}/itinerary", headers=aiko).json()
    target = next(
        item
        for item in itinerary["items"]
        if item["activity"]
        and any(normalize_tag(tag) in DNA_DIMENSIONS for tag in item["activity"]["tags"])
    )
    activity_id = target["activity_id"]

    unconsented = client.post(
        f"/api/trips/{trip_id}/activities/{activity_id}/feedback",
        headers=aiko,
        json={"sentiment": "loved", "consented": False},
    )
    assert unconsented.status_code == 200, unconsented.text
    assert unconsented.json()["journey_dna"] is None

    client.put(
        "/api/users/me/consents",
        headers=aiko,
        json={"consents": {"personalization": False}},
    )
    blocked = client.post(
        f"/api/trips/{trip_id}/activities/{activity_id}/feedback",
        headers=aiko,
        json={"sentiment": "loved", "consented": True},
    )
    assert blocked.status_code == 200, blocked.text
    assert blocked.json()["journey_dna"] is None

    client.put(
        "/api/users/me/consents",
        headers=aiko,
        json={"consents": {"personalization": True}},
    )
    allowed = client.post(
        f"/api/trips/{trip_id}/activities/{activity_id}/feedback",
        headers=aiko,
        json={"sentiment": "loved", "consented": True},
    )
    assert allowed.status_code == 200, allowed.text
    assert allowed.json()["journey_dna"] is not None


def test_trip_twin_compares_read_only_and_adoption_becomes_a_proposal(client, mira, kyoto):
    trip_id = kyoto["id"]
    before = client.get(f"/api/trips/{trip_id}/itinerary", headers=mira).json()

    batch = client.post(
        f"/api/trips/{trip_id}/engine/recommend",
        headers=mira,
        json={"mode": "everyone_wins", "for_date": kyoto["start_date"], "limit": 4},
    ).json()
    alternatives = [item["activity"]["id"] for item in batch["items"][:2]]
    assert len(alternatives) == 2

    comparison = client.post(
        f"/api/trips/{trip_id}/twin/compare",
        headers=mira,
        json={"activity_ids": alternatives, "day": kyoto["start_date"]},
    )
    assert comparison.status_code == 200, comparison.text
    body = comparison.json()
    assert body["requires_approval"] is True
    assert "read-only" in body["disclosure"]
    assert body["alternative_plan"]["items"]

    unchanged = client.get(f"/api/trips/{trip_id}/itinerary", headers=mira).json()
    assert unchanged["confirmed_version"] == before["confirmed_version"]

    adoption = client.post(
        f"/api/trips/{trip_id}/twin/propose",
        headers=mira,
        json={"activity_ids": alternatives, "day": kyoto["start_date"]},
    )
    assert adoption.status_code == 201, adoption.text
    assert adoption.json()["kind"] == "twin_adopt"


def test_pulse_returns_constraint_compass_and_independent_time_needs_no_reason(
    client, aiko, kyoto
):
    trip_id = kyoto["id"]
    updated = client.put(
        f"/api/trips/{trip_id}/pulse",
        headers=aiko,
        json={"energy": 2, "interests": ["relaxation"], "available_minutes": 90},
    )
    assert updated.status_code == 200, updated.text
    body = updated.json()
    assert "constraint_compass" in body
    assert isinstance(body["constraint_compass"]["items"], list)
    assert "does not modify" in body["constraint_compass"]["note"]

    itinerary = client.get(f"/api/trips/{trip_id}/itinerary", headers=aiko).json()
    item_id = itinerary["items"][0]["id"]
    attendance = client.post(
        f"/api/trips/{trip_id}/itinerary/items/{item_id}/attendance",
        headers=aiko,
        json={"status": "join_later"},
    )
    assert attendance.status_code == 200, attendance.text
    assert attendance.json()["status"] == "join_later"
    assert "No reason" in attendance.json()["note"]

    refreshed = client.get(f"/api/trips/{trip_id}/itinerary", headers=aiko).json()
    matching = next(row for row in refreshed["items"] if row["id"] == item_id)
    assert matching["attendance"]["my_status"] == "join_later"


def test_realtime_broadcasts_pulse_updates_to_other_members(client, mira, aiko, kyoto):
    trip_id = kyoto["id"]
    ticket_mira = client.post(
        "/api/auth/ws-ticket", headers=mira
    ).json()["ticket"]
    ticket_aiko = client.post(
        "/api/auth/ws-ticket", headers=aiko
    ).json()["ticket"]
    with client.websocket_connect(
        f"/ws/trips/{trip_id}?token={ticket_mira}"
    ) as socket_mira, client.websocket_connect(
        f"/ws/trips/{trip_id}?token={ticket_aiko}"
    ) as socket_aiko:
        assert socket_mira.receive_json()["event"] == "connected"
        assert socket_aiko.receive_json()["event"] == "connected"

        updated = client.put(
            f"/api/trips/{trip_id}/pulse",
            headers=aiko,
            json={"energy": 4, "interests": ["food"], "available_minutes": 240},
        )
        assert updated.status_code == 200, updated.text

        event_mira = socket_mira.receive_json()
        event_aiko = socket_aiko.receive_json()
        assert event_mira["event"] == "pulse.updated"
        assert event_aiko["event"] == "pulse.updated"
        assert event_mira["trip_id"] == trip_id


def test_admin_surface_rejects_non_admin_users(client):
    probe = _register(client, f"not-admin-{uuid.uuid4().hex[:8]}@example.com")
    for path in ("/api/admin/stats", "/api/admin/abuse-reports"):
        response = client.get(path, headers=probe)
        assert response.status_code == 403, f"{path} -> {response.status_code}"


def test_deleted_account_is_anonymised_and_token_is_revoked(client):
    email = f"delete-me-{uuid.uuid4().hex[:8]}@example.com"
    headers = _register(client, email)
    me = client.get("/api/users/me", headers=headers)
    assert me.status_code == 200, me.text
    user_id = me.json()["user"]["id"]

    deleted = client.delete("/api/users/me", headers=headers)
    assert deleted.status_code == 200, deleted.text

    assert client.get("/api/users/me", headers=headers).status_code == 401
    assert (
        client.post(
            "/api/auth/login", json={"email": email, "password": "audit-pass-123"}
        ).status_code
        == 401
    )

    from app.db.context import system_context
    from app.db.session import SessionLocal
    from app.models import User

    db = SessionLocal()
    try:
        with system_context(db):
            user = db.get(User, user_id)
            assert user is not None
            assert user.email == f"deleted+{user_id}@safar.invalid"
            assert user.display_name == "Former traveller"
            assert user.deleted_at is not None
    finally:
        db.close()


def test_completed_trip_next_action_links_to_the_real_replay_route(client, mira):
    created = client.post(
        "/api/trips",
        headers=mira,
        json={
            "name": f"Past probe {uuid.uuid4().hex[:6]}",
            "start_date": "2025-01-01",
            "end_date": "2025-01-03",
            "group_size": 2,
        },
    )
    assert created.status_code == 201, created.text
    trip_id = created.json()["id"]

    detail = client.get(f"/api/trips/{trip_id}", headers=mira)
    assert detail.status_code == 200, detail.text
    action = detail.json()["next_action"]
    assert action["kind"] == "replay"
    assert action["href"] == f"/trips/{trip_id}/memories/replay"
