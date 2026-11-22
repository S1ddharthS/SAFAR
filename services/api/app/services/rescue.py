"""Trip Rescue (F09) and Fair Trade negotiation (F45).

Rescue only produces a proposal. Nothing is applied until the group approves.
"""

from datetime import date

from sqlalchemy.orm import Session

from app.models import (
    Activity,
    ItineraryItem,
    JourneyPact,
    Place,
    Shadowplan,
    Trip,
    TripMember,
)
from app.services.common import normalize_tag
from app.services.engine import generate_recommendations
from app.services.geo import haversine_km, travel_minutes
from app.services.schedule import DAY_END_MINUTES, item_window, parse_hhmm

KIND_LABELS = {
    "rain": "Rain or bad weather",
    "closure": "Unexpected closure",
    "traffic": "Traffic delay",
    "fatigue": "Fatigue or low energy",
    "budget": "Budget change",
    "time": "Time constraint",
}


def _activity_map(db: Session, items: list[ItineraryItem]) -> dict[str, Activity]:
    ids = [item.activity_id for item in items if item.activity_id]
    if not ids:
        return {}
    return {a.id: a for a in db.query(Activity).filter(Activity.id.in_(ids)).all()}


def _place_coords(db: Session, activity: Activity | None) -> tuple[float, float]:
    if not activity or not activity.place_id:
        return (0.0, 0.0)
    place = db.get(Place, activity.place_id)
    return (place.lat, place.lon) if place else (0.0, 0.0)


def _pick_affected(db: Session, items: list[ItineraryItem], kind: str, item_id: str | None) -> list[dict]:
    if item_id:
        target = next((item for item in items if item.id == item_id), None)
        return [{"item": target, "reason": "The group flagged this item."}] if target else []

    if not items:
        return []
    day = sorted({item.day for item in items})[0]
    day_items = [item for item in items if item.day == day and not item.is_protected]
    activities = _activity_map(db, day_items)

    def activity_of(item: ItineraryItem) -> Activity | None:
        return activities.get(item.activity_id) if item.activity_id else None

    selected: list[ItineraryItem] = []
    reason = ""
    if kind == "rain":
        selected = [item for item in day_items if activity_of(item) and not activity_of(item).indoor]
        reason = "Outdoor activities are exposed to rain."
    elif kind == "closure":
        selected = day_items[:1]
        reason = "The first item of the day is affected by a closure."
    elif kind == "traffic":
        selected = [item for item in day_items if item.start_time >= "12:00"] or day_items[-1:]
        reason = "Later items are likely to slip because of traffic."
    elif kind == "fatigue":
        selected = [item for item in day_items if activity_of(item) and activity_of(item).effort >= 3]
        if not selected:
            selected = sorted(day_items, key=lambda item: activity_of(item).effort if activity_of(item) else 0, reverse=True)[:1]
        reason = "High-effort items are a poor fit for low energy."
    elif kind == "budget":
        selected = sorted(day_items, key=lambda item: item.cost_estimate, reverse=True)[:2]
        reason = "The most expensive items put pressure on the budget."
    elif kind == "time":
        selected = day_items[-1:]
        reason = "The last item is at risk of not fitting the available time."
    return [{"item": item, "reason": reason} for item in selected if item]


def _replacement_filter(kind: str, original: Activity | None):
    def predicate(activity: Activity) -> bool:
        if kind == "rain" and not activity.indoor:
            return False
        if kind == "fatigue" and activity.effort > 2:
            return False
        if kind == "budget":
            if original and original.price_estimate > 0:
                return activity.price_estimate <= max(original.price_estimate * 0.75, 12)
            return activity.price_estimate <= 20
        if kind == "time" and original:
            return activity.duration_minutes <= max(30, original.duration_minutes)
        return True

    return predicate


