# SAFAR — Security & Production Hardening Report

Date: 2026-11-19
Phase: 5 — Production Security & Infrastructure Hardening
Scope: authentication and sessions, API authorization, database isolation,
privacy/user control, secrets, uploads, logging, retention, backup/recovery and
PostgreSQL production readiness.

Method: source inspection, automated regression tests, direct SQL probes
against PostgreSQL with row-level security enforced, a backup/restore drill and
browser verification of the production build. **This is not an external
penetration test and not a production certificate.** Where evidence was not
obtained it is stated in §7 and §8 rather than implied.

Evidence baseline:

| Item | Result |
|---|---|
| Backend tests | **68 passed on SQLite** (19.71 s) and **68 passed on a fresh PostgreSQL 16.4 database** as the non-owner `safar_app` role with `FORCE ROW LEVEL SECURITY` (18.59 s) |
| New security tests | 19 in `services/api/tests/test_security_hardening.py` (Appendix A) |
| Frontend | `vitest` 12 passed · `tsc --noEmit` clean · `next build` clean |
| Database | 55 model tables (56 relations incl. `alembic_version`), 220 RLS policies, 35 `safar_*` helper functions, ENABLE + FORCE RLS on all 55 domain tables |
| Backup/restore | `pg_dump -Fc` 358,169 bytes → `pg_restore` into a new database; identical schema, policies and row counts (§6) |
| Browser | login → dashboard → trip page → sign-out; only the CSRF cookie is JS-readable; post-logout `/api/auth/me` and `/api/auth/refresh` return 401 (§4) |
| Docker | **not executed**: the Docker CLI is not installed on this machine. Compose/Dockerfiles were reviewed but not built (§7) |

---

## 1. What changed, in one view

| Area | Before Phase 5 | Now |
|---|---|---|
| Session tokens | JWT held in `localStorage`; logout only cleared the browser; no server-side revocation | Access token in memory + HttpOnly `safar_access` cookie (15 min); opaque refresh token in HttpOnly `safar_refresh` cookie (30 days, path `/api/auth`); server-side `auth_sessions` with rotation, reuse detection and revocation |
| CSRF | Bearer-token model had no CSRF concept | Double-submit `safar_csrf` cookie + `X-CSRF-Token`, constant-time compare, enforced for every cookie-authenticated unsafe request |
| Database isolation | Application-layer checks only; one missing filter = cross-trip leak | PostgreSQL RLS on all 55 domain tables, `FORCE`, fail-closed by default, policies driven by transaction-local `app.*` GUCs; application checks remain as the primary layer |
| Uploads | Declared `Content-Type` trusted | Magic-byte sniffing (PNG/JPEG/WebP/GIF + PDF where allowed); spoofed image → 415 |
| Request size | Unbounded | 25 MB ceiling (`MAX_REQUEST_BYTES`), checked before parsing |
| Rate limits | One global bucket | Per-(client, bucket) sliding windows: auth 10/min, companion responses 20/min, uploads 30/min, default 240/min; `Retry-After`; health/ready exempt; tracked-client cap |
| Logs | Unstructured; uvicorn access log printed raw URLs | JSON logs with `X-Request-Id`, method/path/status/duration, keyed-hashed client IP, redacted `/api/companion/<token>`, `/api/invitations/<token>`, `/media/<path>`; uvicorn access log disabled |
| Health | One endpoint exposing internals | `/api/health` returns status only; `/api/ready` checks the database and returns 503 when unavailable |
| Deletion | Anonymised the account but kept personal learning rows, pulse answers, memory text/media and private budgets | Erases personal data, deletes own media files, clears private values, revokes sessions/links, keeps shared trip history anonymised |
| Retention | None | Job + CLI for expired sessions/invitations/links, old notifications, synced offline entries and audit logs |
| Production config | Defaults were development-friendly | `SECRET_KEY` length guard, CORS wildcard rejected, `SameSite=None` requires `Secure`, API docs off, seeded demo data off, explicit trusted hosts |
| Monitoring & Observability | Minimal ad-hoc print logging | Structured JSON logs across `safar.access`, `safar.error`, `safar.auth`, `safar.security`, `safar.db`, `safar.alert`, `safar.sync`, `safar.media`, `safar.ws`; sensitive data and query parameters redacted; in-memory thread-safe metrics collector (`MetricsCollector`); administrative `/api/admin/metrics` secured via `require_admin`; automated cooldown alerting abstraction; non-destructive `pg_dump -Fc` and `pg_restore` drill with manifest tracking |

