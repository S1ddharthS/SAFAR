"""End-to-end API tests for the SAFAR backend.

These run against a temporary SQLite database that is seeded with the same
deterministic demo data the product ships with. They assert the product rules
the prompt treats as non-negotiable:

* the engine only recommends; only approval changes the confirmed plan
* private budgets and private memories stay private
* estimates and community reports are never presented as verified facts
* offline sync is idempotent
"""

from __future__ import annotations

import pytest

import uuid

from app.db.context import system_context
from app.db.session import SessionLocal
from app.models import JourneyPact


def _trip_id(kyoto: dict) -> str:
    return kyoto["id"]


def _members(client, headers, trip_id: str) -> list[dict]:
    response = client.get(f"/api/trips/{trip_id}/members", headers=headers)
    assert response.status_code == 200, response.text
    return response.json()["items"]


def _itinerary(client, headers, trip_id: str) -> dict:
    response = client.get(f"/api/trips/{trip_id}/itinerary", headers=headers)
    assert response.status_code == 200, response.text
    return response.json()


def test_health_and_capabilities_are_honest(client):
    health = client.get("/api/health")
    assert health.status_code == 200
    body = health.json()
    assert body["status"] == "ok"
    assert body["database"] == "ok"
    assert body["assistant"].startswith("safar-grounded")
    assert body["external_ai"] is False

    capabilities = client.get("/api/assistant/capabilities")
    assert capabilities.status_code == 200
    caps = capabilities.json()
    assert caps["external_llm"] is False
    assert caps["weather"] is False
    assert caps["translation"] is True
    assert caps["translation_mode"] == "local-templates"
    assert "en" in caps["languages"] and len(caps["languages"]) == 8
    assert "disclosure" in caps


def test_registration_grants_only_required_consent(client):
    email = f"new-{uuid.uuid4().hex[:10]}@safar-tests.com"
    registration = client.post(
        "/api/auth/register",
        json={"email": email, "password": "correct-horse-1", "display_name": "Test Traveller"},
    )
    assert registration.status_code == 201, registration.text
    token = registration.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    me = client.get("/api/users/me", headers=headers)
    assert me.status_code == 200
    assert me.json()["user"]["email"] == email

    consents = client.get("/api/users/me/consents", headers=headers)
    assert consents.status_code == 200
    granted = consents.json()["consents"]
    assert granted["terms"]["granted"] is True
    for optional in ("personalization", "analytics", "location", "marketing"):
        assert granted[optional]["granted"] is False

    duplicate = client.post(
        "/api/auth/register",
        json={"email": email, "password": "correct-horse-1", "display_name": "Duplicate"},
    )
    assert duplicate.status_code == 409


def test_member_budget_and_access_needs_are_private(client, mira, aiko, kyoto):
    trip_id = _trip_id(kyoto)
    as_mira = _members(client, mira, trip_id)
    as_aiko = _members(client, aiko, trip_id)

    mira_self = next(member for member in as_mira if member.get("is_self"))
    assert mira_self["budget_limit"] == 120.0
    assert "accessibility_needs" in mira_self

    aiko_view_of_mira = next(
        member for member in as_aiko if member["id"] == mira_self["id"]
    )
    assert "budget_limit" not in aiko_view_of_mira
    assert "accessibility_needs" not in aiko_view_of_mira

    aiko_self = next(member for member in as_aiko if member.get("is_self"))
    assert aiko_self["budget_limit"] == 80.0


def test_engine_recommends_without_changing_the_confirmed_plan(client, mira, kyoto):
    trip_id = _trip_id(kyoto)
    before = _itinerary(client, mira, trip_id)

    response = client.post(
        f"/api/trips/{trip_id}/engine/recommend",
        headers=mira,
        json={"mode": "everyone_wins", "for_date": kyoto["start_date"], "limit": 5},
    )
    assert response.status_code == 201, response.text
    batch = response.json()
    assert batch["items"], "engine returned no recommendations"
    for item in batch["items"]:
        assert "explanation" in item
        assert "fairness_spread" in item
        assert item["status"] == "suggested"
    assert batch["items"][0]["explanation"]["summary"].startswith(
        f"{batch['items'][0]['activity']['name']} is an everyone wins pick"
    )

    after = _itinerary(client, mira, trip_id)
    assert after["confirmed_version"] == before["confirmed_version"]
    assert len(after["items"]) == len(before["items"])


