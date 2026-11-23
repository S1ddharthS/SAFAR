import secrets
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.deps import get_current_user, get_db, get_trip_and_member
from app.db.context import set_context
from app.models import (
    EmergencyContact,
    SoloSafetySettings,
    Trip,
    TripCheckIn,
    TripMember,
    User,
)
from app.models.models import utcnow
from app.schemas.schemas import (
    EmergencyContactCreate,
    EmergencyContactOut,
    LocalEmergencyNumbers,
    SafetyBeaconOut,
    SoloSafetySettingsOut,
    SoloSafetySettingsUpdate,
    SoloSafetyStatusOut,
    TripCheckInCreate,
    TripCheckInOut,
)
from app.services.common import audit

router = APIRouter(prefix="/api/trips/{trip_id}/safety", tags=["safety"])
public_router = APIRouter(prefix="/api/safety", tags=["safety-public"])


def _resolve_emergency_numbers(destination_name: str | None) -> LocalEmergencyNumbers:
    dest = (destination_name or "").lower()
    if any(k in dest for k in ["japan", "kyoto", "tokyo", "osaka", "hokkaido"]):
        return LocalEmergencyNumbers(
            country_code="JP",
            country_name="Japan",
            police="110",
            ambulance="119",
            fire="119",
            general="110",
        )
    if any(k in dest for k in ["uk", "united kingdom", "britain", "london", "edinburgh", "england", "scotland"]):
        return LocalEmergencyNumbers(
            country_code="GB",
            country_name="United Kingdom",
            police="999",
            ambulance="999",
            fire="999",
            general="112",
        )
    if any(k in dest for k in ["usa", "united states", "america", "canada", "new york", "san francisco", "toronto", "vancouver"]):
        return LocalEmergencyNumbers(
            country_code="US",
            country_name="United States & Canada",
            police="911",
            ambulance="911",
            fire="911",
            general="911",
        )
    if any(k in dest for k in ["india", "delhi", "mumbai", "bengaluru", "bangalore", "goa", "kerala"]):
        return LocalEmergencyNumbers(
            country_code="IN",
            country_name="India",
            police="112",
            ambulance="108",
            fire="101",
            general="112",
        )
    if any(k in dest for k in ["australia", "sydney", "melbourne", "brisbane"]):
        return LocalEmergencyNumbers(
            country_code="AU",
            country_name="Australia",
            police="000",
            ambulance="000",
            fire="000",
            general="112",
        )
    if any(k in dest for k in ["france", "germany", "italy", "spain", "paris", "rome", "berlin", "barcelona", "amsterdam", "europe"]):
        return LocalEmergencyNumbers(
            country_code="EU",
            country_name="European Union",
            police="112",
            ambulance="112",
            fire="112",
            general="112",
        )
    return LocalEmergencyNumbers(
        country_code="INTL",
        country_name="International Standard",
        police="112",
        ambulance="112",
        fire="112",
        general="112",
    )


def _get_or_create_settings(db: Session, trip_id: str) -> SoloSafetySettings:
    settings = db.get(SoloSafetySettings, trip_id)
    if not settings:
        settings = SoloSafetySettings(
            trip_id=trip_id,
            check_in_frequency_hours=24,
            location_sharing_enabled=False,
        )
        db.add(settings)
        db.flush()
    return settings


