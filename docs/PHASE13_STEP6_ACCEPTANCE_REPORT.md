# SAFAR — Phase 13, Step 6 Acceptance Report
## Monitoring, Observability & Operational Reliability

**Date:** 2026-11-21 / 2026-11-22  
**Environment:** Isolated Local Staging (`.env.staging`)  
**Staging API Endpoint:** `http://127.0.0.1:8020` (PID 51932, verified active)  
**Staging Web Endpoint:** `http://localhost:3020` (**Verified Inactive / Not listening**; Dev Web runs separately on port 3000, PID 50400)  
**Development Services:** API `http://127.0.0.1:8000` (PID 49740), Web `http://localhost:3000` (PID 50400)  
**Database:** Dedicated Supabase PostgreSQL 17 (role `safar_app`, NOSUPERUSER, NOBYPASSRLS, PostGIS, TLS)  
**Media Storage:** Isolated private directory `services/api/storage_staging/`  
**Phase Status:** **STEP 6 COMPLETE — AWAITING USER APPROVAL TO PROCEED**

---

### Executive Summary

In Phase 13 Step 6, a comprehensive, enterprise-grade monitoring, observability, and operational reliability foundation was implemented and verified across the SAFAR ecosystem. The implementation provides structured JSON logging with automated sensitive data redaction, thread-safe in-memory operational metrics collection, alert management with automated 5-minute category cooldowns, dual-probe health and readiness architecture, mobile client unhandled error capture with circular breadcrumb buffering, network and WebSocket lifecycle telemetry, offline sync failure tracking and recovery, and automated PostgreSQL logical backup with SHA-256 manifest tracking and non-destructive restore drill verification.

Following the initial audit, a focused verification was conducted across four critical operational dimensions:
1. **Metrics persistence:** Exact itemization of in-memory metrics lost on restart versus disk-backed data preserved across restarts, without adding external monitoring dependencies.
2. **Alert delivery:** Accurate documentation and test verification of `safar.alert` as an in-process structured logging channel and in-memory log, confirming it is not an active external notification mechanism unless explicitly configured with `ALERT_WEBHOOK_URL`.
3. **Backup retention:** Hardening and verification of seven-backup retention, ensuring the newest successful backup is strictly preserved, failed backups never displace or prune valid backups, and manifest integrity hashes match on-disk dump files without deleting existing backups.
4. **Server isolation:** Direct socket and process verification distinguishing development processes (ports 3000, 8000) from staging (port 8020), explicitly confirming that the staging frontend on port 3020 is not currently running, and preserving all healthy background servers without termination or restart.

All 132 backend tests, 12 web tests, 61 mobile unit/widget tests, 12 mobile live API integration tests, and the automated backup drill passed cleanly with zero failures.

---

### 1. Focused Verification Findings & Evidence

