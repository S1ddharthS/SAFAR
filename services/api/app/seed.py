"""Deterministic demo data for SAFAR.

Every record here is real database state: the frontend never substitutes a
hardcoded array for the API. Seeds are idempotent — if any user exists the
function returns immediately, so restarting the API never duplicates data.

Run standalone with::

    python -m app.seed
"""

from __future__ import annotations

from datetime import date, datetime, timedelta

from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import hash_password
from app.models import (
    Activity,
    ActivityFeedback,
    CircleMember,
    CirclePost,
    ConsentRecord,
    Destination,
    Expense,
    ExpenseParticipant,
    GroundRequest,
    GroundResponse,
    Itinerary,
    ItineraryItem,
    ItineraryProposal,
    JourneyCapsule,
    JourneyDNA,
    JourneyPact,
    LocalContributor,
    MaterialWatch,
    MemoryPermission,
    Notification,
    Place,
    PlaceReport,
    PlannerTask,
    Profile,
    Recommendation,
    RecommendationBatch,
    SavedInspiration,
    Shadowplan,
    Trip,
    TripBranch,
    TripInvitation,
    TripMember,
    TripMemory,
    TripPulse,
    User,
    UserMission,
    Vote,
)
from app.models.models import utcnow
from app.services.common import (
    audit,
    default_dna,
    record_itinerary_version,
)
from app.services.discovery import ensure_seed_circles, generate_missions
from app.services.engine import ENGINE_VERSION, generate_recommendations
from app.services.expenses import resolve_shares

DEMO_PASSWORD = "safar-demo-123"


def _ago(days: int, *, hours: int = 0) -> datetime:
    return utcnow() - timedelta(days=days, hours=hours)


# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

USER_BLUEPRINTS = [
    {
        "email": "mira@safar.demo",
        "name": "Mira Okafor",
        "admin": True,
        "timezone": "Asia/Tokyo",
        "home_city": "Lisbon",
        "headline": "Documentary photographer, slow-morning enthusiast.",
        "bio": "I plan around light and long breakfasts. Happiest in gardens with a camera.",
        "travel_pace": "slow",
        "budget_level": "comfort",
        "budget_limit": 120.0,
        "interests": ["photography", "culture", "food", "history", "local"],
        "dietary": ["vegetarian"],
        "languages": ["English", "Portuguese"],
        "dna": {
            "photography": 9,
            "culture": 9,
            "food": 8,
            "history": 8,
            "nature": 7,
            "relaxation": 6,
            "adventure": 6,
            "shopping": 6,
            "luxury": 7,
            "budget": 5,
            "outdoor": 7,
            "local": 8,
        },
    },
    {
        "email": "jonas@safar.demo",
        "name": "Jonas Berg",
        "admin": False,
        "timezone": "Europe/Lisbon",
        "home_city": "Lisbon",
        "headline": "Trail runner collecting ridgelines.",
        "bio": "Give me a hill, an early start and a bakery at the end.",
        "travel_pace": "active",
        "budget_level": "budget",
        "budget_limit": 60.0,
        "interests": ["adventure", "outdoor", "nature", "photography"],
        "dietary": [],
        "languages": ["English", "Swedish"],
        "dna": {
            "photography": 7,
            "culture": 6,
            "food": 7,
            "history": 5,
            "nature": 9,
            "relaxation": 4,
            "adventure": 9,
            "shopping": 3,
            "luxury": 4,
            "budget": 6,
            "outdoor": 9,
            "local": 7,
        },
    },
    {
        "email": "aiko@safar.demo",
        "name": "Aiko Tanaka",
        "admin": False,
        "timezone": "Asia/Tokyo",
        "home_city": "Kyoto",
        "headline": "Food writer on a quiet-café quest.",
        "bio": "I would rather do three things well than ten things badly.",
        "travel_pace": "slow",
        "budget_level": "moderate",
        "budget_limit": 80.0,
        "interests": ["food", "relaxation", "culture", "local", "shopping"],
        "dietary": [],
        "languages": ["Japanese", "English"],
        "dna": {
            "photography": 6,
            "culture": 8,
            "food": 9,
            "history": 6,
            "nature": 5,
            "relaxation": 8,
            "adventure": 3,
            "shopping": 7,
            "luxury": 5,
            "budget": 6,
            "outdoor": 4,
            "local": 8,
        },
    },
    {
        "email": "leo@safar.demo",
        "name": "Leo Martins",
        "admin": False,
        "timezone": "Europe/Lisbon",
        "home_city": "Porto",
        "headline": "Museum guide and amateur historian.",
        "bio": "Every city is a stack of older cities. I want to read all of them.",
        "travel_pace": "balanced",
        "budget_level": "moderate",
        "budget_limit": 150.0,
        "interests": ["history", "culture", "photography", "food", "local"],
        "dietary": [],
        "languages": ["Portuguese", "English", "Spanish"],
        "dna": {
            "photography": 8,
            "culture": 9,
            "food": 7,
            "history": 9,
            "nature": 6,
            "relaxation": 6,
            "adventure": 5,
            "shopping": 5,
            "luxury": 6,
            "budget": 5,
            "outdoor": 6,
            "local": 8,
        },
    },
    {
        "email": "noor@safar.demo",
        "name": "Noor Haddad",
        "admin": False,
        "timezone": "Asia/Tokyo",
        "home_city": "Kyoto",
        "headline": "Kyoto local · garden volunteer · tea student.",
        "bio": "I answer questions about the city I actually walk every day.",
        "travel_pace": "slow",
        "budget_level": "moderate",
        "budget_limit": None,
        "interests": ["local", "food", "history", "relaxation"],
        "dietary": [],
        "languages": ["Japanese", "English", "Arabic"],
        "dna": {
            "photography": 6,
            "culture": 7,
            "food": 9,
            "history": 8,
            "nature": 6,
            "relaxation": 7,
            "adventure": 4,
            "shopping": 5,
            "luxury": 5,
            "budget": 6,
            "outdoor": 6,
            "local": 10,
        },
        "public": True,
    },
    {
        "email": "mateo@safar.demo",
        "name": "Mateo Silveira",
        "admin": False,
        "timezone": "Europe/Lisbon",
        "home_city": "Lisbon",
        "headline": "Lisbon local · ferry commuter · fado listener.",
        "bio": "Ask me which viewpoint is worth the hill, and which is not.",
        "travel_pace": "balanced",
        "budget_level": "moderate",
        "budget_limit": None,
        "interests": ["local", "food", "adventure", "nature"],
        "dietary": [],
        "languages": ["Portuguese", "English"],
        "dna": {
            "photography": 6,
            "culture": 7,
            "food": 8,
            "history": 6,
            "nature": 7,
            "relaxation": 6,
            "adventure": 8,
            "shopping": 4,
            "luxury": 5,
            "budget": 6,
            "outdoor": 8,
            "local": 9,
        },
        "public": True,
    },
]


def _seed_user(db: Session, spec: dict) -> User:
    user = User(
        email=spec["email"],
        password_hash=hash_password(DEMO_PASSWORD),
        display_name=spec["name"],
        is_admin=spec.get("admin", False),
        timezone=spec["timezone"],
        locale="en",
    )
    db.add(user)
    db.flush()

    db.add(
        Profile(
            user_id=user.id,
            headline=spec["headline"],
            bio=spec["bio"],
            home_city=spec["home_city"],
            travel_pace=spec["travel_pace"],
            budget_level=spec["budget_level"],
            budget_limit=spec["budget_limit"],
            interests=spec["interests"],
            dietary=spec["dietary"],
            languages=spec["languages"],
            public_profile=spec.get("public", False),
            allow_discovery=spec.get("public", False),
            location_sharing=False,
        )
    )
    for kind in ("terms", "personalization", "analytics", "location", "marketing"):
        db.add(
            ConsentRecord(
                user_id=user.id,
                kind=kind,
                granted=kind in {"terms", "personalization"},
                policy_version=settings.policy_version,
            )
        )
    scores = default_dna()
    scores.update(spec["dna"])
    db.add(JourneyDNA(user_id=user.id, scores=scores, source="explicit"))
    return user


# ---------------------------------------------------------------------------
# Catalog
# ---------------------------------------------------------------------------


def _mk_place(
    db: Session,
    destination: Destination,
    *,
    name: str,
    category: str,
    description: str,
    lat: float,
    lon: float,
    address: str | None = None,
    fragile: bool = False,
    respect_note: str | None = None,
    verified_days_ago: int | None = None,
) -> Place:
    place = Place(
        destination_id=destination.id,
        name=name,
        category=category,
        description=description,
        lat=lat,
        lon=lon,
        address=address,
        fragile=fragile,
        respect_note=respect_note,
        source_type="seed_catalog",
        source_name="SAFAR curated catalog",
        last_verified_at=_ago(verified_days_ago) if verified_days_ago is not None else None,
    )
    db.add(place)
    db.flush()
    return place


def _mk_activity(
    db: Session,
    destination: Destination,
    place: Place,
    *,
    name: str,
    description: str,
    tags: list[str],
    price: float,
    duration: int,
    effort: int,
    indoor: bool,
    wheelchair: bool | None,
    iconic: bool,
    popularity: float,
    opening_hours: dict | None = None,
    access_chain: dict | None = None,
    verified_days_ago: int | None = None,
    fragile: bool = False,
) -> Activity:
    activity = Activity(
        place_id=place.id,
        destination_id=destination.id,
        name=name,
        description=description,
        tags=tags,
        price_estimate=price,
        currency="EUR",
        duration_minutes=duration,
        effort=effort,
        indoor=indoor,
        wheelchair_accessible=wheelchair,
        iconic=iconic,
        popularity=popularity,
        fragile=fragile,
        opening_hours=opening_hours or {},
        access_chain=access_chain or {},
        source_type="seed_catalog",
        last_verified_at=_ago(verified_days_ago) if verified_days_ago is not None else None,
    )
    db.add(activity)
    db.flush()
    return activity


