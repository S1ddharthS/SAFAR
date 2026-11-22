"""Memory timeline, Memory Studio suggestions and Journey Replay (F11, F12, F18)."""

from datetime import date, datetime, timedelta

from sqlalchemy.orm import Session

from app.models import (
    Activity,
    ItineraryItem,
    MemoryEvent,
    MemoryPermission,
    Place,
    Trip,
    TripMemory,
    User,
)
from app.services.geo import haversine_km
from app.services.serializers import memory_out


def can_view_memory(db: Session, memory: TripMemory, viewer_id: str) -> bool:
    if memory.user_id == viewer_id:
        return True
    if memory.visibility == "private":
        permission = (
            db.query(MemoryPermission)
            .filter(
                MemoryPermission.memory_id == memory.id,
                MemoryPermission.user_id == viewer_id,
                MemoryPermission.can_view.is_(True),
            )
            .first()
        )
        return permission is not None
    return True


def visible_memories(db: Session, trip_id: str, viewer_id: str) -> list[TripMemory]:
    memories = (
        db.query(TripMemory)
        .filter(TripMemory.trip_id == trip_id, TripMemory.deleted_at.is_(None))
        .order_by(TripMemory.captured_at)
        .all()
    )
    return [memory for memory in memories if can_view_memory(db, memory, viewer_id)]


def visible_events(
    db: Session,
    trip_id: str,
    viewer_id: str,
    statuses: set[str] | None = None,
) -> list[MemoryEvent]:
    """Events are only visible when every memory they reference is visible.

    Otherwise an approved event would leak the title, timing and memory ids of
    a private memory to other trip members.
    """
    visible_ids = {memory.id for memory in visible_memories(db, trip_id, viewer_id)}
    query = db.query(MemoryEvent).filter(MemoryEvent.trip_id == trip_id)
    if statuses:
        query = query.filter(MemoryEvent.status.in_(statuses))
    events = query.order_by(MemoryEvent.start_at).all()
    return [
        event
        for event in events
        if all(memory_id in visible_ids for memory_id in (event.memory_ids or []))
    ]


def timeline(db: Session, trip_id: str, viewer_id: str) -> dict:
    memories = visible_memories(db, trip_id, viewer_id)
    authors = {user.id: user for user in db.query(User).all()}
    days: dict[str, list[dict]] = {}
    for memory in memories:
        payload = memory_out(memory, authors.get(memory.user_id))
        days.setdefault(memory.captured_at.date().isoformat(), []).append(payload)
    return {
        "days": [
            {"date": day, "memories": entries}
            for day, entries in sorted(days.items(), reverse=True)
        ],
        "total": len(memories),
        "permissions": "Private memories are only visible to their owner and explicitly permitted members.",
    }


def _nearby_item(
    db: Session, trip_id: str, captured_at: datetime, lat: float | None, lon: float | None
) -> ItineraryItem | None:
    items = (
        db.query(ItineraryItem)
        .filter(
            ItineraryItem.trip_id == trip_id,
            ItineraryItem.day == captured_at.date(),
            ItineraryItem.status == "confirmed",
        )
        .all()
    )
    if not items:
        return None
    if lat is not None and lon is not None:
        best = None
        best_distance = 1.0
        for item in items:
            if not item.activity_id:
                continue
            activity = db.get(Activity, item.activity_id)
            place = db.get(Place, activity.place_id) if activity and activity.place_id else None
            if not place:
                continue
            distance = haversine_km(lat, lon, place.lat, place.lon)
            if distance < best_distance:
                best_distance = distance
                best = item
        if best:
            return best
    target_minutes = captured_at.hour * 60 + captured_at.minute
    for item in items:
        try:
            hours, minutes = item.start_time.split(":")
            start = int(hours) * 60 + int(minutes)
        except ValueError:
            continue
        if abs(start - target_minutes) <= 90:
            return item
    return None


