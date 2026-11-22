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
    Place,
    Profile,
    Trip,
    TripMember,
    TripPulse,
    User,
)
from app.schemas.schemas import PulseIn
from app.services.common import audit, event_payload, normalize_tag
from app.services.engine import BUDGET_COMFORT_CAP
from app.services.geo import haversine_km, travel_minutes
from app.services.serializers import pulse_out

router = APIRouter(
    prefix="/api/trips",
    tags=["pulse"],
    dependencies=[Depends(trip_scope_guard)],
)


def _pulse_rows(db: Session, trip_id: str, day: date) -> list[TripPulse]:
    return (
        db.query(TripPulse)
        .filter(TripPulse.trip_id == trip_id, TripPulse.pulse_date == day)
        .order_by(TripPulse.created_at)
        .all()
    )


def _affected_items(db: Session, trip: Trip, member: TripMember, pulse: TripPulse) -> list[dict]:
    """Constraint Compass (F35): exactly what today's change puts at risk."""
    profile = db.query(Profile).filter(Profile.user_id == member.user_id).first()
    accessibility = list(member.accessibility_needs or [])
    if not accessibility and profile:
        accessibility = list(profile.accessibility_needs or [])
    needs_wheelchair = any(
        "wheel" in need.lower() or "mobility" in need.lower() for need in accessibility
    )
    items = (
        db.query(ItineraryItem)
        .filter(
            ItineraryItem.trip_id == trip.id,
            ItineraryItem.day == pulse.pulse_date,
            ItineraryItem.status == "confirmed",
        )
        .order_by(ItineraryItem.start_time)
        .all()
    )
    affected = []
    for item in items:
        if item.is_protected:
            continue
        activity = db.get(Activity, item.activity_id) if item.activity_id else None
        if not activity:
            continue
        place = db.get(Place, activity.place_id) if activity.place_id else None
        distance = (
            haversine_km(trip.base_lat, trip.base_lon, place.lat, place.lon)
            if place
            else 0.0
        )
        travel = travel_minutes(distance)
        reasons = []
        if pulse.radius_km is not None and distance > pulse.radius_km:
            reasons.append(
                f"{distance:.1f} km away, beyond today's {pulse.radius_km:.0f} km radius."
            )
        if (
            pulse.available_minutes is not None
            and activity.duration_minutes + travel * 2 > pulse.available_minutes
        ):
            reasons.append(
                f"Needs about {activity.duration_minutes + travel * 2} minutes including travel; "
                f"you have {pulse.available_minutes}."
            )
        cap = BUDGET_COMFORT_CAP.get(pulse.budget_comfort)
        if cap is not None and activity.price_estimate > cap:
            reasons.append(
                f"Estimated cost {activity.currency} {activity.price_estimate:.0f} is above today's comfort level."
            )
        if activity.effort > pulse.energy + 1:
            reasons.append(
                f"Effort {activity.effort}/5 is high for today's energy {pulse.energy}/5."
            )
        if needs_wheelchair and activity.wheelchair_accessible is not True:
            reasons.append(
                "Accessibility is not confirmed for this activity, which your profile requires."
            )
        if reasons:
            affected.append(
                {
                    "item_id": item.id,
                    "title": item.title,
                    "start_time": item.start_time,
                    "reasons": reasons,
                }
            )
    return affected


@router.get("/{trip_id}/pulse")
def get_pulse(
    trip_id: str,
    day: date | None = Query(default=None),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = get_trip_and_member(trip_id, db, user)
    pulse_date = day or date.today()
    rows = _pulse_rows(db, trip.id, pulse_date)
    members = {
        member.user_id: member
        for member in db.query(TripMember)
        .filter(TripMember.trip_id == trip.id, TripMember.status == "active")
        .all()
        if member.user_id
    }
    items = []
    for row in rows:
        data = pulse_out(row, user.id)
        author = db.get(User, row.user_id)
        data["author"] = {"id": row.user_id, "display_name": author.display_name} if author else None
        items.append(data)
    return {
        "date": pulse_date,
        "items": items,
        "my_pulse": next(
            (item for item in items if item["user_id"] == user.id), None
        ),
        "coverage": {"shared": len(rows), "members": len(members)},
        "privacy": "Budget comfort and notes are private. Shared pulse values are used for today's recommendations only.",
    }


@router.put("/{trip_id}/pulse")
async def upsert_pulse(
    trip_id: str,
    payload: PulseIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, member = get_trip_and_member(trip_id, db, user)
    pulse_date = payload.pulse_date or date.today()
    pulse = (
        db.query(TripPulse)
        .filter(
            TripPulse.trip_id == trip.id,
            TripPulse.user_id == user.id,
            TripPulse.pulse_date == pulse_date,
        )
        .first()
    )
    previous = (
        {
            "energy": pulse.energy,
            "available_minutes": pulse.available_minutes,
            "radius_km": pulse.radius_km,
            "budget_comfort": pulse.budget_comfort,
            "interests": pulse.interests,
        }
        if pulse
        else None
    )
    if not pulse:
        pulse = TripPulse(
            trip_id=trip.id,
            user_id=user.id,
            pulse_date=pulse_date,
        )
        db.add(pulse)
    pulse.energy = payload.energy
    pulse.interests = [normalize_tag(interest) for interest in payload.interests]
    pulse.available_minutes = payload.available_minutes
    pulse.budget_comfort = payload.budget_comfort
    pulse.radius_km = payload.radius_km
    pulse.activity_prefs = [normalize_tag(tag) for tag in payload.activity_prefs]
    pulse.note = payload.note
    db.flush()
    affected = _affected_items(db, trip, member, pulse)
    changed = []
    if previous:
        for field in ("energy", "available_minutes", "radius_km", "budget_comfort", "interests"):
            if previous.get(field) != getattr(pulse, field):
                changed.append(field)
    audit(
        db,
        action="pulse.update",
        entity_type="trip_pulse",
        entity_id=pulse.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"date": pulse_date.isoformat(), "changed": changed},
    )
    db.commit()
    await manager.broadcast(
        trip.id,
        event_payload(
            "pulse.updated", trip_id=trip.id, user_id=user.id, date=pulse_date.isoformat()
        ),
    )
    return {
        "pulse": pulse_out(pulse, user.id),
        "changed_fields": changed,
        "affected_items": affected,
        "constraint_compass": {
            "summary": (
                "No confirmed items conflict with today's constraints."
                if not affected
                else f"{len(affected)} confirmed item(s) no longer fit today's constraints."
            ),
            "items": affected,
            "note": "This check is about today only and does not modify the confirmed itinerary.",
        },
    }
