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
    Destination,
    Itinerary,
    ItineraryApproval,
    ItineraryAttendance,
    ItineraryItem,
    ItineraryProposal,
    ItineraryVersion,
    JourneyPact,
    Place,
    Shadowplan,
    Trip,
    TripMember,
    User,
    Vote,
)
from app.models.models import utcnow
from app.schemas.schemas import (
    ApprovalIn,
    AttendanceUpdate,
    ItemCreate,
    ItemUpdate,
    ProposalCreate,
    ShadowplanCreate,
    VoteIn,
)
from app.services.common import (
    audit,
    event_payload,
    notify_trip_members,
    record_itinerary_version,
)
from app.services.optimizer import (
    domino_map,
    effort_budget,
    fragility_report,
)
from app.services.schedule import find_conflict, item_window, parse_hhmm
from app.services.serializers import (
    activity_out,
    item_out,
    proposal_out,
    version_out,
)

router = APIRouter(
    prefix="/api/trips",
    tags=["itinerary"],
    dependencies=[Depends(trip_scope_guard)],
)

ADMIN_ROLES = {"owner", "admin"}


def _trip(db, trip_id, user, roles=None):
    return get_trip_and_member(trip_id, db, user, roles)


def _get_itinerary(db: Session, trip: Trip) -> Itinerary:
    itinerary = db.query(Itinerary).filter(Itinerary.trip_id == trip.id).first()
    if not itinerary:
        itinerary = Itinerary(trip_id=trip.id, confirmed_version=0)
        db.add(itinerary)
        db.flush()
    return itinerary


def _serialize_items(db: Session, items: list[ItineraryItem], viewer_id: str) -> list[dict]:
    activity_ids = [item.activity_id for item in items if item.activity_id]
    activities = (
        db.query(Activity).filter(Activity.id.in_(activity_ids)).all() if activity_ids else []
    )
    activity_map = {activity.id: activity for activity in activities}
    place_ids = [activity.place_id for activity in activities if activity.place_id]
    places = db.query(Place).filter(Place.id.in_(place_ids)).all() if place_ids else []
    place_map = {place.id: place for place in places}
    destination_ids = {activity.destination_id for activity in activities}
    destinations = (
        db.query(Destination).filter(Destination.id.in_(destination_ids)).all()
        if destination_ids
        else []
    )
    destination_map = {destination.id: destination for destination in destinations}

    attendance_rows = (
        db.query(ItineraryAttendance)
        .filter(ItineraryAttendance.item_id.in_([item.id for item in items]))
        .all()
        if items
        else []
    )
    attendance: dict[str, list[ItineraryAttendance]] = {}
    for row in attendance_rows:
        attendance.setdefault(row.item_id, []).append(row)

    result = []
    for item in items:
        activity = activity_map.get(item.activity_id) if item.activity_id else None
        payload = item_out(item)
        payload["activity"] = (
            activity_out(
                activity,
                place_map.get(activity.place_id),
                destination_map.get(activity.destination_id),
            )
            if activity
            else None
        )
        rows = attendance.get(item.id, [])
        payload["attendance"] = {
            "in": len([row for row in rows if row.status == "in"]),
            "out": len([row for row in rows if row.status == "out"]),
            "join_later": len([row for row in rows if row.status == "join_later"]),
            "my_status": next(
                (row.status for row in rows if row.user_id == viewer_id), "in"
            ),
        }
        result.append(payload)
    return result


