# SAFAR — Next Phase Audit (Phase 14, P0)

**Date:** 2026-11-22  
**Repository:** local checkout at `C:\Users\LENOVO\Downloads\SAFAR\SAFAR`  
**Branch / HEAD at review start:** `udbhav` / `d68b25c`  
**Blueprint:** [`SAFAR_NEXT_PHASE_IMPLEMENTATION.md`](../SAFAR_NEXT_PHASE_IMPLEMENTATION.md)  
**Product invariant:** The Engine Recommends, The Group Decides.

## Scope and honesty rules

This document reports what was actually inspected and executed in this checkout.
It does **not** reuse handover claims as proof. In particular:

* **Verified here** means the command was run in this checkout and the result is
  recorded below.
* **Code evidence** means source, routes and tests exist and were inspected, but
  a feature-level end-to-end trace was not independently executed.
* **Not executed here** means the environment lacks credentials, services,
  devices or approval; it is not a claim that the feature is broken.
* No release phase is marked complete: P0 remains partially complete because
  PostgreSQL/RLS, restore-drill and live group-trip traces are blocked here.

The working tree already contained user-owned changes before this work began:
`apps/web/package-lock.json` was modified and
`SAFAR_NEXT_PHASE_IMPLEMENTATION.md` was untracked. Both were preserved.

---

## 1. Executive verdict

| Question | Answer |
|---|---|
| Does the repo contain the three-tier SAFAR application? | Yes: `services/api`, `apps/web`, `apps/mobile`, migrations, docs, Dockerfiles and compose. |
| Was a reproducible local baseline achieved? | **Yes after the P0 fixes below.** Before them, backend/web/mobile checks failed in this checkout for environment and missing-source reasons. |
| Are all F01–F49 surfaces present? | **Documented code/route evidence exists for all 49** in the feature registry and prior audit; this review did not re-inspect every UI file. Automated feature-level evidence was executed for a large subset; the rest remain documented-code-only here. |
| Is SAFAR release-ready? | **No.** Cloud staging, private object storage, PITR restore proof, outbound email, live RLS, production signing and pilot gates are unresolved. |
| Was production/user data touched? | **No.** No deploy, account creation, migration of persistent data, email send or cloud provisioning was performed. |
| Are credentials safe now? | Hardcoded staging credentials were removed from tracked source. They were exposed in repository history and **must be rotated by the owner**. No secret values are reproduced here. |

Previous reports (`docs/PHASE14_STEP1_REPOSITORY_BASELINE.md`,
`docs/SAFAR_RELEASE_HANDOVER.md`, `docs/PHASE13_STEP7_PRODUCTION_READINESS_REPORT.md`)
describe a different machine state: clean tree, running dev/staging daemons,
live Supabase access and a restored backup manifest. None of those conditions
were reproducible at the start of this review.

---

## 2. Repository findings

### 2.1 Layout and deployment surface

* Backend: FastAPI/SQLAlchemy/Alembic under `services/api/`, with 14 pytest
  modules plus standalone verification/drill scripts.
* Web: Next.js App Router under `apps/web/`; a successful build in this checkout
  listed **51 routes**.
* Mobile: Flutter under `apps/mobile/`, with unit/widget tests and live API
  integration tests under `test/integration/`.
* Local deployment references: `docker-compose.yml`, `services/api/Dockerfile`,
  `apps/web/Dockerfile`. No CI workflow manifests
  (`.github`, `.gitlab`, CircleCI, Azure, Terraform or Kubernetes) were found.
* No cloud account, domain, signing identity or provider credential was
  available or used.

### 2.2 Root causes of the unreproducible baseline

1. **Flutter `storage/` source was invisible to Git.** The unanchored
   `.gitignore` rule `storage/` ignored every directory with that name,
   including `apps/mobile/lib/core/storage/`. Call sites and tests imported
   `json_store.dart` and `offline_queue.dart`, but neither file existed in the
   checkout, so `flutter test` failed at compilation.