def suggest_events(db: Session, trip: Trip, user_id: str) -> list[MemoryEvent]:
    memories = visible_memories(db, trip.id, user_id)
    sessions: list[list[TripMemory]] = []
    for memory in memories:
        if sessions and (memory.captured_at - sessions[-1][-1].captured_at) <= timedelta(hours=3):
            sessions[-1].append(memory)
        else:
            sessions.append([memory])

    existing = db.query(MemoryEvent).filter(MemoryEvent.trip_id == trip.id).all()
    existing_sets = {frozenset(event.memory_ids or []) for event in existing}
    created = []
    for session in sessions:
        memory_ids = [memory.id for memory in session]
        if frozenset(memory_ids) in existing_sets:
            continue
        first = session[0]
        nearby = _nearby_item(db, trip.id, first.captured_at, first.lat, first.lon)
        title = (
            f"Moments around {nearby.title}"
            if nearby
            else f"Moments on {first.captured_at.strftime('%b %d')}"
        )
        contributors = {memory.user_id for memory in session}
        summary = (
            f"{len(session)} memories from {first.captured_at.strftime('%H:%M')} "
            f"to {session[-1].captured_at.strftime('%H:%M')} contributed by "
            f"{len(contributors)} member(s)."
        )
        event = MemoryEvent(
            trip_id=trip.id,
            title=title,
            summary=summary,
            start_at=first.captured_at,
            end_at=session[-1].captured_at,
            member_ids=sorted(contributors),
            memory_ids=memory_ids,
            status="suggested",
            created_by=user_id,
        )
        db.add(event)
        created.append(event)
    return created


def caption_suggestion(db: Session, trip: Trip, memory: TripMemory) -> dict:
    nearby = _nearby_item(db, trip.id, memory.captured_at, memory.lat, memory.lon)
    parts = []
    if memory.text_content:
        parts.append(memory.text_content.strip()[:180])
    if nearby:
        parts.append(f"Captured during {nearby.title}.")
    else:
        parts.append(
            f"Captured on {memory.captured_at.strftime('%B %d at %H:%M')}."
        )
    if memory.kind in {"photo", "video"}:
        parts.append(f"Shared by the traveller who uploaded this {memory.kind}.")
    suggestion = " ".join(parts)
    return {
        "memory_id": memory.id,
        "suggestion": suggestion,
        "ai_generated": False,
        "generator": "template",
        "approved": False,
        "grounding": "Template built from the upload time, optional location and the confirmed itinerary. No people, feelings or places are invented.",
        "disclosure": "A plain template, not AI-generated text. Review before publishing; nothing is approved until you accept it.",
    }


def replay(db: Session, trip: Trip, viewer_id: str) -> dict:
    items = (
        db.query(ItineraryItem)
        .filter(ItineraryItem.trip_id == trip.id, ItineraryItem.status == "confirmed")
        .order_by(ItineraryItem.day, ItineraryItem.start_time)
        .all()
    )
    memories = visible_memories(db, trip.id, viewer_id)
    approved_events = visible_events(db, trip.id, viewer_id, statuses={"approved"})
    authors = {user.id: user for user in db.query(User).all()}
    by_day: dict[str, dict] = {}
    for item in items:
        day = item.day.isoformat()
        by_day.setdefault(
            day,
            {"date": day, "items": [], "memories": [], "events": [], "captions": []},
        )["items"].append(
            {"id": item.id, "title": item.title, "start_time": item.start_time, "protected": item.is_protected}
        )
    for memory in memories:
        day = memory.captured_at.date().isoformat()
        by_day.setdefault(
            day,
            {"date": day, "items": [], "memories": [], "events": [], "captions": []},
        )["memories"].append(memory_out(memory, authors.get(memory.user_id)))
        if memory.caption and memory.approved:
            by_day[day]["captions"].append(
                {"memory_id": memory.id, "caption": memory.caption, "author": memory.user_id}
            )
    for event in approved_events:
        day = event.start_at.date().isoformat()
        if day in by_day:
            by_day[day]["events"].append(
                {
                    "id": event.id,
                    "title": event.title,
                    "summary": event.summary,
                    "memory_ids": event.memory_ids,
                }
            )
    days = sorted(by_day.values(), key=lambda entry: entry["date"])
    total_media = sum(
        1 for memory in memories if memory.kind in {"photo", "video", "voice"}
    )
    return {
        "trip": {
            "id": trip.id,
            "name": trip.name,
            "destination": trip.destination_name,
            "start_date": trip.start_date,
            "end_date": trip.end_date,
        },
        "days": days,
        "stats": {
            "days_recorded": len(days),
            "memories": len(memories),
            "media": total_media,
            "approved_events": len(approved_events),
            "contributors": len({memory.user_id for memory in memories}),
        },
        "permissions": "Only permitted media is included. Unapproved AI captions are excluded.",
        "format_note": "A print-ready travel book can be generated from this replay; export is available as printable HTML.",
    }
