from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.deps import get_current_user, get_db
from app.models import (
    Activity,
    ActivityFeedback,
    AuthSession,
    CircleMember,
    CirclePost,
    CompanionLink,
    ConnectionRequest,
    ConsentRecord,
    Expense,
    ItineraryApproval,
    ItineraryAttendance,
    JourneyDNA,
    LocalContributor,
    MemoryPermission,
    Notification,
    OfflineSyncQueue,
    PlaceReport,
    Profile,
    RecommendationFeedback,
    SavedInspiration,
    Shadowplan,
    TravellerMatch,
    Trip,
    TripInvitation,
    TripMember,
    TripMemory,
    TripPulse,
    User,
    UserBlock,
    UserMission,
    Vote,
)
from app.models.models import utcnow
from app.schemas.schemas import (
    ConsentUpdate,
    DNAUpdate,
    ProfileUpdate,
    UserSettingsUpdate,
)
from app.services.common import DNA_DIMENSIONS, audit, clamp, default_dna, normalize_tag
from app.services.media_store import MediaValidationError, get_media_store, parse_media_url
from app.services.serializers import profile_out, user_out

router = APIRouter(prefix="/api/users", tags=["users"])


CONSENT_KINDS = {"terms", "personalization", "analytics", "location", "marketing"}

DNA_SENTIMENT = {
    "loved": 2.0,
    "would_return": 1.5,
    "okay": 0.0,
    "not_for_me": -1.5,
    "too_expensive": -1.0,
    "too_far": -0.5,
}


def _get_dna(db: Session, user_id: str) -> JourneyDNA:
    row = db.query(JourneyDNA).filter(JourneyDNA.user_id == user_id).first()
    if not row:
        row = JourneyDNA(user_id=user_id, scores=default_dna(), source="explicit")
        db.add(row)
        db.flush()
    return row


def _consent_map(db: Session, user_id: str) -> dict:
    rows = (
        db.query(ConsentRecord)
        .filter(ConsentRecord.user_id == user_id)
        .order_by(ConsentRecord.created_at.desc())
        .all()
    )
    latest = {}
    for row in rows:
        latest.setdefault(row.kind, row)
    return {
        kind: {
            "granted": record.granted,
            "policy_version": record.policy_version,
            "updated_at": record.created_at,
        }
        for kind, record in latest.items()
    }


