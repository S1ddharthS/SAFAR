"""Group Experience Engine (F07).

Hard constraints are applied before ranking. Ranking is a transparent,
fairness-aware utility that is separate from eligibility:

    score = weighted(average fit, minimum fit, novelty) - penalties

The three modes change the weighting but never bypass a hard constraint.
No member's private budget or preferences are exposed in explanations.
"""

from dataclasses import dataclass, field
from datetime import date, datetime
from math import sqrt

from sqlalchemy.orm import Session

from app.db.context import system_context
from app.models import (
    Activity,
    ActivityFeedback,
    ItineraryItem,
    JourneyDNA,
    Place,
    Profile,
    Trip,
    TripMember,
    TripPulse,
    User,
)
from app.models.models import utcnow
from app.services.common import (
    DNA_DIMENSIONS,
    clamp,
    default_dna,
    normalize_tag,
)
from app.services.feedback import DNA_SENTIMENT, personalization_allowed
from app.services.geo import haversine_km, travel_minutes
from app.services.schedule import schedule_summary

ENGINE_VERSION = "safar-group-engine-1.5"
BUDGET_COMFORT_CAP = {1: 15.0, 2: 35.0, 3: 70.0, 4: 120.0, 5: None}
# Group feedback only nudges a score; it can never overturn a hard constraint
# and is ignored in very small groups where it would just be one person's taste.
FEEDBACK_MAX_ADJUSTMENT = 4.0
FEEDBACK_MIN_GROUP = 3
FEEDBACK_MIN_RATERS = 2
# Similar activities are demoted during selection, never made ineligible.
DIVERSITY_MAX_PENALTY = 4.0
DIVERSITY_SIMILARITY_FLOOR = 0.6
MODE_META = {
    "everyone_wins": {
        "label": "Everyone Wins",
        "intent": "Maximise suitability for the whole group while protecting the least-served member.",
    },
    "your_turn": {
        "label": "Your Turn",
        "intent": "Give extra weight to members whose interests the current plan represents least.",
    },
    "surprise_us": {
        "label": "Surprise Us",
        "intent": "Prefer unfamiliar but relevant experiences that still satisfy every hard constraint.",
    },
}


@dataclass
class MemberContext:
    member_id: str
    user_id: str | None
    label: str
    display_name: str
    dna: dict[str, float]
    budget_limit: float | None
    accessibility: list[str]
    energy: int = 3
    available_minutes: int | None = None
    budget_comfort: int = 3
    radius_km: float | None = None
    pulse: TripPulse | None = None

    @property
    def needs_wheelchair_access(self) -> bool:
        return any("wheel" in need.lower() or "mobility" in need.lower() for need in self.accessibility)

    @property
    def hard_budget(self) -> float | None:
        # Only an explicitly stated limit is a hard constraint. A budget
        # comfort score is a soft preference; treating the default (comfort 3)
        # as a hard cap silently excluded affordable activities for members
        # who never stated a limit.
        return self.budget_limit

    @property
    def soft_budget(self) -> float | None:
        if self.budget_limit is not None:
            return self.budget_limit
        return BUDGET_COMFORT_CAP.get(self.budget_comfort)


@dataclass
class RankedActivity:
    activity: Activity
    score: float
    average_fit: float
    minimum_fit: float
    fairness_spread: float
    novelty: float
    fits: list[float]
    penalties: dict
    distance_km: float
    travel_minutes: int
    exclusions: dict = field(default_factory=dict)
    target_fit: float | None = None
    explanation: dict = field(default_factory=dict)
    feedback_adjustment: float = 0.0
    feedback_raters: int = 0
    diversity_penalty: float = 0.0


def _dna_from_profile(profile: Profile | None) -> dict[str, float]:
    scores = {dimension: 5.0 for dimension in DNA_DIMENSIONS}
    if not profile:
        return scores
    for interest in profile.interests or []:
        key = normalize_tag(interest)
        if key in scores:
            scores[key] = 8.0
    if profile.budget_level == "budget":
        scores["budget"] = 8.0
        scores["luxury"] = 3.0
    elif profile.budget_level == "luxury":
        scores["luxury"] = 9.0
        scores["budget"] = 3.0
    elif profile.budget_level == "comfort":
        scores["luxury"] = 7.0
    return scores