WEEKLY_HOURS = {day: "09:00-17:00" for day in ("mon", "tue", "wed", "thu", "fri", "sat", "sun")}


def _kyoto_catalog(db: Session, destination: Destination) -> dict[str, Activity]:
    specs = [
        {
            "name": "Fushimi Inari Taisha",
            "category": "shrine",
            "description": "Vermilion torii tunnels climbing Mount Inari, busiest at the lower gates.",
            "lat": 34.9671,
            "lon": 135.7727,
            "address": "68 Fukakusa Yabunouchicho, Fushimi Ward",
            "fragile": True,
            "respect_note": "This is an active place of worship. Keep to the paths and lower your voice near the shrines.",
            "verified_days_ago": 40,
            "activity": {
                "name": "Fushimi Inari Torii Walk",
                "description": "A slow climb through the torii gates with a local guide-map of quieter side loops.",
                "tags": ["temple", "history", "photography", "hiking", "outdoor"],
                "price": 0.0,
                "duration": 120,
                "effort": 4,
                "indoor": False,
                "wheelchair": False,
                "iconic": True,
                "popularity": 0.95,
                "opening_hours": {"mon": "24 hours", "tue": "24 hours", "wed": "24 hours", "thu": "24 hours", "fri": "24 hours", "sat": "24 hours", "sun": "24 hours"},
                "access_chain": {
                    "transport_stop": {"status": "verified", "detail": "Inari Station, JR Nara line, 2 minutes on foot."},
                    "path": {"status": "barrier", "detail": "Steep, uneven stone steps beyond the first gates."},
                    "entrance": {"status": "verified", "detail": "Step-free first courtyard."},
                    "experience_area": {"status": "limited", "detail": "Side loops have roots and loose gravel."},
                    "facilities": {"status": "verified", "detail": "Accessible toilet near the main gate."},
                },
                "verified_days_ago": 40,
                "fragile": True,
            },
        },
        {
            "name": "Nishiki Market",
            "category": "market",
            "description": "Five covered blocks of food stalls, pickle shops and knife makers.",
            "lat": 35.0050,
            "lon": 135.7649,
            "address": "Nishikikoji-dori, Nakagyo Ward",
            "verified_days_ago": 12,
            "activity": {
                "name": "Nishiki Market Morning Graze",
                "description": "A guided tasting route through the market with vegetarian stops marked in advance.",
                "tags": ["food", "market", "local", "shopping"],
                "price": 0.0,
                "duration": 90,
                "effort": 1,
                "indoor": True,
                "wheelchair": True,
                "iconic": True,
                "popularity": 0.85,
                "opening_hours": {"mon": "09:30-18:00", "tue": "09:30-18:00", "wed": "09:30-18:00", "thu": "09:30-18:00", "fri": "09:30-18:00", "sat": "09:30-18:00", "sun": "09:30-18:00"},
                "access_chain": {
                    "transport_stop": {"status": "verified", "detail": "Karasuma Station exit 11, step-free lift."},
                    "path": {"status": "verified", "detail": "Flat covered arcade, 4 m wide."},
                    "entrance": {"status": "verified", "detail": "Step-free at both ends."},
                    "experience_area": {"status": "limited", "detail": "Side stalls become narrow at peak hours."},
                    "facilities": {"status": "verified", "detail": "Accessible toilet in the Daimaru basement."},
                },
                "verified_days_ago": 12,
            },
        },
        {
            "name": "Kiyomizu-dera",
            "category": "temple",
            "description": "Hillside temple with the famous wooden stage and a spring below.",
            "lat": 34.9949,
            "lon": 135.7850,
            "address": "1-294 Kiyomizu, Higashiyama Ward",
            "fragile": True,
            "respect_note": "Worship spaces are not photo sets; follow signage about where photography is allowed.",
            "verified_days_ago": 65,
            "activity": {
                "name": "Kiyomizu-dera at Opening",
                "description": "Arrive for the first bell and the empty stage before the tour groups.",
                "tags": ["temple", "history", "photography", "culture"],
                "price": 4.0,
                "duration": 90,
                "effort": 3,
                "indoor": False,
                "wheelchair": None,
                "iconic": True,
                "popularity": 0.9,
                "opening_hours": {"mon": "06:00-18:00", "tue": "06:00-18:00", "wed": "06:00-18:00", "thu": "06:00-18:00", "fri": "06:00-18:00", "sat": "06:00-18:00", "sun": "06:00-18:00"},
                "access_chain": {
                    "transport_stop": {"status": "verified", "detail": "Bus 206 to Kiyomizu-michi, then uphill."},
                    "path": {"status": "limited", "detail": "Steep preserved street with uneven paving."},
                    "entrance": {"status": "reported", "detail": "A side approach claims step-free entry; unverified."},
                    "experience_area": {"status": "limited", "detail": "Main stage requires stairs."},
                    "facilities": {"status": "reported", "detail": "Accessible toilet reported near the ticket gate."},
                },
                "verified_days_ago": 65,
                "fragile": True,
            },
        },
        {
            "name": "Camellia Tea Ceremony",
            "category": "experience",
            "description": "Small tea room near Gion hosting seated matcha ceremonies.",
            "lat": 35.0033,
            "lon": 135.7750,
            "address": "349 Masuyacho, Higashiyama Ward",
            "verified_days_ago": 5,
            "activity": {
                "name": "Tea ceremony at Camellia",
                "description": "A 75-minute seated matcha ceremony with an English-speaking host.",
                "tags": ["culture", "relaxation", "history", "local"],
                "price": 45.0,
                "duration": 75,
                "effort": 1,
                "indoor": True,
                "wheelchair": True,
                "iconic": False,
                "popularity": 0.55,
                "opening_hours": {"mon": "10:00-18:00", "tue": "10:00-18:00", "wed": "10:00-18:00", "thu": "10:00-18:00", "fri": "10:00-18:00", "sat": "10:00-18:00", "sun": "10:00-18:00"},
                "access_chain": {
                    "transport_stop": {"status": "verified", "detail": "Gion-Shijo Station, 6 minutes on foot."},
                    "path": {"status": "verified", "detail": "Level lane, no steps."},
                    "entrance": {"status": "verified", "detail": "Step-free entrance confirmed by the host."},
                    "experience_area": {"status": "verified", "detail": "Seated room with floor cushions and chairs."},
                    "facilities": {"status": "verified", "detail": "Accessible toilet on the ground floor."},
                },
                "verified_days_ago": 5,
            },
        },
        {
            "name": "Arashiyama Bamboo Grove",
            "category": "nature",
            "description": "A short path through tall bamboo on the western edge of the city.",
            "lat": 35.0170,
            "lon": 135.6716,
            "address": "Ukyo Ward, Arashiyama",
            "fragile": True,
            "respect_note": "The grove is a living neighbourhood path. Do not block residents' gates for photos.",
            "verified_days_ago": 20,
            "activity": {
                "name": "Arashiyama Bamboo Grove",
                "description": "Walk the grove early, then take the riverside path back toward the bridge.",
                "tags": ["nature", "photography", "outdoor", "hiking"],
                "price": 0.0,
                "duration": 60,
                "effort": 2,
                "indoor": False,
                "wheelchair": True,
                "iconic": True,
                "popularity": 0.9,
                "opening_hours": {"mon": "24 hours", "tue": "24 hours", "wed": "24 hours", "thu": "24 hours", "fri": "24 hours", "sat": "24 hours", "sun": "24 hours"},
                "access_chain": {
                    "transport_stop": {"status": "verified", "detail": "Torokko Arashiyama Station, 5 minutes on foot."},
                    "path": {"status": "verified", "detail": "Paved, mostly level."},
                    "entrance": {"status": "verified", "detail": "Open access, no ticket."},
                    "experience_area": {"status": "limited", "detail": "One short gravel section."},
                    "facilities": {"status": "reported", "detail": "Accessible toilet at the nearby ranger station."},
                },
                "verified_days_ago": 20,
                "fragile": True,
            },
        },
        {
            "name": "Okochi Sanso Garden",
            "category": "garden",
            "description": "Hillside villa garden with tea included in the entrance fee.",
            "lat": 35.0177,
            "lon": 135.6690,
            "address": "8 Sagaogurayama Tabuchiyamacho, Ukyo Ward",
            "verified_days_ago": 100,
            "activity": {
                "name": "Okochi Sanso Garden & Tea",
                "description": "A quiet hillside garden loop with matcha and a sweet at the villa.",
                "tags": ["nature", "relaxation", "culture", "photography"],
                "price": 7.0,
                "duration": 60,
                "effort": 2,
                "indoor": False,
                "wheelchair": None,
                "iconic": False,
                "popularity": 0.5,
                "opening_hours": WEEKLY_HOURS,
                "access_chain": {
                    "transport_stop": {"status": "reported", "detail": "Arashiyama Station, 15 minutes uphill."},
                    "path": {"status": "limited", "detail": "Gravel and stepped garden paths."},
                    "entrance": {"status": "reported", "detail": "Step at the ticket gate."},
                    "experience_area": {"status": "unknown", "detail": "No reliable access information recorded."},
                },
                "verified_days_ago": 100,
            },
        },
        {
            "name": "Kyoto Railway Museum",
            "category": "museum",
            "description": "Twenty working locomotives, a turntable and hands-on exhibits.",
            "lat": 34.9858,
            "lon": 135.7458,
            "address": "Kankijicho, Shimogyo Ward",
            "verified_days_ago": 8,
            "activity": {
                "name": "Kyoto Railway Museum",
                "description": "Indoor museum with the steam turntable demonstration and a quiet upper gallery.",
                "tags": ["history", "culture", "budget_travel"],
                "price": 12.0,
                "duration": 120,
                "effort": 1,
                "indoor": True,
                "wheelchair": True,
                "iconic": False,
                "popularity": 0.6,
                "opening_hours": {"mon": "10:00-17:00", "tue": "closed", "wed": "10:00-17:00", "thu": "10:00-17:00", "fri": "10:00-17:00", "sat": "10:00-17:00", "sun": "10:00-17:00"},
                "access_chain": {
                    "transport_stop": {"status": "verified", "detail": "Umekoji-Kyotonishi Station, step-free exit."},
                    "path": {"status": "verified", "detail": "Level paved approach."},
                    "entrance": {"status": "verified", "detail": "Step-free with automatic doors."},
                    "experience_area": {"status": "verified", "detail": "Lifts to every gallery."},
                    "facilities": {"status": "verified", "detail": "Accessible toilets on both floors."},
                },
                "verified_days_ago": 8,
            },
        },
        {
            "name": "Philosopher's Path",
            "category": "walk",
            "description": "A canal-side walking path lined with cherry trees.",
            "lat": 35.0270,
            "lon": 135.7949,
            "address": "Sakyo Ward",
            "verified_days_ago": 45,
            "activity": {
                "name": "Philosopher's Path Walk",
                "description": "A slow canal walk with benches, small shrines and no agenda.",
                "tags": ["nature", "relaxation", "outdoor", "culture"],
                "price": 0.0,
                "duration": 45,
                "effort": 2,
                "indoor": False,
                "wheelchair": True,
                "iconic": False,
                "popularity": 0.65,
                "opening_hours": {"mon": "24 hours", "tue": "24 hours", "wed": "24 hours", "thu": "24 hours", "fri": "24 hours", "sat": "24 hours", "sun": "24 hours"},
                "access_chain": {
                    "transport_stop": {"status": "verified", "detail": "Ginkakuji-michi bus stop, 3 minutes."},
                    "path": {"status": "verified", "detail": "Flat paved canal path."},
                    "entrance": {"status": "verified", "detail": "Open path, multiple level access points."},
                    "experience_area": {"status": "verified", "detail": "Benches along the full route."},
                    "facilities": {"status": "reported", "detail": "Public toilet near the north end."},
                },
                "verified_days_ago": 45,
            },
        },
        {
            "name": "Fushimi Sake District",
            "category": "food",
            "description": "Canal-side breweries and tasting rooms south of the centre.",
            "lat": 34.9350,
            "lon": 135.7600,
            "address": "Fushimi Ward",
            "verified_days_ago": 30,
            "activity": {
                "name": "Fushimi Sake District Tasting",
                "description": "Brewery museum plus a guided tasting with non-alcoholic options.",
                "tags": ["food", "history", "local"],
                "price": 15.0,
                "duration": 90,
                "effort": 2,
                "indoor": True,
                "wheelchair": True,
                "iconic": False,
                "popularity": 0.55,
                "opening_hours": {"mon": "10:00-17:00", "tue": "10:00-17:00", "wed": "closed", "thu": "10:00-17:00", "fri": "10:00-17:00", "sat": "10:00-17:00", "sun": "10:00-17:00"},
                "access_chain": {
                    "transport_stop": {"status": "verified", "detail": "Chushojima Station, 4 minutes."},
                    "path": {"status": "verified", "detail": "Flat canal-side street."},
                    "entrance": {"status": "verified", "detail": "Step-free entrance at the museum."},
                    "experience_area": {"status": "verified", "detail": "Tasting room on ground level."},
                    "facilities": {"status": "verified", "detail": "Accessible toilet."},
                },
                "verified_days_ago": 30,
            },
        },
        {
            "name": "Kyoto Handicraft Workshop",
            "category": "experience",
            "description": "Small studio teaching indigo dyeing and paper crafts.",
            "lat": 35.0030,
            "lon": 135.7700,
            "address": "Nakagyo Ward",
            "verified_days_ago": 14,
            "activity": {
                "name": "Indigo Dyeing Workshop",
                "description": "Two-hour indigo workshop; take home your own tenugui cloth.",
                "tags": ["culture", "shopping", "local", "relaxation"],
                "price": 28.0,
                "duration": 120,
                "effort": 2,
                "indoor": True,
                "wheelchair": True,
                "iconic": False,
                "popularity": 0.45,
                "opening_hours": {"mon": "10:00-17:00", "tue": "10:00-17:00", "wed": "10:00-17:00", "thu": "10:00-17:00", "fri": "10:00-17:00", "sat": "10:00-17:00", "sun": "closed"},
                "access_chain": {
                    "transport_stop": {"status": "verified", "detail": "Karasuma Station, 8 minutes."},
                    "path": {"status": "verified", "detail": "Level street."},
                    "entrance": {"status": "verified", "detail": "Step-free."},
                    "experience_area": {"status": "limited", "detail": "Work benches are at standing height."},
                    "facilities": {"status": "reported", "detail": "Toilet on the same floor."},
                },
                "verified_days_ago": 14,
            },
        },
        {
            "name": "Mount Daimonji Trailhead",
            "category": "hike",
            "description": "Short forest climb to the giant bonfire character above the city.",
            "lat": 35.0190,
            "lon": 135.8000,
            "address": "Sakyo Ward",
            "fragile": True,
            "respect_note": "Trail passes through private woodland edges; stay on marked paths.",
            "verified_days_ago": 150,
            "activity": {
                "name": "Mount Daimonji Sunset Hike",
                "description": "A 90-minute climb to the Daimonji fire site for the city view.",
                "tags": ["hiking", "adventure", "outdoor", "nature", "photography"],
                "price": 0.0,
                "duration": 150,
                "effort": 5,
                "indoor": False,
                "wheelchair": False,
                "iconic": False,
                "popularity": 0.5,
                "opening_hours": {"mon": "24 hours", "tue": "24 hours", "wed": "24 hours", "thu": "24 hours", "fri": "24 hours", "sat": "24 hours", "sun": "24 hours"},
                "access_chain": {
                    "transport_stop": {"status": "verified", "detail": "Ginkakuji-michi bus stop."},
                    "path": {"status": "barrier", "detail": "Steep forest trail with roots and loose gravel."},
                    "entrance": {"status": "reported", "detail": "Unmarked trailhead near the cemetery path."},
                    "experience_area": {"status": "barrier", "detail": "Rocky summit ledge."},
                },
                "verified_days_ago": 150,
                "fragile": True,
            },
        },
        {
            "name": "Kyoto Imperial Palace Garden",
            "category": "garden",
            "description": "Free gravel paths and prune-trained pines in the old palace grounds.",
            "lat": 35.0254,
            "lon": 135.7622,
            "address": "Kamigyo Ward",
            "verified_days_ago": 25,
            "activity": {
                "name": "Imperial Palace Garden Loop",
                "description": "A flat garden loop with shaded benches and no crowds before noon.",
                "tags": ["nature", "history", "relaxation", "budget_travel"],
                "price": 0.0,
                "duration": 60,
                "effort": 1,
                "indoor": False,
                "wheelchair": True,
                "iconic": False,
                "popularity": 0.6,
                "opening_hours": {"mon": "09:00-17:00", "tue": "09:00-17:00", "wed": "09:00-17:00", "thu": "09:00-17:00", "fri": "09:00-17:00", "sat": "09:00-17:00", "sun": "09:00-17:00"},
                "access_chain": {
                    "transport_stop": {"status": "verified", "detail": "Imadegawa Station, step-free exit."},
                    "path": {"status": "verified", "detail": "Compacted gravel, level."},
                    "entrance": {"status": "verified", "detail": "Step-free gate."},
                    "experience_area": {"status": "verified", "detail": "Level garden loops."},
                    "facilities": {"status": "verified", "detail": "Accessible toilet at the west gate."},
                },
                "verified_days_ago": 25,
            },
        },
        {
            "name": "Gion",
            "category": "walk",
            "description": "Lantern-lit lanes and wooden townhouses east of the river.",
            "lat": 35.0037,
            "lon": 135.7750,
            "address": "Higashiyama Ward",
            "fragile": True,
            "respect_note": "These are residential lanes. Do not photograph geiko or enter private alleys.",
            "verified_days_ago": 60,
            "activity": {
                "name": "Gion Evening Walk",
                "description": "A guided etiquette-first walk through the public lanes at dusk.",
                "tags": ["culture", "local", "photography", "history"],
                "price": 0.0,
                "duration": 75,
                "effort": 1,
                "indoor": False,
                "wheelchair": True,
                "iconic": False,
                "popularity": 0.7,
                "opening_hours": {"mon": "24 hours", "tue": "24 hours", "wed": "24 hours", "thu": "24 hours", "fri": "24 hours", "sat": "24 hours", "sun": "24 hours"},
                "access_chain": {
                    "transport_stop": {"status": "verified", "detail": "Gion-Shijo Station, step-free exit."},
                    "path": {"status": "verified", "detail": "Mostly level lanes; some stone paving."},
                    "entrance": {"status": "verified", "detail": "Public streets."},
                    "experience_area": {"status": "limited", "detail": "Crowded at dusk; narrow corners."},
                },
                "verified_days_ago": 60,
                "fragile": True,
            },
        },
        {
            "name": "Kyoto Kitchen Studio",
            "category": "food",
            "description": "Home-style cooking class in a converted machiya.",
            "lat": 35.0060,
            "lon": 135.7600,
            "address": "Nakagyo Ward",
            "verified_days_ago": 18,
            "activity": {
                "name": "Machiya Cooking Class",
                "description": "Cook a vegetarian-friendly Kyoto lunch with a market visit first.",
                "tags": ["food", "culture", "local", "market"],
                "price": 45.0,
                "duration": 150,
                "effort": 2,
                "indoor": True,
                "wheelchair": True,
                "iconic": False,
                "popularity": 0.5,
                "opening_hours": {"mon": "10:00-16:00", "tue": "10:00-16:00", "wed": "10:00-16:00", "thu": "10:00-16:00", "fri": "10:00-16:00", "sat": "10:00-16:00", "sun": "closed"},
                "access_chain": {
                    "transport_stop": {"status": "verified", "detail": "Karasuma Station, 7 minutes."},
                    "path": {"status": "verified", "detail": "Level street."},
                    "entrance": {"status": "verified", "detail": "Step-free machiya entrance."},
                    "experience_area": {"status": "verified", "detail": "Ground-floor kitchen."},
                    "facilities": {"status": "verified", "detail": "Accessible toilet."},
                },
                "verified_days_ago": 18,
            },
        },
        {
            "name": "Kyoto International Manga Museum",
            "category": "museum",
            "description": "A former school filled with manga shelves and reading tables.",
            "lat": 35.0150,
            "lon": 135.7590,
            "address": "Nakagyo Ward",
            "verified_days_ago": 22,
            "activity": {
                "name": "Manga Museum Reading Hour",
                "description": "Browse the wall of manga and sketch in the courtyard.",
                "tags": ["culture", "relaxation", "budget_travel"],
                "price": 8.0,
                "duration": 90,
                "effort": 1,
                "indoor": True,
                "wheelchair": True,
                "iconic": False,
                "popularity": 0.55,
                "opening_hours": {"mon": "10:00-18:00", "tue": "10:00-18:00", "wed": "closed", "thu": "10:00-18:00", "fri": "10:00-18:00", "sat": "10:00-18:00", "sun": "10:00-18:00"},
                "access_chain": {
                    "transport_stop": {"status": "verified", "detail": "Karasuma Oike Station, step-free exit."},
                    "path": {"status": "verified", "detail": "Level pavement."},
                    "entrance": {"status": "verified", "detail": "Step-free with a lift."},
                    "experience_area": {"status": "verified", "detail": "Lift to all floors."},
                    "facilities": {"status": "verified", "detail": "Accessible toilet."},
                },
                "verified_days_ago": 22,
            },
        },
        {
            "name": "Nijo Castle",
            "category": "castle",
            "description": "Shogun's palace with nightingale floors and wall paintings.",
            "lat": 35.0142,
            "lon": 135.7481,
            "address": "Nakagyo Ward",
            "verified_days_ago": 70,
            "activity": {
                "name": "Nijo Castle Palace Tour",
                "description": "Walk the palace corridors and the garden loop at an unhurried pace.",
                "tags": ["history", "culture", "photography"],
                "price": 13.0,
                "duration": 90,
                "effort": 2,
                "indoor": False,
                "wheelchair": None,
                "iconic": False,
                "popularity": 0.7,
                "opening_hours": {"mon": "08:45-17:00", "tue": "08:45-17:00", "wed": "08:45-17:00", "thu": "08:45-17:00", "fri": "08:45-17:00", "sat": "08:45-17:00", "sun": "08:45-17:00"},
                "access_chain": {
                    "transport_stop": {"status": "verified", "detail": "Nijojo-mae Station, step-free exit."},
                    "path": {"status": "verified", "detail": "Level gravel approach."},
                    "entrance": {"status": "reported", "detail": "A ramped side entrance is reportedly available."},
                    "experience_area": {"status": "limited", "detail": "Palace corridors have high thresholds."},
                },
                "verified_days_ago": 70,
            },
        },
        {
            "name": "Pontocho Alley",
            "category": "food",
            "description": "Narrow riverside alley of small restaurants.",
            "lat": 35.0055,
            "lon": 135.7716,
            "address": "Nakagyo Ward",
            "verified_days_ago": 35,
            "activity": {
                "name": "Pontocho Alley Dinner",
                "description": "A reserved counter seat at a small family-run restaurant.",
                "tags": ["food", "local", "culture"],
                "price": 35.0,
                "duration": 90,
                "effort": 1,
                "indoor": True,
                "wheelchair": None,
                "iconic": False,
                "popularity": 0.6,
                "opening_hours": {"mon": "17:00-22:00", "tue": "17:00-22:00", "wed": "17:00-22:00", "thu": "17:00-22:00", "fri": "17:00-22:00", "sat": "17:00-22:00", "sun": "17:00-22:00"},
                "access_chain": {
                    "transport_stop": {"status": "verified", "detail": "Gion-Shijo Station, 5 minutes."},
                    "path": {"status": "limited", "detail": "Narrow alley with uneven paving."},
                    "entrance": {"status": "unknown", "detail": "Restaurant entrances vary; ask ahead."},
                    "experience_area": {"status": "reported", "detail": "Counter seating only at this restaurant."},
                },
                "verified_days_ago": 35,
            },
        },
        {
            "name": "Kyoto Station Sky Garden",
            "category": "viewpoint",
            "description": "Free rooftop terrace above the station concourse.",
            "lat": 34.9855,
            "lon": 135.7588,
            "address": "Shimogyo Ward",
            "verified_days_ago": 10,
            "activity": {
                "name": "Kyoto Station Rooftop View",
                "description": "Take the lifts to the sky garden for a free city view.",
                "tags": ["photography", "budget_travel", "relaxation"],
                "price": 0.0,
                "duration": 45,
                "effort": 1,
                "indoor": False,
                "wheelchair": True,
                "iconic": False,
                "popularity": 0.5,
                "opening_hours": {"mon": "10:00-22:00", "tue": "10:00-22:00", "wed": "10:00-22:00", "thu": "10:00-22:00", "fri": "10:00-22:00", "sat": "10:00-22:00", "sun": "10:00-22:00"},
                "access_chain": {
                    "transport_stop": {"status": "verified", "detail": "Kyoto Station, step-free throughout."},
                    "path": {"status": "verified", "detail": "Lifts and level concourse."},
                    "entrance": {"status": "verified", "detail": "Free step-free access."},
                    "experience_area": {"status": "verified", "detail": "Rooftop is level."},
                    "facilities": {"status": "verified", "detail": "Accessible toilets on the concourse."},
                },
                "verified_days_ago": 10,
            },
        },
    ]

    activities: dict[str, Activity] = {}
    for spec in specs:
        activity_spec = spec.pop("activity")
        place = _mk_place(db, destination, **spec)
        activity = _mk_activity(db, destination, place, **activity_spec)
        activities[activity.name] = activity
    return activities


