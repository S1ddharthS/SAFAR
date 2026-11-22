"""Discovery, place intelligence, communities and traveller matching.

Covers F03, F10, F14, F15, F16, F17, F21, F29-F31, F40-F42 and the Respect
Filter. All community signals carry provenance and freshness; none of them
are presented as verified facts.
"""

import json
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.config import settings

from app.core.deps import (
    get_current_user,
    get_db,
    get_optional_user,
    get_trip_and_member,
    trip_scope_guard,
)
from app.models import (
    Activity,
    AbuseReport,
    AuditLog,
    CircleMember,
    CirclePost,
    ConnectionRequest,
    Destination,
    LocalContributor,
    Notification,
    Place,
    PlaceReport,
    Profile,
    SavedInspiration,
    TravelCircle,
    TravellerMatch,
    Trip,
    TripMemory,
    User,
    UserBlock,
)
from app.models.models import utcnow
from app.schemas.schemas import (
    AbuseReportIn,
    ConnectionCreate,
    ConnectionDecision,
    ContributorIn,
    CirclePostCreate,
    ExpectationIn,
    FeedbackIn,
    InspirationIn,
    InspirationReviewIn,
    PlaceReportIn,
    PlaceReportUpdate,
)
from app.services import discovery as discovery_service
from app.services import places as place_service
from app.services.common import audit, notify_trip_members
from app.services.feedback import apply_feedback_to_dna, upsert_activity_feedback
from app.services.geo import haversine_km, travel_minutes
from app.services.media import verify_media_request
from app.services.serializers import (
    activity_out,
    destination_out,
    place_out,
    report_out,
    user_public,
)

router = APIRouter(
    prefix="/api",
    tags=["discovery"],
    dependencies=[Depends(trip_scope_guard)],
)
MEDIA_ROOT = settings.storage_dir
_MEDIA_NAME_PATTERN = re.compile(r"^[A-Za-z0-9._-]+$")


def _trip(db, trip_id, user, roles=None):
    return get_trip_and_member(trip_id, db, user, roles)


def _naive_utc(value: datetime | None) -> datetime:
    if value is None:
        return utcnow()
    if value.tzinfo is None:
        return value
    return value.astimezone(timezone.utc).replace(tzinfo=None)


def _catalog_freshness(activity: Activity) -> dict:
    if not activity.last_verified_at:
        return {"label": "No recorded verification", "age_days": None}
    age = max(0, (utcnow() - activity.last_verified_at).days)
    label = (
        "Fresh catalog entry"
        if age <= 30
        else "Aging catalog entry"
        if age <= 180
        else "Stale catalog entry"
    )
    return {"label": label, "age_days": age}


def _activity_place_maps(db: Session, activities: list[Activity]):
    place_ids = {a.place_id for a in activities if a.place_id}
    destination_ids = {a.destination_id for a in activities if a.destination_id}
    places = db.query(Place).filter(Place.id.in_(place_ids)).all() if place_ids else []
    destinations = (
        db.query(Destination).filter(Destination.id.in_(destination_ids)).all()
        if destination_ids
        else []
    )
    return {p.id: p for p in places}, {d.id: d for d in destinations}


@router.get("/destinations")
def list_destinations(
    q: str | None = Query(default=None, max_length=120),
    tag: str | None = Query(default=None, max_length=60),
    user: User | None = Depends(get_optional_user),
    db: Session = Depends(get_db),
):
    query = db.query(Destination)
    if q:
        query = query.filter(Destination.name.ilike(f"%{q.lower()}%"))
    destinations = query.order_by(Destination.name).all()
    counts = {
        row[0]: row[1]
        for row in db.query(Activity.destination_id, func.count(Activity.id))
        .group_by(Activity.destination_id)
        .all()
    }
    if tag:
        key = tag.lower()
        destinations = [
            destination
            for destination in destinations
            if key in {str(item).lower() for item in destination.tags or []}
        ]
    return {
        "items": [
            {
                **destination_out(destination),
                "activity_count": counts.get(destination.id, 0),
                "disclosure": "Curated catalog — not a live provider inventory feed.",
            }
            for destination in destinations
        ]
    }


