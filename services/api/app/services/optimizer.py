"""Deterministic schedule analysis: buffers, fragility, domino effects, effort.

This is deliberately explainable. It does not pretend to be an exact router:
travel legs use the same estimate as the engine and are labelled as such.
"""

from datetime import date

from sqlalchemy.orm import Session

from app.models import Activity, ItineraryItem, Place, Trip
from app.services.common import clamp
from app.services.geo import day_minutes, haversine_km, minutes_to_hhmm, travel_minutes


def _activity_map(db: Session, items: list[ItineraryItem]) -> dict[str, Activity]:
    ids = [item.activity_id for item in items if item.activity_id]
    if not ids:
        return {}
    return {
        activity.id: activity
        for activity in db.query(Activity).filter(Activity.id.in_(ids)).all()
    }


def _coords_map(db: Session, activities: dict[str, Activity]) -> dict[str, tuple[float, float]]:
    place_ids = [activity.place_id for activity in activities.values() if activity.place_id]
    places = (
        db.query(Place).filter(Place.id.in_(place_ids)).all() if place_ids else []
    )
    by_place = {place.id: (place.lat, place.lon) for place in places}
    return {
        activity_id: by_place.get(activity.place_id, (0.0, 0.0))
        for activity_id, activity in activities.items()
    }


def analyse_day(
    db: Session, items: list[ItineraryItem]
) -> list[dict]:
    activities = _activity_map(db, items)
    coords = _coords_map(db, activities)
    ordered = sorted(items, key=lambda item: day_minutes(item.start_time))
    result: list[dict] = []
    previous = None
    for item in ordered:
        activity = activities.get(item.activity_id) if item.activity_id else None
        duration = activity.duration_minutes if activity else 90
        start = day_minutes(item.start_time)
        leg_minutes = 0
        leg_km = 0.0
        if previous and item.activity_id and previous.activity_id:
            prev_coords = coords.get(previous.activity_id, (0.0, 0.0))
            cur_coords = coords.get(item.activity_id, (0.0, 0.0))
            if prev_coords != (0.0, 0.0) and cur_coords != (0.0, 0.0):
                leg_km = haversine_km(*prev_coords, *cur_coords)
                leg_minutes = travel_minutes(leg_km)
        result.append(
            {
                "item": item,
                "activity": activity,
                "start": start,
                "end": start + duration,
                "leg_minutes": leg_minutes,
                "leg_km": leg_km,
            }
        )
        previous = item

    for index, entry in enumerate(result):
        if index + 1 < len(result):
            next_entry = result[index + 1]
            buffer = next_entry["start"] - entry["end"] - next_entry["leg_minutes"]
            entry["buffer_minutes"] = buffer
            if buffer < 0:
                entry["buffer_status"] = "risky"
            elif buffer < 15:
                entry["buffer_status"] = "tight"
            else:
                entry["buffer_status"] = "comfortable"
        else:
            entry["buffer_minutes"] = None
            entry["buffer_status"] = "end"
    return result


def fragility_report(db: Session, trip: Trip, items: list[ItineraryItem]) -> dict:
    if not items:
        return {
            "resilience_score": None,
            "label": "No confirmed itinerary items to analyse",
            "days": [],
            "summary": {"comfortable": 0, "tight": 0, "risky": 0},
        }
    by_day: dict[date, list[ItineraryItem]] = {}
    for item in items:
        by_day.setdefault(item.day, []).append(item)

    days = []
    totals = {"comfortable": 0, "tight": 0, "risky": 0}
    for day, day_items in sorted(by_day.items()):
        entries = analyse_day(db, day_items)
        for entry in entries:
            status = entry["buffer_status"]
            if status in totals:
                totals[status] += 1
        days.append(
            {
                "day": day,
                "legs": [
                    {
                        "item_id": entry["item"].id,
                        "title": entry["item"].title,
                        "start_time": entry["item"].start_time,
                        "end_time": minutes_to_hhmm(entry["end"]),
                        "buffer_minutes": entry["buffer_minutes"],
                        "buffer_status": entry["buffer_status"],
                        "travel_minutes": entry["leg_minutes"],
                        "travel_km": entry["leg_km"],
                        "protected": entry["item"].is_protected,
                    }
                    for entry in entries
                ],
                "alternative_timings": _timing_alternatives(entries),
            }
        )

    checks = totals["comfortable"] + totals["tight"] + totals["risky"]
    weighted = totals["comfortable"] * 1.0 + totals["tight"] * 0.55 + totals["risky"] * 0.1
    score = round(100 * weighted / max(1, checks))
    if score >= 75:
        label = "Resilient — comfortable buffers across the plan"
    elif score >= 45:
        label = "Moderate — some legs need attention"
    else:
        label = "Fragile — tight or negative buffers are likely"
    return {
        "resilience_score": score,
        "label": label,
        "days": days,
        "summary": totals,
        "disclosure": "Buffers use estimated travel times, not live traffic.",
    }


def _timing_alternatives(entries: list[dict]) -> list[dict]:
    alternatives = []
    for entry in entries:
        buffer = entry.get("buffer_minutes")
        if buffer is None:
            continue
        if buffer < 15:
            shift = max(5, 15 - buffer)
            alternatives.append(
                {
                    "item_id": entry["item"].id,
                    "suggestion": f"Move {entry['item'].title} later or shorten it by about {shift} minutes.",
                    "minutes": shift,
                }
            )
    return alternatives