def build_member_contexts(
    db: Session, trip: Trip, members: list[TripMember], for_date: date
) -> list[MemberContext]:
    contexts: list[MemberContext] = []
    for index, member in enumerate(
        sorted(members, key=lambda m: m.joined_at or datetime.min), start=1
    ):
        user = db.get(User, member.user_id) if member.user_id else None
        if member.user_id:
            # Profile and DNA are private to their owner (RLS); the engine reads them
            # under system context only while building aggregate context and never returns raw scores.
            with system_context(db):
                profile = (
                    db.query(Profile).filter(Profile.user_id == member.user_id).first()
                )
                dna_row = (
                    db.query(JourneyDNA)
                    .filter(JourneyDNA.user_id == member.user_id)
                    .first()
                )
        else:
            profile = None
            dna_row = None
        if dna_row and dna_row.scores:
            dna = {
                dim: float(dna_row.scores.get(dim, 5)) for dim in DNA_DIMENSIONS
            }
        else:
            dna = _dna_from_profile(profile)
        pulse = (
            db.query(TripPulse)
            .filter(
                TripPulse.trip_id == trip.id,
                TripPulse.user_id == member.user_id,
                TripPulse.pulse_date == for_date,
            )
            .first()
            if member.user_id
            else None
        )
        accessibility = list(member.accessibility_needs or [])
        if not accessibility and profile:
            accessibility = list(profile.accessibility_needs or [])
        contexts.append(
            MemberContext(
                member_id=member.id,
                user_id=member.user_id,
                label=f"Member {index}",
                display_name=(
                    user.display_name if user else (member.display_name or f"Member {index}")
                ),
                dna=dna,
                budget_limit=member.budget_limit
                or (profile.budget_limit if profile else None),
                accessibility=accessibility,
                energy=pulse.energy if pulse else 3,
                available_minutes=pulse.available_minutes if pulse else None,
                budget_comfort=pulse.budget_comfort if pulse else 3,
                radius_km=pulse.radius_km if pulse else None,
                pulse=pulse,
            )
        )
    return contexts


def _activity_vector(activity: Activity) -> dict[str, float]:
    vector: dict[str, float] = {}
    for tag in activity.tags or []:
        key = normalize_tag(tag)
        vector[key] = vector.get(key, 0.0) + 1.0
    return vector


def _cosine(a: dict[str, float], b: dict[str, float]) -> float:
    if not a or not b:
        return 0.0
    dot = sum(value * b.get(key, 0.0) for key, value in a.items())
    norm_a = sqrt(sum(value * value for value in a.values()))
    norm_b = sqrt(sum(value * value for value in b.values()))
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return dot / (norm_a * norm_b)


def _member_dna_for_today(ctx: MemberContext) -> dict[str, float]:
    dna = dict(ctx.dna)
    if ctx.pulse:
        for interest in list(ctx.pulse.interests or []) + list(ctx.pulse.activity_prefs or []):
            key = normalize_tag(interest)
            if key in dna:
                # Today's mood boosts a dimension without mutating Journey DNA (F06).
                dna[key] = max(dna[key], 8.5)
    if ctx.pulse and ctx.pulse.energy <= 2:
        dna["relaxation"] = max(dna.get("relaxation", 5), 7.5)
        dna["adventure"] = min(dna.get("adventure", 5), 3)
    return dna