---

## 2. Vulnerabilities identified and fixes applied

Severity reflects impact if left unresolved in a public deployment. All items
were found by inspection or by tests written during this phase; none were
externally reported.

| ID | Severity | Finding | Fix | Evidence |
|---|---|---|---|---|
| V1 | **High** | Access and refresh credentials were persisted in `localStorage`. Any XSS could exfiltrate a long-lived token, and there was no way to revoke it. | Cookie sessions (§4) with HttpOnly refresh, rotation, reuse detection, server-side session check on every request, logout revocation. Frontend keeps only in-memory access/CSRF values. | `test_refresh_rotation_rejects_a_replayed_token`, `test_logout_revokes_the_session_for_existing_tokens`, browser §4 |
| V2 | **High** | No database-level tenant isolation. Every private read depended on the query author remembering the membership filter. | RLS on 55 tables, 220 policies, `FORCE ROW LEVEL SECURITY`, fail-closed with no context, non-owner app role. | §3, direct SQL probes; full suite on PG under RLS |
| V3 | Medium | Media upload trusted the client `Content-Type`, so an HTML/script payload could be stored and later served. | Sniff magic bytes; reject mismatches with 415. | `test_media_upload_rejects_a_spoofed_content_type` |
| V4 | Medium | No request-body ceiling; large JSON/multipart bodies could exhaust memory. | ASGI body-size limiter (25 MB default) rejecting with 413 before validation. | `test_oversized_body_is_rejected_before_validation` |
| V5 | Medium | Unstructured logs and uvicorn's access log recorded raw URL paths. Companion and invitation tokens are credentials in the path, so they could leak into log storage. | JSON logger, path-segment redaction, hashed client IP, uvicorn access log disabled. | `app/core/logging.py`, `test_responses_carry_security_headers_and_request_id` |
| V6 | Medium | Health endpoint exposed internal detail and there was no readiness distinction for orchestrators. | `/api/health` returns status/version/engine flags only; `/api/ready` performs `SELECT 1` and returns 503 when the database is unavailable. | `test_health_and_ready_do_not_leak_internals`; live 8010 `/api/ready` 200 |
| V7 | Medium | Migrating to cookies would have introduced CSRF on state-changing requests. | Double-submit token with `hmac.compare_digest`; cookie-auth writes without a matching header return 403. Bearer clients are unaffected. | `test_cookie_sessions_require_csrf_for_writes`; browser login |
| V8 | Medium | `GET /api/trips/{id}/nearby` accepted caller-supplied `lat`/`lon` without checking the location-sharing consent, letting a user repurpose the endpoint with precise coordinates while the privacy toggle was off. | Caller coordinates now require `profile.location_sharing`; otherwise 403. Trip base coordinates remain usable without exposing member locations. | `test_precise_location_requires_the_privacy_toggle` |
| V9 | Medium | Account deletion left personal learning data (`journey_dna`, feedback, pulse answers), memory text/location and uploaded files, and private budgets on trip memberships. | Deletion erases those rows, unlinks own media files, nulls memory text/caption/location, anonymises memberships and revokes sessions and pending links. | `test_account_deletion_erases_personal_data` |
| V10 | Low | Expired sessions, unaccepted invitations, revoked companion links, old notifications, synced offline entries and audit logs accumulated indefinitely. | `services/api/app/services/retention.py` + `scripts/retention.py`; windows configurable via `RETENTION_*`. | `test_retention_removes_only_expired_rows` |
| V11 | Low | No security headers, no trusted-host enforcement, API docs exposed, production CORS could be `*`. | CSP, `X-Content-Type-Options`, `X-Frame-Options`, Referrer-Policy, Permissions-Policy, COOP/CORP, HSTS behind HTTPS, `no-store` on API/media, TrustedHost, docs off in production, `*` rejected. | `test_responses_carry_security_headers_and_request_id`, `test_unknown_host_header_is_rejected` |
| V12 | Low | Seeded consent records used non-canonical kinds, so consent state did not match what the product exposes. | Seed writes the canonical five kinds with explicit grants. | `app/seed.py` (inspection) |
| V13 | Low | Auth, companion and upload endpoints had no dedicated budgets. | Per-bucket limits with `Retry-After`. | `test_rate_limiter_buckets_and_retry_after` |

### Checks that found no vulnerability

