"""Tests for the stabilisation pass: F24 Opportunity Clock and F26 One-Link Companion."""

from __future__ import annotations

import uuid
from datetime import date, timedelta

from app.db.session import SessionLocal
from app.models import CompanionLink
from app.services.companion import issue_token


def _register(client, email: str) -> dict[str, str]:
    response = client.post(
        "/api/auth/register",
        json={
            "email": email,
            "password": "audit-pass-123",
            "display_name": "Stabilisation Probe",
        },
    )
    assert response.status_code == 201, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_inspiration_import_parses_structure_and_avoids_false_positives(client, mira, kyoto):
    trip_id = kyoto["id"]
    rich = client.post(
        f"/api/trips/{trip_id}/inspirations",
        headers=mira,
        json={
            "source_type": "text",
            "content": "Kyoto in June with a #food focus, budget under €50, plus a tea ceremony.",
        },
    )
    assert rich.status_code == 201, rich.text
    extraction = rich.json()["extraction"]
    types = {match["type"] for match in extraction["matches"]}
    assert "destination" in types
    assert "interest" in types
    assert "budget_hint" in types
    assert "travel_window" in types
    assert "June" in {match["name"] for match in extraction["matches"]}
    assert "food" in extraction["metadata"]["hashtags"]

    false_positive = client.post(
        f"/api/trips/{trip_id}/inspirations",
        headers=mira,
        json={"source_type": "text", "content": "We rented a small apartment near the station."},
    )
    assert false_positive.status_code == 201, false_positive.text
    names = {match["name"] for match in false_positive.json()["extraction"]["matches"]}
    assert "art" not in names

    link = client.post(
        f"/api/trips/{trip_id}/inspirations",
        headers=mira,
        json={"source_type": "link", "content": "https://example.com/kyoto/tea-ceremony"},
    )
    assert link.status_code == 201, link.text
    link_extraction = link.json()["extraction"]
    assert "example.com" in link_extraction["metadata"]["source_hosts"]
    assert any(
        match["type"] == "destination" and "link path" in match["evidence"]
        for match in link_extraction["matches"]
    )
    assert any(
        "Link not read" in note and "disabled" in note
        for note in link_extraction["limitations"]
    )


