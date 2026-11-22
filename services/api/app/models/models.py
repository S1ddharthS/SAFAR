import uuid
from datetime import date, datetime, timezone

from sqlalchemy import (
    JSON,
    Boolean,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base


def new_id() -> str:
    return uuid.uuid4().hex


def utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=utcnow, onupdate=utcnow
    )


# --------------------------------------------------------------------------
# Identity, profile, consent, Journey DNA
# --------------------------------------------------------------------------


class User(Base, TimestampMixin):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    display_name: Mapped[str] = mapped_column(String(120))
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    locale: Mapped[str] = mapped_column(String(16), default="en")
    timezone: Mapped[str] = mapped_column(String(64), default="UTC")
    avatar_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    quiet_mode: Mapped[bool] = mapped_column(Boolean, default=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class Profile(Base):
    __tablename__ = "profiles"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True, index=True
    )
    headline: Mapped[str | None] = mapped_column(String(160), nullable=True)
    bio: Mapped[str | None] = mapped_column(Text, nullable=True)
    home_city: Mapped[str | None] = mapped_column(String(120), nullable=True)
    travel_pace: Mapped[str] = mapped_column(String(20), default="balanced")
    budget_level: Mapped[str] = mapped_column(String(20), default="moderate")
    budget_limit: Mapped[float | None] = mapped_column(Float, nullable=True)
    interests: Mapped[list] = mapped_column(JSON, default=list)
    accessibility_needs: Mapped[list] = mapped_column(JSON, default=list)
    dietary: Mapped[list] = mapped_column(JSON, default=list)
    languages: Mapped[list] = mapped_column(JSON, default=list)
    public_profile: Mapped[bool] = mapped_column(Boolean, default=False)
    allow_discovery: Mapped[bool] = mapped_column(Boolean, default=False)
    location_sharing: Mapped[bool] = mapped_column(Boolean, default=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=utcnow, onupdate=utcnow
    )


class ConsentRecord(Base):
    __tablename__ = "consent_records"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    kind: Mapped[str] = mapped_column(String(40))
    granted: Mapped[bool] = mapped_column(Boolean, default=False)
    policy_version: Mapped[str] = mapped_column(String(20))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class JourneyDNA(Base):
    __tablename__ = "journey_dna"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True, index=True
    )
    scores: Mapped[dict] = mapped_column(JSON, default=dict)
    source: Mapped[str] = mapped_column(String(40), default="explicit")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=utcnow, onupdate=utcnow
    )


class AuthSession(Base):
    """Server-side session backing refresh-token rotation and revocation.

    Only a SHA-256 hash of the refresh secret is stored, so a database leak
    does not hand out usable refresh tokens. IP addresses are stored as an
    HMAC digest (never raw) purely for session forensics.
    """

    __tablename__ = "auth_sessions"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    refresh_hash: Mapped[str] = mapped_column(String(64))
    user_agent: Mapped[str | None] = mapped_column(String(200), nullable=True)
    ip_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    last_used_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    expires_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    revoked_reason: Mapped[str | None] = mapped_column(String(60), nullable=True)


# --------------------------------------------------------------------------
# Discovery catalog
# --------------------------------------------------------------------------


class Destination(Base, TimestampMixin):
    __tablename__ = "destinations"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    slug: Mapped[str] = mapped_column(String(120), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(120), index=True)
    country: Mapped[str] = mapped_column(String(120))
    region: Mapped[str | None] = mapped_column(String(120), nullable=True)
    description: Mapped[str] = mapped_column(Text)
    lat: Mapped[float] = mapped_column(Float)
    lon: Mapped[float] = mapped_column(Float)
    hero_image: Mapped[str | None] = mapped_column(String(500), nullable=True)
    tags: Mapped[list] = mapped_column(JSON, default=list)
    best_months: Mapped[list] = mapped_column(JSON, default=list)
    source_type: Mapped[str] = mapped_column(String(30), default="seed_catalog")
    source_name: Mapped[str] = mapped_column(String(120), default="SAFAR seed catalog")


