"""Opportunity Clock (F24).

Answers one honest question for a single day: which catalog activities still
fit the day that is already planned, given today's opening hours and an
estimated door-to-door travel time?

It is a read-only deterministic calculation. It never writes to the database,
never touches the confirmed itinerary and never claims to know live opening
status: hours come from the catalog, travel is an estimate, and a missing
window is reported as unknown rather than guessed.
"""

import re
from datetime import date, datetime

from sqlalchemy.orm import Session

from app.models import Activity, Itinerary, ItineraryItem, Place, Trip
from app.services.geo import haversine_km, travel_minutes

DAY_START = 8 * 60
DAY_END = 22 * 60
WEEKDAY_KEYS = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")
_RANGE = re.compile(r"(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})")

STATUS_ORDER = {
    "open_now": 0,
    "later_today": 1,
    "no_window": 2,
    "closed_today": 3,
    "unknown": 4,
}


def _hhmm_to_minutes(value: str) -> int | None:
    try:
        hours, minutes = value.split(":")
        return int(hours) * 60 + int(minutes)
    except (ValueError, AttributeError):
        return None


def _minutes_to_hhmm(total: int) -> str:
    total = max(0, min(24 * 60 - 1, total))
    return f"{total // 60:02d}:{total % 60:02d}"


def parse_opening_window(raw: str | None) -> tuple[str, tuple[int, int] | None]:
    """Return (kind, window) where kind is open/closed/unknown."""
    if raw is None or not str(raw).strip():
        return "unknown", None
    value = str(raw).strip().lower()
    if value in {"closed", "closed today", "shut"}:
        return "closed", None
    if "24" in value and ("hour" in value or "open" in value):
        return "open", (0, 24 * 60)
    match = _RANGE.search(value)
    if match:
        start = int(match.group(1)) * 60 + int(match.group(2))
        end = int(match.group(3)) * 60 + int(match.group(4))
        if end <= start:
            return "unknown", None
        return "open", (start, end)
    return "unknown", None


def _confirmed_spans(db: Session, trip: Trip, on: date) -> list[tuple[int, int, str]]:
    rows = (
        db.query(ItineraryItem)
        .filter(
            ItineraryItem.trip_id == trip.id,
            ItineraryItem.day == on,
            ItineraryItem.status == "confirmed",
        )
        .order_by(ItineraryItem.start_time)
        .all()
    )
    spans: list[tuple[int, int, str]] = []
    for item in rows:
        start = _hhmm_to_minutes(item.start_time) or DAY_START
        end = _hhmm_to_minutes(item.end_time or "") if item.end_time else None
        if end is None:
            activity = db.get(Activity, item.activity_id) if item.activity_id else None
            duration = activity.duration_minutes if activity else 90
            end = start + (duration or 90)
        spans.append((start, max(start + 15, end), item.title))
    return spans


def _free_windows(spans: list[tuple[int, int, str]]) -> list[tuple[int, int]]:
    cursor = DAY_START
    windows: list[tuple[int, int]] = []
    for start, end, _title in sorted(spans):
        if start > cursor:
            windows.append((cursor, min(start, DAY_END)))
        cursor = max(cursor, end)
        if cursor >= DAY_END:
            break
    if cursor < DAY_END:
        windows.append((cursor, DAY_END))
    return [(start, end) for start, end in windows if end - start >= 30]


def _intersect(
    free: list[tuple[int, int]], opening: tuple[int, int]
) -> list[tuple[int, int]]:
    result = []
    for f_start, f_end in free:
        start = max(f_start, opening[0])
        end = min(f_end, opening[1])
        if end - start >= 30:
            result.append((start, end))
    return result