def rank_activity(
    activity: Activity,
    contexts: list[MemberContext],
    *,
    base_lat: float,
    base_lon: float,
    coords: tuple[float, float],
    target_member_index: int | None,
    mode: str,
) -> RankedActivity | None:
    if not contexts:
        return None
    lat, lon = coords
    distance = haversine_km(base_lat, base_lon, lat, lon) if (lat or lon) else 0.0
    travel = travel_minutes(distance)
    round_trip = travel * 2
    vector = _activity_vector(activity)
    exclusions: dict[str, str] = {}
    fits: list[float] = []

    for ctx in contexts:
        needed_time = activity.duration_minutes + round_trip
        hard_budget = ctx.hard_budget
        if hard_budget is not None and activity.price_estimate > hard_budget:
            exclusions[ctx.label] = "budget"
            continue
        if ctx.radius_km is not None and distance > ctx.radius_km:
            exclusions[ctx.label] = "radius"
            continue
        if ctx.available_minutes is not None and needed_time > ctx.available_minutes:
            exclusions[ctx.label] = "time"
            continue
        if ctx.needs_wheelchair_access and activity.wheelchair_accessible is False:
            exclusions[ctx.label] = "accessibility"
            continue

        interest = 0.2 + 0.8 * _cosine(vector, _member_dna_for_today(ctx))
        soft_budget = ctx.soft_budget
        if soft_budget:
            budget_fit = clamp(1 - (activity.price_estimate / soft_budget), 0, 1)
        else:
            budget_fit = clamp(1 - activity.price_estimate / 150, 0, 1)
        energy_fit = clamp(1 - max(0, activity.effort - ctx.energy) / 4, 0, 1)
        if ctx.available_minutes:
            time_fit = clamp(1 - (needed_time / ctx.available_minutes) * 0.85, 0.1, 1)
        else:
            time_fit = clamp(1 - round_trip / 180, 0.2, 1)
        if not ctx.accessibility:
            access_fit = 1.0
        elif activity.wheelchair_accessible is True:
            access_fit = 1.0
        elif activity.wheelchair_accessible is None:
            access_fit = 0.45
        else:
            access_fit = 1.0  # non-wheelchair needs are not matched to a field yet

        fit = 100 * (
            0.58 * interest
            + 0.16 * budget_fit
            + 0.10 * energy_fit
            + 0.10 * time_fit
            + 0.06 * access_fit
        )
        fits.append(round(fit, 1))

    if exclusions:
        return None

    average = sum(fits) / len(fits)
    minimum = min(fits)
    spread = max(fits) - minimum
    novelty = clamp(1 - activity.popularity, 0, 1)

    uncertainty = 0.0
    if any(ctx.needs_wheelchair_access for ctx in contexts) and activity.wheelchair_accessible is None:
        uncertainty += 8.0
    if activity.source_type.startswith("seed"):
        uncertainty += 4.0
    if not activity.last_verified_at or (
        utcnow() - activity.last_verified_at
    ).days > 365:
        uncertainty += 3.0

    time_penalty = clamp(round_trip / max(1, min(ctx.available_minutes or 240 for ctx in contexts)) * 10, 0, 12)
    avg_cap = sum(ctx.soft_budget or 150 for ctx in contexts) / len(contexts)
    budget_penalty = clamp(activity.price_estimate / max(1, avg_cap) * 6, 0, 8)
    penalties = {
        "time": round(time_penalty, 2),
        "budget": round(budget_penalty, 2),
        "uncertainty": round(uncertainty, 2),
        "total": round(time_penalty + budget_penalty + uncertainty, 2),
    }

    novelty_points = novelty * 100
    if mode == "your_turn" and target_member_index is not None:
        target_fit = fits[target_member_index]
        score = (
            0.45 * average
            + 0.20 * minimum
            + 0.30 * target_fit
            + 0.05 * novelty_points
            - penalties["total"]
        )
    elif mode == "surprise_us":
        surprise_bonus = 6.0 if not activity.iconic else -3.0
        score = (
            0.45 * average
            + 0.20 * minimum
            + 0.35 * novelty_points
            + surprise_bonus
            - penalties["total"]
        )
    else:
        score = (
            0.55 * average
            + 0.30 * minimum
            + 0.15 * novelty_points
            - penalties["total"]
        )

    return RankedActivity(
        activity=activity,
        score=round(clamp(score, 0, 100), 1),
        average_fit=round(average, 1),
        minimum_fit=round(minimum, 1),
        fairness_spread=round(spread, 1),
        novelty=round(novelty, 3),
        fits=fits,
        penalties=penalties,
        distance_km=distance,
        travel_minutes=travel,
        exclusions=exclusions,
        target_fit=(
            round(fits[target_member_index], 1)
            if target_member_index is not None and target_member_index < len(fits)
            else None
        ),
    )


