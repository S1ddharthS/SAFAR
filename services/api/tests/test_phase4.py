"""Phase 4 regression tests: F48, F39, F45, F36, F21, F27, F12, F14.

Every test exercises the API against the seeded database. Direct database
writes are used only to build controlled datasets (crowd forecasting), and are
removed again before the test finishes.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime, time, timedelta

from app.db.context import system_context
from app.db.session import SessionLocal
from app.models import Activity, PlaceReport, TripMember, TripPulse

DEMO_PASSWORD = "safar-demo-123"


def _login(client, email: str) -> dict[str, str]:
    response = client.post(
        "/api/auth/login", json={"email": email, "password": DEMO_PASSWORD}
    )
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _itinerary(client, headers, trip_id: str) -> dict:
    response = client.get(f"/api/trips/{trip_id}/itinerary", headers=headers)
    assert response.status_code == 200, response.text
    return response.json()


def _item(items: list[dict], title: str) -> dict:
    return next(item for item in items if item["title"] == title)


def _activity_id(name: str) -> str:
    db = SessionLocal()
    try:
        activity = db.query(Activity).filter(Activity.name == name).one()
        return activity.id
    finally:
        db.close()


def _pulse_coverage(trip_id: str) -> dict:
    db = SessionLocal()
    try:
        with system_context(db):
            members = (
                db.query(TripMember)
                .filter(TripMember.trip_id == trip_id, TripMember.status == "active")
                .all()
            )
            pulsed = {
                pulse.user_id
                for pulse in db.query(TripPulse)
                .filter(TripPulse.trip_id == trip_id, TripPulse.pulse_date == date.today())
                .all()
            }
            missing = sum(1 for member in members if not member.user_id or member.user_id not in pulsed)
            return {
                "total": len(members),
                "missing": missing,
                "answered": len(members) - missing,
            }
    finally:
        db.close()


def _recommend(client, headers, trip_id: str, for_date: date, limit: int = 12):
    return client.post(
        f"/api/trips/{trip_id}/engine/recommend",
        headers=headers,
        json={"mode": "everyone_wins", "for_date": for_date.isoformat(), "limit": limit},
    )


# ---------------------------------------------------------------------------
# F48 — Neighborhood Respect Filter
# ---------------------------------------------------------------------------


def test_f48_engine_respect_is_grounded_in_place_data(client, mira, kyoto):
    trip_id = kyoto["id"]
    respected = 0
    for offset in (0, 1, 2, 3):
        response = _recommend(client, mira, trip_id, date.today() + timedelta(days=offset))
        if response.status_code == 422:
            continue
        assert response.status_code == 201, response.text
        for recommendation in response.json()["items"]:
            respect = recommendation["respect"]
            activity = recommendation["activity"]
            place = activity.get("place") or {}
            fragile = bool(activity.get("fragile") or place.get("fragile"))
            assert respect["fragile"] is fragile
            if not fragile:
                assert respect["status"] == "not_applicable"
                assert respect["guidance"] is None
                continue
            respected += 1
            if place.get("respect_note"):
                assert respect["status"] == "guidance_recorded"
                assert respect["confidence"] == "verified"
                assert respect["guidance"] == place["respect_note"]
            else:
                assert respect["status"] == "no_guidance_recorded"
                assert respect["confidence"] == "unverified"
                assert respect["guidance"] is None
    # The catalog contains fragile Kyoto places, so at least one recommendation
    # across four days must carry grounded guidance.
    assert respected > 0


# ---------------------------------------------------------------------------
# F39 — Protected Wander Window
# ---------------------------------------------------------------------------


def test_f39_engine_reports_protected_time_and_free_windows(client, mira, kyoto):
    trip_id = kyoto["id"]
    day = date.today() - timedelta(days=1)
    response = _recommend(client, mira, trip_id, day)
    assert response.status_code == 201, response.text
    protected = response.json()["meta"]["protected_time"]
    assert protected["protected_items"] == [
        {
            "item_id": protected["protected_items"][0]["item_id"],
            "title": "Tea ceremony at Camellia",
            "start": "11:00",
            "end": "12:15",
            "start_minutes": 11 * 60,
            "end_minutes": 12 * 60 + 15,
            "protected": True,
        }
    ]
    assert protected["free_windows"] == [
        {"start": "09:30", "end": "11:00", "minutes": 90},
        {"start": "12:15", "end": "22:00", "minutes": 585},
    ]
    assert protected["max_free_minutes"] == 585
    assert "protected" in protected["note"].lower()


def test_f39_engine_refuses_day_without_free_time(client, mira, kyoto):
    trip_id = kyoto["id"]
    day = date.today() + timedelta(days=3)
    created = client.post(
        f"/api/trips/{trip_id}/itinerary/items",
        headers=mira,
        json={
            "day": day.isoformat(),
            "start_time": "08:00",
            "end_time": "21:30",
            "title": "Reserved quiet day",
            "is_protected": True,
        },
    )
    assert created.status_code == 201, created.text
    try:
        blocked = _recommend(client, mira, trip_id, day)
        assert blocked.status_code == 422, blocked.text
        assert "No activity passes" in blocked.json()["detail"]
    finally:
        client.delete(
            f"/api/trips/{trip_id}/itinerary/items/{created.json()['id']}",
            headers=mira,
        )
    recovered = _recommend(client, mira, trip_id, day)
    assert recovered.status_code == 201, recovered.text


def test_f39_propose_rejects_protected_overlap(client, mira, kyoto):
    trip_id = kyoto["id"]
    day = date.today() - timedelta(days=1)
    batch = _recommend(client, mira, trip_id, day)
    assert batch.status_code == 201, batch.text
    recommendation_id = batch.json()["items"][0]["id"]

    protected = client.post(
        f"/api/trips/{trip_id}/recommendations/{recommendation_id}/propose",
        headers=mira,
        json={"day": day.isoformat(), "start_time": "11:30"},
    )
    assert protected.status_code == 409, protected.text
    detail = protected.json()["detail"]
    assert detail["conflict"]["protected"] is True
    assert detail["conflict"]["title"] == "Tea ceremony at Camellia"

    ordinary = client.post(
        f"/api/trips/{trip_id}/recommendations/{recommendation_id}/propose",
        headers=mira,
        json={"day": day.isoformat(), "start_time": "09:00"},
    )
    assert ordinary.status_code == 409, ordinary.text
    assert ordinary.json()["detail"]["conflict"]["protected"] is False

    clear = client.post(
        f"/api/trips/{trip_id}/recommendations/{recommendation_id}/propose",
        headers=mira,
        json={"day": day.isoformat(), "start_time": "13:00"},
    )
    assert clear.status_code == 201, clear.text
    client.post(
        f"/api/trips/{trip_id}/proposals/{clear.json()['id']}/reject", headers=mira
    )


def test_f39_manual_edits_cannot_overwrite_protected_time(client, mira, kyoto):
    trip_id = kyoto["id"]
    protected_day = date.today() - timedelta(days=1)
    items = _itinerary(client, mira, trip_id)["items"]
    kiyomizu = _item(items, "Kiyomizu-dera at Opening")

    overlap_add = client.post(
        f"/api/trips/{trip_id}/itinerary/items",
        headers=mira,
        json={
            "day": protected_day.isoformat(),
            "start_time": "11:30",
            "title": "Snack stop",
            "end_time": "12:00",
        },
    )
    assert overlap_add.status_code == 409, overlap_add.text
    assert overlap_add.json()["detail"]["conflict"]["protected"] is True

    overlap_patch = client.patch(
        f"/api/trips/{trip_id}/itinerary/items/{kiyomizu['id']}",
        headers=mira,
        json={"start_time": "11:30", "end_time": "13:00"},
    )
    assert overlap_patch.status_code == 409, overlap_patch.text

    missing_end = client.post(
        f"/api/trips/{trip_id}/itinerary/items",
        headers=mira,
        json={
            "day": (date.today() + timedelta(days=1)).isoformat(),
            "start_time": "14:00",
            "title": "Free afternoon",
            "is_protected": True,
        },
    )
    assert missing_end.status_code == 422, missing_end.text
    assert "end_time" in missing_end.json()["detail"]

    reserved = client.post(
        f"/api/trips/{trip_id}/itinerary/items",
        headers=mira,
        json={
            "day": (date.today() + timedelta(days=1)).isoformat(),
            "start_time": "14:00",
            "end_time": "15:00",
            "title": "Free afternoon",
            "is_protected": True,
        },
    )
    assert reserved.status_code == 201, reserved.text
    assert reserved.json()["end_time"] == "15:00"
    assert reserved.json()["is_protected"] is True
    client.delete(
        f"/api/trips/{trip_id}/itinerary/items/{reserved.json()['id']}", headers=mira
    )


def test_f39_twin_adoption_cannot_remove_protected_block(client, mira, kyoto):
    trip_id = kyoto["id"]
    day = date.today() + timedelta(days=2)
    created = client.post(
        f"/api/trips/{trip_id}/itinerary/items",
        headers=mira,
        json={
            "day": day.isoformat(),
            "start_time": "14:00",
            "end_time": "15:00",
            "title": "Reserved quiet hour",
            "is_protected": True,
        },
    )
    assert created.status_code == 201, created.text
    try:
        proposal = client.post(
            f"/api/trips/{trip_id}/twin/propose",
            headers=mira,
            json={
                "activity_ids": [
                    _activity_id("Gion Evening Walk"),
                    _activity_id("Imperial Palace Garden Loop"),
                ],
                "day": day.isoformat(),
            },
        )
        assert proposal.status_code == 201, proposal.text
        proposal_id = proposal.json()["id"]

        approval = client.post(
            f"/api/trips/{trip_id}/proposals/{proposal_id}/approve",
            headers=mira,
            json={"approval": True},
        )
        assert approval.status_code == 409, approval.text
        conflicts = approval.json()["detail"]["conflicts"]
        assert any(
            conflict.get("protected") and "Protected time" in conflict.get("reason", "")
            for conflict in conflicts
        )
        client.post(
            f"/api/trips/{trip_id}/proposals/{proposal_id}/reject", headers=mira
        )
    finally:
        client.delete(
            f"/api/trips/{trip_id}/itinerary/items/{created.json()['id']}", headers=mira
        )


def test_f39_rescue_never_targets_protected_time(client, mira, kyoto):
    trip_id = kyoto["id"]
    day = date.today()
    created = client.post(
        f"/api/trips/{trip_id}/itinerary/items",
        headers=mira,
        json={
            "day": day.isoformat(),
            "start_time": "16:00",
            "end_time": "17:00",
            "title": "Reserved rest",
            "is_protected": True,
        },
    )
    assert created.status_code == 201, created.text
    protected_item = created.json()
    try:
        analysis = client.post(
            f"/api/trips/{trip_id}/rescue/analyze",
            headers=mira,
            json={"kind": "rain", "item_id": protected_item["id"], "extra_minutes": 45},
        )
        assert analysis.status_code == 200, analysis.text
        body = analysis.json()
        assert body["affected"] == []
        assert body["proposals"] == []
        assert body["protected"][0]["item_id"] == protected_item["id"]
        assert body["consequences"]["protected_respected"] is True

        attempt = client.post(
            f"/api/trips/{trip_id}/rescue/propose",
            headers=mira,
            json={
                "kind": "rain",
                "items": [
                    {
                        "item_id": protected_item["id"],
                        "activity_id": _activity_id("Kyoto Railway Museum"),
                        "day": day.isoformat(),
                        "start_time": "16:00",
                    }
                ],
            },
        )
        assert attempt.status_code == 409, attempt.text
        assert "protected" in attempt.json()["detail"].lower()
    finally:
        client.delete(
            f"/api/trips/{trip_id}/itinerary/items/{protected_item['id']}", headers=mira
        )


# ---------------------------------------------------------------------------
# F45 — Fair Trade Negotiator
# ---------------------------------------------------------------------------


def test_f45_negotiation_uses_the_requested_trip_date(client, mira, kyoto):
    trip_id = kyoto["id"]
    for day in (date.today() - timedelta(days=2), date.today(), date.today() + timedelta(days=2)):
        ranked = _recommend(client, mira, trip_id, day)
        assert ranked.status_code == 201, ranked.text
        option_a = [ranked.json()["items"][0]["activity"]["id"]]
        option_b = [ranked.json()["items"][1]["activity"]["id"]]
        response = client.post(
            f"/api/trips/{trip_id}/negotiate",
            headers=mira,
            json={
                "option_a": option_a,
                "option_b": option_b,
                "for_date": day.isoformat(),
            },
        )
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["status"] == "compromise_ready", body
        assert body["compromise"]["activity_id"] in {option_a[0], option_b[0]}

    fallback_a = [_activity_id("Gion Evening Walk")]
    fallback_b = [_activity_id("Imperial Palace Garden Loop")]
    outside = client.post(
        f"/api/trips/{trip_id}/negotiate",
        headers=mira,
        json={
            "option_a": fallback_a,
            "option_b": fallback_b,
            "for_date": (date.fromisoformat(kyoto["end_date"]) + timedelta(days=10)).isoformat(),
        },
    )
    assert outside.status_code == 422, outside.text


# ---------------------------------------------------------------------------
# F21 — Crowd Forecasting (controlled dataset)
# ---------------------------------------------------------------------------


def _insert_crowd_reports(activity_id: str, days_ago: int, hour: int, scores: list[float]):
    db = SessionLocal()
    try:
        with system_context(db):
            base = datetime.combine(date.today() - timedelta(days=days_ago), time(hour=hour))
            ids = []
            for score in scores:
                report = PlaceReport(
                    id=uuid.uuid4().hex,
                    activity_id=activity_id,
                    category="crowd",
                    value={"score": score, "level": "high" if score >= 0.8 else "moderate"},
                    note="Controlled forecasting probe.",
                    observed_at=base,
                    source_type="community",
                    confidence=0.7,
                )
                db.add(report)
                db.flush()
                ids.append(report.id)
            db.commit()
            return ids
    finally:
        db.close()


def _delete_reports(report_ids: list[str]):
    db = SessionLocal()
    try:
        with system_context(db):
            for report_id in report_ids:
                report = db.get(PlaceReport, report_id)
                if report:
                    db.delete(report)
            db.commit()
    finally:
        db.close()


def _forecast(client, headers, trip_id: str, activity_id: str) -> dict:
    response = client.get(
        f"/api/trips/{trip_id}/places/{activity_id}", headers=headers
    )
    assert response.status_code == 200, response.text
    return response.json()["crowd_forecast"]


def test_f21_forecast_requires_eight_reports_and_stays_estimated(client, mira, kyoto):
    trip_id = kyoto["id"]
    activity_id = _activity_id("Kyoto Railway Museum")
    inserted: list[str] = []
    try:
        baseline = _forecast(client, mira, trip_id, activity_id)
        assert baseline["status"] == "insufficient_data"
        assert baseline["required_reports"] == 8
        assert baseline.get("available_reports", 0) == 0

        inserted += _insert_crowd_reports(activity_id, 7, 11, [0.6] * 7)
        below = _forecast(client, mira, trip_id, activity_id)
        assert below["status"] == "insufficient_data"
        assert below["available_reports"] == 7
        assert "forecasts" not in below

        inserted += _insert_crowd_reports(activity_id, 7, 10, [0.6])
        predicted = _forecast(client, mira, trip_id, activity_id)
        assert predicted["status"] == "predicted"
        assert predicted["provenance"] == "ESTIMATED"
        assert predicted["model"] == "bucket-forecast-v2"
        assert "PREDICTED" in predicted["disclosure"]
        assert "not a verified measurement" in predicted["disclosure"]
        assert predicted["observed"]["reports_used"] == 8
        assert predicted["observed"]["reports_seen"] == 8
        assert "forecasts" not in predicted
        assert predicted["predicted"]["provenance"] == "ESTIMATED"
        entry = predicted["predicted"]["forecasts"][0]
        assert entry["reports"] == 8
        assert set(
            [
                "confidence",
                "confidence_label",
                "freshness",
                "mean_report_age_days",
                "spread",
                "interval_80",
                "granularity",
            ]
        ) <= set(entry)
        assert 0 <= entry["confidence"] <= 0.9
        assert 0 <= entry["freshness"] <= 1
        assert entry["granularity"] == "weekday_bucket"
        low, high = entry["interval_80"]
        assert 0 <= low <= entry["expected_level"] <= high <= 1

        inserted += _insert_crowd_reports(activity_id, 14, 11, [0.6] * 4)
        more = _forecast(client, mira, trip_id, activity_id)
        consistent = next(item for item in more["predicted"]["forecasts"] if item["reports"] == 12)
        assert consistent["confidence"] > entry["confidence"]

        inserted += _insert_crowd_reports(
            activity_id, 9, 11, [0.1, 0.9] * 4
        )
        mixed = _forecast(client, mira, trip_id, activity_id)
        spread_entry = next(
            item for item in mixed["predicted"]["forecasts"] if item["spread"] > 0.3
        )
        assert spread_entry["confidence"] < consistent["confidence"]
    finally:
        _delete_reports(inserted)


# ---------------------------------------------------------------------------
# F27 — Load Balancer summary
# ---------------------------------------------------------------------------


def _walk_keys(payload):
    if isinstance(payload, dict):
        for key, value in payload.items():
            yield key
            yield from _walk_keys(value)
    elif isinstance(payload, list):
        for value in payload:
            yield from _walk_keys(value)


def test_f27_task_summary_matches_planner_and_stays_private(client, mira, noor, kyoto):
    trip_id = kyoto["id"]
    tasks = client.get(f"/api/trips/{trip_id}/tasks", headers=mira)
    assert tasks.status_code == 200, tasks.text
    rows = tasks.json()["items"]

    expected: dict[str | None, dict[str, int]] = {}
    for row in rows:
        bucket = expected.setdefault(row["assignee_id"], {"open": 0, "done": 0, "total": 0})
        bucket["total"] += 1
        if row["status"] == "done":
            bucket["done"] += 1
        else:
            bucket["open"] += 1

    summary = client.get(f"/api/trips/{trip_id}/tasks/summary", headers=mira)
    assert summary.status_code == 200, summary.text
    body = summary.json()
    assert body["totals"] == {
        "open": sum(bucket["open"] for bucket in expected.values()),
        "done": sum(bucket["done"] for bucket in expected.values()),
        "total": len(rows),
    }
    by_assignee = {entry["user_id"]: entry for entry in body["by_assignee"]}
    for assignee_id, bucket in expected.items():
        if assignee_id is None:
            assert body["unassigned"] == bucket
        else:
            assert by_assignee[assignee_id]["open"] == bucket["open"]
            assert by_assignee[assignee_id]["total"] == bucket["total"]
    opens = [entry["open"] for entry in body["load"]]
    assert opens == sorted(opens, reverse=True)

    keys = set(_walk_keys(body))
    assert "title" not in keys and "description" not in keys
    assert "Counts only" in body["disclosure"]

    outsider = client.get(f"/api/trips/{trip_id}/tasks/summary", headers=noor)
    assert outsider.status_code == 404


# ---------------------------------------------------------------------------
# F12 — Caption suggestion honesty
# ---------------------------------------------------------------------------


def test_f12_caption_is_a_template_not_ai(client, mira, kyoto):
    trip_id = kyoto["id"]
    timeline = client.get(f"/api/trips/{trip_id}/memories", headers=mira)
    assert timeline.status_code == 200, timeline.text
    memory_id = timeline.json()["days"][0]["memories"][0]["id"]

    suggestion = client.post(
        f"/api/trips/{trip_id}/memories/{memory_id}/caption", headers=mira
    )
    assert suggestion.status_code == 200, suggestion.text
    body = suggestion.json()
    assert body["ai_generated"] is False
    assert body["generator"] == "template"
    assert body["approved"] is False
    assert "not AI-generated" in body["disclosure"]


# ---------------------------------------------------------------------------
# F14 — Verified community reports stay REPORTED
# ---------------------------------------------------------------------------


def test_f14_moderator_verification_never_promotes_community_reports(client, mira, aiko, kyoto):
    trip_id = kyoto["id"]
    activity_id = _activity_id("Kyoto Railway Museum")
    created = client.post(
        f"/api/trips/{trip_id}/place-reports",
        headers=aiko,
        json={
            "activity_id": activity_id,
            "category": "quality",
            "value": {"status": "well kept"},
            "note": "Read from the museum notice board.",
            "source_type": "community",
        },
    )
    assert created.status_code == 201, created.text
    report_id = created.json()["id"]
    assert created.json()["verification"] == "unverified"

    verified = client.post(
        f"/api/admin/place-reports/{report_id}/verify?verify=true", headers=mira
    )
    assert verified.status_code == 200, verified.text
    body = verified.json()
    assert body["source_type"] == "community"
    assert body["provenance"] == "REPORTED"
    assert "still shown as REPORTED" in body["provenance_note"]

    listed = client.get(
        f"/api/trips/{trip_id}/place-reports",
        headers=mira,
        params={"activity_id": activity_id},
    )
    assert listed.status_code == 200, listed.text
    row = next(item for item in listed.json()["items"] if item["id"] == report_id)
    assert row["verified"] is True
    assert row["verification"] == "moderator_verified"
    assert row["provenance"] == "REPORTED"

    detail = client.get(
        f"/api/trips/{trip_id}/places/{activity_id}", headers=mira
    ).json()
    quality = next(
        category for category in detail["reports"]["categories"] if category["category"] == "quality"
    )
    aggregated = next(entry for entry in quality["reports"] if entry["id"] == report_id)
    assert aggregated["verified"] is True
    assert aggregated["verification"] == "moderator_verified"
    assert aggregated["provenance"] == "REPORTED"

    nishiki_id = _item(_itinerary(client, mira, trip_id)["items"], "Nishiki Market Morning Graze")[
        "activity_id"
    ]
    nishiki_reports = client.get(
        f"/api/trips/{trip_id}/place-reports",
        headers=mira,
        params={"activity_id": nishiki_id},
    ).json()["items"]
    official = next(item for item in nishiki_reports if item["source_type"] == "official")
    official_verify = client.post(
        f"/api/admin/place-reports/{official['id']}/verify?verify=true", headers=mira
    )
    assert official_verify.status_code == 200, official_verify.text
    assert official_verify.json()["provenance"] == "VERIFIED"
    assert "Official source" in official_verify.json()["provenance_note"]


# ---------------------------------------------------------------------------
# F36 — One Question That Matters
# ---------------------------------------------------------------------------


def test_f36_question_only_mentions_members_who_have_not_answered(client, mira, kyoto):
    trip_id = kyoto["id"]
    coverage = _pulse_coverage(trip_id)
    first = _recommend(client, mira, trip_id, date.today())
    assert first.status_code == 201, first.text
    meta = first.json()["meta"]
    assert meta["pulse_coverage"] == f"{coverage['answered']}/{coverage['total']}"
    question = meta["clarifying_question"]
    if question is not None:
        assert (
            f"{coverage['missing']} of {coverage['total']} members haven't shared a Trip Pulse"
            in question
        )

    leo = _login(client, "leo@safar.demo")
    pulse = client.put(
        f"/api/trips/{trip_id}/pulse",
        headers=leo,
        json={"energy": 3, "interests": ["food"], "available_minutes": 300},
    )
    assert pulse.status_code == 200, pulse.text

    after = _pulse_coverage(trip_id)
    assert after["answered"] >= coverage["answered"]
    second = _recommend(client, mira, trip_id, date.today())
    assert second.status_code == 201, second.text
    meta = second.json()["meta"]
    assert meta["pulse_coverage"] == f"{after['answered']}/{after['total']}"
    if after["missing"] == 0:
        assert meta["clarifying_question"] is None