def analyse_rescue(
    db: Session,
    trip: Trip,
    members: list[TripMember],
    *,
    kind: str,
    item_id: str | None,
    extra_minutes: int,
    note: str | None,
) -> dict:
    all_items = (
        db.query(ItineraryItem)
        .filter(ItineraryItem.trip_id == trip.id, ItineraryItem.status == "confirmed")
        .order_by(ItineraryItem.day, ItineraryItem.start_time)
        .all()
    )
    if not all_items:
        return {
            "disruption": {"kind": kind, "label": KIND_LABELS.get(kind, kind)},
            "affected": [],
            "replacements": [],
            "message": "There is no confirmed itinerary to repair yet.",
            "requires_approval": True,
        }

    today = date.today()
    upcoming = [item for item in all_items if item.day >= today]
    pool = upcoming or all_items
    if not item_id:
        # Focus on the nearest day with items so rescue is actionable.
        nearest_day = sorted({item.day for item in pool})[0]
        pool = [item for item in pool if item.day == nearest_day]

    affected = _pick_affected(db, pool, kind, item_id)
    protected_targets = [entry for entry in affected if entry["item"].is_protected]
    affected = [entry for entry in affected if not entry["item"].is_protected]
    activities = _activity_map(db, all_items)
    planned_ids = {item.activity_id for item in all_items if item.activity_id}

    recommendation = generate_recommendations(
        db,
        trip,
        members,
        mode="everyone_wins",
        for_date=pool[0].day if pool else today,
        limit=10,
    )
    candidates = [item for item in recommendation.get("items", []) if item.activity.id not in planned_ids]
    predicate = _replacement_filter(kind, activities.get(affected[0]["item"].activity_id) if affected and affected[0]["item"].activity_id else None)
    candidates = [candidate for candidate in candidates if predicate(candidate.activity)]

    shadowplans = {
        plan.itinerary_item_id: plan
        for plan in db.query(Shadowplan)
        .filter(Shadowplan.trip_id == trip.id)
        .all()
    }

    proposals = []
    total_cost_delta = 0.0
    total_duration_delta = 0

    def slot_minutes(item: ItineraryItem) -> int:
        start = parse_hhmm(item.start_time)
        if start is None:
            return 0
        later = []
        for other in all_items:
            if other.id == item.id or other.day != item.day or other.status != "confirmed":
                continue
            window = item_window(db, other)
            if window and window[0] >= start:
                later.append(window[0])
        end = min(later) if later else DAY_END_MINUTES
        return max(0, end - start)

    for entry in affected:
        item: ItineraryItem = entry["item"]
        available = slot_minutes(item)
        original = activities.get(item.activity_id) if item.activity_id else None
        original_coords = _place_coords(db, original)
        original_travel = (
            travel_minutes(haversine_km(trip.base_lat, trip.base_lon, *original_coords))
            if original_coords != (0.0, 0.0)
            else 0
        )
        backup = shadowplans.get(item.id)
        backup_activity = db.get(Activity, backup.backup_activity_id) if backup else None
        options = []
        if backup_activity and backup_activity.duration_minutes <= available:
            options.append(
                {
                    "activity": backup_activity,
                    "source": "shadowplan",
                    "note": "Pre-agreed backup attached to this item." if backup.notes is None else backup.notes,
                    "ready": True,
                    "score": None,
                }
            )
        fitting = 0
        for candidate in candidates:
            if fitting >= 3:
                break
            if backup_activity and candidate.activity.id == backup_activity.id:
                continue
            if candidate.activity.duration_minutes > available:
                continue
            fitting += 1
            options.append(
                {
                    "activity": candidate.activity,
                    "source": "engine",
                    "score": candidate.score,
                    "note": (candidate.explanation or {}).get("summary"),
                    "ready": True,
                    "distance_km": candidate.distance_km,
                }
            )
        if not options and original:
            options.append(
                {
                    "activity": None,
                    "source": "none",
                    "note": (
                        "No feasible replacement fits this slot without running into "
                        "protected time or the next confirmed item. Consider updating a "
                        "Trip Pulse, widening the radius, or keeping the original with a contingency."
                    ),
                    "ready": False,
                    "score": None,
                }
            )
        best = options[0] if options else None
        if best and best.get("activity"):
            replacement_cost = best["activity"].price_estimate
            replacement_coords = _place_coords(db, best["activity"])
            replacement_travel = (
                travel_minutes(haversine_km(trip.base_lat, trip.base_lon, *replacement_coords))
                if replacement_coords != (0.0, 0.0)
                else 0
            )
            total_cost_delta += replacement_cost - item.cost_estimate
            total_duration_delta += best["activity"].duration_minutes - (original.duration_minutes if original else 90)
        else:
            replacement_travel = 0
        proposals.append(
            {
                "item_id": item.id,
                "day": item.day,
                "title": item.title,
                "start_time": item.start_time,
                "reason": entry["reason"],
                "original_activity": (
                    {
                        "id": original.id,
                        "name": original.name,
                        "price": original.price_estimate,
                        "duration": original.duration_minutes,
                        "indoor": original.indoor,
                        "effort": original.effort,
                    }
                    if original
                    else None
                ),
                "travel_minutes": original_travel,
                "options": [
                    {
                        "activity_id": option["activity"].id if option["activity"] else None,
                        "name": option["activity"].name if option["activity"] else "No feasible replacement",
                        "price": option["activity"].price_estimate if option["activity"] else None,
                        "duration": option["activity"].duration_minutes if option["activity"] else None,
                        "indoor": option["activity"].indoor if option["activity"] else None,
                        "effort": option["activity"].effort if option["activity"] else None,
                        "source": option["source"],
                        "score": option["score"],
                        "note": option["note"],
                        "ready": option["ready"],
                    }
                    for option in options
                ],
                "recommended": best["activity"].name if best and best.get("activity") else None,
                "recommended_activity_id": (
                    best["activity"].id if best and best.get("activity") else None
                ),
            }
        )

    pact = db.query(JourneyPact).filter(JourneyPact.trip_id == trip.id).first()
    conflicts = []
    if pact:
        must_do = {str(title).lower() for title in (pact.must_do or [])}
        for entry in affected:
            title = entry["item"].title.lower()
            if any(item_title in title or title in item_title for item_title in must_do):
                conflicts.append(
                    {
                        "item": entry["item"].title,
                        "pact_rule": "Part of the agreed must-do list.",
                        "needed": "An explicit exception from the group before this can change.",
                    }
                )

    return {
        "disruption": {
            "kind": kind,
            "label": KIND_LABELS.get(kind, kind),
            "note": note,
            "extra_minutes": extra_minutes,
        },
        "target_day": (affected[0]["item"].day if affected else (pool[0].day if pool else None)),
        "affected": [
            {
                "item_id": entry["item"].id,
                "title": entry["item"].title,
                "start_time": entry["item"].start_time,
                "reason": entry["reason"],
            }
            for entry in affected
        ],
        "protected": [
            {
                "item_id": entry["item"].id,
                "title": entry["item"].title,
                "start_time": entry["item"].start_time,
                "reason": "Protected time is reserved. Trip Rescue will not replace or move it.",
            }
            for entry in protected_targets
        ],
        "proposals": proposals,
        "consequences": {
            "cost_delta": round(total_cost_delta, 2),
            "duration_delta_minutes": total_duration_delta,
            "time_saved_or_lost": f"{extra_minutes} minutes of disruption accounted for",
            "pact_conflicts": conflicts,
            "protected_respected": bool(protected_targets),
        },
        "requires_approval": True,
        "disclosure": (
            "Nothing has been changed. This is a proposed repair. "
            "The group must approve it before the confirmed itinerary changes."
        ),
    }


