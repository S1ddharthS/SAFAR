"""Place intelligence: provenance, freshness, crowd forecasting, evidence (F14, F21, F30, F40, F41)."""

from datetime import datetime, timedelta
from math import exp, log, sqrt

from sqlalchemy.orm import Session

from app.models import Activity, Place, PlaceReport
from app.models.models import utcnow

CROWD_MODEL = "bucket-forecast-v2"
CROWD_MIN_REPORTS = 8
CROWD_MIN_BUCKET_REPORTS = 3
CROWD_WINDOW_DAYS = 180
CROWD_MAX_AGE_DAYS = 120
CROWD_STALE_DAYS = 60
_LEVEL_SCORES = {
    "low": 0.25,
    "quiet": 0.2,
    "moderate": 0.5,
    "medium": 0.5,
    "busy": 0.7,
    "high": 0.8,
    "very_high": 0.95,
    "extreme": 1.0,
}
_GRANULARITY_FACTOR = {
    "weekday_bucket": 1.0,
    "weekday": 0.8,
    "day_type_bucket": 0.75,
}

SOURCE_LABELS = {
    "official": "Officially sourced",
    "community": "Community reported",
    "estimated": "Estimated",
    "unknown": "Unknown",
}


def freshness(observed_at: datetime, source_type: str, verified: bool = False) -> float:
    age_days = max(0.0, (utcnow() - observed_at).total_seconds() / 86400)
    half_life = 90 if source_type == "official" else 30 if verified else 7
    score = exp(-log(2) * age_days / half_life)
    if verified:
        score = min(1.0, score * 1.15)
    return round(score, 3)


def provenance(source_type: str, verified: bool) -> str:
    if source_type == "official" and verified:
        return "VERIFIED"
    if source_type == "official":
        return "REPORTED"
    return {
        "community": "REPORTED",
        "estimated": "ESTIMATED",
        "unknown": "UNKNOWN",
    }.get(source_type, "UNKNOWN")


def freshness_label(score: float) -> str:
    if score >= 0.75:
        return "fresh"
    if score >= 0.4:
        return "recent but fading"
    if score >= 0.15:
        return "old — treat with caution"
    return "stale — do not rely on it alone"


def relevant_reports(db: Session, activity_id: str, days: int = 90) -> list[PlaceReport]:
    cutoff = utcnow() - timedelta(days=days)
    return (
        db.query(PlaceReport)
        .filter(
            PlaceReport.activity_id == activity_id,
            PlaceReport.observed_at >= cutoff,
        )
        .order_by(PlaceReport.observed_at.desc())
        .all()
    )


def aggregate_reports(db: Session, activity_id: str) -> dict:
    reports = relevant_reports(db, activity_id)
    categories: dict[str, list[dict]] = {}
    for report in reports:
        weight = freshness(report.observed_at, report.source_type, report.verified) * report.confidence
        categories.setdefault(report.category, []).append(
            {
                "id": report.id,
                "value": report.value or {},
                "note": report.note,
                "observed_at": report.observed_at,
                "source_type": report.source_type,
                "source_label": SOURCE_LABELS.get(report.source_type, "Unknown"),
                "provenance": provenance(report.source_type, report.verified),
                "verified": report.verified,
                "verification": (
                    "official_verified"
                    if report.verified and report.source_type == "official"
                    else "moderator_verified"
                    if report.verified
                    else "unverified"
                ),
                "confidence": report.confidence,
                "freshness": freshness(report.observed_at, report.source_type, report.verified),
                "weight": round(weight, 3),
            }
        )
    summary = []
    for category, entries in categories.items():
        entries.sort(key=lambda entry: entry["weight"], reverse=True)
        leader = entries[0]
        summary.append(
            {
                "category": category,
                "status": leader["provenance"],
                "source_type": leader["source_type"],
                "source_label": leader["source_label"],
                "latest_observed_at": leader["observed_at"],
                "freshness": leader["freshness"],
                "freshness_label": freshness_label(leader["freshness"]),
                "confidence": leader["confidence"],
                "reports_count": len(entries),
                "weighted_support": round(sum(entry["weight"] for entry in entries), 3),
                "reports": entries,
            }
        )
    summary.sort(key=lambda item: item["weighted_support"], reverse=True)
    return {
        "activity_id": activity_id,
        "window_days": 90,
        "has_data": bool(reports),
        "categories": summary,
        "disclosure": (
            "Community observations are not official facts. Freshness decays over time; "
            "verified official sources rank above community reports."
        ),
    }


