from datetime import datetime

from sqlalchemy.orm import Session

from app.services.media import sign_media_url
from app.models import (
    Activity,
    Destination,
    Expense,
    ExpenseParticipant,
    ItineraryItem,
    ItineraryProposal,
    ItineraryVersion,
    Place,
    PlaceReport,
    Recommendation,
    Trip,
    TripInvitation,
    TripMember,
    TripMemory,
    TripPulse,
    User,
    Vote,
)


def user_public(user: User | None) -> dict | None:
    if not user:
        return None
    return {
        "id": user.id,
        "display_name": user.display_name,
        "avatar_url": user.avatar_url,
        "locale": user.locale,
    }


def user_out(user: User) -> dict:
    return {
        "id": user.id,
        "email": user.email,
        "display_name": user.display_name,
        "is_admin": user.is_admin,
        "quiet_mode": user.quiet_mode,
        "locale": user.locale,
        "timezone": user.timezone,
        "avatar_url": user.avatar_url,
        "created_at": user.created_at,
    }


def profile_out(profile, user: User) -> dict:
    data = {
        "user_id": user.id,
        "display_name": user.display_name,
        "email": user.email,
        "headline": None,
        "bio": None,
        "home_city": None,
        "travel_pace": "balanced",
        "budget_level": "moderate",
        "budget_limit": None,
        "interests": [],
        "accessibility_needs": [],
        "dietary": [],
        "languages": [],
        "public_profile": False,
        "allow_discovery": False,
        "location_sharing": False,
    }
    if profile:
        data.update(
            {
                "headline": profile.headline,
                "bio": profile.bio,
                "home_city": profile.home_city,
                "travel_pace": profile.travel_pace,
                "budget_level": profile.budget_level,
                "budget_limit": profile.budget_limit,
                "interests": profile.interests or [],
                "accessibility_needs": profile.accessibility_needs or [],
                "dietary": profile.dietary or [],
                "languages": profile.languages or [],
                "public_profile": profile.public_profile,
                "allow_discovery": profile.allow_discovery,
                "location_sharing": profile.location_sharing,
            }
        )
    return data


def destination_out(destination: Destination) -> dict:
    return {
        "id": destination.id,
        "slug": destination.slug,
        "name": destination.name,
        "country": destination.country,
        "region": destination.region,
        "description": destination.description,
        "lat": destination.lat,
        "lon": destination.lon,
        "hero_image": destination.hero_image,
        "tags": destination.tags or [],
        "best_months": destination.best_months or [],
        "source_type": destination.source_type,
        "source_name": destination.source_name,
    }


def place_out(place: Place | None) -> dict | None:
    if not place:
        return None
    return {
        "id": place.id,
        "name": place.name,
        "category": place.category,
        "description": place.description,
        "lat": place.lat,
        "lon": place.lon,
        "address": place.address,
        "image_url": place.image_url,
        "fragile": place.fragile,
        "respect_note": place.respect_note,
        "source_type": place.source_type,
        "source_name": place.source_name,
        "last_verified_at": place.last_verified_at,
    }


def activity_out(
    activity: Activity, place: Place | None = None, destination: Destination | None = None
) -> dict:
    return {
        "id": activity.id,
        "place_id": activity.place_id,
        "destination_id": activity.destination_id,
        "name": activity.name,
        "description": activity.description,
        "tags": activity.tags or [],
        "price_estimate": activity.price_estimate,
        "currency": activity.currency,
        "duration_minutes": activity.duration_minutes,
        "effort": activity.effort,
        "indoor": activity.indoor,
        "wheelchair_accessible": activity.wheelchair_accessible,
        "iconic": activity.iconic,
        "popularity": activity.popularity,
        "fragile": activity.fragile,
        "opening_hours": activity.opening_hours or {},
        "access_chain": activity.access_chain or {},
        "image_url": activity.image_url,
        "source_type": activity.source_type,
        "last_verified_at": activity.last_verified_at,
        "place": place_out(place),
        "destination": destination_out(destination) if destination else None,
    }