@router.get("", response_model=SoloSafetyStatusOut)
def get_safety_status(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, member = get_trip_and_member(trip_id, db, user)
    settings = _get_or_create_settings(db, trip.id)
    contacts = (
        db.query(EmergencyContact)
        .filter(EmergencyContact.trip_id == trip.id)
        .order_by(EmergencyContact.is_primary.desc(), EmergencyContact.created_at.asc())
        .all()
    )
    check_ins = (
        db.query(TripCheckIn)
        .filter(TripCheckIn.trip_id == trip.id)
        .order_by(TripCheckIn.created_at.desc())
        .limit(20)
        .all()
    )

    last_check_in = check_ins[0] if check_ins else None
    now = utcnow()
    is_overdue = False
    hours_overdue = 0.0

    if settings.next_check_in_due and now > settings.next_check_in_due:
        is_overdue = True
        hours_overdue = max(0.0, (now - settings.next_check_in_due).total_seconds() / 3600.0)

    is_solo = getattr(trip, "trip_type", "group") == "solo" or trip.group_size == 1

    return SoloSafetyStatusOut(
        trip_id=trip.id,
        trip_name=trip.name,
        is_solo=is_solo,
        settings=SoloSafetySettingsOut(
            trip_id=settings.trip_id,
            check_in_frequency_hours=settings.check_in_frequency_hours,
            last_check_in_at=settings.last_check_in_at,
            next_check_in_due=settings.next_check_in_due,
            location_sharing_enabled=settings.location_sharing_enabled,
            share_token=settings.share_token,
            updated_at=settings.updated_at,
        ),
        contacts=[
            EmergencyContactOut(
                id=c.id,
                trip_id=c.trip_id,
                user_id=c.user_id,
                name=c.name,
                relationship=c.relationship,
                phone=c.phone,
                email=c.email,
                notes=c.notes,
                is_primary=c.is_primary,
                created_at=c.created_at,
            )
            for c in contacts
        ],
        recent_check_ins=[
            TripCheckInOut(
                id=ci.id,
                trip_id=ci.trip_id,
                user_id=ci.user_id,
                status=ci.status,
                location_name=ci.location_name,
                lat=ci.lat,
                lon=ci.lon,
                message=ci.message,
                created_at=ci.created_at,
            )
            for ci in check_ins
        ],
        last_check_in=TripCheckInOut(
            id=last_check_in.id,
            trip_id=last_check_in.trip_id,
            user_id=last_check_in.user_id,
            status=last_check_in.status,
            location_name=last_check_in.location_name,
            lat=last_check_in.lat,
            lon=last_check_in.lon,
            message=last_check_in.message,
            created_at=last_check_in.created_at,
        )
        if last_check_in
        else None,
        is_overdue=is_overdue,
        hours_overdue=round(hours_overdue, 1),
        local_emergency_numbers=_resolve_emergency_numbers(trip.destination_name),
    )


@router.post("/contacts", status_code=201, response_model=EmergencyContactOut)
def add_emergency_contact(
    trip_id: str,
    payload: EmergencyContactCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, member = get_trip_and_member(trip_id, db, user, {"owner", "admin"})

    if payload.is_primary:
        db.query(EmergencyContact).filter(
            EmergencyContact.trip_id == trip.id
        ).update({"is_primary": False})

    contact = EmergencyContact(
        trip_id=trip.id,
        user_id=user.id,
        name=payload.name.strip(),
        relationship=payload.relationship.strip(),
        phone=payload.phone.strip(),
        email=payload.email,
        notes=payload.notes,
        is_primary=payload.is_primary,
    )
    db.add(contact)
    db.commit()
    db.refresh(contact)

    audit(
        db,
        action="safety.contact.create",
        entity_type="emergency_contact",
        entity_id=contact.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"name": contact.name, "relationship": contact.relationship},
    )

    return EmergencyContactOut(
        id=contact.id,
        trip_id=contact.trip_id,
        user_id=contact.user_id,
        name=contact.name,
        relationship=contact.relationship,
        phone=contact.phone,
        email=contact.email,
        notes=contact.notes,
        is_primary=contact.is_primary,
        created_at=contact.created_at,
    )


@router.delete("/contacts/{contact_id}", status_code=204)
def delete_emergency_contact(
    trip_id: str,
    contact_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, member = get_trip_and_member(trip_id, db, user, {"owner", "admin"})
    contact = db.get(EmergencyContact, contact_id)
    if not contact or contact.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Emergency contact not found")

    db.delete(contact)
    db.commit()

    audit(
        db,
        action="safety.contact.delete",
        entity_type="emergency_contact",
        entity_id=contact_id,
        user_id=user.id,
        trip_id=trip.id,
    )


@router.post("/check-in", status_code=201, response_model=TripCheckInOut)
def record_check_in(
    trip_id: str,
    payload: TripCheckInCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, member = get_trip_and_member(trip_id, db, user)
    settings = _get_or_create_settings(db, trip.id)

    now = utcnow()
    check_in = TripCheckIn(
        trip_id=trip.id,
        user_id=user.id,
        status=payload.status,
        location_name=payload.location_name,
        lat=payload.lat,
        lon=payload.lon,
        message=payload.message,
        created_at=now,
    )
    db.add(check_in)

    settings.last_check_in_at = now
    freq = settings.check_in_frequency_hours or 24
    settings.next_check_in_due = now + timedelta(hours=freq)
    db.flush()

    audit(
        db,
        action="safety.check_in",
        entity_type="trip_check_in",
        entity_id=check_in.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"status": payload.status, "location": payload.location_name},
    )
    db.commit()
    db.refresh(check_in)

    return TripCheckInOut(
        id=check_in.id,
        trip_id=check_in.trip_id,
        user_id=check_in.user_id,
        status=check_in.status,
        location_name=check_in.location_name,
        lat=check_in.lat,
        lon=check_in.lon,
        message=check_in.message,
        created_at=check_in.created_at,
    )


@router.patch("/settings", response_model=SoloSafetySettingsOut)
def update_safety_settings(
    trip_id: str,
    payload: SoloSafetySettingsUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, member = get_trip_and_member(trip_id, db, user, {"owner", "admin"})
    settings = _get_or_create_settings(db, trip.id)

    if payload.check_in_frequency_hours is not None:
        settings.check_in_frequency_hours = payload.check_in_frequency_hours
        if settings.last_check_in_at:
            settings.next_check_in_due = settings.last_check_in_at + timedelta(
                hours=payload.check_in_frequency_hours
            )

    if payload.location_sharing_enabled is not None:
        settings.location_sharing_enabled = payload.location_sharing_enabled
        if payload.location_sharing_enabled and not settings.share_token:
            settings.share_token = secrets.token_urlsafe(24)

    db.commit()
    db.refresh(settings)

    return SoloSafetySettingsOut(
        trip_id=settings.trip_id,
        check_in_frequency_hours=settings.check_in_frequency_hours,
        last_check_in_at=settings.last_check_in_at,
        next_check_in_due=settings.next_check_in_due,
        location_sharing_enabled=settings.location_sharing_enabled,
        share_token=settings.share_token,
        updated_at=settings.updated_at,
    )


@public_router.get("/beacon/{token}", response_model=SafetyBeaconOut)
def get_safety_beacon(token: str, db: Session = Depends(get_db)):
    """Unauthenticated public endpoint for family/trusted contacts to view status via share link."""
    settings = (
        db.query(SoloSafetySettings)
        .filter(
            SoloSafetySettings.share_token == token,
            SoloSafetySettings.location_sharing_enabled == True,
        )
        .first()
    )
    if not settings:
        raise HTTPException(
            status_code=404,
            detail="Safety beacon not found or location sharing is not enabled.",
        )

    trip = db.get(Trip, settings.trip_id)
    if not trip or trip.deleted_at:
        raise HTTPException(status_code=404, detail="Trip not found.")

    owner = db.get(User, trip.created_by)
    traveler_name = owner.display_name if owner else "SAFAR Traveler"

    last_check_in = (
        db.query(TripCheckIn)
        .filter(TripCheckIn.trip_id == trip.id)
        .order_by(TripCheckIn.created_at.desc())
        .first()
    )

    now = utcnow()
    is_overdue = bool(settings.next_check_in_due and now > settings.next_check_in_due)

    return SafetyBeaconOut(
        traveler_name=traveler_name,
        trip_name=trip.name,
        destination_name=trip.destination_name,
        status=last_check_in.status if last_check_in else "safe",
        last_check_in_at=last_check_in.created_at if last_check_in else None,
        last_location_name=last_check_in.location_name if last_check_in else None,
        last_message=last_check_in.message if last_check_in else None,
        next_check_in_due=settings.next_check_in_due,
        is_overdue=is_overdue,
    )