def clock(db: Session, trip: Trip, on: date) -> dict:
    itinerary = db.query(Itinerary).filter(Itinerary.trip_id == trip.id).first()
    confirmed_version = itinerary.confirmed_version if itinerary else None

    if not trip.destination_id:
        return {
            "date": on.isoformat(),
            "available": False,
            "reason": "Set a destination for this trip before using the Opportunity Clock.",
            "items": [],
            "summary": {"candidates": 0, "open_now": 0, "later_today": 0, "unknown_hours": 0},
            "disclosure": (
                "The clock only reads the catalog and the confirmed plan. It never changes either."
            ),
            "plan_unchanged": True,
            "confirmed_version": confirmed_version,
        }

    spans = _confirmed_spans(db, trip, on)
    free = _free_windows(spans)
    confirmed_activity_ids = {
        row[0]
        for row in db.query(ItineraryItem.activity_id)
        .filter(
            ItineraryItem.trip_id == trip.id,
            ItineraryItem.day == on,
            ItineraryItem.status == "confirmed",
            ItineraryItem.activity_id.isnot(None),
        )
        .all()
    }

    activities = (
        db.query(Activity)
        .filter(Activity.destination_id == trip.destination_id)
        .order_by(Activity.popularity.desc())
        .all()
    )
    today = date.today()
    now_minutes = datetime.now().hour * 60 + datetime.now().minute if on == today else None
    weekday = WEEKDAY_KEYS[on.weekday()]

    items = []
    for activity in activities:
        if activity.id in confirmed_activity_ids:
            continue
        place = db.get(Place, activity.place_id)
        distance = (
            haversine_km(trip.base_lat, trip.base_lon, place.lat, place.lon)
            if place
            else 0.0
        )
        travel = travel_minutes(distance)
        duration = activity.duration_minutes or 90
        needed = travel + duration

        raw_hours = (activity.opening_hours or {}).get(weekday)
        kind, opening = parse_opening_window(raw_hours)
        next_start: int | None = None
        status = "unknown"
        explanation = ""

        if kind == "open" and opening:
            windows = _intersect(free, opening)
            feasible = [
                (start, end)
                for start, end in windows
                if end - start >= needed
            ]
            if not feasible:
                status = "no_window"
                explanation = (
                    f"Open {_minutes_to_hhmm(opening[0])}–{_minutes_to_hhmm(opening[1])}, "
                    f"but no free gap today fits {duration} min plus about {travel} min travel."
                )
            else:
                starts = [start for start, _end in feasible]
                if now_minutes is not None:
                    upcoming = [
                        (start, end) for start, end in feasible if end - now_minutes >= needed
                    ]
                    if upcoming:
                        next_start = max(upcoming[0][0], now_minutes)
                        fits_now = (
                            opening[0] <= now_minutes <= opening[1]
                            and upcoming[0][0] <= now_minutes
                        )
                        status = "open_now" if fits_now else "later_today"
                        explanation = (
                            f"Open now and a free gap runs until {_minutes_to_hhmm(upcoming[0][1])}; "
                            f"{duration} min plus about {travel} min travel fits."
                            if fits_now
                            else f"Next feasible start is {_minutes_to_hhmm(next_start)}."
                        )
                    else:
                        status = "window_missed"
                        explanation = (
                            f"Open {_minutes_to_hhmm(opening[0])}–{_minutes_to_hhmm(opening[1])}, "
                            "but that window has already closed for today."
                        )
                else:
                    next_start = starts[0]
                    status = "later_today"
                    explanation = (
                        f"Fits from {_minutes_to_hhmm(next_start)} inside "
                        f"{_minutes_to_hhmm(feasible[0][1])}."
                    )
        elif kind == "closed":
            status = "closed_today"
            explanation = "The catalog lists this place as closed on this weekday."
        else:
            status = "unknown"
            explanation = (
                "No usable opening hours are recorded for this weekday, so feasibility cannot be estimated."
            )

        items.append(
            {
                "activity_id": activity.id,
                "name": activity.name,
                "place_name": place.name if place else None,
                "duration_minutes": duration,
                "price_estimate": activity.price_estimate,
                "currency": activity.currency,
                "opening_hours_today": raw_hours,
                "opening_source": activity.source_type,
                "last_verified_at": activity.last_verified_at.isoformat()
                if activity.last_verified_at
                else None,
                "travel_minutes_estimate": travel,
                "status": status,
                "next_start": _minutes_to_hhmm(next_start) if next_start is not None else None,
                "explanation": explanation,
                "provenance": "ESTIMATED",
            }
        )

    items.sort(key=lambda row: (STATUS_ORDER.get(row["status"], 9), row["name"]))
    summary = {
        "candidates": len(items),
        "open_now": len([row for row in items if row["status"] == "open_now"]),
        "later_today": len([row for row in items if row["status"] == "later_today"]),
        "closed_today": len([row for row in items if row["status"] == "closed_today"]),
        "unknown_hours": len([row for row in items if row["status"] == "unknown"]),
    }
    planned = [title for _start, _end, title in spans]
    explanation = (
        "Nothing fit the remaining gaps of this day."
        if not summary["open_now"] and not summary["later_today"]
        else f"{summary['open_now']} option(s) fit right now and {summary['later_today']} fit later today."
    )
    return {
        "date": on.isoformat(),
        "available": True,
        "weekday": weekday,
        "now": _minutes_to_hhmm(now_minutes) if now_minutes is not None else None,
        "planned_count": len(spans),
        "planned_titles": planned,
        "free_windows": [
            {
                "start": _minutes_to_hhmm(start),
                "end": _minutes_to_hhmm(end),
                "minutes": end - start,
            }
            for start, end in free
        ],
        "items": items,
        "summary": summary,
        "explanation": explanation,
        "disclosure": (
            "Opening hours come from the catalog and may be stale; travel time is an estimate, "
            "not a routed ETA. This view is read-only and never changes the confirmed itinerary."
        ),
        "plan_unchanged": True,
        "confirmed_version": confirmed_version,
    }