2. **Web tests assumed a jsdom localStorage implementation.** Node 26 can run
   jsdom without `--localstorage-file`, leaving `window.localStorage` absent;
   Zustand's persist middleware then failed on `setItem`.
3. **Three staging-path tests required a specific developer machine.** They
   asserted a hardcoded backup manifest path and live dev/staging ports, so a
   portable checkout reported product failures for missing environment.
4. **Tracked scripts contained hardcoded staging host/user/password values and
   absolute developer paths.** These made backup/RLS scripts non-portable and
   exposed credentials in source control.
5. **Earlier reports' counts do not match this tree.** The baseline report
   claims 132 backend tests and no skips; the current suite has 132 collected
   tests with 3 environment-dependent skips after the fix. The handover claims
   129 passing backend tests and 71 Flutter analyzer issues were observed here
   before repair.

---

## 3. Commands actually executed

### 3.1 Before fixes (baseline in this checkout)

Commands were run from `services/api`, `apps/web` and `apps/mobile` as
indicated.

| Layer | Command | Workdir | Result |
|---|---|---|---|
| Backend | `python -m pytest tests -q` | `services/api` | **3 failed, 129 passed** (hardcoded staging manifest/ports). |
| Web | `npm test` | `apps/web` | **2 failed, 10 passed** (missing jsdom `localStorage`). |
| Mobile | `flutter analyze` | `apps/mobile` | **71 issues**. |
| Mobile | `flutter test` | `apps/mobile` | Compilation failure: missing `lib/core/storage/json_store.dart` and `offline_queue.dart`. |

Tool versions observed: Python 3.13.12 in `services/api\.venv` (global Python
3.14.3), Node v26.13.1, npm 11.20.0, Flutter 3.41.4, Dart 3.11.1.

### 3.2 After fixes

| Layer | Command | Workdir | Result |
|---|---|---|---|
| Backend | `.\.venv\Scripts\python.exe -m pytest tests -q` | `services/api` | **157 passed, 3 skipped, 1 warning in 23.81s** after the config-hardening work; **136 passed** after the adapter work; **129 passed** after the first P0 fix alone. Twenty-one new config tests and seven new adapter tests were added. |
| Backend syntax | `.\.venv\Scripts\python.exe -m compileall -q scripts tests` | `services/api` | Clean. |
| Web | `npm test` | `apps/web` | **2 files passed, 12 tests passed**. |
| Web | `npm run typecheck` | `apps/web` | Clean after `npm run build` regenerated `.next/types`. |
| Web | `npm run build` | `apps/web` | Production build succeeded; **51 routes**. |
| Mobile | `flutter analyze` | `apps/mobile` | `No issues found!` |
| Mobile | `flutter test` | `apps/mobile` | **61 passed, 12 skipped** (live API suite; no `SAFAR_LIVE_API`). |
| Ignore rules | `git check-ignore -v` on source and runtime media paths | repo root | Flutter storage source is trackable; runtime media paths remain ignored. |

`npm run build` warned that Next.js inferred the workspace root from
`C:\Users\LENOVO\package-lock.json`; the build still succeeded. This is an
environment observation, not a product failure.

### 3.3 Tests and checks deliberately not executed here