def _representation_scores(
    db: Session,
    contexts: list[MemberContext],
    confirmed_items: list[ItineraryItem],
) -> list[float]:
    """Average personal interest fit of the confirmed plan per member."""
    if not confirmed_items:
        return [0.0 for _ in contexts]
    activity_ids = [item.activity_id for item in confirmed_items if item.activity_id]
    activities = (
        db.query(Activity).filter(Activity.id.in_(activity_ids)).all()
        if activity_ids
        else []
    )
    by_id = {activity.id: activity for activity in activities}
    vectors = {aid: _activity_vector(act) for aid, act in by_id.items()}
    scores: list[float] = []
    for ctx in contexts:
        dna = _member_dna_for_today(ctx)
        fits = [
            0.2 + 0.8 * _cosine(vectors[item.activity_id], dna)
            for item in confirmed_items
            if item.activity_id in vectors
        ]
        scores.append(sum(fits) / len(fits) if fits else 0.0)
    return scores


def _freshness(activity: Activity) -> dict:
    if activity.last_verified_at:
        age_days = max(0, (utcnow() - activity.last_verified_at).days)
        if age_days <= 30:
            label = "Fresh catalog entry"
        elif age_days <= 180:
            label = "Aging catalog entry"
        else:
            label = "Stale catalog entry — recheck before relying on it"
        return {
            "last_verified_at": activity.last_verified_at.isoformat(),
            "age_days": age_days,
            "label": label,
        }
    return {
        "last_verified_at": None,
        "age_days": None,
        "label": "No verification date on record",
    }