def count_bucket(hour: int) -> str:
    if 8 <= hour < 12:
        return "morning"
    if 12 <= hour < 16:
        return "afternoon"
    if 16 <= hour < 20:
        return "evening"
    return "night"


def _clamp01(value: float) -> float:
    return max(0.0, min(1.0, value))


def _score_of(value: dict) -> float | None:
    raw = (value or {}).get("score")
    if raw is None:
        raw = (value or {}).get("level")
    if isinstance(raw, str):
        text = raw.strip().lower().replace(" ", "_")
        if text in _LEVEL_SCORES:
            return _LEVEL_SCORES[text]
        try:
            raw = float(text)
        except ValueError:
            return None
    try:
        score = float(raw)
    except (TypeError, ValueError):
        return None
    if score > 1 and score <= 100:
        score /= 100
    return _clamp01(score)


def _median(values: list[float]) -> float:
    ordered = sorted(values)
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[middle]
    return (ordered[middle - 1] + ordered[middle]) / 2


def _reject_outliers(
    observations: list[dict],
) -> tuple[list[dict], int]:
    """Drop values far outside the bucket median using the MAD rule."""
    scores = [item["score"] for item in observations]
    median = _median(scores)
    deviations = [abs(score - median) for score in scores]
    mad = _median(deviations)
    threshold = max(3 * 1.4826 * mad, 0.35) if mad else 0.35
    kept = [item for item in observations if abs(item["score"] - median) <= threshold]
    return kept, len(observations) - len(kept)


def _level_label(level: float) -> str:
    if level >= 0.8:
        return "very high"
    if level >= 0.65:
        return "high"
    if level >= 0.4:
        return "moderate"
    return "low"


def _confidence_label(confidence: float) -> str:
    if confidence >= 0.7:
        return "high"
    if confidence >= 0.5:
        return "moderate"
    return "low"


def _forecast_entry(
    weekday: int,
    bucket: str,
    observations: list[dict],
    granularity: str,
) -> dict:
    scores = [item["score"] for item in observations]
    count = len(scores)
    mean = sum(scores) / count
    variance = sum((score - mean) ** 2 for score in scores) / count
    spread = variance**0.5
    ages = [item["age_days"] for item in observations]
    mean_age = sum(ages) / count
    freshness = _clamp01(1 - mean_age / CROWD_MAX_AGE_DAYS)
    sample_component = min(1.0, count / 12)
    stability = _clamp01(1 - spread * 4)
    factor = _GRANULARITY_FACTOR.get(granularity, 0.7)
    confidence = min(
        0.9,
        (0.25 + 0.35 * sample_component + 0.2 * stability + 0.1 * freshness) * factor,
    )
    standard_error = max(spread, 0.05) / sqrt(count)
    margin = 1.2816 * standard_error
    return {
        "weekday": weekday,
        "bucket": bucket,
        "expected_level": round(mean, 2),
        "level_label": _level_label(mean),
        "spread": round(spread, 2),
        "interval_80": [
            round(_clamp01(mean - margin), 2),
            round(_clamp01(mean + margin), 2),
        ],
        "reports": count,
        "granularity": granularity,
        "fallback": granularity != "weekday_bucket",
        "stale": mean_age > CROWD_STALE_DAYS,
        "freshness": round(freshness, 2),
        "mean_report_age_days": round(mean_age, 1),
        "confidence": round(confidence, 2),
        "confidence_label": _confidence_label(confidence),
    }