| Check | Result |
|---|---|
| SQL injection | Quote/`OR 1=1`/`UNION`/`DROP` probes against query and login paths returned normal empty results or 401/422, never 500. Queries use SQLAlchemy expression/bound parameters. |
| IDOR on private trips | Cross-user trip, expenses, itinerary and memories all return 404 (existence is not disclosed). | `test_cross_user_trip_access_is_hidden` |
| Mass assignment | Registration ignores `is_admin`, `role` and caller-supplied `id`. | `test_registration_ignores_privilege_fields` |
| Error leakage | Error bodies contain only `detail` (+ request id); no stack traces or SQL. | `test_error_bodies_do_not_leak_internals` |
| Anonymous scope | With no credentials: `/api/trips`, `/api/users/me`, `/api/admin/*` → 401; `/api/health`, `/api/ready`, `/api/capabilities` → 200. | `test_anonymous_requests_reach_only_public_endpoints` |
| Forged/expired tokens | Wrong signing key and expired access token → 401. | `test_expired_and_forged_tokens_are_rejected` |
| Companion/invitation tokens | Unknown → 404; used/revoked/expired → 410 (Phase 3/4 tests). No user id, IP or user agent stored for companion responses. | existing suites |

---

## 3. RLS coverage

### Mechanics

- Migration `d9e4f1b2c305_row_level_security.py` creates 35 `safar_*` helper
  functions and applies `ENABLE` + `FORCE ROW LEVEL SECURITY` plus four
  policies (SELECT/INSERT/UPDATE/DELETE) to every domain table — **220
  policies across 55 tables**. Only `alembic_version` has no RLS.
- Identity comes from transaction-local GUCs set with
  `set_config(..., true)` by `app/db/context.py`:
  `app.user_id`, `app.admin`, `app.system`, `app.auth`,
  `app.companion_link`, `app.invitation_token`. With no GUC, policies deny
  access (fail closed).
- Membership helpers (`safar_is_trip_member`, `safar_is_trip_admin`, …) are
  `SECURITY DEFINER` with `SET search_path = public, pg_temp`.
- Production connects as a **non-owner role without `BYPASSRLS`**; the
  migration role needs bypass rights. Exact SQL is in
  `docs/DEPLOYMENT.md` §3.
- Application-layer authorization and serializers remain the primary control.
  RLS is the backstop, not a replacement: it is row-level, so column-level
  privacy (budget limits, access needs, pact limits) is still enforced by the
  serializers described in `docs/ARCHITECTURE.md` §3.

### Domain coverage

| Domain | Tables | Policy intent |
|---|---|---|
| Identity & consent | users, profiles, user_preferences, journey_dna, consent_records, user_blocks, notifications, audit_logs, auth_sessions | Self; shared-trip/circle/connection peers see public profile fields only at the serializer; invites visible to inviter/invitee. `audit_logs` requires `app.admin` or system. |
| Trips | trips, trip_members, trip_invitations, journey_pacts, planner_tasks, trip_branches, material_watch, journey_capsules | Active members; invitations also visible to the matching email or invitation token; trip privacy `public` grants read only to authenticated users. |
| Catalog | destinations, places, activities, place_sources | Public read; writes only admin/system. |
| Planning | itinerary_items, itinerary_versions, itinerary_proposals, activity_votes, itinerary_attendance, shadowplans | Trip members; votes/attendance own-row writes; shadowplans owner. |
| Intelligence | recommendation_batches, recommendations, recommendation_feedback, activity_feedback | Trip members; feedback owner; companion link may read its own target. |
| Pulse & ground | trip_pulse, ground_requests, ground_responses | Trip members; ground responses by matching local contributors. |
| Money | expenses, expense_participants, expense_settlements | Trip members only. |
| Memory | trip_memories, memory_permissions | Owner, explicit `can_view` permission, admin or system. |
| Social | travel_circles, circle_members, circle_posts, local_contributors, connection_requests, saved_inspiration, traveller_matches, abuse_reports, place_reports | Public/circle/connection scopes; place reports are publicly readable by design, writes restricted to the reporter. |
| Offline | offline_sync_queue | Owner only. |
| Companion | companion_links, companion_responses | Link creator, trip admin, or the link's own transaction context; responses have no user id/IP/user-agent columns. |

### Direct SQL evidence (PG 16.4, role `safar_app`, fresh `safar_p5_final`)