def test_proposal_only_changes_itinerary_after_owner_approval(client, mira, aiko, kyoto):
    trip_id = _trip_id(kyoto)
    itinerary = _itinerary(client, mira, trip_id)
    planned = {item["activity_id"] for item in itinerary["items"] if item["activity_id"]}

    search = client.get(
        f"/api/activities/search?destination_id={kyoto['destination_id']}&limit=60",
        headers=aiko,
    )
    assert search.status_code == 200
    candidates = [
        entry["activity"]
        for entry in search.json()["items"]
        if entry["activity"]["id"] not in planned and entry["activity"]["price_estimate"] <= 20
    ]
    assert candidates, "no unplanned affordable activity available for the proposal test"
    activity = candidates[0]

    proposal = client.post(
        f"/api/trips/{trip_id}/proposals",
        headers=aiko,
        json={
            "kind": "add_activity",
            "title": f"Add {activity['name']}",
            "summary": "Proposed by a member, not applied automatically.",
            "activity_id": activity["id"],
            "day": kyoto["start_date"],
            "start_time": "15:00",
        },
    )
    assert proposal.status_code == 201, proposal.text
    proposal_id = proposal.json()["id"]

    unchanged = _itinerary(client, mira, trip_id)
    assert activity["id"] not in {item["activity_id"] for item in unchanged["items"]}

    member_approval = client.post(
        f"/api/trips/{trip_id}/proposals/{proposal_id}/approve",
        headers=aiko,
        json={"approval": True},
    )
    assert member_approval.status_code == 403

    approval = client.post(
        f"/api/trips/{trip_id}/proposals/{proposal_id}/approve",
        headers=mira,
        json={"approval": True},
    )
    assert approval.status_code == 200, approval.text
    assert approval.json()["created_items"]

    confirmed = _itinerary(client, mira, trip_id)
    assert activity["id"] in {item["activity_id"] for item in confirmed["items"]}
    assert confirmed["confirmed_version"] > unchanged["confirmed_version"]


def test_member_cannot_patch_confirmed_itinerary(client, aiko, kyoto):
    trip_id = _trip_id(kyoto)
    itinerary = _itinerary(client, aiko, trip_id)
    assert itinerary["items"]
    item_id = itinerary["items"][0]["id"]

    response = client.patch(
        f"/api/trips/{trip_id}/itinerary/items/{item_id}",
        headers=aiko,
        json={"notes": "Members must go through a proposal."},
    )
    assert response.status_code == 403, response.text


def test_expense_split_and_balances_reconcile(client, mira, kyoto):
    trip_id = _trip_id(kyoto)
    response = client.post(
        f"/api/trips/{trip_id}/expenses",
        headers=mira,
        json={
            "title": "Group dinner test",
            "category": "food",
            "amount": 40.0,
            "split": "equal",
            "participants": [],
        },
    )
    assert response.status_code == 201, response.text
    expense = response.json()
    shares = [participant["share_amount"] for participant in expense["participants"]]
    assert len(shares) == 4
    assert abs(sum(shares) - 40.0) < 0.01

    balances = client.get(f"/api/trips/{trip_id}/expenses/balances", headers=mira)
    assert balances.status_code == 200
    data = balances.json()
    assert abs(sum(entry["net"] for entry in data["balances"])) < 0.05
    assert data["disclosure"] == "Tracking only — SAFAR does not move money."

    mismatch = client.post(
        f"/api/trips/{trip_id}/expenses",
        headers=mira,
        json={
            "title": "Broken custom split",
            "amount": 10.0,
            "split": "custom",
            "participants": [
                {"guest_name": "A", "share_amount": 2.0},
                {"guest_name": "B", "share_amount": 2.0},
            ],
        },
    )
    assert mismatch.status_code == 422


def test_place_detail_keeps_provenance_and_unknowns(client, aiko, kyoto):
    trip_id = _trip_id(kyoto)
    activity = _itinerary(client, aiko, trip_id)["items"][0]
    assert activity["activity_id"]

    detail = client.get(
        f"/api/trips/{trip_id}/places/{activity['activity_id']}", headers=aiko
    )
    assert detail.status_code == 200, detail.text
    body = detail.json()
    assert set(["activity", "catalog_freshness", "reports", "evidence", "access_chain", "crowd_forecast"]).issubset(body)
    assert body["reports"]["disclosure"]
    assert "sources" in body["evidence"]
    assert body["access_chain"]["stages"]

    expectation = client.post(
        f"/api/trips/{trip_id}/places/{activity['activity_id']}/expectation",
        headers=aiko,
        json={"claim": "It is quiet at opening"},
    )
    assert expectation.status_code == 200, expectation.text
    result = expectation.json()
    assert result["verdict"]
    assert "limitations" in result
    assert "unknowns" in result