def crowd_forecast(db: Session, activity_id: str) -> dict:
    now = utcnow()
    reports = relevant_reports(db, activity_id, days=CROWD_WINDOW_DAYS)
    crowd = [
        report
        for report in reports
        if report.category == "crowd" and report.source_type in {"community", "official"}
    ]
    observations: list[dict] = []
    stale = 0
    unusable = 0
    for report in crowd:
        score = _score_of(report.value or {})
        if score is None:
            unusable += 1
            continue
        age_days = max(0.0, (now - report.observed_at).total_seconds() / 86400)
        if age_days > CROWD_MAX_AGE_DAYS:
            stale += 1
            continue
        observations.append(
            {
                "weekday": report.observed_at.weekday(),
                "bucket": count_bucket(report.observed_at.hour),
                "score": score,
                "age_days": age_days,
                "observed_at": report.observed_at,
            }
        )

    threshold = {
        "min_reports": CROWD_MIN_REPORTS,
        "min_reports_per_bucket": CROWD_MIN_BUCKET_REPORTS,
        "window_days": CROWD_WINDOW_DAYS,
        "max_age_days": CROWD_MAX_AGE_DAYS,
    }
    observed = {
        "reports_seen": len(crowd),
        "reports_used": len(observations),
        "excluded_stale": stale,
        "excluded_unusable": unusable,
        "latest_observed_at": crowd[0].observed_at if crowd else None,
        "range": (
            {
                "min": round(min(item["score"] for item in observations), 2),
                "max": round(max(item["score"] for item in observations), 2),
            }
            if observations
            else None
        ),
        "note": "Observed values are traveller or official reports, not sensor measurements.",
    }

    if len(observations) < CROWD_MIN_REPORTS:
        latest = crowd[0] if crowd else None
        reason = "not_enough_reports"
        if stale and len(observations) + stale >= CROWD_MIN_REPORTS:
            reason = "reports_are_stale"
        return {
            "activity_id": activity_id,
            "status": "insufficient_data",
            "required_reports": CROWD_MIN_REPORTS,
            "available_reports": len(observations),
            "reason": reason,
            "threshold": threshold,
            "observed": observed,
            "latest_observation": (
                {
                    "observed_at": latest.observed_at,
                    "source_type": latest.source_type,
                    "source_label": SOURCE_LABELS.get(latest.source_type),
                    "value": latest.value,
                }
                if latest
                else None
            ),
            "message": (
                "Not enough recent, reliable observations to forecast crowds. "
                "Showing the latest report instead of inventing a prediction."
                if reason == "not_enough_reports"
                else "Reports exist but are too old to forecast. Fresh observations are needed."
            ),
        }

    grouped: dict[tuple[int, str], list[dict]] = {}
    weekday_groups: dict[int, list[dict]] = {}
    day_type_groups: dict[tuple[str, str], list[dict]] = {}
    for item in observations:
        grouped.setdefault((item["weekday"], item["bucket"]), []).append(item)
        weekday_groups.setdefault(item["weekday"], []).append(item)
        day_type = "weekend" if item["weekday"] >= 5 else "weekday"
        day_type_groups.setdefault((day_type, item["bucket"]), []).append(item)

    direct: dict[tuple[int, str], list[dict]] = {}
    excluded_outliers = 0
    for key, bucket_observations in grouped.items():
        kept, rejected = _reject_outliers(bucket_observations)
        excluded_outliers += rejected
        if len(kept) >= CROWD_MIN_BUCKET_REPORTS:
            direct[key] = kept
    observed["excluded_outliers"] = excluded_outliers
    observed["buckets"] = [
        {
            "weekday": weekday,
            "bucket": bucket,
            "reports": len(items),
            "mean_level": round(sum(item["score"] for item in items) / len(items), 2),
            "latest_observed_at": max(item["observed_at"] for item in items),
        }
        for (weekday, bucket), items in sorted(grouped.items())
    ]

    forecasts: list[dict] = []
    for key in sorted(grouped):
        weekday, bucket = key
        if key in direct:
            forecasts.append(
                _forecast_entry(weekday, bucket, direct[key], "weekday_bucket")
            )
            continue
        weekday_items = weekday_groups.get(weekday, [])
        if len(weekday_items) >= CROWD_MIN_BUCKET_REPORTS:
            forecasts.append(_forecast_entry(weekday, bucket, weekday_items, "weekday"))
            continue
        day_type = "weekend" if weekday >= 5 else "weekday"
        day_type_items = day_type_groups.get((day_type, bucket), [])
        if len(day_type_items) >= CROWD_MIN_BUCKET_REPORTS:
            forecasts.append(
                _forecast_entry(weekday, bucket, day_type_items, "day_type_bucket")
            )

    if not forecasts:
        return {
            "activity_id": activity_id,
            "status": "insufficient_data",
            "required_reports": CROWD_MIN_REPORTS,
            "available_reports": len(observations),
            "reason": "no_reliable_bucket",
            "threshold": threshold,
            "observed": observed,
            "latest_observation": {
                "observed_at": crowd[0].observed_at,
                "source_type": crowd[0].source_type,
                "source_label": SOURCE_LABELS.get(crowd[0].source_type),
                "value": crowd[0].value,
            },
            "message": (
                "Each time bucket needs at least 3 usable, non-stale reports before a "
                "forecast is shown."
            ),
        }

    forecasts.sort(key=lambda item: (-item["confidence"], item["weekday"]))
    return {
        "activity_id": activity_id,
        "status": "predicted",
        "model": CROWD_MODEL,
        "provenance": "ESTIMATED",
        "threshold": threshold,
        "observed": observed,
        "predicted": {
            "method": (
                "median/MAD outlier rejection, freshness-weighted bucket mean with "
                "weekday/day-type fallback; 80% interval from sample dispersion"
            ),
            "model": CROWD_MODEL,
            "provenance": "ESTIMATED",
            "forecasts": forecasts,
            "note": (
                "Predictions are derived from observed reports. They are not "
                "measurements and do not guarantee what you will find."
            ),
        },
        "disclosure": (
            "PREDICTED from historical community/official observations. This is an estimate, "
            "not a verified measurement. Confidence reflects sample size, agreement between "
            "reports, recency and whether the estimate had to fall back to a broader time group."
        ),
    }