| Probe | Result |
|---|---|
| `SELECT count(*) FROM trips` with no GUCs | **0** |
| As mira (`app.user_id`) | **6** trips |
| As jonas | **3** trips |
| Foreign trip by id / its expenses / its members | **0 / 0 / 0** |
| With `app.system='on'` | **9** trips |
| `audit_logs` as mira without admin | **0** |
| `audit_logs` as mira with `app.admin='on'` | **85** |
| `INSERT INTO trips (created_by = mira)` while acting as jonas | **rejected**: `new row violates row-level security policy for table "trips"` |

The full 68-test suite also passed while connected as `safar_app` with FORCE
RLS, which proves the product flows operate inside the policies rather than
around them.

---

## 4. Authentication and session changes

### Cookies

| Cookie | Contents | HttpOnly | Path | Lifetime | Notes |
|---|---|---|---|---|---|
| `safar_access` | HS256 JWT (`sub`, `sid`, `typ: access`) | yes | `/` | 15 min | `Secure` in production; also accepted as `Authorization: Bearer` for API clients |
| `safar_refresh` | `<session_id>.<random secret>` | yes | `/api/auth` | 30 days, rotated on every refresh | Stored server-side as SHA-256; never readable by JavaScript |
| `safar_csrf` | random 32-byte token | **no** (by design) | `/` | 30 days | Echoed in `X-CSRF-Token`; compared with `hmac.compare_digest` |

`SameSite` defaults to `lax`; `none` requires `Secure` (enforced at startup).
`Secure` defaults to true when `ENVIRONMENT=production`. `COOKIE_DOMAIN` is
optional for a shared parent domain.

### Server-side sessions

- `auth_sessions` records user, refresh hash, user agent, keyed-hashed IP,
  expiry, last use, revocation time and reason.
- Every authenticated request checks that the session referenced by `sid`
  still exists, belongs to the user, is unrevoked and unexpired. A stolen
  access token stops working as soon as its session is revoked.
- Refresh rotation: each refresh replaces the stored hash. Presenting a
  previously rotated secret is treated as theft and revokes the session
  (`reason=refresh_reuse`).
- Logout revokes the session for both cookie and bearer callers; repeated
  logout is idempotent.
- WebSocket: `POST /api/auth/ws-ticket` issues a two-minute `typ: ws` JWT bound
  to the session. The socket re-checks user status, session state and trip
  membership before accepting. The first-party client always uses this
  ticket. The endpoint also accepts a normal access token for compatibility —
  see the query-string risk in §7.

### Frontend

- `lib/api.ts` keeps access and CSRF tokens in module memory only; nothing is
  written to `localStorage` or `sessionStorage` (only the theme and the offline
  queue are persisted).
- Every request uses `credentials: "include"`. Unsafe methods add
  `X-CSRF-Token`. A 401 triggers one silent refresh and one retry; concurrent
  callers share the in-flight refresh.
- On page load the app restores the session from the HttpOnly refresh cookie
  (`/api/auth/refresh`) and then `/api/auth/me`.
- Sign-out clears server state and redirects to `/login?next=…`.

### Browser evidence (production build, 2026-11-19)

| Step | Observed |
|---|---|
| Sign in as `mira@safar.demo` | `POST /api/auth/login` 200; redirect to `/dashboard`; dashboard, trips and `/api/users/me` load |
| Cookies after login | `document.cookie` contains **only** `safar_csrf=…`; access and refresh are HttpOnly |
| Trip page | `/trips/<id>/itinerary` renders the confirmed plan (9 items, protected block, version 3) |
| Sign out | Redirect to `/login?next=%2Fprofile`; `document.cookie` empty |
| After sign out | `fetch('/api/auth/me')` → **401**; `fetch('/api/auth/refresh')` → **401** |

### Account deletion and retention

- Deletion removes: Journey DNA, activity/recommendation feedback, votes,
  approvals, attendance, pulse answers, memory permissions, saved inspiration,
  offline queue, missions, circle membership/posts, contributor status, place
  reports, shadowplans, connection requests, matches, pending invitations;
  revokes companion links and all sessions; deletes own `/media/` files; nulls
  memory text/caption/location; sets memories private and soft-deleted;
  anonymises trip memberships (`Former traveller`, budget null, needs empty).
  Shared itinerary/expense history remains for other members, without the
  person's private data.
- Retention defaults: sessions 30 days, invitations 30, companion links 30,
  notifications 180, offline queue 7, audit logs 365. All are environment
  variables; the job is idempotent and can be scheduled externally.

---

## 5. PostgreSQL verification

### Schema and migrations