#### 1.1 Metrics Persistence & API Restart Behavior
Operational metrics are collected through `MetricsCollector` ([services/api/app/core/metrics.py](file:///c:/Users/siddharth/Desktop/SAFAR/services/api/app/core/metrics.py)). In strict compliance with guidelines, no external monitoring dependencies (e.g. Prometheus, Datadog, Redis) were introduced.

- **Metrics Stored Only in Memory (Lost on API Restart):**
  - **Process Lifetime:** `started_at`, `start_monotonic`, `uptime_seconds`.
  - **HTTP Throughput & Status Distribution:** `requests_total`, `status_2xx`, `status_3xx`, `status_4xx`, `status_5xx`.
  - **Latency Profiles:** `_latencies` (rolling deque of max 200 samples) and calculated `avg_latency_ms`.
  - **Security & Authentication Events:** `auth_login_success`, `auth_login_failure`, `auth_refresh_success`, `auth_refresh_failure`, `auth_refresh_reuse` (theft detection), `auth_session_revoked`, `csrf_failures`, `rate_limit_exceeded`, `permission_denied`.
  - **Database Telemetry:** `db_queries_total`, `db_slow_queries_total` (>500ms), `db_errors_total`, `db_last_query_ms`.
  - **Realtime / WebSocket:** `ws_active_connections`, `ws_total_connected`, `ws_total_disconnected`, `ws_total_broadcasts`, `ws_auth_rejected`.
  - **Media Uploads:** `media_uploads_success`, `media_uploads_rejected_size`, `media_uploads_rejected_mime`.
  - **Offline Sync:** `sync_batches_total`, `sync_items_applied`, `sync_items_rejected`, `sync_items_skipped`.
  - **Alert Manager History:** Circular alert history (`_recent_alerts`, max 50) and category cooldown timestamps (`_last_alert_times`).

- **Operational Data Preserved Across Restarts:**
  - **Media Storage Usage:** File count and disk usage in bytes are queried dynamically on demand from the filesystem (`storage_staging/`) in `GET /api/admin/metrics`, reflecting actual disk state across restarts.
  - **Backup History:** Stored persistently on disk in `storage_staging/backups/backup_manifest.json`, retaining all completed backup records and verification statuses.
  - **Relational Domain Data:** Stored permanently in PostgreSQL 17 (users, trips, itineraries, proposals, expenses, pacts, etc.).
  - **Security & User Audit Trails:** Stored permanently in the PostgreSQL `audit_logs` table (user logins, consent grants, administrative changes).

- **Automated Verification:**
  - Tested in `services/api/tests/test_phase13_step6_focused_verification.py::TestMetricsPersistence::test_in_memory_metrics_reset_on_restart`.
  - Verified that accumulating metrics, terminating the session, and instantiating a new collector resets all counters to 0, empties the latency sample buffer, and resets uptime, while file-backed manifest records survive intact.

#### 1.2 Alert Delivery Capabilities & Channels
Operational alerts are managed by `AlertManager` ([services/api/app/core/alerting.py](file:///c:/Users/siddharth/Desktop/SAFAR/services/api/app/core/alerting.py)).

- **Delivery Mechanism Assessment:**
  - `safar.alert` is **strictly an in-process structured logging channel and in-memory circular history buffer**.
  - In default staging and development configurations (`ALERT_WEBHOOK_URL` is unset / `None`), it is **NOT an active external notification mechanism**. It does NOT deliver emails, SMS, mobile push notifications, or external webhook calls.
  - Alerts are emitted via Python standard logging to logger `safar.alert` at level `CRITICAL` or `WARNING`. The attached `JsonFormatter` writes a single-line structured JSON record with the full alert dictionary attached under `extra={"alert": alert_dict}`.
  - In-memory circular history stores the last 50 alerts, inspectable programmatically or via `GET /api/admin/metrics`.
  - **Cooldown Rate-Limiting:** A strict 5-minute (300-second) cooldown per alert category prevents log flooding during sustained error events. Subsequent triggers within the cooldown window return `False` and are suppressed unless `force=True` is explicitly specified.
  - **Optional External Webhook:** If an operator explicitly configures `ALERT_WEBHOOK_URL` in the environment, `AlertManager._dispatch_webhook()` initiates a non-blocking background HTTP POST with the alert payload.

- **Automated Verification:**
  - Tested in `test_phase13_step6_focused_verification.py::TestAlertDelivery`.
  - Verified that triggering an alert emits a structured JSON log record to `safar.alert`, immediate subsequent triggers within 300 seconds are throttled (`emitted == False`), and zero network calls are attempted when `ALERT_WEBHOOK_URL` is unset.

#### 1.3 Backup Retention, Failure Isolation & Manifest Integrity
PostgreSQL backup operations are managed by `backup_staging.py` ([services/api/scripts/backup_staging.py](file:///c:/Users/siddharth/Desktop/SAFAR/services/api/scripts/backup_staging.py)).

- **Retention & Safety Rules:**
  - **Seven-Backup Retention:** `enforce_retention(max_backups=7)` partitions records into successful dumps and failure audit logs. Slicing `successful[:-max_backups]` prunes only the oldest successful dumps beyond the 7th.
  - **Preserving Most Recent Backup:** The newest successful backup (`successful[-1]`) is mathematically guaranteed to never be pruned.
  - **Failed Backup Isolation:** Failed backups (`status == "failed"`) do NOT count towards the 7 retained backups and NEVER cause valid successful backups to be pruned or displaced.
  - **Partial Dump Cleanup:** If `pg_dump` fails with a non-zero exit code, any partial or 0-byte `.dump` file on disk is immediately unlinked before recording the failure in the manifest.
  - **Cryptographic Manifest Verification:** `verify_manifest_integrity()` checks every manifest entry against the actual filesystem: verifies file existence, exact byte size, and SHA-256 cryptographic checksums.

- **Automated Verification:**
  - **Live Non-Destructive Check:** `TestBackupRetentionAndIntegrity::test_live_staging_manifest_integrity_preserved` verified the live staging backup `safar_staging_backup_20261121_182557.dump` (`size_bytes: 919,147`, `sha256: e31f1e020a750db261f507199ae41233e1d0e806e121bdcc189f9b8f5d3115ba`). Zero existing backups were deleted.
  - **Sandbox Retention & Failure Drill:** `TestBackupRetentionAndIntegrity::test_seven_backup_retention_and_failure_isolation_sandbox` generated 10 successful mock backups in an isolated temporary directory, confirmed retention pruned exactly the 3 oldest and preserved the 7 newest (including the latest), and proved that appending 5 failed backup attempts caused zero displacement of the 7 valid backups.

#### 1.4 Server Isolation & Process Demarcation
Direct network socket queries and Windows process table inspections were performed to establish accurate process demarcation:

| Port | Service Role | Protocol / State | Owning Process | Command Line / Origin | Assessment |
| :---: | :---: | :---: | :---: | :---: | :--- |
| **3000** | Development Web | TCP Listen `[::]:3000` | PID 50400 (`node.exe`) | `npm run dev` in `apps/web` (`next dev -p 3000`) | **Active Development Web Frontend** |
| **3020** | Staging Web | **CLOSED / NOT LISTENING** | None | None | **Inactive — Staging Frontend is NOT genuinely running** |
| **8000** | Development API | TCP Listen `127.0.0.1:8000` | PID 49740 (`python3.13`) | `uvicorn app.main:app --host 127.0.0.1 --port 8000` | **Active Development API Backend** |
| **8020** | Staging API | TCP Listen `127.0.0.1:8020` | PID 51932 (`python3.13`) | `uvicorn app.main:app --host 127.0.0.1 --port 8020` with `.env.staging` | **Active Staging API Backend** |

- **Process Demarcation Confirmation:**
  - Port 3000 is exclusively the development Next.js instance.
  - Port 3020 is **not running**. Previous reports listing `http://localhost:3020` documented target staging configuration parameters from `.env.staging` (`CORS_ORIGINS=http://localhost:3020`), but no staging web process was spawned or is listening.
  - The staging API on port 8020 is backed by dedicated Supabase PostgreSQL 17 under the non-privileged `safar_app` role.
  - **Process Preservation:** In strict compliance with instructions, all three healthy running processes (PIDs 50400, 49740, 51932) were left undisturbed, with zero terminations or restarts.

---

### 2. Implemented Backend Observability Foundation

#### 2.1 Structured JSON Logging & Sensitive Data Redaction
- **File:** [services/api/app/core/logging.py](file:///c:/Users/siddharth/Desktop/SAFAR/services/api/app/core/logging.py)
- **Features:**
  - `JsonFormatter`: Formats all application logs as single-line JSON with `timestamp`, `level`, `logger`, `message`, `environment`, and correlated `request_id`.
  - `redact_path()`: Automatically scrubs sensitive path parameters (`/api/companion/[REDACTED]`, `/api/trips/{id}/invitations/[REDACTED]`, `/api/trips/{id}/media/[REDACTED]`) and strips query parameters containing `token`, `sig`, `key`, `password`, or `secret`.
  - `redact_sensitive_dict()`: Recursively scrubs sensitive keys (`password`, `token`, `authorization`, `cookie`, `secret`) from logged payloads.
  - `CorrelationIdMiddleware`: Injects and propagates `X-Request-Id` across all request-bound log records.

#### 2.2 Operational Metrics Collector
- **File:** [services/api/app/core/metrics.py](file:///c:/Users/siddharth/Desktop/SAFAR/services/api/app/core/metrics.py)
- **Features:** Thread-safe singleton collector tracking HTTP status distribution, rolling request latencies (p50, p95), security violations, database query execution times, slow queries (>500ms), WebSocket client lifecycles, media upload rejection reasons, and offline sync batch counts.

#### 2.3 Alert Management with Automated Cooldown
- **File:** [services/api/app/core/alerting.py](file:///c:/Users/siddharth/Desktop/SAFAR/services/api/app/core/alerting.py)
- **Features:** Supports severities (`INFO`, `WARNING`, `CRITICAL`) and categories (`DATABASE_DOWN`, `SLOW_QUERY`, `HIGH_AUTH_FAILURES`, `REFRESH_REUSE_DETECTED`, `HIGH_API_ERROR_RATE`, `SECURITY_VIOLATION`, `MEDIA_UPLOAD_FAILURES`, `BACKUP_FAILED`, `OFFLINE_SYNC_PERSISTENT_FAILURES`). Enforces a 5-minute category cooldown. Emits structured JSON alerts to `safar.alert`.

#### 2.4 Database Observability & Dual-Probe Health Architecture
- **Files:** [services/api/app/db/session.py](file:///c:/Users/siddharth/Desktop/SAFAR/services/api/app/db/session.py), [services/api/app/main.py](file:///c:/Users/siddharth/Desktop/SAFAR/services/api/app/main.py)
- **Features:**
  - SQLAlchemy cursor execution event listeners timing every query, alerting on queries exceeding 500ms, and recording database errors.
  - `get_db_pool_status()` providing pool health (`size`, `checked_in`, `checked_out`, `overflow`).
  - `GET /api/health`: Lightweight liveness probe.
  - `GET /api/ready`: Readiness probe validating live database connectivity via `check_db_readiness()`. Returns `{"status": "ready", "database": "ok"}` on success; returns `503 Service Unavailable` on failure without disclosing internal connection strings, database software versions, or ping times.

#### 2.5 Secured Administrative Metrics Endpoint
- **File:** [services/api/app/routers/admin.py](file:///c:/Users/siddharth/Desktop/SAFAR/services/api/app/routers/admin.py)
- **Features:** `GET /api/admin/metrics` gated strictly by `require_admin` dependency (returns `401` for anonymous, `403` for non-admin users). Exposes system uptime, HTTP throughput and latency percentiles, security incident tallies, database pool telemetry, media storage volume/bytes, and backup manifest records.

---

### 3. Implemented Mobile Client Diagnostics & Telemetry

#### 3.1 Mobile Diagnostics Service
- **File:** [apps/mobile/lib/core/services/diagnostics_service.dart](file:///c:/Users/siddharth/Desktop/SAFAR/apps/mobile/lib/core/services/diagnostics_service.dart)
- **Features:** Bounded circular buffer (100 entries) capturing diagnostic breadcrumbs (`app`, `network`, `realtime`, `sync`, `error`) across severity levels (`debug`, `info`, `warning`, `error`, `critical`). Automatically redacts JWTs, bearer tokens, passwords, emails, and HMAC signatures. Configured in [apps/mobile/lib/main.dart](file:///c:/Users/siddharth/Desktop/SAFAR/apps/mobile/lib/main.dart) via `FlutterError.onError` and `PlatformDispatcher.instance.onError`.

#### 3.2 Network, Realtime & Offline Queue Telemetry
- **Files:** [api_client.dart](file:///c:/Users/siddharth/Desktop/SAFAR/apps/mobile/lib/core/network/api_client.dart), [trip_channel.dart](file:///c:/Users/siddharth/Desktop/SAFAR/apps/mobile/lib/core/realtime/trip_channel.dart), [offline_queue.dart](file:///c:/Users/siddharth/Desktop/SAFAR/apps/mobile/lib/core/storage/offline_queue.dart)
- **Features:** `_TelemetryInterceptor` logging request durations and 401 events; `TripChannel` logging WebSocket state transitions and reconnect backoff; `OfflineQueue` tracking item status (`pending`, `syncing`, `failed`), retry counts, error reasons, and user-initiated recovery via `retryFailed()`.

---

### 4. Full Regression & Verification Matrix

| Component | Test Suite / Command | Total Tests | Passed | Failed | Status |
| :--- | :--- | :---: | :---: | :---: | :---: |
| **Backend API** | `pytest services/api/tests` (including focused & observability tests) | 132 | 132 | 0 | **100% PASS** |
| **Focused Verification** | `pytest test_phase13_step6_focused_verification.py` | 7 | 7 | 0 | **100% PASS** |
| **Frontend Web** | `npm run typecheck` & `npm test` in `apps/web` | 12 | 12 | 0 | **100% PASS** (0 Type Errors) |
| **Mobile Flutter** | `flutter analyze` in `apps/mobile` | 0 issues | Clean | 0 | **100% PASS** |
| **Mobile Flutter** | `flutter test` (Unit, Widget, Usability, Observability) | 61 | 61 | 0 | **100% PASS** |
| **Mobile Live API** | `flutter test test/integration/` against port `8020` | 12 | 12 | 0 | **100% PASS** |
| **PostgreSQL RLS** | `services/api/tests/verify_postgres_rls.py` on Supabase PG 17 | 100% checks | 100% | 0 | **100% PASS** |
| **Staging Stress** | `services/api/tests/verify_phase13_step5_stress.py` | 15 Scenarios | 15 | 0 | **100% PASS** |
| **Staging Backup** | `services/api/scripts/backup_staging.py --verify` | 5 Drill Steps | 5 | 0 | **100% PASS** |
| **Manifest Integrity** | `verify_manifest_integrity()` on live staging manifest | 1 Dump File | Valid | 0 | **100% PASS** |

---

### 5. Changed & Created Files Summary

#### New Files
1. `services/api/tests/test_phase13_step6_focused_verification.py` — Focused verification test suite covering metrics persistence, restart behavior, alert channels/cooldowns, backup retention/integrity, and server isolation.
2. `services/api/app/core/metrics.py` — In-memory thread-safe metrics collector.
3. `services/api/app/core/alerting.py` — Operational alert manager with cooldown rate-limiting.
4. `services/api/scripts/backup_staging.py` — Custom-format logical PostgreSQL backup, manifest integrity verification, retention management, and restore drill script.
5. `services/api/tests/test_observability.py` — Backend observability test suite (13 tests).
6. `apps/mobile/lib/core/services/diagnostics_service.dart` — Mobile diagnostics service with circular event buffering and redaction.
7. `apps/mobile/test/phase13_step6_observability_test.dart` — Mobile observability test suite (4 tests).
8. `docs/PHASE13_STEP6_ACCEPTANCE_REPORT.md` — Complete acceptance report document.

#### Modified Files
1. `services/api/scripts/backup_staging.py` — Hardened `enforce_retention` to strictly preserve the newest successful backup and isolate failed records; added `verify_manifest_integrity()`.
2. `services/api/tests/verify_postgres_rls.py` — Fixed password management to use the stable staging password from `.env.staging` rather than mutating the password on each run.
3. `services/api/app/core/alerting.py` — Added `SLOW_QUERY` and `SECURITY_VIOLATION` to `AlertCategory`.
4. `services/api/app/core/config.py` — Added `slow_query_threshold_ms` and `alert_webhook_url`.
5. `services/api/app/core/logging.py` — Added `JsonFormatter`, `redact_path`, and `redact_sensitive_dict`.
6. `services/api/app/core/middleware.py` — Integrated HTTP latency metrics and 5xx alert dispatches.
7. `services/api/app/core/deps.py` & `ratelimit.py` — Added security logging and metrics for CSRF, auth drops, and rate limits.
8. `services/api/app/db/session.py` & `main.py` — Added query timing listeners, `get_db_pool_status()`, `check_db_readiness()`, and dual-probe `/api/health` and `/api/ready`.
9. `services/api/app/routers/admin.py` — Added secured `GET /api/admin/metrics` endpoint.
10. `apps/mobile/lib/main.dart` — Wired global error handling.
11. `apps/mobile/lib/core/network/api_client.dart` — Added telemetry interceptor.
12. `apps/mobile/lib/core/realtime/trip_channel.dart` — Added realtime telemetry.
13. `apps/mobile/lib/core/storage/offline_queue.dart` — Added state tracking (`pending`, `syncing`, `failed`) and `retryFailed()`.
14. Documentation: Updated `docs/SECURITY.md`, `docs/ARCHITECTURE.md`, `docs/FEATURE_REGISTRY.md`, `apps/mobile/README.md`, and root `README.md`.

---

### 6. Phase Boundary & Next Steps

Phase 13 Step 6 verification is complete. All four requested points have been thoroughly verified with automated test evidence and accurate documentation.

**In strict compliance with instructions:**
- No Phase 13 Step 7 activities have been started.
- No production release or deployment has been attempted.
- All healthy background server processes remain running undisturbed.
- Execution has halted awaiting your review and approval.
