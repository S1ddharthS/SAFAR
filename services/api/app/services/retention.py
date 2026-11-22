"""Data-retention cleanup.

Run after the app has been deployed long enough to accumulate expired rows:

    python scripts/retention.py

Schedule it daily (cron, systemd timer or a container job). Counts are
returned so the job can be logged and monitored. Nothing here deletes live
content: only sessions past expiry, expired invitations and one-use links,
old notifications, applied offline queue rows and aged audit records.
"""

from datetime import datetime, timedelta

from sqlalchemy.orm import Session

from app.core.config import settings
from app.models import (
    AuditLog,
    AuthSession,
    CompanionLink,
    Notification,
    OfflineSyncQueue,
    TripInvitation,
)
from app.models.models import utcnow


def run_retention(db: Session, now: datetime | None = None) -> dict[str, int]:
    now = now or utcnow()

    def cutoff(days: int) -> datetime:
        return now - timedelta(days=days)

    removed: dict[str, int] = {}
    removed["auth_sessions"] = (
        db.query(AuthSession)
        .filter(
            (AuthSession.expires_at < cutoff(settings.retention_session_days))
            | (
                AuthSession.revoked_at.is_not(None)
                & (AuthSession.revoked_at < cutoff(settings.retention_session_days))
            )
        )
        .delete(synchronize_session=False)
    )
    removed["trip_invitations"] = (
        db.query(TripInvitation)
        .filter(
            TripInvitation.accepted_at.is_(None),
            TripInvitation.expires_at.is_not(None),
            TripInvitation.expires_at < cutoff(settings.retention_invitation_days),
        )
        .delete(synchronize_session=False)
    )
    removed["companion_links"] = (
        db.query(CompanionLink)
        .filter(
            (CompanionLink.expires_at < cutoff(settings.retention_companion_days))
            | (
                CompanionLink.revoked_at.is_not(None)
                & (CompanionLink.revoked_at < cutoff(settings.retention_companion_days))
            )
        )
        .delete(synchronize_session=False)
    )
    removed["notifications"] = (
        db.query(Notification)
        .filter(Notification.created_at < cutoff(settings.retention_notification_days))
        .delete(synchronize_session=False)
    )
    removed["offline_sync_queue"] = (
        db.query(OfflineSyncQueue)
        .filter(
            OfflineSyncQueue.applied_at.is_not(None),
            OfflineSyncQueue.created_at < cutoff(settings.retention_offline_days),
        )
        .delete(synchronize_session=False)
    )
    removed["audit_logs"] = (
        db.query(AuditLog)
        .filter(AuditLog.created_at < cutoff(settings.retention_audit_days))
        .delete(synchronize_session=False)
    )
    return removed
