import secrets
from datetime import date, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.deps import (
    get_current_user,
    get_db,
    get_trip_and_member,
    trip_scope_guard,
)
from app.core.realtime import manager
from app.db.context import set_context, system_context
from app.models import (
    AuditLog,
    Destination,
    Itinerary,
    ItineraryItem,
    ItineraryProposal,
    JourneyCapsule,
    JourneyPact,
    LocalContributor,
    Notification,
    PlannerTask,
    RecommendationBatch,
    Trip,
    TripBranch,
    TripInvitation,
    TripMember,
    TripMission,
    TripPulse,
    User,
    UserMission,
    GroundRequest,
    GroundResponse,
    Activity,
    Place,
)
from app.models.models import utcnow
from app.schemas.schemas import (
    BranchCreate,
    CapsuleCreate,
    GroundRequestIn,
    GroundResponseIn,
    InviteCreate,
    MemberRoleUpdate,
    MemberSelfUpdate,
    PactUpsert,
    TaskCreate,
    TaskUpdate,
    TripCreate,
    TripUpdate,
)
from app.services.common import (
    audit,
    event_payload,
    notify_trip_members,
    snapshot_items,
)
from app.services.geo import haversine_km, travel_minutes
from app.services.serializers import (
    invitation_out,
    member_out,
    trip_out,
)
from app.services import discovery as discovery_service
from app.integrations import email as email_service

router = APIRouter(
    prefix="/api/trips",
    tags=["trips"],
    dependencies=[Depends(trip_scope_guard)],
)
invitations_router = APIRouter(prefix="/api/invitations", tags=["invitations"])


def _trip(db, trip_id, user, roles=None):
    return get_trip_and_member(trip_id, db, user, roles)


def _validate_dates(start: date, end: date) -> None:
    if end < start:
        raise HTTPException(status_code=422, detail="End date must be on or after the start date")


def _active_member(db: Session, trip_id: str, user_id: str | None) -> TripMember | None:
    if not user_id:
        return None
    return (
        db.query(TripMember)
        .filter(
            TripMember.trip_id == trip_id,
            TripMember.user_id == user_id,
            TripMember.status == "active",
        )
        .first()
    )