def test_community_report_is_reported_not_verified(client, aiko, kyoto):
    trip_id = _trip_id(kyoto)
    activity_id = _itinerary(client, aiko, trip_id)["items"][0]["activity_id"]
    response = client.post(
        f"/api/trips/{trip_id}/place-reports",
        headers=aiko,
        json={
            "activity_id": activity_id,
            "category": "crowd",
            "value": {"level": "busy"},
            "note": "Observed queue at the lower gate.",
            "source_type": "community",
        },
    )
    assert response.status_code == 201, response.text
    report = response.json()
    assert report["provenance"] == "REPORTED"
    assert report["verified"] is False

    verify = client.post(
        f"/api/admin/place-reports/{report['id']}/verify", headers=aiko
    )
    assert verify.status_code == 403


def test_assistant_is_grounded_and_states_limitations(client, mira, kyoto):
    response = client.post(
        f"/api/trips/{_trip_id(kyoto)}/assistant",
        headers=mira,
        json={"message": "What is the confirmed plan for the trip?"},
    )
    assert response.status_code == 200, response.text
    answer = response.json()
    assert answer["generated_by"].startswith("safar-grounded")
    assert answer["answer"]
    assert answer["citations"]

    weather = client.post(
        f"/api/trips/{_trip_id(kyoto)}/assistant",
        headers=mira,
        json={"message": "Will it rain tomorrow?"},
    )
    assert weather.status_code == 200
    body = weather.json()
    assert body["grounding"] == "none"
    assert body["limitations"] == ["No weather API is configured."]
    assert "don't have a weather provider" in body["answer"]


def test_offline_snapshot_and_idempotent_sync(client, aiko, kyoto):
    trip_id = _trip_id(kyoto)
    snapshot = client.get(f"/api/trips/{trip_id}/offline", headers=aiko)
    assert snapshot.status_code == 200
    assert snapshot.json()["disclosure"]
    assert "items" in snapshot.json()

    client_id = f"test-{uuid.uuid4().hex}"
    payload = [
        {
            "client_id": client_id,
            "operation": "memory_create",
            "payload": {"kind": "text", "text_content": "Captured while offline.", "visibility": "trip"},
        }
    ]
    first = client.post(f"/api/trips/{trip_id}/sync", headers=aiko, json=payload)
    assert first.status_code == 200, first.text
    assert first.json()["applied"] == 1
    memory_id = first.json()["results"][0]["id"]
    assert memory_id

    second = client.post(f"/api/trips/{trip_id}/sync", headers=aiko, json=payload)
    assert second.status_code == 200
    assert second.json()["applied"] == 0
    assert second.json()["skipped"] == 1
    assert second.json()["results"][0]["id"] is None

    timeline = client.get(f"/api/trips/{trip_id}/memories", headers=aiko)
    captured = [
        memory
        for day in timeline.json()["days"]
        for memory in day["memories"]
        if memory["id"] == memory_id
    ]
    assert len(captured) == 1


def test_private_memory_stays_private(client, mira, aiko, kyoto):
    trip_id = _trip_id(kyoto)
    created = client.post(
        f"/api/trips/{trip_id}/memories",
        headers=aiko,
        json={
            "kind": "text",
            "text_content": "A private note only I should see.",
            "visibility": "private",
        },
    )
    assert created.status_code == 201, created.text
    memory_id = created.json()["id"]

    def ids(headers) -> set[str]:
        timeline = client.get(f"/api/trips/{trip_id}/memories", headers=headers)
        return {
            memory["id"]
            for day in timeline.json()["days"]
            for memory in day["memories"]
        }

    assert memory_id in ids(aiko)
    assert memory_id not in ids(mira)

    replay = client.get(f"/api/trips/{trip_id}/replay", headers=mira)
    assert replay.status_code == 200
    replay_memory_ids = {
        memory["id"]
        for day in replay.json()["days"]
        for memory in day["memories"]
    }
    assert memory_id not in replay_memory_ids

    book = client.get(f"/api/trips/{trip_id}/travel-book", headers=aiko)
    assert book.status_code == 200
    assert book.headers["content-type"].startswith("text/html")
    assert "A private note only I should see." in book.text