@router.get("/{trip_id}/itinerary")
def get_itinerary(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, member = _trip(db, trip_id, user)
    itinerary = _get_itinerary(db, trip)
    items = (
        db.query(ItineraryItem)
        .filter(
            ItineraryItem.trip_id == trip.id,
            ItineraryItem.status == "confirmed",
        )
        .order_by(ItineraryItem.day, ItineraryItem.sort_order, ItineraryItem.start_time)
        .all()
    )
    versions = (
        db.query(ItineraryVersion)
        .filter(ItineraryVersion.itinerary_id == itinerary.id)
        .order_by(ItineraryVersion.version.desc())
        .limit(15)
        .all()
    )
    open_proposals = (
        db.query(ItineraryProposal)
        .filter(ItineraryProposal.trip_id == trip.id, ItineraryProposal.status == "open")
        .all()
    )
    total_cost = sum(item.cost_estimate for item in items)
    return {
        "itinerary_id": itinerary.id,
        "confirmed_version": itinerary.confirmed_version,
        "my_role": member.role,
        "items": _serialize_items(db, items, user.id),
        "versions": [version_out(version) for version in versions],
        "open_proposals": len(open_proposals),
        "totals": {
            "items": len(items),
            "cost": round(total_cost, 2),
            "currency": trip.currency,
            "days": len({item.day for item in items}),
            "protected_items": len([item for item in items if item.is_protected]),
        },
    }


def _next_sort_order(db: Session, trip_id: str, item_day: date) -> int:
    last = (
        db.query(ItineraryItem)
        .filter(ItineraryItem.trip_id == trip_id, ItineraryItem.day == item_day)
        .order_by(ItineraryItem.sort_order.desc())
        .first()
    )
    return (last.sort_order + 1) if last else 0


def _within_trip(trip: Trip, day: date) -> None:
    if day < trip.start_date or day > trip.end_date:
        raise HTTPException(
            status_code=422,
            detail=(
                f"{day.isoformat()} is outside the trip dates "
                f"({trip.start_date.isoformat()} to {trip.end_date.isoformat()})."
            ),
        )


def _validate_times(
    start_time: str,
    end_time: str | None,
    *,
    has_activity: bool,
    is_protected: bool,
) -> None:
    start = parse_hhmm(start_time)
    end = parse_hhmm(end_time)
    if start is None:
        raise HTTPException(status_code=422, detail="start_time must use HH:MM")
    if end is not None and end <= start:
        raise HTTPException(status_code=422, detail="end_time must be later than start_time")
    if is_protected and not has_activity and end is None:
        raise HTTPException(
            status_code=422,
            detail="Protected time without an activity needs an end_time so the reservation is unambiguous.",
        )


def _protected_conflict(
    db: Session,
    trip: Trip,
    day: date,
    *,
    start_minutes: int,
    duration_minutes: int,
    exclude_item_id: str | None = None,
) -> dict | None:
    conflicts = (
        db.query(ItineraryItem)
        .filter(
            ItineraryItem.trip_id == trip.id,
            ItineraryItem.day == day,
            ItineraryItem.status == "confirmed",
        )
        .all()
    )
    conflict = find_conflict(
        db,
        conflicts,
        start_minutes=start_minutes,
        duration_minutes=duration_minutes,
        ignore_item_ids={exclude_item_id} if exclude_item_id else None,
    )
    return conflict if conflict and conflict["protected"] else None


def _raise_protected_conflict(conflict: dict) -> None:
    raise HTTPException(
        status_code=409,
        detail={
            "message": "This time overlaps protected time. Choose another slot or change the protected block explicitly.",
            "conflict": conflict,
        },
    )


@router.post("/{trip_id}/itinerary/items", status_code=201)
async def add_item(
    trip_id: str,
    payload: ItemCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user, ADMIN_ROLES)
    _within_trip(trip, payload.day)
    itinerary = _get_itinerary(db, trip)
    activity = db.get(Activity, payload.activity_id) if payload.activity_id else None
    if payload.activity_id and not activity:
        raise HTTPException(status_code=404, detail="Activity not found")
    if activity and activity.destination_id != trip.destination_id:
        raise HTTPException(status_code=422, detail="Activity is not in this trip's destination")
    title = payload.title or (activity.name if activity else None)
    if not title:
        raise HTTPException(status_code=422, detail="A title is required")
    _validate_times(
        payload.start_time,
        payload.end_time,
        has_activity=activity is not None,
        is_protected=payload.is_protected,
    )
    start = parse_hhmm(payload.start_time)
    end = parse_hhmm(payload.end_time)
    duration = (
        end - start
        if end is not None and start is not None
        else (activity.duration_minutes if activity else 90)
    )
    conflict = _protected_conflict(
        db,
        trip,
        payload.day,
        start_minutes=start,
        duration_minutes=duration,
    )
    if conflict:
        _raise_protected_conflict(conflict)
    item = ItineraryItem(
        itinerary_id=itinerary.id,
        trip_id=trip.id,
        day=payload.day,
        start_time=payload.start_time,
        end_time=payload.end_time,
        title=title,
        activity_id=activity.id if activity else None,
        place_id=activity.place_id if activity else None,
        notes=payload.notes,
        cost_estimate=(
            payload.cost_estimate
            if payload.cost_estimate is not None
            else (activity.price_estimate if activity else 0.0)
        ),
        is_protected=payload.is_protected,
        created_by=user.id,
        sort_order=_next_sort_order(db, trip.id, payload.day),
    )
    db.add(item)
    db.flush()
    record_itinerary_version(
        db, itinerary, user_id=user.id, note=f"Added {item.title}"
    )
    audit(
        db,
        action="itinerary.item_add",
        entity_type="itinerary_item",
        entity_id=item.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"title": item.title},
    )
    notify_trip_members(
        db,
        trip,
        kind="itinerary_updated",
        title=f"{user.display_name} added {item.title}",
        link=f"/trips/{trip.id}/itinerary",
        exclude_user_id=user.id,
    )
    db.commit()
    await manager.broadcast(
        trip.id,
        event_payload("itinerary.updated", trip_id=trip.id, by=user.display_name),
    )
    return _serialize_items(db, [item], user.id)[0]