@router.get("/destinations/{destination_id}")
def get_destination(
    destination_id: str,
    user: User | None = Depends(get_optional_user),
    db: Session = Depends(get_db),
):
    destination = db.get(Destination, destination_id)
    if not destination:
        raise HTTPException(status_code=404, detail="Destination not found")
    activities = (
        db.query(Activity)
        .filter(Activity.destination_id == destination.id)
        .order_by(Activity.popularity.desc())
        .limit(12)
        .all()
    )
    place_map, _ = _activity_place_maps(db, activities)
    return {
        **destination_out(destination),
        "sample_activities": [
            activity_out(activity, place_map.get(activity.place_id), destination)
            for activity in activities
        ],
    }


@router.get("/activities/search")
def search_activities(
    q: str | None = Query(default=None, max_length=120),
    destination_id: str | None = None,
    tags: str | None = Query(default=None, max_length=200),
    max_budget: float | None = Query(default=None, ge=0),
    max_duration: int | None = Query(default=None, ge=15, le=1440),
    indoor: bool | None = None,
    accessible: bool = False,
    lens: str = Query(default="balanced", pattern=r"^(balanced|iconic|similar)$"),
    limit: int = Query(default=24, ge=1, le=60),
    user: User | None = Depends(get_optional_user),
    db: Session = Depends(get_db),
):
    dna = discovery_service.dna_for_user(db, user.id) if user else None
    tag_list = [tag.strip() for tag in (tags or "").split(",") if tag.strip()]
    results = discovery_service.search_activities(
        db,
        q=q,
        destination_id=destination_id,
        tags=tag_list,
        max_budget=max_budget,
        max_duration=max_duration,
        indoor=indoor,
        accessible=accessible,
        lens=lens,
        dna=dna,
        limit=limit,
    )
    return {
        "lens": lens,
        "items": [
            {
                "activity": activity_out(item["activity"], item["place"], item["destination"]),
                "personal_fit": item["personal_fit"],
                "similar_to": item["similar_to"],
                "similarity": item["similarity"],
                "respect_note": item["respect_note"],
                "provenance": (
                    "ESTIMATED"
                    if (item["activity"].source_type or "").startswith("seed")
                    else "REPORTED"
                ),
                "catalog_freshness": _catalog_freshness(item["activity"]),
            }
            for item in results
        ],
        "personalised": bool(dna),
        "disclosure": (
            "Catalog attributes are curated data. Personal fit is an estimate from your Journey DNA, "
            "not a live provider score."
        ),
    }


