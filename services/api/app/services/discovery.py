"""Discovery, Dream import, Serendipity matching, Circles, Missions, Respect filter."""

import re
from datetime import date
from math import sqrt

from sqlalchemy.orm import Session

from app.models import (
    Activity,
    Destination,
    ItineraryItem,
    JourneyDNA,
    Place,
    Profile,
    SavedInspiration,
    TravelCircle,
    TravellerMatch,
    Trip,
    TripMember,
    TripMission,
    User,
)
from app.db.context import system_context
from app.services.common import DNA_DIMENSIONS, normalize_tag


def _discoverable_trips(db: Session, user_id: str) -> list[Trip]:
    """Read trip metadata for a public-profile candidate inside one transaction.

    Only the matcher calls this, and only aggregate fields (destination and
    dates) are used. The result never reaches an API response.
    """
    with system_context(db):
        return (
            db.query(Trip)
            .join(TripMember, TripMember.trip_id == Trip.id)
            .filter(TripMember.user_id == user_id, Trip.deleted_at.is_(None))
            .all()
        )


def _cosine(a: dict[str, float], b: dict[str, float]) -> float:
    if not a or not b:
        return 0.0
    dot = sum(value * b.get(key, 0.0) for key, value in a.items())
    na = sqrt(sum(value * value for value in a.values()))
    nb = sqrt(sum(value * value for value in b.values()))
    return dot / (na * nb) if na and nb else 0.0


def dna_for_user(db: Session, user_id: str | None) -> dict[str, float]:
    if not user_id:
        return {dim: 5.0 for dim in DNA_DIMENSIONS}
    row = db.query(JourneyDNA).filter(JourneyDNA.user_id == user_id).first()
    if row and row.scores:
        return {dim: float(row.scores.get(dim, 5)) for dim in DNA_DIMENSIONS}
    profile = db.query(Profile).filter(Profile.user_id == user_id).first()
    scores = {dim: 5.0 for dim in DNA_DIMENSIONS}
    if profile:
        for interest in profile.interests or []:
            key = normalize_tag(interest)
            if key in scores:
                scores[key] = 8.0
    return scores


def activity_tags(activity: Activity) -> dict[str, float]:
    tags: dict[str, float] = {}
    for tag in activity.tags or []:
        key = normalize_tag(tag)
        tags[key] = tags.get(key, 0.0) + 1.0
    return tags


def search_activities(
    db: Session,
    *,
    q: str | None = None,
    destination_id: str | None = None,
    tags: list[str] | None = None,
    max_budget: float | None = None,
    max_duration: int | None = None,
    indoor: bool | None = None,
    accessible: bool = False,
    lens: str = "balanced",
    dna: dict[str, float] | None = None,
    limit: int = 40,
) -> list[dict]:
    query = db.query(Activity)
    if destination_id:
        query = query.filter(Activity.destination_id == destination_id)
    if q:
        like = f"%{q.lower()}%"
        query = query.filter(Activity.name.ilike(like) | Activity.description.ilike(like))
    activities = query.all()
    places = {place.id: place for place in db.query(Place).all()}
    destinations = {dest.id: dest for dest in db.query(Destination).all()}
    wanted = {normalize_tag(tag) for tag in (tags or [])}
    dna = dna or {}

    scored = []
    for activity in activities:
        activity_tag_map = activity_tags(activity)
        if wanted and not wanted.intersection(activity_tag_map):
            continue
        if max_budget is not None and activity.price_estimate > max_budget:
            continue
        if max_duration is not None and activity.duration_minutes > max_duration:
            continue
        if indoor is not None and activity.indoor != indoor:
            continue
        if accessible and activity.wheelchair_accessible is not True:
            # Unknown accessibility is not treated as accessible (F41 honesty).
            continue
        personal = 0.25 + 0.75 * _cosine(activity_tag_map, dna) if dna else 0.5
        scored.append(
            {
                "activity": activity,
                "place": places.get(activity.place_id),
                "destination": destinations.get(activity.destination_id),
                "personal_fit": round(personal * 100, 1),
                "tag_map": activity_tag_map,
            }
        )

    if lens == "iconic":
        scored.sort(
            key=lambda item: (
                item["activity"].iconic,
                item["activity"].popularity,
                item["personal_fit"],
            ),
            reverse=True,
        )
    elif lens == "similar":
        iconic = [item for item in scored if item["activity"].iconic]
        alternatives = [item for item in scored if not item["activity"].iconic]
        for item in alternatives:
            best = 0.0
            best_name = None
            for anchor in iconic:
                similarity = _cosine(item["tag_map"], anchor["tag_map"])
                if similarity > best:
                    best = similarity
                    best_name = anchor["activity"].name
            item["similar_to"] = best_name if best >= 0.35 else None
            item["similarity"] = round(best, 2)
        alternatives.sort(
            key=lambda item: (item.get("similarity", 0), item["personal_fit"]), reverse=True
        )
        others = [item for item in scored if not item["activity"].iconic]
        scored = others
    elif lens == "balanced":
        iconic = sorted(
            [item for item in scored if item["activity"].iconic],
            key=lambda item: item["personal_fit"],
            reverse=True,
        )
        other = sorted(
            [item for item in scored if not item["activity"].iconic],
            key=lambda item: item["personal_fit"],
            reverse=True,
        )
        mixed = []
        while iconic or other:
            if iconic:
                mixed.append(iconic.pop(0))
            if other:
                mixed.append(other.pop(0))
        scored = mixed
    else:
        scored.sort(key=lambda item: item["personal_fit"], reverse=True)

    return [
        {
            "activity": item["activity"],
            "place": item["place"],
            "destination": item["destination"],
            "personal_fit": item["personal_fit"],
            "similar_to": item.get("similar_to"),
            "similarity": item.get("similarity"),
            "respect_note": (
                item["place"].respect_note
                if item["place"] and item["place"].fragile
                else None
            ),
        }
        for item in scored[:limit]
    ]