def _lisbon_catalog(db: Session, destination: Destination) -> dict[str, Activity]:
    specs = [
        {
            "name": "Alfama",
            "category": "neighbourhood",
            "description": "Steep lanes below the castle, best walked without a plan.",
            "lat": 38.7110,
            "lon": -9.1300,
            "fragile": True,
            "respect_note": "Residents live in these lanes; keep noise down after dusk.",
            "verified_days_ago": 20,
            "activity": {
                "name": "Alfama Lanes Walk",
                "description": "A quiet-morning loop through stairways and small squares.",
                "tags": ["local", "history", "photography", "culture"],
                "price": 0.0,
                "duration": 90,
                "effort": 3,
                "indoor": False,
                "wheelchair": False,
                "iconic": True,
                "popularity": 0.85,
                "opening_hours": {"mon": "24 hours", "tue": "24 hours", "wed": "24 hours", "thu": "24 hours", "fri": "24 hours", "sat": "24 hours", "sun": "24 hours"},
                "verified_days_ago": 20,
            },
        },
        {
            "name": "Time Out Market",
            "category": "market",
            "description": "Food hall under the old market ironwork.",
            "lat": 38.7070,
            "lon": -9.1450,
            "verified_days_ago": 15,
            "activity": {
                "name": "Time Out Market Lunch",
                "description": "Pick three small plates from different counters.",
                "tags": ["food", "market", "local"],
                "price": 20.0,
                "duration": 75,
                "effort": 1,
                "indoor": True,
                "wheelchair": True,
                "iconic": True,
                "popularity": 0.8,
                "opening_hours": {"mon": "10:00-22:00", "tue": "10:00-22:00", "wed": "10:00-22:00", "thu": "10:00-22:00", "fri": "10:00-23:00", "sat": "10:00-23:00", "sun": "10:00-22:00"},
                "verified_days_ago": 15,
            },
        },
        {
            "name": "Belém Tower",
            "category": "monument",
            "description": "Manueline tower on the river at the western edge.",
            "lat": 38.6916,
            "lon": -9.2160,
            "verified_days_ago": 45,
            "activity": {
                "name": "Belém Riverfront Morning",
                "description": "Tower exteriors, the monument gardens and a riverside coffee.",
                "tags": ["history", "photography", "culture"],
                "price": 8.0,
                "duration": 120,
                "effort": 2,
                "indoor": False,
                "wheelchair": True,
                "iconic": True,
                "popularity": 0.9,
                "opening_hours": {"mon": "closed", "tue": "10:00-17:30", "wed": "10:00-17:30", "thu": "10:00-17:30", "fri": "10:00-17:30", "sat": "10:00-17:30", "sun": "10:00-17:30"},
                "verified_days_ago": 45,
            },
        },
        {
            "name": "LX Factory",
            "category": "market",
            "description": "Converted industrial complex of bookshops and studios.",
            "lat": 38.7030,
            "lon": -9.1780,
            "verified_days_ago": 25,
            "activity": {
                "name": "LX Factory Browse",
                "description": "Independent bookshops, print studios and a rooftop bar.",
                "tags": ["shopping", "culture", "local", "food"],
                "price": 0.0,
                "duration": 90,
                "effort": 1,
                "indoor": False,
                "wheelchair": True,
                "iconic": False,
                "popularity": 0.6,
                "opening_hours": {"mon": "10:00-20:00", "tue": "10:00-20:00", "wed": "10:00-20:00", "thu": "10:00-20:00", "fri": "10:00-20:00", "sat": "10:00-20:00", "sun": "10:00-20:00"},
                "verified_days_ago": 25,
            },
        },
        {
            "name": "Tram 28 Route",
            "category": "transport",
            "description": "The classic yellow tram over the hills.",
            "lat": 38.7130,
            "lon": -9.1390,
            "verified_days_ago": 30,
            "activity": {
                "name": "Tram 28 End-to-End",
                "description": "Ride the full route early to avoid the crush.",
                "tags": ["local", "photography", "budget_travel"],
                "price": 3.0,
                "duration": 60,
                "effort": 1,
                "indoor": True,
                "wheelchair": False,
                "iconic": True,
                "popularity": 0.85,
                "opening_hours": {"mon": "06:00-23:00", "tue": "06:00-23:00", "wed": "06:00-23:00", "thu": "06:00-23:00", "fri": "06:00-23:00", "sat": "06:00-23:00", "sun": "06:00-23:00"},
                "verified_days_ago": 30,
            },
        },
        {
            "name": "Miradouro da Graça",
            "category": "viewpoint",
            "description": "Terrace view over the castle and river.",
            "lat": 38.7169,
            "lon": -9.1315,
            "verified_days_ago": 40,
            "activity": {
                "name": "Graça Sunset View",
                "description": "Arrive an hour before sunset with a drink from the kiosk.",
                "tags": ["photography", "relaxation", "local"],
                "price": 0.0,
                "duration": 60,
                "effort": 2,
                "indoor": False,
                "wheelchair": True,
                "iconic": False,
                "popularity": 0.65,
                "opening_hours": {"mon": "24 hours", "tue": "24 hours", "wed": "24 hours", "thu": "24 hours", "fri": "24 hours", "sat": "24 hours", "sun": "24 hours"},
                "verified_days_ago": 40,
            },
        },
        {
            "name": "National Tile Museum",
            "category": "museum",
            "description": "Azulejo panels in a former convent.",
            "lat": 38.7250,
            "lon": -9.1140,
            "verified_days_ago": 18,
            "activity": {
                "name": "Tile Museum Visit",
                "description": "Five centuries of azulejo in a quiet convent cloister.",
                "tags": ["culture", "history", "art"],
                "price": 8.0,
                "duration": 90,
                "effort": 1,
                "indoor": True,
                "wheelchair": True,
                "iconic": False,
                "popularity": 0.5,
                "opening_hours": {"mon": "closed", "tue": "10:00-18:00", "wed": "10:00-18:00", "thu": "10:00-18:00", "fri": "10:00-18:00", "sat": "10:00-18:00", "sun": "10:00-18:00"},
                "verified_days_ago": 18,
            },
        },
    ]
    activities: dict[str, Activity] = {}
    for spec in specs:
        activity_spec = spec.pop("activity")
        place = _mk_place(db, destination, **spec)
        activity = _mk_activity(db, destination, place, **activity_spec)
        activities[activity.name] = activity
    return activities


