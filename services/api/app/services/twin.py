"""Trip Twin (F08): compare alternatives without touching the confirmed plan."""

from datetime import date

from sqlalchemy.orm import Session

from app.models import Activity, ItineraryItem, Place, Trip, TripMember
from app.services.engine import rank_activity
from app.services.geo import haversine_km, travel_minutes


def _activity_coords(db: Session, activity: Activity) -> tuple[float, float]:
    if not activity.place_id:
        return (0.0, 0.0)
    place = db.get(Place, activity.place_id)
    return (place.lat, place.lon) if place else (0.0, 0.0)


def _metrics_for_activities(
    db: Session,
    trip: Trip,
    contexts,
    activities: list[Activity],
    fallback_costs: dict[str, float] | None = None,
    fallback_durations: dict[str, int] | None = None,
) -> dict:
    fits: list[list[float]] = [[] for _ in contexts]
    total_cost = 0.0
    total_duration = 0
    total_travel = 0
    details = []
    for activity in activities:
        coords = _activity_coords(db, activity)
        distance = haversine_km(trip.base_lat, trip.base_lon, *coords) if coords != (0.0, 0.0) else 0.0
        leg = travel_minutes(distance)
        ranked = rank_activity(
            activity,
            contexts,
            base_lat=trip.base_lat,
            base_lon=trip.base_lon,
            coords=coords,
            target_member_index=None,
            mode="everyone_wins",
        )
        if ranked:
            for index, fit in enumerate(ranked.fits):
                fits[index].append(fit)
        total_cost += activity.price_estimate
        total_duration += activity.duration_minutes
        total_travel += leg
        details.append(
            {
                "activity_id": activity.id,
                "name": activity.name,
                "cost": activity.price_estimate,
                "duration": activity.duration_minutes,
                "distance_km": distance,
                "travel_minutes": leg,
                "eligible": ranked is not None,
            }
        )
    per_member = [sum(values) / len(values) for values in fits if values]
    return {
        "total_cost": round(total_cost, 2),
        "total_duration_minutes": total_duration,
        "total_travel_minutes": total_travel,
        "average_group_fit": round(sum(per_member) / len(per_member), 1) if per_member else None,
        "minimum_member_fit": round(min(per_member), 1) if per_member else None,
        "items": details,
    }


def compare_plan(
    db: Session,
    trip: Trip,
    contexts,
    items: list[ItineraryItem],
    candidate_ids: list[str],
    day: date | None = None,
) -> dict:
    from app.services.common import utcnow

    day = day or date.today()
    confirmed_activities = []
    by_id = {}
    activity_ids = [item.activity_id for item in items if item.activity_id]
    if activity_ids:
        by_id = {a.id: a for a in db.query(Activity).filter(Activity.id.in_(activity_ids)).all()}
        for item in sorted(items, key=lambda i: (i.day, i.start_time)):
            if item.activity_id and item.activity_id in by_id:
                confirmed_activities.append(by_id[item.activity_id])

    candidate_activities = (
        db.query(Activity).filter(Activity.id.in_(candidate_ids)).all()
        if candidate_ids
        else []
    )
    order = {activity_id: index for index, activity_id in enumerate(candidate_ids)}
    candidate_activities.sort(key=lambda activity: order.get(activity.id, 999))

    current = _metrics_for_activities(db, trip, contexts, confirmed_activities)
    alternative = _metrics_for_activities(db, trip, contexts, candidate_activities)

    current_ids = [activity.id for activity in confirmed_activities]
    alt_ids = [activity.id for activity in candidate_activities]
    removed = [
        {"activity_id": activity.id, "name": activity.name}
        for activity in confirmed_activities
        if activity.id not in alt_ids
    ]
    added = [
        {"activity_id": activity.id, "name": activity.name}
        for activity in candidate_activities
        if activity.id not in current_ids
    ]
    kept = [
        {"activity_id": activity.id, "name": activity.name}
        for activity in candidate_activities
        if activity.id in current_ids
    ]

    tradeoffs = []
    if current["average_group_fit"] is not None and alternative["average_group_fit"] is not None:
        delta = alternative["average_group_fit"] - current["average_group_fit"]
        tradeoffs.append(
            f"Average group fit {'improves' if delta >= 0 else 'drops'} by {abs(delta):.1f} points."
        )
    if current["minimum_member_fit"] is not None and alternative["minimum_member_fit"] is not None:
        delta = alternative["minimum_member_fit"] - current["minimum_member_fit"]
        tradeoffs.append(
            f"The least-served member's fit {'improves' if delta >= 0 else 'drops'} by {abs(delta):.1f} points."
        )
    cost_delta = round(alternative["total_cost"] - current["total_cost"], 2)
    tradeoffs.append(
        f"Estimated cost {'rises' if cost_delta > 0 else 'falls'} by {abs(cost_delta):.2f}."
    )
    time_delta = alternative["total_duration_minutes"] - current["total_duration_minutes"]
    tradeoffs.append(
        f"Activity time {'increases' if time_delta > 0 else 'decreases'} by {abs(time_delta)} minutes."
    )
    if alternative["minimum_member_fit"] is not None and alternative["minimum_member_fit"] < 45:
        tradeoffs.append("Caution: at least one member is below 45/100 on this alternative.")

    return {
        "day": day,
        "confirmed_plan": {"name": "Confirmed plan", **current},
        "alternative_plan": {"name": "Trip Twin alternative", **alternative},
        "diff": {"added": added, "removed": removed, "kept": kept},
        "trade_offs": tradeoffs,
        "requires_approval": True,
        "disclosure": (
            "This comparison is read-only. Adopting it creates a proposal; "
            "the confirmed itinerary is only changed after group approval."
        ),
        "generated_at": utcnow(),
    }