_MONTHS = (
    "january",
    "february",
    "march",
    "april",
    "may",
    "june",
    "july",
    "august",
    "september",
    "october",
    "november",
    "december",
)

_BUDGET_PATTERN = re.compile(
    r"(?:under|below|max(?:imum)?|upto|up to|budget(?: of| around)?|around|about|less than)?\s*"
    r"(?:([€$£])\s?(\d[\d,.]*)|(\d[\d,.]*)\s?(eur|usd|gbp))",
    re.IGNORECASE,
)

_URL_PATTERN = re.compile(r"https?://[^\s<>\"']+", re.IGNORECASE)
_HASHTAG_PATTERN = re.compile(r"#([A-Za-z][\w-]{1,40})")

_MONTH_WORD = (
    r"(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|"
    r"jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|"
    r"dec(?:ember)?)"
)
_DATE_RANGE_PATTERN = re.compile(
    rf"\b(?:\d{{1,2}}\s*[-–]\s*\d{{1,2}}\s+{_MONTH_WORD}\.?\s*(?:\d{{4}})?"
    rf"|{_MONTH_WORD}\.?\s+\d{{1,2}}\s*[-–]\s*\d{{1,2}},?\s*(?:\d{{4}})?)\b",
    re.IGNORECASE,
)
_ISO_DATE_PATTERN = re.compile(r"\b20\d{2}-\d{2}-\d{2}\b")
_DURATION_PATTERN = re.compile(
    r"\b(\d{1,2})\s*(days?|nights?|weeks?)\b", re.IGNORECASE
)


def _phrase_pattern(phrase: str) -> re.Pattern | None:
    phrase = (phrase or "").strip()
    if len(phrase) < 2:
        return None
    # Word boundaries avoid substring false positives such as "art" in "apartment".
    return re.compile(rf"(?<!\w){re.escape(phrase)}(?!\w)", re.IGNORECASE)


def _name_in_url(name: str, tokens: set[str]) -> bool:
    words = re.findall(r"[a-z0-9]+", name.lower())
    return bool(words) and all(word in tokens for word in words if len(word) >= 3)


def _url_tokens(url: str) -> list[str]:
    from urllib.parse import unquote, urlsplit

    parts = urlsplit(url)
    pieces = [parts.netloc.removeprefix("www.")]
    pieces.extend(unquote(parts.path).replace("-", " ").replace("_", " ").split("/"))
    joined = " ".join(pieces).lower()
    return [token for token in re.split(r"[^a-z0-9]+", joined) if len(token) >= 3]


def _span(match: re.Match | None) -> dict | None:
    if not match:
        return None
    return {"start": match.start(), "end": match.end(), "text": match.group(0)[:120]}