def _reykjavik_catalog(db: Session, destination: Destination) -> dict[str, Activity]:
    specs = [
        {
            "name": "Hallgrímskirkja",
            "category": "church",
            "description": "Concrete church with a lift to the tower view.",
            "lat": 64.1417,
            "lon": -21.9266,
            "verified_days_ago": 200,
            "activity": {
                "name": "Hallgrímskirkja Tower View",
                "description": "Lift to the tower for the rooftops of the city.",
                "tags": ["culture", "photography", "history"],
                "price": 9.0,
                "duration": 45,
                "effort": 1,
                "indoor": True,
                "wheelchair": True,
                "iconic": True,
                "popularity": 0.9,
                "opening_hours": {"mon": "09:00-21:00", "tue": "09:00-21:00", "wed": "09:00-21:00", "thu": "09:00-21:00", "fri": "09:00-21:00", "sat": "09:00-21:00", "sun": "09:00-21:00"},
                "verified_days_ago": 200,
            },
        },
        {
            "name": "Blue Lagoon",
            "category": "spa",
            "description": "Geothermal spa in a lava field.",
            "lat": 63.8804,
            "lon": -22.4495,
            "verified_days_ago": 210,
            "activity": {
                "name": "Blue Lagoon Soak",
                "description": "A timed-entry soak; worth it once, book ahead.",
                "tags": ["relaxation", "luxury", "nature"],
                "price": 65.0,
                "duration": 150,
                "effort": 1,
                "indoor": False,
                "wheelchair": True,
                "iconic": True,
                "popularity": 0.95,
                "opening_hours": {"mon": "08:00-22:00", "tue": "08:00-22:00", "wed": "08:00-22:00", "thu": "08:00-22:00", "fri": "08:00-22:00", "sat": "08:00-22:00", "sun": "08:00-22:00"},
                "verified_days_ago": 210,
            },
        },
        {
            "name": "Golden Circle",
            "category": "nature",
            "description": "Þingvellir, Geysir and Gullfoss in one loop.",
            "lat": 64.3271,
            "lon": -20.1199,
            "verified_days_ago": 195,
            "activity": {
                "name": "Golden Circle Drive",
                "description": "A self-drive loop with short walks at each stop.",
                "tags": ["nature", "adventure", "outdoor", "hiking"],
                "price": 25.0,
                "duration": 300,
                "effort": 3,
                "indoor": False,
                "wheelchair": True,
                "iconic": True,
                "popularity": 0.9,
                "verified_days_ago": 195,
            },
        },
        {
            "name": "Old Harbour",
            "category": "food",
            "description": "Fishing harbour turned food-walk district.",
            "lat": 64.1500,
            "lon": -21.9400,
            "verified_days_ago": 190,
            "activity": {
                "name": "Harbour Food Walk",
                "description": "Three stops: lobster soup, rye ice cream, a bakery.",
                "tags": ["food", "local", "market"],
                "price": 30.0,
                "duration": 120,
                "effort": 1,
                "indoor": False,
                "wheelchair": True,
                "iconic": False,
                "popularity": 0.6,
                "verified_days_ago": 190,
            },
        },
        {
            "name": "Grótta Lighthouse",
            "category": "viewpoint",
            "description": "Tidal causeway and lighthouse on the city edge.",
            "lat": 64.1630,
            "lon": -22.0220,
            "verified_days_ago": 205,
            "activity": {
                "name": "Grótta Northern Lights Watch",
                "description": "A guided night walk to the lighthouse; no aurora guarantee.",
                "tags": ["nature", "photography", "outdoor", "adventure"],
                "price": 0.0,
                "duration": 120,
                "effort": 2,
                "indoor": False,
                "wheelchair": False,
                "iconic": False,
                "popularity": 0.55,
                "verified_days_ago": 205,
            },
        },
    ]
    activities: dict[str, Activity] = {}
    for spec in specs:
        activity_spec = spec.pop("activity")
        place = _mk_place(db, destination, **spec)
        activity = _mk_activity(db, destination, place, **activity_spec)
        activities[activity.name] = activity
    return activities