def _explanation(
    ranked: RankedActivity,
    contexts: list[MemberContext],
    mode: str,
    target: MemberContext | None,
) -> dict:
    activity = ranked.activity
    tags = [normalize_tag(tag) for tag in (activity.tags or [])][:5]
    tag_text = ", ".join(tags) if tags else "mixed interests"

    why: list[str] = []
    if mode == "everyone_wins":
        why.append(
            f"Balances the group: average fit {ranked.average_fit:.0f}/100 with the least-served member at {ranked.minimum_fit:.0f}/100."
        )
    elif mode == "your_turn":
        why.append(
            "Gives extra weight to a member whose interests the confirmed plan represents least."
        )
        if ranked.target_fit is not None:
            why.append(f"Fit for that member is {ranked.target_fit:.0f}/100.")
    else:
        why.append(
            f"Unfamiliar but relevant: novelty {round(ranked.novelty * 100):.0f}/100 while every member stays above {ranked.minimum_fit:.0f}/100."
        )
    if ranked.feedback_adjustment:
        direction = "raised" if ranked.feedback_adjustment > 0 else "lowered"
        why.append(
            f"Consented group feedback {direction} this suggestion by "
            f"{abs(ranked.feedback_adjustment):.1f} points."
        )
    why.append(f"Matches group interests in {tag_text}.")
    if ranked.penalties["total"] > 0:
        why.append(
            f"Penalties applied for time, budget and uncertainty: {ranked.penalties['total']:.0f} points total."
        )

    suits = [f"Members interested in {tag_text}"]
    if activity.indoor:
        suits.append("Members who prefer indoor experiences")
    if activity.effort <= 2:
        suits.append("Members looking for a lower-effort option")
    if activity.price_estimate <= 15:
        suits.append("Budget-conscious members")

    may_not = []
    low_fits = [ctx for ctx, fit in zip(contexts, ranked.fits) if fit < 55]
    if low_fits:
        may_not.append("Members whose interests are not aligned with these tags")
    if activity.effort >= 4:
        may_not.append("Members with low energy today")
    if activity.price_estimate >= 60:
        may_not.append("Members near their budget comfort level")
    if not may_not:
        may_not.append("No strong mismatch identified for the current group")

    constraints = [
        {
            "constraint": "Budget",
            "status": "satisfied",
            "detail": (
                f"Estimated {activity.currency} {activity.price_estimate:.0f} per person; "
                "no member's stated budget limit is exceeded."
            ),
        },
        {
            "constraint": "Accessibility",
            "status": (
                "satisfied"
                if not any(ctx.needs_wheelchair_access for ctx in contexts)
                else ("satisfied" if activity.wheelchair_accessible else "unknown")
            ),
            "detail": (
                "Step-free access confirmed in the catalog."
                if activity.wheelchair_accessible is True
                else (
                    "No accessibility requirement stated by members."
                    if not any(ctx.needs_wheelchair_access for ctx in contexts)
                    else "Accessibility is not confirmed for this place; treat as unknown."
                )
            ),
        },
        {
            "constraint": "Time",
            "status": "satisfied",
            "detail": f"{activity.duration_minutes} min activity plus ~{ranked.travel_minutes * 2} min round-trip travel fits today's availability.",
        },
        {
            "constraint": "Distance",
            "status": "satisfied",
            "detail": f"{ranked.distance_km:.1f} km from the trip base, inside every stated radius.",
        },
    ]

    uncertainties = []
    if activity.source_type.startswith("seed"):
        uncertainties.append(
            "Catalog attributes are curated seed data, not live provider data."
        )
    if activity.wheelchair_accessible is None:
        uncertainties.append("Wheelchair accessibility is unknown, not verified.")
    if not activity.last_verified_at:
        uncertainties.append("No last-verified date is recorded for opening hours or price.")
    if not uncertainties:
        uncertainties.append("Travel time is an estimate; it is not a routed ETA.")

    return {
        "summary": (
            f"{activity.name} is "
            f"{'an' if mode == 'everyone_wins' else 'a'} {mode.replace('_', ' ')} pick for the group."
        ),
        "why_selected": why,
        "suits": suits,
        "may_not_prefer": may_not,
        "constraints_checked": constraints,
        "estimated_cost": activity.price_estimate,
        "currency": activity.currency,
        "distance_km": ranked.distance_km,
        "travel_minutes": ranked.travel_minutes,
        "duration_minutes": activity.duration_minutes,
        "data_freshness": _freshness(activity),
        "uncertainties": uncertainties,
        "metrics": {
            "average_fit": ranked.average_fit,
            "minimum_fit": ranked.minimum_fit,
            "fairness_spread": ranked.fairness_spread,
            "novelty": ranked.novelty,
            "score": ranked.score,
            "feedback_adjustment": ranked.feedback_adjustment,
            "diversity_penalty": ranked.diversity_penalty,
        },
        "selection": {
            "diversity_penalty": ranked.diversity_penalty,
            "feedback_adjustment": ranked.feedback_adjustment,
            "note": (
                "A close duplicate of an already suggested activity was demoted, "
                "not removed from eligibility."
                if ranked.diversity_penalty
                else "No diversity adjustment was needed for this suggestion."
            ),
        },
        "member_fits_anonymous": ranked.fits,
        "target_member": target.label if target else None,
    }