class Place(Base, TimestampMixin):
    __tablename__ = "places"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    destination_id: Mapped[str] = mapped_column(
        ForeignKey("destinations.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(160), index=True)
    category: Mapped[str] = mapped_column(String(60), default="attraction")
    description: Mapped[str] = mapped_column(Text)
    lat: Mapped[float] = mapped_column(Float)
    lon: Mapped[float] = mapped_column(Float)
    address: Mapped[str | None] = mapped_column(String(240), nullable=True)
    image_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    fragile: Mapped[bool] = mapped_column(Boolean, default=False)
    respect_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    source_type: Mapped[str] = mapped_column(String(30), default="seed_catalog")
    source_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    last_verified_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class Activity(Base, TimestampMixin):
    __tablename__ = "activities"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    place_id: Mapped[str] = mapped_column(
        ForeignKey("places.id", ondelete="CASCADE"), index=True
    )
    destination_id: Mapped[str] = mapped_column(
        ForeignKey("destinations.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(160), index=True)
    description: Mapped[str] = mapped_column(Text)
    tags: Mapped[list] = mapped_column(JSON, default=list)
    price_estimate: Mapped[float] = mapped_column(Float, default=0.0)
    currency: Mapped[str] = mapped_column(String(8), default="EUR")
    duration_minutes: Mapped[int] = mapped_column(Integer, default=90)
    effort: Mapped[int] = mapped_column(Integer, default=2)
    indoor: Mapped[bool] = mapped_column(Boolean, default=False)
    wheelchair_accessible: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    iconic: Mapped[bool] = mapped_column(Boolean, default=False)
    popularity: Mapped[float] = mapped_column(Float, default=0.5)
    fragile: Mapped[bool] = mapped_column(Boolean, default=False)
    opening_hours: Mapped[dict] = mapped_column(JSON, default=dict)
    access_chain: Mapped[dict] = mapped_column(JSON, default=dict)
    source_type: Mapped[str] = mapped_column(String(30), default="seed_catalog")
    last_verified_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    image_url: Mapped[str | None] = mapped_column(String(500), nullable=True)


class PlaceSource(Base):
    __tablename__ = "place_sources"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    entity_type: Mapped[str] = mapped_column(String(30))
    entity_id: Mapped[str] = mapped_column(String(32), index=True)
    name: Mapped[str] = mapped_column(String(160))
    url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    licence: Mapped[str | None] = mapped_column(String(120), nullable=True)
    is_official: Mapped[bool] = mapped_column(Boolean, default=False)
    retrieved_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class PlaceReport(Base):
    __tablename__ = "place_reports"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    activity_id: Mapped[str | None] = mapped_column(
        ForeignKey("activities.id", ondelete="CASCADE"), nullable=True, index=True
    )
    place_id: Mapped[str | None] = mapped_column(
        ForeignKey("places.id", ondelete="CASCADE"), nullable=True, index=True
    )
    trip_id: Mapped[str | None] = mapped_column(
        ForeignKey("trips.id", ondelete="SET NULL"), nullable=True, index=True
    )
    category: Mapped[str] = mapped_column(String(40), index=True)
    value: Mapped[dict] = mapped_column(JSON, default=dict)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    observed_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    source_type: Mapped[str] = mapped_column(String(20), default="community")
    confidence: Mapped[float] = mapped_column(Float, default=0.6)
    verified: Mapped[bool] = mapped_column(Boolean, default=False)
    reporter_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    helpful_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


# --------------------------------------------------------------------------
# Trips, membership, invitations
# --------------------------------------------------------------------------


class Trip(Base, TimestampMixin):
    __tablename__ = "trips"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    name: Mapped[str] = mapped_column(String(160))
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    destination_id: Mapped[str | None] = mapped_column(
        ForeignKey("destinations.id", ondelete="SET NULL"), nullable=True, index=True
    )
    destination_name: Mapped[str] = mapped_column(String(160), default="")
    start_date: Mapped[date] = mapped_column(Date)
    end_date: Mapped[date] = mapped_column(Date)
    group_size: Mapped[int] = mapped_column(Integer, default=4)
    budget_total: Mapped[float | None] = mapped_column(Float, nullable=True)
    currency: Mapped[str] = mapped_column(String(8), default="EUR")
    base_lat: Mapped[float] = mapped_column(Float, default=0.0)
    base_lon: Mapped[float] = mapped_column(Float, default=0.0)
    status: Mapped[str] = mapped_column(String(20), default="planning")
    privacy: Mapped[str] = mapped_column(String(20), default="private")
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class TripMember(Base):
    __tablename__ = "trip_members"
    __table_args__ = (
        UniqueConstraint("trip_id", "user_id", name="uq_trip_member"),
        Index("ix_trip_members_user_status", "user_id", "status"),
    )

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True
    )
    display_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    role: Mapped[str] = mapped_column(String(20), default="member")
    scope: Mapped[str] = mapped_column(String(20), default="full")
    status: Mapped[str] = mapped_column(String(20), default="active")
    budget_limit: Mapped[float | None] = mapped_column(Float, nullable=True)
    accessibility_needs: Mapped[list] = mapped_column(JSON, default=list)
    invited_by: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    joined_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class TripInvitation(Base):
    __tablename__ = "trip_invitations"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), index=True
    )
    token: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    email: Mapped[str | None] = mapped_column(String(320), nullable=True)
    role: Mapped[str] = mapped_column(String(20), default="member")
    scope: Mapped[str] = mapped_column(String(20), default="full")
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    accepted_by: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


# --------------------------------------------------------------------------
# Itinerary, proposals, votes, approvals
# --------------------------------------------------------------------------


class CompanionLink(Base):
    """A signed, single-purpose, expiring link for one vote or check-in (F26).

    The token itself is never stored: it is an HMAC over the link id, expiry,
    purpose and target. Responses are anonymous by design and are recorded
    separately so no traveller identity is attached to them.
    """

    __tablename__ = "companion_links"
    __table_args__ = (Index("ix_companion_links_trip", "trip_id", "created_at"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), index=True
    )
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    purpose: Mapped[str] = mapped_column(String(20))
    target_id: Mapped[str] = mapped_column(String(64))
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    max_uses: Mapped[int] = mapped_column(Integer, default=1)
    used_count: Mapped[int] = mapped_column(Integer, default=0)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class CompanionResponse(Base):
    __tablename__ = "companion_responses"
    __table_args__ = (Index("ix_companion_responses_link", "link_id", "created_at"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    link_id: Mapped[str] = mapped_column(
        ForeignKey("companion_links.id", ondelete="CASCADE"), index=True
    )
    value: Mapped[str] = mapped_column(String(20))
    comment: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Itinerary(Base):
    __tablename__ = "itineraries"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), unique=True, index=True
    )
    confirmed_version: Mapped[int] = mapped_column(Integer, default=1)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class ItineraryItem(Base):
    __tablename__ = "itinerary_items"
    __table_args__ = (Index("ix_itinerary_day_order", "trip_id", "day", "sort_order"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    itinerary_id: Mapped[str] = mapped_column(
        ForeignKey("itineraries.id", ondelete="CASCADE"), index=True
    )
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), index=True
    )
    day: Mapped[date] = mapped_column(Date, index=True)
    start_time: Mapped[str] = mapped_column(String(5), default="09:00")
    end_time: Mapped[str | None] = mapped_column(String(5), nullable=True)
    title: Mapped[str] = mapped_column(String(200))
    activity_id: Mapped[str | None] = mapped_column(
        ForeignKey("activities.id", ondelete="SET NULL"), nullable=True
    )
    place_id: Mapped[str | None] = mapped_column(
        ForeignKey("places.id", ondelete="SET NULL"), nullable=True
    )
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    cost_estimate: Mapped[float] = mapped_column(Float, default=0.0)
    status: Mapped[str] = mapped_column(String(20), default="confirmed")
    is_protected: Mapped[bool] = mapped_column(Boolean, default=False)
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=utcnow, onupdate=utcnow
    )


