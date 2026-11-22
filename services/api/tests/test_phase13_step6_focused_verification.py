"""Focused Verification Suite for Phase 13 Step 6 Acceptance.

Covers:
1. Metrics persistence & API restart behavior.
2. Alert delivery mechanics & cooldown rate-limiting.
3. Backup retention, failed-backup isolation, and manifest integrity hashes.
4. Server isolation: port inspection and distinction between dev and staging processes.
"""

from datetime import datetime, timezone
import hashlib
import json
import logging
import os
from pathlib import Path
import socket
import tempfile
import time
from typing import Any
import pytest

from app.core.metrics import MetricsCollector
from app.core.alerting import AlertManager, AlertCategory, AlertSeverity
from scripts.backup_staging import MANIFEST_FILE, verify_manifest_integrity


class TestMetricsPersistence:
    """Verifies in-memory metrics behavior, reset on restart, and disk-backed persistence."""

    def test_in_memory_metrics_reset_on_restart(self):
        """Proves that operational counters live purely in process memory and reset to 0 on restart."""
        # 1. Simulate active API instance accumulating operational metrics
        active_collector = MetricsCollector()
        active_collector.record_http_request("GET", "/api/trips", 200, 45.2)
        active_collector.record_http_request("POST", "/api/trips", 201, 120.5)
        active_collector.record_http_request("GET", "/api/nonexistent", 404, 12.0)
        active_collector.record_http_request("POST", "/api/error", 500, 50.0)

        active_collector.record_auth_event("login_success")
        active_collector.record_auth_event("refresh_reuse")
        active_collector.record_auth_event("csrf_failure")
        active_collector.record_auth_event("rate_limit_exceeded")

        active_collector.record_db_query(35.0, is_slow=False)
        active_collector.record_db_query(650.0, is_slow=True)
        active_collector.record_db_error()

        active_collector.record_ws_connect()
        active_collector.record_ws_broadcast()
        active_collector.record_sync_batch(applied=3, rejected=1, skipped=2)
        active_collector.record_media_upload("success")
        active_collector.record_media_upload("rejected_mime")

        snap = active_collector.snapshot()
        assert snap["http"]["requests_total"] == 4
        assert snap["http"]["status_2xx"] == 2
        assert snap["http"]["status_4xx"] == 1
        assert snap["http"]["status_5xx"] == 1
        assert snap["security"]["auth_login_success"] == 1
        assert snap["security"]["auth_refresh_reuse"] == 1
        assert snap["security"]["csrf_failures"] == 1
        assert snap["security"]["rate_limit_exceeded"] == 1
        assert snap["database"]["queries_total"] == 2
        assert snap["database"]["slow_queries_total"] == 1
        assert snap["database"]["errors_total"] == 1
        assert snap["realtime"]["active_connections"] == 1
        assert snap["sync"]["items_applied"] == 3
        assert snap["media"]["uploads_success"] == 1
        assert snap["media"]["uploads_rejected_mime"] == 1

        # 2. Simulate API process restart (new process memory space)
        restarted_collector = MetricsCollector()
        new_snap = restarted_collector.snapshot()

        # All in-memory counters reset to zero
        assert new_snap["http"]["requests_total"] == 0
        assert new_snap["http"]["status_2xx"] == 0
        assert new_snap["http"]["status_4xx"] == 0
        assert new_snap["http"]["status_5xx"] == 0
        assert new_snap["http"]["avg_latency_ms"] == 0.0
        assert new_snap["security"]["auth_login_success"] == 0
        assert new_snap["security"]["auth_refresh_reuse"] == 0
        assert new_snap["security"]["csrf_failures"] == 0
        assert new_snap["security"]["rate_limit_exceeded"] == 0
        assert new_snap["database"]["queries_total"] == 0
        assert new_snap["database"]["slow_queries_total"] == 0
        assert new_snap["database"]["errors_total"] == 0
        assert new_snap["realtime"]["active_connections"] == 0
        assert new_snap["realtime"]["total_connected"] == 0
        assert new_snap["sync"]["batches_total"] == 0
        assert new_snap["sync"]["items_applied"] == 0
        assert new_snap["media"]["uploads_success"] == 0
        assert new_snap["media"]["uploads_rejected_mime"] == 0
        assert new_snap["uptime_seconds"] < 1.0

    def test_file_backed_data_survives_process_restart(self):
        """Verifies that a configured staging backup manifest survives restarts.

        Environment-dependent check: it runs only where a staging backup has
        actually been created (``SAFAR_BACKUP_DIR``). Portable test runs skip
        with an explicit reason instead of failing on a developer machine.
        """
        manifest_file = MANIFEST_FILE
        if not manifest_file.exists():
            pytest.skip(
                f"No staging backup manifest at {manifest_file}; "
                "set SAFAR_BACKUP_DIR and run scripts/backup_staging.py to enable this check"
            )

        manifest_data = json.loads(manifest_file.read_text(encoding="utf-8"))
        assert "backups" in manifest_data
        assert len(manifest_data["backups"]) >= 1

        # Most recent backup record is intact
        latest = manifest_data["backups"][-1]
        assert latest["status"] == "success"
        assert Path(latest["path"]).exists()


