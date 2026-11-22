# SAFAR — Phase 13, Step 7 Production Readiness Report
## Release Blockers, Staging Sign-Off & Production Readiness Assessment

**Date:** 2026-11-22  
**Phase:** 13 — Controlled Pilot & Real-World Validation  
**Step:** 7 — Production Readiness Assessment  
**Environment:** Local Isolated Staging & Dedicated Supabase PostgreSQL 17  
**Staging API Endpoint:** `http://127.0.0.1:8020` (PID 51932, verified active)  
**Staging Web Endpoint:** `http://localhost:3020` (Verified inactive; target port in `.env.staging`)  
**Development Services:** API `http://127.0.0.1:8000` (PID 49740), Web `http://localhost:3000` (PID 50400)  
**Database:** Dedicated Supabase PostgreSQL 17 (`safar_app` restricted role, NOSUPERUSER, NOBYPASSRLS, PostGIS, TLS)  
**Media Storage:** Isolated private directory `services/api/storage_staging/`  
**Phase Status:** **STEP 7 COMPLETE — AWAITING USER APPROVAL BEFORE PROCEEDING**

---

### Executive Summary

In Phase 13 Step 7, an exhaustive technical, security, infrastructure, database, mobile, and web production readiness assessment was conducted for **SAFAR 1.0.0 — The Living Journey Network**. 

Passing automated test suites does not inherently equal production readiness. This evaluation audited the actual codebase, configurations, database security architecture, build artifacts, network behaviors, and deployment topology to identify every remaining requirement, operational risk, external account dependency, and blocker before SAFAR can transition from local staging to a production public launch.

**Key Findings:**
1. **Core Capabilities:** All 49 master features (F01–F49) are fully implemented across backend APIs, Next.js web client, and the Flutter mobile client. The intelligence layer is deterministic, grounded, explainable, and privacy-preserving.
2. **Database Security & RLS:** PostgreSQL Row-Level Security is active across all 56 domain tables (55 forced, 220 policies) with fail-closed tenant isolation. Alembic migration revision is verified at head (`e5c8a2b7d940`).
3. **Transport & Connection Pooling:** Direct connections to `db.<ref>.supabase.co:5432` are IPv6-only on AWS and subject to host network packet loss; connecting via the dedicated IPv4 session pooler (`aws-0-[region].pooler.supabase.com:5432`) is required for reliable production connectivity.
4. **Disaster Recovery Gap:** Current backups rely on logical custom-format dumps (`pg_dump -Fc`) with 7-backup retention and manifest verification. Production requires cloud-managed automated continuous WAL archiving and Point-in-Time Recovery (PITR) with an RPO < 15 min and RTO < 1 hour.
5. **Mobile Release Artifacts:** The existing release APK and AAB were signed with a temporary throwaway verification key. An official production upload keystore must be generated and registered in Google Play Console.
6. **iOS Platform Limitation:** The current development environment is Windows without macOS/Xcode. iOS cannot be certified release-ready without building, signing, and testing on a physical iOS device with macOS.
7. **Infrastructure & Hosting:** Production requires provisioning dedicated cloud hosting (co-located backend and database), private cloud object storage (S3/R2 with presigned URLs) to replace local filesystem media, custom domain DNS with TLS termination, and external developer accounts.

---

### 1. Master Specification Compliance Audit (F01–F49)