class ItineraryVersion(Base):
    __tablename__ = "itinerary_versions"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    itinerary_id: Mapped[str] = mapped_column(
        ForeignKey("itineraries.id", ondelete="CASCADE"), index=True
    )
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), index=True
    )
    version: Mapped[int] = mapped_column(Integer)
    snapshot: Mapped[list] = mapped_column(JSON, default=list)
    note: Mapped[str | None] = mapped_column(String(240), nullable=True)
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class ItineraryProposal(Base):
    __tablename__ = "itinerary_proposals"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), index=True
    )
    kind: Mapped[str] = mapped_column(String(30), default="add_activity")
    title: Mapped[str] = mapped_column(String(200))
    summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    payload: Mapped[dict] = mapped_column(JSON, default=dict)
    status: Mapped[str] = mapped_column(String(20), default="open", index=True)
    target_day: Mapped[date | None] = mapped_column(Date, nullable=True)
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    decided_by: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    decided_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class ItineraryApproval(Base):
    __tablename__ = "itinerary_approvals"
    __table_args__ = (
        UniqueConstraint("proposal_id", "user_id", name="uq_proposal_approval"),
    )

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    proposal_id: Mapped[str] = mapped_column(
        ForeignKey("itinerary_proposals.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    approval: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Vote(Base):
    __tablename__ = "activity_votes"
    __table_args__ = (UniqueConstraint("proposal_id", "user_id", name="uq_vote"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    proposal_id: Mapped[str] = mapped_column(
        ForeignKey("itinerary_proposals.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    value: Mapped[str] = mapped_column(String(10), default="yes")
    comment: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class ItineraryAttendance(Base):
    __tablename__ = "itinerary_attendance"
    __table_args__ = (UniqueConstraint("item_id", "user_id", name="uq_attendance"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    item_id: Mapped[str] = mapped_column(
        ForeignKey("itinerary_items.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    status: Mapped[str] = mapped_column(String(20), default="in")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=utcnow, onupdate=utcnow
    )


# --------------------------------------------------------------------------
# Trip Pulse and intelligence outputs
# --------------------------------------------------------------------------


class TripPulse(Base):
    __tablename__ = "trip_pulse"
    __table_args__ = (
        UniqueConstraint("trip_id", "user_id", "pulse_date", name="uq_daily_pulse"),
    )

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    pulse_date: Mapped[date] = mapped_column(Date, index=True)
    energy: Mapped[int] = mapped_column(Integer, default=3)
    interests: Mapped[list] = mapped_column(JSON, default=list)
    available_minutes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    budget_comfort: Mapped[int] = mapped_column(Integer, default=3)
    radius_km: Mapped[float | None] = mapped_column(Float, nullable=True)
    activity_prefs: Mapped[list] = mapped_column(JSON, default=list)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class RecommendationBatch(Base):
    __tablename__ = "recommendation_batches"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), index=True
    )
    mode: Mapped[str] = mapped_column(String(30))
    for_date: Mapped[date] = mapped_column(Date, default=date.today)
    model_version: Mapped[str] = mapped_column(String(40), default="safar-engine-1.0")
    meta: Mapped[dict] = mapped_column(JSON, default=dict)
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Recommendation(Base):
    __tablename__ = "recommendations"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    batch_id: Mapped[str] = mapped_column(
        ForeignKey("recommendation_batches.id", ondelete="CASCADE"), index=True
    )
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), index=True
    )
    activity_id: Mapped[str] = mapped_column(ForeignKey("activities.id"))
    rank: Mapped[int] = mapped_column(Integer, default=1)
    score: Mapped[float] = mapped_column(Float, default=0)
    average_fit: Mapped[float] = mapped_column(Float, default=0)
    minimum_fit: Mapped[float] = mapped_column(Float, default=0)
    fairness_spread: Mapped[float] = mapped_column(Float, default=0)
    novelty: Mapped[float] = mapped_column(Float, default=0)
    penalties: Mapped[dict] = mapped_column(JSON, default=dict)
    explanation: Mapped[dict] = mapped_column(JSON, default=dict)
    status: Mapped[str] = mapped_column(String(20), default="suggested")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class RecommendationFeedback(Base):
    __tablename__ = "recommendation_feedback"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    recommendation_id: Mapped[str] = mapped_column(
        ForeignKey("recommendations.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    sentiment: Mapped[str] = mapped_column(String(30))
    consented: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


# --------------------------------------------------------------------------
# Journey agreements, resilience, capsules
# --------------------------------------------------------------------------


class JourneyPact(Base, TimestampMixin):
    __tablename__ = "journey_pacts"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), unique=True, index=True
    )
    must_do: Mapped[list] = mapped_column(JSON, default=list)
    flexible: Mapped[list] = mapped_column(JSON, default=list)
    individual_limits: Mapped[dict] = mapped_column(JSON, default=dict)
    confirmed_times: Mapped[dict] = mapped_column(JSON, default=dict)
    exceptions: Mapped[list] = mapped_column(JSON, default=list)
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))


class Shadowplan(Base):
    __tablename__ = "shadowplans"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), index=True
    )
    itinerary_item_id: Mapped[str] = mapped_column(
        ForeignKey("itinerary_items.id", ondelete="CASCADE"), index=True
    )
    backup_activity_id: Mapped[str] = mapped_column(ForeignKey("activities.id"))
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    readiness: Mapped[dict] = mapped_column(JSON, default=dict)
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class JourneyCapsule(Base):
    __tablename__ = "journey_capsules"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), index=True
    )
    snapshot: Mapped[dict] = mapped_column(JSON, default=dict)
    stale_after: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class MaterialWatch(Base):
    __tablename__ = "material_watch"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), index=True
    )
    activity_id: Mapped[str | None] = mapped_column(
        ForeignKey("activities.id", ondelete="CASCADE"), nullable=True
    )
    field: Mapped[str] = mapped_column(String(60), default="opening_hours")
    last_value: Mapped[dict] = mapped_column(JSON, default=dict)
    status: Mapped[str] = mapped_column(String(30), default="watching")
    last_checked_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


