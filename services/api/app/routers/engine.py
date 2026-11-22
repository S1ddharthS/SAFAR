"""Group Experience Engine, Trip Twin, Trip Rescue and Fair Trade APIs.

Every recommendation, alternative and repair is persisted or returned as a
proposal. None of these endpoints mutate the confirmed itinerary: adoption
always goes through the voting and approval workflow in the itinerary router.
"""

from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.deps import (
    get_current_user,
    get_db,
    get_trip_and_member,
    trip_scope_guard,
)
from app.core.realtime import manager
from app.models import (
    Activity,
    ItineraryItem,
    ItineraryProposal,
    JourneyPact,
    Place,
    Recommendation,
    RecommendationBatch,
    RecommendationFeedback,
    Trip,
    TripMember,
    User,
)
from app.routers.itinerary import _proposal_impact
from app.schemas.schemas import (
    NegotiateIn,
    RecommendationFeedbackIn,
    RecommendationProposeIn,
    RecommendIn,
    RescueIn,
    RescueProposeIn,
    TwinCompareIn,
    TwinProposeIn,
)
from app.services import rescue as rescue_service
from app.services import twin as twin_service
from app.services.common import (
    audit,
    event_payload,
    notify_trip_members,
)
from app.services.engine import (
    ENGINE_VERSION,
    MODE_META,
    build_member_contexts,
    generate_recommendations,
)
from app.services.feedback import apply_feedback_to_dna, upsert_activity_feedback
from app.services.schedule import find_conflict, parse_hhmm
from app.services.serializers import proposal_out, recommendation_out

router = APIRouter(
    prefix="/api/trips",
    tags=["engine"],
    dependencies=[Depends(trip_scope_guard)],
)


def _trip(db, trip_id, user, roles=None):
    return get_trip_and_member(trip_id, db, user, roles)


def _active_members(db: Session, trip_id: str) -> list[TripMember]:
    return (
        db.query(TripMember)
        .filter(TripMember.trip_id == trip_id, TripMember.status == "active")
        .all()
    )


def _within_trip(trip: Trip, day: date) -> None:
    if day < trip.start_date or day > trip.end_date:
        raise HTTPException(
            status_code=422,
            detail=(
                f"{day.isoformat()} is outside the trip dates "
                f"({trip.start_date.isoformat()} to {trip.end_date.isoformat()})."
            ),
        )


def _activity_in_trip(db: Session, trip: Trip, activity_id: str) -> Activity:
    activity = db.get(Activity, activity_id)
    if not activity:
        raise HTTPException(status_code=404, detail="Activity not found")
    if activity.destination_id != trip.destination_id:
        raise HTTPException(status_code=422, detail="Activity is outside this trip's destination")
    return activity


def _batch_out(db: Session, batch: RecommendationBatch, viewer_id: str) -> dict:
    recs = (
        db.query(Recommendation)
        .filter(Recommendation.batch_id == batch.id)
        .order_by(Recommendation.rank)
        .all()
    )
    activity_ids = [rec.activity_id for rec in recs]
    activities = (
        db.query(Activity).filter(Activity.id.in_(activity_ids)).all() if activity_ids else []
    )
    activity_map = {activity.id: activity for activity in activities}
    place_ids = {activity.place_id for activity in activities if activity.place_id}
    places = db.query(Place).filter(Place.id.in_(place_ids)).all() if place_ids else []
    place_map = {place.id: place for place in places}
    feedback_rows = (
        db.query(RecommendationFeedback)
        .filter(
            RecommendationFeedback.recommendation_id.in_([rec.id for rec in recs]),
            RecommendationFeedback.user_id == viewer_id,
        )
        .all()
        if recs
        else []
    )
    my_feedback = {row.recommendation_id: row.sentiment for row in feedback_rows}
    return {
        "id": batch.id,
        "mode": batch.mode,
        "mode_meta": MODE_META.get(batch.mode, {}),
        "for_date": batch.for_date,
        "model_version": batch.model_version,
        "meta": batch.meta or {},
        "created_at": batch.created_at,
        "created_by": batch.created_by,
        "items": [
            {
                **recommendation_out(
                    rec,
                    activity_map.get(rec.activity_id),
                    place_map.get(
                        getattr(activity_map.get(rec.activity_id), "place_id", None)
                    ),
                ),
                "my_feedback": my_feedback.get(rec.id),
            }
            for rec in recs
        ],
    }