- Engine: PostgreSQL 16.4 (local cluster, `127.0.0.1:55432`).
- Fresh database `safar_p5_final`: `alembic upgrade head` applied four
  revisions in order (`9c224ee10414` baseline, `b1f6c2d84e71` companion links,
  `c7d3e9a1f204` auth sessions, `d9e4f1b2c305` RLS) with no manual steps.
- Result: 56 relations (55 model tables + `alembic_version`), 220 policies,
  35 helper functions, 55 tables with ENABLE + FORCE RLS, 220 grants to
  `safar_app` (55 tables × 4 verbs).
- Baseline schema uses portable types: `JSON` (native `json` on PG, TEXT on
  SQLite), `DateTime` (UTC-naive `timestamp without time zone` on PG),
  explicit foreign keys and indexes; SQLite enables `PRAGMA foreign_keys=ON`.
  The RLS migration is a no-op on SQLite.
- Duplicate-submission, single-use link/invitation, private-memory and
  multi-user isolation tests all pass on PG, exercising transactions and
  unique/foreign-key constraints under real concurrency semantics at test
  scale.

### SQLite-specific assumptions (what SQLite tests do **not** prove)

| Assumption | Consequence |
|---|---|
| SQLite has no roles or RLS | The SQLite suite proves application-layer authorization only. RLS must be verified on PG (it was, §3). |
| Tests/dev use `create_all`; production uses Alembic | A model change without a migration would pass SQLite tests and fail at production startup. Keep `alembic check` in CI. |
| SQLite ignores `FORCE` and GUCs | `app.*` context code is a no-op there; RLS bugs can only be caught on PG. |
| SQLite locking differs | Concurrency behaviour at production scale is untested (§7). |
| Timestamps are UTC-naive in both engines | Consistent today, but not timezone-aware. Multi-region or DST-sensitive reporting would need `timestamptz`. |

### PostgreSQL test run

```
SAFAR_TEST_DATABASE_URL=postgresql+psycopg://safar_app:…@127.0.0.1:55432/safar_p5_final \
  python -m pytest -q        → 68 passed in 18.59s
python -m pytest -q          → 68 passed in 19.71s   (SQLite)
```

The PG run must use a **fresh** database (or truncate between runs): the
prepared test mode seeds only when the user table is empty, so reusing a dirty
database accumulates demo rows and can fail two order-dependent assertions.
This is a test-harness property, not an application defect; it is recorded in
§7.

---

## 6. Backup and recovery verification

Performed 2026-11-19 against the fresh PG database:

| Step | Command (abridged) | Result |
|---|---|---|
| Dump | `pg_dump -Fc -f safar-backup-2026-11-19.dump safar_p5_final` | 358,169 bytes, exit 0 |
| Restore | `createdb safar_restore_check` + `pg_restore -d safar_restore_check --no-owner` | exit 0, no errors |
| Schema parity | `pg_tables`, `pg_policies`, `pg_class.relforcerowsecurity` | identical: 56 tables, 220 policies, 55 tables with FORCE RLS |
| Row parity | `users`, `trips`, `trip_memories` | identical: 20 / 7 / 9 |
| RLS after restore | `SET ROLE safar_app`; no-context vs mira | 0 vs 6 — policies restored and effective |
| Grants | re-granted to `safar_app` after restore | 220 privileges |

Media files are **not** in the database. `/media` is a local Docker volume;
`docs/DEPLOYMENT.md` §8 documents backing it up alongside the dump and warns
that a database-only restore leaves media references dangling. Verified
limitations: the drill covered schema, data, policies and grants, not a
point-in-time recovery (no WAL archiving is configured) and not a restore
through the Docker volume path.

---

## 7. Remaining risks

Ordered by importance. None of these is silently accepted: each has a
mitigation or a deployment requirement, and the ones that matter are recorded
in `docs/DEPLOYMENT.md`.