# ---------------------------------------------------------------------------
# Trips
# ---------------------------------------------------------------------------


def _add_member(
    db: Session,
    trip: Trip,
    user: User,
    *,
    role: str,
    budget_limit: float | None,
    accessibility: list[str] | None = None,
    invited_by: str | None = None,
) -> TripMember:
    member = TripMember(
        trip_id=trip.id,
        user_id=user.id,
        display_name=user.display_name,
        role=role,
        status="active",
        budget_limit=budget_limit,
        accessibility_needs=accessibility or [],
        invited_by=invited_by,
    )
    db.add(member)
    db.flush()
    return member


def _add_pulse(
    db: Session,
    trip: Trip,
    user: User,
    *,
    pulse_date: date,
    energy: int,
    interests: list[str],
    available_minutes: int | None,
    budget_comfort: int,
    radius_km: float | None,
    activity_prefs: list[str] | None = None,
    note: str | None = None,
) -> TripPulse:
    pulse = TripPulse(
        trip_id=trip.id,
        user_id=user.id,
        pulse_date=pulse_date,
        energy=energy,
        interests=interests,
        available_minutes=available_minutes,
        budget_comfort=budget_comfort,
        radius_km=radius_km,
        activity_prefs=activity_prefs or [],
        note=note,
    )
    db.add(pulse)
    db.flush()
    return pulse


def _add_item(
    db: Session,
    itinerary: Itinerary,
    trip: Trip,
    *,
    user_id: str,
    day: date,
    start_time: str,
    title: str,
    activity: Activity,
    duration_minutes: int,
    cost: float,
    sort_order: int,
    protected: bool = False,
    notes: str | None = None,
) -> ItineraryItem:
    start_hour, start_minute = map(int, start_time.split(":"))
    total = start_hour * 60 + start_minute + duration_minutes
    end_time = f"{(total // 60) % 24:02d}:{total % 60:02d}"
    item = ItineraryItem(
        itinerary_id=itinerary.id,
        trip_id=trip.id,
        day=day,
        start_time=start_time,
        end_time=end_time,
        title=title,
        activity_id=activity.id,
        place_id=activity.place_id,
        notes=notes,
        cost_estimate=cost,
        status="confirmed",
        is_protected=protected,
        created_by=user_id,
        sort_order=sort_order,
    )
    db.add(item)
    db.flush()
    return item