| Check | Why not executed | How to execute later |
|---|---|---|
| PostgreSQL/RLS verification | No live managed database or `safar_app` credentials in this environment. | Configure `SAFAR_STAGING_DATABASE_URL` or `SAFAR_STAGING_DB_*` plus `SAFAR_APP_DB_PASSWORD`, then run `services/api/tests/verify_postgres_rls.py`. |
| Full backup/restore drill | No PostgreSQL tools/manifest/credentials; drill provisions and drops a temporary database. | Set `SAFAR_PG_BIN`, `SAFAR_BACKUP_DIR` and DB env vars, then run `services/api/tests/run_full_backup_restore_drill.py` against disposable staging. |
| Three formerly failing staging tests | Now explicit skips: no manifest or `SAFAR_REQUIRE_RUNNING_SERVICES=1`. | Set `SAFAR_BACKUP_DIR` after a real backup; set `SAFAR_REQUIRE_RUNNING_SERVICES=1` on the staging host. |
| Flutter live API suite (12) | Needs `SAFAR_LIVE_API` and a running seeded API. | Start disposable seeded API, set `SAFAR_LIVE_API`, run `flutter test` in `apps/mobile`. |
| Independent end-to-end group-trip trace | Requires real persisted records across three to five accounts on both clients; no seeded services were started. | Follow blueprint §5 against private staging and capture request IDs, screenshots and DB row ids without private field values. |
| Docker image build / cloud deploy | No external approval or credentials. | P14-03 after owner approval. |

---

## 4. First safe task implemented

The first P0 task was chosen as **restore a reproducible baseline and remove
hardcoded staging credentials**. It is self-contained, reversible and does not
touch cloud resources or persistent user data.

### Code added or changed

| File | Change |
|---|---|
| `apps/mobile/lib/core/storage/json_store.dart` | Restored `JsonStore`, `MemoryJsonStore` and `SecureJsonStore` using the existing call-site contract. No logging of key or value contents. |
| `apps/mobile/lib/core/storage/offline_queue.dart` | Restored `OfflineCapture`, `OfflineQueue`, `newClientId`, persistence, status transitions, failed-retry semantics and idempotent `clientId` handling. |
| `apps/web/tests/setup.ts` | Test-only in-memory `Storage` shim for jsdom. Production code unaffected. |
| `apps/web/vitest.config.ts` | Registers `tests/setup.ts` via `setupFiles`. |
| `.gitignore` | Anchored runtime media rules to repo root / `services/api`; added `!apps/mobile/lib/core/storage/` so source is not ignored. |
| `services/api/scripts/backup_staging.py` | Env-based host, port, user, password, app role, backup dir and PostgreSQL tools path; optional `SAFAR_ENV_FILE`; no hardcoded credentials or developer paths. |
| `services/api/tests/verify_postgres_rls.py` | Uses shared `get_db_credentials()`. |
| `services/api/tests/run_full_backup_restore_drill.py` | Uses shared env-based config and repo-relative paths; supports PATH tools. |
| `services/api/tests/download_pgsql_tools.py` | Uses `SAFAR_PG_BIN` or repo-relative tools directory. |
| `services/api/tests/test_phase13_step6_focused_verification.py` | Three environment-dependent checks skip with explicit reasons instead of failing portable runs. No assertion was weakened on configured hosts. |

### Environment variables now required for staging scripts

`SAFAR_PG_BIN`, `SAFAR_BACKUP_DIR`, `SAFAR_ENV_FILE`,
`SAFAR_STAGING_DATABASE_URL` **or** `SAFAR_STAGING_DB_HOST`,
`SAFAR_STAGING_DB_PORT`, `SAFAR_STAGING_DB_USER`,
`SAFAR_STAGING_DB_PASSWORD`, `SAFAR_STAGING_DB_NAME`,
`SAFAR_APP_DB_USER`, `SAFAR_APP_DB_PASSWORD`,
`SAFAR_REQUIRE_RUNNING_SERVICES`. Media additionally uses
`SAFAR_MEDIA_BACKEND` and `SAFAR_STORAGE_DIR`. Values must be supplied by the
owner through a secret store or untracked env file; none are stored in this
document.

### Security caveat

Removing exposed values from the working tree does not undo their presence in
Git history. Treat the previous staging database/application credentials as
compromised, rotate them and review log/tool history. No rotation was attempted
here.

### Follow-up safe task: media storage adapter seam (P14-04 groundwork)

A second self-contained task added a storage abstraction without changing the
public `/media/{trip_id}/{filename}` signed-URL contract or contacting a cloud
provider.

