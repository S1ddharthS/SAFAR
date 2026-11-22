"""Shared memories, AI Memory Studio, Journey Replay and offline capture.

F11, F12, F18, F20 and F34. Media permissions are enforced on every read.
AI captions and event groupings are suggestions until a contributor approves
them; nothing is invented beyond recorded metadata and the confirmed plan.
"""

import logging
import uuid
from datetime import datetime, timedelta, timezone
from html import escape
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import HTMLResponse
from pydantic import ValidationError
from sqlalchemy.orm import Session

from app.core.alerting import AlertCategory, AlertSeverity, alert_manager
from app.core.config import settings
from app.core.metrics import metrics

media_logger = logging.getLogger("safar.media")
sync_logger = logging.getLogger("safar.sync")

from app.core.deps import (
    get_current_user,
    get_db,
    get_trip_and_member,
    trip_scope_guard,
)
from app.models import (
    Itinerary,
    JourneyPact,
    MemoryEvent,
    MemoryPermission,
    OfflineSyncQueue,
    Trip,
    TripMember,
    TripMemory,
    User,
)
from app.models.models import utcnow
from app.schemas.schemas import (
    MemoryCreate,
    MemoryEventCreate,
    MemoryPermissionIn,
    MemoryUpdate,
    OfflineSyncItem,
)
from app.services import memory as memory_service
from app.services.common import audit, notify_trip_members
from app.services.media import canonical_media_url, media_matches_type, sign_media_url
from app.services.serializers import memory_out

router = APIRouter(
    prefix="/api/trips",
    tags=["memories"],
    dependencies=[Depends(trip_scope_guard)],
)

ADMIN_ROLES = {"owner", "admin"}
MEDIA_ROOT = settings.storage_dir
MAX_UPLOAD_BYTES = 25 * 1024 * 1024
ALLOWED_MEDIA = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "video/mp4": ".mp4",
    "audio/webm": ".webm",
    "audio/mpeg": ".mp3",
    "audio/ogg": ".ogg",
    "audio/wav": ".wav",
}


def _trip(db, trip_id, user, roles=None):
    return get_trip_and_member(trip_id, db, user, roles)


def _naive_utc(value: datetime | None) -> datetime:
    if value is None:
        return utcnow()
    if value.tzinfo is None:
        return value
    return value.astimezone(timezone.utc).replace(tzinfo=None)


def _validate_memory_content(
    kind: str, text: str | None, media_url: str | None, trip_id: str
) -> None:
    if not text and not media_url:
        raise HTTPException(
            status_code=422,
            detail="A memory needs text or a media upload.",
        )
    if kind in {"photo", "video", "voice"} and not media_url:
        raise HTTPException(
            status_code=422,
            detail=f"A {kind} memory needs an uploaded media file.",
        )
    if media_url and media_url.startswith("/media/"):
        if not media_url.startswith(f"/media/{trip_id}/"):
            raise HTTPException(
                status_code=422,
                detail="Media must belong to this trip.",
            )
    elif media_url and not media_url.startswith("https://"):
        raise HTTPException(
            status_code=422,
            detail="Media must be an uploaded SAFAR file or an HTTPS URL.",
        )


def _memory_for_trip(db: Session, trip: Trip, memory_id: str, viewer_id: str) -> TripMemory:
    memory = db.get(TripMemory, memory_id)
    if not memory or memory.trip_id != trip.id or memory.deleted_at is not None:
        raise HTTPException(status_code=404, detail="Memory not found")
    if not memory_service.can_view_memory(db, memory, viewer_id):
        raise HTTPException(status_code=404, detail="Memory not found")
    return memory


