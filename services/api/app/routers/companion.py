from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.deps import (
    get_current_user,
    get_db,
    get_trip_and_member,
    trip_scope_guard,
)
from app.db.context import companion_context
from app.models import (
    CompanionLink,
    CompanionResponse,
    ItineraryItem,
    ItineraryProposal,
    User,
)
from app.models.models import utcnow
from app.schemas.schemas import CompanionLinkIn, CompanionResponseIn
from app.services import companion as companion_service
from app.services.common import audit

router = APIRouter(
    prefix="/api/trips",
    tags=["companion"],
    dependencies=[Depends(trip_scope_guard)],
)
public_router = APIRouter(prefix="/api/companion", tags=["companion"])


def _link_brief(db: Session, link: CompanionLink) -> dict:
    responses = (
        db.query(func.count(CompanionResponse.id))
        .filter(CompanionResponse.link_id == link.id)
        .scalar()
        or 0
    )
    values = {
        value: count
        for value, count in (
            db.query(CompanionResponse.value, func.count(CompanionResponse.id))
            .filter(CompanionResponse.link_id == link.id)
            .group_by(CompanionResponse.value)
            .all()
        )
    }
    target = None
    if link.purpose == "vote":
        proposal = db.get(ItineraryProposal, link.target_id)
        target = {
            "kind": "proposal",
            "id": link.target_id,
            "title": proposal.title if proposal else "Decision removed",
            "status": proposal.status if proposal else "missing",
        }
    else:
        item = db.get(ItineraryItem, link.target_id)
        target = {
            "kind": "checkin",
            "id": link.target_id,
            "title": item.title if item else "Item removed",
            "day": item.day.isoformat() if item else None,
            "status": item.status if item else "missing",
        }
    return {
        "id": link.id,
        "purpose": link.purpose,
        "target": target,
        "status": companion_service.link_status(link),
        "expires_at": link.expires_at,
        "max_uses": link.max_uses,
        "used_count": link.used_count,
        "anonymous_responses": responses,
        "response_values": values,
        "created_at": link.created_at,
    }


@router.post("/{trip_id}/companion-links", status_code=201)
def create_companion_link(
    trip_id: str,
    payload: CompanionLinkIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = get_trip_and_member(trip_id, db, user)

    if payload.purpose == "vote":
        target = db.get(ItineraryProposal, payload.target_id)
        if not target or target.trip_id != trip.id:
            raise HTTPException(status_code=404, detail="Decision not found")
        if target.status != "open":
            raise HTTPException(status_code=422, detail="Only open decisions can be shared.")
    else:
        target = db.get(ItineraryItem, payload.target_id)
        if not target or target.trip_id != trip.id:
            raise HTTPException(status_code=404, detail="Itinerary item not found")
        if target.status != "confirmed":
            raise HTTPException(
                status_code=422, detail="Only confirmed itinerary items can be shared."
            )

    link = CompanionLink(
        trip_id=trip.id,
        created_by=user.id,
        purpose=payload.purpose,
        target_id=payload.target_id,
        expires_at=companion_service.expires_from_now(payload.ttl_minutes),
        max_uses=1,
        used_count=0,
    )
    db.add(link)
    db.flush()
    token = companion_service.issue_token(link)
    audit(
        db,
        action="companion.create",
        entity_type="companion_link",
        entity_id=link.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"purpose": link.purpose, "target_id": link.target_id},
    )
    db.commit()
    return {
        "link": _link_brief(db, link),
        "token": token,
        "url": f"/companion/{token}",
        "disclosure": (
            "Anyone with this link can answer once, without an account. Their identity is not recorded. "
            "The link expires on its own and can be revoked."
        ),
    }


@router.get("/{trip_id}/companion-links")
def list_companion_links(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, member = get_trip_and_member(trip_id, db, user)
    query = db.query(CompanionLink).filter(CompanionLink.trip_id == trip.id)
    if member.role not in {"owner", "admin"}:
        query = query.filter(CompanionLink.created_by == user.id)
    links = query.order_by(CompanionLink.created_at.desc()).all()
    return {
        "items": [_link_brief(db, link) for link in links],
        "disclosure": "Tokens are shown once when created and are never listed again.",
    }


@router.post("/{trip_id}/companion-links/{link_id}/revoke")
def revoke_companion_link(
    trip_id: str,
    link_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, member = get_trip_and_member(trip_id, db, user)
    link = db.get(CompanionLink, link_id)
    if not link or link.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Link not found")
    if link.created_by != user.id and member.role not in {"owner", "admin"}:
        raise HTTPException(status_code=403, detail="Only the creator or an owner can revoke this link")
    if not link.revoked_at:
        link.revoked_at = utcnow()
        audit(
            db,
            action="companion.revoke",
            entity_type="companion_link",
            entity_id=link.id,
            user_id=user.id,
            trip_id=trip.id,
        )
        db.commit()
    return {"id": link.id, "status": companion_service.link_status(link)}


@router.get("/{trip_id}/companion-links/{link_id}/responses")
def list_companion_responses(
    trip_id: str,
    link_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, member = get_trip_and_member(trip_id, db, user)
    link = db.get(CompanionLink, link_id)
    if not link or link.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Link not found")
    if link.created_by != user.id and member.role not in {"owner", "admin"}:
        raise HTTPException(status_code=403, detail="Only the creator or an owner can read responses")
    rows = (
        db.query(CompanionResponse)
        .filter(CompanionResponse.link_id == link.id)
        .order_by(CompanionResponse.created_at)
        .all()
    )
    return {
        "items": [
            {"id": row.id, "value": row.value, "comment": row.comment, "created_at": row.created_at}
            for row in rows
        ],
        "anonymous": True,
        "disclosure": "No respondent identity, IP address or device identifier is stored.",
    }


@public_router.get("/{token}")
def companion_view(token: str, db: Session = Depends(get_db)):
    parsed = companion_service.parse_token(token)
    if parsed:
        companion_context(db, parsed[0])
    link, error = companion_service.resolve_active(db, token)
    if error:
        status_code = 404 if link is None else 410
        raise HTTPException(status_code=status_code, detail=error)
    return companion_service.context(db, link)


@public_router.post("/{token}/respond")
def respond(token: str, payload: CompanionResponseIn, db: Session = Depends(get_db)):
    parsed = companion_service.parse_token(token)
    if parsed:
        companion_context(db, parsed[0])
    link, error = companion_service.resolve_active(db, token)
    if error:
        status_code = 404 if link is None else 410
        raise HTTPException(status_code=status_code, detail=error)

    allowed = (
        companion_service.VOTE_VALUES
        if link.purpose == "vote"
        else companion_service.CHECKIN_VALUES
    )
    if payload.value not in allowed:
        raise HTTPException(
            status_code=422,
            detail=f"Choose one of: {', '.join(allowed)}",
        )
    ok, reason = companion_service.target_open(db, link)
    if not ok:
        raise HTTPException(status_code=409, detail=reason)

    db.add(
        CompanionResponse(
            link_id=link.id,
            value=payload.value,
            comment=(payload.comment or "").strip() or None,
        )
    )
    link.used_count += 1
    audit(
        db,
        action="companion.response",
        entity_type="companion_link",
        entity_id=link.id,
        user_id=None,
        trip_id=link.trip_id,
        detail={"purpose": link.purpose, "value": payload.value},
    )
    db.commit()
    db.refresh(link)
    return {
        "ok": True,
        "recorded": payload.value,
        "anonymous": True,
        "remaining_uses": max(0, link.max_uses - link.used_count),
        "message": "Thank you — your answer was recorded without an account.",
    }