| File | Change |
|---|---|
| `services/api/app/services/media_store.py` | New `MediaStore` contract, strict `MediaKey` validation, `LocalMediaStore` with atomic writes, `InMemoryMediaStore` for tests, and fail-closed `build_media_store()`. |
| `services/api/app/core/config.py` | Adds `SAFAR_MEDIA_BACKEND` (`local` or `memory`) and rejects unknown backends; `memory` is blocked in hosted environments. |
| `services/api/app/routers/memories.py` | Upload now streams through the configured store; size rejection still returns 413 and records metrics. |
| `services/api/app/main.py` | Signed media serving resolves through the store instead of direct path construction. |
| `services/api/app/routers/places.py` | Dream-import OCR media resolution uses the store and retains trip/signature checks. |
| `services/api/app/routers/users.py` | Account erasure deletes stored media through the adapter by canonical URL key. |
| `services/api/app/routers/admin.py` | Operational metrics report the active backend and storage stats from the adapter. |
| `.env.example` | Documents `SAFAR_MEDIA_BACKEND`. |
| `services/api/tests/test_media_store.py` | Seven new tests: traversal/key validation, size limit cleanup, signed URL parsing, memory backend, unknown-backend failure and API write-through. |

Invariants preserved: filenames remain UUID-based, trip ids are 32-hex, no
path separators or traversal segments are accepted, unsigned/tampered URLs are
still rejected, only canonical URLs are persisted, and there is no external
network call. The `memory` backend has no local file path, so serving/OCR
endpoints fail closed for it; it is for tests only.

This is **not** a cloud adapter and no media was migrated. The next P14-04 step
is a private bucket implementation behind the same contract, with member/
outsider/revocation/delete tests and a compatibility rollback.

### Follow-up safe task: hosted configuration fail-closed checks

A third self-contained task tightened startup configuration so staging and
production cannot silently inherit development-safe defaults.

| File | Change |
|---|---|
| `services/api/app/core/config.py` | Hosted environments now require `postgresql+psycopg://`, `COOKIE_SECURE=true`, non-test `TRUSTED_HOSTS`, explicit bare http(s) `CORS_ORIGINS`, and `SAFAR_SEED=false` / `SAFAR_CREATE_SCHEMA=false`. The `memory` media backend is rejected in both staging and production. API docs now default off in staging. |
| `.env.example` | Documents the hosted fail-closed requirements and the staging/production media restriction. |
| `services/api/tests/test_config_hardening.py` | Twenty-one tests covering development defaults, a valid hardened staging config, SQLite rejection, test/emulator hosts, insecure cookies, memory media, seed/schema creation, malformed/wildcard CORS, and an explicit docs opt-in. |

Localhost/127.0.0.1 remain acceptable in `TRUSTED_HOSTS` for in-container
probes, but `testserver`, `10.0.2.2` and `*` are rejected in hosted
environments. No cloud resource was contacted and no existing deployment was
changed. These are startup guards only; they do not prove HTTPS, proxy header
handling or hosted CORS behaviour without a real staging deployment.

---

## 5. F01–F49 feature evidence matrix

Legend:

* **Automated** — a named backend/web/mobile test file covering the feature was
  collected and passed in the after-fix suite recorded above.
* **Partial** — automated evidence covers a key invariant but not the full
  feature or both clients.
* **Static** — code/route/UI and registry evidence exist; no named
  feature-level test was independently executed in this review.
* **E2E** — not executed for **any** row. A passing unit/integration suite is
  not a substitute for the blueprint §5 live group-trip trace.

Code paths are indexed in [`docs/FEATURE_REGISTRY.md`](FEATURE_REGISTRY.md) and
[`docs/PHASE13_STEP7_PRODUCTION_READINESS_REPORT.md`](PHASE13_STEP7_PRODUCTION_READINESS_REPORT.md);
this review cross-checked the test links below against files present in this
checkout. Rows marked **Static** rely on those documents and repository route
evidence, not on a newly executed feature-level test.