@router.patch("/{trip_id}/itinerary/items/{item_id}")
async def update_item(
    trip_id: str,
    item_id: str,
    payload: ItemUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user, ADMIN_ROLES)
    item = db.get(ItineraryItem, item_id)
    if not item or item.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Itinerary item not found")
    data = payload.model_dump(exclude_unset=True)
    if "day" in data:
        _within_trip(trip, data["day"])
    if {"start_time", "end_time", "day", "is_protected"} & data.keys():
        activity = db.get(Activity, item.activity_id) if item.activity_id else None
        prospective_day = data.get("day", item.day)
        prospective_start = data.get("start_time", item.start_time)
        prospective_end = data.get("end_time", item.end_time)
        prospective_protected = data.get("is_protected", item.is_protected)
        _validate_times(
            prospective_start,
            prospective_end,
            has_activity=activity is not None,
            is_protected=prospective_protected,
        )
        if data.get("status", item.status) == "confirmed":
            start = parse_hhmm(prospective_start)
            end = parse_hhmm(prospective_end)
            duration = (
                end - start
                if end is not None and start is not None
                else (activity.duration_minutes if activity else 90)
            )
            conflict = _protected_conflict(
                db,
                trip,
                prospective_day,
                start_minutes=start,
                duration_minutes=duration,
                exclude_item_id=item.id,
            )
            if conflict:
                _raise_protected_conflict(conflict)
    for field, value in data.items():
        setattr(item, field, value)
    db.flush()
    itinerary = _get_itinerary(db, trip)
    record_itinerary_version(
        db, itinerary, user_id=user.id, note=f"Updated {item.title}"
    )
    audit(
        db,
        action="itinerary.item_update",
        entity_type="itinerary_item",
        entity_id=item.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"fields": list(data.keys())},
    )
    notify_trip_members(
        db,
        trip,
        kind="itinerary_updated",
        title=f"{user.display_name} updated {item.title}",
        link=f"/trips/{trip.id}/itinerary",
        exclude_user_id=user.id,
    )
    db.commit()
    await manager.broadcast(
        trip.id, event_payload("itinerary.updated", trip_id=trip.id)
    )
    return _serialize_items(db, [item], user.id)[0]


@router.delete("/{trip_id}/itinerary/items/{item_id}")
async def delete_item(
    trip_id: str,
    item_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user, ADMIN_ROLES)
    item = db.get(ItineraryItem, item_id)
    if not item or item.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Itinerary item not found")
    item.status = "cancelled"
    db.flush()
    itinerary = _get_itinerary(db, trip)
    record_itinerary_version(
        db, itinerary, user_id=user.id, note=f"Removed {item.title}"
    )
    audit(
        db,
        action="itinerary.item_remove",
        entity_type="itinerary_item",
        entity_id=item.id,
        user_id=user.id,
        trip_id=trip.id,
    )
    notify_trip_members(
        db,
        trip,
        kind="itinerary_updated",
        title=f"{user.display_name} removed {item.title}",
        link=f"/trips/{trip.id}/itinerary",
        exclude_user_id=user.id,
    )
    db.commit()
    await manager.broadcast(
        trip.id, event_payload("itinerary.updated", trip_id=trip.id)
    )
    return {"ok": True}


