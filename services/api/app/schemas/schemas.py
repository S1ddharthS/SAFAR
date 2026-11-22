from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, EmailStr, Field

TravelPace = Literal["slow", "balanced", "fast"]
BudgetLevel = Literal["budget", "moderate", "comfort", "luxury"]
TripRole = Literal["owner", "admin", "member"]
EngineMode = Literal["everyone_wins", "your_turn", "surprise_us"]


class RegisterIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    display_name: str = Field(min_length=2, max_length=80)


class LoginIn(BaseModel):
    email: EmailStr
    password: str


class UserOut(BaseModel):
    id: str
    email: EmailStr
    display_name: str
    is_admin: bool
    quiet_mode: bool
    locale: str
    created_at: datetime


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut


class ProfileUpdate(BaseModel):
    headline: str | None = Field(default=None, max_length=160)
    bio: str | None = None
    home_city: str | None = None
    travel_pace: TravelPace | None = None
    budget_level: BudgetLevel | None = None
    budget_limit: float | None = Field(default=None, ge=0)
    interests: list[str] | None = None
    accessibility_needs: list[str] | None = None
    dietary: list[str] | None = None
    languages: list[str] | None = None
    public_profile: bool | None = None
    allow_discovery: bool | None = None
    location_sharing: bool | None = None


class DNAUpdate(BaseModel):
    scores: dict[str, int]


class ConsentUpdate(BaseModel):
    consents: dict[str, bool]


class UserSettingsUpdate(BaseModel):
    display_name: str | None = Field(default=None, min_length=2, max_length=80)
    quiet_mode: bool | None = None
    locale: str | None = Field(default=None, max_length=16)
    timezone: str | None = Field(default=None, max_length=64)


class AbuseReportIn(BaseModel):
    target_user_id: str | None = None
    target_type: Literal["user", "post", "memory", "report"] = "user"
    target_id: str | None = None
    reason: str = Field(min_length=5, max_length=2000)


class FeedbackIn(BaseModel):
    sentiment: Literal[
        "loved", "okay", "not_for_me", "too_expensive", "too_far", "would_return"
    ]
    consented: bool = True


class TripCreate(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    description: str | None = None
    destination_id: str | None = None
    destination_name: str | None = None
    start_date: date
    end_date: date
    group_size: int = Field(default=4, ge=2, le=12)
    budget_total: float | None = Field(default=None, ge=0)
    currency: str = "EUR"


class TripUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=120)
    description: str | None = None
    start_date: date | None = None
    end_date: date | None = None
    group_size: int | None = Field(default=None, ge=2, le=12)
    budget_total: float | None = Field(default=None, ge=0)
    status: Literal["planning", "active", "completed", "archived"] | None = None


class InviteCreate(BaseModel):
    email: EmailStr | None = None
    role: Literal["admin", "member"] = "member"
    scope: Literal["full", "vote", "pulse", "view"] = "full"
    expires_in_days: int = Field(default=7, ge=1, le=30)


class MemberSelfUpdate(BaseModel):
    budget_limit: float | None = Field(default=None, ge=0)
    accessibility_needs: list[str] | None = None


class MemberRoleUpdate(BaseModel):
    role: Literal["owner", "admin", "member"]


class ItemCreate(BaseModel):
    day: date
    start_time: str = Field(default="09:00", pattern=r"^\d{2}:\d{2}$")
    end_time: str | None = Field(default=None, pattern=r"^\d{2}:\d{2}$")
    title: str | None = None
    activity_id: str | None = None
    notes: str | None = None
    cost_estimate: float | None = Field(default=None, ge=0)
    is_protected: bool = False


class ItemUpdate(BaseModel):
    day: date | None = None
    start_time: str | None = Field(default=None, pattern=r"^\d{2}:\d{2}$")
    end_time: str | None = Field(default=None, pattern=r"^\d{2}:\d{2}$")
    title: str | None = None
    notes: str | None = None
    cost_estimate: float | None = Field(default=None, ge=0)
    is_protected: bool | None = None
    status: Literal["confirmed", "cancelled"] | None = None


class AttendanceUpdate(BaseModel):
    status: Literal["in", "out", "join_later"]


class ProposalCreate(BaseModel):
    kind: Literal["add_activity", "replace_item", "remove_item", "custom"] = (
        "add_activity"
    )
    title: str = Field(min_length=2, max_length=200)
    summary: str | None = None
    activity_id: str | None = None
    day: date | None = None
    start_time: str | None = Field(default=None, pattern=r"^\d{2}:\d{2}$")
    target_item_id: str | None = None
    payload: dict = Field(default_factory=dict)