| ID | Feature | Evidence status | Code / route evidence | Automated evidence executed here | E2E here |
|---|---|---|---|---|---|
| F01 | Account, Consent & Preferences | Automated | `routers/auth.py`, `routers/users.py`; `/register`, `/login`, `/onboarding`, `/profile`, `/settings` | [`test_api.py`](../services/api/tests/test_api.py), [`test_audit_fixes.py`](../services/api/tests/test_audit_fixes.py) | No |
| F02 | Journey DNA | Automated | `GET/PUT /api/me/dna`; profile/onboarding | [`test_api.py`](../services/api/tests/test_api.py), [`test_audit_fixes.py`](../services/api/tests/test_audit_fixes.py) | No |
| F03 | Destination & Activity Discovery | Partial | `/api/destinations*`, `/api/activities/search`; `/discover` | [`test_api.py`](../services/api/tests/test_api.py), [`test_phase7_evaluation.py`](../services/api/tests/test_phase7_evaluation.py) | No |
| F04 | Trip Creation, Membership & Roles | Automated | `/api/trips*`, invites, members; `/trips/new`, members screen | [`test_api.py`](../services/api/tests/test_api.py), [`test_phase11.py`](../services/api/tests/test_phase11.py), [`phase10_test.dart`](../apps/mobile/test/phase10_test.dart) | No |
| F05 | Collaborative Itinerary & Voting | Automated | itinerary/proposals/votes/versions; `/itinerary`, `/voting` | [`test_api.py`](../services/api/tests/test_api.py), [`test_phase11.py`](../services/api/tests/test_phase11.py) | No |
| F06 | Trip Pulse | Automated | `/api/trips/{id}/pulse`; `/pulse` | [`test_api.py`](../services/api/tests/test_api.py), [`test_audit_fixes.py`](../services/api/tests/test_audit_fixes.py) | No |
| F07 | Group Experience Engine | Automated | `services/engine.py`; `/engine`, `/insights` | [`test_api.py`](../services/api/tests/test_api.py), [`test_audit_fixes.py`](../services/api/tests/test_audit_fixes.py), [`test_phase7_recommendations.py`](../services/api/tests/test_phase7_recommendations.py) | No |
| F08 | Trip Twin | Automated | `routers/twin.py`; `/twin` | [`test_audit_fixes.py`](../services/api/tests/test_audit_fixes.py) | No |
| F09 | Trip Rescue | Automated | `services/rescue.py`; `/rescue` | [`test_audit_fixes.py`](../services/api/tests/test_audit_fixes.py) | No |
| F10 | Maps & Nearby | Partial | `/nearby`, map screen, configurable tiles | [`test_security_hardening.py`](../services/api/tests/test_security_hardening.py), [`phase10_test.dart`](../apps/mobile/test/phase10_test.dart) | No |
| F11 | Shared Memory Timeline | Automated | memory CRUD/media; `/memories` | [`test_api.py`](../services/api/tests/test_api.py), [`test_audit_fixes.py`](../services/api/tests/test_audit_fixes.py), [`test_phase11.py`](../services/api/tests/test_phase11.py) | No |
| F12 | AI Memory Studio / Constellation | Automated | suggest-events/caption/approval; `/memories/studio` | [`test_phase4.py`](../services/api/tests/test_phase4.py) | No |
| F13 | Group Expenses | Automated | expenses/balances/export; `/expenses` | [`test_api.py`](../services/api/tests/test_api.py), [`test_audit_fixes.py`](../services/api/tests/test_audit_fixes.py) | No |
| F14 | Place Pulse | Automated | place reports/helpful/verify; place detail | [`test_api.py`](../services/api/tests/test_api.py), [`test_phase4.py`](../services/api/tests/test_phase4.py) | No |
| F15 | Serendipity Radar | Static | `/api/serendipity/*`; `/connections` | Registry records browser checks; no named test found in this checkout | No |
| F16 | Travel Circles & Local Contributors | Automated | `/api/circles*`, `/api/contributors*`; `/circles` | [`test_api.py`](../services/api/tests/test_api.py) | No |
| F17 | Dream-to-Destination Import | Automated | `/inspirations`, links/OCR adapters, review gate | [`test_phase7_dream_import.py`](../services/api/tests/test_phase7_dream_import.py), [`test_stabilisation.py`](../services/api/tests/test_stabilisation.py) | No |
| F18 | Journey Replay & Travel Book | Automated | `/replay`, travel-book export | [`test_api.py`](../services/api/tests/test_api.py), [`test_audit_fixes.py`](../services/api/tests/test_audit_fixes.py) | No |
| F19 | Travel Missions & Wildcards | Static | `/missions*`; `/missions` | Registry records browser checks; no named test found | No |
| F20 | Offline-First Capture & Sync | Automated | `/sync`, snapshot, queue, service worker; `/offline` | [`test_api.py`](../services/api/tests/test_api.py), [`phase13_step5_offline_sync_test.dart`](../apps/mobile/test/integration/phase13_step5_offline_sync_test.dart) | No |
| F21 | Predictive Crowd Forecasting | Automated | `services/places.py` `crowd_forecast`; place detail | [`test_phase7_forecasting.py`](../services/api/tests/test_phase7_forecasting.py), [`test_phase4.py`](../services/api/tests/test_phase4.py) | No |
| F22 | Multilingual Travel Conversation | Automated | `/api/assistant/*`; `/assistant` | [`test_phase7_multilingual.py`](../services/api/tests/test_phase7_multilingual.py), [`test_phase7_evaluation.py`](../services/api/tests/test_phase7_evaluation.py) | No |
| F23 | Journey Pact | Automated | `GET/PUT /pact`; `/pact` | [`test_api.py`](../services/api/tests/test_api.py) | No |
| F24 | Opportunity Clock | Automated | `services/opportunity.py`; `/opportunity` | [`test_stabilisation.py`](../services/api/tests/test_stabilisation.py) | No |
| F25 | Shadowplan | Static | `/shadowplans`; `/insights` | Registry records browser checks; no named test found | No |
| F26 | One-Link Companion | Automated | `services/companion.py`; `/companion`, public token route | [`test_stabilisation.py`](../services/api/tests/test_stabilisation.py) | No |
| F27 | Planner Load Balancer | Automated | `/tasks/summary`; `/tasks` | [`test_phase4.py`](../services/api/tests/test_phase4.py) | No |
| F28 | Branch & Rejoin | Static | `/branches`; `/branches` | Registry records browser checks; no named test found | No |
| F29 | Journey Effort Budget | Static | `/effort`, `services/optimizer.py`; `/insights` | Registry records browser checks; no named test found | No |
| F30 | Decision Evidence Passport | Automated | place detail + assistant citations | [`test_api.py`](../services/api/tests/test_api.py) | No |
| F31 | Ask the Ground | Automated | `/ground-requests*`; `/ground` | [`test_api.py`](../services/api/tests/test_api.py) | No |
| F32 | Cost-Shock Guard | Partial | proposal `cost_impact`; `/voting` | Budget privacy/gating in [`test_api.py`](../services/api/tests/test_api.py) and [`test_audit_fixes.py`](../services/api/tests/test_audit_fixes.py) | No |
| F33 | Outcome Calibrator | Automated | feedback services; place detail/engine | [`test_api.py`](../services/api/tests/test_api.py), [`test_phase7_recommendations.py`](../services/api/tests/test_phase7_recommendations.py) | No |
| F34 | Journey Capsule | Static | `/capsules`; `/insights` | Registry records UI checks; no named test found | No |
| F35 | Constraint Compass | Automated | `PUT /pulse`; `/pulse` | [`test_audit_fixes.py`](../services/api/tests/test_audit_fixes.py) | No |
| F36 | One Question That Matters | Automated | engine `clarifying_question`; `/engine` | [`test_phase4.py`](../services/api/tests/test_phase4.py) | No |
| F37 | Journey Fragility Radar | Static | `/fragility`; `/insights` | Registry records browser checks; no named test found | No |
| F38 | Domino Map | Static | `/domino`; `/insights` | Registry records browser checks; no named test found | No |
| F39 | Protected Wander Window | Automated | `is_protected`, `services/schedule.py`; itinerary/engine/rescue | [`test_phase4.py`](../services/api/tests/test_phase4.py) | No |
| F40 | Expectation Reality Check | Static | `/places/{id}/expectation`; place detail | Registry records browser checks; no named test found | No |
| F41 | Door-to-Door Access Chain | Automated | `access_chain` in place detail | [`test_api.py`](../services/api/tests/test_api.py) | No |
| F42 | Discovery Balance Lens | Static | search `lens`; `/discover/[id]` | Registry records browser checks; no named test found | No |
| F43 | Graceful Independent Time | Automated | attendance endpoint; `/itinerary` | [`test_audit_fixes.py`](../services/api/tests/test_audit_fixes.py) | No |
| F44 | Material Change Watch | Static | `/material-watch*`; `/watch` | Registry records browser checks; no named test found | No |
| F45 | Fair Trade Negotiator | Automated | `/negotiate`; `/twin` | [`test_phase4.py`](../services/api/tests/test_phase4.py) | No |
| F46 | Local Context Requests | Automated | `/ground`; shared F31 infrastructure | [`test_api.py`](../services/api/tests/test_api.py) | No |
| F47 | Journey Thread | Static | `/api/me/thread`; `/thread` | Registry records browser checks; no named test found | No |
| F48 | Neighborhood Respect Filter | Automated | respect guidance in engine/place detail | [`test_phase4.py`](../services/api/tests/test_phase4.py) | No |
| F49 | Decision Load Governor | Automated | `/next-action`, quiet mode; dashboard | [`test_audit_fixes.py`](../services/api/tests/test_audit_fixes.py) | No |