def _candidate(
    kind: str,
    name: str,
    confidence: float,
    evidence: str,
    *,
    source: str,
    span: dict | None = None,
    entity_id: str | None = None,
    value: dict | None = None,
) -> dict:
    payload = {
        "type": kind,
        "kind": kind,
        "id": entity_id,
        "name": name,
        "confidence": round(confidence, 2),
        "evidence": evidence,
        "source": source,
        "source_span": span,
        "provenance": "ESTIMATED",
        "verified": False,
        "decision": "pending",
    }
    if value is not None:
        payload["value"] = value
    return payload


def _provider_summary(result) -> dict:
    return {
        "provider": result.provider,
        "ok": result.ok,
        "provenance": result.provenance,
        "cached": result.cached,
        "error": result.error,
        "message": result.message,
        "attribution": result.attribution,
        "fetched_at": result.fetched_at.isoformat() if result.fetched_at else None,
    }


def dream_import(
    db: Session,
    user_id: str,
    inspiration: SavedInspiration,
    *,
    media_path=None,
) -> dict:
    from pathlib import Path

    from app.integrations import base as provider_base
    from app.integrations import links, ocr

    text = inspiration.content or ""
    destinations = db.query(Destination).all()
    activities = db.query(Activity).all()
    matches: list[dict] = []
    provider_results = []

    urls = _URL_PATTERN.findall(text)
    url_tokens: set[str] = set()
    for url in urls:
        url_tokens.update(_url_tokens(url))
    # Mask URLs with spaces of equal length so spans still map to the original
    # text while link paths are not mistaken for prose mentions.
    prose = _URL_PATTERN.sub(lambda match: " " * len(match.group(0)), text)

    link_result = None
    link_text = ""
    if inspiration.source_type == "link":
        if urls:
            link_result = links.fetch_metadata(urls[0])
        else:
            link_result = provider_base.unavailable(
                "page-metadata", "No web address was found in the link field."
            )
        provider_results.append(link_result)
        if link_result.ok and link_result.data:
            link_text = " ".join(
                part
                for part in (
                    link_result.data.get("title"),
                    link_result.data.get("description"),
                )
                if part
            )

    ocr_result = None
    ocr_text = ""
    if inspiration.source_type == "image_url" and media_path:
        ocr_result = ocr.extract_text(Path(media_path))
        provider_results.append(ocr_result)
        if ocr_result.ok and ocr_result.data:
            ocr_text = ocr_result.data.get("text", "")

    sources: list[tuple[str, str]] = [("text", prose)]
    if link_text:
        sources.append(("link_metadata", link_text))
    if ocr_text:
        sources.append(("ocr", ocr_text))
    narrative_sources = [item for item in sources if item[0] in {"text", "ocr"}]

    def confidence(kind: str, source: str) -> float:
        table = {
            ("destination", "text"): 0.9,
            ("destination", "link_metadata"): 0.8,
            ("destination", "ocr"): 0.65,
            ("destination", "url_path"): 0.7,
            ("destination_hint", "text"): 0.55,
            ("destination_hint", "link_metadata"): 0.45,
            ("destination_hint", "ocr"): 0.4,
            ("activity", "text"): 0.85,
            ("activity", "link_metadata"): 0.75,
            ("activity", "ocr"): 0.6,
            ("interest", "text"): 0.4,
            ("interest", "link_metadata"): 0.35,
            ("interest", "ocr"): 0.3,
            ("budget_hint", "text"): 0.5,
            ("budget_hint", "link_metadata"): 0.35,
            ("budget_hint", "ocr"): 0.45,
            ("travel_window", "text"): 0.35,
            ("travel_window", "ocr"): 0.3,
            ("travel_dates", "text"): 0.6,
            ("travel_dates", "ocr"): 0.5,
            ("trip_length", "text"): 0.55,
            ("trip_length", "ocr"): 0.45,
        }
        return table.get((kind, source), 0.35)

    evidence = {
        ("destination", "text"): "Destination name appears in the text.",
        ("destination", "link_metadata"): "Destination name appears in the page's metadata.",
        ("destination", "ocr"): "Destination name was machine-read from the image; OCR can misread.",
        ("destination", "url_path"): "Destination name appears in the link path; the page itself was not read.",
        ("activity", "text"): "Activity name appears in the text.",
        ("activity", "link_metadata"): "Activity name appears in the page's metadata.",
        ("activity", "ocr"): "Activity name was machine-read from the image; OCR can misread.",
    }

    for destination in destinations:
        name_pattern = _phrase_pattern(destination.name)
        slug_pattern = _phrase_pattern((destination.slug or "").replace("-", " "))
        found = False
        for source, source_text in sources:
            match = name_pattern.search(source_text) if name_pattern else None
            if match is None and slug_pattern:
                match = slug_pattern.search(source_text)
            if match:
                matches.append(
                    _candidate(
                        "destination",
                        destination.name,
                        confidence("destination", source),
                        evidence[("destination", source)],
                        source=source,
                        span=_span(match),
                        entity_id=destination.id,
                    )
                )
                found = True
                break
        if found:
            continue
        if url_tokens and _name_in_url(destination.name, url_tokens):
            matches.append(
                _candidate(
                    "destination",
                    destination.name,
                    confidence("destination", "url_path"),
                    evidence[("destination", "url_path")],
                    source="url_path",
                    entity_id=destination.id,
                )
            )
            continue
        hint_found = False
        for source, source_text in sources:
            for tag in destination.tags or []:
                tag_pattern = _phrase_pattern(str(tag))
                tag_match = tag_pattern.search(source_text) if tag_pattern else None
                if tag_match:
                    matches.append(
                        _candidate(
                            "destination_hint",
                            destination.name,
                            confidence("destination_hint", source),
                            f"Interest keyword '{tag}' matches this destination.",
                            source=source,
                            span=_span(tag_match),
                            entity_id=destination.id,
                        )
                    )
                    hint_found = True
                    break
            if hint_found:
                break

    for activity in activities:
        activity_pattern = _phrase_pattern(activity.name)
        for source, source_text in sources:
            match = activity_pattern.search(source_text) if activity_pattern else None
            if match:
                matches.append(
                    _candidate(
                        "activity",
                        activity.name,
                        confidence("activity", source),
                        evidence[("activity", source)],
                        source=source,
                        span=_span(match),
                        entity_id=activity.id,
                    )
                )
                break

    interest_terms = {
        "food",
        "temple",
        "beach",
        "hiking",
        "art",
        "market",
        "museum",
        "nature",
        "shopping",
        "nightlife",
        "photography",
        "street food",
    }
    for raw_tag in _HASHTAG_PATTERN.findall(text):
        interest_terms.add(raw_tag.replace("-", " ").replace("_", " "))
    claimed_names = {match["name"].lower() for match in matches}
    for term in sorted(interest_terms):
        if term in claimed_names:
            continue
        term_pattern = _phrase_pattern(term)
        for source, source_text in sources:
            match = term_pattern.search(source_text) if term_pattern else None
            if match:
                matches.append(
                    _candidate(
                        "interest",
                        term,
                        confidence("interest", source),
                        f"Keyword '{term}' found; requires your confirmation.",
                        source=source,
                        span=_span(match),
                    )
                )
                break

    for source, source_text in sources:
        for match in _BUDGET_PATTERN.finditer(source_text):
            symbol, amount, bare_amount, code = match.groups()
            value = amount or bare_amount
            if not value:
                continue
            label = f"{symbol or code.upper()} {value}".replace("  ", " ")
            matches.append(
                _candidate(
                    "budget_hint",
                    label,
                    confidence("budget_hint", source),
                    "Budget mention found; confirm it before using it as a filter.",
                    source=source,
                    span=_span(match),
                )
            )

    date_ranges: list[tuple[str, int, int]] = []
    for source, source_text in narrative_sources:
        for pattern in (_DATE_RANGE_PATTERN, _ISO_DATE_PATTERN):
            for match in pattern.finditer(source_text):
                phrase = match.group(0)
                date_ranges.append((source, match.start(), match.end()))
                matches.append(
                    _candidate(
                        "travel_dates",
                        phrase,
                        confidence("travel_dates", source),
                        "Date phrase found; confirm the exact dates yourself.",
                        source=source,
                        span=_span(match),
                    )
                )
        for match in _DURATION_PATTERN.finditer(source_text):
            matches.append(
                _candidate(
                    "trip_length",
                    match.group(0),
                    confidence("trip_length", source),
                    "Trip length found; confirm it yourself.",
                    source=source,
                    span=_span(match),
                    value={"amount": int(match.group(1)), "unit": match.group(2).lower()},
                )
            )

    for source, source_text in narrative_sources:
        for month in _MONTHS:
            pattern = _phrase_pattern(month)
            match = pattern.search(source_text) if pattern else None
            if not match:
                continue
            inside_range = any(
                same_source == source and start <= match.start() < end
                for same_source, start, end in date_ranges
            )
            if inside_range:
                continue
            matches.append(
                _candidate(
                    "travel_window",
                    month.capitalize(),
                    confidence("travel_window", source),
                    "Month mentioned; add exact dates yourself.",
                    source=source,
                    span=_span(match),
                )
            )

    seen = set()
    deduped = []
    for match in sorted(matches, key=lambda item: item["confidence"], reverse=True):
        key = (match["type"], match["id"] or match["name"].lower())
        if key in seen:
            continue
        seen.add(key)
        deduped.append(match)
    for match in deduped:
        slug = re.sub(r"[^a-z0-9]+", "-", match["name"].lower()).strip("-")[:40]
        match["candidate_id"] = f"{match['type']}:{match['id'] or slug}"

    notes = [
        "Extraction reads the text you supplied with word-boundary matching, URL paths, hashtags, budget mentions, dates and month names. It only proposes candidates; nothing is added to a trip automatically.",
        f"{len(deduped)} candidate(s) need your review. Accept or reject each one.",
    ]
    limitations = [
        "Candidates are inferred from matching, not verified facts. Opening hours, prices and availability are never inferred."
    ]
    if inspiration.source_type == "image_url":
        if ocr_result is None:
            limitations.append(
                "No local image was attached, so the image was not analysed. "
                "Upload the image to read its text locally."
            )
        elif not ocr_result.ok:
            limitations.append(f"OCR was not available: {ocr_result.message}")
        else:
            notes.append(
                "Text was machine-read from the uploaded image. OCR can misread; confirm every candidate."
            )
    if inspiration.source_type == "link":
        if link_result is None:
            limitations.append("The link was not read.")
        elif not link_result.ok:
            limitations.append(f"Link not read: {link_result.message}")
        else:
            notes.append(
                "Only the page's title and description metadata were read; the article body was not."
            )

    extraction = {
        "matches": deduped[:40],
        "status": "needs_confirmation",
        "notes": notes,
        "limitations": limitations,
        "review": {"pending": len(deduped), "accepted": 0, "rejected": 0},
        "metadata": {
            "source_hosts": sorted(
                {url.split("//", 1)[-1].split("/", 1)[0] for url in urls}
            ),
            "hashtags": sorted({tag.lower() for tag in _HASHTAG_PATTERN.findall(text)}),
            "urls": urls[:5],
            "sources": [
                {"kind": kind, "characters": len(source_text)}
                for kind, source_text in sources
            ],
            "providers": [_provider_summary(result) for result in provider_results],
            "link": (
                link_result.data
                if link_result is not None and link_result.ok
                else None
            ),
            "ocr": (
                {
                    "available": ocr_result.ok,
                    "characters": len(ocr_text),
                    "preview": ocr_text[:400],
                }
                if ocr_result is not None
                else None
            ),
        },
    }
    inspiration.extracted = extraction
    return extraction