@router.get("/me")
def get_me(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    profile = db.query(Profile).filter(Profile.user_id == user.id).first()
    dna = _get_dna(db, user.id)
    return {
        "user": user_out(user),
        "profile": profile_out(profile, user),
        "dna": {
            "scores": dna.scores,
            "source": dna.source,
            "updated_at": dna.updated_at,
            "dimensions": DNA_DIMENSIONS,
        },
        "consents": _consent_map(db, user.id),
        "policy_version": settings.policy_version,
    }


@router.patch("/me/profile")
def update_profile(
    payload: ProfileUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    profile = db.query(Profile).filter(Profile.user_id == user.id).first()
    if not profile:
        profile = Profile(user_id=user.id)
        db.add(profile)
        db.flush()
    data = payload.model_dump(exclude_unset=True)
    for field, value in data.items():
        setattr(profile, field, value)
    if "interests" in data and data["interests"] is not None:
        dna = _get_dna(db, user.id)
        scores = dict(dna.scores or default_dna())
        for interest in data["interests"]:
            key = normalize_tag(interest)
            if key in DNA_DIMENSIONS:
                scores[key] = max(float(scores.get(key, 5)), 7.0)
        dna.scores = scores
        dna.source = "profile+explicit"
    audit(db, action="profile.update", entity_type="profile", entity_id=profile.id, user_id=user.id)
    db.commit()
    return profile_out(profile, user)


@router.get("/me/dna")
def get_dna(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    dna = _get_dna(db, user.id)
    return {
        "scores": dna.scores,
        "source": dna.source,
        "updated_at": dna.updated_at,
        "dimensions": DNA_DIMENSIONS,
        "note": "Journey DNA is editable and never a permanent personality label.",
    }


@router.put("/me/dna")
def update_dna(
    payload: DNAUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    unknown = set(payload.scores) - set(DNA_DIMENSIONS)
    if unknown:
        raise HTTPException(status_code=422, detail=f"Unknown DNA dimensions: {', '.join(sorted(unknown))}")
    dna = _get_dna(db, user.id)
    scores = dict(dna.scores or default_dna())
    for dimension, value in payload.scores.items():
        scores[dimension] = clamp(float(value), 0, 10)
    dna.scores = scores
    dna.source = "explicit"
    audit(db, action="dna.update", entity_type="journey_dna", entity_id=dna.id, user_id=user.id)
    db.commit()
    return {"scores": dna.scores, "source": dna.source, "updated_at": dna.updated_at}


@router.get("/me/consents")
def get_consents(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return {
        "consents": _consent_map(db, user.id),
        "policy_version": settings.policy_version,
        "kinds": sorted(CONSENT_KINDS),
    }


@router.put("/me/consents")
def update_consents(
    payload: ConsentUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    unknown = set(payload.consents) - CONSENT_KINDS
    if unknown:
        raise HTTPException(status_code=422, detail=f"Unknown consent types: {', '.join(sorted(unknown))}")
    for kind, granted in payload.consents.items():
        db.add(
            ConsentRecord(
                user_id=user.id,
                kind=kind,
                granted=bool(granted),
                policy_version=settings.policy_version,
            )
        )
    audit(
        db,
        action="consent.update",
        entity_type="consent",
        user_id=user.id,
        detail=payload.consents,
    )
    db.commit()
    return {"consents": _consent_map(db, user.id), "policy_version": settings.policy_version}


@router.patch("/me/settings")
def update_settings(
    payload: UserSettingsUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    data = payload.model_dump(exclude_unset=True)
    for field, value in data.items():
        setattr(user, field, value)
    audit(db, action="settings.update", entity_type="user", entity_id=user.id, user_id=user.id)
    db.commit()
    return user_out(user)


@router.get("/me/notifications")
def notifications(
    limit: int = Query(default=30, ge=1, le=100),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from app.models import Notification

    rows = (
        db.query(Notification)
        .filter(Notification.user_id == user.id)
        .order_by(Notification.created_at.desc())
        .limit(limit)
        .all()
    )
    unread = (
        db.query(Notification)
        .filter(Notification.user_id == user.id, Notification.read_at.is_(None))
        .count()
    )
    return {
        "unread": unread,
        "items": [
            {
                "id": row.id,
                "trip_id": row.trip_id,
                "kind": row.kind,
                "title": row.title,
                "body": row.body,
                "link": row.link,
                "read": row.read_at is not None,
                "created_at": row.created_at,
            }
            for row in rows
        ],
    }


@router.post("/me/notifications/{notification_id}/read")
def read_notification(
    notification_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from app.models import Notification

    row = db.get(Notification, notification_id)
    if not row or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="Notification not found")
    if not row.read_at:
        row.read_at = utcnow()
        db.commit()
    return {"ok": True}


@router.post("/me/notifications/read-all")
def read_all_notifications(
    user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    from app.models import Notification

    db.query(Notification).filter(
        Notification.user_id == user.id, Notification.read_at.is_(None)
    ).update({Notification.read_at: utcnow()})
    db.commit()
    return {"ok": True}


@router.post("/me/blocks/{blocked_id}")
def block_user(
    blocked_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if blocked_id == user.id:
        raise HTTPException(status_code=400, detail="You cannot block yourself")
    if not db.get(User, blocked_id):
        raise HTTPException(status_code=404, detail="User not found")
    existing = (
        db.query(UserBlock)
        .filter(UserBlock.blocker_id == user.id, UserBlock.blocked_id == blocked_id)
        .first()
    )
    if not existing:
        db.add(UserBlock(blocker_id=user.id, blocked_id=blocked_id))
        db.commit()
    return {"ok": True}


@router.delete("/me/blocks/{blocked_id}")
def unblock_user(
    blocked_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    db.query(UserBlock).filter(
        UserBlock.blocker_id == user.id, UserBlock.blocked_id == blocked_id
    ).delete()
    db.commit()
    return {"ok": True}


@router.get("/me/blocks")
def list_blocks(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.query(UserBlock).filter(UserBlock.blocker_id == user.id).all()
    blocked = {row.blocked_id for row in rows}
    users = db.query(User).filter(User.id.in_(blocked)).all() if blocked else []
    return {
        "items": [
            {"user": {"id": person.id, "display_name": person.display_name}, "created_at": row.created_at}
            for row, person in ((row, db.get(User, row.blocked_id)) for row in rows)
            if person
        ]
    }


@router.get("/me/export")
def export_data(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    profile = db.query(Profile).filter(Profile.user_id == user.id).first()
    dna = _get_dna(db, user.id)
    memberships = (
        db.query(TripMember)
        .filter(TripMember.user_id == user.id)
        .all()
    )
    trip_ids = [membership.trip_id for membership in memberships]
    trips = (
        db.query(Trip).filter(Trip.id.in_(trip_ids)).all() if trip_ids else []
    )
    memories = (
        db.query(TripMemory).filter(TripMemory.user_id == user.id).all()
    )
    expenses = db.query(Expense).filter(Expense.paid_by == user.id).all()
    feedback = db.query(ActivityFeedback).filter(ActivityFeedback.user_id == user.id).all()
    return {
        "exported_at": utcnow().isoformat(),
        "user": user_out(user),
        "profile": profile_out(profile, user),
        "journey_dna": {"scores": dna.scores, "source": dna.source},
        "consents": _consent_map(db, user.id),
        "trips": [
            {
                "id": trip.id,
                "name": trip.name,
                "destination": trip.destination_name,
                "start_date": trip.start_date,
                "end_date": trip.end_date,
                "role": next(
                    (m.role for m in memberships if m.trip_id == trip.id), None
                ),
            }
            for trip in trips
        ],
        "memories": [
            {
                "id": memory.id,
                "trip_id": memory.trip_id,
                "kind": memory.kind,
                "caption": memory.caption,
                "text": memory.text_content,
                "captured_at": memory.captured_at,
                "visibility": memory.visibility,
            }
            for memory in memories
        ],
        "expenses_paid": [
            {"id": expense.id, "title": expense.title, "amount": expense.amount}
            for expense in expenses
        ],
        "activity_feedback": [
            {
                "activity_id": row.activity_id,
                "sentiment": row.sentiment,
                "consented": row.consented,
                "created_at": row.created_at,
            }
            for row in feedback
        ],
        "disclosure": "This export contains your account data. Private members' information is excluded.",
    }


@router.delete("/me")
def delete_account(
    user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    if user.is_admin:
        raise HTTPException(
            status_code=400,
            detail="Administrator accounts must be transferred before deletion.",
        )
    now = utcnow()
    profile = db.query(Profile).filter(Profile.user_id == user.id).first()
    if profile:
        profile.headline = None
        profile.bio = None
        profile.home_city = None
        profile.interests = []
        profile.accessibility_needs = []
        profile.dietary = []
        profile.languages = []
        profile.public_profile = False
        profile.allow_discovery = False
        profile.location_sharing = False
        profile.budget_limit = None

    # Personal learning, preference and private planning data is erased.
    erased = (
        JourneyDNA,
        ActivityFeedback,
        RecommendationFeedback,
        Vote,
        ItineraryApproval,
        ItineraryAttendance,
        TripPulse,
        MemoryPermission,
        SavedInspiration,
        OfflineSyncQueue,
        UserMission,
        CircleMember,
        CirclePost,
        LocalContributor,
        PlaceReport,
    )
    for model in erased:
        query = db.query(model)
        column = (
            PlaceReport.reporter_id if model is PlaceReport else getattr(model, "user_id")
        )
        query.filter(column == user.id).delete(synchronize_session=False)
    db.query(Shadowplan).filter(Shadowplan.created_by == user.id).delete(
        synchronize_session=False
    )
    db.query(ConnectionRequest).filter(
        (ConnectionRequest.from_user_id == user.id)
        | (ConnectionRequest.to_user_id == user.id)
    ).delete(synchronize_session=False)
    db.query(TravellerMatch).filter(
        (TravellerMatch.user_a_id == user.id) | (TravellerMatch.user_b_id == user.id)
    ).delete(synchronize_session=False)
    # Pending invitations and one-use links must stop working immediately.
    db.query(TripInvitation).filter(
        TripInvitation.created_by == user.id, TripInvitation.accepted_at.is_(None)
    ).delete(synchronize_session=False)
    db.query(CompanionLink).filter(
        CompanionLink.created_by == user.id, CompanionLink.revoked_at.is_(None)
    ).update({CompanionLink.revoked_at: now}, synchronize_session=False)

    # Shared memories lose their content, location and stored media files.
    media_store = get_media_store()
    for memory in db.query(TripMemory).filter(TripMemory.user_id == user.id).all():
        if memory.media_url:
            try:
                key = parse_media_url(memory.media_url)
            except MediaValidationError:
                key = None
            if key:
                media_store.delete(key.trip_id, key.filename)
        memory.text_content = None
        memory.caption = None
        memory.media_url = None
        memory.media_type = None
        memory.lat = None
        memory.lon = None
        memory.visibility = "private"
        memory.deleted_at = memory.deleted_at or now

    # Group history stays for balances and trip records, but without identity,
    # private budget limits or accessibility needs.
    for membership in (
        db.query(TripMember).filter(TripMember.user_id == user.id).all()
    ):
        membership.display_name = "Former traveller"
        membership.budget_limit = None
        membership.accessibility_needs = []
        membership.invited_by = None
        membership.status = "removed"

    db.query(Notification).filter(Notification.user_id == user.id).delete(
        synchronize_session=False
    )
    db.query(UserBlock).filter(
        (UserBlock.blocker_id == user.id) | (UserBlock.blocked_id == user.id)
    ).delete(synchronize_session=False)
    # Session rows hold refresh hashes, user agents and IP digests: remove them.
    db.query(AuthSession).filter(AuthSession.user_id == user.id).delete(
        synchronize_session=False
    )
    db.add(
        ConsentRecord(
            user_id=user.id,
            kind="terms",
            granted=False,
            policy_version=settings.policy_version,
        )
    )
    user.deleted_at = now
    user.is_active = False
    user.email = f"deleted+{user.id}@safar.invalid"
    user.display_name = "Former traveller"
    user.avatar_url = None
    user.password_hash = "deleted-account"
    user.quiet_mode = True
    audit(
        db,
        action="account.delete",
        entity_type="user",
        entity_id=user.id,
        user_id=user.id,
    )
    db.commit()
    return {
        "ok": True,
        "note": (
            "Account deleted. Personal preferences, memories, media, session "
            "data and pending links were removed; shared trip records are kept "
            "anonymised for other members."
        ),
    }


@router.get("/me/thread")
def journey_thread(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Carry favourites and traditions from previous trips (F47)."""
    today = date.today()
    memberships = db.query(TripMember).filter(TripMember.user_id == user.id).all()
    completed_ids = []
    for membership in memberships:
        trip = db.get(Trip, membership.trip_id)
        if trip and not trip.deleted_at and (
            trip.status == "completed" or trip.end_date < today
        ):
            completed_ids.append(trip.id)
    loved = (
        db.query(ActivityFeedback)
        .filter(
            ActivityFeedback.user_id == user.id,
            ActivityFeedback.sentiment.in_(["loved", "would_return"]),
            ActivityFeedback.consented.is_(True),
        )
        .order_by(ActivityFeedback.created_at.desc())
        .all()
    )
    activities = {}
    for row in loved:
        activity = db.get(Activity, row.activity_id)
        if not activity:
            continue
        key = activity.id
        entry = activities.setdefault(
            key,
            {
                "activity_id": key,
                "name": activity.name,
                "price_estimate": activity.price_estimate,
                "duration_minutes": activity.duration_minutes,
                "sentiments": [],
            },
        )
        entry["sentiments"].append(row.sentiment)
    return {
        "completed_trips": len(completed_ids),
        "traditions": sorted(
            activities.values(), key=lambda entry: len(entry["sentiments"]), reverse=True
        )[:10],
        "note": (
            "Only outcomes you consented to share are used. You can repeat, modify or avoid "
            "any of these in a new journey."
        ),
    }