def compromise(
    db: Session,
    trip: Trip,
    members: list[TripMember],
    option_a: list[str],
    option_b: list[str],
    for_date: date | None = None,
) -> dict:
    """Build a fair-trade compromise from two competing options (F45).

    Feasibility is evaluated for the day being negotiated, not the server's
    current date, so past and future trip days behave consistently.
    """

    by_id = {
        activity.id: activity
        for activity in db.query(Activity).filter(Activity.id.in_(set(option_a + option_b) or {""})).all()
    }
    a = [by_id[aid] for aid in option_a if aid in by_id]
    b = [by_id[aid] for aid in option_b if aid in by_id]
    if not a or not b:
        return {
            "status": "needs_options",
            "message": "Provide at least one activity for each side of the negotiation.",
        }

    target_date = for_date or date.today()
    rec = generate_recommendations(
        db, trip, members, mode="everyone_wins", for_date=target_date, limit=12
    )
    ranked = {item.activity.id: item for item in rec.get("items", [])}

    def best(pool: list[Activity]):
        scored = [ranked[activity.id] for activity in pool if activity.id in ranked]
        return max(scored, key=lambda item: item.minimum_fit) if scored else None

    best_a = best(a)
    best_b = best(b)
    if not best_a or not best_b:
        return {
            "status": "no_feasible_option",
            "message": "One or both options violate a hard constraint for at least one member.",
        }

    compromise_choice = best_a if best_a.minimum_fit >= best_b.minimum_fit else best_b
    other = best_b if compromise_choice is best_a else best_a
    benefits = sorted(
        {
            normalize_tag(tag)
            for tag in (compromise_choice.activity.tags or [])
            if tag
        }
    )[:3]
    return {
        "status": "compromise_ready",
        "compromise": {
            "activity_id": compromise_choice.activity.id,
            "name": compromise_choice.activity.name,
            "minimum_fit": compromise_choice.minimum_fit,
            "average_fit": compromise_choice.average_fit,
        },
        "alternative": {
            "activity_id": other.activity.id,
            "name": other.activity.name,
            "minimum_fit": other.minimum_fit,
            "average_fit": other.average_fit,
        },
        "who_benefits": f"Members interested in {', '.join(benefits) or 'the activity themes'}.",
        "who_compromises": "Members whose first choice was the other option; the protected minimum fit stays highest here.",
        "trade_offs": [
            f"Protected minimum fit {compromise_choice.minimum_fit}/100 versus {other.minimum_fit}/100 for the alternative.",
            f"Average fit {compromise_choice.average_fit}/100 versus {other.average_fit}/100.",
            "Private constraints stayed private; only aggregate suitability is shown.",
        ],
        "feasible": True,
        "disclosure": "Apply only with group approval. No private budget or preference is exposed.",
    }