@router.post("/{trip_id}/engine/recommend", status_code=201)
async def recommend(
    trip_id: str,
    payload: RecommendIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    for_date = payload.for_date or date.today()
    _within_trip(trip, for_date)
    members = _active_members(db, trip.id)
    result = generate_recommendations(
        db,
        trip,
        members,
        mode=payload.mode,
        for_date=for_date,
        limit=payload.limit,
    )
    if result.get("error"):
        raise HTTPException(status_code=422, detail=result["error"])
    if not result["items"]:
        raise HTTPException(
            status_code=422,
            detail=(
                "No activity passes every hard constraint for this group today. "
                "Adjust a Trip Pulse, budget limit or radius and try again."
            ),
        )

    meta = {
        **result["meta"],
        "mode_meta": result["mode_meta"],
        "clarifying_question": result.get("clarifying_question"),
        "exclusion_reasons": result.get("exclusion_reasons", {}),
        "target_member": result["target"].label if result.get("target") else None,
        "alternative_count": len(result.get("all_ranked_ids", [])) - len(result["items"]),
    }
    batch = RecommendationBatch(
        trip_id=trip.id,
        mode=payload.mode,
        for_date=for_date,
        model_version=ENGINE_VERSION,
        meta=meta,
        created_by=user.id,
    )
    db.add(batch)
    db.flush()
    for rank, ranked in enumerate(result["items"], start=1):
        db.add(
            Recommendation(
                batch_id=batch.id,
                trip_id=trip.id,
                activity_id=ranked.activity.id,
                rank=rank,
                score=ranked.score,
                average_fit=ranked.average_fit,
                minimum_fit=ranked.minimum_fit,
                fairness_spread=ranked.fairness_spread,
                novelty=ranked.novelty,
                penalties=ranked.penalties,
                explanation=ranked.explanation,
                status="suggested",
            )
        )
    audit(
        db,
        action="engine.recommend",
        entity_type="recommendation_batch",
        entity_id=batch.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"mode": payload.mode, "for_date": for_date.isoformat()},
    )
    db.commit()
    await manager.broadcast(
        trip.id,
        event_payload("engine.updated", trip_id=trip.id, mode=payload.mode),
    )
    return _batch_out(db, batch, user.id)


