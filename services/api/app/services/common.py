from datetime import date, datetime

from sqlalchemy.orm import Session

from app.models import (
    Activity,
    AuditLog,
    Itinerary,
    ItineraryItem,
    ItineraryVersion,
    Notification,
    Trip,
    TripMember,
    User,
)
from app.models.models import utcnow

DNA_DIMENSIONS = [
    "culture",
    "adventure",
    "food",
    "nature",
    "photography",
    "shopping",
    "history",
    "relaxation",
    "luxury",
    "budget",
    "outdoor",
    "local",
]

TAG_ALIASES = {
    "art": "culture",
    "museum": "culture",
    "architecture": "culture",
    "music": "culture",
    "nightlife": "culture",
    "hiking": "adventure",
    "trek": "adventure",
    "sports": "adventure",
    "diving": "adventure",
    "culinary": "food",
    "market": "food",
    "cafe": "food",
    "beach": "nature",
    "park": "nature",
    "wildlife": "nature",
    "viewpoint": "nature",
    "landscape": "nature",
    "photo": "photography",
    "souvenir": "shopping",
    "heritage": "history",
    "temple": "history",
    "monument": "history",
    "wellness": "relaxation",
    "spa": "relaxation",
    "luxury": "luxury",
    "budget_travel": "budget",
    "backpacking": "budget",
    "outdoors": "outdoor",
    "local_experience": "local",
    "community": "local",
}


def normalize_tag(tag: str) -> str:
    key = (tag or "").strip().lower().replace(" ", "_").replace("-", "_")
    return TAG_ALIASES.get(key, key)


def default_dna() -> dict[str, int]:
    return {dimension: 5 for dimension in DNA_DIMENSIONS}


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def audit(
    db: Session,
    *,
    action: str,
    entity_type: str,
    entity_id: str | None = None,
    user_id: str | None = None,
    trip_id: str | None = None,
    detail: dict | None = None,
) -> None:
    db.add(
        AuditLog(
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            user_id=user_id,
            trip_id=trip_id,
            detail=detail or {},
        )
    )


def notify_trip_members(
    db: Session,
    trip: Trip,
    *,
    kind: str,
    title: str,
    body: str | None = None,
    link: str | None = None,
    exclude_user_id: str | None = None,
    urgent: bool = False,
) -> list[str]:
    """Create in-app notifications for active members.

    Quiet mode (F49) suppresses non-urgent notifications. Every feature remains
    reachable in-app; quiet mode only removes the interruption.
    """
    members = (
        db.query(TripMember)
        .filter(TripMember.trip_id == trip.id, TripMember.status == "active")
        .all()
    )
    notified: list[str] = []
    for member in members:
        if not member.user_id or member.user_id == exclude_user_id:
            continue
        user = db.get(User, member.user_id)
        if not user:
            continue
        if user.quiet_mode and not urgent:
            continue
        db.add(
            Notification(
                user_id=user.id,
                trip_id=trip.id,
                kind=kind,
                title=title,
                body=body,
                link=link,
            )
        )
        notified.append(user.id)
    return notified


def snapshot_items(items: list[ItineraryItem]) -> list[dict]:
    return [
        {
            "id": item.id,
            "day": item.day.isoformat(),
            "start_time": item.start_time,
            "end_time": item.end_time,
            "title": item.title,
            "activity_id": item.activity_id,
            "place_id": item.place_id,
            "notes": item.notes,
            "cost_estimate": item.cost_estimate,
            "is_protected": item.is_protected,
            "sort_order": item.sort_order,
        }
        for item in items
    ]


def record_itinerary_version(
    db: Session,
    itinerary: Itinerary,
    *,
    user_id: str,
    note: str,
) -> ItineraryVersion:
    itinerary.confirmed_version += 1
    items = (
        db.query(ItineraryItem)
        .filter(
            ItineraryItem.itinerary_id == itinerary.id,
            ItineraryItem.status == "confirmed",
        )
        .order_by(ItineraryItem.day, ItineraryItem.sort_order)
        .all()
    )
    version = ItineraryVersion(
        itinerary_id=itinerary.id,
        trip_id=itinerary.trip_id,
        version=itinerary.confirmed_version,
        snapshot=snapshot_items(items),
        note=note,
        created_by=user_id,
    )
    db.add(version)
    return version


def get_activity_or_404(db: Session, activity_id: str) -> Activity:
    from fastapi import HTTPException

    activity = db.get(Activity, activity_id)
    if not activity:
        raise HTTPException(status_code=404, detail="Activity not found")
    return activity


def parse_date(value: date | str | None, fallback: date | None = None) -> date:
    if value is None:
        return fallback or date.today()
    if isinstance(value, date):
        return value
    return date.fromisoformat(value)


def now_iso() -> str:
    return utcnow().isoformat() + "Z"


def event_payload(event: str, **data) -> dict:
    return {"event": event, "at": now_iso(), **data}