class VoteIn(BaseModel):
    value: Literal["yes", "no", "abstain"]
    comment: str | None = Field(default=None, max_length=1000)


class ApprovalIn(BaseModel):
    approval: bool = True


class PulseIn(BaseModel):
    pulse_date: date | None = None
    energy: int = Field(default=3, ge=1, le=5)
    interests: list[str] = Field(default_factory=list)
    available_minutes: int | None = Field(default=None, ge=15, le=1440)
    budget_comfort: int = Field(default=3, ge=1, le=5)
    radius_km: float | None = Field(default=None, ge=0, le=200)
    activity_prefs: list[str] = Field(default_factory=list)
    note: str | None = Field(default=None, max_length=500)


class RecommendIn(BaseModel):
    mode: EngineMode = "everyone_wins"
    for_date: date | None = None
    limit: int = Field(default=6, ge=1, le=12)


class RecommendationFeedbackIn(BaseModel):
    sentiment: Literal[
        "loved", "okay", "not_for_me", "too_expensive", "too_far", "would_return"
    ]
    consented: bool = True


class ApproveRecommendationIn(BaseModel):
    day: date
    start_time: str = Field(default="09:00", pattern=r"^\d{2}:\d{2}$")


class TwinCompareIn(BaseModel):
    activity_ids: list[str] = Field(default_factory=list, max_length=16)
    day: date | None = None


class TwinProposeIn(BaseModel):
    activity_ids: list[str] = Field(min_length=1, max_length=16)
    day: date | None = None


class RecommendationProposeIn(BaseModel):
    day: date
    start_time: str = Field(default="09:00", pattern=r"^\d{2}:\d{2}$")


class RescueProposalItem(BaseModel):
    item_id: str
    activity_id: str
    day: date
    start_time: str = Field(default="09:00", pattern=r"^\d{2}:\d{2}$")


class RescueProposeIn(BaseModel):
    kind: Literal["rain", "closure", "traffic", "fatigue", "budget", "time"] = "rain"
    item_id: str | None = None
    extra_minutes: int = Field(default=45, ge=0, le=600)
    note: str | None = None
    items: list[RescueProposalItem] = Field(default_factory=list)


class RescueIn(BaseModel):
    kind: Literal["rain", "closure", "traffic", "fatigue", "budget", "time"]
    item_id: str | None = None
    extra_minutes: int = Field(default=45, ge=0, le=600)
    note: str | None = None


class NegotiateIn(BaseModel):
    option_a: list[str] = Field(default_factory=list)
    option_b: list[str] = Field(default_factory=list)
    for_date: date | None = None


class ParticipantIn(BaseModel):
    user_id: str | None = None
    guest_name: str | None = Field(default=None, max_length=120)
    weight: float = Field(default=1.0, gt=0)
    share_amount: float | None = Field(default=None, ge=0)


class ExpenseCreate(BaseModel):
    title: str = Field(min_length=2, max_length=160)
    category: str = "other"
    amount: float = Field(gt=0)
    # When omitted the trip currency is used; a mismatched explicit value is rejected.
    currency: str | None = None
    paid_by: str | None = None
    incurred_on: date | None = None
    notes: str | None = None
    split: Literal["equal", "custom", "weights"] = "equal"
    participants: list[ParticipantIn] = Field(default_factory=list)


class PlaceReportIn(BaseModel):
    activity_id: str | None = None
    place_id: str | None = None
    category: Literal[
        "crowd", "queue", "parking", "closure", "accessibility", "price", "road", "quality"
    ]
    value: dict = Field(default_factory=dict)
    note: str | None = Field(default=None, max_length=1000)
    observed_at: datetime | None = None
    source_type: Literal["official", "community", "estimated", "unknown"] = "community"
    confidence: float | None = Field(default=None, ge=0, le=1)


class ExpectationIn(BaseModel):
    claim: str = Field(min_length=3, max_length=300)


class ContributorIn(BaseModel):
    destination_id: str
    bio: str | None = Field(default=None, max_length=1000)
    expertise: list[str] = Field(default_factory=list)
    accepts_requests: bool = True


class PlaceReportUpdate(BaseModel):
    value: dict | None = None
    note: str | None = Field(default=None, max_length=1000)


class MaterialWatchIn(BaseModel):
    activity_id: str
    field: Literal["opening_hours", "price_estimate", "wheelchair_accessible"] = "opening_hours"