Every feature in [SAFAR_MASTER_SPECIFICATION.md](file:///c:/Users/siddharth/Desktop/SAFAR/SAFAR_MASTER_SPECIFICATION.md) and [docs/FEATURE_REGISTRY.md](file:///c:/Users/siddharth/Desktop/SAFAR/docs/FEATURE_REGISTRY.md) was inspected across backend routers, Flutter screens, web pages, database authorization policies, and regression tests.

| Feature ID & Name | Status | Backend Service / Endpoints | Flutter Mobile Screen | Next.js Web Route | Privacy & Authorization Controls | Automated Test Evidence | Known Limitations |
| :--- | :---: | :--- | :--- | :--- | :--- | :--- | :--- |
| **F01 Account & Consent** | ✅ Complete | `routers/auth.py`, `users.py` | `SettingsScreen`, `ProfileScreen` | `/profile`, `/settings`, `/login` | Per-purpose consent versioned (`2026-01`), anonymizing account erasure, token revocation. | `test_registration_grants_only_required_consent` | In-memory session tracking per-process. |
| **F02 Journey DNA** | ✅ Complete | `GET/PUT /api/me/dna` | `ProfileScreen` (DNA section) | `/profile` | Explicit edits only; feedback changes DNA only with explicit consent. | `test_dna_consent_gating` | Purely heuristic scoring (0–10). |
| **F03 Discovery** | ✅ Complete | `routers/places.py`, `destinations.py` | `DiscoveryScreen` | `/discover`, `/discover/[id]` | Hard filters applied before scoring; lens (balanced/iconic/similar); provenance labels. | `test_places_discovery` | Static curated catalog seed. |
| **F04 Trip Roster & Roles** | ✅ Complete | `routers/trips.py` (members, invites) | `PeopleInvitesScreen` | `/trips/[id]/members` | Single-use invitation tokens, email-bound, owner/admin role gates, member removal confirmation. | `test_invite_reuse_409`, `test_foreign_email_403` | No outbound SMTP; invitation URLs shared via OS share sheet. |
| **F05 Collaborative Itinerary & Voting** | ✅ Complete | `routers/itinerary.py`, `voting.py` | `ItineraryScreen`, `VotingScreen` | `/trips/[id]/itinerary`, `/voting` | Unapproved proposals cannot mutate confirmed items; attendance tracked without mandatory rationale. | `test_proposal_approval_gate`, `test_member_patch_denial` | Realtime relies on active WebSocket connection. |
| **F06 Trip Pulse** | ✅ Complete | `routers/trips.py` (`/pulse`) | `PulseScreen` | `/trips/[id]/pulse` | Energy/time/radius shared; budget comfort and private notes strictly filtered server-side. | `test_pulse_privacy_isolation` | Shared only for confirmed active trip members. |
| **F07 Group Experience Engine** | ✅ Complete | `services/engine.py` | `EngineScreen` | `/trips/[id]/engine` | Hard constraints filter candidates first (budget limit, access, time, radius, protected time); fairness scoring; explainable reasons. | `test_engine_fairness`, `test_protected_time_respected` | 2.5s latency over cross-internet database SSL. No external LLM. |
| **F08 Trip Twin** | ✅ Complete | `routers/twin.py` | `TwinScreen` | `/trips/[id]/twin` | Read-only comparison; adoption opens a standard proposal requiring group approval. | `test_twin_adoption_creates_proposal` | Evaluates single-day alternative permutations. |
| **F09 Trip Rescue** | ✅ Complete | `services/rescue.py` | `RescueScreen` | `/trips/[id]/rescue` | Disruption analysis (rain, closure, fatigue, budget, lost time); replacements are proposals only; protected items cannot be replaced. | `test_rescue_leaves_protected_time_untouched` | 2.2s latency over cross-internet database SSL. Weather is unknown unless provider configured. |
| **F10 Maps & Nearby** | ✅ Complete | `services/places.py` (`/nearby`) | `NearbyScreen` | `/trips/[id]/map` | Coordinates require user consent toggle; straight-line distances from base; no live member location tracking. | `test_precise_location_requires_privacy_toggle` | Schematic fallback rendered unless tile URL configured at build time. |
| **F11 Shared Memory Timeline** | ✅ Complete | `routers/memories.py` | `MemoriesScreen` | `/trips/[id]/memories` | Private memories excluded from timeline queries; media served via expiring HMAC-signed URLs (12h TTL). | `test_private_memory_timeline_exclusion`, `test_hmac_media_link` | Media stored on local filesystem; no cloud CDN. |
| **F12 Memory Studio** | ✅ Complete | `services/memory.py` | `MemoryStudioScreen` | `/trips/[id]/memories/studio` | Deterministic event grouping; caption drafts are template-based, marked `ai_generated: false` with approval disclosure. | `test_f12_caption_is_a_template_not_ai` | Events referencing private memories hidden from peers. |
| **F13 Group Expenses** | ✅ Complete | `routers/expenses.py` | `ExpensesScreen` | `/trips/[id]/expenses` | Split reconciliation; custom split mismatch returns 422; pairwise debt minimization. | `test_splits_reconcile`, `test_balance_minimization` | CSV export only; no direct banking / payment rails. |
| **F14 Place Pulse** | ✅ Complete | `services/places.py` | `PlaceDetailScreen` | `/trips/[id]/places/[id]` | Community reports labelled `REPORTED`; moderator verification cannot convert community reports to `VERIFIED`. | `test_f14_moderator_verification_never_promotes_community` | User-submitted observation reports only. |
| **F15 Serendipity Radar** | ✅ Complete | `services/discovery.py` (`/serendipity`) | `ConnectionsScreen` | `/connections` | Opt-in, reciprocal, mutual acceptance before contact; blocked users strictly excluded; no exact locations. | `test_serendipity_reciprocal_acceptance` | In-app matching only. |
| **F16 Travel Circles** | ✅ Complete | `routers/circles.py` | `CirclesScreen` | `/circles`, `/circles/[id]` | Public vs private circles; circle members list exposes minimal display identity. | `test_circle_member_privacy` | Local community messaging only. |
| **F17 Dream Import** | ✅ Complete | `services/discovery.py` (`/inspirations`) | `InspirationsScreen` | `/trips/[id]/inspirations` | Structural text parsing; candidates proposed for review before becoming proposals; SSRF-guarded link preview (disabled by default). | `test_phase7_dream_import.py` (10 tests) | OCR requires local Tesseract binary. |
| **F18 Journey Replay & Travel Book** | ✅ Complete | `routers/memories.py` (`/replay`) | `ReplayScreen` | `/trips/[id]/memories/replay` | Private memories strictly excluded from replay; printable HTML travel book export. | `test_replay_excludes_private_memories` | Client-rendered text/photo layout. |
| **F19 Travel Missions** | ✅ Complete | `routers/missions.py` | `MissionsScreen` | `/trips/[id]/missions` | Optional, self-reported; trip administrators can disable missions per trip. | `test_missions_lifecycle` | Curated catalog mission prompts. |
| **F20 Offline Capture & Sync** | ✅ Complete | `routers/memories.py` (`/sync`) | `OfflineSyncScreen`, `OfflineQueue` | `/trips/[id]/offline` | Client-generated UUIDs; idempotent re-submission (`skipped: 1`); conflicting re-submission rejected (`409`). | `test_offline_sync_idempotency` | Synchronizes memories and pulse; itinerary edits require online connection. |
| **F21 Predictive Crowd Forecasting** | ✅ Complete | `services/places.py` (`crowd_forecast`) | `PlaceDetailScreen` | `/trips/[id]/places/[id]` | `bucket-forecast-v2`: requires ≥8 reports in 180 days; MAD outlier filter; falls back to `insufficient_data` honestly. | `test_phase7_forecasting.py` (5 tests) | Relies on community reports threshold. |
| **F22 Multilingual Assistant** | ✅ Complete | `services/assistant.py`, `language.py` | `AssistantScreen` | `/trips/[id]/assistant` | 8 languages; in-repo lexicons and grounded templates; citations with provenance; no message leaves server. | `test_phase7_multilingual.py` (12 tests) | No external LLM; unmapped phrasing falls back to English with explanation. |
| **F23 Journey Pact** | ✅ Complete | `routers/trips.py` (`/pact`) | `PactScreen` | `/trips/[id]/pact` | Individual member limits private and merged; conflicting proposals rejected with 409 at approval gate. | `test_journey_pact_limits_enforced` | Admin can edit shared pact commitments. |
| **F24 Opportunity Clock** | ✅ Complete | `services/opportunity.py` | `OpportunityScreen` | `/trips/[id]/opportunity` | Read-only feasibility evaluation for selected day; deductible free windows; no state mutated. | `test_opportunity_clock_is_read_only` | Estimates based on straight-line travel and opening hours. |
| **F25 Shadowplan** | ✅ Complete | `routers/shadowplans.py` | `InsightsScreen` | `/trips/[id]/insights` | Backups attached to itinerary items; engine/rescue can propose them; never mutates confirmed plan. | `test_shadowplan_adoption` | User-curated alternative activities. |
| **F26 One-Link Companion** | ✅ Complete | `services/companion.py`, `routers/companion.py` | `CompanionScreen` | `/trips/[id]/companion`, `/companion/[token]` | HMAC-signed token (`{id}.{exp}.{sig}`); single-use; anonymous response recorded without IP, user id, or user agent. | `test_companion_single_use_anonymous` | 1 vote or pulse check-in per link. |
| **F27 Planner Load Balancer** | ✅ Complete | `routers/trips.py` (`/tasks/summary`) | `TasksScreen` | `/trips/[id]/tasks` | Server-side summary returns counts only; task titles and descriptions remain scoped to trip members. | `test_f27_task_summary_privacy` | Shared task assignments across members. |
| **F28 Branch & Rejoin** | ✅ Complete | `routers/branches.py` | `BranchesScreen` | `/trips/[id]/branches` | Split groups with reunion place/time; travel feasibility estimated; confirmed plan untouched. | `test_branch_rejoin_feasibility` | Informational coordination tool. |
| **F29 Journey Effort Budget** | ✅ Complete | `services/optimizer.py` | `InsightsScreen` | `/trips/[id]/insights` | Walking km, transitions, rest blocks; accessibility constraints never traded for effort optimization. | `test_effort_budget_accessibility_gate` | Heuristic calculation based on activity metadata. |
| **F30 Decision Evidence Passport** | ✅ Complete | `services/places.py` | `PlaceDetailScreen` | `/trips/[id]/places/[id]` | Source, timestamp, assumptions, reports, unknowns displayed separately with clear provenance labels. | `test_provenance_labels` | Transparent disclosure of data pedigree. |
| **F31 Ask the Ground** | ✅ Complete | `routers/ground.py` | `GroundScreen` | `/trips/[id]/ground` | Ground requests require opted-in local contributor; answers labelled `REPORTED (unverified)`. | `test_ground_request_lifecycle` | Relies on registered local contributors in area. |
| **F32 Cost-Shock Guard** | ✅ Complete | `services/impact.py` | `VotingScreen` | `/trips/[id]/voting` | Per-member cost impact evaluated; proposals breaking hard member budgets blocked from approval. | `test_cost_shock_guard_blocks_approval` | Member budget limits remain private. |
| **F33 Outcome Calibrator** | ✅ Complete | `services/feedback.py` | `PlaceDetailScreen` | `/trips/[id]/places/[id]` | Sentiments update Journey DNA only with explicit consent; bounded engine nudge (±4 points). | `test_outcome_calibrator_consent` | Requires ≥2 consented raters in group of ≥3. |
| **F34 Journey Capsule** | ✅ Complete | `routers/capsules.py` | `InsightsScreen` | `/trips/[id]/insights` | Timestamped snapshot with freshness indicators; read-only memory artifact. | `test_capsule_snapshot_freshness` | Snapshot generated on-demand. |
| **F35 Constraint Compass** | ✅ Complete | `routers/trips.py` (`/pulse`) | `PulseScreen` | `/trips/[id]/pulse` | Updating today's pulse returns structured list of affected confirmed itinerary items. | `test_constraint_compass_affected_items` | Real-time advisory feedback on pulse update. |
| **F36 One Question That Matters** | ✅ Complete | `services/engine.py` | `EngineScreen` | `/trips/[id]/engine` | Clarifying prompt naming only members missing pulse for day; null when coverage complete; dismissible. | `test_f36_question_coverage` | Shown in engine recommendation header. |
| **F37 Fragility Radar** | ✅ Complete | `services/optimizer.py` | `InsightsScreen` | `/trips/[id]/insights` | Detects tight transitions (<30m), buffer deficits, and risky schedules; proposes alternative timings. | `test_fragility_radar_tight_transitions` | Heuristic assessment. |
| **F38 Domino Map** | ✅ Complete | `services/optimizer.py` | `InsightsScreen` | `/trips/[id]/insights` | Simulates cascade delays (15m, 30m, 60m) across afternoon items; identifies repair needs. | `test_domino_delay_simulation` | Purely predictive advisory model. |
| **F39 Protected Wander Window** | ✅ Complete | `services/schedule.py` | `ItineraryScreen`, `EngineScreen` | `/trips/[id]/itinerary` | `is_protected: true` is a hard constraint everywhere: Engine excludes overlapping candidates; manual edits/proposals return 409; Rescue refuses replacement. | `test_f39_protected_windows_enforced` (5 tests) | Requires start and end time. |
| **F40 Expectation Reality Check** | ✅ Complete | `services/places.py` | `PlaceDetailScreen` | `/trips/[id]/places/[id]` | Compares claim against curated catalog evidence, reports, and unknowns; states limitations. | `test_expectation_reality_check` | Grounded in curated place attributes. |
| **F41 Door-to-Door Access Chain** | ✅ Complete | `services/places.py` | `PlaceDetailScreen` | `/trips/[id]/places/[id]` | Multi-stage accessibility check: transport → path → entrance → experience → facilities → return. | `test_access_chain_unknown_handling` | Reports missing stages as `unknown` honestly. |
| **F42 Balance Lens** | ✅ Complete | `services/ranking.py` | `DiscoveryScreen` | `/discover` | Lenses: balanced, iconic, similar; compares destinations without dismissing user dreams. | `test_balance_lens_ranking` | Ranked against curated destination dataset. |
| **F43 Graceful Independent Time** | ✅ Complete | `routers/itinerary.py` (`/attendance`) | `ItineraryScreen` | `/trips/[id]/itinerary` | Attendance options: "I'm in", "Join later", "Skip" with zero mandatory justification required. | `test_independent_time_reason_free` | Recorded per itinerary item. |
| **F44 Material Change Watch** | ✅ Complete | `routers/watch.py` | `WatchScreen` | `/trips/[id]/watch` | Monitors opening hours, price spikes, and accessibility changes; check returns changed vs unchanged. | `test_material_change_watch` | Scans catalog source updates. |
| **F45 Fair Trade Negotiator** | ✅ Complete | `routers/twin.py` (`/negotiate`) | `TwinScreen` | `/trips/[id]/twin` | Multi-activity compromise trade-offs; identifies who benefits and who compromises without leaking private data. | `test_f45_negotiation_date_validation` | Scored against caller-specified trip date. |
| **F46 Local Context Requests** | ✅ Complete | `routers/ground.py` | `GroundScreen` | `/trips/[id]/ground` | Focused activity-scoped questions directed to verified local contributors. | `test_local_context_requests` | Shared infrastructure with F31. |
| **F47 Journey Thread** | ✅ Complete | `routers/users.py` (`/me/thread`) | `ThreadScreen` | `/thread` | Consented historical signals carried forward across trips (repeat, modify, avoid). | `test_journey_thread_consent` | Requires user consent toggle. |
| **F48 Neighborhood Respect Filter** | ✅ Complete | `services/engine.py`, `places.py` | `EngineScreen`, `PlaceDetailScreen` | `/trips/[id]/engine`, `/places/[id]` | Curated neighborhood respect guidance (`fragile`, `status`, `guidance`); returns `unknown` when no note exists. | `test_f48_engine_respect_grounding` | Curated editorial guidance; not an automated exclusion system. |
| **F49 Decision Load Governor** | ✅ Complete | `routers/users.py` (`/next-action`) | `DashboardScreen` | `/dashboard` | Computes exactly one recommended next action per journey; quiet mode suppresses non-critical alerts. | `test_next_action_computation` | Heuristic prioritization across trip states. |

**Audit Conclusion:** There are **zero missing or partially implemented features** in the core application logic. All 49 capabilities operate against live backend endpoints and are represented in the mobile and web clients with grounded, explainable outputs.

---

### 2. Production Database Readiness

#### 2.1 Configuration & Security Controls
- **Engine Version:** Supabase PostgreSQL 17.12 (AArch64 Linux, PostGIS available).
- **Transport Security:** TLS encryption is strictly enforced (`sslmode=require`). Plaintext database connections are rejected.
- **Application Role Privileges:**
  - The FastAPI application connects using the dedicated `safar_app` non-owner role.
  - Role attributes: `NOSUPERUSER`, `NOBYPASSRLS`.
  - Privileges granted: `USAGE` on schema `public`, `SELECT, INSERT, UPDATE, DELETE` on all tables, `USAGE, SELECT` on sequences, and `EXECUTE` on functions.
  - The role owns zero tables and cannot execute DDL commands (`CREATE TABLE`, `DROP TABLE`, `ALTER TABLE`).
- **Row-Level Security (RLS) Posture:**
  - **56 / 56 tables have RLS enabled** (`relrowsecurity = true`).
  - **55 tables have FORCE RLS enabled** (`relforcerowsecurity = true`), ensuring table owners are subject to RLS policies.
  - Exactly one table (`alembic_version`) has unforced RLS; a dedicated read-only policy (`alembic_version_read`) grants `safar_app` `SELECT` access while blocking writes.
  - Exactly **220 row-level security policies** are enforced.
  - Anonymous database queries with no `app.current_user_id` GUC fail closed, returning 0 rows.
- **Migration Synchronization:**
  - Alembic migrations are synchronized at head revision `e5c8a2b7d940`.
  - `alembic check` passes with 0 pending schema differences.

#### 2.2 Connection Pooling & IPv4/IPv6 Routing
- **Direct Connection Limitation:** The Supabase direct hostname `db.<ref>.supabase.co:5432` resolves exclusively to an IPv6 address (`AAAA` record). If deployed in an environment with unstable IPv6 routing, connections time out with `Socket is not connected (0x00002749/10057)`.
- **Session Pooler Requirement:** For production, connection strings must use the Supabase IPv4-compatible session pooler:
  ```text
  postgresql+psycopg://safar_app.<project_ref>:<password>@aws-0-[region].pooler.supabase.com:5432/postgres?sslmode=require
  ```
  This pooler natively routes over IPv4 (port 5432, session mode) and eliminates IPv6 routing dropouts.
- **Connection Pool Tuning:** The application uses SQLAlchemy's `QueuePool` with `pool_size=5`, `max_overflow=10`, `pool_timeout=30`, and `pool_pre_ping=True`. For high-concurrency production deployments (>50 concurrent API workers), connection pooling should be offloaded to Supavisor or a dedicated PgBouncer instance.

#### 2.3 Backup, Retention & Disaster Recovery
- **Logical Backup Runbook:** [backup_staging.py](file:///c:/Users/siddharth/Desktop/SAFAR/services/api/scripts/backup_staging.py) executes `pg_dump -Fc` compressed logical backups, verifies SHA-256 checksums, and updates [backup_manifest.json](file:///c:/Users/siddharth/Desktop/SAFAR/storage_staging/backups/backup_manifest.json).
- **Retention Invariant:** `enforce_retention(max_backups=7)` prunes only the oldest successful backups. The most recent successful backup is mathematically guaranteed to never be deleted. Failed backup attempts are recorded for auditing but never displace valid dumps. Partial dump files from failed runs are immediately cleaned up.
- **Restore Verification Drill:** Automated drill successfully provisioned temporary database `safar_restore_verify`, restored all objects via `pg_restore --clean`, verified 56 tables, 220 policies, RLS flags, and tenant isolation, and cleanly tore down the verification database.
- **CRITICAL Disaster Recovery Gap:** Staging currently relies entirely on periodic logical backups. Logical dumps do not support Point-in-Time Recovery (PITR). If a disaster occurs, all data written between the last backup and the incident is lost.
  - **Required Action for Production:** Continuous Write-Ahead Log (WAL) archiving and PITR must be enabled through managed cloud database configuration (e.g. Supabase Pro, AWS RDS, or Google Cloud SQL) with a Recovery Point Objective (RPO) < 15 minutes and Recovery Time Objective (RTO) < 1 hour.
- **Database Isolation Invariant:** Staging and production MUST use completely separate physical or managed database instances. Under no circumstances should staging and production share schemas or credentials.

---

### 3. Security Readiness Review

| Security Dimension | Staging Implementation | Production Assessment | Status |
| :--- | :--- | :--- | :---: |
| **Authentication & Tokens** | Access tokens: 15m expiration, signed with `SECRET_KEY`. Refresh tokens: 30d, HttpOnly cookies, server-side session registry in `auth_sessions`. | Robust. Cryptographically sound. Access tokens stay in memory; cookies use secure storage on mobile. | ✅ PASS |
| **Refresh Reuse / Theft Detection** | Single-use refresh token rotation. Replaying an invalidated refresh token triggers immediate revocation of the entire session family and dispatches a critical alert. | Fully operational and regression-tested. | ✅ PASS |
| **Session Revocation** | `POST /api/auth/logout` invalidates session in database and expires cookies client-side. | Prevents ghost sessions. | ✅ PASS |
| **CSRF Protection** | Double-submit cookie pattern: readable `safar_csrf` cookie matched with `X-CSRF-Token` header using constant-time comparison on unsafe HTTP methods. | Protects cookie-based browser sessions against CSRF. | ✅ PASS |
| **CORS Policy** | Explicit origin allowlist in `CORS_ORIGINS`. Production guards abort startup if wildcard `*` is present. | Must be configured to exact production domains. | ✅ PASS |
| **Host Header Injection** | `TrustedHostMiddleware` enforces `TRUSTED_HOSTS`. Unrecognized hosts receive 400 Bad Request. | Protects against cache poisoning and host header attacks. | ✅ PASS |
| **Secure Cookies & Transport** | Staging uses `COOKIE_SECURE=false` for localhost. Production config guards enforce `COOKIE_SECURE=true` and reject plain HTTP. | Production must terminate TLS at reverse proxy / load balancer. | ✅ PASS (Guarded) |
| **Rate Limiting** | Sliding window limiters: general (240/min), auth (10-120/min), companion (20-60/min), upload (30-60/min). | Operates in-process memory. **Multi-instance deployment requires Redis.** | ⚠️ CONDITIONAL |
| **Upload Security** | Magic-byte file sniffing, strict MIME type validation (JPEG, PNG, WebP), max upload size cap 25MB (`MAX_REQUEST_BYTES`). | Spoofed extensions and oversized payloads fail fast. | ✅ PASS |
| **Media Access Control** | Media stored in private directory. Served only through expiring HMAC-signed URLs (12h TTL). Unsigned or expired links return 403 Forbidden. | Filesystem storage must be migrated to private cloud object storage (S3/R2) with presigned URLs. | ⚠️ CONDITIONAL |
| **Tenant Isolation (RLS)** | 56 tables with RLS; 55 tables with FORCE RLS; 220 policies. Transaction-local GUCs (`app.user_id`). Anonymous access fails closed (0 rows). | Verified against live PostgreSQL 17 under `safar_app` role. | ✅ PASS |
| **Sensitive Data Redaction** | `JsonFormatter` redacts passwords, tokens, authorization headers, HMAC signatures, and sensitive paths (`companion`, `invitations`, `media`) from application logs. | Prevents credential and PII leakage in log aggregators. | ✅ PASS |
| **Deep-Link Security** | Custom schemes `safar://companion/<token>` and `safar://invite/<token>` using cryptographically random single-use tokens. | Companion responses recorded without user id, IP, or user agent. | ✅ PASS |
| **Location Consent Gate** | Profile-level toggle `location_sharing: false` disables GPS coordinates server-side. Coordinates sent only on explicit current query. | No continuous background location tracking. | ✅ PASS |

---

### 4. Android Release Readiness

- **Application Identifier:** `app.safar.safar_mobile`
- **Version Number:** `1.0.0+1` (Version Name: `1.0.0`, Version Code: `1` in [pubspec.yaml](file:///c:/Users/siddharth/Desktop/SAFAR/apps/mobile/pubspec.yaml#L19))
- **SDK Targets:** `minSdk = 21` (Android 5.0 Lollipop), `targetSdk = 36` (Android 16), `compileSdk = 36` in [build.gradle.kts](file:///c:/Users/siddharth/Desktop/SAFAR/apps/mobile/android/app/build.gradle.kts#L50).
- **Permissions Audit in Manifest:**
  - `android.permission.INTERNET` (Required for API and tile fetching).
  - `android.permission.ACCESS_COARSE_LOCATION` and `android.permission.ACCESS_FINE_LOCATION` (Used only for Nearby discovery; `uses-feature android.hardware.location` is explicitly marked `android:required="false"` so devices without GPS can install).
  - No camera or storage permissions declared in Android manifest (photo picking uses the system photo picker contract via `image_picker`, avoiding broad external storage permissions).
- **Cleartext Traffic Policy:** `android:usesCleartextTraffic="false"` in [AndroidManifest.xml](file:///c:/Users/siddharth/Desktop/SAFAR/apps/mobile/android/app/src/main/AndroidManifest.xml#L15). Cleartext is permitted only in the debug overlay for emulator development.
- **Deep-Link Intent Filters:** Configured for custom scheme `safar://` with hosts `companion` and `invite`.
- **Existing Build Artifacts:**
  - Debug APK: `build/app/outputs/apk/debug/app-debug.apk` (185 MB)
  - Release APK: `build/app/outputs/apk/release/app-release.apk` (61.4 MB)
  - Release AAB: `build/app/outputs/bundle/release/app-release.aab` (47.7 MB)
- **CRITICAL Android Release Blocker:**
  - The existing release artifacts were signed using a **throwaway temporary verification keystore** generated during Phase 10 to validate the Gradle signing pipeline.
  - **These artifacts are NOT valid for Google Play Store upload.**
  - **Required Action:**
    1. A genuine production upload keystore (`safar-upload-keystore.jks`) must be generated using `keytool`.
    2. Keystore credentials must be supplied via production environment variables (`SAFAR_KEYSTORE_PATH`, `SAFAR_KEYSTORE_PASSWORD`, `SAFAR_KEY_ALIAS`, `SAFAR_KEY_PASSWORD`).
    3. The public certificate must be enrolled in Google Play App Signing.
    4. Release AAB must be recompiled and signed with the official upload key.

---

### 5. iOS Release Readiness

- **Bundle Identifier:** `app.safar.safar_mobile`
- **Privacy & Usage Descriptions in [Info.plist](file:///c:/Users/siddharth/Desktop/SAFAR/apps/mobile/ios/Runner/Info.plist):**
  - `NSCameraUsageDescription`: *"SAFAR uses the camera only when you choose to add a photo to a trip memory."*
  - `NSPhotoLibraryUsageDescription`: *"SAFAR reads the photo you pick so it can be attached to a trip memory."*
  - `NSLocationWhenInUseUsageDescription`: *"SAFAR uses your location only when you tap 'Use my current location' to sort nearby places. It is not shared with the group."*
- **URL Types:** `app.safar.companion` scheme registered for `safar://`.
- **CRITICAL Platform Limitation & Blocker:**
  - The current development and build host is **Windows 11 x64**.
  - macOS and Xcode 15+ are strictly required to compile Objective-C/Swift plugins, build the iOS Runner target, provision certificates, configure Apple App Store distribution profiles, and generate an `.ipa` archive.
  - **Required Action:**
    1. Establish a macOS build runner (e.g. GitHub Actions macOS runner, Mac Stadium, or physical Mac).
    2. Enroll in the Apple Developer Program ($99/year).
    3. Generate Apple Distribution Certificate and Provisioning Profile.
    4. Compile release archive with `flutter build ipa --release`.
    5. Test release binary on a physical iPhone via TestFlight before public distribution.

---

### 6. Web Production Readiness

- **Framework:** Next.js 15.5.29 (App Router) + React 19.3.1 + TypeScript 5.7.
- **Production Build Verification:**
  - Executed `npm run build` in [apps/web](file:///c:/Users/siddharth/Desktop/SAFAR/apps/web).
  - Output: Compiled successfully in 16.8s. Generated static and dynamic server routes for all 51 product paths with zero syntax, type, or bundling errors.
- **Security Headers in [next.config.ts](file:///c:/Users/siddharth/Desktop/SAFAR/apps/web/next.config.ts#L9):**
  - `X-Content-Type-Options: nosniff`
  - `Referrer-Policy: strict-origin-when-cross-origin`
  - `X-Frame-Options: SAMEORIGIN`
- **Cookie Security:** Web client uses `BrowserHttpClientAdapter(withCredentials: true)`, relying on browser-enforced HttpOnly cookie transport for access and refresh sessions.
- **Staging Frontend Status:** Port 3020 is currently inactive. Development frontend is running on port 3000 (PID 50400). The web application was verified via TypeScript typechecking (`tsc --noEmit`), Vitest suite (12/12 passed), and optimized production build generation.

---

### 7. Target Production Infrastructure Architecture

```
                                  INTERNET
                                      │
                         [ Cloudflare CDN & DDoS Shield ]
                                      │
                       TLS 1.3 Termination (HTTPS)
                                      │
            ┌─────────────────────────┴─────────────────────────┐
            │                                                   │
  [ Next.js Web App ]                                 [ Reverse Proxy / ALB ]
  (Vercel / Cloud Run)                                          │
            │                                     [ FastAPI Backend Cluster ]
            │                                     (AWS ECS Fargate / Cloud Run)
            │                                     (Min 2 instances, autoscaled)
            │                                                   │
            │                         ┌─────────────────────────┼─────────────────────────┐
            │                         │                         │                         │
            ▼                         ▼                         ▼                         ▼
    [ Public APIs ]        [ Distributed Cache ]     [ Private Object Storage ]   [ PostgreSQL 17 + PostGIS ]
    (HTTPS/WSS)            (Redis Cluster / ElastiCache)  (AWS S3 / Cloudflare R2)  (Supabase Pro / AWS RDS)
                           - Shared Rate Limits      - Encrypted Media Files      - Multi-AZ Deployment
                           - Session Invalidation    - Presigned URLs (12h TTL)   - Continuous WAL Archiving
                           - WebSocket Pub/Sub Bus                                - Automated PITR (RPO <15m)
```

#### Infrastructure Requirements & Estimated Service Costs
| Resource | Recommended Service | Justification | External Prerequisite / Cost |
| :--- | :--- | :--- | :--- |
| **Domain & DNS** | Cloudflare / AWS Route 53 | Custom domain, automated SSL certificate issuance, edge DDoS mitigation. | Domain registration (~$12–$20/year). |
| **Web Frontend** | Vercel / Cloudflare Pages / Cloud Run | Global edge delivery of Next.js static assets and SSR routes. | Free tier to Pro (~$20/mo). |
| **API Backend** | AWS ECS Fargate or Google Cloud Run | Serverless container execution co-located in region with DB (`ap-south-1`). | ~$30–$80/mo based on traffic. |
| **Managed Database** | Supabase Pro or AWS RDS PostgreSQL 17 | High-availability PostgreSQL, automated daily backups, continuous WAL PITR, connection pooler. | Supabase Pro ($25/mo) or AWS RDS (~$45–$90/mo). |
| **Private Object Storage** | AWS S3 or Cloudflare R2 | Replaces ephemeral local disk storage with private, encrypted, scalable object store. | ~$5–$15/mo based on media volume. |
| **Distributed Cache / Bus** | Redis (AWS ElastiCache / Redis Cloud) | Multi-node rate limiting, WebSocket broadcast bus, and revoked session blacklists. | ~$15–$30/mo. |
| **Transactional Email** | SendGrid / Postmark / Resend | Outbound email delivery for trip invitation links and account notices. | Free tier to ~$15/mo. |
| **Mobile App Distribution** | Apple Developer Program & Google Play | App store distribution to Android and iOS users. | Apple: $99/year; Google: $25 one-time. |
| **Error Monitoring** | Sentry | Production crash reporting and performance tracing for API, Web, and Mobile. | Free tier to Developer (~$26/mo). |

---

### 8. Performance and Latency Investigation

During Step 5 stress testing, single-request latencies on heavy intelligence endpoints were observed:
- `/api/trips/{id}/engine/recommend`: **~2,526 ms**
- `/api/trips/{id}/rescue/analyze`: **~2,177 ms**

#### Root Cause Analysis
1. **Network RTT Over Distance:** The staging API ran on a local Windows machine, connecting over the public internet to Supabase PostgreSQL hosted in AWS Mumbai (`ap-south-1`). The average ping latency was **~120 ms** per round-trip.
2. **Sequential Query Multipliers:** The Group Engine and Trip Rescue algorithms perform multiple sequential database lookups (fetching itinerary items, parsing member pulse records, retrieving candidate place attributes, and loading respect notes) to construct the grounded context before evaluating constraints. With 15–20 queries executed sequentially across the wire, network round-trip latency alone accounts for **1,800 ms – 2,400 ms** of total execution time.
3. **Pure Algorithmic Computation:** On local SQLite, the identical Engine scoring algorithms execute in **under 45 ms**.

#### Production Latency Remediations
- **Co-Location:** In production, hosting the FastAPI backend container in the same cloud region and availability zone as the PostgreSQL database (e.g. AWS `ap-south-1`) reduces database round-trip latency from ~120 ms to **< 1.5 ms**. Total Engine response time will drop below **200 ms**.
- **Batch Querying:** Minor optimization to batch place candidate queries into single multi-row `WHERE id IN (...)` queries to minimize round-trips.
- **Connection Pre-Warming:** Session pooler pre-ping eliminates TLS renegotiation overhead.

---

### 9. Environment Configuration Audit

Audit of configuration files ([.env](file:///c:/Users/siddharth/Desktop/SAFAR/.env), [.env.example](file:///c:/Users/siddharth/Desktop/SAFAR/.env.example), [.env.staging](file:///c:/Users/siddharth/Desktop/SAFAR/.env.staging), [.gitignore](file:///c:/Users/siddharth/Desktop/SAFAR/.gitignore)):

- **No Committed Secrets:** Repository git status confirms `.env`, `.env.staging`, `*.db`, `storage/`, `storage_staging/`, and `key.properties` are strictly excluded by `.gitignore`.
- **Production Guard Rails in [config.py](file:///c:/Users/siddharth/Desktop/SAFAR/services/api/app/core/config.py):**
  - Application aborts startup (`RuntimeError`) if `ENVIRONMENT=production` and `SECRET_KEY` is the default development secret or fewer than 32 characters.
  - Application aborts startup if `ENVIRONMENT=production` and wildcard `*` is found in `CORS_ORIGINS`.
  - Application aborts startup if `ENVIRONMENT=production` and `COOKIE_SECURE=false`.
  - Application aborts startup if `ENVIRONMENT=production` and `SAFAR_CREATE_SCHEMA=true`.
  - Application aborts startup if `ENVIRONMENT=production` and `SAFAR_SEED=true`.
- **Honest Provider Defaults:** Link fetching, weather forecasts, and external LLMs are off by default. Zero phantom API calls are made.

---

### 10. Full Regression Matrix

| Layer | Test Suite | Tests Executed | Passed | Failed | Skipped | Status |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **Backend API** | `pytest services/api/tests` (Full suite) | 132 | 132 | 0 | 0 | **100% PASS** |
| **Web Client** | `tsc --noEmit` (TypeScript typecheck) | Clean | Clean | 0 | 0 | **100% PASS** |
| **Web Client** | `vitest run` in `apps/web` | 12 | 12 | 0 | 0 | **100% PASS** |
| **Web Client** | `next build` (Production compilation) | 51 Routes | 51 | 0 | 0 | **100% PASS** |
| **Mobile Flutter** | `flutter analyze` in `apps/mobile` | 0 issues | Clean | 0 | 0 | **100% PASS** |
| **Mobile Flutter** | `flutter test` (Unit, Widget, Usability, Observability) | 61 | 61 | 0 | 0 | **100% PASS** |
| **Database RLS** | `verify_postgres_rls.py` on PostgreSQL 17 | 8 Checks | 8 | 0 | 0 | **100% PASS** |
| **Database Migrations** | `alembic check` / `alembic current` | `e5c8a2b7d940` | Head | 0 | 0 | **100% PASS** |
| **Backup Integrity** | `verify_manifest_integrity()` on staging manifest | 1 Dump File | Valid | 0 | 0 | **100% PASS** |

---

### 11. Release Blocker Classification Matrix

Every finding from this assessment is categorized by severity:
- **CRITICAL:** Must be fixed before any production release.
- **HIGH:** Must be fixed before public launch.
- **MEDIUM:** Should be fixed before general availability.
- **LOW:** Can be scheduled for a later maintenance release.

| Category | Finding Description | Severity | Component | Required Action | Blocks Release? |
| :--- | :--- | :---: | :---: | :--- | :---: |
| **External Account** | Android release artifacts signed with throwaway verification key | **CRITICAL** | Mobile Android | Generate official production keystore; configure `SAFAR_KEYSTORE_PATH` in CI/CD; enroll public cert in Google Play App Signing; build final release AAB. | **YES** |
| **Infrastructure** | Database lacks Point-in-Time Recovery (PITR) and continuous WAL archiving | **CRITICAL** | Database | Enable continuous WAL archiving and automated daily snapshots on production PostgreSQL instance (RPO < 15m, RTO < 1h). | **YES** |
| **Infrastructure** | Missing production database provisioning (staging must not be used for prod) | **CRITICAL** | Database | Provision separate production PostgreSQL instance; run `alembic upgrade head`; create `safar_app` restricted role. | **YES** |
| **Infrastructure** | Cloud production hosting & TLS termination unprovisioned | **CRITICAL** | DevOps | Provision cloud container runtime (ECS / Cloud Run), domain name, CDN, and TLS certificates. | **YES** |
| **External Account** | Missing iOS macOS compilation and device verification | **HIGH** | Mobile iOS | Establish macOS CI build runner, enroll in Apple Developer Program ($99/yr), build release IPA, and test on physical device. | **YES (for iOS release)** |
| **Missing Infrastructure** | Ephemeral local filesystem media storage (`storage/`) | **HIGH** | Backend Media | Migrate storage layer to AWS S3 / Cloudflare R2 with expiring presigned download URLs. | **YES (for multi-node)** |
| **Missing Infrastructure** | Single-node in-memory rate limiting | **HIGH** | Backend API | Connect rate limit middleware to a Redis cluster if scaling beyond a single API instance. | **NO (if single container)** |
| **External Account** | Missing transactional email service for trip invitations | **HIGH** | Product / Auth | Configure transactional email provider (SendGrid / Postmark / Resend) to deliver invitation emails directly. | **NO (link copy works)** |
| **Operational Risk** | Direct database hostname is IPv6-only on AWS | **HIGH** | Database | Use the Supabase IPv4 session pooler (`aws-0-[region].pooler.supabase.com:5432`) in production connection strings. | **YES** |
| **Operational Risk** | Cross-region network latency causes ~2.5s Engine response times | **MEDIUM** | Performance | Co-locate FastAPI backend container in the same cloud region and data center as the PostgreSQL database. | **NO** |
| **Implementation** | No automated background task scheduler for expired token cleanup | **MEDIUM** | Database Maintenance | Configure a daily cron job calling `cleanup_expired_tokens()` to prune expired sessions and companion links. | **NO** |
| **Operational Risk** | In-memory operational metrics reset on API process restart | **MEDIUM** | Observability | Export operational metrics to Prometheus / OpenTelemetry collector for historical dashboards. | **NO** |
| **Future Improvement** | Lack of push notification provider (FCM / APNs) | **LOW** | Mobile | Integrate Firebase Cloud Messaging / APNs for background itinerary updates and voting alerts. | **NO (in-app WS works)** |
| **Future Improvement** | Missing external map tile provider credentials | **LOW** | Mobile / Web | Configure commercial map tile vendor (Mapbox / Stadia / Thunderforest) for customized cartography. | **NO (schematic works)** |

---

### 12. Final Production Readiness Sign-Off Checklist

- [x] **Master Specification (F01–F49):** 100% complete, verified with honest labels and zero mock endpoints.
- [x] **Database Row-Level Security:** 56 tables enabled, 55 forced, 220 policies verified under restricted `safar_app` role.
- [x] **Database Migrations:** Alembic synchronized at head `e5c8a2b7d940`.
- [x] **Backend Regression:** 132/132 tests passing.
- [x] **Web Regression:** 12/12 Vitest tests passing; TypeScript typecheck clean; production build compiled cleanly.
- [x] **Mobile Regression:** 61/61 unit/widget tests passing; Flutter analysis clean.
- [x] **Security Controls:** CSRF, session rotation, theft detection, sensitive data redaction, secure cookies guarded.
- [ ] **Android Production Signing:** Blocked on generating official upload key.
- [ ] **iOS Production Verification:** Blocked on macOS build runner and Apple Developer account.
- [ ] **Cloud Production Infrastructure:** Blocked on provisioning production cloud hosting, S3 object storage, and domain.
- [ ] **Database PITR & DR:** Blocked on provisioning cloud managed PostgreSQL with continuous WAL archiving.

---

### 13. Phase Boundary Confirmation

Phase 13 Step 7 is completely finished. The production readiness assessment is fully documented, all remaining blockers are identified and classified, and regression suites have been validated.

**In strict compliance with instructions:**
- No production deployment has been attempted.
- No APK or AAB has been published.
- No external accounts, infrastructure, or domains have been purchased.
- All healthy background processes (PIDs 50400, 49740, 51932) remain running undisturbed.
- Execution has halted awaiting your explicit review and approval. **Do NOT begin Step 8.**