def test_pact_individual_limits_are_private_and_merged(client, mira, aiko, kyoto):
    trip_id = _trip_id(kyoto)
    mira_pact = client.get(f"/api/trips/{trip_id}/pact", headers=mira).json()["pact"]
    mira_id = next(
        member["user"]["id"]
        for member in _members(client, mira, trip_id)
        if member.get("is_self")
    )
    aiko_id = next(
        member["user"]["id"]
        for member in _members(client, aiko, trip_id)
        if member.get("is_self")
    )
    assert set(mira_pact["individual_limits"]) == {mira_id}

    saved = client.put(
        f"/api/trips/{trip_id}/pact",
        headers=mira,
        json={
            "must_do": mira_pact["must_do"],
            "flexible": mira_pact["flexible"],
            "confirmed_times": mira_pact["confirmed_times"],
            "exceptions": mira_pact["exceptions"],
            "individual_limits": {mira_id: {"budget_limit": 125.0, "note": "private"}},
        },
    )
    assert saved.status_code == 200, saved.text

    aiko_pact = client.get(f"/api/trips/{trip_id}/pact", headers=aiko).json()["pact"]
    assert set(aiko_pact["individual_limits"]) == {aiko_id}
    assert aiko_pact["individual_limits"][aiko_id]["budget_limit"] == 80.0

    db = SessionLocal()
    try:
        with system_context(db):
            stored = db.query(JourneyPact).filter(JourneyPact.trip_id == trip_id).one()
            assert stored.individual_limits[aiko_id]["budget_limit"] == 80.0
            assert stored.individual_limits[mira_id]["budget_limit"] == 125.0
            assert stored.must_do == mira_pact["must_do"]
    finally:
        db.close()


def test_ground_request_answers_are_marked_reported(client, aiko, noor, kyoto):
    trip_id = _trip_id(kyoto)
    activity_id = _itinerary(client, aiko, trip_id)["items"][0]["activity_id"]
    request = client.post(
        f"/api/trips/{trip_id}/ground-requests",
        headers=aiko,
        json={"activity_id": activity_id, "question": "Is the lower gate open before 8am?"},
    )
    assert request.status_code == 201, request.text
    request_id = request.json()["id"]

    not_a_contributor = client.post(
        f"/api/trips/{trip_id}/ground-requests/{request_id}/responses",
        headers=aiko,
        json={"observation": "I am not an opted-in local.", "confidence": 0.6},
    )
    assert not_a_contributor.status_code == 403

    answer = client.post(
        f"/api/trips/{trip_id}/ground-requests/{request_id}/responses",
        headers=noor,
        json={"observation": "It was open at 07:40 when I walked past.", "confidence": 0.6},
    )
    assert answer.status_code == 201, answer.text

    listing = client.get(f"/api/trips/{trip_id}/ground-requests", headers=aiko)
    stored = next(row for row in listing.json()["items"] if row["id"] == request_id)
    assert stored["responses"]
    assert stored["responses"][0]["provenance"] == "REPORTED (unverified)"
    assert stored["responses"][0]["verified"] is False


def test_circle_detail_lists_members_without_private_fields(client, mira):
    listing = client.get("/api/circles", headers=mira)
    assert listing.status_code == 200, listing.text
    circle_id = listing.json()["items"][0]["id"]

    detail = client.get(f"/api/circles/{circle_id}", headers=mira)
    assert detail.status_code == 200, detail.text
    body = detail.json()
    assert body["members"], "circle detail must include the member list"
    for member in body["members"]:
        assert set(member) == {"user_id", "display_name", "role"}
    for post in body["posts"]:
        assert post["status"] == "published"


def test_trip_websocket_requires_membership(client, mira, noor, kyoto):
    from starlette.websockets import WebSocketDisconnect

    trip_id = _trip_id(kyoto)
    ticket = client.post("/api/auth/ws-ticket", headers=mira).json()["ticket"]
    with client.websocket_connect(f"/ws/trips/{trip_id}?token={ticket}") as socket:
        hello = socket.receive_json()
        assert hello["event"] == "connected"
        assert hello["trip_id"] == trip_id

    access_token = mira["Authorization"].split(" ", 1)[1]
    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect(
            f"/ws/trips/{trip_id}?token={access_token}"
        ) as socket:
            socket.receive_json()

    outsider_ticket = client.post(
        "/api/auth/ws-ticket", headers=noor
    ).json()["ticket"]
    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect(
            f"/ws/trips/{trip_id}?token={outsider_ticket}"
        ) as socket:
            socket.receive_json()