@router.get("/trips/{trip_id}/nearby")
def nearby(
    trip_id: str,
    lat: float | None = Query(default=None, ge=-90, le=90),
    lon: float | None = Query(default=None, ge=-180, le=180),
    radius_km: float = Query(default=5, gt=0, le=50),
    category: str | None = Query(default=None, max_length=60),
    limit: int = Query(default=20, ge=1, le=60),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    if lat is not None or lon is not None:
        profile = db.query(Profile).filter(Profile.user_id == user.id).first()
        if not profile or not profile.location_sharing:
            raise HTTPException(
                status_code=403,
                detail=(
                    "Enable precise location in your privacy settings to use "
                    "your current position for nearby suggestions."
                ),
            )
        if lat is None or lon is None:
            raise HTTPException(
                status_code=422, detail="Provide both lat and lon, or neither"
            )
    base_lat = lat if lat is not None else trip.base_lat
    base_lon = lon if lon is not None else trip.base_lon
    activities = (
        db.query(Activity).filter(Activity.destination_id == trip.destination_id).all()
        if trip.destination_id
        else []
    )
    place_map, destination_map = _activity_place_maps(db, activities)
    items = []
    for activity in activities:
        place = place_map.get(activity.place_id)
        if not place:
            continue
        if category and place.category.lower() != category.lower():
            continue
        distance = haversine_km(base_lat, base_lon, place.lat, place.lon)
        if distance > radius_km:
            continue
        items.append(
            {
                "activity": activity_out(
                    activity, place, destination_map.get(activity.destination_id)
                ),
                "distance_km": round(distance, 2),
                "travel_minutes": travel_minutes(distance),
                "provenance": "ESTIMATED",
            }
        )
    items.sort(key=lambda item: item["distance_km"])
    return {
        "base": {"lat": base_lat, "lon": base_lon, "source": "shared trip base" if lat is None else "requested point"},
        "radius_km": radius_km,
        "items": items[:limit],
        "disclosure": (
            "Distances are straight-line estimates and travel time is not a live routed ETA. "
            "No live member location is exposed."
        ),
    }


def _activity_for_trip(db: Session, trip: Trip, activity_id: str) -> Activity:
    activity = db.get(Activity, activity_id)
    if not activity:
        raise HTTPException(status_code=404, detail="Activity not found")
    if activity.destination_id != trip.destination_id:
        raise HTTPException(status_code=404, detail="Activity not found for this trip")
    return activity


@router.get("/trips/{trip_id}/places/{activity_id}")
def place_detail(
    trip_id: str,
    activity_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    activity = _activity_for_trip(db, trip, activity_id)
    place = db.get(Place, activity.place_id) if activity.place_id else None
    return {
        "activity": activity_out(
            activity, place, db.get(Destination, activity.destination_id)
        ),
        "catalog_freshness": _catalog_freshness(activity),
        "reports": place_service.aggregate_reports(db, activity.id),
        "evidence": place_service.evidence_passport(db, activity),
        "access_chain": place_service.access_chain(activity),
        "crowd_forecast": place_service.crowd_forecast(db, activity.id),
    }


@router.post("/trips/{trip_id}/place-reports", status_code=201)
def create_place_report(
    trip_id: str,
    payload: PlaceReportIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, member = _trip(db, trip_id, user)
    if not payload.activity_id and not payload.place_id:
        raise HTTPException(status_code=422, detail="Provide an activity or place for this report")
    activity = None
    place = None
    if payload.activity_id:
        activity = _activity_for_trip(db, trip, payload.activity_id)
        place = db.get(Place, activity.place_id) if activity.place_id else None
    if payload.place_id:
        if place and payload.place_id != place.id:
            raise HTTPException(status_code=422, detail="Activity and place do not match")
        place = db.get(Place, payload.place_id)
        if not place or place.destination_id != trip.destination_id:
            raise HTTPException(status_code=404, detail="Place not found for this trip")
        if not activity:
            activity = (
                db.query(Activity)
                .filter(Activity.place_id == place.id)
                .first()
            )
    if payload.source_type == "official" and not user.is_admin:
        raise HTTPException(
            status_code=403,
            detail="Only platform moderators can mark a report as officially sourced",
        )
    if len(json.dumps(payload.value)) > 2000:
        raise HTTPException(status_code=422, detail="Report value is too large")
    observed_at = _naive_utc(payload.observed_at)
    if observed_at > utcnow() + timedelta(minutes=5):
        raise HTTPException(status_code=422, detail="Observation time cannot be in the future")
    confidence = payload.confidence
    if confidence is None:
        confidence = {"official": 0.8, "community": 0.6, "estimated": 0.4, "unknown": 0.2}[
            payload.source_type
        ]
    report = PlaceReport(
        activity_id=activity.id if activity else None,
        place_id=place.id if place else None,
        trip_id=trip.id,
        reporter_id=user.id,
        category=payload.category,
        value=payload.value,
        note=payload.note,
        observed_at=observed_at,
        source_type=payload.source_type,
        confidence=confidence,
        verified=False,
    )
    db.add(report)
    audit(
        db,
        action="place_report.create",
        entity_type="place_report",
        entity_id=report.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"category": payload.category, "source_type": payload.source_type},
    )
    if member.role in {"owner", "admin"}:
        notify_trip_members(
            db,
            trip,
            kind="place_report",
            title=f"New {payload.category} report",
            body=f"{user.display_name} shared what they observed.",
            link=f"/trips/{trip.id}/places",
            exclude_user_id=user.id,
        )
    db.commit()
    result = report_out(
        db, report, place_service.freshness(report.observed_at, report.source_type)
    )
    result["provenance"] = place_service.provenance(report.source_type, report.verified)
    result["disclosure"] = "Community reports are unverified observations, not official facts."
    return result


@router.get("/trips/{trip_id}/place-reports")
def list_place_reports(
    trip_id: str,
    activity_id: str = Query(...),
    days: int = Query(default=90, ge=1, le=365),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    activity = _activity_for_trip(db, trip, activity_id)
    rows = place_service.relevant_reports(db, activity.id, days=days)
    items = []
    for report in rows:
        score = place_service.freshness(report.observed_at, report.source_type, report.verified)
        payload = report_out(db, report, score)
        payload["provenance"] = place_service.provenance(report.source_type, report.verified)
        payload["freshness_label"] = place_service.freshness_label(score)
        items.append(payload)
    return {
        "items": items,
        "window_days": days,
        "disclosure": "Older reports lose weight. Provenance is shown per report.",
    }


@router.patch("/trips/{trip_id}/place-reports/{report_id}")
def correct_place_report(
    trip_id: str,
    report_id: str,
    payload: PlaceReportUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    report = db.get(PlaceReport, report_id)
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")
    activity = db.get(Activity, report.activity_id) if report.activity_id else None
    place = db.get(Place, report.place_id) if report.place_id else None
    destination_id = (
        activity.destination_id if activity else place.destination_id if place else None
    )
    if destination_id != trip.destination_id:
        raise HTTPException(status_code=404, detail="Report not found")
    if report.reporter_id != user.id and not user.is_admin:
        raise HTTPException(status_code=403, detail="Only the reporter can correct this observation")
    data = payload.model_dump(exclude_unset=True)
    if "value" in data and data["value"] is not None:
        if len(json.dumps(data["value"])) > 2000:
            raise HTTPException(status_code=422, detail="Report value is too large")
        report.value = data["value"]
    if "note" in data:
        report.note = data["note"]
    report.observed_at = utcnow()
    report.verified = False
    audit(
        db,
        action="place_report.correct",
        entity_type="place_report",
        entity_id=report.id,
        user_id=user.id,
        trip_id=trip.id,
    )
    db.commit()
    score = place_service.freshness(report.observed_at, report.source_type, report.verified)
    result = report_out(db, report, score)
    result["provenance"] = place_service.provenance(report.source_type, report.verified)
    result["disclosure"] = "Corrections reset verification and refresh the observation time."
    return result


@router.post("/trips/{trip_id}/place-reports/{report_id}/helpful")
def mark_helpful(
    trip_id: str,
    report_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    report = db.get(PlaceReport, report_id)
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")
    if report.activity_id:
        _activity_for_trip(db, trip, report.activity_id)
    elif report.place_id:
        place = db.get(Place, report.place_id)
        if not place or place.destination_id != trip.destination_id:
            raise HTTPException(status_code=404, detail="Report not found")
    already = (
        db.query(AuditLog)
        .filter(
            AuditLog.action == "place_report.helpful",
            AuditLog.entity_id == report.id,
            AuditLog.user_id == user.id,
        )
        .first()
    )
    if already:
        raise HTTPException(status_code=409, detail="You already marked this report helpful")
    report.helpful_count = (report.helpful_count or 0) + 1
    audit(
        db,
        action="place_report.helpful",
        entity_type="place_report",
        entity_id=report.id,
        user_id=user.id,
        trip_id=trip.id,
    )
    db.commit()
    return {
        "ok": True,
        "helpful_count": report.helpful_count,
        "note": "Helpful marks do not verify a report; moderation does.",
    }


@router.post("/trips/{trip_id}/places/{activity_id}/expectation")
def expectation_check(
    trip_id: str,
    activity_id: str,
    payload: ExpectationIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    activity = _activity_for_trip(db, trip, activity_id)
    return place_service.expectation_check(db, activity, payload.claim)


@router.get("/trips/{trip_id}/inspirations")
def list_inspirations(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    rows = (
        db.query(SavedInspiration)
        .filter(
            SavedInspiration.trip_id == trip.id,
            SavedInspiration.user_id == user.id,
        )
        .order_by(SavedInspiration.created_at.desc())
        .all()
    )
    return {
        "items": [
            {
                "id": row.id,
                "source_type": row.source_type,
                "content": row.content,
                "status": row.status,
                "extracted": row.extracted or {},
                "created_at": row.created_at,
            }
            for row in rows
        ]
    }


def _media_path_for_trip(trip: Trip, media_url: str | None) -> Path | None:
    """Resolve a signed local media URL to a file inside this trip's folder."""
    if not media_url:
        return None
    parts = urlsplit(media_url)
    if parts.scheme or parts.netloc:
        raise HTTPException(status_code=422, detail="Media must be a local SAFAR upload")
    prefix = f"/media/{trip.id}/"
    if not parts.path.startswith(prefix):
        raise HTTPException(status_code=422, detail="Media does not belong to this trip")
    filename = parts.path[len(prefix):]
    if not _MEDIA_NAME_PATTERN.match(filename):
        raise HTTPException(status_code=422, detail="Invalid media name")
    query = {key: values[0] for key, values in parse_qs(parts.query).items()}
    if not verify_media_request(parts.path, query):
        raise HTTPException(status_code=403, detail="Media link is missing or expired")
    candidate = (MEDIA_ROOT / trip.id / filename).resolve()
    if MEDIA_ROOT.resolve() not in candidate.parents or not candidate.is_file():
        raise HTTPException(status_code=404, detail="Media not found")
    return candidate


@router.post("/trips/{trip_id}/inspirations", status_code=201)
def import_inspiration(
    trip_id: str,
    payload: InspirationIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    if payload.trip_id and payload.trip_id != trip.id:
        raise HTTPException(status_code=422, detail="Trip mismatch")
    content = (payload.content or "").strip()
    if payload.source_type == "image_url":
        if not content and not payload.media_url:
            raise HTTPException(
                status_code=422, detail="Attach an image or describe what it shows"
            )
    elif len(content) < 2:
        raise HTTPException(status_code=422, detail="Inspiration text is too short")
    media_path = _media_path_for_trip(trip, payload.media_url)
    stored_content = content or "Uploaded image"
    inspiration = SavedInspiration(
        user_id=user.id,
        trip_id=trip.id,
        source_type=payload.source_type,
        content=stored_content,
        status="pending",
    )
    db.add(inspiration)
    db.flush()
    extraction = discovery_service.dream_import(
        db, user.id, inspiration, media_path=media_path
    )
    inspiration.status = "extracted"
    audit(
        db,
        action="inspiration.import",
        entity_type="saved_inspiration",
        entity_id=inspiration.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={
            "source_type": payload.source_type,
            "media": bool(media_path),
            "candidates": len(extraction.get("matches", [])),
        },
    )
    db.commit()
    return {
        "id": inspiration.id,
        "source_type": inspiration.source_type,
        "status": inspiration.status,
        "extraction": extraction,
        "disclosure": (
            "Candidates are suggestions only. Confirm them before adding anything to the itinerary."
        ),
    }


@router.post("/trips/{trip_id}/inspirations/{inspiration_id}/review")
def review_inspiration(
    trip_id: str,
    inspiration_id: str,
    payload: InspirationReviewIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    row = (
        db.query(SavedInspiration)
        .filter(
            SavedInspiration.id == inspiration_id,
            SavedInspiration.trip_id == trip.id,
            SavedInspiration.user_id == user.id,
        )
        .first()
    )
    if not row:
        raise HTTPException(status_code=404, detail="Inspiration not found")
    extraction = json.loads(json.dumps(row.extracted or {}))
    matches = extraction.get("matches", [])
    target = next(
        (
            match
            for match in matches
            if match.get("candidate_id") == payload.candidate_id
        ),
        None,
    )
    if not target:
        raise HTTPException(status_code=404, detail="Candidate not found")
    target["decision"] = payload.decision
    decisions = extraction.setdefault("decisions", {})
    decisions[payload.candidate_id] = {
        "decision": payload.decision,
        "decided_at": utcnow().isoformat(),
    }
    accepted = sum(1 for match in matches if match.get("decision") == "accept")
    rejected = sum(1 for match in matches if match.get("decision") == "reject")
    pending = len(matches) - accepted - rejected
    extraction["review"] = {
        "pending": pending,
        "accepted": accepted,
        "rejected": rejected,
    }
    if pending == 0:
        row.status = "reviewed" if accepted else "rejected"
    else:
        row.status = "extracted"
    row.extracted = extraction
    audit(
        db,
        action="inspiration.review",
        entity_type="saved_inspiration",
        entity_id=row.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"candidate_id": payload.candidate_id, "decision": payload.decision},
    )
    db.commit()
    return {
        "id": row.id,
        "status": row.status,
        "extraction": extraction,
        "disclosure": (
            "Accepted candidates are still suggestions. Turn an activity into a "
            "proposal so the group can vote before the plan changes."
        ),
    }


def _blocked_ids(db: Session, user_id: str) -> set[str]:
    rows = (
        db.query(UserBlock)
        .filter((UserBlock.blocker_id == user_id) | (UserBlock.blocked_id == user_id))
        .all()
    )
    blocked: set[str] = set()
    for row in rows:
        blocked.add(row.blocker_id)
        blocked.add(row.blocked_id)
    blocked.discard(user_id)
    return blocked


@router.get("/serendipity/matches")
def serendipity_matches(
    user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    result = discovery_service.serendipity_suggestions(db, user)
    blocked = _blocked_ids(db, user.id)
    result["matches"] = [
        match for match in result.get("matches", []) if match["user"]["id"] not in blocked
    ]
    db.commit()
    return result


@router.get("/serendipity/requests")
def list_connection_requests(
    user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    rows = (
        db.query(ConnectionRequest)
        .filter(
            (ConnectionRequest.from_user_id == user.id)
            | (ConnectionRequest.to_user_id == user.id)
        )
        .order_by(ConnectionRequest.created_at.desc())
        .all()
    )
    users = {
        person.id: person
        for person in db.query(User)
        .filter(User.id.in_({row.from_user_id for row in rows} | {row.to_user_id for row in rows}))
        .all()
    }
    return {
        "items": [
            {
                "id": row.id,
                "direction": "outgoing" if row.from_user_id == user.id else "incoming",
                "from_user": user_public(users.get(row.from_user_id)),
                "to_user": user_public(users.get(row.to_user_id)),
                "message": row.message,
                "status": row.status,
                "created_at": row.created_at,
                "decided_at": row.decided_at,
            }
            for row in rows
        ],
        "disclosure": "Contact requires mutual acceptance. Exact locations are never shared.",
    }


@router.post("/serendipity/requests", status_code=201)
def create_connection_request(
    payload: ConnectionCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if payload.to_user_id == user.id:
        raise HTTPException(status_code=422, detail="You cannot connect with yourself")
    target = db.get(User, payload.to_user_id)
    if not target or target.deleted_at or not target.is_active:
        raise HTTPException(status_code=404, detail="Traveller not found")
    target_profile = db.query(Profile).filter(Profile.user_id == target.id).first()
    my_profile = db.query(Profile).filter(Profile.user_id == user.id).first()
    if not my_profile or not my_profile.allow_discovery:
        raise HTTPException(
            status_code=403,
            detail="Enable traveller discovery in your privacy settings first",
        )
    if not target_profile or not target_profile.allow_discovery or not target_profile.public_profile:
        raise HTTPException(status_code=403, detail="This traveller is not open to contact")
    if target.id in _blocked_ids(db, user.id):
        raise HTTPException(status_code=403, detail="This traveller is not open to contact")
    existing = (
        db.query(ConnectionRequest)
        .filter(
            ConnectionRequest.status.in_(["pending", "accepted"]),
            (
                ((ConnectionRequest.from_user_id == user.id) & (ConnectionRequest.to_user_id == target.id))
                | ((ConnectionRequest.from_user_id == target.id) & (ConnectionRequest.to_user_id == user.id))
            ),
        )
        .first()
    )
    if existing:
        raise HTTPException(
            status_code=409,
            detail="A request already exists between you two",
        )
    if payload.trip_id:
        _trip(db, payload.trip_id, user)
    request = ConnectionRequest(
        from_user_id=user.id,
        to_user_id=target.id,
        trip_id=payload.trip_id,
        message=payload.message,
    )
    db.add(request)
    db.add(
        Notification(
            user_id=target.id,
            kind="connection_request",
            title=f"{user.display_name} would like to connect",
            body="Accept only if you are comfortable. Exact locations are never shared.",
            link="/connections",
        )
    )
    audit(
        db,
        action="connection.request",
        entity_type="connection_request",
        entity_id=request.id,
        user_id=user.id,
        trip_id=payload.trip_id,
    )
    db.commit()
    return {
        "id": request.id,
        "status": request.status,
        "note": "The other traveller must accept before contact details are exchanged.",
    }


@router.post("/serendipity/requests/{request_id}/decide")
def decide_connection_request(
    request_id: str,
    payload: ConnectionDecision,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    request = db.get(ConnectionRequest, request_id)
    if not request or request.to_user_id != user.id:
        raise HTTPException(status_code=404, detail="Request not found")
    if request.status != "pending":
        raise HTTPException(status_code=409, detail="This request was already decided")
    request.status = "accepted" if payload.accept else "declined"
    request.decided_at = utcnow()
    match = (
        db.query(TravellerMatch)
        .filter(
            TravellerMatch.user_a_id == request.from_user_id,
            TravellerMatch.user_b_id == user.id,
        )
        .first()
    )
    if match:
        match.status = "connected" if payload.accept else "declined"
    db.add(
        Notification(
            user_id=request.from_user_id,
            kind="connection_decision",
            title=(
                f"{user.display_name} accepted your connection"
                if payload.accept
                else f"{user.display_name} declined your connection"
            ),
            body="Meet only in public places and share only what you choose." if payload.accept else None,
            link="/connections",
        )
    )
    audit(
        db,
        action="connection.decide",
        entity_type="connection_request",
        entity_id=request.id,
        user_id=user.id,
        detail={"accept": payload.accept},
    )
    db.commit()
    return {
        "ok": True,
        "status": request.status,
        "disclosure": "Both travellers have now agreed. Keep meetups in public places.",
    }


def _circle_out(db: Session, circle: TravelCircle, viewer_id: str | None) -> dict:
    member_count = db.query(CircleMember).filter(CircleMember.circle_id == circle.id).count()
    joined = (
        db.query(CircleMember)
        .filter(CircleMember.circle_id == circle.id, CircleMember.user_id == viewer_id)
        .first()
        if viewer_id
        else None
    )
    return {
        "id": circle.id,
        "slug": circle.slug,
        "name": circle.name,
        "description": circle.description,
        "interests": circle.interests or [],
        "cover_image": circle.cover_image,
        "member_count": member_count,
        "joined": bool(joined),
        "created_at": circle.created_at,
    }


@router.get("/circles")
def list_circles(
    user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    circles = discovery_service.ensure_seed_circles(db, user.id)
    db.commit()
    return {
        "items": [_circle_out(db, circle, user.id) for circle in circles],
        "disclosure": "Circles are optional communities. Report any harmful content to moderators.",
    }


@router.get("/circles/{circle_id}")
def get_circle(
    circle_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    circle = db.get(TravelCircle, circle_id)
    if not circle:
        raise HTTPException(status_code=404, detail="Circle not found")
    posts = (
        db.query(CirclePost)
        .filter(CirclePost.circle_id == circle.id, CirclePost.status == "published")
        .order_by(CirclePost.created_at.desc())
        .limit(50)
        .all()
    )
    authors = {
        person.id: person
        for person in db.query(User)
        .filter(User.id.in_({post.user_id for post in posts}))
        .all()
    } if posts else {}
    # Display names and roles are public inside a circle; no contact details
    # or personal preferences are ever included.
    members = (
        db.query(CircleMember, User)
        .join(User, User.id == CircleMember.user_id)
        .filter(CircleMember.circle_id == circle.id)
        .order_by(CircleMember.joined_at.asc())
        .all()
    )
    return {
        **_circle_out(db, circle, user.id),
        "members": [
            {
                "user_id": member.user_id,
                "display_name": person.display_name,
                "role": member.role,
            }
            for member, person in members
        ],
        "posts": [
            {
                "id": post.id,
                "title": post.title,
                "body": post.body,
                "activity_id": post.activity_id,
                "status": post.status,
                "author": user_public(authors.get(post.user_id)),
                "created_at": post.created_at,
            }
            for post in posts
        ],
    }


@router.post("/circles/{circle_id}/join")
def join_circle(
    circle_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    circle = db.get(TravelCircle, circle_id)
    if not circle:
        raise HTTPException(status_code=404, detail="Circle not found")
    existing = (
        db.query(CircleMember)
        .filter(CircleMember.circle_id == circle.id, CircleMember.user_id == user.id)
        .first()
    )
    if not existing:
        db.add(CircleMember(circle_id=circle.id, user_id=user.id))
        audit(
            db,
            action="circle.join",
            entity_type="travel_circle",
            entity_id=circle.id,
            user_id=user.id,
        )
        db.commit()
    return {"ok": True, "joined": True, "member_count": _circle_out(db, circle, user.id)["member_count"]}


@router.delete("/circles/{circle_id}/join")
def leave_circle(
    circle_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    circle = db.get(TravelCircle, circle_id)
    if not circle:
        raise HTTPException(status_code=404, detail="Circle not found")
    db.query(CircleMember).filter(
        CircleMember.circle_id == circle.id, CircleMember.user_id == user.id
    ).delete()
    db.commit()
    return {"ok": True, "joined": False}


@router.post("/circles/{circle_id}/posts", status_code=201)
def create_circle_post(
    circle_id: str,
    payload: CirclePostCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    circle = db.get(TravelCircle, circle_id)
    if not circle:
        raise HTTPException(status_code=404, detail="Circle not found")
    membership = (
        db.query(CircleMember)
        .filter(CircleMember.circle_id == circle.id, CircleMember.user_id == user.id)
        .first()
    )
    if not membership:
        raise HTTPException(status_code=403, detail="Join the circle before posting")
    if payload.activity_id:
        activity = db.get(Activity, payload.activity_id)
        if not activity:
            raise HTTPException(status_code=404, detail="Activity not found")
    post = CirclePost(
        circle_id=circle.id,
        user_id=user.id,
        title=payload.title,
        body=payload.body,
        activity_id=payload.activity_id,
    )
    db.add(post)
    audit(
        db,
        action="circle.post",
        entity_type="circle_post",
        entity_id=post.id,
        user_id=user.id,
        detail={"circle_id": circle.id},
    )
    db.commit()
    return {
        "id": post.id,
        "title": post.title,
        "body": post.body,
        "status": post.status,
        "created_at": post.created_at,
        "moderation": "Posts are published immediately and can be reported for review.",
    }


@router.get("/contributors")
def list_contributors(
    destination_id: str | None = None,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    query = db.query(LocalContributor)
    if destination_id:
        query = query.filter(LocalContributor.destination_id == destination_id)
    rows = query.all()
    users = {
        person.id: person
        for person in db.query(User)
        .filter(User.id.in_({row.user_id for row in rows}))
        .all()
    } if rows else {}
    destinations = {
        destination.id: destination
        for destination in db.query(Destination)
        .filter(Destination.id.in_({row.destination_id for row in rows}))
        .all()
    } if rows else {}
    return {
        "items": [
            {
                "id": row.id,
                "user": user_public(users.get(row.user_id)),
                "destination": (
                    destination_out(destinations[row.destination_id])
                    if row.destination_id in destinations
                    else None
                ),
                "bio": row.bio,
                "expertise": row.expertise or [],
                "verified": row.verified,
                "accepts_requests": row.accepts_requests,
            }
            for row in rows
        ],
        "disclosure": "Contributors are opt-in travellers, not official tourism authorities.",
    }


@router.post("/contributors")
def upsert_contributor(
    payload: ContributorIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    destination = db.get(Destination, payload.destination_id)
    if not destination:
        raise HTTPException(status_code=404, detail="Destination not found")
    row = db.query(LocalContributor).filter(LocalContributor.user_id == user.id).first()
    if not row:
        row = LocalContributor(user_id=user.id, destination_id=destination.id)
        db.add(row)
    row.destination_id = destination.id
    row.bio = payload.bio
    row.expertise = payload.expertise
    row.accepts_requests = payload.accepts_requests
    audit(
        db,
        action="contributor.upsert",
        entity_type="local_contributor",
        entity_id=row.id,
        user_id=user.id,
    )
    db.commit()
    return {
        "id": row.id,
        "destination_id": row.destination_id,
        "accepts_requests": row.accepts_requests,
        "verified": row.verified,
        "note": "Verification is granted by moderators, never self-declared.",
    }


@router.post("/trips/{trip_id}/activities/{activity_id}/feedback")
def activity_feedback(
    trip_id: str,
    activity_id: str,
    payload: FeedbackIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    activity = _activity_for_trip(db, trip, activity_id)
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
        action="activity.feedback",
        entity_type="activity",
        entity_id=activity.id,
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
            "Private to you. Only consented outcomes shape future recommendations."
        ),
    }


@router.post("/abuse-reports", status_code=201)
def report_abuse(
    payload: AbuseReportIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if payload.target_user_id:
        target = db.get(User, payload.target_user_id)
        if not target or target.deleted_at:
            raise HTTPException(status_code=404, detail="Reported user not found")
    if payload.target_type == "post" and payload.target_id:
        if not db.get(CirclePost, payload.target_id):
            raise HTTPException(status_code=404, detail="Reported post not found")
    if payload.target_type == "memory" and payload.target_id:
        if not db.get(TripMemory, payload.target_id):
            raise HTTPException(status_code=404, detail="Reported memory not found")
    if payload.target_type == "report" and payload.target_id:
        if not db.get(PlaceReport, payload.target_id):
            raise HTTPException(status_code=404, detail="Reported report not found")
    existing = (
        db.query(AbuseReport)
        .filter(
            AbuseReport.reporter_id == user.id,
            AbuseReport.target_type == payload.target_type,
            AbuseReport.target_id == payload.target_id,
            AbuseReport.status == "open",
        )
        .first()
    )
    if existing:
        raise HTTPException(status_code=409, detail="You already reported this; moderators are reviewing it")
    report = AbuseReport(
        reporter_id=user.id,
        target_user_id=payload.target_user_id,
        target_type=payload.target_type,
        target_id=payload.target_id,
        reason=payload.reason,
    )
    db.add(report)
    audit(
        db,
        action="abuse.report",
        entity_type="abuse_report",
        entity_id=report.id,
        user_id=user.id,
        detail={"target_type": payload.target_type},
    )
    db.commit()
    return {
        "id": report.id,
        "status": report.status,
        "note": "Moderators review reports. Retaliation is not permitted.",
    }