class AbuseDecisionIn(BaseModel):
    decision: Literal["dismiss", "hide_content", "warn"]
    note: str | None = Field(default=None, max_length=1000)


class GroundRequestIn(BaseModel):
    place_id: str | None = None
    activity_id: str | None = None
    question: str = Field(min_length=5, max_length=1000)


class GroundResponseIn(BaseModel):
    observation: str = Field(min_length=5, max_length=2000)
    confidence: float = Field(default=0.5, ge=0, le=1)


class MemoryCreate(BaseModel):
    kind: Literal["text", "photo", "video", "voice", "event"] = "text"
    text_content: str | None = Field(default=None, max_length=4000)
    media_url: str | None = Field(default=None, max_length=500)
    media_type: str | None = Field(default=None, max_length=60)
    caption: str | None = Field(default=None, max_length=1000)
    captured_at: datetime | None = None
    lat: float | None = None
    lon: float | None = None
    visibility: Literal["trip", "private"] = "trip"
    client_id: str | None = None


class MemoryUpdate(BaseModel):
    text_content: str | None = Field(default=None, max_length=4000)
    caption: str | None = Field(default=None, max_length=1000)
    visibility: Literal["trip", "private"] | None = None
    approved: bool | None = None


class MemoryPermissionIn(BaseModel):
    user_id: str
    can_view: bool = True


class MemoryEventCreate(BaseModel):
    title: str = Field(min_length=2, max_length=160)
    summary: str | None = None
    start_at: datetime
    end_at: datetime | None = None
    memory_ids: list[str] = Field(default_factory=list)
    status: Literal["suggested", "approved"] = "suggested"


class ChatIn(BaseModel):
    message: str = Field(min_length=1, max_length=2000)
    trip_id: str | None = None
    language: str | None = Field(default=None, max_length=16)


class InspirationIn(BaseModel):
    source_type: Literal["text", "image_url", "link"] = "text"
    content: str = Field(default="", max_length=4000)
    trip_id: str | None = None
    # Signed local media URL from POST /api/trips/{id}/media. Used for local OCR.
    media_url: str | None = Field(default=None, max_length=1000)


class InspirationReviewIn(BaseModel):
    candidate_id: str = Field(min_length=1, max_length=120)
    decision: Literal["accept", "reject"]


class CompanionLinkIn(BaseModel):
    purpose: Literal["vote", "checkin"]
    target_id: str = Field(min_length=1, max_length=64)
    ttl_minutes: int = Field(default=1440, ge=5, le=10080)


class CompanionResponseIn(BaseModel):
    value: str = Field(min_length=1, max_length=20)
    comment: str | None = Field(default=None, max_length=500)


class PactUpsert(BaseModel):
    must_do: list[str] = Field(default_factory=list)
    flexible: list[str] = Field(default_factory=list)
    individual_limits: dict = Field(default_factory=dict)
    confirmed_times: dict = Field(default_factory=dict)
    exceptions: list[str] = Field(default_factory=list)


class TaskCreate(BaseModel):
    title: str = Field(min_length=2, max_length=160)
    description: str | None = None
    assignee_id: str | None = None


class TaskUpdate(BaseModel):
    status: Literal["open", "done"] | None = None
    assignee_id: str | None = None


class BranchCreate(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    member_ids: list[str] = Field(default_factory=list)
    activity_id: str | None = None
    reunion_at: datetime | None = None
    reunion_place: str | None = None


class ShadowplanCreate(BaseModel):
    item_id: str
    backup_activity_id: str
    notes: str | None = None


class CapsuleCreate(BaseModel):
    ttl_hours: int = Field(default=72, ge=1, le=720)


class ConnectionCreate(BaseModel):
    to_user_id: str
    trip_id: str | None = None
    message: str | None = Field(default=None, max_length=500)


class ConnectionDecision(BaseModel):
    accept: bool


class CirclePostCreate(BaseModel):
    title: str = Field(min_length=2, max_length=160)
    body: str = Field(min_length=2, max_length=4000)
    activity_id: str | None = None


class MissionCreate(BaseModel):
    title: str = Field(min_length=2, max_length=160)
    description: str = Field(min_length=2, max_length=1000)
    constraints: dict = Field(default_factory=dict)


class NotificationRead(BaseModel):
    read: bool = True


class OfflineSyncItem(BaseModel):
    client_id: str = Field(min_length=6, max_length=80)
    operation: Literal["memory_create"]
    payload: dict