class TestAlertDelivery:
    """Verifies that safar.alert operates as a structured logging channel with cooldown and optional webhook."""

    def test_alert_emits_structured_log(self, caplog):
        """Verifies structured logging to safar.alert without external dependencies."""
        mgr = AlertManager(cooldown_seconds=300.0, max_history=10)
        mgr.reset_for_tests()

        with caplog.at_level(logging.WARNING, logger="safar.alert"):
            emitted = mgr.trigger(
                category=AlertCategory.SLOW_QUERY,
                severity=AlertSeverity.WARNING,
                title="Slow Database Query",
                message="Query on table 'trips' took 620ms",
                details={"table": "trips", "duration_ms": 620},
            )

        assert emitted is True
        recent = mgr.get_recent_alerts()
        assert len(recent) == 1
        assert recent[0]["category"] == "slow_query"
        assert recent[0]["severity"] == "warning"
        assert recent[0]["details"]["duration_ms"] == 620

        # Structured log record captured
        alert_records = [r for r in caplog.records if r.name == "safar.alert"]
        assert len(alert_records) >= 1
        record = alert_records[-1]
        assert record.levelno == logging.WARNING
        assert hasattr(record, "alert")
        assert record.alert["category"] == "slow_query"

    def test_alert_cooldown_prevents_flooding(self):
        """Verifies 5-minute cooldown per category."""
        mgr = AlertManager(cooldown_seconds=300.0)
        mgr.reset_for_tests()

        # First trigger succeeds
        assert mgr.trigger(
            category=AlertCategory.DATABASE_DOWN,
            severity=AlertSeverity.CRITICAL,
            title="Database Unreachable",
            message="Connection failed",
        ) is True

        # Immediate second trigger of same category is throttled
        assert mgr.trigger(
            category=AlertCategory.DATABASE_DOWN,
            severity=AlertSeverity.CRITICAL,
            title="Database Unreachable",
            message="Connection failed again",
        ) is False

        # Different category is NOT throttled
        assert mgr.trigger(
            category=AlertCategory.HIGH_AUTH_FAILURES,
            severity=AlertSeverity.WARNING,
            title="Auth Failures",
            message="Multiple bad logins",
        ) is True

        # Forced trigger bypasses cooldown
        assert mgr.trigger(
            category=AlertCategory.DATABASE_DOWN,
            severity=AlertSeverity.CRITICAL,
            title="Database Unreachable",
            message="Emergency forced alert",
            force=True,
        ) is True