def serendipity_suggestions(db: Session, user: User) -> dict:
    profile = db.query(Profile).filter(Profile.user_id == user.id).first()
    if not profile or not profile.allow_discovery:
        return {
            "eligible": False,
            "reason": "Enable traveller discovery in Privacy settings to see compatible travellers.",
            "matches": [],
        }
    my_trips = (
        db.query(Trip)
        .join(TripMember, TripMember.trip_id == Trip.id)
        .filter(TripMember.user_id == user.id, Trip.deleted_at.is_(None))
        .all()
    )
    my_destinations = {trip.destination_id for trip in my_trips if trip.destination_id}
    my_dates = [(trip.start_date, trip.end_date) for trip in my_trips]
    my_dna = dna_for_user(db, user.id)
    my_interests = {normalize_tag(tag) for tag in (profile.interests or [])}

    candidates = (
        db.query(Profile)
        .filter(
            Profile.allow_discovery.is_(True),
            Profile.user_id != user.id,
            Profile.public_profile.is_(True),
        )
        .all()
    )
    results = []
    for candidate in candidates:
        candidate_user = db.get(User, candidate.user_id)
        if not candidate_user or candidate_user.deleted_at:
            continue
        their_trips = _discoverable_trips(db, candidate.user_id)
        their_destinations = {trip.destination_id for trip in their_trips if trip.destination_id}
        shared_destinations = my_destinations.intersection(their_destinations)
        shared_interests = my_interests.intersection(
            {normalize_tag(tag) for tag in (candidate.interests or [])}
        )
        date_overlap = any(
            not (trip.end_date < start or trip.start_date > end)
            for trip in their_trips
            for start, end in my_dates
        )
        if not shared_destinations and not shared_interests and not date_overlap:
            continue
        with system_context(db):
            their_dna = dna_for_user(db, candidate.user_id)
        dna_similarity = _cosine(my_dna, their_dna)
        score = round(
            35
            * (1 if shared_destinations else 0)
            + 25 * min(1, len(shared_interests) / 3)
            + 25 * dna_similarity
            + (15 if date_overlap else 0),
            1,
        )
        reasons = []
        if shared_destinations:
            reasons.append("Destination overlap")
        if shared_interests:
            reasons.append("Shared interests: " + ", ".join(sorted(shared_interests)[:4]))
        if date_overlap:
            reasons.append("Overlapping travel dates")
        results.append(
            {
                "user": {
                    "id": candidate_user.id,
                    "display_name": candidate_user.display_name,
                    "avatar_url": candidate_user.avatar_url,
                    "headline": candidate.headline,
                    "home_city": candidate.home_city,
                },
                "score": score,
                "reasons": reasons,
                "shared_interests": sorted(shared_interests),
                "privacy": "No exact locations or contact details are shared. Contact requires mutual acceptance.",
            }
        )
    results.sort(key=lambda item: item["score"], reverse=True)
    for result in results[:10]:
        existing = (
            db.query(TravellerMatch)
            .filter(
                TravellerMatch.user_a_id == user.id,
                TravellerMatch.user_b_id == result["user"]["id"],
            )
            .first()
        )
        if not existing:
            db.add(
                TravellerMatch(
                    user_a_id=user.id,
                    user_b_id=result["user"]["id"],
                    overlap_score=result["score"],
                    reasons=result["reasons"],
                )
            )
    return {
        "eligible": True,
        "matches": results[:10],
        "disclosure": "Matching is opt-in and reciprocal. No private location is ever exposed.",
    }