| # | Risk | Why it remains | Mitigation / next step |
|---|---|---|---|
| R1 | **No external penetration test or security review** | Phase 5 was a self-assessment; tests prove intended behaviour, not absence of unknown classes of flaw. | Commission an external review before public launch. |
| R2 | **Docker images were not built** | `docker` is unavailable in this environment. Compose and Dockerfiles are reviewed but unexecuted. | Build and smoke-test `docker compose up` in CI or on a host with Docker; verify non-root users, health checks and `alembic upgrade head` on first boot. |
| R3 | **TLS/reverse-proxy path untested** | The stack was exercised over plain HTTP on localhost. HSTS only emits for HTTPS requests; `Secure` cookies require HTTPS. | Terminate TLS at a proxy, set `TRUST_PROXY_HEADERS=true`, test login/refresh/cookies over HTTPS, and confirm HSTS. |
| R4 | **WebSocket token in the query string** | Browsers cannot set handshake headers. The 2-minute ticket limits exposure, but reverse proxies may log query strings and the ticket is not stored single-use. | Use WSS, disable/redact query-string logging at the proxy, keep the 2-minute TTL; consider a single-use ticket store if multi-instance. |
| R5 | **Rate limiting is in-process** | Each API process has its own counters; horizontal scaling multiplies limits. `X-Forwarded-For` is trusted only when explicitly enabled. | Enforce limits at the gateway or move to a shared store (Redis) when running more than one instance. |
| R6 | **Companion/invitation tokens travel in URLs** | That is the product (one-link access). API responses set `Referrer-Policy: no-referrer`, logs redact the path, and links are single-use with expiry/revocation. | Keep token TTLs short, avoid embedding links in third-party pages, and include the web origin in the proxy's no-referrer/no-log policy. |
| R7 | **No production-scale load/concurrency testing** | Concurrency was probed at small scale; PG locking, pool exhaustion and slow queries under load are unmeasured. | Load-test with representative data; size the pool and set statement/lock timeouts at the database. |
| R8 | **Prepared PG test mode requires a clean database** | The harness seeds once and assumes an empty users table. | Create/migrate a fresh database per CI run. |
| R9 | **No WAL archiving / PITR** | Backups are logical dumps; a dump cannot recover to an arbitrary point between runs. | Enable continuous archiving or managed PITR if the RPO demands it. |
| R10 | **UTC-naive timestamps** | Correct and consistent, but not zone-aware. | Move to `timestamptz` if reporting crosses timezones or DST correctness matters. |
| R11 | **No automated accessibility/Playwright suite** | Browser evidence is manual; regressions in security-sensitive UI flows would rely on unit tests. | Add Playwright flows for login, refresh, logout and companion links in CI. |
| R12 | **Optional monitoring is not configured** | Sentry is an integration point (`safar.error` + `SENTRY_DSN`), not a shipped dependency. | Attach an error monitor and log shipping in the deployment environment. |
| R13 | **Demo credentials in the UI** | The login page displays seeded credentials for the demo workspace. | They only exist when `SAFAR_SEED=true`; compose sets it to `false` for production. Never enable seeding on a public deployment. |

---

## 8. Production readiness assessment

Honest verdict: **the application is security-hardened and PostgreSQL-ready,
but not production-certified.** The core controls are implemented and tested;
the unverified items are deployment-path items that require Docker, TLS and an
external review.

| Area | Status | Basis |
|---|---|---|
| Session/auth security | **Ready** | HttpOnly cookies, rotation, reuse detection, revocation, CSRF, session checks; tests + browser evidence |
| Authorization (API) | **Ready** | 121 paths exercised across phases; private trips 404 for outsiders; admin gating; mass-assignment and IDOR tests |
| Database isolation (RLS) | **Ready on PG** | 220 policies, FORCE RLS, fail-closed; direct SQL probes and a full suite as the non-owner role |
| Privacy & user control | **Ready with limits** | Consent, export, erasure, retention, location toggle, memory permissions, blocking/reporting; no analytics pipeline ships, so no analytics-PII path exists |
| Uploads & input handling | **Ready** | Magic-byte checks, 25 MB cap, validated schemas, no SQL injection or 5xx on malicious probes |
| Mobile client (Android) | **Ready with limits** | Backups/cleartext off, env-only release signing, no bundled secrets, HTTPS-only tiles; see §9 |
| Secrets & configuration | **Ready** | No committed secrets (repo has no commits); env-only configuration; production guards for `SECRET_KEY`, CORS, cookies, docs, seeding; accurate `.env.example` |
| Logging & monitoring | **Conditional** | Structured JSON, request ids, redaction and error hook exist; no monitor/log sink is configured in this environment |
| Rate limiting / abuse | **Conditional** | Per-bucket limits and `Retry-After` work; single-process only (R5) |
| Backup & recovery | **Conditional** | Logical dump/restore verified end to end; no PITR and no Docker-volume drill (R9) |
| Infrastructure (Docker/CI) | **Not verified** | Images not built here (R2); CI/CD steps documented but not executed |
| TLS / proxy / HSTS | **Not verified** | Plain HTTP localhost only (R3) |
| Scale / performance | **Not verified** | No load testing (R7) |
| External security review | **Not performed** | R1 |

**Conditions for a public deployment**