class TestBackupRetentionAndIntegrity:
    """Verifies 7-backup retention, preserving valid backups, failure handling, and SHA256 integrity."""

    def test_live_staging_manifest_integrity_preserved(self):
        """Verifies the live staging backup without modifying or deleting any file."""
        if not MANIFEST_FILE.exists():
            pytest.skip(
                f"No staging backup manifest at {MANIFEST_FILE}; "
                "set SAFAR_BACKUP_DIR and run scripts/backup_staging.py to enable this check"
            )
        report = verify_manifest_integrity()
        assert report["valid"] is True, f"Manifest integrity failed: {report.get('errors')}"
        assert report["successful_verified"] >= 1
        assert len(report["errors"]) == 0

    def test_seven_backup_retention_and_failure_isolation_sandbox(self):
        """Tests retention in a temporary sandbox directory without touching staging data."""
        with tempfile.TemporaryDirectory() as tmpdir:
            sandbox = Path(tmpdir)
            manifest_file = sandbox / "backup_manifest.json"

            # 1. Create 10 mock successful backups
            backups = []
            for i in range(1, 11):
                filename = f"safar_staging_backup_20261121_{i:02d}0000.dump"
                fpath = sandbox / filename
                content = f"DUMP_CONTENT_VERSION_{i}".encode("utf-8")
                fpath.write_bytes(content)
                sha = hashlib.sha256(content).hexdigest()
                backups.append({
                    "timestamp": f"2026-11-21T{i:02d}:00:00+00:00",
                    "filename": filename,
                    "path": str(fpath),
                    "status": "success",
                    "size_bytes": len(content),
                    "sha256": sha,
                    "duration_seconds": 10.0,
                    "verified": True,
                })

            manifest_file.write_text(json.dumps({"version": "1.0", "backups": backups}, indent=2), encoding="utf-8")

            # 2. Simulate enforce_retention(max_backups=7)
            from scripts.backup_staging import enforce_retention
            # Monkey-patch MANIFEST_FILE for sandbox test
            import scripts.backup_staging as bs
            original_manifest_file = bs.MANIFEST_FILE
            try:
                bs.MANIFEST_FILE = manifest_file
                bs.enforce_retention(max_backups=7)

                # Check manifest
                data = json.loads(manifest_file.read_text(encoding="utf-8"))
                retained = data["backups"]
                assert len(retained) == 7

                # The 3 oldest (1, 2, 3) must be deleted from disk
                for i in range(1, 4):
                    assert not (sandbox / f"safar_staging_backup_20261121_{i:02d}0000.dump").exists()

                # The 7 newest (4 through 10) must exist on disk
                for i in range(4, 11):
                    assert (sandbox / f"safar_staging_backup_20261121_{i:02d}0000.dump").exists()

                # The newest backup (10) is strictly preserved
                assert retained[-1]["filename"] == "safar_staging_backup_20261121_100000.dump"

                # 3. Simulate 5 failed backup attempts
                for j in range(1, 6):
                    failed_filename = f"safar_staging_backup_failed_{j:02d}.dump"
                    failed_record = {
                        "timestamp": f"2026-11-22T{j:02d}:00:00+00:00",
                        "filename": failed_filename,
                        "path": str(sandbox / failed_filename),
                        "status": "failed",
                        "duration_seconds": 1.5,
                        "error": "Simulated pg_dump failure",
                    }
                    data["backups"].append(failed_record)

                manifest_file.write_text(json.dumps(data, indent=2), encoding="utf-8")

                # Run retention again with failed records present
                bs.enforce_retention(max_backups=7)

                updated_data = json.loads(manifest_file.read_text(encoding="utf-8"))
                successful_retained = [b for b in updated_data["backups"] if b["status"] == "success"]

                # Failed backups MUST NOT displace, replace, or prune valid backups
                assert len(successful_retained) == 7
                for i in range(4, 11):
                    assert (sandbox / f"safar_staging_backup_20261121_{i:02d}0000.dump").exists()

                # Verify manifest integrity in sandbox
                report = bs.verify_manifest_integrity(manifest_file)
                assert report["valid"] is True
                assert report["successful_verified"] == 7
                assert report["failed_records"] == 5

            finally:
                bs.MANIFEST_FILE = original_manifest_file


class TestServerIsolation:
    """Verifies listening ports and confirms development vs staging process separation."""

    def test_listening_ports_and_process_separation(self):
        """Verifies actual port status and distinguishes dev from staging.

        Opt-in with ``SAFAR_REQUIRE_RUNNING_SERVICES=1`` on the machine that
        runs the documented dev/staging daemons; CI without those services
        skips rather than reporting a false product regression.
        """
        if os.environ.get("SAFAR_REQUIRE_RUNNING_SERVICES") != "1":
            pytest.skip(
                "Running dev/staging daemons are not assumed; "
                "set SAFAR_REQUIRE_RUNNING_SERVICES=1 on the staging host"
            )

        def is_port_listening(port: int, host: str = "127.0.0.1") -> bool:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(1.0)
                return s.connect_ex((host, port)) == 0

        # Port 8000: Dev API backend is listening
        dev_api_listening = is_port_listening(8000)
        assert dev_api_listening is True, "Port 8000 (Development API) should be listening"

        # Port 8020: Staging API backend is listening
        staging_api_listening = is_port_listening(8020)
        assert staging_api_listening is True, "Port 8020 (Staging API) should be listening"

        # Port 3000: Dev Web frontend is listening
        dev_web_listening = is_port_listening(3000)
        assert dev_web_listening is True, "Port 3000 (Development Web) should be listening"

        # Port 3020: Staging Web frontend is NOT listening
        staging_web_listening = is_port_listening(3020)
        assert staging_web_listening is False, "Port 3020 (Staging Web) is NOT listening; staging web is not running"