**Matrix conclusion:** all 49 features have documented code/UI/API evidence.
Automated feature-level evidence was executed here for 34 rows, partial
automated evidence for 3 rows, and documented-code-only evidence remains for 12
rows. No row has an independent live end-to-end trace in this review.

---

## 6. Security and release-readiness gaps

See [`docs/RELEASE_READINESS.md`](RELEASE_READINESS.md) for owners and gates.
Current blockers:

1. **Credentials exposed in history** — rotate the former staging DB/application
   passwords; no secret values are repeated here.
2. **RLS not re-verified here** — earlier 56-table/220-policy claims are
   historical; rerun `verify_postgres_rls.py` against a disposable managed
   database under the non-owner role.
3. **Restore drill not re-executed here** — logical backup code is portable
   now, but PITR and a timed restore are still external prerequisites.
4. **Local filesystem media** — signed URLs and a storage adapter seam are
   implemented, but the active backend is still local; multi-node or public
   deployment requires a private bucket adapter with revocation testing.
5. **No outbound invitation email** — share links remain the fallback; SPF,
   DKIM, DMARC and abuse controls require a chosen provider.
6. **In-process limits/WebSockets** — acceptable for a one-node pilot only;
   multi-instance needs shared limits/pub-sub and reconnect/resync proof.
