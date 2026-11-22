"""Protected-time and day-schedule helpers (F39).

Protected itinerary items reserve a block of time. The engine treats those
blocks as busy when it decides what still fits in a day, proposals cannot
cancel them, and rescue cannot replace them.
"""

from sqlalchemy.orm import Session

from app.models import Activity, ItineraryItem

DEFAULT_DURATION_MINUTES = 90
DAY_START_MINUTES = 8 * 60
DAY_END_MINUTES = 22 * 60


def parse_hhmm(value: str | None) -> int | None:
    if not value:
        return None
    try:
        hour, minute = value.strip().split(":")[:2]
        minutes = int(hour) * 60 + int(minute)
    except (AttributeError, TypeError, ValueError):
        return None
    if 0 <= minutes <= 24 * 60:
        return minutes
    return None


def format_hhmm(minutes: int) -> str:
    return f"{(minutes // 60) % 24:02d}:{minutes % 60:02d}"


def item_duration(db: Session, item: ItineraryItem) -> int:
    start = parse_hhmm(item.start_time)
    end = parse_hhmm(item.end_time)
    if start is not None and end is not None and end > start:
        return end - start
    if item.activity_id:
        activity = db.get(Activity, item.activity_id)
        if activity and activity.duration_minutes:
            return activity.duration_minutes
    return DEFAULT_DURATION_MINUTES


def item_window(db: Session, item: ItineraryItem) -> tuple[int, int] | None:
    start = parse_hhmm(item.start_time)
    if start is None:
        return None
    return start, start + item_duration(db, item)


def busy_windows(db: Session, day_items: list[ItineraryItem]) -> list[dict]:
    windows = []
    for item in day_items:
        if item.status != "confirmed":
            continue
        window = item_window(db, item)
        if not window:
            continue
        windows.append(
            {
                "item_id": item.id,
                "title": item.title,
                "start": format_hhmm(window[0]),
                "end": format_hhmm(window[1]),
                "start_minutes": window[0],
                "end_minutes": window[1],
                "protected": bool(item.is_protected),
            }
        )
    windows.sort(key=lambda window: window["start_minutes"])
    return windows


def free_windows(
    windows: list[dict],
    day_start: int = DAY_START_MINUTES,
    day_end: int = DAY_END_MINUTES,
) -> list[dict]:
    free = []
    cursor = day_start
    for window in sorted(windows, key=lambda entry: entry["start_minutes"]):
        start = max(window["start_minutes"], day_start)
        if start > cursor:
            free.append({"start_minutes": cursor, "end_minutes": min(start, day_end)})
        cursor = max(cursor, window["end_minutes"])
        if cursor >= day_end:
            break
    if cursor < day_end:
        free.append({"start_minutes": cursor, "end_minutes": day_end})
    return [window for window in free if window["end_minutes"] > window["start_minutes"]]


def schedule_summary(db: Session, day_items: list[ItineraryItem]) -> dict:
    windows = busy_windows(db, day_items)
    free = free_windows(windows)
    protected = [window for window in windows if window["protected"]]
    return {
        "busy": windows,
        "protected": protected,
        "protected_count": len(protected),
        "free_windows": [
            {
                "start": format_hhmm(window["start_minutes"]),
                "end": format_hhmm(window["end_minutes"]),
                "minutes": window["end_minutes"] - window["start_minutes"],
            }
            for window in free
        ],
        "max_free_minutes": max(
            (window["end_minutes"] - window["start_minutes"] for window in free),
            default=0,
        ),
        "day_window": {
            "start": format_hhmm(DAY_START_MINUTES),
            "end": format_hhmm(DAY_END_MINUTES),
        },
        "note": (
            "Protected items reserve their time block; the engine only suggests "
            "activities with enough free time left in the day."
        ),
    }


def find_conflict(
    db: Session,
    day_items: list[ItineraryItem],
    *,
    start_minutes: int,
    duration_minutes: int,
    ignore_item_ids: set[str] | None = None,
) -> dict | None:
    end_minutes = start_minutes + duration_minutes
    ignored = ignore_item_ids or set()
    for item in day_items:
        if item.id in ignored or item.status != "confirmed":
            continue
        window = item_window(db, item)
        if not window:
            continue
        if start_minutes < window[1] and window[0] < end_minutes:
            return {
                "item_id": item.id,
                "title": item.title,
                "start": format_hhmm(window[0]),
                "end": format_hhmm(window[1]),
                "protected": bool(item.is_protected),
            }
    return None