@router.get("/{trip_id}/engine/latest")
def latest_batch(
    trip_id: str,
    mode: str | None = Query(default=None, pattern=r"^(everyone_wins|your_turn|surprise_us)$"),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    query = db.query(RecommendationBatch).filter(RecommendationBatch.trip_id == trip.id)
    if mode:
        query = query.filter(RecommendationBatch.mode == mode)
    batch = query.order_by(RecommendationBatch.created_at.desc()).first()
    if not batch:
        return {
            "id": None,
            "mode": mode or "everyone_wins",
            "mode_meta": MODE_META.get(mode or "everyone_wins", {}),
            "items": [],
            "meta": {},
            "message": "No recommendation batch yet. Generate one to get started.",
        }
    return _batch_out(db, batch, user.id)


@router.get("/{trip_id}/engine/batches")
def list_batches(
    trip_id: str,
    limit: int = Query(default=10, ge=1, le=50),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    batches = (
        db.query(RecommendationBatch)
        .filter(RecommendationBatch.trip_id == trip.id)
        .order_by(RecommendationBatch.created_at.desc())
        .limit(limit)
        .all()
    )
    return {
        "items": [
            {
                "id": batch.id,
                "mode": batch.mode,
                "mode_meta": MODE_META.get(batch.mode, {}),
                "for_date": batch.for_date,
                "created_at": batch.created_at,
                "summary": (batch.meta or {}).get("disclosure"),
            }
            for batch in batches
        ]
    }


@router.get("/{trip_id}/engine/modes")
def list_modes(trip_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    _trip(db, trip_id, user)
    return {
        "items": [
            {"id": mode, "label": meta["label"], "intent": meta["intent"]}
            for mode, meta in MODE_META.items()
        ]
    }


@router.post("/{trip_id}/recommendations/{recommendation_id}/feedback")
def recommendation_feedback(
    trip_id: str,
    recommendation_id: str,
    payload: RecommendationFeedbackIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    rec = db.get(Recommendation, recommendation_id)
    if not rec or rec.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Recommendation not found")
    activity = db.get(Activity, rec.activity_id)
    if not activity:
        raise HTTPException(status_code=404, detail="Activity not found")

    row = (
        db.query(RecommendationFeedback)
        .filter(
            RecommendationFeedback.recommendation_id == rec.id,
            RecommendationFeedback.user_id == user.id,
        )
        .first()
    )
    if not row:
        row = RecommendationFeedback(
            recommendation_id=rec.id, user_id=user.id, sentiment=payload.sentiment
        )
        db.add(row)
    row.sentiment = payload.sentiment
    row.consented = payload.consented

    upsert_activity_feedback(
        db,
        user_id=user.id,
        trip_id=trip.id,
        activity=activity,
        sentiment=payload.sentiment,
        consented=payload.consented,
    )
    dna_update = apply_feedback_to_dna(
        db, user, activity, payload.sentiment, consented=payload.consented
    )
    audit(
        db,
        action="recommendation.feedback",
        entity_type="recommendation",
        entity_id=rec.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"sentiment": payload.sentiment, "consented": payload.consented},
    )
    db.commit()
    return {
        "ok": True,
        "sentiment": payload.sentiment,
        "consented": payload.consented,
        "journey_dna": dna_update,
        "note": (
            "Feedback stays private to you. It shapes your Journey DNA only while you consent."
            if payload.consented
            else "Saved privately. Because consent was declined, your Journey DNA was not changed."
        ),
    }


def _create_proposal(
    db: Session,
    trip: Trip,
    user: User,
    *,
    kind: str,
    title: str,
    summary: str | None,
    day: date | None,
    payload: dict,
) -> tuple[ItineraryProposal, dict]:
    proposal = ItineraryProposal(
        trip_id=trip.id,
        kind=kind,
        title=title,
        summary=summary,
        target_day=day,
        created_by=user.id,
        payload=payload,
    )
    db.add(proposal)
    db.flush()
    impact = _proposal_impact(db, trip, proposal)
    audit(
        db,
        action="proposal.create",
        entity_type="itinerary_proposal",
        entity_id=proposal.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"kind": kind, "title": title, "origin": "engine"},
    )
    notify_trip_members(
        db,
        trip,
        kind="proposal_created",
        title=f"New proposal: {title}",
        body=f"{user.display_name} turned an engine suggestion into a group decision.",
        link=f"/trips/{trip.id}/voting",
        exclude_user_id=user.id,
    )
    return proposal, impact


@router.post("/{trip_id}/recommendations/{recommendation_id}/propose", status_code=201)
async def propose_recommendation(
    trip_id: str,
    recommendation_id: str,
    payload: RecommendationProposeIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    _within_trip(trip, payload.day)
    rec = db.get(Recommendation, recommendation_id)
    if not rec or rec.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Recommendation not found")
    activity = _activity_in_trip(db, trip, rec.activity_id)

    start = parse_hhmm(payload.start_time)
    if start is None:
        raise HTTPException(status_code=422, detail="start_time must use HH:MM")
    day_items = (
        db.query(ItineraryItem)
        .filter(
            ItineraryItem.trip_id == trip.id,
            ItineraryItem.day == payload.day,
            ItineraryItem.status == "confirmed",
        )
        .all()
    )
    conflict = find_conflict(
        db,
        day_items,
        start_minutes=start,
        duration_minutes=activity.duration_minutes or 90,
    )
    if conflict:
        raise HTTPException(
            status_code=409,
            detail={
                "message": (
                    "This start time overlaps protected time. The engine will not "
                    "place an activity on top of a protected block."
                    if conflict["protected"]
                    else "This start time overlaps another confirmed item."
                ),
                "conflict": conflict,
            },
        )

    proposal, impact = _create_proposal(
        db,
        trip,
        user,
        kind="add_activity",
        title=f"Add {activity.name}",
        summary=(
            "Suggested by the Group Experience Engine. "
            "The group must approve before the itinerary changes."
        ),
        day=payload.day,
        payload={
            "activity_id": activity.id,
            "day": payload.day.isoformat(),
            "start_time": payload.start_time,
            "recommendation_id": rec.id,
            "source": ENGINE_VERSION,
        },
    )
    rec.status = "proposed"
    db.commit()
    await manager.broadcast(
        trip.id,
        event_payload("proposal.created", trip_id=trip.id, proposal_id=proposal.id),
    )
    return {**proposal_out(db, proposal, user.id), "impact": impact}


@router.post("/{trip_id}/twin/compare")
def twin_compare(
    trip_id: str,
    payload: TwinCompareIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    if not payload.activity_ids:
        raise HTTPException(
            status_code=422,
            detail="Provide at least one alternative activity to compare.",
        )
    for activity_id in payload.activity_ids:
        _activity_in_trip(db, trip, activity_id)
    if len(set(payload.activity_ids)) != len(payload.activity_ids):
        raise HTTPException(status_code=422, detail="Duplicate activities in the alternative")
    day = payload.day or date.today()
    _within_trip(trip, day)
    items = (
        db.query(ItineraryItem)
        .filter(
            ItineraryItem.trip_id == trip.id,
            ItineraryItem.day == day,
            ItineraryItem.status == "confirmed",
        )
        .all()
    )
    contexts = build_member_contexts(db, trip, _active_members(db, trip.id), day)
    result = twin_service.compare_plan(db, trip, contexts, items, payload.activity_ids, day)
    result["generated_at"] = result["generated_at"].isoformat()
    return result


@router.post("/{trip_id}/twin/propose", status_code=201)
async def twin_propose(
    trip_id: str,
    payload: TwinProposeIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    day = payload.day or trip.start_date
    _within_trip(trip, day)
    if len(set(payload.activity_ids)) != len(payload.activity_ids):
        raise HTTPException(status_code=422, detail="Duplicate activities in the alternative")
    activities = [_activity_in_trip(db, trip, activity_id) for activity_id in payload.activity_ids]
    proposal, impact = _create_proposal(
        db,
        trip,
        user,
        kind="twin_adopt",
        title="Adopt a Trip Twin alternative",
        summary=(
            f"Replaces {day.isoformat()} with: "
            + ", ".join(activity.name for activity in activities)
            + ". Read-only comparison only; adoption needs group approval."
        ),
        day=day,
        payload={
            "day": day.isoformat(),
            "items": [
                {"activity_id": activity.id, "day": day.isoformat(), "start_time": "09:00"}
                for activity in activities
            ],
        },
    )
    db.commit()
    await manager.broadcast(
        trip.id,
        event_payload("proposal.created", trip_id=trip.id, proposal_id=proposal.id),
    )
    return {**proposal_out(db, proposal, user.id), "impact": impact}


@router.post("/{trip_id}/rescue/analyze")
def rescue_analyze(
    trip_id: str,
    payload: RescueIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    return rescue_service.analyse_rescue(
        db,
        trip,
        _active_members(db, trip.id),
        kind=payload.kind,
        item_id=payload.item_id,
        extra_minutes=payload.extra_minutes,
        note=payload.note,
    )


@router.post("/{trip_id}/rescue/propose", status_code=201)
async def rescue_propose(
    trip_id: str,
    payload: RescueProposeIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    if not payload.items:
        raise HTTPException(
            status_code=422,
            detail="Select at least one replacement from the rescue analysis.",
        )
    items = []
    for entry in payload.items:
        _within_trip(trip, entry.day)
        item = db.get(ItineraryItem, entry.item_id)
        if not item or item.trip_id != trip.id or item.status != "confirmed":
            raise HTTPException(status_code=404, detail="A rescue target item was not found")
        if item.is_protected:
            raise HTTPException(
                status_code=409,
                detail=f"\"{item.title}\" is protected time and cannot be replaced by Trip Rescue.",
            )
        activity = _activity_in_trip(db, trip, entry.activity_id)
        start = parse_hhmm(entry.start_time)
        if start is None:
            raise HTTPException(status_code=422, detail="start_time must use HH:MM")
        day_items = (
            db.query(ItineraryItem)
            .filter(
                ItineraryItem.trip_id == trip.id,
                ItineraryItem.day == entry.day,
                ItineraryItem.status == "confirmed",
            )
            .all()
        )
        conflict = find_conflict(
            db,
            day_items,
            start_minutes=start,
            duration_minutes=activity.duration_minutes or 90,
            ignore_item_ids={item.id},
        )
        if conflict:
            raise HTTPException(
                status_code=409,
                detail={
                    "message": (
                        f"The replacement would overlap protected time ({conflict['title']})."
                        if conflict["protected"]
                        else f"The replacement would overlap {conflict['title']}."
                    ),
                    "conflict": conflict,
                },
            )
        items.append(
            {
                "item_id": item.id,
                "activity_id": activity.id,
                "day": entry.day.isoformat(),
                "start_time": entry.start_time,
                "notes": f"Trip Rescue ({payload.kind}) replacement",
                "title": item.title,
            }
        )
    title = f"Trip Rescue: {payload.kind.replace('_', ' ').title()}"
    summary = (
        payload.note
        or "Replaces affected activities after a disruption. Shown as changes only; nothing is applied until approved."
    )
    pact = db.query(JourneyPact).filter(JourneyPact.trip_id == trip.id).first()
    proposal, impact = _create_proposal(
        db,
        trip,
        user,
        kind="rescue",
        title=title,
        summary=summary,
        day=payload.items[0].day,
        payload={
            "kind": payload.kind,
            "extra_minutes": payload.extra_minutes,
            "note": payload.note,
            "items": items,
        },
    )
    db.commit()
    await manager.broadcast(
        trip.id,
        event_payload("proposal.created", trip_id=trip.id, proposal_id=proposal.id),
    )
    response = {**proposal_out(db, proposal, user.id), "impact": impact}
    if pact:
        response["pact"] = {
            "must_do": pact.must_do or [],
            "flexible": pact.flexible or [],
            "note": "Pact conflicts block approval until the group adds an exception.",
        }
    return response


@router.post("/{trip_id}/negotiate")
def negotiate(
    trip_id: str,
    payload: NegotiateIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    for activity_id in set(payload.option_a + payload.option_b):
        _activity_in_trip(db, trip, activity_id)
    if payload.for_date:
        _within_trip(trip, payload.for_date)
    return rescue_service.compromise(
        db,
        trip,
        _active_members(db, trip.id),
        payload.option_a,
        payload.option_b,
        for_date=payload.for_date,
    )