def _build_proposal_operations(db: Session, trip: Trip, proposal: ItineraryProposal) -> list[dict]:
    """Validate and normalise a proposal into concrete itinerary operations."""
    payload = proposal.payload or {}
    operations: list[dict] = []

    def add_activity_op(activity_id: str, day_value, start_time, notes, title=None):
        activity = db.get(Activity, activity_id)
        if not activity:
            raise HTTPException(status_code=422, detail="A proposed activity no longer exists")
        if activity.destination_id != trip.destination_id:
            raise HTTPException(status_code=422, detail="A proposed activity is outside this destination")
        if day_value is None:
            raise HTTPException(status_code=422, detail="A proposed item is missing its day")
        day = day_value if isinstance(day_value, date) else date.fromisoformat(str(day_value))
        _within_trip(trip, day)
        start = start_time or "09:00"
        if len(start) != 5 or ":" not in start:
            raise HTTPException(status_code=422, detail="Invalid start time in proposal")
        operations.append(
            {
                "op": "add",
                "activity_id": activity.id,
                "day": day,
                "start_time": start,
                "notes": notes,
                "title": title or activity.name,
                "cost": activity.price_estimate,
                "place_id": activity.place_id,
            }
        )

    def cancel_op(item_id: str | None):
        if not item_id:
            return
        item = db.get(ItineraryItem, item_id)
        if not item or item.trip_id != trip.id:
            raise HTTPException(status_code=422, detail="A referenced itinerary item no longer exists")
        operations.append({"op": "cancel", "item_id": item.id, "title": item.title, "cost": -item.cost_estimate})

    if proposal.kind == "add_activity":
        add_activity_op(
            payload.get("activity_id"),
            payload.get("day"),
            payload.get("start_time"),
            payload.get("notes"),
        )
    elif proposal.kind == "replace_item":
        cancel_op(payload.get("target_item_id"))
        add_activity_op(
            payload.get("activity_id"),
            payload.get("day"),
            payload.get("start_time"),
            payload.get("notes"),
        )
    elif proposal.kind == "remove_item":
        cancel_op(payload.get("target_item_id"))
    elif proposal.kind == "twin_adopt":
        day = payload.get("day")
        if day:
            day_value = day if isinstance(day, date) else date.fromisoformat(str(day))
            existing = (
                db.query(ItineraryItem)
                .filter(
                    ItineraryItem.trip_id == trip.id,
                    ItineraryItem.day == day_value,
                    ItineraryItem.status == "confirmed",
                )
                .all()
            )
            for item in existing:
                cancel_op(item.id)
        for entry in payload.get("items", []):
            add_activity_op(
                entry.get("activity_id"),
                entry.get("day", payload.get("day")),
                entry.get("start_time"),
                entry.get("notes"),
            )
    elif proposal.kind == "rescue":
        for entry in payload.get("items", []):
            cancel_op(entry.get("item_id"))
            if entry.get("activity_id"):
                add_activity_op(
                    entry.get("activity_id"),
                    entry.get("day"),
                    entry.get("start_time"),
                    entry.get("notes", "Trip Rescue replacement"),
                )
    else:
        for entry in payload.get("items", []):
            add_activity_op(
                entry.get("activity_id"),
                entry.get("day"),
                entry.get("start_time"),
                entry.get("notes"),
            )
        for item_id in payload.get("remove_item_ids", []):
            cancel_op(item_id)

    if not operations:
        raise HTTPException(status_code=422, detail="This proposal contains no itinerary changes")
    return operations


def _pact_conflicts(db: Session, trip: Trip, operations: list[dict]) -> list[dict]:
    pact = db.query(JourneyPact).filter(JourneyPact.trip_id == trip.id).first()
    if not pact:
        return []
    must_do = {str(title).strip().lower() for title in (pact.must_do or [])}
    exceptions = {str(title).strip().lower() for title in (pact.exceptions or [])}
    conflicts = []
    for operation in operations:
        if operation["op"] != "cancel":
            continue
        title = (operation.get("title") or "").strip().lower()
        if not title:
            continue
        for rule in must_do:
            if rule and (rule in title or title in rule):
                if any(exception in title or title in exception for exception in exceptions):
                    continue
                conflicts.append(
                    {
                        "item": operation["title"],
                        "rule": "Agreed must-do activity (Journey Pact)",
                        "resolution": "Add a Journey Pact exception or keep the item.",
                    }
                )
    return conflicts


