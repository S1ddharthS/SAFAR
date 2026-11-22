# SAFAR — Phase 13, Step 5 Acceptance Report
## Usability, Edge-Case & Reliability Stress Testing

**Date:** 2026-11-21  
**Environment:** Isolated Local Staging (`.env.staging`)  
**Staging API Endpoint:** `http://127.0.0.1:8020`  
**Staging Web Endpoint:** `http://localhost:3020`  
**Database:** Dedicated Supabase PostgreSQL 17 (role `safar_app`, NOSUPERUSER, NOBYPASSRLS, PostGIS, TLS)  
**Media Storage:** Isolated private directory `services/api/storage_staging/`  
**Phase Status:** **STEP 5 COMPLETE — AWAITING USER APPROVAL TO PROCEED**

---

### Executive Summary

In Phase 13 Step 5, SAFAR underwent comprehensive usability, edge-case, concurrency, and reliability stress testing. All backend and integration evaluations were conducted against the live staging environment on port `8020` backed by Supabase PostgreSQL 17 under the non-privileged `safar_app` role with PostgreSQL Row-Level Security active across 56 tables (55 forced, 220 policies).

Automated stress suites validated concurrent multi-user editing and race conditions, network failures and recovery, offline queue persistence and idempotent synchronization, security edge cases (HMAC-signed media links, MIME spoofing, oversized uploads, CSRF, session rotation), responsive mobile viewports (compact screens, landscape orientation, 200% text scale, keyboard bottom insets), and protected-time invariance under Trip Rescue.

---

### 1. Test Execution & Scenario Results

