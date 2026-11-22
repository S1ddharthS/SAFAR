"""Phase 7 evaluation: recommendation intelligence, fairness and diversity.

The metrics asserted here are the promises of the ranking upgrade: hard
constraints are never violated, fairness is measurable, diversity changes the
selected set (not eligibility), and consented feedback can only nudge a score
within a documented bound.
"""

import json

from app.db.context import system_context
from app.db.session import SessionLocal
from app.models import Trip, TripMember
from app.services.engine import (
    DIVERSITY_MAX_PENALTY,
    FEEDBACK_MAX_ADJUSTMENT,
    MODE_META,
    _feedback_adjustments,
    build_member_contexts,
)


def _recommend(client, headers, trip_id, mode, for_date, limit=6):
    response = client.post(
        f"/api/trips/{trip_id}/engine/recommend",
        headers=headers,
        json={"mode": mode, "for_date": for_date, "limit": limit},
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_batch_meta_exposes_measurable_evaluation(client, mira, kyoto):
    batch = _recommend(client, mira, kyoto["id"], "everyone_wins", kyoto["start_date"])
    meta = batch["meta"]
    evaluation = meta["evaluation"]

    assert set(evaluation) == {"fairness", "satisfaction", "constraints", "diversity"}
    assert 0.0 <= evaluation["fairness"]["jain_index"] <= 1.0
    assert evaluation["fairness"]["least_served_member_mean_fit"] >= 0
    assert evaluation["fairness"]["member_mean_spread"] >= 0
    assert 0 <= evaluation["satisfaction"]["mean_average_fit"] <= 100
    assert 0 <= evaluation["satisfaction"]["mean_minimum_fit"] <= 100
    assert evaluation["constraints"]["violations"] == 0
    assert evaluation["constraints"]["excluded"] >= 0
    assert 0.0 <= evaluation["diversity"]["mean_pairwise_similarity"] <= 1.0
    assert evaluation["diversity"]["unique_tags"] > 0

    assert meta["feedback_learning"]["enabled"] is True
    assert meta["feedback_learning"]["max_adjustment"] == FEEDBACK_MAX_ADJUSTMENT
    assert "feedback" in meta["ranking_formula"]
    assert "diversity" in meta["ranking_formula"]

    for item in batch["items"]:
        explanation = item["explanation"]
        assert explanation["selection"]["note"]
        assert explanation["metrics"]["feedback_adjustment"] == 0.0
        assert 0 <= explanation["metrics"]["diversity_penalty"] <= DIVERSITY_MAX_PENALTY
    scores = [item["score"] for item in batch["items"]]
    assert scores == sorted(scores, reverse=True)


def test_feedback_learning_is_bounded_and_private(client, mira, jonas, kyoto):
    first = _recommend(client, mira, kyoto["id"], "everyone_wins", kyoto["start_date"])
    target = first["items"][0]
    recommendation_id = target["id"]
    activity_id = target["activity_id"]

    for headers in (mira, jonas):
        response = client.post(
            f"/api/trips/{kyoto['id']}/recommendations/{recommendation_id}/feedback",
            headers=headers,
            json={"sentiment": "loved", "consented": True},
        )
        assert response.status_code == 200, response.text

    batch = _recommend(client, mira, kyoto["id"], "everyone_wins", kyoto["start_date"])
    learning = batch["meta"]["feedback_learning"]
    assert learning["applied_activities"] >= 1
    assert learning["consented_raters"] >= 2

    adjusted = next(
        (item for item in batch["items"] if item["activity_id"] == activity_id), None
    )
    assert adjusted is not None, "a positive consented nudge should keep the item in the top set"
    assert 0 < adjusted["explanation"]["metrics"]["feedback_adjustment"] <= FEEDBACK_MAX_ADJUSTMENT
    assert any(
        "feedback" in reason for reason in adjusted["explanation"]["why_selected"]
    )

    payload = json.dumps(batch)
    assert "loved" not in payload
    assert "sentiment" not in batch["meta"]["feedback_learning"]
    assert "member_id" not in json.dumps(learning)
    assert "user_id" not in json.dumps(learning)
    assert "Mira" not in json.dumps(learning) and "Jonas" not in json.dumps(learning)


def test_unconsented_feedback_does_not_change_ranking(client, mira, kyoto):
    first = _recommend(client, mira, kyoto["id"], "surprise_us", kyoto["start_date"])
    target = first["items"][0]
    client.post(
        f"/api/trips/{kyoto['id']}/recommendations/{target['id']}/feedback",
        headers=mira,
        json={"sentiment": "not_for_me", "consented": False},
    )
    batch = _recommend(client, mira, kyoto["id"], "surprise_us", kyoto["start_date"])
    assert batch["meta"]["feedback_learning"]["applied_activities"] == 0
    for item in batch["items"]:
        assert item["explanation"]["metrics"]["feedback_adjustment"] == 0.0


def test_all_three_modes_stay_explainable(client, mira, kyoto):
    for mode, marker in (
        ("everyone_wins", "everyone wins pick"),
        ("your_turn", "your turn pick"),
        ("surprise_us", "surprise us pick"),
    ):
        batch = _recommend(client, mira, kyoto["id"], mode, kyoto["start_date"], limit=4)
        assert batch["mode"] == mode
        assert batch["meta"]["mode_meta"] == MODE_META[mode]
        assert marker in batch["items"][0]["explanation"]["summary"]
        assert batch["items"][0]["explanation"]["constraints_checked"]
        assert batch["meta"]["evaluation"]["fairness"]["jain_index"] >= 0


def test_feedback_requires_a_three_member_group(client, kyoto):
    """Seeded Reykjavik has two members with real consented feedback."""
    db = SessionLocal()
    try:
        with system_context(db):
            trip = db.query(Trip).filter(Trip.name.contains("Reykjavik")).first()
            assert trip is not None
            members = (
                db.query(TripMember)
                .filter(TripMember.trip_id == trip.id, TripMember.status == "active")
                .all()
            )
            assert len(members) == 2
            contexts = build_member_contexts(db, trip, members, kyoto["start_date"])
            adjustments, raters = _feedback_adjustments(db, trip, contexts)
            assert adjustments == {}
            assert raters == 0
    finally:
        db.close()