@router.get("")
def list_trips(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    memberships = (
        db.query(TripMember)
        .filter(TripMember.user_id == user.id, TripMember.status == "active")
        .all()
    )
    result = []
    for membership in memberships:
        trip = db.get(Trip, membership.trip_id)
        if not trip or trip.deleted_at:
            continue
        result.append(trip_out(db, trip, membership))
    result.sort(key=lambda item: (item["start_date"] or date.max))
    return {"items": result}


@router.post("", status_code=201)
async def create_trip(
    payload: TripCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _validate_dates(payload.start_date, payload.end_date)
    destination = db.get(Destination, payload.destination_id) if payload.destination_id else None
    if payload.destination_id and not destination:
        raise HTTPException(status_code=404, detail="Destination not found")
    trip = Trip(
        name=payload.name.strip(),
        description=payload.description,
        destination_id=destination.id if destination else None,
        destination_name=(destination.name if destination else payload.destination_name or "").strip(),
        start_date=payload.start_date,
        end_date=payload.end_date,
        group_size=payload.group_size,
        budget_total=payload.budget_total,
        currency=payload.currency.upper()[:8],
        base_lat=destination.lat if destination else 0.0,
        base_lon=destination.lon if destination else 0.0,
        created_by=user.id,
        privacy="private",
    )
    db.add(trip)
    db.flush()
    membership = TripMember(
        trip_id=trip.id,
        user_id=user.id,
        role="owner",
        status="active",
        display_name=user.display_name,
    )
    db.add(membership)
    db.flush()
    db.add(Itinerary(trip_id=trip.id, confirmed_version=0))
    audit(
        db,
        action="trip.create",
        entity_type="trip",
        entity_id=trip.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"name": trip.name},
    )
    db.commit()
    return trip_out(db, trip, membership)


@router.get("/{trip_id}")
def get_trip(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, member = _trip(db, trip_id, user)
    data = trip_out(db, trip, member)
    data["next_action"] = _next_action(db, trip, member, user)
    return data


@router.patch("/{trip_id}")
async def update_trip(
    trip_id: str,
    payload: TripUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, member = _trip(db, trip_id, user, {"owner", "admin"})
    data = payload.model_dump(exclude_unset=True)
    if "start_date" in data or "end_date" in data:
        _validate_dates(
            data.get("start_date", trip.start_date), data.get("end_date", trip.end_date)
        )
    for field, value in data.items():
        setattr(trip, field, value)
    audit(
        db,
        action="trip.update",
        entity_type="trip",
        entity_id=trip.id,
        user_id=user.id,
        trip_id=trip.id,
        detail=data,
    )
    db.commit()
    await manager.broadcast(
        trip.id,
        event_payload("trip.updated", trip_id=trip.id, by=user.display_name),
    )
    return trip_out(db, trip, member)


@router.delete("/{trip_id}")
async def delete_trip(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user, {"owner"})
    trip.deleted_at = utcnow()
    audit(
        db,
        action="trip.delete",
        entity_type="trip",
        entity_id=trip.id,
        user_id=user.id,
        trip_id=trip.id,
    )
    db.commit()
    await manager.broadcast(trip.id, event_payload("trip.deleted", trip_id=trip.id))
    return {"ok": True}


@router.get("/{trip_id}/members")
def list_members(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    members = (
        db.query(TripMember)
        .filter(TripMember.trip_id == trip.id, TripMember.status == "active")
        .order_by(TripMember.joined_at)
        .all()
    )
    return {"items": [member_out(db, row, user.id) for row in members]}


@router.patch("/{trip_id}/members/me")
def update_my_membership(
    trip_id: str,
    payload: MemberSelfUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, member = _trip(db, trip_id, user)
    data = payload.model_dump(exclude_unset=True)
    for field, value in data.items():
        setattr(member, field, value)
    audit(
        db,
        action="member.update_self",
        entity_type="trip_member",
        entity_id=member.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"fields": list(data.keys())},
    )
    db.commit()
    return member_out(db, member, user.id)


@router.patch("/{trip_id}/members/{member_id}")
async def update_member_role(
    trip_id: str,
    member_id: str,
    payload: MemberRoleUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, actor = _trip(db, trip_id, user, {"owner", "admin"})
    target = db.get(TripMember, member_id)
    if not target or target.trip_id != trip.id or target.status != "active":
        raise HTTPException(status_code=404, detail="Member not found")
    if target.role == "owner":
        raise HTTPException(status_code=400, detail="Transfer ownership explicitly; it cannot be overwritten")
    if payload.role == "owner":
        if actor.role != "owner":
            raise HTTPException(status_code=403, detail="Only the owner can transfer ownership")
        actor.role = "admin"
        target.role = "owner"
    else:
        if target.user_id == user.id:
            raise HTTPException(status_code=400, detail="You cannot change your own role")
        target.role = payload.role
    audit(
        db,
        action="member.role_update",
        entity_type="trip_member",
        entity_id=target.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"role": payload.role},
    )
    db.commit()
    await manager.broadcast(
        trip.id,
        event_payload(
            "member.role_updated",
            trip_id=trip.id,
            member_id=target.id,
            role=target.role,
        ),
    )
    return member_out(db, target, user.id)


@router.delete("/{trip_id}/members/{member_id}")
async def remove_member(
    trip_id: str,
    member_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, actor = _trip(db, trip_id, user)
    target = db.get(TripMember, member_id)
    if not target or target.trip_id != trip.id or target.status != "active":
        raise HTTPException(status_code=404, detail="Member not found")
    if target.id == actor.id and target.role == "owner":
        raise HTTPException(
            status_code=400,
            detail="Transfer ownership to another member before leaving the trip.",
        )
    if target.id != actor.id and actor.role not in {"owner", "admin"}:
        raise HTTPException(status_code=403, detail="Only owners and admins can remove members")
    if target.role == "owner":
        raise HTTPException(status_code=403, detail="The owner cannot be removed")
    target.status = "left"
    audit(
        db,
        action="member.remove",
        entity_type="trip_member",
        entity_id=target.id,
        user_id=user.id,
        trip_id=trip.id,
    )
    if target.user_id and target.id != actor.id:
        db.add(
            Notification(
                user_id=target.user_id,
                trip_id=trip.id,
                kind="member_removed",
                title=f"You were removed from {trip.name}",
                link=f"/dashboard",
            )
        )
    db.commit()
    if target.user_id:
        await manager.disconnect_user(trip.id, target.user_id)
    await manager.broadcast(
        trip.id, event_payload("member.removed", trip_id=trip.id, member_id=target.id)
    )
    return {"ok": True}


@router.post("/{trip_id}/invitations", status_code=201)
def create_invitation(
    trip_id: str,
    payload: InviteCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, member = _trip(db, trip_id, user, {"owner", "admin"})
    token = secrets.token_urlsafe(24)
    invitation = TripInvitation(
        trip_id=trip.id,
        token=token,
        email=str(payload.email).lower() if payload.email else None,
        role=payload.role,
        scope=payload.scope,
        created_by=user.id,
        expires_at=utcnow() + timedelta(days=payload.expires_in_days),
    )
    db.add(invitation)
    audit(
        db,
        action="invitation.create",
        entity_type="trip_invitation",
        entity_id=invitation.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"role": payload.role, "scope": payload.scope},
    )
    db.commit()
    data = invitation_out(invitation, trip)
    data["path"] = f"/invite/{token}"
    if invitation.email:
        try:
            message = email_service.build_invitation_email(
                invitation.email, data["path"], invitation.expires_at
            )
            delivery = email_service.get_email_sender().send_invitation(message)
            if not delivery.delivered:
                email_service.email_logger.info(
                    "invitation_email_not_sent", extra={"provider": delivery.provider}
                )
        except email_service.EmailValidationError:
            email_service.email_logger.warning("invitation_email_validation_failed")
        except Exception:
            email_service.email_logger.exception("invitation_email_failed")
    return data


@router.get("/{trip_id}/invitations")
def list_invitations(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user, {"owner", "admin"})
    rows = (
        db.query(TripInvitation)
        .filter(TripInvitation.trip_id == trip.id)
        .order_by(TripInvitation.created_at.desc())
        .all()
    )
    now = utcnow()
    items = []
    for row in rows:
        data = invitation_out(row, trip)
        data["expired"] = bool(row.expires_at and row.expires_at < now)
        items.append(data)
    return {"items": items}


@router.delete("/{trip_id}/invitations/{invitation_id}")
def revoke_invitation(
    trip_id: str,
    invitation_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user, {"owner", "admin"})
    invitation = db.get(TripInvitation, invitation_id)
    if not invitation or invitation.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Invitation not found")
    db.delete(invitation)
    audit(
        db,
        action="invitation.revoke",
        entity_type="trip_invitation",
        entity_id=invitation_id,
        user_id=user.id,
        trip_id=trip.id,
    )
    db.commit()
    return {"ok": True}


@invitations_router.get("/{token}")
def preview_invitation(
    token: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    set_context(db, app_invitation_token=token)
    invitation = (
        db.query(TripInvitation).filter(TripInvitation.token == token).first()
    )
    if not invitation:
        raise HTTPException(status_code=404, detail="Invitation not found")
    now = utcnow()
    if invitation.expires_at and invitation.expires_at < now:
        raise HTTPException(status_code=410, detail="This invitation has expired")
    trip = db.get(Trip, invitation.trip_id)
    if not trip or trip.deleted_at:
        raise HTTPException(status_code=404, detail="Trip not available")
    with system_context(db):
        member_count = (
            db.query(TripMember)
            .filter(TripMember.trip_id == trip.id, TripMember.status == "active")
            .count()
        )
    return {
        "trip": {
            "id": trip.id,
            "name": trip.name,
            "destination_name": trip.destination_name,
            "start_date": trip.start_date,
            "end_date": trip.end_date,
            "group_size": trip.group_size,
            "member_count": member_count,
        },
        "role": invitation.role,
        "scope": invitation.scope,
        "invited_by": db.get(User, invitation.created_by).display_name if db.get(User, invitation.created_by) else None,
        "expires_at": invitation.expires_at,
        "already_member": _active_member(db, trip.id, user.id) is not None,
        "accepted": invitation.accepted_at is not None,
        "accepted_by_you": invitation.accepted_by == user.id,
        "email_bound": invitation.email is not None,
    }


@invitations_router.post("/{token}/accept")
async def accept_invitation(
    token: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    set_context(db, app_invitation_token=token)
    invitation = (
        db.query(TripInvitation).filter(TripInvitation.token == token).first()
    )
    if not invitation:
        raise HTTPException(status_code=404, detail="Invitation not found")
    now = utcnow()
    if invitation.expires_at and invitation.expires_at < now:
        raise HTTPException(status_code=410, detail="This invitation has expired")
    if invitation.email and invitation.email != (user.email or "").lower():
        raise HTTPException(
            status_code=403,
            detail="This invitation was issued to a different email address",
        )
    trip = db.get(Trip, invitation.trip_id)
    if not trip or trip.deleted_at:
        raise HTTPException(status_code=404, detail="Trip not available")
    member = _active_member(db, trip.id, user.id)
    if invitation.accepted_at:
        # A used invitation is only idempotent while its holder is still an
        # active member. It must never restore a member who was removed later.
        if invitation.accepted_by != user.id or not member:
            raise HTTPException(
                status_code=409,
                detail="This invitation has already been used",
            )
        return trip_out(db, trip, member)
    if not member:
        existing = (
            db.query(TripMember)
            .filter(TripMember.trip_id == trip.id, TripMember.user_id == user.id)
            .first()
        )
        if existing:
            existing.status = "active"
            existing.role = invitation.role
            existing.scope = invitation.scope
            member = existing
        else:
            member = TripMember(
                trip_id=trip.id,
                user_id=user.id,
                role=invitation.role,
                scope=invitation.scope,
                status="active",
                display_name=user.display_name,
                invited_by=invitation.created_by,
            )
            db.add(member)
    invitation.accepted_at = now
    invitation.accepted_by = user.id
    audit(
        db,
        action="invitation.accept",
        entity_type="trip_invitation",
        entity_id=invitation.id,
        user_id=user.id,
        trip_id=trip.id,
    )
    notify_trip_members(
        db,
        trip,
        kind="member_joined",
        title=f"{user.display_name} joined {trip.name}",
        link=f"/trips/{trip.id}/members",
        exclude_user_id=user.id,
    )
    db.commit()
    await manager.broadcast(
        trip.id,
        event_payload("member.joined", trip_id=trip.id, display_name=user.display_name),
    )
    return trip_out(db, trip, member)


def _next_action(db: Session, trip: Trip, member: TripMember, user: User) -> dict:
    """Decision Load Governor (F49): one clear next action for this stage."""
    today = date.today()
    items = (
        db.query(ItineraryItem)
        .filter(ItineraryItem.trip_id == trip.id, ItineraryItem.status == "confirmed")
        .count()
    )
    today_items = (
        db.query(ItineraryItem)
        .filter(
            ItineraryItem.trip_id == trip.id,
            ItineraryItem.day == today,
            ItineraryItem.status == "confirmed",
        )
        .count()
    )
    pulse = (
        db.query(TripPulse)
        .filter(
            TripPulse.trip_id == trip.id,
            TripPulse.user_id == user.id,
            TripPulse.pulse_date == today,
        )
        .first()
    )
    open_proposals = (
        db.query(ItineraryProposal)
        .filter(ItineraryProposal.trip_id == trip.id, ItineraryProposal.status == "open")
        .count()
    )
    has_batch = (
        db.query(RecommendationBatch)
        .filter(RecommendationBatch.trip_id == trip.id)
        .first()
        is not None
    )

    if trip.start_date <= today <= trip.end_date:
        if not pulse:
            action = {
                "title": "Share today's Trip Pulse",
                "reason": "The plan for today adapts to your energy, time and interests.",
                "href": f"/trips/{trip.id}/pulse",
                "kind": "pulse",
            }
        elif today_items:
            action = {
                "title": "Open today's plan",
                "reason": "Your confirmed items for today are ready.",
                "href": f"/trips/{trip.id}/itinerary",
                "kind": "today",
            }
        else:
            action = {
                "title": "Find something for today",
                "reason": "No confirmed items today — let the group engine suggest options.",
                "href": f"/trips/{trip.id}/engine",
                "kind": "engine",
            }
    elif trip.end_date < today or trip.status == "completed":
        action = {
            "title": "Create your Journey Replay",
            "reason": "Turn your memories into a shared, editable travel book.",
            "href": f"/trips/{trip.id}/memories/replay",
            "kind": "replay",
        }
    elif open_proposals:
        action = {
            "title": "There's a decision waiting",
            "reason": f"{open_proposals} proposal(s) need the group's response.",
            "href": f"/trips/{trip.id}/voting",
            "kind": "vote",
        }
    elif items == 0:
        action = {
            "title": "Build your first day",
            "reason": "Start with one activity the whole group can agree on.",
            "href": f"/trips/{trip.id}/engine",
            "kind": "engine",
        }
    elif not has_batch:
        action = {
            "title": "See three ways to spend a day",
            "reason": "Everyone Wins, Your Turn and Surprise Us are ready to compare.",
            "href": f"/trips/{trip.id}/engine",
            "kind": "engine",
        }
    else:
        action = {
            "title": "Review the shared itinerary",
            "reason": "Keep the plan current before the journey begins.",
            "href": f"/trips/{trip.id}/itinerary",
            "kind": "itinerary",
        }
    return {**action, "quiet_mode": user.quiet_mode}


@router.get("/{trip_id}/next-action")
def next_action(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, member = _trip(db, trip_id, user)
    return _next_action(db, trip, member, user)


@router.get("/{trip_id}/activity")
def trip_activity(
    trip_id: str,
    limit: int = Query(default=30, ge=1, le=100),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    rows = (
        db.query(AuditLog)
        .filter(AuditLog.trip_id == trip.id)
        .order_by(AuditLog.created_at.desc())
        .limit(limit)
        .all()
    )
    return {
        "items": [
            {
                "id": row.id,
                "action": row.action,
                "entity_type": row.entity_type,
                "entity_id": row.entity_id,
                "detail": (
                    None
                    if row.action in {"recommendation.feedback", "activity.feedback"}
                    else row.detail
                ),
                "created_at": row.created_at,
            }
            for row in rows
        ]
    }


@router.get("/{trip_id}/pact")
def get_pact(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    pact = db.query(JourneyPact).filter(JourneyPact.trip_id == trip.id).first()
    if not pact:
        return {"pact": None}
    return {
        "pact": {
            "id": pact.id,
            "must_do": pact.must_do,
            "flexible": pact.flexible,
            # Budget limits are private. A member only ever sees their own.
            "individual_limits": (
                {user.id: pact.individual_limits[user.id]}
                if user.id in (pact.individual_limits or {})
                else {}
            ),
            "confirmed_times": pact.confirmed_times,
            "exceptions": pact.exceptions,
            "updated_at": pact.updated_at,
        }
    }


@router.put("/{trip_id}/pact")
def upsert_pact(
    trip_id: str,
    payload: PactUpsert,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user, {"owner", "admin"})
    pact = db.query(JourneyPact).filter(JourneyPact.trip_id == trip.id).first()
    if not pact:
        pact = JourneyPact(trip_id=trip.id, created_by=user.id)
        db.add(pact)
    pact.must_do = payload.must_do
    pact.flexible = payload.flexible
    # Individual limits are private. Merge rather than replace so an editor who
    # cannot see other members' limits never wipes them.
    merged_limits = dict(pact.individual_limits or {})
    merged_limits.update(payload.individual_limits or {})
    pact.individual_limits = merged_limits
    pact.confirmed_times = payload.confirmed_times
    pact.exceptions = payload.exceptions
    audit(
        db,
        action="pact.update",
        entity_type="journey_pact",
        entity_id=pact.id,
        user_id=user.id,
        trip_id=trip.id,
    )
    db.commit()
    return {"ok": True}


@router.get("/{trip_id}/capsules")
def list_capsules(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    rows = (
        db.query(JourneyCapsule)
        .filter(JourneyCapsule.trip_id == trip.id)
        .order_by(JourneyCapsule.created_at.desc())
        .limit(10)
        .all()
    )
    now = utcnow()
    return {
        "items": [
            {
                "id": row.id,
                "created_at": row.created_at,
                "stale_after": row.stale_after,
                "stale": bool(row.stale_after and row.stale_after < now),
                "snapshot": row.snapshot,
            }
            for row in rows
        ]
    }


@router.post("/{trip_id}/capsules", status_code=201)
def create_capsule(
    trip_id: str,
    payload: CapsuleCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    items = (
        db.query(ItineraryItem)
        .filter(ItineraryItem.trip_id == trip.id, ItineraryItem.status == "confirmed")
        .order_by(ItineraryItem.day, ItineraryItem.sort_order)
        .all()
    )
    pact = db.query(JourneyPact).filter(JourneyPact.trip_id == trip.id).first()
    snapshot = {
        "trip": {
            "name": trip.name,
            "destination": trip.destination_name,
            "start_date": trip.start_date.isoformat(),
            "end_date": trip.end_date.isoformat(),
        },
        "items": snapshot_items(items),
        "meeting_arrangements": pact.confirmed_times if pact else {},
        "generated_by": user.display_name,
    }
    capsule = JourneyCapsule(
        trip_id=trip.id,
        snapshot=snapshot,
        stale_after=utcnow() + timedelta(hours=payload.ttl_hours),
        created_by=user.id,
    )
    db.add(capsule)
    audit(
        db,
        action="capsule.create",
        entity_type="journey_capsule",
        entity_id=capsule.id,
        user_id=user.id,
        trip_id=trip.id,
    )
    db.commit()
    return {"id": capsule.id, "stale_after": capsule.stale_after, "snapshot": snapshot}


@router.get("/{trip_id}/tasks")
def list_tasks(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    rows = (
        db.query(PlannerTask)
        .filter(PlannerTask.trip_id == trip.id)
        .order_by(PlannerTask.created_at.desc())
        .all()
    )
    return {
        "items": [
            {
                "id": row.id,
                "title": row.title,
                "description": row.description,
                "assignee_id": row.assignee_id,
                "status": row.status,
                "created_at": row.created_at,
            }
            for row in rows
        ]
    }


@router.get("/{trip_id}/tasks/summary")
def task_summary(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Server-side planner load summary (F27).

    Mirrors the planner's client-side calculation so every screen agrees.
    Only counts and display names are returned; task text stays private.
    """
    trip, _member = _trip(db, trip_id, user)
    rows = db.query(PlannerTask).filter(PlannerTask.trip_id == trip.id).all()
    members = (
        db.query(TripMember)
        .filter(TripMember.trip_id == trip.id, TripMember.status == "active")
        .all()
    )
    names: dict[str, str] = {}
    for member in members:
        if not member.user_id:
            continue
        name = member.display_name
        if not name:
            account = db.get(User, member.user_id)
            name = account.display_name if account else None
        if name:
            names[member.user_id] = name

    totals = {"open": 0, "done": 0, "total": 0}
    counts: dict[str | None, dict[str, int]] = {}
    for row in rows:
        bucket = counts.setdefault(row.assignee_id, {"open": 0, "done": 0, "total": 0})
        bucket["total"] += 1
        totals["total"] += 1
        if row.status == "done":
            bucket["done"] += 1
            totals["done"] += 1
        else:
            bucket["open"] += 1
            totals["open"] += 1

    unassigned = counts.pop(None, {"open": 0, "done": 0, "total": 0})
    by_assignee = [
        {
            "user_id": assignee_id,
            "display_name": names.get(assignee_id) or "Former member",
            "open": bucket["open"],
            "done": bucket["done"],
            "total": bucket["total"],
        }
        for assignee_id, bucket in counts.items()
    ]
    by_assignee.sort(key=lambda entry: (-entry["open"], entry["display_name"]))

    load = [
        {"key": entry["user_id"], "display_name": entry["display_name"], "open": entry["open"]}
        for entry in by_assignee
        if entry["open"]
    ]
    if unassigned["open"]:
        load.append({"key": "unassigned", "display_name": "Unassigned", "open": unassigned["open"]})
    load.sort(key=lambda entry: -entry["open"])

    return {
        "trip_id": trip.id,
        "totals": totals,
        "by_assignee": by_assignee,
        "unassigned": unassigned,
        "load": load,
        "disclosure": (
            "Counts only — task titles, notes and private member details stay in the planner."
        ),
    }


@router.post("/{trip_id}/tasks", status_code=201)
def create_task(
    trip_id: str,
    payload: TaskCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    if payload.assignee_id and not _active_member(db, trip.id, payload.assignee_id):
        raise HTTPException(status_code=422, detail="Assignee must be an active trip member")
    task = PlannerTask(
        trip_id=trip.id,
        title=payload.title,
        description=payload.description,
        assignee_id=payload.assignee_id,
        created_by=user.id,
    )
    db.add(task)
    audit(
        db,
        action="task.create",
        entity_type="planner_task",
        entity_id=task.id,
        user_id=user.id,
        trip_id=trip.id,
    )
    db.commit()
    return {"id": task.id, "title": task.title, "status": task.status}


@router.patch("/{trip_id}/tasks/{task_id}")
def update_task(
    trip_id: str,
    task_id: str,
    payload: TaskUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, member = _trip(db, trip_id, user)
    task = db.get(PlannerTask, task_id)
    if not task or task.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Task not found")
    if task.assignee_id and task.assignee_id != user.id and member.role not in {"owner", "admin"}:
        raise HTTPException(status_code=403, detail="Only the assignee or an admin can update this task")
    data = payload.model_dump(exclude_unset=True)
    if data.get("assignee_id") and not _active_member(db, trip.id, data["assignee_id"]):
        raise HTTPException(status_code=422, detail="Assignee must be an active trip member")
    for field, value in data.items():
        setattr(task, field, value)
    db.commit()
    return {"id": task.id, "status": task.status, "assignee_id": task.assignee_id}


@router.get("/{trip_id}/branches")
def list_branches(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    rows = (
        db.query(TripBranch)
        .filter(TripBranch.trip_id == trip.id)
        .order_by(TripBranch.created_at.desc())
        .all()
    )
    return {
        "items": [
            {
                "id": row.id,
                "name": row.name,
                "member_ids": row.member_ids,
                "activity_id": row.activity_id,
                "reunion_at": row.reunion_at,
                "reunion_place": row.reunion_place,
                "status": row.status,
            }
            for row in rows
        ]
    }


@router.post("/{trip_id}/branches", status_code=201)
def create_branch(
    trip_id: str,
    payload: BranchCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    for member_id in payload.member_ids:
        member = db.get(TripMember, member_id)
        if not member or member.trip_id != trip.id or member.status != "active":
            raise HTTPException(status_code=422, detail="Branches can only include active members")
    activity = db.get(Activity, payload.activity_id) if payload.activity_id else None
    if payload.activity_id and not activity:
        raise HTTPException(status_code=404, detail="Activity not found")
    feasibility = {
        "status": "unknown",
        "note": "Reunion travel feasibility is not verified unless the reunion place is a catalog activity.",
    }
    if activity and payload.reunion_place and payload.reunion_at:
        reunion_activity = (
            db.query(Activity)
            .filter(Activity.destination_id == trip.destination_id, Activity.name.ilike(payload.reunion_place))
            .first()
        )
        if reunion_activity and activity.place_id and reunion_activity.place_id:
            origin = db.get(Place, activity.place_id)
            target = db.get(Place, reunion_activity.place_id)
            if origin and target:
                distance = haversine_km(origin.lat, origin.lon, target.lat, target.lon)
                minutes = travel_minutes(distance)
                feasibility = {
                    "status": "estimated",
                    "distance_km": distance,
                    "travel_minutes": minutes,
                    "note": "Estimated from straight-line distance, not live routing.",
                }
    branch = TripBranch(
        trip_id=trip.id,
        name=payload.name,
        member_ids=payload.member_ids,
        activity_id=payload.activity_id,
        reunion_at=payload.reunion_at,
        reunion_place=payload.reunion_place,
        created_by=user.id,
    )
    db.add(branch)
    audit(
        db,
        action="branch.create",
        entity_type="trip_branch",
        entity_id=branch.id,
        user_id=user.id,
        trip_id=trip.id,
    )
    db.commit()
    return {"id": branch.id, "feasibility": feasibility}


@router.get("/{trip_id}/ground-requests")
def list_ground_requests(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    rows = (
        db.query(GroundRequest)
        .filter(GroundRequest.trip_id == trip.id)
        .order_by(GroundRequest.created_at.desc())
        .all()
    )
    items = []
    for row in rows:
        responses = db.query(GroundResponse).filter(GroundResponse.request_id == row.id).all()
        items.append(
            {
                "id": row.id,
                "question": row.question,
                "place_id": row.place_id,
                "activity_id": row.activity_id,
                "status": row.status,
                "created_at": row.created_at,
                "responses": [
                    {
                        "id": response.id,
                        "observation": response.observation,
                        "observed_at": response.observed_at,
                        "confidence": response.confidence,
                        "verified": response.verified,
                        "provenance": "REPORTED (unverified)" if not response.verified else "VERIFIED",
                        "contributor_id": response.contributor_id,
                    }
                    for response in responses
                ],
            }
        )
    return {"items": items}


@router.post("/{trip_id}/ground-requests", status_code=201)
def create_ground_request(
    trip_id: str,
    payload: GroundRequestIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    if not payload.place_id and not payload.activity_id:
        raise HTTPException(status_code=422, detail="A place or activity is required")
    if payload.activity_id:
        activity = db.get(Activity, payload.activity_id)
        if not activity:
            raise HTTPException(status_code=404, detail="Activity not found")
    request = GroundRequest(
        trip_id=trip.id,
        place_id=payload.place_id,
        activity_id=payload.activity_id,
        question=payload.question,
        requested_by=user.id,
    )
    db.add(request)
    db.commit()
    return {"id": request.id, "status": request.status}


@router.post("/{trip_id}/ground-requests/{request_id}/responses", status_code=201)
def respond_ground_request(
    trip_id: str,
    request_id: str,
    payload: GroundResponseIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # Local contributors are not trip members. They answer as opted-in locals
    # for the destination, so this endpoint checks contributor status rather
    # than membership; it never returns trip details to them.
    if db.get_bind().dialect.name == "postgresql":
        # Security-definer helper returns only the destination id, so the
        # contributor never gains row access to unrelated trip data.
        destination_id = db.execute(
            text("SELECT safar_ground_request_destination(:rid)"),
            {"rid": request_id},
        ).scalar()
        if not destination_id:
            raise HTTPException(status_code=404, detail="Trip not found")
    else:
        trip = db.get(Trip, trip_id)
        if not trip or trip.deleted_at:
            raise HTTPException(status_code=404, detail="Trip not found")
        destination_id = trip.destination_id
    contributor = (
        db.query(LocalContributor)
        .filter(
            LocalContributor.user_id == user.id,
            LocalContributor.accepts_requests.is_(True),
        )
        .first()
    )
    if not contributor:
        raise HTTPException(
            status_code=403,
            detail="Only opt-in local contributors can answer ground requests",
        )
    if contributor.destination_id != destination_id:
        raise HTTPException(
            status_code=403,
            detail="Only contributors for this destination can answer",
        )
    request = db.get(GroundRequest, request_id)
    if not request or request.trip_id != trip_id:
        raise HTTPException(status_code=404, detail="Request not found")
    response = GroundResponse(
        request_id=request.id,
        contributor_id=user.id,
        observation=payload.observation,
        confidence=payload.confidence,
        verified=False,
    )
    db.add(response)
    db.flush()
    request.status = "answered"
    audit(
        db,
        action="ground.response",
        entity_type="ground_response",
        entity_id=response.id,
        user_id=user.id,
        trip_id=trip_id,
    )
    db.commit()
    return {
        "id": response.id,
        "provenance": "REPORTED (unverified)",
        "note": "One traveller observation never becomes verified information automatically.",
    }


@router.get("/{trip_id}/missions")
def list_missions(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    missions = discovery_service.generate_missions(db, trip, user.id)
    db.commit()
    joined = {
        row.mission_id: row
        for row in db.query(UserMission).filter(UserMission.user_id == user.id).all()
    }
    return {
        "items": [
            {
                "id": mission.id,
                "title": mission.title,
                "description": mission.description,
                "constraints": mission.constraints,
                "status": mission.status,
                "my_status": joined.get(mission.id).status if joined.get(mission.id) else None,
                "optional": True,
                "self_reported": True,
            }
            for mission in missions
        ],
        "note": "Missions are optional and can be disabled. Completion is self-reported.",
    }


@router.post("/{trip_id}/missions/{mission_id}/join")
def join_mission(
    trip_id: str,
    mission_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    mission = db.get(TripMission, mission_id)
    if not mission or mission.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Mission not found")
    if mission.status == "disabled":
        raise HTTPException(status_code=400, detail="This mission is disabled")
    row = (
        db.query(UserMission)
        .filter(UserMission.mission_id == mission.id, UserMission.user_id == user.id)
        .first()
    )
    if not row:
        row = UserMission(mission_id=mission.id, user_id=user.id)
        db.add(row)
        db.commit()
    return {"ok": True, "status": row.status}


@router.post("/{trip_id}/missions/{mission_id}/complete")
def complete_mission(
    trip_id: str,
    mission_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    mission = db.get(TripMission, mission_id)
    if not mission or mission.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Mission not found")
    row = (
        db.query(UserMission)
        .filter(UserMission.mission_id == mission.id, UserMission.user_id == user.id)
        .first()
    )
    if not row:
        row = UserMission(mission_id=mission.id, user_id=user.id)
        db.add(row)
    row.status = "completed"
    row.completed_at = utcnow()
    db.commit()
    return {"ok": True, "status": row.status, "self_reported": True}


@router.post("/{trip_id}/missions/{mission_id}/disable")
def disable_mission(
    trip_id: str,
    mission_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user, {"owner", "admin"})
    mission = db.get(TripMission, mission_id)
    if not mission or mission.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Mission not found")
    mission.status = "disabled"
    db.commit()
    return {"ok": True}