def _add_expense(
    db: Session,
    trip: Trip,
    users: list[User],
    *,
    payer: User,
    title: str,
    category: str,
    amount: float,
    incurred_on: date,
    notes: str | None = None,
) -> Expense:
    expense = Expense(
        trip_id=trip.id,
        title=title,
        category=category,
        amount=amount,
        currency=trip.currency,
        paid_by=payer.id,
        incurred_on=incurred_on,
        notes=notes,
        created_by=payer.id,
    )
    db.add(expense)
    db.flush()
    rows = resolve_shares(
        amount,
        [{"user_id": user.id} for user in users],
        "equal",
    )
    for row in rows:
        db.add(
            ExpenseParticipant(
                expense_id=expense.id,
                user_id=row["user_id"],
                weight=row["weight"],
                share_amount=row["share_amount"],
            )
        )
    return expense


def _add_place_report(
    db: Session,
    *,
    activity: Activity,
    trip: Trip | None,
    reporter: User,
    category: str,
    value: dict,
    note: str | None,
    observed_at: datetime,
    source_type: str = "community",
    confidence: float = 0.6,
    verified: bool = False,
) -> PlaceReport:
    report = PlaceReport(
        activity_id=activity.id,
        place_id=activity.place_id,
        trip_id=trip.id if trip else None,
        category=category,
        value=value,
        note=note,
        observed_at=observed_at,
        source_type=source_type,
        confidence=confidence,
        verified=verified,
        reporter_id=reporter.id,
    )
    db.add(report)
    db.flush()
    return report


def _persist_recommendation_batch(
    db: Session,
    trip: Trip,
    members: list[TripMember],
    user: User,
    *,
    mode: str,
    for_date: date,
) -> RecommendationBatch | None:
    result = generate_recommendations(
        db, trip, members, mode=mode, for_date=for_date, limit=6
    )
    if result.get("error") or not result.get("items"):
        return None
    meta = {
        **result["meta"],
        "mode_meta": result["mode_meta"],
        "clarifying_question": result.get("clarifying_question"),
        "exclusion_reasons": result.get("exclusion_reasons", {}),
        "target_member": result["target"].label if result.get("target") else None,
    }
    batch = RecommendationBatch(
        trip_id=trip.id,
        mode=mode,
        for_date=for_date,
        model_version=ENGINE_VERSION,
        meta=meta,
        created_by=user.id,
    )
    db.add(batch)
    db.flush()
    for rank, ranked in enumerate(result["items"], start=1):
        db.add(
            Recommendation(
                batch_id=batch.id,
                trip_id=trip.id,
                activity_id=ranked.activity.id,
                rank=rank,
                score=ranked.score,
                average_fit=ranked.average_fit,
                minimum_fit=ranked.minimum_fit,
                fairness_spread=ranked.fairness_spread,
                novelty=ranked.novelty,
                penalties=ranked.penalties,
                explanation=ranked.explanation,
                status="suggested",
            )
        )
    audit(
        db,
        action="engine.recommend",
        entity_type="recommendation_batch",
        entity_id=batch.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"mode": mode, "for_date": for_date.isoformat()},
    )
    return batch