def domino_map(
    db: Session,
    items: list[ItineraryItem],
    disrupted_item_id: str,
    delay_minutes: int,
) -> dict | None:
    by_day: dict[date, list[ItineraryItem]] = {}
    for item in items:
        by_day.setdefault(item.day, []).append(item)
    target = next((item for item in items if item.id == disrupted_item_id), None)
    if not target:
        return None
    day_items = sorted(by_day.get(target.day, []), key=lambda item: day_minutes(item.start_time))
    entries = analyse_day(db, day_items)
    target_index = next(
        (index for index, entry in enumerate(entries) if entry["item"].id == disrupted_item_id),
        None,
    )
    if target_index is None:
        return None

    affected = []
    unaffected = []
    carry = delay_minutes
    for index, entry in enumerate(entries):
        if index < target_index:
            unaffected.append(
                {"item_id": entry["item"].id, "title": entry["item"].title, "reason": "before the disruption"}
            )
            continue
        if index == target_index:
            carry = delay_minutes
            affected.append(
                {
                    "item_id": entry["item"].id,
                    "title": entry["item"].title,
                    "slip_minutes": delay_minutes,
                    "new_start": minutes_to_hhmm(entry["start"] + delay_minutes),
                    "is_source": True,
                    "protected": entry["item"].is_protected,
                }
            )
            continue
        # Absorb delay with any buffer, then propagate the remainder.
        absorb = max(0, entry.get("buffer_minutes") or 0)
        absorbed = min(carry, absorb)
        net_slip = carry - absorbed
        if net_slip > 0:
            affected.append(
                {
                    "item_id": entry["item"].id,
                    "title": entry["item"].title,
                    "slip_minutes": net_slip,
                    "new_start": minutes_to_hhmm(entry["start"] + net_slip),
                    "is_source": False,
                    "protected": entry["item"].is_protected,
                }
            )
            carry = net_slip
        else:
            unaffected.append(
                {"item_id": entry["item"].id, "title": entry["item"].title, "reason": "buffer absorbs the delay"}
            )
            carry = 0

    repairs = []
    for entry in affected:
        if entry["is_source"]:
            continue
        repairs.append(
            {
                "item_id": entry["item_id"],
                "title": entry["title"],
                "options": [
                    f"Shorten by {entry['slip_minutes']} minutes.",
                    f"Move to {entry['new_start']} and confirm with the group.",
                    "Replace with its Shadowplan backup." if not entry["protected"] else "Protected time: ask the group before changing.",
                ],
            }
        )

    return {
        "day": target.day,
        "disruption": {
            "item_id": target.id,
            "title": target.title,
            "delay_minutes": delay_minutes,
        },
        "affected": affected,
        "unaffected": unaffected,
        "minimum_repairs_needed": len(repairs),
        "repair_options": repairs,
        "disclosure": "Propagation uses planned durations and estimated travel time.",
    }


def effort_budget(db: Session, items: list[ItineraryItem]) -> dict:
    activities = _activity_map(db, items)
    coords = _coords_map(db, activities)
    ordered = sorted(items, key=lambda item: (item.day, day_minutes(item.start_time)))
    walking_km = 0.0
    effort_points = 0
    rest_minutes = 0
    transitions = 0
    previous = None
    for item in ordered:
        activity = activities.get(item.activity_id) if item.activity_id else None
        if item.is_protected:
            rest_minutes += 60
        elif activity:
            effort_points += activity.effort
        if previous and item.activity_id and previous.activity_id and item.day == previous.day:
            prev_coords = coords.get(previous.activity_id, (0.0, 0.0))
            cur_coords = coords.get(item.activity_id, (0.0, 0.0))
            if prev_coords != (0.0, 0.0) and cur_coords != (0.0, 0.0):
                walking_km += haversine_km(*prev_coords, *cur_coords) * 1.25
                transitions += 1
        previous = item
    walking_minutes = int(round(walking_km * 12))
    effort_level = "light" if effort_points <= 6 else "moderate" if effort_points <= 12 else "demanding"
    return {
        "effort_points": effort_points,
        "effort_level": effort_level,
        "walking_km_estimate": round(walking_km, 2),
        "walking_minutes_estimate": walking_minutes,
        "transitions": transitions,
        "protected_rest_minutes": rest_minutes,
        "heat_exposure": "unknown — no weather source is configured",
        "accessibility_note": "Hard accessibility requirements are never traded for a lower effort score.",
        "disclosure": "Effort points derive from catalog intensity; walking distance is a straight-line estimate adjusted for streets.",
    }


def scored_plan(
    db: Session,
    trip: Trip,
    items: list[ItineraryItem],
    contexts,
) -> dict:
    """Plan-level metrics used by Trip Twin."""
    from app.services.engine import rank_activity

    activities = _activity_map(db, items)
    coords = _coords_map(db, activities)
    total_cost = sum(item.cost_estimate for item in items)
    total_duration = 0
    total_travel = 0
    fits: list[list[float]] = [[] for _ in contexts]
    for index, item in enumerate(sorted(items, key=lambda i: (i.day, day_minutes(i.start_time)))):
        activity = activities.get(item.activity_id) if item.activity_id else None
        if not activity:
            continue
        total_duration += activity.duration_minutes
        ranked = rank_activity(
            activity,
            contexts,
            base_lat=trip.base_lat,
            base_lon=trip.base_lon,
            coords=coords.get(activity.id, (0.0, 0.0)),
            target_member_index=None,
            mode="everyone_wins",
        )
        total_travel += travel_minutes(ranked.distance_km) if ranked else 0
        if ranked:
            for member_index, fit in enumerate(ranked.fits):
                fits[member_index].append(fit)
    averages = [sum(values) / len(values) for values in fits if values]
    return {
        "items_count": len(items),
        "total_cost": round(total_cost, 2),
        "total_duration_minutes": total_duration,
        "total_travel_minutes": total_travel,
        "average_group_fit": round(sum(averages) / len(averages), 1) if averages else None,
        "minimum_member_fit": round(min(averages), 1) if averages else None,
        "effort": effort_budget(db, items),
    }