def evidence_passport(
    db: Session,
    activity: Activity,
    group_suitability: dict | None = None,
) -> dict:
    place = db.get(Place, activity.place_id) if activity.place_id else None
    reports = aggregate_reports(db, activity.id)
    sources = [
        {
            "entity": "activity_catalog",
            "name": activity.source_type,
            "last_verified_at": activity.last_verified_at,
            "is_live": False,
        }
    ]
    if place:
        sources.append(
            {
                "entity": "place_catalog",
                "name": place.source_name or place.source_type,
                "last_verified_at": place.last_verified_at,
                "is_live": False,
            }
        )
    unknowns = []
    if activity.wheelchair_accessible is None:
        unknowns.append("Wheelchair accessibility is unverified.")
    if not activity.opening_hours:
        unknowns.append("Opening hours are not recorded.")
    if not activity.last_verified_at:
        unknowns.append("No recent verification timestamp for price or hours.")
    if not reports["has_data"]:
        unknowns.append("No recent traveller reports for this activity.")
    return {
        "activity_id": activity.id,
        "name": activity.name,
        "sources": sources,
        "cost_assumption": {
            "value": activity.price_estimate,
            "currency": activity.currency,
            "basis": "catalog estimate per person",
        },
        "travel_assumption": "Estimated door-to-door time from the trip base; not a live routed ETA.",
        "recent_reports": reports,
        "group_suitability": group_suitability,
        "unknowns": unknowns,
        "provenance": "REPORTED" if reports["has_data"] else "ESTIMATED",
        "disclosure": "Evidence is shown as recorded. Missing data stays unknown.",
    }


