"""Consented outcome learning (F33) shared by engine and place endpoints."""

from sqlalchemy.orm import Session

from app.models import Activity, ActivityFeedback, ConsentRecord, JourneyDNA, User
from app.services.common import DNA_DIMENSIONS, clamp, default_dna, normalize_tag

DNA_SENTIMENT = {
    "loved": 2.0,
    "would_return": 1.5,
    "okay": 0.0,
    "not_for_me": -1.5,
    "too_expensive": -1.0,
    "too_far": -0.5,
}


def personalization_allowed(db: Session, user_id: str) -> bool:
    row = (
        db.query(ConsentRecord)
        .filter(
            ConsentRecord.user_id == user_id,
            ConsentRecord.kind == "personalization",
        )
        .order_by(ConsentRecord.created_at.desc())
        .first()
    )
    return not row or row.granted


def upsert_activity_feedback(
    db: Session,
    *,
    user_id: str,
    trip_id: str | None,
    activity: Activity,
    sentiment: str,
    consented: bool,
) -> ActivityFeedback:
    row = (
        db.query(ActivityFeedback)
        .filter(
            ActivityFeedback.user_id == user_id,
            ActivityFeedback.activity_id == activity.id,
            ActivityFeedback.trip_id == trip_id,
        )
        .first()
    )
    if row:
        row.sentiment = sentiment
        row.consented = consented
        return row
    row = ActivityFeedback(
        user_id=user_id,
        trip_id=trip_id,
        activity_id=activity.id,
        sentiment=sentiment,
        consented=consented,
    )
    db.add(row)
    return row


def apply_feedback_to_dna(
    db: Session,
    user: User,
    activity: Activity,
    sentiment: str,
    *,
    consented: bool,
) -> dict | None:
    delta = DNA_SENTIMENT.get(sentiment, 0.0)
    if not consented or delta == 0:
        return None
    if not personalization_allowed(db, user.id):
        return None
    dna = db.query(JourneyDNA).filter(JourneyDNA.user_id == user.id).first()
    if not dna:
        dna = JourneyDNA(user_id=user.id, scores=default_dna(), source="feedback")
        db.add(dna)
        db.flush()
    scores = dict(dna.scores or default_dna())
    changed: list[str] = []
    for tag in activity.tags or []:
        key = normalize_tag(tag)
        if key in DNA_DIMENSIONS:
            scores[key] = round(clamp(float(scores.get(key, 5)) + delta, 0, 10), 2)
            changed.append(key)
    if not changed:
        return None
    dna.scores = scores
    dna.source = "feedback+explicit"
    return {"dimensions": sorted(set(changed)), "scores": scores}