1. Build and smoke-test the images with Docker, non-root users and the
   `alembic upgrade head` startup step.
2. Terminate TLS at a proxy; set `ENVIRONMENT=production`, a 32+ character
   `SECRET_KEY`, explicit `CORS_ORIGINS`/`TRUSTED_HOSTS`,
   `TRUST_PROXY_HEADERS=true`, `SAFAR_SEED=false`.
3. Run the database as the non-owner `safar_app` role and apply
   `d9e4f1b2c305`; verify `SELECT count(*) FROM trips` is 0 with no context.
4. Schedule the retention job and backups; test a restore into a clean
   database.
5. Put rate limiting at the gateway if more than one API instance runs.
6. Attach an error monitor and log sink.
7. Commission an external penetration test and a small load test before
   opening registration.

Until those are done, the correct claim is “hardened and verified on this
environment”, not “production ready”.

---

## 9. Android client hardening (Phase 10)

No API, database or authorisation rule changed; this section records the
client-side posture of `apps/mobile`.

- **No secrets in the app**: only the public API base URL and optional tile
  configuration are compile-time values. No map key, AI key or signing secret
  is bundled. Tokens stay in memory; the cookie jar uses Keychain on iOS and
  encrypted preferences on Android.
- **Network**: the main manifest sets `android:usesCleartextTraffic="false"`
  and `android:allowBackup="false"`. Cleartext exists only in the debug
  manifest overlay for emulator development. Release builds require an HTTPS
  `SAFAR_API_BASE_URL` and fail at startup without it.
- **Map tiles**: `SAFAR_MAP_TILE_URL` must be HTTPS in release and must contain
  `{z}`/`{x}`/`{y}`; invalid or absent configuration renders a labelled
  schematic map instead of fetching from an unapproved host. No provider is
  hardcoded and no key is assumed.
- **Signing**: `build.gradle.kts` resolves the keystore from
  `SAFAR_KEYSTORE_PATH`/`_PASSWORD`/`SAFAR_KEY_ALIAS`/`SAFAR_KEY_PASSWORD` or an
  untracked `key.properties`, and throws instead of using the debug key.
  `key.properties`, `*.jks` and `*.keystore` are gitignored. The Phase 10
  release APK/AAB were signed with a throwaway verification key solely to
  prove the path; production must re-sign with the real upload key.
- **Location**: precise origin requires the profile's location-sharing consent
  before the OS permission prompt, and coordinates are used only for the
  current Nearby query. Denial falls back to the shared trip base.
- **Notifications**: no push token or FCM/APNs credential exists; in-app
  notifications are the only channel, so there is no push attack surface.
- **Verified artifacts**: release APK signature checked with
  `apksigner verify --print-certs` (certificate SHA-256
  `d59f0211330ff15bddf068355ee7e2804ea65b647f0d7d685ddc985757333931`); AAB
  reports `jar verified.`. Debug APK installed and exercised on an API 36
  emulator. Hashes and limitations: `docs/FLUTTER_MIGRATION_PLAN.md` §9.

Known client-side limits: the throwaway signing key is not a production
identity; iOS was not built; the emulator image shows an AOSP IME back-callback
bug and a `geolocator` NMEA ANR without Play services; an abrupt kill during
refresh-token rotation forces a fresh sign-in by design.

---

## 8. Phase 13 Step 7 — Production Readiness Security Evaluation

In Phase 13 Step 7, an exhaustive security and operational readiness assessment
was conducted on the Supabase PostgreSQL 17 staging deployment.

### 8.1 Database Role and RLS Hardening
* **Dedicated Non-Owner Role:** The application operates strictly as `safar_app`
  with `NOSUPERUSER` and `NOBYPASSRLS`. The role possesses no DDL capabilities and
  cannot drop or alter tables.
* **Comprehensive RLS Coverage:** 56 total tables have RLS enabled (`relrowsecurity = true`),
  with 55 domain tables configured with `FORCE ROW LEVEL SECURITY` (220 policies).
  `alembic_version` has an explicit SELECT policy (`alembic_version_read`) granting
  read-only access to `safar_app` without DDL or write permissions.
* **Fail-Closed Default:** Any query executed without setting transaction-local GUCs
  (`app.user_id`, `app.admin`, etc.) returns 0 rows.

### 8.2 Transport Security & IPv4 Connection Pooling
* **Mandatory TLS:** All database transport enforces `sslmode=require`. Plaintext
  connections are rejected by the database.