def seed_if_needed(db: Session, force: bool = False) -> dict:
    """Populate the demo dataset once. Safe to call on every startup."""
    if settings.is_production:
        raise RuntimeError("Demo seeding is strictly prohibited in production.")
    if not force and not settings.auto_seed:
        return {"seeded": False, "reason": "auto-seeding is disabled"}
    if db.query(User).first():
        return {"seeded": False, "reason": "database already contains users"}

    today = date.today()

    # --- users -----------------------------------------------------------
    users = {}
    for spec in USER_BLUEPRINTS:
        users[spec["email"].split("@")[0]] = _seed_user(db, spec)
    mira = users["mira"]
    jonas = users["jonas"]
    aiko = users["aiko"]
    leo = users["leo"]
    noor = users["noor"]
    mateo = users["mateo"]

    # --- destinations and catalog ---------------------------------------
    kyoto = Destination(
        slug="kyoto",
        name="Kyoto",
        country="Japan",
        region="Kansai",
        description=(
            "Temple gardens, market mornings and a city that rewards slow walking. "
            "SAFAR's Kyoto entries are curated seed data, not live provider feeds."
        ),
        lat=35.0116,
        lon=135.7681,
        tags=["culture", "food", "history", "nature", "photography"],
        best_months=[3, 4, 10, 11],
        source_type="seed_catalog",
        source_name="SAFAR curated catalog",
    )
    lisbon = Destination(
        slug="lisbon",
        name="Lisbon",
        country="Portugal",
        region="Lisboa",
        description=(
            "Hills, tiled facades and a river that keeps reappearing at the end of streets."
        ),
        lat=38.7223,
        lon=-9.1393,
        tags=["food", "culture", "photography", "local"],
        best_months=[4, 5, 6, 9, 10],
        source_type="seed_catalog",
        source_name="SAFAR curated catalog",
    )
    reykjavik = Destination(
        slug="reykjavik",
        name="Reykjavik",
        country="Iceland",
        region="Capital Region",
        description="A small capital at the edge of lava fields and long light.",
        lat=64.1466,
        lon=-21.9426,
        tags=["nature", "adventure", "outdoor", "photography"],
        best_months=[6, 7, 8, 9, 2, 3],
        source_type="seed_catalog",
        source_name="SAFAR curated catalog",
    )
    db.add_all([kyoto, lisbon, reykjavik])
    db.flush()

    kyoto_activities = _kyoto_catalog(db, kyoto)
    lisbon_activities = _lisbon_catalog(db, lisbon)
    reykjavik_activities = _reykjavik_catalog(db, reykjavik)

    # --- Kyoto trip ------------------------------------------------------
    kyoto_trip = Trip(
        name="Kyoto in Slow Bloom",
        description=(
            "Seven days built around light, tea and one market morning. "
            "The group decides; the engine only recommends."
        ),
        destination_id=kyoto.id,
        destination_name="Kyoto, Japan",
        start_date=today - timedelta(days=2),
        end_date=today + timedelta(days=4),
        group_size=4,
        budget_total=3200.0,
        currency="EUR",
        base_lat=35.0037,
        base_lon=135.7752,
        status="active",
        privacy="private",
        created_by=mira.id,
    )
    db.add(kyoto_trip)
    db.flush()

    _add_member(db, kyoto_trip, mira, role="owner", budget_limit=120.0)
    _add_member(db, kyoto_trip, jonas, role="admin", budget_limit=60.0)
    _add_member(
        db,
        kyoto_trip,
        aiko,
        role="member",
        budget_limit=80.0,
        accessibility=["step-free access"],
    )
    _add_member(db, kyoto_trip, leo, role="member", budget_limit=150.0)

    # Pulses for today. Leo deliberately has none so the engine can surface a
    # real clarifying question instead of inventing his preferences.
    _add_pulse(
        db, kyoto_trip, mira,
        pulse_date=today, energy=4, interests=["photography", "culture", "food"],
        available_minutes=480, budget_comfort=4, radius_km=20,
        activity_prefs=["slow mornings"], note="Hoping for good light in the gardens.",
    )
    _add_pulse(
        db, kyoto_trip, jonas,
        pulse_date=today, energy=3, interests=["adventure", "nature"],
        available_minutes=360, budget_comfort=3, radius_km=25,
        activity_prefs=["outdoors"], note="Knees are fine today, up for a climb.",
    )
    _add_pulse(
        db, kyoto_trip, aiko,
        pulse_date=today, energy=2, interests=["food", "relaxation"],
        available_minutes=240, budget_comfort=2, radius_km=8,
        activity_prefs=["seated experiences"], note="Low energy — nothing with stairs, please.",
    )

    itinerary = Itinerary(trip_id=kyoto_trip.id, confirmed_version=0)
    db.add(itinerary)
    db.flush()

    day_minus_2 = today - timedelta(days=2)
    day_minus_1 = today - timedelta(days=1)
    day_plus_1 = today + timedelta(days=1)
    day_plus_2 = today + timedelta(days=2)

    fushimi = kyoto_activities["Fushimi Inari Torii Walk"]
    nishiki = kyoto_activities["Nishiki Market Morning Graze"]
    kiyomizu = kyoto_activities["Kiyomizu-dera at Opening"]
    camellia = kyoto_activities["Tea ceremony at Camellia"]
    arashiyama = kyoto_activities["Arashiyama Bamboo Grove"]
    okochi = kyoto_activities["Okochi Sanso Garden & Tea"]
    philosophy = kyoto_activities["Philosopher's Path Walk"]
    sake = kyoto_activities["Fushimi Sake District Tasting"]
    imperial = kyoto_activities["Imperial Palace Garden Loop"]
    gion = kyoto_activities["Gion Evening Walk"]
    railway = kyoto_activities["Kyoto Railway Museum"]
    rooftop = kyoto_activities["Kyoto Station Rooftop View"]

    _add_item(
        db, itinerary, kyoto_trip, user_id=mira.id, day=day_minus_2,
        start_time="08:00", title="Fushimi Inari Torii Walk", activity=fushimi,
        duration_minutes=120, cost=0.0, sort_order=1,
        notes="Early start agreed in the pact; lower gates first.",
    )
    _add_item(
        db, itinerary, kyoto_trip, user_id=aiko.id, day=day_minus_2,
        start_time="11:30", title="Nishiki Market Morning Graze", activity=nishiki,
        duration_minutes=90, cost=0.0, sort_order=2,
        notes="Vegetarian stalls marked in the shared note.",
    )
    _add_item(
        db, itinerary, kyoto_trip, user_id=mira.id, day=day_minus_1,
        start_time="08:00", title="Kiyomizu-dera at Opening", activity=kiyomizu,
        duration_minutes=90, cost=4.0, sort_order=1,
    )
    _add_item(
        db, itinerary, kyoto_trip, user_id=aiko.id, day=day_minus_1,
        start_time="11:00", title="Tea ceremony at Camellia", activity=camellia,
        duration_minutes=75, cost=45.0, sort_order=2, protected=True,
        notes="Booked and protected: a Journey Pact must-do.",
    )
    _add_item(
        db, itinerary, kyoto_trip, user_id=jonas.id, day=today,
        start_time="09:00", title="Arashiyama Bamboo Grove", activity=arashiyama,
        duration_minutes=60, cost=0.0, sort_order=1,
    )
    _add_item(
        db, itinerary, kyoto_trip, user_id=leo.id, day=today,
        start_time="12:30", title="Kyoto Station Rooftop View", activity=rooftop,
        duration_minutes=45, cost=0.0, sort_order=2,
        notes="Backup meeting point if the bamboo grove is packed.",
    )
    _add_item(
        db, itinerary, kyoto_trip, user_id=aiko.id, day=day_plus_1,
        start_time="10:00", title="Philosopher's Path Walk", activity=philosophy,
        duration_minutes=45, cost=0.0, sort_order=1,
    )
    _add_item(
        db, itinerary, kyoto_trip, user_id=jonas.id, day=day_plus_2,
        start_time="11:00", title="Fushimi Sake District Tasting", activity=sake,
        duration_minutes=90, cost=15.0, sort_order=1,
    )

    record_itinerary_version(
        db, itinerary, user_id=mira.id, note="Baseline agreed through group voting"
    )
    db.flush()

    pact = JourneyPact(
        trip_id=kyoto_trip.id,
        must_do=["Tea ceremony at Camellia", "Nishiki Market Morning Graze"],
        flexible=["Arashiyama Bamboo Grove", "Gion Evening Walk"],
        individual_limits={
            mira.id: {"budget_limit": 120.0, "note": "private"},
            jonas.id: {"budget_limit": 60.0, "note": "private"},
            aiko.id: {"budget_limit": 80.0, "note": "private"},
            leo.id: {"budget_limit": 150.0, "note": "private"},
        },
        confirmed_times={
            "Tea ceremony at Camellia": "11:00",
            "Fushimi Inari Torii Walk": "08:00",
        },
        exceptions=[],
        created_by=mira.id,
    )
    db.add(pact)

    proposal = ItineraryProposal(
        trip_id=kyoto_trip.id,
        kind="add_activity",
        title="Add Okochi Sanso Garden & Tea",
        summary=(
            "A quiet hillside garden with tea included. Far from the base, so the "
            "engine would only rank it when travel time is acceptable."
        ),
        payload={
            "activity_id": okochi.id,
            "day": day_plus_1.isoformat(),
            "start_time": "14:30",
            "notes": "Could pair with the Philosopher's Path walk.",
        },
        status="open",
        target_day=day_plus_1,
        created_by=leo.id,
    )
    db.add(proposal)
    db.flush()

    db.add_all(
        [
            Vote(proposal_id=proposal.id, user_id=mira.id, value="yes", comment="The garden light is worth it."),
            Vote(proposal_id=proposal.id, user_id=jonas.id, value="yes", comment="Happy to walk."),
            Vote(proposal_id=proposal.id, user_id=aiko.id, value="no", comment="Too far for my energy today."),
            Vote(proposal_id=proposal.id, user_id=leo.id, value="yes", comment="I proposed it."),
        ]
    )

    db.add(
        JourneyCapsule(
            trip_id=kyoto_trip.id,
            snapshot={
                "plan_version": itinerary.confirmed_version,
                "destination": kyoto_trip.destination_name,
                "members": [user.display_name for user in (mira, jonas, aiko, leo)],
                "must_do": ["Tea ceremony at Camellia", "Nishiki Market Morning Graze"],
                "protected_items": ["Tea ceremony at Camellia"],
                "currency": kyoto_trip.currency,
                "budget_total": kyoto_trip.budget_total,
            },
            stale_after=utcnow() + timedelta(days=2),
            created_by=mira.id,
        )
    )

    db.add_all(
        [
            PlannerTask(
                trip_id=kyoto_trip.id,
                title="Confirm tea ceremony headcount",
                description="Camellia needs final numbers 24 hours ahead.",
                assignee_id=aiko.id,
                status="done",
                created_by=mira.id,
            ),
            PlannerTask(
                trip_id=kyoto_trip.id,
                title="Buy Arashiyama tram tickets",
                description="Buy four returns for tomorrow morning.",
                assignee_id=jonas.id,
                status="open",
                created_by=jonas.id,
            ),
            PlannerTask(
                trip_id=kyoto_trip.id,
                title="Pick a rainy-day museum",
                description="If the bamboo grove is wet, switch to the Railway Museum.",
                assignee_id=leo.id,
                status="open",
                created_by=mira.id,
            ),
        ]
    )

    db.add(
        TripBranch(
            trip_id=kyoto_trip.id,
            name="Garden wanderers",
            member_ids=[aiko.id, leo.id],
            activity_id=okochi.id,
            reunion_at=datetime.combine(day_plus_1, datetime.min.time()) + timedelta(hours=16, minutes=30),
            reunion_place="Philosopher's Path north bench",
            status="planned",
            created_by=aiko.id,
        )
    )

    db.add(
        Shadowplan(
            trip_id=kyoto_trip.id,
            itinerary_item_id=(
                db.query(ItineraryItem)
                .filter(ItineraryItem.trip_id == kyoto_trip.id, ItineraryItem.activity_id == philosophy.id)
                .first()
                .id
            ),
            backup_activity_id=imperial.id,
            notes="If it rains, swap the canal walk for the Imperial Palace garden loop.",
            readiness={"weather": "unknown", "reservation": "not required", "accessibility": "step-free"},
            created_by=mira.id,
        )
    )

    db.add(
        MaterialWatch(
            trip_id=kyoto_trip.id,
            activity_id=nishiki.id,
            field="opening_hours",
            last_value=dict(nishiki.opening_hours or {}),
            status="watching",
        )
    )

    db.add(
        TripInvitation(
            trip_id=kyoto_trip.id,
            token="safar-kyoto-invite-demo",
            email=None,
            role="member",
            scope="full",
            created_by=mira.id,
            expires_at=utcnow() + timedelta(days=14),
        )
    )

    # --- Memories --------------------------------------------------------
    memory_one = TripMemory(
        trip_id=kyoto_trip.id,
        user_id=mira.id,
        kind="text",
        text_content="The first torii gate at 8am, still wet from rain, and nobody else on the path.",
        captured_at=datetime.combine(day_minus_2, datetime.min.time()) + timedelta(hours=8, minutes=40),
        visibility="trip",
    )
    memory_two = TripMemory(
        trip_id=kyoto_trip.id,
        user_id=jonas.id,
        kind="text",
        text_content="Aiko found the only pickle stall that labels everything vegetarian. Trip saved.",
        captured_at=datetime.combine(day_minus_2, datetime.min.time()) + timedelta(hours=12, minutes=10),
        visibility="trip",
    )
    memory_three = TripMemory(
        trip_id=kyoto_trip.id,
        user_id=aiko.id,
        kind="text",
        text_content="Tea ceremony notes: warm the bowl first; the sweet comes before the tea.",
        captured_at=datetime.combine(day_minus_1, datetime.min.time()) + timedelta(hours=11, minutes=50),
        visibility="trip",
    )
    memory_private = TripMemory(
        trip_id=kyoto_trip.id,
        user_id=mira.id,
        kind="text",
        text_content="Private: I want one completely unplanned afternoon. Still deciding how to say it.",
        captured_at=datetime.combine(day_minus_1, datetime.min.time()) + timedelta(hours=20),
        visibility="private",
    )
    db.add_all([memory_one, memory_two, memory_three, memory_private])
    db.flush()
    db.add(
        MemoryPermission(memory_id=memory_private.id, user_id=jonas.id, can_view=True)
    )

    # --- Place intelligence ---------------------------------------------
    for offset in (7, 14, 21):
        day = today - timedelta(days=offset)
        for hour, score in ((11, 0.82), (15, 0.64), (19, 0.4)):
            _add_place_report(
                db,
                activity=nishiki,
                trip=kyoto_trip,
                reporter=[mira, jonas, aiko][offset % 3],
                category="crowd",
                value={"score": score, "level": "high" if score >= 0.8 else "moderate"},
                note="Counted people per minute at the east entrance.",
                observed_at=datetime.combine(day, datetime.min.time()) + timedelta(hours=hour),
                confidence=0.65,
            )

    _add_place_report(
        db,
        activity=nishiki,
        trip=kyoto_trip,
        reporter=mira,
        category="hours",
        value={"open": "09:30", "close": "18:00"},
        note="Verified against the market association notice board.",
        observed_at=_ago(12),
        source_type="official",
        confidence=0.95,
        verified=True,
    )
    _add_place_report(
        db,
        activity=nishiki,
        trip=kyoto_trip,
        reporter=aiko,
        category="queue",
        value={"wait_minutes": 20},
        note="Stall 12 had a 20-minute line at lunch; the rest were quick.",
        observed_at=_ago(1, hours=3),
    )
    _add_place_report(
        db,
        activity=camellia,
        trip=kyoto_trip,
        reporter=aiko,
        category="accessibility",
        value={"status": "step_free", "detail": "Step-free entrance and chair seating available."},
        note="Confirmed with the host when booking.",
        observed_at=_ago(4),
        confidence=0.85,
    )
    _add_place_report(
        db,
        activity=arashiyama,
        trip=kyoto_trip,
        reporter=jonas,
        category="closure",
        value={"closed": True, "reason": "Storm clean-up on the riverside section"},
        note="The grove itself was open; the riverside path was taped off.",
        observed_at=_ago(2),
        confidence=0.7,
    )
    _add_place_report(
        db,
        activity=kiyomizu,
        trip=kyoto_trip,
        reporter=leo,
        category="price",
        value={"adult": 4.0, "currency": "EUR"},
        note="Entrance fee unchanged.",
        observed_at=_ago(5),
        confidence=0.8,
    )

    # --- Ground request --------------------------------------------------
    ground_request = GroundRequest(
        trip_id=kyoto_trip.id,
        place_id=arashiyama.place_id,
        activity_id=arashiyama.id,
        question="Is the bamboo grove path usable with a walking aid after the storm?",
        requested_by=aiko.id,
        status="answered",
    )
    db.add(ground_request)
    db.flush()
    db.add(
        GroundResponse(
            request_id=ground_request.id,
            contributor_id=noor.id,
            observation=(
                "The main grove path is clear and level. The riverside spur is still taped "
                "off; skip it and return via the main street."
            ),
            observed_at=_ago(1, hours=6),
            confidence=0.6,
            verified=False,
        )
    )

    # --- Expenses --------------------------------------------------------
    _add_expense(
        db, kyoto_trip, [mira, jonas, aiko, leo],
        payer=mira, title="Welcome dinner at Pontocho", category="food",
        amount=148.50, incurred_on=day_minus_2,
        notes="Counter seats; vegetarian options confirmed.",
    )
    _add_expense(
        db, kyoto_trip, [mira, jonas, aiko, leo],
        payer=jonas, title="Arashiyama tram returns", category="transport",
        amount=96.00, incurred_on=day_minus_1,
    )
    _add_expense(
        db, kyoto_trip, [mira, jonas, aiko, leo],
        payer=aiko, title="Market snacks and tea", category="food",
        amount=42.30, incurred_on=today,
    )

    # --- Circles, contributors, missions --------------------------------
    circles = ensure_seed_circles(db, mira.id)
    db.flush()
    circle_map = {circle.slug: circle for circle in circles}
    for circle in circles:
        for user in (mira, jonas, aiko, leo):
            db.add(CircleMember(circle_id=circle.id, user_id=user.id))
    db.flush()
    db.add_all(
        [
            CirclePost(
                circle_id=circle_map["slow-travel"].id,
                user_id=aiko.id,
                title="Three benches worth planning around",
                body="The Imperial Palace garden has the best shaded benches before noon. Bring a book, not a checklist.",
            ),
            CirclePost(
                circle_id=circle_map["food-first"].id,
                user_id=jonas.id,
                title="Market strategy: start at the west end",
                body="Everyone enters at the east end and queues. Start west, finish east with the crowd.",
                activity_id=nishiki.id,
            ),
            CirclePost(
                circle_id=circle_map["trail-and-view"].id,
                user_id=leo.id,
                title="Daimonji is worth it — but not in sandals",
                body="The trailhead near the cemetery path is unmarked. Give yourself 90 minutes up and take the bus home.",
                activity_id=kyoto_activities["Mount Daimonji Sunset Hike"].id,
            ),
        ]
    )

    db.add(
        LocalContributor(
            user_id=noor.id,
            destination_id=kyoto.id,
            bio="Kyoto local, garden volunteer and tea student. Answers about access and quiet hours.",
            expertise=["gardens", "tea", "accessibility", "quiet corners"],
            verified=True,
            accepts_requests=True,
        )
    )
    db.add(
        LocalContributor(
            user_id=mateo.id,
            destination_id=lisbon.id,
            bio="Lisbon local who commutes by ferry. Knows which viewpoint is worth the hill.",
            expertise=["viewpoints", "ferries", "fado", "food"],
            verified=True,
            accepts_requests=True,
        )
    )

    missions = generate_missions(db, kyoto_trip, mira.id)
    db.flush()
    if missions:
        db.add(UserMission(mission_id=missions[0].id, user_id=aiko.id))

    db.add(
        SavedInspiration(
            user_id=aiko.id,
            trip_id=kyoto_trip.id,
            source_type="text",
            content=(
                "I want a quiet garden, one tea ceremony, and a market morning. "
                "No more than three things a day."
            ),
            extracted={
                "keywords": ["quiet", "garden", "tea", "market"],
                "suggested_tags": ["relaxation", "culture", "food"],
                "limitations": [
                    "Parsed from text only. Image and link imports need a caption review step.",
                ],
            },
            status="processed",
        )
    )

    # --- Notifications ---------------------------------------------------
    db.add_all(
        [
            Notification(
                user_id=aiko.id,
                trip_id=kyoto_trip.id,
                kind="vote",
                title="Vote needed: Okochi Sanso Garden & Tea",
                body="Leo proposed a garden visit on the free day. Your vote is the only no so far.",
                link=f"/trips/{kyoto_trip.id}?tab=voting",
            ),
            Notification(
                user_id=jonas.id,
                trip_id=kyoto_trip.id,
                kind="material_change",
                title="Watching Nishiki Market hours",
                body="Material Change Watch is active. You will only be notified if the value changes.",
                link=f"/trips/{kyoto_trip.id}?tab=places",
            ),
            Notification(
                user_id=mira.id,
                trip_id=kyoto_trip.id,
                kind="ground",
                title="Noor answered your ground question",
                body="An unverified local observation about the Arashiyama path is available.",
                link=f"/trips/{kyoto_trip.id}?tab=places",
            ),
        ]
    )

    # --- Engine ----------------------------------------------------------
    kyoto_members = (
        db.query(TripMember).filter(TripMember.trip_id == kyoto_trip.id).all()
    )
    _persist_recommendation_batch(
        db, kyoto_trip, kyoto_members, mira, mode="everyone_wins", for_date=today
    )

    # --- Lisbon trip -----------------------------------------------------
    lisbon_trip = Trip(
        name="Lisbon, Unscheduled",
        description="A long weekend with nothing booked except the first coffee.",
        destination_id=lisbon.id,
        destination_name="Lisbon, Portugal",
        start_date=today + timedelta(days=35),
        end_date=today + timedelta(days=41),
        group_size=3,
        budget_total=2400.0,
        currency="EUR",
        base_lat=38.7139,
        base_lon=-9.1394,
        status="planning",
        privacy="private",
        created_by=jonas.id,
    )
    db.add(lisbon_trip)
    db.flush()
    _add_member(db, lisbon_trip, jonas, role="owner", budget_limit=90.0)
    _add_member(db, lisbon_trip, mira, role="admin", budget_limit=120.0)
    _add_member(db, lisbon_trip, aiko, role="member", budget_limit=80.0)

    lisbon_itinerary = Itinerary(trip_id=lisbon_trip.id, confirmed_version=0)
    db.add(lisbon_itinerary)
    db.flush()
    _add_item(
        db, lisbon_itinerary, lisbon_trip, user_id=jonas.id,
        day=lisbon_trip.start_date, start_time="16:00",
        title="Graça Sunset View", activity=lisbon_activities["Graça Sunset View"],
        duration_minutes=60, cost=0.0, sort_order=1,
    )
    _add_item(
        db, lisbon_itinerary, lisbon_trip, user_id=mira.id,
        day=lisbon_trip.start_date + timedelta(days=1), start_time="10:00",
        title="Alfama Lanes Walk", activity=lisbon_activities["Alfama Lanes Walk"],
        duration_minutes=90, cost=0.0, sort_order=1,
    )
    record_itinerary_version(
        db, lisbon_itinerary, user_id=jonas.id, note="First two anchors"
    )

    # --- Reykjavik completed trip ---------------------------------------
    reykjavik_trip = Trip(
        name="Reykjavik in Winter Light",
        description="A completed trip kept for memories, replay and the Journey Thread.",
        destination_id=reykjavik.id,
        destination_name="Reykjavik, Iceland",
        start_date=today - timedelta(days=400),
        end_date=today - timedelta(days=393),
        group_size=2,
        budget_total=2800.0,
        currency="EUR",
        base_lat=64.1466,
        base_lon=-21.9426,
        status="completed",
        privacy="private",
        created_by=mira.id,
    )
    db.add(reykjavik_trip)
    db.flush()
    _add_member(db, reykjavik_trip, mira, role="owner", budget_limit=150.0)
    _add_member(db, reykjavik_trip, jonas, role="member", budget_limit=150.0)

    blue_lagoon = reykjavik_activities["Blue Lagoon Soak"]
    db.add_all(
        [
            ActivityFeedback(
                user_id=mira.id,
                trip_id=reykjavik_trip.id,
                activity_id=blue_lagoon.id,
                sentiment="loved",
                consented=True,
            ),
            ActivityFeedback(
                user_id=jonas.id,
                trip_id=reykjavik_trip.id,
                activity_id=blue_lagoon.id,
                sentiment="would_return",
                consented=True,
            ),
            TripMemory(
                trip_id=reykjavik_trip.id,
                user_id=mira.id,
                kind="text",
                text_content="Steam on the water at 9am and nobody spoke for ten minutes.",
                captured_at=utcnow() - timedelta(days=397),
                visibility="trip",
            ),
        ]
    )
    audit(
        db,
        action="seed.completed",
        entity_type="system",
        detail={"users": len(users), "trips": 3},
    )

    db.commit()
    return {
        "seeded": True,
        "users": len(users),
        "destinations": 3,
        "activities": len(kyoto_activities) + len(lisbon_activities) + len(reykjavik_activities),
        "demo_password": DEMO_PASSWORD,
    }


def main() -> None:
    from app.db.session import Base, SessionLocal, engine
    from app.db.context import system_context

    if settings.create_schema:
        Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        with system_context(db):
            summary = seed_if_needed(db, force=True)
            print(summary)
    finally:
        db.close()


if __name__ == "__main__":
    main()