def _feedback_adjustments(
    db: Session, trip: Trip, contexts: list[MemberContext]
) -> tuple[dict[str, dict], int]:
    """Aggregate consented trip feedback into a small, bounded score nudge.

    Individual sentiments never leave this function. A nudge needs at least two
    consenting raters and a group of three or more, otherwise it is personal
    taste rather than group learning.
    """
    if len(contexts) < FEEDBACK_MIN_GROUP:
        return {}, 0
    user_ids = [ctx.user_id for ctx in contexts if ctx.user_id]
    allowed = {uid for uid in user_ids if personalization_allowed(db, uid)}
    if not allowed:
        return {}, 0
    rows = (
        db.query(ActivityFeedback)
        .filter(
            ActivityFeedback.trip_id == trip.id,
            ActivityFeedback.user_id.in_(allowed),
            ActivityFeedback.consented.is_(True),
        )
        .all()
    )
    grouped: dict[str, list[float]] = {}
    for row in rows:
        delta = DNA_SENTIMENT.get(row.sentiment, 0.0)
        grouped.setdefault(row.activity_id, []).append(delta)
    adjustments: dict[str, dict] = {}
    raters = 0
    for activity_id, deltas in grouped.items():
        if len(deltas) < FEEDBACK_MIN_RATERS:
            continue
        mean = sum(deltas) / len(deltas)
        adjustment = round(
            clamp(mean * 2.0, -FEEDBACK_MAX_ADJUSTMENT, FEEDBACK_MAX_ADJUSTMENT), 2
        )
        if adjustment == 0:
            continue
        adjustments[activity_id] = {"adjustment": adjustment, "raters": len(deltas)}
        raters += len(deltas)
    return adjustments, raters


def _select_diverse(
    ranked: list[RankedActivity], limit: int
) -> tuple[list[RankedActivity], list[RankedActivity]]:
    """Greedy selection that demotes near-duplicates within a small margin.

    The demotion is capped at ``DIVERSITY_MAX_PENALTY`` so a clearly better
    activity always wins, and removed candidates remain available as
    alternatives rather than disappearing.
    """
    remaining = list(ranked)
    selected: list[RankedActivity] = []
    while remaining and len(selected) < limit:
        best: RankedActivity | None = None
        best_value = float("-inf")
        for candidate in remaining:
            similarity = 0.0
            if selected:
                vector = _activity_vector(candidate.activity)
                similarity = max(
                    _cosine(vector, _activity_vector(item.activity)) for item in selected
                )
            penalty = 0.0
            if similarity > DIVERSITY_SIMILARITY_FLOOR:
                span = 1 - DIVERSITY_SIMILARITY_FLOOR
                penalty = round(
                    DIVERSITY_MAX_PENALTY * (similarity - DIVERSITY_SIMILARITY_FLOOR) / span, 2
                )
            value = candidate.score - penalty
            if value > best_value:
                best, best_value = candidate, value
                candidate.diversity_penalty = penalty
        assert best is not None
        selected.append(best)
        remaining.remove(best)
    selected.sort(key=lambda item: item.score, reverse=True)
    remaining.sort(key=lambda item: item.score, reverse=True)
    return selected, remaining[:3]


def _evaluation_meta(
    top: list[RankedActivity], contexts: list[MemberContext], excluded: int
) -> dict:
    if not top:
        return {
            "fairness": {"least_served_member_mean_fit": 0.0, "member_mean_spread": 0.0, "jain_index": 0.0},
            "satisfaction": {"mean_average_fit": 0.0, "mean_minimum_fit": 0.0, "mean_novelty": 0.0},
            "constraints": {"violations": 0, "eligible": 0, "excluded": excluded},
            "diversity": {"unique_primary_tags": 0, "unique_tags": 0, "mean_pairwise_similarity": 0.0},
        }
    member_means = [
        sum(item.fits[index] for item in top) / len(top)
        for index in range(len(contexts))
    ]
    total = sum(member_means)
    jain = (
        (total * total) / (len(member_means) * sum(value * value for value in member_means))
        if total
        else 0.0
    )
    vectors = [_activity_vector(item.activity) for item in top]
    similarities = [
        _cosine(vectors[left], vectors[right])
        for left in range(len(vectors))
        for right in range(left + 1, len(vectors))
    ]
    tags = {
        normalize_tag(tag)
        for item in top
        for tag in (item.activity.tags or [])
        if normalize_tag(tag)
    }
    return {
        "fairness": {
            "least_served_member_mean_fit": round(min(member_means), 1),
            "member_mean_spread": round(max(member_means) - min(member_means), 1),
            "jain_index": round(clamp(jain, 0, 1), 3),
            "note": (
                "Computed over anonymised per-member fits. No individual "
                "preference or budget is exposed."
            ),
        },
        "satisfaction": {
            "mean_average_fit": round(sum(item.average_fit for item in top) / len(top), 1),
            "mean_minimum_fit": round(sum(item.minimum_fit for item in top) / len(top), 1),
            "mean_novelty": round(sum(item.novelty for item in top) / len(top), 3),
        },
        "constraints": {
            "violations": 0,
            "eligible": len(top),
            "excluded": excluded,
            "note": "Every selected activity passed all hard constraints before ranking.",
        },
        "diversity": {
            "unique_primary_tags": len(
                {
                    normalize_tag(item.activity.tags[0])
                    for item in top
                    if item.activity.tags
                }
            ),
            "unique_tags": len(tags),
            "mean_pairwise_similarity": (
                round(sum(similarities) / len(similarities), 3) if similarities else 0.0
            ),
            "note": (
                "Similar activities are demoted during selection but stay "
                "eligible and available as alternatives."
            ),
        },
    }


