"""Grounded travel assistant (F22) with explicit capability disclosure."""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.deps import (
    get_current_user,
    get_db,
    get_trip_and_member,
    trip_scope_guard,
)
from app.integrations.registry import capabilities as provider_capabilities
from app.models import Profile, Trip, TripMember, User
from app.schemas.schemas import ChatIn
from app.services.assistant import GENERATOR, answer
from app.services.assistant_text import t
from app.services.language import resolve_language

router = APIRouter(prefix="/api/assistant", tags=["assistant"])


def _preferred_language(db: Session, user: User) -> str | None:
    profile = db.query(Profile).filter(Profile.user_id == user.id).first()
    languages = list(profile.languages or []) if profile else []
    return languages[0] if languages else None


def _answer_with_trip(
    db: Session, user: User, trip: Trip, message: str, language: str | None
) -> dict:
    return answer(
        db,
        user,
        trip,
        message,
        language=language,
        preferred_language=_preferred_language(db, user),
    )


@router.get("/capabilities")
def capabilities():
    providers = provider_capabilities()["providers"]
    weather_enabled = bool(providers["weather"]["enabled"])
    translation = providers["translation"]
    return {
        "generator": GENERATOR,
        "type": "grounded retrieval",
        "external_llm": False,
        "translation": True,
        "translation_mode": translation["mode"],
        "language_detection": "unicode script ranges + folded stopword scoring",
        "languages": translation["languages"],
        "language_names": translation["language_names"],
        "weather": weather_enabled,
        "weather_provider": providers["weather"]["provider"] if weather_enabled else None,
        "answer_sources": [
            "confirmed itinerary",
            "trip expenses and settlement suggestions",
            "trip members and roles",
            "open proposals",
            "latest recommendation batches",
            "catalog activity records and recent traveller reports",
            "own profile preferences and consent-permitted group aggregates",
        ],
        "disclosure": (
            "Answers are assembled in-process from SAFAR's own records using local "
            "language templates. No external AI model is used and no message text is "
            "sent to a vendor. "
            + (
                "Weather is a forecast from Open-Meteo, labelled as predicted. "
                if weather_enabled
                else "No weather provider is configured, and the assistant says so. "
            )
            + "Unknown facts are stated as unknown rather than guessed, and physical "
            "itinerary changes are only ever proposed for the group to approve."
        ),
    }


@router.post("/chat")
def chat(
    payload: ChatIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if payload.trip_id:
        trip, _member = get_trip_and_member(payload.trip_id, db, user)
        return {
            **_answer_with_trip(db, user, trip, payload.message, payload.language),
            "trip_id": trip.id,
        }
    trips = (
        db.query(Trip)
        .join(TripMember, TripMember.trip_id == Trip.id)
        .filter(
            TripMember.user_id == user.id,
            TripMember.status == "active",
            Trip.deleted_at.is_(None),
        )
        .order_by(Trip.start_date.desc())
        .all()
    )
    resolution = resolve_language(
        payload.message, requested=payload.language, preferred=_preferred_language(db, user)
    )
    return {
        "intent": "general",
        "answer": t("general.no_trip", resolution["code"]),
        "citations": [],
        "grounding": "product",
        "limitations": ["No trip selected."],
        "suggested_actions": [
            {"label": "Open a trip", "href": f"/trips/{trip.id}"} for trip in trips[:3]
        ],
        "generated_by": GENERATOR,
        "language": {
            "code": resolution["code"],
            "name": resolution["name"],
            "source": resolution["source"],
        },
        "mutation": "none",
        "trip_id": None,
    }


trip_router = APIRouter(
    prefix="/api/trips",
    tags=["assistant"],
    dependencies=[Depends(trip_scope_guard)],
)


@trip_router.post("/{trip_id}/assistant")
def trip_chat(
    trip_id: str,
    payload: ChatIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = get_trip_and_member(trip_id, db, user)
    if payload.trip_id and payload.trip_id != trip.id:
        raise HTTPException(status_code=422, detail="Trip mismatch")
    return {
        **_answer_with_trip(db, user, trip, payload.message, payload.language),
        "trip_id": trip.id,
    }