def _schedule_conflicts(db: Session, trip: Trip, operations: list[dict]) -> list[dict]:
    """Protected-time and overlap guard for proposal approval.

    Operations are simulated in order: cancels free a slot, adds consume one.
    A change may never remove a protected block or place an activity on top of
    one, and two activities cannot claim the same minutes.
    """
    confirmed = (
        db.query(ItineraryItem)
        .filter(ItineraryItem.trip_id == trip.id, ItineraryItem.status == "confirmed")
        .all()
    )
    remaining = {item.id: item for item in confirmed}
    added: list[dict] = []
    conflicts: list[dict] = []
    for operation in operations:
        if operation["op"] == "cancel":
            item = remaining.pop(operation["item_id"], None)
            if item and item.is_protected:
                conflicts.append(
                    {
                        "item": item.title,
                        "reason": "Protected time cannot be removed by this change.",
                        "protected": True,
                    }
                )
            continue
        day = operation.get("day")
        start = parse_hhmm(operation.get("start_time"))
        if not day or start is None:
            continue
        day_value = day if isinstance(day, date) else date.fromisoformat(str(day))
        activity = (
            db.get(Activity, operation["activity_id"])
            if operation.get("activity_id")
            else None
        )
        duration = activity.duration_minutes if activity and activity.duration_minutes else 90
        end = start + duration
        windows: list[tuple[str, int, int, bool]] = []
        for item in remaining.values():
            if item.day != day_value:
                continue
            window = item_window(db, item)
            if window:
                windows.append((item.title, window[0], window[1], bool(item.is_protected)))
        windows.extend(
            (entry["title"], entry["start_minutes"], entry["end_minutes"], False)
            for entry in added
            if entry["day"] == day_value
        )
        for title, window_start, window_end, protected in windows:
            if start < window_end and window_start < end:
                conflicts.append(
                    {
                        "item": title,
                        "proposed": operation.get("title"),
                        "reason": (
                            "Protected time would be overlapped."
                            if protected
                            else "Another confirmed item would overlap."
                        ),
                        "protected": protected,
                    }
                )
                break
        added.append(
            {
                "title": operation.get("title"),
                "day": day_value,
                "start_minutes": start,
                "end_minutes": end,
            }
        )
    return conflicts


def _proposal_impact(db: Session, trip: Trip, proposal: ItineraryProposal) -> dict:
    operations = _build_proposal_operations(db, trip, proposal)
    total_delta = round(sum(operation.get("cost", 0) for operation in operations), 2)
    members = (
        db.query(TripMember)
        .filter(TripMember.trip_id == trip.id, TripMember.status == "active")
        .all()
    )
    per_member = round(total_delta / max(1, len(members)), 2)
    budget_conflicts = []
    for operation in operations:
        if operation["op"] != "add":
            continue
        for member in members:
            if member.budget_limit is not None and operation["cost"] > member.budget_limit:
                budget_conflicts.append(
                    {
                        "reason": "A stated hard budget limit would be exceeded.",
                        "item": operation["title"],
                    }
                )
    return {
        "operations": [
            {
                "op": operation["op"],
                "title": operation.get("title"),
                "day": operation.get("day"),
                "start_time": operation.get("start_time"),
                "cost": operation.get("cost"),
            }
            for operation in operations
        ],
        "cost_impact": {
            "total_delta": total_delta,
            "per_member_estimate": per_member,
            "currency": trip.currency,
            "note": "Per-member estimate assumes an equal share of the group plan.",
        },
        "budget_conflicts": budget_conflicts,
        "pact_conflicts": _pact_conflicts(db, trip, operations),
        "schedule_conflicts": _schedule_conflicts(db, trip, operations),
        "requires_approval": True,
    }


