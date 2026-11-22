"""One-Link Companion (F26).

Short-lived, single-purpose links let somebody answer exactly one question —
one vote or one check-in — without an account. Tokens are HMAC-signed and
carry the link id, expiry, purpose and target, so a token cannot be repointed
at another trip, proposal or item. Responses are anonymous: no user id, IP
address or user agent is stored.
"""

import hashlib
import hmac
from datetime import datetime, timedelta, timezone

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models import (
    CompanionLink,
    CompanionResponse,
    ItineraryItem,
    ItineraryProposal,
    Trip,
    Vote,
)
from app.models.models import utcnow

MAX_TTL_MINUTES = 7 * 24 * 60
MIN_TTL_MINUTES = 5

VOTE_VALUES = ("yes", "no", "abstain")
CHECKIN_VALUES = ("in", "out", "join_later")
PURPOSES = ("vote", "checkin")


def _epoch(value: datetime) -> int:
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return int(value.timestamp())


def _signature(link_id: str, expires: int, purpose: str, target_id: str) -> str:
    message = f"{link_id}.{expires}.{purpose}.{target_id}".encode("utf-8")
    return hmac.new(
        settings.secret_key.encode("utf-8"), message, hashlib.sha256
    ).hexdigest()[:40]


def issue_token(link: CompanionLink) -> str:
    expires = _epoch(link.expires_at)
    return f"{link.id}.{expires}.{_signature(link.id, expires, link.purpose, link.target_id)}"


def parse_token(token: str) -> tuple[str, int, str] | None:
    parts = (token or "").split(".")
    if len(parts) != 3:
        return None
    link_id, raw_expires, signature = parts
    if len(link_id) != 32 or not link_id.isalnum():
        return None
    try:
        expires = int(raw_expires)
    except ValueError:
        return None
    return link_id, expires, signature


def token_valid(link: CompanionLink, expires: int, signature: str) -> bool:
    if expires != _epoch(link.expires_at):
        return False
    expected = _signature(link.id, expires, link.purpose, link.target_id)
    return hmac.compare_digest(signature, expected)


def link_status(link: CompanionLink, now: datetime | None = None) -> str:
    now = now or utcnow()
    if link.revoked_at:
        return "revoked"
    if _epoch(link.expires_at) <= _epoch(now):
        return "expired"
    if link.used_count >= link.max_uses:
        return "used"
    return "active"


def expires_from_now(minutes: int) -> datetime:
    minutes = max(MIN_TTL_MINUTES, min(MAX_TTL_MINUTES, minutes))
    return utcnow() + timedelta(minutes=minutes)


def resolve_active(db: Session, token: str) -> tuple[CompanionLink, str | None]:
    """Return (link, None) or (link/None, error message)."""
    parsed = parse_token(token)
    if not parsed:
        return None, "This link is not valid."
    link_id, expires, signature = parsed
    link = db.get(CompanionLink, link_id)
    if not link or not token_valid(link, expires, signature):
        return None, "This link is not valid."
    status = link_status(link)
    if status == "revoked":
        return link, "This link was revoked by its creator."
    if status == "expired":
        return link, "This link has expired."
    if status == "used":
        return link, "This link has already been used."
    return link, None


def context(db: Session, link: CompanionLink) -> dict:
    trip = db.get(Trip, link.trip_id)
    base = {
        "purpose": link.purpose,
        "trip": {
            "name": trip.name if trip else "Journey",
            "destination_name": trip.destination_name if trip else "",
        },
        "expires_at": link.expires_at,
        "remaining_uses": max(0, link.max_uses - link.used_count),
        "disclosure": (
            "This page answers one question without an account. Your identity is not recorded."
        ),
    }
    anonymous_count = (
        db.query(func.count(CompanionResponse.id))
        .filter(CompanionResponse.link_id == link.id)
        .scalar()
        or 0
    )
    base["anonymous_responses"] = anonymous_count

    if link.purpose == "vote":
        proposal = db.get(ItineraryProposal, link.target_id)
        counts = {"yes": 0, "no": 0, "abstain": 0}
        if proposal:
            for value, count in (
                db.query(Vote.value, func.count(Vote.id))
                .filter(Vote.proposal_id == proposal.id)
                .group_by(Vote.value)
                .all()
            ):
                counts[value] = count
        base["target"] = {
            "kind": "proposal",
            "id": link.target_id,
            "title": proposal.title if proposal else "Decision unavailable",
            "summary": proposal.summary if proposal else None,
            "status": proposal.status if proposal else "missing",
            "registered_votes": counts,
        }
        base["question"] = "Do you support this decision?"
        base["options"] = list(VOTE_VALUES)
    else:
        item = db.get(ItineraryItem, link.target_id)
        base["target"] = {
            "kind": "checkin",
            "id": link.target_id,
            "title": item.title if item else "Item unavailable",
            "day": item.day.isoformat() if item else None,
            "start_time": item.start_time if item else None,
            "status": item.status if item else "missing",
        }
        base["question"] = "Will you join this confirmed item?"
        base["options"] = list(CHECKIN_VALUES)
    return base


def target_open(db: Session, link: CompanionLink) -> tuple[bool, str]:
    if link.purpose == "vote":
        proposal = db.get(ItineraryProposal, link.target_id)
        if not proposal or proposal.trip_id != link.trip_id:
            return False, "This decision is unavailable."
        if proposal.status != "open":
            return False, "This decision is no longer open."
        return True, ""
    item = db.get(ItineraryItem, link.target_id)
    if not item or item.trip_id != link.trip_id or item.status != "confirmed":
        return False, "This item is no longer confirmed."
    return True, ""