#### 1.1 Network Failure & Resilience Testing
- **Suite:** [apps/mobile/test/integration/phase13_step5_network_stress_test.dart](file:///c:/Users/siddharth/Desktop/SAFAR/apps/mobile/test/integration/phase13_step5_network_stress_test.dart)
- **Scenarios Evaluated:**
  - *Normal Connectivity:* Successful authentication and session token issuance.
  - *Unreachable API / Connection Loss:* Simulated connection drop to an unbound port (`59999`); verified structured `ApiException` is thrown with human-readable error (`"Could not reach SAFAR. Check the API address and your network."`), producing zero application crashes.
  - *Temporary Connection Drop & Recovery:* Simulated offline failure followed by restoration to live endpoint `8020`; verified clean retry and transparent recovery without stale session corruption.
  - *Tampered/Expired Session:* Simulated corrupted access token; verified clean `401 Unauthorized` handling without unhandled runtime exceptions.
- **Result:** **3/3 Passed (0s, Clean)**

#### 1.2 Offline Capture & Synchronisation
- **Suite:** [apps/mobile/test/integration/phase13_step5_offline_sync_test.dart](file:///c:/Users/siddharth/Desktop/SAFAR/apps/mobile/test/integration/phase13_step5_offline_sync_test.dart)
- **Scenarios Evaluated:**
  - *Offline Capture While Disconnected:* Multiple offline captures created with client-generated IDs (`m<microseconds><salt>`) and stored in secure device storage (`JsonStore`).
  - *App Restart Before Sync:* Complete re-instantiation of `OfflineQueue` from persistent storage; confirmed queued captures survived restart intact.
  - *Sync against Staging API (`POST /api/trips/{trip_id}/sync`):* Both captures applied and recorded in PostgreSQL `offline_sync_queue` and `trip_memories` tables (`applied: 2, skipped: 0, rejected: 0`).
  - *Idempotency on Retry:* Re-submitting the exact same client ID and payload returned `skipped: 1, applied: 0`, confirming zero duplicate records inserted.
  - *Conflicting Update Detection:* Submitting a previously used client ID with modified payload content resulted in immediate server rejection (`"Client id reused with different content"`).
- **Result:** **1/1 Passed (4s, Clean)**

#### 1.3 Concurrent Collaboration & Race Conditions
- **Suite:** [services/api/tests/verify_phase13_step5_stress.py](file:///c:/Users/siddharth/Desktop/SAFAR/services/api/tests/verify_phase13_step5_stress.py) (Section 1)
- **Scenarios Evaluated:**
  - *Concurrent Itinerary Item Creation:* Mira and Jonas concurrently posted items using `asyncio.gather`; both items persisted cleanly without ID collision or row lock deadlocks.
  - *Concurrent Voting:* Aiko and Leo voted simultaneously on a proposal; both votes registered cleanly in the votes ledger.
  - *Concurrent Expense Logging:* Mira (€60) and Leo (€120) submitted expenses concurrently; ledger totaled exactly €180.0, and 3 pairwise debt settlement transfers reconciled cleanly.
  - *Approval / Vote Race Condition:* Owner approved a proposal while another member attempted a concurrent vote; the proposal status transitioned to `"approved"`, and subsequent vote attempts were rejected with `409 Conflict` (`"This proposal is no longer open"`).
  - *Member Removal During Active Session:* Trip owner removed Leo from membership; Leo's subsequent write request with active token was rejected with `404 Not Found`. Leo was then re-invited and restored.
- **Result:** **100% Passed**

#### 1.4 Repeated & Interrupted Actions
- **Suite:** [services/api/tests/verify_phase13_step5_stress.py](file:///c:/Users/siddharth/Desktop/SAFAR/services/api/tests/verify_phase13_step5_stress.py) (Section 2)
- **Scenarios Evaluated:**
  - *Invitation Token Replay:* Re-accepting a single-use invitation token returned `409 Conflict`.
  - *Repeated Proposal Approval:* Attempting to re-approve an approved proposal returned `409 Conflict`.
  - *Double-Tapping Submissions:* Rapid concurrent expense submissions generated distinct UUIDs, avoiding silent overwrites.
  - *Refresh Token Rotation & Replay Attack:* Using a refresh token issued a new refresh cookie and invalidated the old one; attempting to replay the old refresh cookie was rejected with `401 Unauthorized`.
  - *Post-Logout Action:* Actions attempted after calling `/api/auth/logout` returned `401 Unauthorized`.
- **Result:** **100% Passed**

#### 1.5 Privacy & Security Edge Cases
- **Suite:** [services/api/tests/verify_phase13_step5_stress.py](file:///c:/Users/siddharth/Desktop/SAFAR/services/api/tests/verify_phase13_step5_stress.py) (Section 3)
- **Scenarios Evaluated:**
  - *Expired / Non-Existent Invitations:* Returned `404`/`410`.
  - *Private Memory Isolation:* Mira's private memory (`visibility: private`) was strictly excluded from member Aiko's timeline query (`days[].memories[]`) and returned `404 Not Found` to external contributor Noor.
  - *Cross-User Modification:* Leo attempting to modify Mira's private memory was rejected with `404 Not Found`.
  - *HMAC-Signed Media Links:* Valid media URLs served with 200; tampered signatures or bare unsigned URLs returned `403 Forbidden` (`"Media link is missing or expired"`).
  - *MIME Spoofing Rejection:* File declaring `image/png` but containing plain text headers was rejected with `415 Unsupported Media Type` (`"The uploaded file does not match its declared media type."`).
  - *Oversized File Upload:* Upload exceeding `MAX_UPLOAD_BYTES` (25MB) was rejected with `413 Payload Too Large`.
  - *Location Consent Withdrawal:* `PATCH /api/users/me/profile` with `location_sharing: false` persisted cleanly.
  - *CSRF Protection:* State-changing requests (`POST /api/trips/{id}/expenses`) with cookie authentication but missing/invalid `X-CSRF-Token` header were rejected with `403 Forbidden`.
- **Result:** **100% Passed**

#### 1.6 Mobile Usability & Responsive Layout
- **Suite:** [apps/mobile/test/phase13_step5_usability_test.dart](file:///c:/Users/siddharth/Desktop/SAFAR/apps/mobile/test/phase13_step5_usability_test.dart)
- **Scenarios Evaluated:**
  - *Compact Viewport (320x568 / iPhone SE):* `TripOverviewScreen` rendered with zero visual overflows.
  - *Extreme Accessibility Text Scaling (200% Scale):* `ItineraryScreen` scaled with `TextScaler.linear(2.0)`; titles wrapped cleanly, and lock icons remained visible with zero layout overflows.
  - *Landscape Orientation (800x400):* `ExpensesScreen` rendered and scrolled smoothly without overflows.
  - *Keyboard Insets (300px Bottom ViewInsets):* Form and preference fields on `SettingsScreen` remained scrollable and accessible.
  - *Extreme Text Lengths:* 100+ character trip titles and long destination names wrapped cleanly.
- **Result:** **5/5 Passed (3s, Clean)**

#### 1.7 Trip Rescue & Protected-Time Edge Cases
- **Suite:** [services/api/tests/verify_phase13_step5_stress.py](file:///c:/Users/siddharth/Desktop/SAFAR/services/api/tests/verify_phase13_step5_stress.py) (Section 4)
- **Scenarios Evaluated:**
  - *Protected-Time Invariance:* Scheduled a protected morning walk (`08:00` - `10:30`, `is_protected: true`). Disruption analysis (`POST /api/trips/{id}/rescue/analyze` with `kind: rain`, `closure`, `fatigue`, `budget`, `time`) verified that protected time is placed in `"protected"`, excluded from `"affected"`, and never replaced.
  - *Direct Replacement Rejection:* Direct proposal to replace a protected item (`POST /api/trips/{id}/rescue/propose`) was rejected with `409 Conflict` (`'"{item.title}" is protected time and cannot be replaced by Trip Rescue.'`).
  - *Non-Mutating Inspection:* Verified confirmed itinerary in PostgreSQL was 100% untouched after rescue evaluations.
  - *Approval Disclosure:* Confirmed explicit disclosure: *"Nothing has been changed. This is a proposed repair. The group must approve it before the confirmed itinerary changes."*
- **Result:** **100% Passed**

---

### 2. Bugs Discovered & Fixes Applied During Step 5

| Bug / Failure | Component | Root Cause | Fix Applied | Retest Result |
| :--- | :--- | :--- | :--- | :---: |
| **`SkeletonList` 4px Landscape Overflow** | Flutter Widgets | `SkeletonList` in `safar_widgets.dart` used an unscrollable `Column` with 3 cards totaling 324px height, which exceeded the 320px viewport in 400px-tall landscape mode by 4.0 pixels. | Wrapped `Column` in a `SingleChildScrollView(physics: NeverScrollableScrollPhysics())` in [safar_widgets.dart](file:///c:/Users/siddharth/Desktop/SAFAR/apps/mobile/lib/core/widgets/safar_widgets.dart#L593). | **PASS** (Zero overflows across landscape and small viewports) |
| **Proposal Query Default Filtering** | Backend API Test | In `verify_phase13_step5_stress.py`, `GET /proposals` omitted status parameter, defaulting to `open`. Approved proposals were filtered out. | Added `?status=all` to query all proposal states. | **PASS** (Approved status validated cleanly) |
| **Profile Endpoint Path** | Backend API Test | Location consent toggle targeted `/api/users/me` instead of `/api/users/me/profile`. | Updated target endpoint to `/api/users/me/profile`. | **PASS** (Consent persisted and verified) |
| **CSRF Cookie Name** | Backend API Test | CSRF test referenced `safar_session` instead of `safar_access`. | Updated to set `safar_access` cookie. | **PASS** (`403 Forbidden` returned on missing CSRF token) |
| **Trip Rescue Endpoint Schema** | Backend API Test | Rescue test called `GET /rescue` instead of `POST /rescue/analyze`. | Updated to `POST /rescue/analyze` with `RescueIn` schema. | **PASS** (Rescue analysis and 409 protected rejection verified) |

---

### 3. Performance & Reliability Measurements

Measured on the live staging API on port `8020` connected to Supabase PostgreSQL 17:

| Endpoint & Workflow | Method | Measured Response Time | Assessment |
| :--- | :---: | :---: | :--- |
| `/api/health` | `GET` | **129.2 ms** | Healthy (<200ms) |
| `/api/auth/login` | `POST` | **329.9 ms** | Normal PBKDF2 hash verification |
| `/api/trips/{id}` | `GET` | **603.8 ms** | Normal query over SSL |
| `/api/trips/{id}/itinerary` | `GET` | **655.6 ms** | Multi-table join with RLS context |
| `/api/trips/{id}/engine/recommend` | `POST` | **2526.7 ms** | Heavy scoring & fairness calculations |
| `/api/trips/{id}/expenses` | `POST` | **983.8 ms** | Ledger insert + participant weighting |
| `/api/trips/{id}/expenses/balances` | `GET` | **721.4 ms** | Graph-based debt minimization |
| `/api/trips/{id}/rescue/analyze` | `POST` | **2177.6 ms** | Disruption filtering + alternative search |
| **WebSocket Ticket & Connect** | `POST` + `WS` | **Clean handshake** | Verified ticket issuance, `connected` event, `ping`/`pong` exchange, and reconnect. |

---

### 4. Full Regression Verification Matrix

| Component | Test Suite / Command | Total Tests | Passed | Failed | Status |
| :--- | :--- | :---: | :---: | :---: | :---: |
| **Backend API** | `pytest` in `services/api` | 112 | 112 | 0 | **100% PASS** |
| **Frontend Web** | `npm run typecheck` & `vitest` in `apps/web` | 12 | 12 | 0 | **100% PASS** |
| **Mobile Flutter** | `flutter analyze` in `apps/mobile` | 0 issues | Clean | 0 | **100% PASS** |
| **Mobile Flutter** | `flutter test` (Unit, Widget, Usability, Network, Sync, Live API) | 66 | 66 | 0 | **100% PASS** |
| **Staging Stress** | `verify_phase13_step5_stress.py` | 15 Scenarios | 15 | 0 | **100% PASS** |

---

### 5. Scope Limitations & Strict Boundaries

- **Testing Methodology:** All stress scenarios were executed through automated integration scripts, Flutter unit/widget harnesses, and live HTTP/WebSocket requests. Physical device testing and human pilot participation have **not** yet been conducted.
- **Staging Isolation:** The staging environment remains strictly bound to localhost (`127.0.0.1:8020` and `localhost:3020`). No external connections, domains, or real user emails were contacted.
- **Phase Boundary:** Phase 13 Step 5 is complete. Execution has halted, and **Phase 13 Step 6 (Final Staging Audit & Pilot Rollout Readiness) will NOT proceed without explicit user approval.**