7. **Mobile artifacts** — existing release artifacts use a throwaway key;
   Android Play signing and iOS TestFlight remain unbuilt here.
8. **Monitoring** — structured logs/metrics/admin endpoint exist in code and
   tests, but no hosted dashboards, alerts or retention policy were provisioned.

---

## 7. Ordered implementation plan (P1/P2)

All items are incremental and reversible. Use the existing FastAPI, Next.js,
Flutter, Docker, Alembic and `/api/health` + `/api/ready` abstractions; do not
rewrite the application.

1. **P14-03 — Managed private staging (first external step).** Choose one
   provider and region; provision isolated DB, secret store, private media
   bucket, API/web containers, HTTPS domains, staging-only IAM, CI build/test/
   migration job, health/readiness probes and rollback tag. Acceptance:
   reproducible deploy from a clean runner, exact CORS/CSRF/cookie checks, and
   a documented rollback. Requires owner-approved cloud account and domains.
2. **P14-05 — Database recovery.** Enable managed automated backups and PITR,
   configure retention from secrets, then execute a timed restore of a
   disposable clone and verify row counts, policies and tenant isolation.
   Acceptance: measured RPO/RTO; if targets are not met, report actual values.
3. **P14-04 — Private object storage adapter.** The interface and local/
   in-memory implementations are already in place. Next: implement a private
   bucket backend behind a flag, keep local reads during verification, then cut
   over after member/outsider/revocation/delete tests pass. Acceptance: no
   public objects, expiring URLs, TTL review for sensitive media, and a
   compatibility rollback.
