"""Moderation, report verification and Material Change Watch (F14, F44).

Moderation decisions are attributed, audited and communicated to the reporter.
Material watches alert only when a tracked value actually changes.
"""

import json
from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.alerting import alert_manager
from app.core.config import settings
from app.core.deps import get_current_user, get_db, get_trip_and_member, require_admin
from app.core.metrics import metrics
from app.db.session import check_db_readiness
from app.models import (
    AbuseReport,
    Activity,
    AuditLog,
    CirclePost,
    Expense,
    ItineraryProposal,
    MaterialWatch,
    Notification,
    PlaceReport,
    RecommendationBatch,
    Trip,
    TripMember,
    TripMemory,
    User,
)
from app.models.models import utcnow
from app.schemas.schemas import AbuseDecisionIn, MaterialWatchIn
from app.services.common import audit, notify_trip_members

router = APIRouter(prefix="/api", tags=["admin"])
ADMIN_ROLES = {"owner", "admin"}


def _watch_value(activity: Activity, field: str):
    value = getattr(activity, field, None)
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return value


@router.get("/trips/{trip_id}/material-watch")
def list_watches(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = get_trip_and_member(trip_id, db, user)
    rows = (
        db.query(MaterialWatch)
        .filter(MaterialWatch.trip_id == trip.id)
        .order_by(MaterialWatch.created_at.desc())
        .all()
    )
    activities = {
        activity.id: activity
        for activity in db.query(Activity)
        .filter(Activity.id.in_({row.activity_id for row in rows if row.activity_id}))
        .all()
    } if rows else {}
    return {
        "items": [
            {
                "id": row.id,
                "activity_id": row.activity_id,
                "activity_name": (
                    activities[row.activity_id].name
                    if row.activity_id in activities
                    else None
                ),
                "field": row.field,
                "last_value": row.last_value,
                "status": row.status,
                "last_checked_at": row.last_checked_at,
            }
            for row in rows
        ],
        "note": "Material watches only alert when the tracked field actually changes.",
    }


@router.post("/trips/{trip_id}/material-watch", status_code=201)
def create_watch(
    trip_id: str,
    payload: MaterialWatchIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = get_trip_and_member(trip_id, db, user)
    activity = db.get(Activity, payload.activity_id)
    if not activity or activity.destination_id != trip.destination_id:
        raise HTTPException(status_code=404, detail="Activity not found for this trip")
    existing = (
        db.query(MaterialWatch)
        .filter(
            MaterialWatch.trip_id == trip.id,
            MaterialWatch.activity_id == activity.id,
            MaterialWatch.field == payload.field,
        )
        .first()
    )
    if existing:
        raise HTTPException(status_code=409, detail="This field is already being watched")
    watch = MaterialWatch(
        trip_id=trip.id,
        activity_id=activity.id,
        field=payload.field,
        last_value={"value": _watch_value(activity, payload.field)},
        status="watching",
    )
    db.add(watch)
    audit(
        db,
        action="material_watch.create",
        entity_type="material_watch",
        entity_id=watch.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"field": payload.field},
    )
    db.commit()
    return {
        "id": watch.id,
        "field": watch.field,
        "last_value": watch.last_value,
        "status": watch.status,
    }


@router.delete("/trips/{trip_id}/material-watch/{watch_id}")
def delete_watch(
    trip_id: str,
    watch_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, member = get_trip_and_member(trip_id, db, user)
    watch = db.get(MaterialWatch, watch_id)
    if not watch or watch.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Watch not found")
    db.delete(watch)
    audit(
        db,
        action="material_watch.delete",
        entity_type="material_watch",
        entity_id=watch_id,
        user_id=user.id,
        trip_id=trip.id,
    )
    db.commit()
    return {"ok": True}


@router.post("/trips/{trip_id}/material-watch/check")
def check_watches(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = get_trip_and_member(trip_id, db, user)
    rows = db.query(MaterialWatch).filter(MaterialWatch.trip_id == trip.id).all()
    changed = []
    unchanged = 0
    for watch in rows:
        activity = db.get(Activity, watch.activity_id) if watch.activity_id else None
        if not activity:
            watch.status = "target_missing"
            watch.last_checked_at = utcnow()
            continue
        current = _watch_value(activity, watch.field)
        previous = (watch.last_value or {}).get("value")
        watch.last_checked_at = utcnow()
        if current != previous:
            watch.status = "changed"
            watch.last_value = {"value": current, "previous": previous}
            changed.append(
                {
                    "watch_id": watch.id,
                    "activity_id": activity.id,
                    "activity_name": activity.name,
                    "field": watch.field,
                    "previous": previous,
                    "current": current,
                }
            )
        else:
            watch.status = "watching"
            unchanged += 1
    if changed:
        notify_trip_members(
            db,
            trip,
            kind="material_change",
            title=f"{len(changed)} tracked fact(s) changed",
            body="Open Material Change Watch to review the differences. Nothing was changed in your plan.",
            link=f"/trips/{trip.id}/watch",
            exclude_user_id=None,
        )
    audit(
        db,
        action="material_watch.check",
        entity_type="trip",
        entity_id=trip.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"changed": len(changed), "unchanged": unchanged},
    )
    db.commit()
    return {
        "checked": len(rows),
        "changed": changed,
        "unchanged": unchanged,
        "note": "Alerts are only sent when a value changes. Your confirmed plan is untouched.",
    }


@router.get("/admin/stats")
def admin_stats(
    user: User = Depends(require_admin), db: Session = Depends(get_db)
):
    return {
        "users": db.query(func.count(User.id)).scalar(),
        "trips": db.query(func.count(Trip.id)).filter(Trip.deleted_at.is_(None)).scalar(),
        "memberships": db.query(func.count(TripMember.id)).scalar(),
        "proposals_open": db.query(func.count(ItineraryProposal.id))
        .filter(ItineraryProposal.status == "open")
        .scalar(),
        "recommendation_batches": db.query(func.count(RecommendationBatch.id)).scalar(),
        "expenses": db.query(func.count(Expense.id))
        .filter(Expense.deleted_at.is_(None))
        .scalar(),
        "memories": db.query(func.count(TripMemory.id))
        .filter(TripMemory.deleted_at.is_(None))
        .scalar(),
        "place_reports": db.query(func.count(PlaceReport.id)).scalar(),
        "open_abuse_reports": db.query(func.count(AbuseReport.id))
        .filter(AbuseReport.status == "open")
        .scalar(),
        "audit_events": db.query(func.count(AuditLog.id)).scalar(),
    }


@router.get("/admin/abuse-reports")
def list_abuse_reports(
    status: str = Query(default="open", pattern=r"^(open|resolved|dismissed|all)$"),
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    query = db.query(AbuseReport)
    if status != "all":
        query = query.filter(AbuseReport.status == status)
    rows = query.order_by(AbuseReport.created_at.desc()).limit(200).all()
    users = {
        person.id: person
        for person in db.query(User)
        .filter(User.id.in_({row.reporter_id for row in rows} | {row.target_user_id for row in rows if row.target_user_id}))
        .all()
    } if rows else {}
    return {
        "items": [
            {
                "id": row.id,
                "reporter": (
                    {
                        "id": users[row.reporter_id].id,
                        "display_name": users[row.reporter_id].display_name,
                    }
                    if row.reporter_id in users
                    else None
                ),
                "target_type": row.target_type,
                "target_id": row.target_id,
                "target_user_id": row.target_user_id,
                "reason": row.reason,
                "status": row.status,
                "reviewed_by": row.reviewed_by,
                "reviewed_at": row.reviewed_at,
                "created_at": row.created_at,
            }
            for row in rows
        ]
    }


@router.post("/admin/abuse-reports/{report_id}/decide")
def decide_abuse_report(
    report_id: str,
    payload: AbuseDecisionIn,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    report = db.get(AbuseReport, report_id)
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")
    if report.status != "open":
        raise HTTPException(status_code=409, detail="This report was already reviewed")
    hidden = False
    if payload.decision == "hide_content":
        if report.target_type == "post" and report.target_id:
            post = db.get(CirclePost, report.target_id)
            if post:
                post.status = "removed"
                hidden = True
        elif report.target_type == "memory" and report.target_id:
            memory = db.get(TripMemory, report.target_id)
            if memory and memory.deleted_at is None:
                memory.visibility = "private"
                memory.approved = False
                hidden = True
        else:
            raise HTTPException(
                status_code=422,
                detail="Content can only be hidden for posts and memories; use warn otherwise",
            )
    report.status = "resolved" if payload.decision in {"hide_content", "warn"} else "dismissed"
    report.reviewed_by = user.id
    report.reviewed_at = utcnow()
    db.add(
        Notification(
            user_id=report.reporter_id,
            kind="moderation_update",
            title="Your report was reviewed",
            body="Moderators reviewed your report and recorded an outcome.",
            link="/settings",
        )
    )
    if payload.decision == "warn" and report.target_user_id:
        db.add(
            Notification(
                user_id=report.target_user_id,
                kind="moderation_warning",
                title="Community guidelines reminder",
                body=payload.note or "A moderator reviewed content connected to your account.",
                link="/settings",
            )
        )
    audit(
        db,
        action="abuse.decide",
        entity_type="abuse_report",
        entity_id=report.id,
        user_id=user.id,
        detail={"decision": payload.decision, "hidden": hidden},
    )
    db.commit()
    return {
        "ok": True,
        "status": report.status,
        "content_hidden": hidden,
        "note": "Reporter is notified without exposing reviewer identity.",
    }


@router.post("/admin/place-reports/{report_id}/verify")
def verify_place_report(
    report_id: str,
    verify: bool = Query(default=True),
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    report = db.get(PlaceReport, report_id)
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")
    report.verified = verify
    if verify:
        report.confidence = max(report.confidence, 0.85)
    audit(
        db,
        action="place_report.verify",
        entity_type="place_report",
        entity_id=report.id,
        user_id=user.id,
        detail={"verified": verify},
    )
    if report.reporter_id:
        db.add(
            Notification(
                user_id=report.reporter_id,
                kind="report_verified",
                title="Your observation was verified" if verify else "Verification withdrawn",
                body=(
                    "A moderator checked this community report. It still carries the REPORTED "
                    "label because only official sources become VERIFIED."
                    if verify and report.source_type != "official"
                    else "Moderators changed the verification status of your report."
                ),
                link="/settings",
            )
        )
    db.commit()
    provenance = "VERIFIED" if verify and report.source_type == "official" else "REPORTED"
    return {
        "ok": True,
        "verified": report.verified,
        "confidence": report.confidence,
        "source_type": report.source_type,
        "provenance": provenance,
        "provenance_note": (
            "Official source: shown as VERIFIED."
            if provenance == "VERIFIED"
            else "Moderator-checked community report: still shown as REPORTED, never as an official fact."
            if verify
            else "Verification withdrawn: this is an unverified community report."
        ),
    }


@router.get("/admin/metrics")
def get_operational_metrics(user: User = Depends(require_admin)):
    """Administrative operational observability endpoint.

    Exposes real operational metrics: server uptime, HTTP counters, database readiness,
    security events, WebSocket counts, media storage status, and recent alerts.
    Accessible only to authenticated platform administrators.
    """
    db_check = check_db_readiness()
    snapshot = metrics.snapshot()

    # Safe inspection of storage directory
    media_dir = settings.storage_dir
    total_media_files = 0
    total_media_bytes = 0
    if media_dir.exists():
        try:
            for item in media_dir.rglob("*"):
                if item.is_file():
                    total_media_files += 1
                    total_media_bytes += item.stat().st_size
        except Exception:
            pass

    # Read latest backup record if manifest exists
    backup_info = None
    backup_manifest_candidates = [
        media_dir / "backups" / "backup_manifest.json",
        Path("storage_staging/backups/backup_manifest.json"),
    ]
    for candidate in backup_manifest_candidates:
        if candidate.exists():
            try:
                manifest_data = json.loads(candidate.read_text(encoding="utf-8"))
                backups_list = manifest_data.get("backups", [])
                if backups_list:
                    backup_info = backups_list[-1]
                    break
            except Exception:
                pass

    overall_status = "ok" if db_check["status"] == "ok" else "degraded"

    return {
        "status": overall_status,
        "environment": settings.environment,
        "release": settings.release,
        "database": db_check,
        "metrics": snapshot,
        "alerts": {
            "recent": alert_manager.get_recent_alerts(),
            "total_recent": len(alert_manager.get_recent_alerts()),
        },
        "media_storage": {
            "storage_dir": media_dir.name,
            "total_files": total_media_files,
            "total_bytes": total_media_bytes,
        },
        "backup": backup_info or {"status": "none_recorded"},
    }