@router.post("/{trip_id}/proposals", status_code=201)
async def create_proposal(
    trip_id: str,
    payload: ProposalCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    if payload.kind == "add_activity" and not payload.activity_id:
        raise HTTPException(status_code=422, detail="activity_id is required for add_activity")
    if payload.kind == "replace_item" and (not payload.activity_id or not payload.target_item_id):
        raise HTTPException(
            status_code=422,
            detail="replace_item needs both activity_id and target_item_id",
        )
    if payload.kind == "remove_item" and not payload.target_item_id:
        raise HTTPException(status_code=422, detail="target_item_id is required for remove_item")

    proposal = ItineraryProposal(
        trip_id=trip.id,
        kind=payload.kind,
        title=payload.title,
        summary=payload.summary,
        target_day=payload.day,
        created_by=user.id,
        payload={
            "activity_id": payload.activity_id,
            "day": payload.day.isoformat() if payload.day else None,
            "start_time": payload.start_time,
            "target_item_id": payload.target_item_id,
            **payload.payload,
        },
    )
    db.add(proposal)
    db.flush()
    try:
        impact = _proposal_impact(db, trip, proposal)
    except HTTPException:
        db.rollback()
        raise
    audit(
        db,
        action="proposal.create",
        entity_type="itinerary_proposal",
        entity_id=proposal.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"kind": proposal.kind, "title": proposal.title},
    )
    notify_trip_members(
        db,
        trip,
        kind="proposal_created",
        title=f"New proposal: {proposal.title}",
        body=f"{user.display_name} asked the group to decide.",
        link=f"/trips/{trip.id}/voting",
        exclude_user_id=user.id,
    )
    db.commit()
    await manager.broadcast(
        trip.id,
        event_payload("proposal.created", trip_id=trip.id, proposal_id=proposal.id),
    )
    return {**proposal_out(db, proposal, user.id), "impact": impact}