@router.get("/{trip_id}/memories")
def get_timeline(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    return memory_service.timeline(db, trip.id, user.id)


@router.post("/{trip_id}/memories", status_code=201)
def create_memory(
    trip_id: str,
    payload: MemoryCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    _validate_memory_content(
        payload.kind, payload.text_content, payload.media_url, trip.id
    )
    captured_at = _naive_utc(payload.captured_at)
    if captured_at > utcnow() + timedelta(minutes=5):
        raise HTTPException(status_code=422, detail="Capture time cannot be in the future")
    memory = TripMemory(
        trip_id=trip.id,
        user_id=user.id,
        kind=payload.kind,
        text_content=payload.text_content,
        media_url=canonical_media_url(payload.media_url),
        media_type=payload.media_type,
        caption=payload.caption,
        captured_at=captured_at,
        lat=payload.lat,
        lon=payload.lon,
        visibility=payload.visibility,
        ai_generated=False,
        approved=True,
    )
    db.add(memory)
    db.flush()
    audit(
        db,
        action="memory.create",
        entity_type="trip_memory",
        entity_id=memory.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"kind": memory.kind, "visibility": memory.visibility},
    )
    notify_trip_members(
        db,
        trip,
        kind="memory_added",
        title=f"{user.display_name} added a memory",
        body="Photos, notes and voice memories stay visible only as each contributor allows."
        if payload.visibility == "trip"
        else None,
        link=f"/trips/{trip.id}/memories",
        exclude_user_id=user.id,
    )
    db.commit()
    return memory_out(memory, user)


@router.patch("/{trip_id}/memories/{memory_id}")
def update_memory(
    trip_id: str,
    memory_id: str,
    payload: MemoryUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    memory = db.get(TripMemory, memory_id)
    if not memory or memory.trip_id != trip.id or memory.deleted_at is not None:
        raise HTTPException(status_code=404, detail="Memory not found")
    if memory.user_id != user.id:
        raise HTTPException(status_code=403, detail="Only the contributor can edit this memory")
    data = payload.model_dump(exclude_unset=True)
    for field, value in data.items():
        setattr(memory, field, value)
    if "caption" in data:
        memory.ai_generated = False
    audit(
        db,
        action="memory.update",
        entity_type="trip_memory",
        entity_id=memory.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"fields": list(data.keys())},
    )
    db.commit()
    return memory_out(memory, user)


@router.delete("/{trip_id}/memories/{memory_id}")
def delete_memory(
    trip_id: str,
    memory_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    memory = db.get(TripMemory, memory_id)
    if not memory or memory.trip_id != trip.id or memory.deleted_at is not None:
        raise HTTPException(status_code=404, detail="Memory not found")
    if memory.user_id != user.id:
        raise HTTPException(status_code=403, detail="Only the contributor can delete this memory")
    memory.deleted_at = utcnow()
    db.query(MemoryPermission).filter(MemoryPermission.memory_id == memory.id).delete()
    audit(
        db,
        action="memory.delete",
        entity_type="trip_memory",
        entity_id=memory.id,
        user_id=user.id,
        trip_id=trip.id,
    )
    db.commit()
    return {"ok": True, "note": "Removed from every shared view."}


@router.post("/{trip_id}/memories/{memory_id}/permissions")
def set_memory_permission(
    trip_id: str,
    memory_id: str,
    payload: MemoryPermissionIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    memory = db.get(TripMemory, memory_id)
    if not memory or memory.trip_id != trip.id or memory.deleted_at is not None:
        raise HTTPException(status_code=404, detail="Memory not found")
    if memory.user_id != user.id:
        raise HTTPException(status_code=403, detail="Only the contributor controls this memory's permissions")
    target_member = (
        db.query(TripMember)
        .filter(
            TripMember.trip_id == trip.id,
            TripMember.user_id == payload.user_id,
            TripMember.status == "active",
        )
        .first()
    )
    if not target_member or payload.user_id == user.id:
        raise HTTPException(status_code=422, detail="Choose another active trip member")
    row = (
        db.query(MemoryPermission)
        .filter(
            MemoryPermission.memory_id == memory.id,
            MemoryPermission.user_id == payload.user_id,
        )
        .first()
    )
    if not row:
        row = MemoryPermission(memory_id=memory.id, user_id=payload.user_id)
        db.add(row)
    row.can_view = payload.can_view
    db.commit()
    return {"ok": True, "user_id": payload.user_id, "can_view": row.can_view}


@router.post("/{trip_id}/media", status_code=201)
async def upload_media(
    trip_id: str,
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    suffix = ALLOWED_MEDIA.get(file.content_type or "")
    if not suffix:
        metrics.record_media_upload("rejected_mime")
        media_logger.warning("media_upload_rejected_mime", extra={"content_type": file.content_type, "trip_id": trip.id})
        raise HTTPException(
            status_code=415,
            detail="Supported media: JPEG, PNG, WebP, MP4, WebM audio, MP3, OGG, WAV.",
        )
    target_dir = MEDIA_ROOT / trip.id
    target_dir.mkdir(parents=True, exist_ok=True)
    filename = f"{uuid.uuid4().hex}{suffix}"
    path = target_dir / filename
    size = 0
    head = await file.read(64)
    if not media_matches_type(file.content_type, head):
        metrics.record_media_upload("rejected_mime")
        media_logger.warning("media_upload_rejected_magic_bytes", extra={"content_type": file.content_type, "trip_id": trip.id})
        raise HTTPException(
            status_code=415,
            detail="The uploaded file does not match its declared media type.",
        )
    with path.open("wb") as handle:
        chunk = head
        while chunk:
            size += len(chunk)
            if size > MAX_UPLOAD_BYTES:
                handle.close()
                path.unlink(missing_ok=True)
                metrics.record_media_upload("rejected_size")
                media_logger.warning("media_upload_rejected_size", extra={"size": size, "trip_id": trip.id})
                raise HTTPException(status_code=413, detail="Media files are limited to 25 MB.")
            handle.write(chunk)
            chunk = await file.read(1024 * 1024)
    metrics.record_media_upload("success")
    media_logger.info("media_upload_success", extra={"trip_id": trip.id, "media_type": file.content_type, "bytes": size})
    audit(
        db,
        action="media.upload",
        entity_type="trip",
        entity_id=trip.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"media_type": file.content_type, "bytes": size},
    )
    db.commit()
    return {
        "media_url": sign_media_url(f"/media/{trip.id}/{filename}"),
        "media_type": file.content_type,
        "bytes": size,
        "disclosure": "Files are stored on this deployment. Uploads are not virus-scanned.",
    }


@router.get("/{trip_id}/memory-studio")
def memory_studio(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    memories = memory_service.visible_memories(db, trip.id, user.id)
    events = memory_service.visible_events(db, trip.id, user.id)
    return {
        "memories": [memory_out(memory, user) for memory in memories],
        "events": [
            {
                "id": event.id,
                "title": event.title,
                "summary": event.summary,
                "start_at": event.start_at,
                "end_at": event.end_at,
                "memory_ids": event.memory_ids or [],
                "status": event.status,
            }
            for event in events
        ],
        "capabilities": {
            "event_grouping": "time + optional location proximity",
            "caption_grounding": "capture time, location and confirmed itinerary only",
            "image_embedding": False,
            "ocr": False,
            "speech_to_text": False,
        },
        "disclosure": (
            "Image embeddings, OCR and speech-to-text are not configured on this deployment. "
            "Suggestions use recorded metadata only."
        ),
    }


@router.post("/{trip_id}/memory-studio/suggest-events", status_code=201)
def suggest_events(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    created = memory_service.suggest_events(db, trip, user.id)
    db.commit()
    return {
        "created": [
            {
                "id": event.id,
                "title": event.title,
                "summary": event.summary,
                "start_at": event.start_at,
                "memory_ids": event.memory_ids,
                "status": event.status,
            }
            for event in created
        ],
        "note": "Suggested groups stay unapproved until a contributor approves them.",
    }


@router.post("/{trip_id}/memory-events", status_code=201)
def create_event(
    trip_id: str,
    payload: MemoryEventCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    start_at = _naive_utc(payload.start_at)
    end_at = _naive_utc(payload.end_at) if payload.end_at else None
    if end_at and end_at < start_at:
        raise HTTPException(status_code=422, detail="End time must be after the start time")
    memory_ids = []
    for memory_id in payload.memory_ids:
        memory = _memory_for_trip(db, trip, memory_id, user.id)
        memory_ids.append(memory.id)
    event = MemoryEvent(
        trip_id=trip.id,
        title=payload.title,
        summary=payload.summary,
        start_at=start_at,
        end_at=end_at,
        member_ids=[user.id],
        memory_ids=memory_ids,
        status=payload.status,
        created_by=user.id,
    )
    db.add(event)
    audit(
        db,
        action="memory_event.create",
        entity_type="memory_event",
        entity_id=event.id,
        user_id=user.id,
        trip_id=trip.id,
    )
    db.commit()
    return {
        "id": event.id,
        "title": event.title,
        "status": event.status,
        "memory_ids": event.memory_ids,
        "note": "Review AI-suggested events before approving them for the travel book.",
    }


@router.post("/{trip_id}/memory-events/{event_id}/approve")
def approve_event(
    trip_id: str,
    event_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, member = _trip(db, trip_id, user)
    event = db.get(MemoryEvent, event_id)
    if not event or event.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Memory event not found")
    if event.created_by != user.id and member.role not in ADMIN_ROLES:
        raise HTTPException(status_code=403, detail="Only the creator or a trip admin can approve")
    event.status = "approved"
    audit(
        db,
        action="memory_event.approve",
        entity_type="memory_event",
        entity_id=event.id,
        user_id=user.id,
        trip_id=trip.id,
    )
    db.commit()
    return {"ok": True, "status": event.status}


@router.post("/{trip_id}/memories/{memory_id}/caption")
def suggest_caption(
    trip_id: str,
    memory_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    memory = _memory_for_trip(db, trip, memory_id, user.id)
    suggestion = memory_service.caption_suggestion(db, trip, memory)
    audit(
        db,
        action="memory.caption_suggest",
        entity_type="trip_memory",
        entity_id=memory.id,
        user_id=user.id,
        trip_id=trip.id,
    )
    db.commit()
    return suggestion


@router.get("/{trip_id}/replay")
def journey_replay(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    return memory_service.replay(db, trip, user.id)


def _safe_media_url(url: str | None) -> str | None:
    if not url:
        return None
    if url.startswith("/media/") or url.startswith("https://"):
        return sign_media_url(url)
    return None


@router.get("/{trip_id}/travel-book")
def travel_book(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    replay = memory_service.replay(db, trip, user.id)
    sections = []
    for day in replay["days"]:
        blocks = []
        for item in day["items"]:
            blocks.append(
                f"<li class='plan'>{escape(item['start_time'])} — {escape(item['title'])}</li>"
            )
        for memory in day["memories"]:
            media = _safe_media_url(memory.get("media_url"))
            media_html = ""
            if media:
                src = escape(media, quote=True)
                if memory["kind"] == "photo":
                    media_html = f"<img src='{src}' alt='{escape(memory.get('caption') or 'Trip memory', quote=True)}'>"
                elif memory["kind"] == "video":
                    media_html = f"<video controls src='{src}'></video>"
                elif memory["kind"] == "voice":
                    media_html = f"<audio controls src='{src}'></audio>"
            caption = memory.get("caption") if memory.get("approved") else None
            body = escape((caption or memory.get("text_content") or "")[:1200])
            author = escape((memory.get("author") or {}).get("display_name") or "Traveller")
            blocks.append(
                f"<figure class='memory'>{media_html}<figcaption>{body}"
                f"<span class='byline'>— {author}</span></figcaption></figure>"
            )
        for event in day["events"]:
            blocks.append(
                f"<h3 class='event'>{escape(event['title'])}</h3>"
                f"<p class='event-summary'>{escape(event.get('summary') or '')}</p>"
            )
        sections.append(
            f"<section><h2>{escape(day['date'])}</h2><ul>{''.join(blocks)}</ul></section>"
        )
    html = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<title>{escape(trip.name)} — SAFAR travel book</title>
<style>
body{{font-family:Georgia,serif;max-width:760px;margin:40px auto;padding:0 20px;color:#1d1d1f;line-height:1.6}}
h1{{font-size:2.4rem;margin-bottom:.2rem}} .meta{{color:#666;margin-bottom:2rem}}
h2{{border-bottom:1px solid #ddd;padding-bottom:.4rem;margin-top:3rem}}
ul{{list-style:none;padding:0}} .plan{{padding:.3rem 0;color:#444}}
figure{{margin:1.2rem 0}} img,video{{max-width:100%;border-radius:8px}} audio{{width:100%}}
figcaption{{font-size:.95rem;margin-top:.4rem}} .byline{{display:block;color:#777;font-size:.85rem}}
.event{{margin:1.6rem 0 .2rem}} .event-summary{{color:#555;margin-top:0}}
footer{{margin-top:4rem;color:#777;font-size:.85rem}}
</style></head><body>
<h1>{escape(trip.name)}</h1>
<p class="meta">{escape(trip.destination_name or '')} · {trip.start_date} → {trip.end_date}</p>
{''.join(sections) or '<p>No recorded days yet.</p>'}
<footer>Generated by SAFAR journey replay. Only permitted media and approved captions are included.</footer>
</body></html>"""
    return HTMLResponse(content=html)


@router.get("/{trip_id}/offline")
def offline_snapshot(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    from app.models import Activity, Itinerary, ItineraryItem, Place

    items = (
        db.query(ItineraryItem)
        .filter(ItineraryItem.trip_id == trip.id, ItineraryItem.status == "confirmed")
        .order_by(ItineraryItem.day, ItineraryItem.sort_order, ItineraryItem.start_time)
        .all()
    )
    activities = {}
    places = {}
    if items:
        activity_ids = [item.activity_id for item in items if item.activity_id]
        activities = {
            activity.id: activity
            for activity in db.query(Activity).filter(Activity.id.in_(activity_ids)).all()
        } if activity_ids else {}
        place_ids = [activity.place_id for activity in activities.values() if activity.place_id]
        places = {
            place.id: place
            for place in db.query(Place).filter(Place.id.in_(place_ids)).all()
        } if place_ids else {}
    itinerary = db.query(Itinerary).filter(Itinerary.trip_id == trip.id).first()
    pact = db.query(JourneyPact).filter(JourneyPact.trip_id == trip.id).first()
    members = (
        db.query(TripMember)
        .filter(TripMember.trip_id == trip.id, TripMember.status == "active")
        .all()
    )
    return {
        "generated_at": utcnow().isoformat(),
        "stale_after": (datetime.combine(trip.end_date, datetime.min.time()) + timedelta(days=7)).isoformat(),
        "trip": {
            "id": trip.id,
            "name": trip.name,
            "destination": trip.destination_name,
            "start_date": trip.start_date,
            "end_date": trip.end_date,
            "currency": trip.currency,
            "base": {"lat": trip.base_lat, "lon": trip.base_lon},
        },
        "confirmed_version": itinerary.confirmed_version if itinerary else 0,
        "items": [
            {
                "id": item.id,
                "day": item.day,
                "start_time": item.start_time,
                "title": item.title,
                "cost_estimate": item.cost_estimate,
                "is_protected": item.is_protected,
                "place": (
                    {
                        "name": places[activities[item.activity_id].place_id].name,
                        "address": places[activities[item.activity_id].place_id].address,
                        "lat": places[activities[item.activity_id].place_id].lat,
                        "lon": places[activities[item.activity_id].place_id].lon,
                    }
                    if item.activity_id in activities
                    and activities[item.activity_id].place_id in places
                    else None
                ),
            }
            for item in items
        ],
        "members": [
            {"id": member.id, "display_name": member.display_name, "role": member.role}
            for member in members
        ],
        "pact": (
            {
                "must_do": pact.must_do or [],
                "flexible": pact.flexible or [],
                "confirmed_times": pact.confirmed_times or {},
            }
            if pact
            else None
        ),
        "disclosure": (
            "Offline snapshot of the confirmed plan only. Private budgets, accessibility needs "
            "and private memories are excluded. Check staleness before relying on it."
        ),
    }


@router.get("/{trip_id}/sync")
def list_sync_queue(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    rows = (
        db.query(OfflineSyncQueue)
        .filter(OfflineSyncQueue.trip_id == trip.id, OfflineSyncQueue.user_id == user.id)
        .order_by(OfflineSyncQueue.created_at.desc())
        .limit(100)
        .all()
    )
    return {
        "items": [
            {
                "client_id": row.client_id,
                "operation": row.operation,
                "status": row.status,
                "applied_at": row.applied_at,
                "created_at": row.created_at,
            }
            for row in rows
        ]
    }


@router.post("/{trip_id}/sync")
def sync_offline(
    trip_id: str,
    payload: list[OfflineSyncItem],
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    if len(payload) > 100:
        raise HTTPException(status_code=422, detail="Sync at most 100 items per request")
    results = []
    applied = 0
    skipped = 0
    rejected = 0
    for entry in payload:
        existing = (
            db.query(OfflineSyncQueue)
            .filter(OfflineSyncQueue.client_id == entry.client_id)
            .first()
        )
        if existing:
            if existing.user_id != user.id or existing.trip_id != trip.id:
                rejected += 1
                results.append(
                    {"client_id": entry.client_id, "status": "rejected", "reason": "Client id conflict"}
                )
            elif existing.operation != entry.operation or existing.payload != entry.payload:
                rejected += 1
                results.append(
                    {
                        "client_id": entry.client_id,
                        "status": "rejected",
                        "reason": "Client id reused with different content",
                    }
                )
            else:
                skipped += 1
                results.append(
                    {"client_id": entry.client_id, "status": existing.status, "id": None}
                )
            continue
        try:
            memory_payload = MemoryCreate(**entry.payload)
        except ValidationError as exc:
            rejected += 1
            results.append(
                {
                    "client_id": entry.client_id,
                    "status": "rejected",
                    "reason": "Invalid payload",
                    "errors": exc.errors(include_url=False),
                }
            )
            continue
        _validate_memory_content(
            memory_payload.kind,
            memory_payload.text_content,
            memory_payload.media_url,
            trip.id,
        )
        captured_at = _naive_utc(memory_payload.captured_at)
        memory = TripMemory(
            trip_id=trip.id,
            user_id=user.id,
            kind=memory_payload.kind,
            text_content=memory_payload.text_content,
            media_url=canonical_media_url(memory_payload.media_url),
            media_type=memory_payload.media_type,
            caption=memory_payload.caption,
            captured_at=captured_at,
            lat=memory_payload.lat,
            lon=memory_payload.lon,
            visibility=memory_payload.visibility,
        )
        db.add(memory)
        db.flush()
        db.add(
            OfflineSyncQueue(
                user_id=user.id,
                trip_id=trip.id,
                client_id=entry.client_id,
                operation=entry.operation,
                payload=entry.payload,
                status="applied",
                applied_at=utcnow(),
            )
        )
        applied += 1
        results.append(
            {"client_id": entry.client_id, "status": "applied", "id": memory.id}
        )
    audit(
        db,
        action="offline.sync",
        entity_type="trip",
        entity_id=trip.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"applied": applied, "skipped": skipped, "rejected": rejected},
    )
    db.commit()
    metrics.record_sync_batch(applied=applied, rejected=rejected, skipped=skipped)
    sync_logger.info(
        "offline_sync_batch",
        extra={"trip_id": trip.id, "applied": applied, "skipped": skipped, "rejected": rejected},
    )
    if rejected > 0:
        alert_manager.trigger(
            AlertCategory.OFFLINE_SYNC_PERSISTENT_FAILURES,
            AlertSeverity.WARNING,
            "Offline Sync Rejections",
            f"Trip {trip.id} offline sync batch had {rejected} rejected items.",
            details={"trip_id": trip.id, "rejected": rejected, "applied": applied},
        )
    return {
        "applied": applied,
        "skipped": skipped,
        "rejected": rejected,
        "results": results,
        "note": "Client ids make retries idempotent. Nothing is overwritten silently.",
    }