def test_opportunity_clock_is_read_only_and_honest(client, mira, kyoto):
    trip_id = kyoto["id"]
    start = date.fromisoformat(kyoto["start_date"])
    sunday = next(
        start + timedelta(days=offset)
        for offset in range(7)
        if (start + timedelta(days=offset)).weekday() == 6
    )
    before = client.get(f"/api/trips/{trip_id}/itinerary", headers=mira).json()

    response = client.get(
        f"/api/trips/{trip_id}/opportunity-clock?on={sunday.isoformat()}",
        headers=mira,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["available"] is True
    assert body["plan_unchanged"] is True
    assert body["confirmed_version"] == before["confirmed_version"]
    assert body["items"], "Expected catalog candidates for the seeded destination"
    allowed = {
        "open_now",
        "later_today",
        "no_window",
        "closed_today",
        "unknown",
        "window_missed",
    }
    for item in body["items"]:
        assert item["status"] in allowed
        assert item["explanation"]
        assert item["provenance"] == "ESTIMATED"
        if item["status"] == "closed_today":
            assert "closed" in item["explanation"].lower()

    outside = client.get(
        f"/api/trips/{trip_id}/opportunity-clock?on=2030-01-01",
        headers=mira,
    )
    assert outside.status_code == 422

    stranger = _register(client, f"clock-stranger-{uuid.uuid4().hex[:8]}@example.com")
    denied = client.get(f"/api/trips/{trip_id}/opportunity-clock", headers=stranger)
    assert denied.status_code == 404

    after = client.get(f"/api/trips/{trip_id}/itinerary", headers=mira).json()
    assert after["confirmed_version"] == before["confirmed_version"]


def test_one_link_companion_vote_is_single_use_signed_and_anonymous(client, mira, kyoto):
    trip_id = kyoto["id"]
    proposals = client.get(
        f"/api/trips/{trip_id}/proposals?status=open", headers=mira
    ).json()["items"]
    assert proposals, "Seeded open proposal required for this test"
    proposal_id = proposals[0]["id"]

    created = client.post(
        f"/api/trips/{trip_id}/companion-links",
        headers=mira,
        json={"purpose": "vote", "target_id": proposal_id, "ttl_minutes": 60},
    )
    assert created.status_code == 201, created.text
    body = created.json()
    token = body["token"]
    assert body["url"] == f"/companion/{token}"
    assert body["link"]["max_uses"] == 1

    context = client.get(f"/api/companion/{token}")
    assert context.status_code == 200, context.text
    payload = context.json()
    serialized = str(payload).lower()
    assert "budget" not in serialized
    assert "email" not in serialized
    assert payload["purpose"] == "vote"
    assert payload["target"]["title"]
    assert "registered_votes" in payload["target"]
    assert payload["anonymous_responses"] == 0

    tampered = token[:-1] + ("a" if token[-1] != "a" else "b")
    assert client.get(f"/api/companion/{tampered}").status_code == 404

    answered = client.post(f"/api/companion/{token}/respond", json={"value": "yes"})
    assert answered.status_code == 200, answered.text
    assert answered.json()["anonymous"] is True
    assert answered.json()["remaining_uses"] == 0

    repeat = client.post(f"/api/companion/{token}/respond", json={"value": "no"})
    assert repeat.status_code == 410
    assert client.get(f"/api/companion/{token}").status_code == 410

    listing = client.get(f"/api/trips/{trip_id}/companion-links", headers=mira)
    assert listing.status_code == 200
    row = next(
        item for item in listing.json()["items"] if item["id"] == body["link"]["id"]
    )
    assert row["status"] == "used"
    assert row["anonymous_responses"] == 1
    assert "token" not in row

    responses = client.get(
        f"/api/trips/{trip_id}/companion-links/{row['id']}/responses", headers=mira
    )
    assert responses.status_code == 200
    items = responses.json()["items"]
    assert len(items) == 1 and items[0]["value"] == "yes"
    assert "user_id" not in items[0]


def test_one_link_companion_checkin_expiry_revocation_and_scope(client, mira, kyoto):
    trip_id = kyoto["id"]
    itinerary = client.get(f"/api/trips/{trip_id}/itinerary", headers=mira).json()
    item_id = itinerary["items"][0]["id"]

    created = client.post(
        f"/api/trips/{trip_id}/companion-links",
        headers=mira,
        json={"purpose": "checkin", "target_id": item_id, "ttl_minutes": 5},
    )
    assert created.status_code == 201, created.text
    token = created.json()["token"]
    link_id = created.json()["link"]["id"]

    context = client.get(f"/api/companion/{token}").json()
    assert context["purpose"] == "checkin"
    assert context["target"]["kind"] == "checkin"
    assert context["target"]["day"]
    assert "join" in context["question"].lower()

    invalid = client.post(f"/api/companion/{token}/respond", json={"value": "yes"})
    assert invalid.status_code == 422

    db = SessionLocal()
    try:
        from app.db.context import system_context

        with system_context(db):
            row = db.get(CompanionLink, link_id)
            assert row is not None
            row.expires_at = row.expires_at - timedelta(days=1)
            db.commit()
            expired_token = issue_token(row)
    finally:
        db.close()
    assert client.get(f"/api/companion/{expired_token}").status_code == 410

    fresh = client.post(
        f"/api/trips/{trip_id}/companion-links",
        headers=mira,
        json={"purpose": "checkin", "target_id": item_id, "ttl_minutes": 60},
    )
    assert fresh.status_code == 201, fresh.text
    fresh_id = fresh.json()["link"]["id"]
    fresh_token = fresh.json()["token"]

    revoked = client.post(
        f"/api/trips/{trip_id}/companion-links/{fresh_id}/revoke", headers=mira
    )
    assert revoked.status_code == 200
    assert revoked.json()["status"] == "revoked"
    assert client.get(f"/api/companion/{fresh_token}").status_code == 410

    stranger = _register(client, f"companion-stranger-{uuid.uuid4().hex[:8]}@example.com")
    denied = client.post(
        f"/api/trips/{trip_id}/companion-links",
        headers=stranger,
        json={"purpose": "vote", "target_id": item_id, "ttl_minutes": 60},
    )
    assert denied.status_code == 404

    mismatch = client.post(
        f"/api/trips/{trip_id}/companion-links",
        headers=mira,
        json={"purpose": "vote", "target_id": item_id, "ttl_minutes": 60},
    )
    assert mismatch.status_code == 404