def expectation_check(db: Session, activity: Activity, claim: str) -> dict:
    reports = aggregate_reports(db, activity.id)
    claim_lower = claim.lower()
    supported = []
    limitations = []

    if any(word in claim_lower for word in ["crowd", "busy", "quiet"]) and reports["has_data"]:
        crowd = next((c for c in reports["categories"] if c["category"] == "crowd"), None)
        supported.append(
            {
                "item": "Crowds",
                "status": crowd["status"] if crowd else "UNKNOWN",
                "detail": (
                    f"Latest crowd observation: {crowd['latest_observed_at']}."
                    if crowd
                    else "No crowd report on record."
                ),
            }
        )
    if any(word in claim_lower for word in ["free", "price", "cheap", "ticket", "cost"]):
        supported.append(
            {
                "item": "Cost",
                "status": "ESTIMATED",
                "detail": f"Catalog estimate is {activity.currency} {activity.price_estimate:.0f}; not a live ticket price.",
            }
        )
    if any(word in claim_lower for word in ["open", "hours", "closed"]):
        supported.append(
            {
                "item": "Opening hours",
                "status": "REPORTED" if activity.opening_hours else "UNKNOWN",
                "detail": (
                    "Hours are from the catalog, not a live provider."
                    if activity.opening_hours
                    else "Opening hours are not recorded."
                ),
            }
        )
    if any(word in claim_lower for word in ["accessible", "wheelchair", "step-free"]):
        status = (
            "VERIFIED"
            if activity.wheelchair_accessible is True
            else "UNKNOWN"
            if activity.wheelchair_accessible is None
            else "REPORTED"
        )
        supported.append(
            {
                "item": "Accessibility",
                "status": status,
                "detail": (
                    "Catalog reports step-free access."
                    if activity.wheelchair_accessible is True
                    else "Accessibility is unknown." if activity.wheelchair_accessible is None else "Catalog reports barriers."
                ),
            }
        )

    limitations.append("Social media inspiration is not evidence.")
    if activity.source_type.startswith("seed"):
        limitations.append("This catalog entry is curated seed data, not a live provider feed.")
    return {
        "activity_id": activity.id,
        "claim": claim,
        "evidence": supported,
        "recent_reports": reports["categories"],
        "limitations": limitations,
        "unknowns": [u for u in [
            "Live availability is unknown." if True else "",
            "Current queues are unknown unless recently reported." if not reports["has_data"] else "",
        ] if u],
        "verdict": (
            "insufficient_evidence"
            if not supported
            else "partially_supported" if any(item["status"] in {"UNKNOWN", "ESTIMATED"} for item in supported)
            else "supported_by_recorded_sources"
        ),
    }


def access_chain(activity: Activity) -> dict:
    chain = activity.access_chain or {}
    stages = ["transport_stop", "path", "entrance", "experience_area", "facilities", "return"]
    labels = {
        "transport_stop": "Transport stop",
        "path": "Path to entrance",
        "entrance": "Entrance",
        "experience_area": "Experience area",
        "facilities": "Facilities",
        "return": "Return journey",
    }
    entries = []
    for stage in stages:
        raw = chain.get(stage)
        if isinstance(raw, dict):
            status = raw.get("status", "reported")
            detail = raw.get("detail")
        elif isinstance(raw, str):
            status, detail = "reported", raw
        else:
            status, detail = "unknown", "No information recorded."
        entries.append(
            {
                "stage": stage,
                "label": labels[stage],
                "status": status,
                "detail": detail,
                "source": "catalog" if raw else None,
            }
        )
    verified = [entry for entry in entries if entry["status"] == "verified"]
    barriers = [entry for entry in entries if entry["status"] in {"barrier", "limited"}]
    return {
        "activity_id": activity.id,
        "stages": entries,
        "summary": {
            "verified_stages": len(verified),
            "reported_barriers": len(barriers),
            "unknown_stages": len([entry for entry in entries if entry["status"] == "unknown"]),
        },
        "disclosure": "Unknown stages stay unknown. Do not assume step-free access without evidence.",
    }