def trip_out(db: Session, trip: Trip, member: TripMember | None = None) -> dict:
    member_count = (
        db.query(TripMember)
        .filter(TripMember.trip_id == trip.id, TripMember.status == "active")
        .count()
    )
    return {
        "id": trip.id,
        "name": trip.name,
        "description": trip.description,
        "destination_id": trip.destination_id,
        "destination_name": trip.destination_name,
        "start_date": trip.start_date,
        "end_date": trip.end_date,
        "group_size": trip.group_size,
        "budget_total": trip.budget_total,
        "currency": trip.currency,
        "base_lat": trip.base_lat,
        "base_lon": trip.base_lon,
        "status": trip.status,
        "privacy": trip.privacy,
        "trip_type": getattr(trip, "trip_type", "group") or "group",
        "created_by": trip.created_by,
        "member_count": member_count,
        "my_role": member.role if member else None,
        "created_at": trip.created_at,
    }


def member_out(db: Session, member: TripMember, viewer_id: str | None = None) -> dict:
    user = db.get(User, member.user_id) if member.user_id else None
    is_self = member.user_id == viewer_id
    data = {
        "id": member.id,
        "user": user_public(user),
        "display_name": user.display_name if user else (member.display_name or "Guest"),
        "role": member.role,
        "scope": member.scope or "full",
        "status": member.status,
        "joined_at": member.joined_at,
        "is_self": is_self,
    }
    # Budget limits and accessibility needs are private by default. They are
    # only surfaced back to their owner (F04/F32 privacy rule).
    if is_self:
        data["budget_limit"] = member.budget_limit
        data["accessibility_needs"] = member.accessibility_needs or []
    return data


def invitation_out(invitation: TripInvitation, trip: Trip | None = None) -> dict:
    return {
        "id": invitation.id,
        "token": invitation.token,
        "email": invitation.email,
        "role": invitation.role,
        "scope": invitation.scope,
        "expires_at": invitation.expires_at,
        "accepted_at": invitation.accepted_at,
        "created_at": invitation.created_at,
        "trip": {"id": trip.id, "name": trip.name} if trip else None,
    }


def item_out(item: ItineraryItem, activity: Activity | None = None) -> dict:
    return {
        "id": item.id,
        "day": item.day,
        "start_time": item.start_time,
        "end_time": item.end_time,
        "title": item.title,
        "activity_id": item.activity_id,
        "place_id": item.place_id,
        "notes": item.notes,
        "cost_estimate": item.cost_estimate,
        "status": item.status,
        "is_protected": item.is_protected,
        "sort_order": item.sort_order,
        "created_by": item.created_by,
        "created_at": item.created_at,
        "activity": activity_out(activity) if activity else None,
    }


def proposal_out(
    db: Session,
    proposal: ItineraryProposal,
    viewer_id: str | None = None,
) -> dict:
    votes = db.query(Vote).filter(Vote.proposal_id == proposal.id).all()
    counts = {"yes": 0, "no": 0, "abstain": 0}
    my_vote = None
    comments: list[dict] = []
    user_cache: dict[str, User | None] = {}
    for vote in votes:
        counts[vote.value] = counts.get(vote.value, 0) + 1
        if vote.user_id not in user_cache:
            user_cache[vote.user_id] = db.get(User, vote.user_id)
        author = user_cache[vote.user_id]
        if vote.comment:
            comments.append(
                {
                    "id": vote.id,
                    "user": user_public(author),
                    "comment": vote.comment,
                    "value": vote.value,
                    "created_at": vote.created_at,
                }
            )
        if viewer_id and vote.user_id == viewer_id:
            my_vote = vote.value
    author = db.get(User, proposal.created_by)
    return {
        "id": proposal.id,
        "kind": proposal.kind,
        "title": proposal.title,
        "summary": proposal.summary,
        "payload": proposal.payload or {},
        "status": proposal.status,
        "target_day": proposal.target_day,
        "created_by": proposal.created_by,
        "author": user_public(author),
        "created_at": proposal.created_at,
        "decided_at": proposal.decided_at,
        "votes": counts,
        "vote_count": len(votes),
        "my_vote": my_vote,
        "comments": comments,
    }


def version_out(version: ItineraryVersion) -> dict:
    return {
        "id": version.id,
        "version": version.version,
        "snapshot": version.snapshot or [],
        "note": version.note,
        "created_at": version.created_at,
        "created_by": version.created_by,
    }