4. **P14-06 — Outbound invitation email.** Provider-neutral sender behind a
   flag; authenticated domain with SPF/DKIM/DMARC, expiry, per-recipient rate
   limit, bounded logs, and no private trip/member data in the message. Keep
   link and share-sheet fallback. Acceptance: deliverability report and abuse
   test; no email sent without explicit owner approval.
5. **P14-07 — Observability and security.** Ship structured logs to the chosen
   sink; add dashboards/alerts for 5xx, auth failures, refresh reuse, CSRF,
   slow queries, sync conflicts and readiness failures. Re-run auth/RLS/media
   regressions after every infra change. Acceptance: alert routing tested and
   no token/private-field leakage in logs.
6. **P14-08 — Multi-node readiness (conditional).** Only if scaling beyond one
   instance: shared rate limits/pub-sub, sticky-free WebSocket reconnect and
   resync, then failure-injection tests. Do not pay for Redis before staging
   traffic justifies it.
7. **P15-01/P15-02 — Grounded route/place/weather adapters.** Provider-neutral
   contracts with mode, source and freshness; routed durations replace
   straight-line defaults only when available; all fallbacks labelled
   `ESTIMATED` or `unknown`. Add offline/error/stale tests.
8. **P16-01/P16-03 — Decision workspace and offline resilience.** Unify
   pulse → choices → vote → approval without auto-apply; add duplicate/restart/
   conflict tests for the restored `OfflineQueue`.
9. **P18-01 — Seven-day controlled pilot.** Three to five consenting groups,
   static-chat baseline, severe-blocker checklist, fairness/feasibility
   metrics and signed release decision. No public launch before gates pass.

**Recommended commits after owner review (in order):**

1. `fix(P0): restore reproducible baseline and remove hardcoded staging credentials`
   — P0 files listed in §4, both new audit documents, excluding the pre-existing
   `package-lock.json` change unless the owner explicitly wants it included.
2. `feat(storage): add private media store adapter seam`
   — the adapter/config/router/admin changes and `test_media_store.py` listed in
   the follow-up subsection of §4.
3. `hardening: fail closed on hosted configuration defaults`
   — the `config.py` / `.env.example` checks and `test_config_hardening.py`
   listed in the hosted-configuration subsection of §4.

No cloud manifest, deployment action or persistent data migration is included
in any of these commits.

---

## 8. What is not claimed

No claim is made here that the following were verified in this environment:
live Flutter API connectivity, PostgreSQL/RLS enforcement, backup restore or
PITR, cloud deployment, HTTPS domain/CORS/CSRF behaviour on a hosted origin,
email delivery, object-storage authorization, production Android/iOS signing,
or an independent end-to-end group-trip trace. Their prerequisites and owners
are recorded in [`RELEASE_READINESS.md`](RELEASE_READINESS.md).