* **IPv4 Pooler Transport:** Supabase direct hostnames (`db.<ref>.supabase.co`)
  resolve only via IPv6. On networks with IPv6 routing drops, connections must route
  through the Supabase IPv4 session pooler (`aws-0-[region].pooler.supabase.com:5432`)
  using `[role].[project_ref]` username format to prevent connection timeouts.

### 8.3 Rate Limiting & Storage Migration Preconditions
* **Distributed Rate Limiting:** The current sliding-window rate limiter runs
  in-memory per API process. Scaling to multiple container instances in cloud
  production requires backed rate-limiting via Redis to maintain global caps.
* **Private Cloud Object Storage:** Media files are currently stored on the local
  filesystem and served via expiring HMAC-signed URLs (12h TTL). Production requires
  migrating to AWS S3 or Cloudflare R2 with expiring presigned download URLs.

### 8.4 Mobile Signing Identity
* **Android Production Upload Keystore:** Existing release APK/AAB artifacts were
  signed with a temporary verification key. An official production upload key must
  be generated and enrolled in Google Play App Signing before public store distribution.
* **iOS Platform Requirement:** Compiling, signing, and device testing the iOS client
  requires macOS with Xcode 15+ and an Apple Developer Team account ($99/year).

---

## Appendix A — security regression tests

`services/api/tests/test_security_hardening.py` (19 tests; all pass on SQLite
and PostgreSQL):

| Test | Proves |
|---|---|
| `test_responses_carry_security_headers_and_request_id` | nosniff, frame denial, no-referrer, CSP, COOP, `no-store`, 32-char request id, valid echo, invalid replacement |
| `test_health_and_ready_do_not_leak_internals` | health/ready bodies contain no secrets or internals |
| `test_unknown_host_header_is_rejected` | TrustedHost returns 400 for `evil.example.com` |
| `test_oversized_body_is_rejected_before_validation` | 413 for a body over the cap, with request id |
| `test_anonymous_requests_reach_only_public_endpoints` | private endpoints 401; public endpoints 200 |
| `test_cookie_sessions_require_csrf_for_writes` | missing/mismatched CSRF 403; valid 201 |
| `test_refresh_rotation_rejects_a_replayed_token` | replayed refresh token 401 and session revocation |
| `test_logout_revokes_the_session_for_existing_tokens` | bearer token invalid after cookie logout; refresh 401; logout idempotent |
| `test_expired_and_forged_tokens_are_rejected` | expiry and wrong key rejected |
| `test_media_upload_rejects_a_spoofed_content_type` | HTML bytes as `image/png` → 415; real PNG → 201 |
| `test_cross_user_trip_access_is_hidden` | trip/expenses/itinerary/memories 404 |
| `test_unknown_companion_and_invitation_tokens_are_404` | no existence leak |
| `test_registration_ignores_privilege_fields` | `is_admin`/`role`/`id` ignored |
| `test_account_deletion_erases_personal_data` | DNA, pulse, sessions, memory text/location and media removed; membership anonymised |
| `test_precise_location_requires_the_privacy_toggle` | 403 without consent; allowed with it |
| `test_retention_removes_only_expired_rows` | expired sessions/invitations/links and old rows removed; fresh rows kept |
| `test_malicious_inputs_are_handled_without_server_errors` | injection probes return 200/401/422, never 5xx |
| `test_error_bodies_do_not_leak_internals` | only `detail`, no traceback |
| `test_rate_limiter_buckets_and_retry_after` | per-bucket 429 + `Retry-After`; health exempt |

## Appendix B — verification commands

```bash
# SQLite regression
cd services/api && python -m pytest -q

# PostgreSQL regression as the non-owner role, against a fresh database
SAFAR_TEST_DATABASE_URL=postgresql+psycopg://safar_app:…@127.0.0.1:55432/safar_p5_final \
  python -m pytest -q

# RLS fail-closed check (see DEPLOYMENT.md §3 for role setup)
psql "$PG_URL" -c "SET ROLE safar_app; SELECT count(*) FROM trips;"          # 0
psql "$PG_URL" -c "SET ROLE safar_app; SELECT set_config('app.user_id','<uuid>',false);
                   SELECT count(*) FROM trips;"                              # own trips

# Backup and restore
pg_dump -Fc -f safar.dump safar
createdb safar_restore_check && pg_restore -d safar_restore_check --no-owner safar.dump

# Retention (scheduled)
python -m scripts.retention

# Frontend
cd apps/web && npm test && npm run typecheck && npm run build
```