def generate_missions(db: Session, trip: Trip, created_by: str) -> list[TripMission]:
    existing = db.query(TripMission).filter(TripMission.trip_id == trip.id).all()
    if existing:
        return existing
    activities = (
        db.query(Activity).filter(Activity.destination_id == trip.destination_id).all()
        if trip.destination_id
        else []
    )
    missions = []
    templates = [
        ("Taste something local", "food", "Find a local food experience within today's budget and radius."),
        ("Find a quiet viewpoint", "nature", "Discover a viewpoint that fits your energy and travel radius."),
        ("Meet the city's history", "history", "Visit a cultural landmark and share one thing you learned."),
    ]
    for title, tag, description in templates:
        matches = [
            activity
            for activity in activities
            if tag in {normalize_tag(t) for t in activity.tags or []}
        ]
        suggested = matches[0].name if matches else None
        missions.append(
            TripMission(
                trip_id=trip.id,
                title=title,
                description=description + (f" Suggestion: {suggested}." if suggested else " No matching catalog activity yet."),
                constraints={
                    "max_cost": 25,
                    "max_effort": 3,
                    "tag": tag,
                    "respect_accessibility": True,
                    "optional": True,
                    "suggested_activity": suggested,
                },
                created_by=created_by,
            )
        )
    db.add_all(missions)
    return missions


def ensure_seed_circles(db: Session, user_id: str) -> list[TravelCircle]:
    circles = db.query(TravelCircle).all()
    if circles:
        return circles
    seeds = [
        ("slow-travel", "Slow Travel", "Longer stays, local rhythms, fewer checkboxes.", ["culture", "local", "relaxation"]),
        ("food-first", "Food First", "Markets, kitchens and neighbourhood tables.", ["food", "local"]),
        ("trail-and-view", "Trail & View", "Walks, viewpoints and outdoor days.", ["outdoor", "nature", "adventure"]),
    ]
    created = []
    for slug, name, description, interests in seeds:
        circle = TravelCircle(
            slug=slug,
            name=name,
            description=description,
            interests=interests,
            created_by=user_id,
        )
        db.add(circle)
        created.append(circle)
    db.flush()
    return created