def pulse_out(pulse: TripPulse, viewer_id: str | None = None) -> dict:
    own = pulse.user_id == viewer_id
    data = {
        "id": pulse.id,
        "user_id": pulse.user_id,
        "pulse_date": pulse.pulse_date,
        "energy": pulse.energy,
        "interests": pulse.interests or [],
        "available_minutes": pulse.available_minutes,
        "radius_km": pulse.radius_km,
        "activity_prefs": pulse.activity_prefs or [],
        "created_at": pulse.created_at,
        "is_self": own,
    }
    # Budget comfort and free-text notes stay private; the engine can still use
    # them for filtering without exposing them to the group.
    if own:
        data["budget_comfort"] = pulse.budget_comfort
        data["note"] = pulse.note
    return data


def respect_out(activity: Activity | None, place: Place | None) -> dict:
    fragile = bool((activity and activity.fragile) or (place and place.fragile))
    if not fragile:
        return {"fragile": False, "confidence": "verified", "status": "not_applicable", "guidance": None}
    if place and place.respect_note:
        return {
            "fragile": True,
            "confidence": "verified",
            "status": "guidance_recorded",
            "guidance": place.respect_note,
        }
    return {
        "fragile": True,
        "confidence": "unverified",
        "status": "no_guidance_recorded",
        "guidance": None,
    }


def recommendation_out(
    rec: Recommendation,
    activity: Activity | None,
    place: Place | None = None,
    destination: Destination | None = None,
) -> dict:
    return {
        "id": rec.id,
        "activity_id": rec.activity_id,
        "rank": rec.rank,
        "score": rec.score,
        "average_fit": rec.average_fit,
        "minimum_fit": rec.minimum_fit,
        "fairness_spread": rec.fairness_spread,
        "novelty": rec.novelty,
        "penalties": rec.penalties or {},
        "explanation": rec.explanation or {},
        "status": rec.status,
        "activity": activity_out(activity, place, destination) if activity else None,
        "respect": respect_out(activity, place),
    }


def expense_out(
    db: Session, expense: Expense, participant_rows: list[ExpenseParticipant] | None = None
) -> dict:
    rows = participant_rows or []
    participants = []
    user_cache: dict[str, User | None] = {}
    for row in rows:
        user = None
        if row.user_id:
            if row.user_id not in user_cache:
                user_cache[row.user_id] = db.get(User, row.user_id)
            user = user_cache[row.user_id]
        participants.append(
            {
                "id": row.id,
                "user": user_public(user),
                "guest_name": row.guest_name,
                "weight": row.weight,
                "share_amount": row.share_amount,
            }
        )
    payer = db.get(User, expense.paid_by)
    return {
        "id": expense.id,
        "title": expense.title,
        "category": expense.category,
        "amount": expense.amount,
        "currency": expense.currency,
        "paid_by": expense.paid_by,
        "payer": user_public(payer),
        "incurred_on": expense.incurred_on,
        "notes": expense.notes,
        "participants": participants,
        "created_at": expense.created_at,
    }


def memory_out(memory: TripMemory, author: User | None) -> dict:
    return {
        "id": memory.id,
        "user_id": memory.user_id,
        "author": user_public(author),
        "kind": memory.kind,
        "text_content": memory.text_content,
        "media_url": sign_media_url(memory.media_url),
        "media_type": memory.media_type,
        "caption": memory.caption,
        "captured_at": memory.captured_at,
        "lat": memory.lat,
        "lon": memory.lon,
        "visibility": memory.visibility,
        "ai_generated": memory.ai_generated,
        "approved": memory.approved,
        "created_at": memory.created_at,
    }


def report_out(db: Session, report: PlaceReport, freshness: float | None = None) -> dict:
    reporter = db.get(User, report.reporter_id) if report.reporter_id else None
    return {
        "id": report.id,
        "activity_id": report.activity_id,
        "place_id": report.place_id,
        "category": report.category,
        "value": report.value or {},
        "note": report.note,
        "observed_at": report.observed_at,
        "source_type": report.source_type,
        "confidence": report.confidence,
        "verified": report.verified,
        "verification": (
            "official_verified"
            if report.verified and report.source_type == "official"
            else "moderator_verified"
            if report.verified
            else "unverified"
        ),
        "helpful_count": report.helpful_count,
        "reporter": user_public(reporter),
        "freshness": freshness,
        "created_at": report.created_at,
    }


def iso(value: datetime | None) -> str | None:
    return value.isoformat() if value else None
