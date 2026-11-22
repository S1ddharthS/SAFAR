from math import asin, cos, radians, sin, sqrt


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    if not all(isinstance(v, (int, float)) for v in (lat1, lon1, lat2, lon2)):
        return 0.0
    r = 6371.0
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon / 2) ** 2
    return round(2 * r * asin(sqrt(a)), 2)


def travel_minutes(distance_km: float) -> int:
    """Honest estimate, not a routed ETA.

    Urban trips assume 25 km/h door-to-door; longer hops assume 45 km/h.
    A 6 minute access overhead is added. The UI labels this as an estimate.
    """
    if distance_km <= 0:
        return 0
    speed = 25.0 if distance_km <= 10 else 45.0
    return int(round((distance_km / speed) * 60 + 6))


def day_minutes(hhmm: str) -> int:
    try:
        hours, minutes = hhmm.split(":")
        return int(hours) * 60 + int(minutes)
    except (ValueError, AttributeError):
        return 9 * 60


def minutes_to_hhmm(total: int) -> str:
    total = total % (24 * 60)
    return f"{total // 60:02d}:{total % 60:02d}"
