"""Phase 7 F21 evaluation: crowd forecasting honesty and calibration.

Controlled PlaceReport rows are inserted directly and removed again. The tests
assert that observations and predictions are reported separately, stale and
anomalous reports are excluded rather than averaged in, and insufficient data
never produces an invented forecast.
"""

import uuid
from datetime import date, datetime, time, timedelta

from app.db.context import system_context
from app.db.session import SessionLocal
from app.models import Activity, PlaceReport

_ACTIVITY = "Indigo Dyeing Workshop"


def _activity_id() -> str:
    db = SessionLocal()
    try:
        with system_context(db):
            activity = db.query(Activity).filter(Activity.name == _ACTIVITY).one()
            return activity.id
    finally:
        db.close()


def _insert(activity_id, days_ago, hour, scores):
    db = SessionLocal()
    inserted = []
    try:
        with system_context(db):
            base = datetime.combine(date.today() - timedelta(days=days_ago), time(hour=hour))
            for score in scores:
                report = PlaceReport(
                    id=uuid.uuid4().hex,
                    activity_id=activity_id,
                    category="crowd",
                    value={"score": score},
                    note="Controlled forecast probe.",
                    observed_at=base,
                    source_type="community",
                    confidence=0.7,
                )
                db.add(report)
                db.flush()
                inserted.append(report.id)
            db.commit()
            return inserted
    finally:
        db.close()


def _delete(report_ids):
    db = SessionLocal()
    try:
        with system_context(db):
            for report_id in report_ids:
                report = db.get(PlaceReport, report_id)
                if report:
                    db.delete(report)
            db.commit()
    finally:
        db.close()


def _forecast(client, headers, trip_id, activity_id):
    response = client.get(f"/api/trips/{trip_id}/places/{activity_id}", headers=headers)
    assert response.status_code == 200, response.text
    return response.json()["crowd_forecast"]


def test_insufficient_data_never_invents_a_forecast(client, mira, kyoto):
    forecast = _forecast(client, mira, kyoto["id"], _activity_id())
    assert forecast["status"] == "insufficient_data"
    assert forecast["reason"] == "not_enough_reports"
    assert forecast["required_reports"] == 8
    assert forecast["available_reports"] == 0
    assert "predicted" not in forecast
    assert "forecasts" not in forecast
    assert forecast["observed"]["reports_used"] == 0
    assert "instead of inventing" in forecast["message"]
    assert forecast["threshold"]["min_reports_per_bucket"] == 3


def test_observed_and_predicted_are_separate_and_outliers_ignored(client, mira, kyoto):
    activity_id = _activity_id()
    inserted = []
    try:
        inserted += _insert(activity_id, 5, 15, [0.6] * 8)
        inserted += _insert(activity_id, 5, 15, [0.05])
        forecast = _forecast(client, mira, kyoto["id"], activity_id)

        assert forecast["status"] == "predicted"
        assert forecast["model"] == "bucket-forecast-v2"
        assert forecast["provenance"] == "ESTIMATED"
        assert "forecasts" not in forecast

        observed = forecast["observed"]
        assert observed["reports_used"] == 9
        assert observed["excluded_outliers"] == 1
        assert observed["range"]["max"] == 0.6
        assert observed["buckets"]

        predicted = forecast["predicted"]
        assert predicted["provenance"] == "ESTIMATED"
        entry = predicted["forecasts"][0]
        assert entry["reports"] == 8
        assert entry["granularity"] == "weekday_bucket"
        assert entry["fallback"] is False
        assert entry["expected_level"] == 0.6
        assert entry["level_label"] == "moderate"
        low, high = entry["interval_80"]
        assert 0 <= low <= entry["expected_level"] <= high <= 1
        assert entry["confidence_label"] in {"low", "moderate", "high"}
        assert entry["stale"] is False
    finally:
        _delete(inserted)


def test_stale_reports_are_excluded_not_averaged(client, mira, kyoto):
    activity_id = _activity_id()
    inserted = []
    try:
        inserted += _insert(activity_id, 150, 11, [0.6] * 8)
        forecast = _forecast(client, mira, kyoto["id"], activity_id)
        assert forecast["status"] == "insufficient_data"
        assert forecast["reason"] == "reports_are_stale"
        assert forecast["available_reports"] == 0
        assert forecast["observed"]["excluded_stale"] == 8
        assert forecast["observed"]["reports_seen"] == 8
        assert "too old" in forecast["message"]
        assert "predicted" not in forecast
    finally:
        _delete(inserted)


def test_hierarchical_fallback_is_labelled(client, mira, kyoto):
    activity_id = _activity_id()
    inserted = []
    try:
        # Same weekday: 2 morning reports and 3 afternoon reports.
        inserted += _insert(activity_id, 3, 10, [0.5, 0.6])
        inserted += _insert(activity_id, 3, 15, [0.6] * 3)
        # A different weekday with its own full bucket.
        inserted += _insert(activity_id, 4, 20, [0.3] * 3)

        forecast = _forecast(client, mira, kyoto["id"], activity_id)
        assert forecast["status"] == "predicted"
        assert forecast["observed"]["reports_used"] == 8

        weekday = (date.today() - timedelta(days=3)).weekday()
        forecasts = forecast["predicted"]["forecasts"]
        fallback = next(
            item
            for item in forecasts
            if item["weekday"] == weekday and item["bucket"] == "morning"
        )
        assert fallback["granularity"] == "weekday"
        assert fallback["fallback"] is True
        assert fallback["reports"] == 5

        direct = next(
            item
            for item in forecasts
            if item["weekday"] == weekday and item["bucket"] == "afternoon"
        )
        assert direct["granularity"] == "weekday_bucket"
        assert direct["reports"] == 3
    finally:
        _delete(inserted)


def test_forecasts_stay_labelled_as_predictions(client, mira, kyoto):
    activity_id = _activity_id()
    inserted = []
    try:
        inserted += _insert(activity_id, 2, 9, [0.4, 0.5, 0.6, 0.5])
        inserted += _insert(activity_id, 2, 18, [0.7, 0.8, 0.7, 0.75])
        forecast = _forecast(client, mira, kyoto["id"], activity_id)

        assert forecast["status"] == "predicted"
        assert "PREDICTED" in forecast["disclosure"]
        assert "not a verified measurement" in forecast["disclosure"]
        assert forecast["predicted"]["note"].startswith("Predictions are derived")
        for entry in forecast["predicted"]["forecasts"]:
            assert entry["confidence"] <= 0.9
            assert 0 <= entry["freshness"] <= 1
            assert entry["mean_report_age_days"] >= 0
    finally:
        _delete(inserted)