@router.get("/{trip_id}/proposals")
def list_proposals(
    trip_id: str,
    status: str = Query(default="open", pattern=r"^(open|approved|rejected|withdrawn|all)$"),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    query = db.query(ItineraryProposal).filter(ItineraryProposal.trip_id == trip.id)
    if status != "all":
        query = query.filter(ItineraryProposal.status == status)
    rows = query.order_by(ItineraryProposal.created_at.desc()).all()
    return {"items": [proposal_out(db, row, user.id) for row in rows]}


@router.get("/{trip_id}/proposals/{proposal_id}")
def get_proposal(
    trip_id: str,
    proposal_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    proposal = db.get(ItineraryProposal, proposal_id)
    if not proposal or proposal.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Proposal not found")
    try:
        impact = _proposal_impact(db, trip, proposal)
    except HTTPException as exc:
        impact = {"error": exc.detail}
    return {**proposal_out(db, proposal, user.id), "impact": impact}


@router.post("/{trip_id}/proposals/{proposal_id}/vote")
async def vote_proposal(
    trip_id: str,
    proposal_id: str,
    payload: VoteIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    proposal = db.get(ItineraryProposal, proposal_id)
    if not proposal or proposal.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Proposal not found")
    if proposal.status != "open":
        raise HTTPException(status_code=409, detail="This proposal is no longer open")
    vote = (
        db.query(Vote)
        .filter(Vote.proposal_id == proposal.id, Vote.user_id == user.id)
        .first()
    )
    if not vote:
        vote = Vote(proposal_id=proposal.id, user_id=user.id)
        db.add(vote)
    vote.value = payload.value
    vote.comment = payload.comment
    audit(
        db,
        action="proposal.vote",
        entity_type="itinerary_proposal",
        entity_id=proposal.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"value": payload.value},
    )
    db.commit()
    await manager.broadcast(
        trip.id,
        event_payload(
            "proposal.voted",
            trip_id=trip.id,
            proposal_id=proposal.id,
            voter=user.display_name,
        ),
    )
    return proposal_out(db, proposal, user.id)


@router.post("/{trip_id}/proposals/{proposal_id}/approve")
async def approve_proposal(
    trip_id: str,
    proposal_id: str,
    payload: ApprovalIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user, ADMIN_ROLES)
    proposal = db.get(ItineraryProposal, proposal_id)
    if not proposal or proposal.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Proposal not found")
    if proposal.status != "open":
        raise HTTPException(status_code=409, detail="This proposal is no longer open")
    if not payload.approval:
        raise HTTPException(status_code=422, detail="Use the reject action instead")

    operations = _build_proposal_operations(db, trip, proposal)
    conflicts = _pact_conflicts(db, trip, operations)
    if conflicts:
        raise HTTPException(
            status_code=409,
            detail={
                "message": "This change breaks the Journey Pact.",
                "conflicts": conflicts,
            },
        )
    schedule_conflicts = _schedule_conflicts(db, trip, operations)
    if schedule_conflicts:
        raise HTTPException(
            status_code=409,
            detail={
                "message": "This change conflicts with protected time or an existing item.",
                "conflicts": schedule_conflicts,
            },
        )

    members = (
        db.query(TripMember)
        .filter(TripMember.trip_id == trip.id, TripMember.status == "active")
        .all()
    )
    for operation in operations:
        if operation["op"] != "add":
            continue
        for member in members:
            if member.budget_limit is not None and operation["cost"] > member.budget_limit:
                raise HTTPException(
                    status_code=409,
                    detail={
                        "message": "At least one member's stated hard budget limit would be exceeded.",
                        "item": operation["title"],
                    },
                )

    itinerary = _get_itinerary(db, trip)
    created_items: list[ItineraryItem] = []
    for operation in operations:
        if operation["op"] == "cancel":
            item = db.get(ItineraryItem, operation["item_id"])
            if item:
                item.status = "cancelled"
                item.updated_at = utcnow()
            continue
        item = ItineraryItem(
            itinerary_id=itinerary.id,
            trip_id=trip.id,
            day=operation["day"],
            start_time=operation["start_time"],
            title=operation["title"],
            activity_id=operation["activity_id"],
            place_id=operation["place_id"],
            notes=operation.get("notes"),
            cost_estimate=operation["cost"],
            created_by=user.id,
            sort_order=_next_sort_order(db, trip.id, operation["day"]),
        )
        db.add(item)
        created_items.append(item)

    proposal.status = "approved"
    proposal.decided_by = user.id
    proposal.decided_at = utcnow()
    db.add(
        ItineraryApproval(
            proposal_id=proposal.id, user_id=user.id, approval=True
        )
    )
    db.flush()
    record_itinerary_version(
        db, itinerary, user_id=user.id, note=f"Approved: {proposal.title}"
    )
    audit(
        db,
        action="proposal.approve",
        entity_type="itinerary_proposal",
        entity_id=proposal.id,
        user_id=user.id,
        trip_id=trip.id,
    )
    notify_trip_members(
        db,
        trip,
        kind="proposal_approved",
        title=f"Approved: {proposal.title}",
        body=f"{user.display_name} confirmed the change with the group.",
        link=f"/trips/{trip.id}/itinerary",
        exclude_user_id=user.id,
    )
    total_delta = round(sum(operation.get("cost", 0) for operation in operations), 2)
    db.commit()
    await manager.broadcast(
        trip.id,
        event_payload(
            "proposal.approved",
            trip_id=trip.id,
            proposal_id=proposal.id,
            version=itinerary.confirmed_version,
        ),
    )
    return {
        **proposal_out(db, proposal, user.id),
        "confirmed_version": itinerary.confirmed_version,
        "created_items": _serialize_items(db, created_items, user.id),
        "cost_impact": {
            "total_delta": total_delta,
            "per_member_estimate": round(total_delta / max(1, len(members)), 2),
            "currency": trip.currency,
        },
    }


@router.post("/{trip_id}/proposals/{proposal_id}/reject")
async def reject_proposal(
    trip_id: str,
    proposal_id: str,
    reason: str | None = Query(default=None, max_length=500),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user, ADMIN_ROLES)
    proposal = db.get(ItineraryProposal, proposal_id)
    if not proposal or proposal.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Proposal not found")
    if proposal.status != "open":
        raise HTTPException(status_code=409, detail="This proposal is no longer open")
    proposal.status = "rejected"
    proposal.decided_by = user.id
    proposal.decided_at = utcnow()
    if reason:
        proposal.summary = f"{proposal.summary or ''}\nRejected: {reason}".strip()
    audit(
        db,
        action="proposal.reject",
        entity_type="itinerary_proposal",
        entity_id=proposal.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"reason": reason},
    )
    notify_trip_members(
        db,
        trip,
        kind="proposal_rejected",
        title=f"Not this time: {proposal.title}",
        body=reason,
        link=f"/trips/{trip.id}/voting",
        exclude_user_id=user.id,
    )
    db.commit()
    await manager.broadcast(
        trip.id,
        event_payload("proposal.rejected", trip_id=trip.id, proposal_id=proposal.id),
    )
    return proposal_out(db, proposal, user.id)


@router.post("/{trip_id}/proposals/{proposal_id}/withdraw")
async def withdraw_proposal(
    trip_id: str,
    proposal_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, member = _trip(db, trip_id, user)
    proposal = db.get(ItineraryProposal, proposal_id)
    if not proposal or proposal.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Proposal not found")
    if proposal.created_by != user.id and member.role not in ADMIN_ROLES:
        raise HTTPException(status_code=403, detail="Only the author or an admin can withdraw")
    if proposal.status != "open":
        raise HTTPException(status_code=409, detail="This proposal is no longer open")
    proposal.status = "withdrawn"
    proposal.decided_at = utcnow()
    db.commit()
    await manager.broadcast(
        trip.id,
        event_payload("proposal.withdrawn", trip_id=trip.id, proposal_id=proposal.id),
    )
    return proposal_out(db, proposal, user.id)


@router.post("/{trip_id}/itinerary/items/{item_id}/attendance")
def update_attendance(
    trip_id: str,
    item_id: str,
    payload: AttendanceUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    item = db.get(ItineraryItem, item_id)
    if not item or item.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Itinerary item not found")
    row = (
        db.query(ItineraryAttendance)
        .filter(ItineraryAttendance.item_id == item.id, ItineraryAttendance.user_id == user.id)
        .first()
    )
    if not row:
        row = ItineraryAttendance(item_id=item.id, user_id=user.id, status=payload.status)
        db.add(row)
    else:
        row.status = payload.status
    audit(
        db,
        action="itinerary.attendance",
        entity_type="itinerary_item",
        entity_id=item.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"status": payload.status},
    )
    db.commit()
    return {"ok": True, "status": row.status, "note": "No reason is required or recorded."}


@router.get("/{trip_id}/itinerary/versions")
def list_versions(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    itinerary = _get_itinerary(db, trip)
    rows = (
        db.query(ItineraryVersion)
        .filter(ItineraryVersion.itinerary_id == itinerary.id)
        .order_by(ItineraryVersion.version.desc())
        .all()
    )
    return {"items": [version_out(row) for row in rows]}


@router.get("/{trip_id}/fragility")
def get_fragility(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    items = (
        db.query(ItineraryItem)
        .filter(ItineraryItem.trip_id == trip.id, ItineraryItem.status == "confirmed")
        .all()
    )
    return fragility_report(db, trip, items)


@router.get("/{trip_id}/domino")
def get_domino(
    trip_id: str,
    item_id: str = Query(...),
    delay_minutes: int = Query(default=45, ge=0, le=600),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    items = (
        db.query(ItineraryItem)
        .filter(ItineraryItem.trip_id == trip.id, ItineraryItem.status == "confirmed")
        .all()
    )
    result = domino_map(db, items, item_id, delay_minutes)
    if not result:
        raise HTTPException(status_code=404, detail="Disrupted item not found")
    return result


@router.get("/{trip_id}/effort")
def get_effort(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    items = (
        db.query(ItineraryItem)
        .filter(ItineraryItem.trip_id == trip.id, ItineraryItem.status == "confirmed")
        .all()
    )
    return effort_budget(db, items)


@router.post("/{trip_id}/shadowplans", status_code=201)
def create_shadowplan(
    trip_id: str,
    payload: ShadowplanCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    item = db.get(ItineraryItem, payload.item_id)
    if not item or item.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Itinerary item not found")
    activity = db.get(Activity, payload.backup_activity_id)
    if not activity or activity.destination_id != trip.destination_id:
        raise HTTPException(status_code=422, detail="Backup must be a catalog activity in this destination")
    plan = Shadowplan(
        trip_id=trip.id,
        itinerary_item_id=item.id,
        backup_activity_id=activity.id,
        notes=payload.notes,
        readiness={"status": "ready", "checked_at": utcnow().isoformat()},
        created_by=user.id,
    )
    db.add(plan)
    audit(
        db,
        action="shadowplan.create",
        entity_type="shadowplan",
        entity_id=plan.id,
        user_id=user.id,
        trip_id=trip.id,
    )
    db.commit()
    return {"id": plan.id, "backup_activity_id": activity.id, "readiness": plan.readiness}


@router.get("/{trip_id}/shadowplans")
def list_shadowplans(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    rows = db.query(Shadowplan).filter(Shadowplan.trip_id == trip.id).all()
    return {
        "items": [
            {
                "id": row.id,
                "item_id": row.itinerary_item_id,
                "backup_activity_id": row.backup_activity_id,
                "notes": row.notes,
                "readiness": row.readiness,
                "created_at": row.created_at,
            }
            for row in rows
        ]
    }