# --------------------------------------------------------------------------
# Expenses
# --------------------------------------------------------------------------


class Expense(Base):
    __tablename__ = "expenses"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(160))
    category: Mapped[str] = mapped_column(String(40), default="other")
    amount: Mapped[float] = mapped_column(Float)
    currency: Mapped[str] = mapped_column(String(8), default="EUR")
    paid_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    incurred_on: Mapped[date] = mapped_column(Date, default=date.today)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class ExpenseParticipant(Base):
    __tablename__ = "expense_participants"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    expense_id: Mapped[str] = mapped_column(
        ForeignKey("expenses.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    guest_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    weight: Mapped[float] = mapped_column(Float, default=1.0)
    share_amount: Mapped[float] = mapped_column(Float, default=0.0)


class ExpenseSettlement(Base):
    __tablename__ = "expense_settlements"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), index=True
    )
    from_user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    to_user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    amount: Mapped[float] = mapped_column(Float)
    status: Mapped[str] = mapped_column(String(20), default="suggested")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


# --------------------------------------------------------------------------
# Memories and media
# --------------------------------------------------------------------------


class TripMemory(Base):
    __tablename__ = "trip_memories"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    kind: Mapped[str] = mapped_column(String(20), default="text")
    text_content: Mapped[str | None] = mapped_column(Text, nullable=True)
    media_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    media_type: Mapped[str | None] = mapped_column(String(60), nullable=True)
    caption: Mapped[str | None] = mapped_column(Text, nullable=True)
    captured_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    lon: Mapped[float | None] = mapped_column(Float, nullable=True)
    visibility: Mapped[str] = mapped_column(String(20), default="trip")
    ai_generated: Mapped[bool] = mapped_column(Boolean, default=False)
    approved: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class MemoryEvent(Base):
    __tablename__ = "memory_events"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(160))
    summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    start_at: Mapped[datetime] = mapped_column(DateTime)
    end_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    member_ids: Mapped[list] = mapped_column(JSON, default=list)
    memory_ids: Mapped[list] = mapped_column(JSON, default=list)
    status: Mapped[str] = mapped_column(String(20), default="suggested")
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class MemoryPermission(Base):
    __tablename__ = "memory_permissions"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    memory_id: Mapped[str] = mapped_column(
        ForeignKey("trip_memories.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    can_view: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


# --------------------------------------------------------------------------
# Social, circles, contributors, matching
# --------------------------------------------------------------------------


class TravelCircle(Base):
    __tablename__ = "travel_circles"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    slug: Mapped[str] = mapped_column(String(120), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(120))
    description: Mapped[str] = mapped_column(Text)
    interests: Mapped[list] = mapped_column(JSON, default=list)
    cover_image: Mapped[str | None] = mapped_column(String(500), nullable=True)
    is_public: Mapped[bool] = mapped_column(Boolean, default=True)
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class CircleMember(Base):
    __tablename__ = "circle_members"
    __table_args__ = (UniqueConstraint("circle_id", "user_id", name="uq_circle_member"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    circle_id: Mapped[str] = mapped_column(
        ForeignKey("travel_circles.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    role: Mapped[str] = mapped_column(String(20), default="member")
    joined_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class CirclePost(Base):
    __tablename__ = "circle_posts"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    circle_id: Mapped[str] = mapped_column(
        ForeignKey("travel_circles.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    title: Mapped[str] = mapped_column(String(160))
    body: Mapped[str] = mapped_column(Text)
    activity_id: Mapped[str | None] = mapped_column(
        ForeignKey("activities.id", ondelete="SET NULL"), nullable=True
    )
    status: Mapped[str] = mapped_column(String(20), default="published")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class LocalContributor(Base):
    __tablename__ = "local_contributors"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True, index=True
    )
    destination_id: Mapped[str] = mapped_column(ForeignKey("destinations.id"))
    bio: Mapped[str | None] = mapped_column(Text, nullable=True)
    expertise: Mapped[list] = mapped_column(JSON, default=list)
    verified: Mapped[bool] = mapped_column(Boolean, default=False)
    accepts_requests: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class TravellerMatch(Base):
    __tablename__ = "traveller_matches"
    __table_args__ = (
        UniqueConstraint("user_a_id", "user_b_id", name="uq_match_pair"),
    )

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    user_a_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    user_b_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    destination_id: Mapped[str | None] = mapped_column(
        ForeignKey("destinations.id", ondelete="SET NULL"), nullable=True
    )
    overlap_score: Mapped[float] = mapped_column(Float, default=0)
    reasons: Mapped[list] = mapped_column(JSON, default=list)
    status: Mapped[str] = mapped_column(String(20), default="suggested")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class ConnectionRequest(Base):
    __tablename__ = "connection_requests"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    from_user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    to_user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    trip_id: Mapped[str | None] = mapped_column(
        ForeignKey("trips.id", ondelete="SET NULL"), nullable=True
    )
    message: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="pending")
    decided_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


# --------------------------------------------------------------------------
# Notifications, audit, inspiration, offline queue
# --------------------------------------------------------------------------


class Notification(Base):
    __tablename__ = "notifications"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    trip_id: Mapped[str | None] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), nullable=True
    )
    kind: Mapped[str] = mapped_column(String(40), default="info")
    title: Mapped[str] = mapped_column(String(160))
    body: Mapped[str | None] = mapped_column(Text, nullable=True)
    link: Mapped[str | None] = mapped_column(String(240), nullable=True)
    read_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    trip_id: Mapped[str | None] = mapped_column(
        ForeignKey("trips.id", ondelete="SET NULL"), nullable=True, index=True
    )
    action: Mapped[str] = mapped_column(String(60), index=True)
    entity_type: Mapped[str] = mapped_column(String(60))
    entity_id: Mapped[str | None] = mapped_column(String(32), nullable=True)
    detail: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class ActivityFeedback(Base):
    __tablename__ = "activity_feedback"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    trip_id: Mapped[str | None] = mapped_column(
        ForeignKey("trips.id", ondelete="SET NULL"), nullable=True
    )
    activity_id: Mapped[str] = mapped_column(ForeignKey("activities.id"))
    sentiment: Mapped[str] = mapped_column(String(30))
    consented: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class UserBlock(Base):
    __tablename__ = "user_blocks"
    __table_args__ = (
        UniqueConstraint("blocker_id", "blocked_id", name="uq_user_block"),
    )

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    blocker_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    blocked_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class AbuseReport(Base):
    __tablename__ = "abuse_reports"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    reporter_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    target_user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    target_type: Mapped[str] = mapped_column(String(30), default="user")
    target_id: Mapped[str | None] = mapped_column(String(32), nullable=True)
    reason: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(20), default="open")
    reviewed_by: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class SavedInspiration(Base):
    __tablename__ = "saved_inspiration"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    trip_id: Mapped[str | None] = mapped_column(
        ForeignKey("trips.id", ondelete="SET NULL"), nullable=True
    )
    source_type: Mapped[str] = mapped_column(String(20), default="text")
    content: Mapped[str] = mapped_column(Text)
    extracted: Mapped[dict] = mapped_column(JSON, default=dict)
    status: Mapped[str] = mapped_column(String(20), default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class OfflineSyncQueue(Base):
    __tablename__ = "offline_sync_queue"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    trip_id: Mapped[str] = mapped_column(ForeignKey("trips.id", ondelete="CASCADE"))
    client_id: Mapped[str] = mapped_column(String(80), unique=True)
    operation: Mapped[str] = mapped_column(String(40))
    payload: Mapped[dict] = mapped_column(JSON, default=dict)
    status: Mapped[str] = mapped_column(String(20), default="queued")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    applied_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


# --------------------------------------------------------------------------
# Collaborative planning extras
# --------------------------------------------------------------------------


class PlannerTask(Base):
    __tablename__ = "planner_tasks"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(160))
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    assignee_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    status: Mapped[str] = mapped_column(String(20), default="open")
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class TripBranch(Base):
    __tablename__ = "trip_branches"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(120))
    member_ids: Mapped[list] = mapped_column(JSON, default=list)
    activity_id: Mapped[str | None] = mapped_column(
        ForeignKey("activities.id", ondelete="SET NULL"), nullable=True
    )
    reunion_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    reunion_place: Mapped[str | None] = mapped_column(String(160), nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="planned")
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class GroundRequest(Base):
    __tablename__ = "ground_requests"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), index=True
    )
    place_id: Mapped[str | None] = mapped_column(
        ForeignKey("places.id", ondelete="SET NULL"), nullable=True
    )
    activity_id: Mapped[str | None] = mapped_column(
        ForeignKey("activities.id", ondelete="SET NULL"), nullable=True
    )
    question: Mapped[str] = mapped_column(Text)
    requested_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    status: Mapped[str] = mapped_column(String(20), default="open")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class GroundResponse(Base):
    __tablename__ = "ground_responses"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    request_id: Mapped[str] = mapped_column(
        ForeignKey("ground_requests.id", ondelete="CASCADE"), index=True
    )
    contributor_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    observation: Mapped[str] = mapped_column(Text)
    observed_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    confidence: Mapped[float] = mapped_column(Float, default=0.5)
    verified: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class TripMission(Base):
    __tablename__ = "trip_missions"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(160))
    description: Mapped[str] = mapped_column(Text)
    constraints: Mapped[dict] = mapped_column(JSON, default=dict)
    status: Mapped[str] = mapped_column(String(20), default="active")
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class UserMission(Base):
    __tablename__ = "user_missions"
    __table_args__ = (UniqueConstraint("mission_id", "user_id", name="uq_user_mission"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    mission_id: Mapped[str] = mapped_column(
        ForeignKey("trip_missions.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    status: Mapped[str] = mapped_column(String(20), default="joined")
    completed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