def generate_recommendations(
    db: Session,
    trip: Trip,
    members: list[TripMember],
    *,
    mode: str,
    for_date: date,
    limit: int = 6,
) -> dict:
    if mode not in MODE_META:
        mode = "everyone_wins"
    contexts = build_member_contexts(db, trip, members, for_date)
    if not contexts:
        return {"items": [], "error": "No active members to personalise for."}
    if not trip.destination_id:
        return {
            "items": [],
            "error": "Set a destination for this trip before generating group recommendations.",
        }

    feedback_map, feedback_raters = _feedback_adjustments(db, trip, contexts)

    activities = (
        db.query(Activity)
        .filter(Activity.destination_id == trip.destination_id)
        .order_by(Activity.name)
        .all()
    )
    place_cache: dict[str, Place | None] = {}

    def coords_for(activity: Activity) -> tuple[float, float]:
        if activity.place_id not in place_cache:
            place_cache[activity.place_id] = (
                db.get(Place, activity.place_id) if activity.place_id else None
            )
        place = place_cache[activity.place_id]
        return (place.lat, place.lon) if place else (0.0, 0.0)

    confirmed = (
        db.query(ItineraryItem)
        .filter(
            ItineraryItem.trip_id == trip.id,
            ItineraryItem.status == "confirmed",
        )
        .all()
    )
    planned_activity_ids = {item.activity_id for item in confirmed if item.activity_id}
    day_items = [item for item in confirmed if item.day == for_date]
    schedule = schedule_summary(db, day_items)

    target_index: int | None = None
    target_ctx: MemberContext | None = None
    if mode == "your_turn":
        representation = _representation_scores(db, contexts, confirmed)
        if any(score > 0 for score in representation):
            target_index = min(range(len(contexts)), key=lambda i: representation[i])
        target_ctx = contexts[target_index] if target_index is not None else None

    ranked: list[RankedActivity] = []
    exclusion_reasons: dict[str, int] = {}
    seen: dict[str, int] = {}
    for activity in activities:
        if activity.id in planned_activity_ids:
            continue
        coords = coords_for(activity)
        distance = (
            haversine_km(trip.base_lat, trip.base_lon, coords[0], coords[1])
            if (coords[0] or coords[1])
            else 0.0
        )
        needed = activity.duration_minutes + travel_minutes(distance) * 2
        if needed > schedule["max_free_minutes"]:
            key = "protected_time" if schedule["protected_count"] else "day_schedule"
            exclusion_reasons[key] = exclusion_reasons.get(key, 0) + 1
            continue
        result = rank_activity(
            activity,
            contexts,
            base_lat=trip.base_lat,
            base_lon=trip.base_lon,
            coords=coords,
            target_member_index=target_index,
            mode=mode,
        )
        if result is None:
            exclusion_reasons["hard_constraint"] = (
                exclusion_reasons.get("hard_constraint", 0) + 1
            )
            continue
        ranked.append(result)

    if mode == "your_turn" and target_index is None and ranked:
        # No plan yet: target the member whose interests are hardest to serve.
        hardest = min(range(len(contexts)), key=lambda i: sum(r.fits[i] for r in ranked) / len(ranked))
        target_index = hardest
        target_ctx = contexts[hardest]
        for result in ranked:
            result.target_fit = result.fits[hardest]
            result.score = round(
                clamp(
                    0.45 * result.average_fit
                    + 0.20 * result.minimum_fit
                    + 0.30 * result.fits[hardest]
                    + 0.05 * result.novelty * 100
                    - result.penalties["total"],
                    0,
                    100,
                ),
                1,
            )

    for result in ranked:
        learned = feedback_map.get(result.activity.id)
        if learned:
            result.feedback_adjustment = learned["adjustment"]
            result.feedback_raters = learned["raters"]
            result.score = round(
                clamp(result.score + learned["adjustment"], 0, 100), 1
            )

    ranked.sort(key=lambda item: item.score, reverse=True)
    top, alternatives = _select_diverse(ranked, limit)

    for result in top:
        explanation = _explanation(result, contexts, mode, target_ctx)
        explanation["alternatives"] = [
            {
                "activity_id": alt.activity.id,
                "name": alt.activity.name,
                "score_delta": round(result.score - alt.score, 1),
            }
            for alt in alternatives
        ]
        result.explanation = explanation

    top_scores = [item.score for item in top]
    close_call = len(top_scores) >= 2 and (top_scores[0] - top_scores[1]) < 4
    missing_pulse = [ctx for ctx in contexts if ctx.pulse is None]
    clarifying_question = None
    if close_call and missing_pulse:
        clarifying_question = (
            f"{len(missing_pulse)} of {len(contexts)} members haven't shared a Trip Pulse today. "
            "Knowing their available time and energy could change the top result."
        )

    return {
        "mode": mode,
        "mode_meta": MODE_META[mode],
        "for_date": for_date,
        "items": top,
        "contexts": contexts,
        "target": target_ctx,
        "meta": {
            "model_version": ENGINE_VERSION,
            "candidate_count": len(activities),
            "eligible_count": len(ranked),
            "excluded_count": sum(exclusion_reasons.values()),
            "planned_excluded": len(planned_activity_ids),
            "members_count": len(contexts),
            "pulse_coverage": f"{len(contexts) - len(missing_pulse)}/{len(contexts)}",
            "hard_constraints": [
                "stated budget limits",
                "wheelchair accessibility requirements",
                "today's available time",
                "today's travel radius",
                "remaining free time in the day",
                "protected time blocks",
            ],
            "ranking_formula": (
                "mode-weighted average fit + minimum fit + novelty - time, budget and "
                "uncertainty penalties, plus a bounded consented-feedback nudge, then "
                "diversity-aware selection"
            ),
            "disclosure": (
                "Catalog attributes are curated seed data. Travel times are estimates. "
                "Private budgets and preferences are used for filtering but never exposed."
            ),
            "evaluation": _evaluation_meta(top, contexts, sum(exclusion_reasons.values())),
            "feedback_learning": {
                "applied_activities": len(feedback_map),
                "consented_raters": feedback_raters,
                "enabled": len(contexts) >= FEEDBACK_MIN_GROUP,
                "max_adjustment": FEEDBACK_MAX_ADJUSTMENT,
                "note": (
                    "Only consented feedback from at least two members in a group of "
                    "three or more is used, as an aggregate nudge capped at "
                    f"{FEEDBACK_MAX_ADJUSTMENT:.0f} points. Individual sentiments are never shown."
                ),
            },
            "protected_time": {
                "protected_items": schedule["protected"],
                "free_windows": schedule["free_windows"],
                "max_free_minutes": schedule["max_free_minutes"],
                "note": schedule["note"],
            },
        },
        "exclusion_reasons": exclusion_reasons,
        "clarifying_question": clarifying_question,
        "all_ranked_ids": [item.activity.id for item in ranked],
    }
