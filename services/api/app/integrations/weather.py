"""Open-Meteo weather adapter.

Free, keyless and attribution-based. Enabled only when
``SAFAR_WEATHER_PROVIDER=open-meteo``. Coordinates are rounded to roughly one
kilometre before leaving the server, and no user identifier is sent.
"""

from urllib.parse import urlencode

from app.core.config import settings
from app.integrations import base, http
from app.integrations.base import ProviderResult
from app.integrations.cache import TTLCache
from app.integrations.ratelimit import TokenBucket

PROVIDER = "open-meteo"
ATTRIBUTION = "Weather data by Open-Meteo.com (CC BY 4.0)"
_BASE_URL = "https://api.open-meteo.com/v1/forecast"
_cache = TTLCache(max_entries=128)
_bucket = TokenBucket(settings.weather_rate_limit_per_minute, burst=10)

_WMO = {
    0: "Clear sky",
    1: "Mainly clear",
    2: "Partly cloudy",
    3: "Overcast",
    45: "Fog",
    48: "Rime fog",
    51: "Light drizzle",
    53: "Drizzle",
    55: "Dense drizzle",
    56: "Freezing drizzle",
    57: "Dense freezing drizzle",
    61: "Light rain",
    63: "Rain",
    65: "Heavy rain",
    66: "Freezing rain",
    67: "Heavy freezing rain",
    71: "Light snow",
    73: "Snow",
    75: "Heavy snow",
    77: "Snow grains",
    80: "Light showers",
    81: "Showers",
    82: "Violent showers",
    85: "Snow showers",
    86: "Heavy snow showers",
    95: "Thunderstorm",
    96: "Thunderstorm with hail",
    99: "Severe thunderstorm with hail",
}


def reset() -> None:
    _cache.clear()
    _bucket.reset()


def enabled() -> bool:
    return settings.weather_provider == PROVIDER


def status() -> dict:
    return {
        "provider": PROVIDER,
        "enabled": enabled(),
        "network": True,
        "key_required": False,
        "provenance": base.PREDICTED,
        "attribution": ATTRIBUTION,
        "cache_seconds": settings.weather_cache_ttl_seconds,
        "notes": (
            ["Forecasts are predictions, not observed weather. Coordinates are rounded."]
            if enabled()
            else ["Disabled. The assistant states that no weather provider is configured."]
        ),
    }


def weather_label(code: int | None) -> str:
    if code is None:
        return "Unknown conditions"
    return _WMO.get(int(code), "Unclassified conditions")


def _parse(payload: dict) -> dict | None:
    daily = payload.get("daily") or {}
    days = daily.get("time") or []
    if not days:
        return None
    codes = daily.get("weather_code") or []
    highs = daily.get("temperature_2m_max") or []
    lows = daily.get("temperature_2m_min") or []
    rain = daily.get("precipitation_probability_max") or []
    rows = []
    for index, day in enumerate(days):
        code = codes[index] if index < len(codes) else None
        rows.append(
            {
                "date": day,
                "weather_code": code,
                "conditions": weather_label(code),
                "temperature_max": highs[index] if index < len(highs) else None,
                "temperature_min": lows[index] if index < len(lows) else None,
                "precipitation_probability": rain[index] if index < len(rain) else None,
            }
        )
    current_raw = payload.get("current") or {}
    current = None
    if current_raw:
        current = {
            "time": current_raw.get("time"),
            "temperature": current_raw.get("temperature_2m"),
            "weather_code": current_raw.get("weather_code"),
            "conditions": weather_label(current_raw.get("weather_code")),
            "precipitation": current_raw.get("precipitation"),
        }
    return {
        "timezone": payload.get("timezone"),
        "units": payload.get("current_units") or payload.get("daily_units") or {},
        "current": current,
        "days": rows,
    }


def forecast(lat: float, lon: float, days: int = 3) -> ProviderResult:
    if not enabled():
        return base.unavailable(
            PROVIDER, "No weather provider is configured on this deployment."
        )
    try:
        latitude = round(float(lat), 2)
        longitude = round(float(lon), 2)
    except (TypeError, ValueError):
        return base.failed(PROVIDER, "invalid_location", "A valid location is needed for weather.")
    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        return base.failed(PROVIDER, "invalid_location", "A valid location is needed for weather.")
    requested_days = max(1, min(int(days or 3), 7))
    key = f"weather:{latitude}:{longitude}:{requested_days}"
    cached = _cache.get(key)
    if cached:
        value, _ = cached
        return ProviderResult(
            ok=True,
            provider=PROVIDER,
            data=value,
            provenance=base.PREDICTED,
            fetched_at=base.now(),
            cached=True,
            attribution=ATTRIBUTION,
            message="Cached forecast. Forecasts are predictions, not observations.",
        )
    if not _bucket.allow():
        return base.failed(
            PROVIDER, "rate_limited", "Weather was requested too often. Try again shortly."
        )
    query = urlencode(
        {
            "latitude": latitude,
            "longitude": longitude,
            "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
            "current": "temperature_2m,weather_code,precipitation",
            "timezone": "auto",
            "forecast_days": requested_days,
        }
    )
    try:
        payload = http.fetch_json(
            f"{_BASE_URL}?{query}", timeout=settings.provider_timeout_seconds
        )
    except http.FetchError as exc:
        return base.failed(PROVIDER, exc.code, exc.message)
    if payload.get("error"):
        return base.failed(
            PROVIDER, "provider_error", "The weather provider could not return a forecast."
        )
    data = _parse(payload)
    if data is None:
        return base.failed(
            PROVIDER, "empty_response", "The weather provider returned no forecast days."
        )
    _cache.set(key, data, settings.weather_cache_ttl_seconds)
    return ProviderResult(
        ok=True,
        provider=PROVIDER,
        data=data,
        provenance=base.PREDICTED,
        fetched_at=base.now(),
        attribution=ATTRIBUTION,
        message="Forecast from Open-Meteo. It is a prediction, not an observation.",
    )
