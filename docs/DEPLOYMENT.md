# SAFAR — Deployment, Operations and Recovery

This document describes how to run SAFAR outside a developer laptop. It
covers PostgreSQL, row-level security, secrets, logging, health checks,
backups and recovery. Everything here is implementable without a paid
service; optional integrations are marked.

Verification status is stated per section. Where something could not be
exercised in the development environment it is called out explicitly.

---

## 1. Topology

```
browser ──HTTPS──> reverse proxy ──> web (Next.js, :3000)
                         │
                         └─────────> api (FastAPI/uvicorn, :8000) ──> PostgreSQL 16
                                              │
                                              └──> media volume (/app/storage)
```

- The API is the only component that talks to the database.
- Trip media is stored on a local volume and served by the API only with a
  short-lived HMAC signature (12 hours).
- Sessions: access JWT (15 minutes, HttpOnly cookie and/or bearer), rotating
  refresh token (30 days, HttpOnly cookie), readable CSRF cookie.
- No external AI, weather, translation, analytics or map service is called.
  `GET /api/health` reports `external_ai: false` and
  `GET /api/assistant/capabilities` reports the same.

`docker-compose.yml` is a production-like reference stack. PostgreSQL is
plain `postgres:16-alpine`; SAFAR does not use PostGIS or any database
extension.

**Verification:** the API, PostgreSQL 16.4, migrations, RLS, the test suite,
backup and restore were exercised on this machine (see §10). Docker itself
was **not available** in the development environment, so the images and
compose file were reviewed but not built here.

---

## 2. Configuration

Copy `.env.example` to `.env` (compose) and/or `services/api/.env` (direct
runs). Never commit a real `.env`.

Required for any non-development deployment:

| Variable | Why |
| --- | --- |
| `SECRET_KEY` | Signs JWTs, media URLs and keyed IP digests. ≥ 32 chars. Startup fails in production if it is the default or too short. |
| `DATABASE_URL` | `postgresql+psycopg://user:password@host:5432/safar` |
| `ENVIRONMENT` | `production` disables schema creation, seeding defaults and API docs, enables cookie hardening. |
| `CORS_ORIGINS` | Exact browser origins. Wildcards are rejected in production. |
| `TRUSTED_HOSTS` | Host header allowlist; requests with other Host headers get 400. |
| `COOKIE_SECURE` / `COOKIE_SAMESITE` | Must match the deployment scheme. `SameSite=none` requires `Secure`. |
| `POSTGRES_PASSWORD` | Compose database password (compose refuses to start without it). |

Important operational variables:

| Variable | Default | Notes |
| --- | --- | --- |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | 15 | Keep short; refresh rotation handles continuity. |
| `REFRESH_TOKEN_EXPIRE_DAYS` | 30 | |
| `SAFAR_SEED` | false in production | Never seed demo accounts in production. |
| `SAFAR_CREATE_SCHEMA` | false in production | Production schema comes from migrations only. |
| `RATE_LIMIT_PER_MINUTE` | 240 | Per IP, default bucket. |
| `AUTH_RATE_LIMIT_PER_MINUTE` | 10 | Login/register/refresh/logout bucket. |
| `COMPANION_RATE_LIMIT_PER_MINUTE` | 20 | Public one-link responses. |
| `UPLOAD_RATE_LIMIT_PER_MINUTE` | 30 | Media and sync uploads. |
| `MAX_REQUEST_BYTES` | 26214400 (25 MB) | Rejected with 413 before parsing. |
| `TRUST_PROXY_HEADERS` | false | Enable only behind a proxy that overwrites `X-Forwarded-For`. |
| `ENABLE_API_DOCS` | false in production | `/api/docs` and `/api/openapi.json`. |
| `LOG_LEVEL` | INFO | JSON logs to stdout. |
| `RELEASE` | safar-1.0.0 | Reported by `/api/health`. |
| `SENTRY_DSN` | unset | Optional; requires `sentry-sdk` installed. No PII is sent (`send_default_pii=False`). |

Backend-only secrets (`SECRET_KEY`, `DATABASE_URL`, `OPENAI_API_KEY`) are
never prefixed with `NEXT_PUBLIC_`; `NEXT_PUBLIC_*` values are shipped to the
browser.

---

## 3. Database and row-level security

### 3.1 Applying migrations

Run as the database owner (or a role with DDL rights):

```bash
cd services/api
DATABASE_URL=postgresql+psycopg://owner:...@host:5432/safar \
  python -m alembic upgrade head
```

The migration chain creates 54 domain tables (plus `alembic_version`), 220
row-level-security policies and 35 `safar_*` helper functions. Every domain
table has `ENABLE` + `FORCE ROW LEVEL SECURITY`; `alembic_version` has a dedicated
SELECT policy (`alembic_version_read`) granting the application role read access
while blocking DDL/DML.

Do not let the application create or alter the schema in production. The
compose container runs `alembic upgrade head` at start; for managed
databases run it as a separate release step.

### 3.1.1 Supabase IPv4 Session Pooler Transport

Direct Supabase hostnames (`db.<ref>.supabase.co:5432`) resolve only via IPv6 (`AAAA`).
To ensure connection reliability and prevent host socket timeouts on networks without
native IPv6 routing, configure the connection string using the Supabase IPv4 session
pooler:

```text
DATABASE_URL=postgresql+psycopg://safar_app.<project_ref>:<password>@aws-0-[region].pooler.supabase.com:5432/postgres?sslmode=require
```

### 3.2 Use a non-owner application role

RLS is enforced for the table owner too (FORCE RLS) and for every role
without `BYPASSRLS`. A separate login role keeps DDL and runtime privileges
apart. Verified SQL (run as the owner after migrations):

```sql
CREATE ROLE safar_app LOGIN PASSWORD '...' NOSUPERUSER NOBYPASSRLS;
GRANT CONNECT ON DATABASE safar TO safar_app;
GRANT USAGE ON SCHEMA public TO safar_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO safar_app;
-- For future migrations run by this owner:
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO safar_app;
```

Do not grant `safar_app` ownership of tables or `BYPASSRLS`.

### 3.3 How the identity reaches the database

The API sets transaction-local GUCs (`app.user_id`, `app.admin`,
`app.system`, `app.auth`, `app.companion_link`, `app.invitation_token`)
through `set_config(..., true)` on every transaction. Helpers are
`SECURITY DEFINER` with a locked `search_path`. The app never filters
security only in Python and never relies on frontend restrictions.

### 3.4 Verifying RLS after deploys

```sql
-- As the app role, with no identity: must return 0.
SELECT count(*) FROM trips;

BEGIN;
SELECT set_config('app.user_id', '<a real user id>', true);
SELECT count(*) FROM trips;  -- only that user's trips
COMMIT;
```

Expected on the verification database (2026-11-19): no identity → `0`;
a member with 6 trips → `6`; a user outside a private trip sees `0` rows in
`trips`, `trip_members` and `expenses` for it; inserting a trip with another
user's `created_by` fails with a row-level security violation.

---

## 4. Running the stack

```bash
cp .env.example .env       # set SECRET_KEY and POSTGRES_PASSWORD
docker compose up --build
```

- API: `http://localhost:8000`, web: `http://localhost:3000`.
- Both containers run as unprivileged users (`safar`, `node`).
- Health checks: the API uses `/api/ready`; the database uses `pg_isready`.
- Media persists in the `media` volume; the database in `pgdata`.

For a local HTTP trial set `COOKIE_SECURE=false`. In production, terminate
TLS at the reverse proxy and keep `COOKIE_SECURE=true`; otherwise the
browser will not store the session cookies.

Reverse proxy requirements:

- Forward `X-Forwarded-For` and `X-Forwarded-Proto`; set
  `TRUST_PROXY_HEADERS=true` only if the proxy overwrites them.
- Request body limit at or above `MAX_REQUEST_BYTES`.
- Do not cache `/api/*` or `/media/*` responses (the API already sends
  `Cache-Control: no-store` / `private, no-store`).

---

## 5. Health checks and monitoring

| Endpoint | Use |
| --- | --- |
| `GET /api/health` | Liveness plus database check. Never fails on a degraded database; reports `database: unavailable`. |
| `GET /api/ready` | Readiness. Returns 503 when the database is unreachable. Use for load balancer registration and container health. |

Logging:

- Structured JSON on stdout with `ts`, `level`, `logger`, `message`,
  `request_id`, `method`, `path`, `status`, `duration_ms`, `client`.
- Client IPs are stored as a keyed HMAC prefix, never raw.
- Query strings, cookies, authorization headers and request bodies are never
  logged.
- Path segments for `/api/companion/<token>`, `/api/invitations/<token>` and
  `/media/<...>` are redacted before logging.
- Uvicorn's raw access log is disabled so one-use tokens cannot leak through
  it.
- The same `X-Request-Id` is echoed to the client and included in the JSON
  body of an unhandled 500.

Error monitoring integration point: the `safar.error` logger. Installing
`sentry-sdk` and setting `SENTRY_DSN` initialises Sentry without PII; any
other provider can attach a logging handler to that logger. No paid service
is required.

---

## 6. Rate limiting

The limiter is an in-process sliding window keyed by client IP with separate
buckets for auth, companion responses, uploads and everything else. It is
adequate for one API process.

For horizontal scaling put a shared limiter (gateway or Redis) in front and
keep the application limiter as defence in depth. `/api/health`,
`/api/ready` and `/api/openapi.json` are exempt so probes never spend the
budget.

---

## 7. Retention

`RETENTION_*` variables control how long the cleanup job keeps:

| Data | Default |
| --- | --- |
| Auth sessions past expiry | 30 days |
| Unaccepted, expired invitations | 30 days |
| Expired or revoked one-use links | 30 days |
| Notifications | 180 days |
| Audit log rows | 365 days |
| Applied offline queue rows | 7 days |

Run daily:

```bash
cd services/api && python scripts/retention.py
# containers:
docker compose run --rm api python scripts/retention.py
```

The job prints a JSON summary per table. Account deletion (`DELETE
/api/users/me`) is immediate and removes personal preferences, memories,
media files, session rows, pending links and personal content; shared trip
records are kept anonymised.

---

## 8. Backups and restore

### 8.1 What to back up

1. PostgreSQL (all data, RLS policies and grants).
2. The media volume (`/app/storage`): files are not reproducible from the
   database.

### 8.2 PostgreSQL Logical Dumps and Retention

Automated staging backups are performed via `services/api/scripts/backup_staging.py`:
- Generates compressed custom-format dumps (`pg_dump -Fc`).
- Computes SHA-256 integrity checksums and records metadata into `backup_manifest.json`.
- Enforces 7-backup retention (`enforce_retention(max_backups=7)`), strictly guaranteeing
  that the most recent successful backup is never deleted and failed attempts never displace valid dumps.
- Manifest integrity is verified on-demand via `verify_manifest_integrity()`.

```bash
cd services/api
python scripts/backup_staging.py
```

### 8.3 Disaster Recovery & Continuous Archiving Requirements (PITR)

Periodic logical dumps (`pg_dump -Fc`) do not provide Point-in-Time Recovery (PITR).
For production deployment, cloud database infrastructure must be configured with:
1. **Continuous Write-Ahead Log (WAL) Archiving:** Archiving WAL segments to durable
   cloud object storage (S3/GCS).
2. **Point-in-Time Recovery (PITR):** Recovery Point Objective (RPO) < 15 minutes and
   Recovery Time Objective (RTO) < 1 hour.
3. **Multi-AZ Replication:** Automated failover across multiple availability zones.
4. **Separate Production Instance:** Staging and production MUST never share database
   instances, schemas, or credentials.

Verify after restore:

```sql
SELECT count(*) FROM information_schema.tables WHERE table_schema='public'; -- 56
SELECT count(*) FROM pg_policies WHERE schemaname='public';                  -- 220
SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind='r' AND c.relrowsecurity
  AND c.relforcerowsecurity;                                                 -- 55
```

Then connect as the app role with no identity and confirm `SELECT count(*)
FROM trips` returns 0.

**Verified on 2026-11-19** (PostgreSQL 16.4): `pg_dump -Fc` +
`pg_restore` into a fresh database reproduced 56 tables, 220 policies, 55
FORCE-RLS tables and identical row counts (`users` 20, `trips` 7,
`trip_memories` 9). RLS enforcement survived the restore: no-context trips
`0`, member context `6`.

### 8.3 Media

```bash
docker run --rm -v safar_media:/data -v "$PWD":/backup alpine \
  tar czf /backup/media-$(date +%F).tar.gz -C /data .
```

Restore by extracting into the volume while the API is stopped. Signed
media URLs remain valid only until their 12-hour expiry; signatures are
derived from `SECRET_KEY`, so keep that value stable across restores.

### 8.4 Drill cadence

- Nightly logical backup, retained off-host.
- Weekly restore into a scratch database and run the verification queries.
- Media volume snapshot on the same schedule.
- Suggested objectives: RPO 24 hours (or WAL archiving for less), RTO under
  1 hour for a database of this size.

---

## 9. Rollback and recovery

1. **Bad release, schema unchanged:** redeploy the previous image. Sessions
   stay valid; cookies are signed with the same `SECRET_KEY`.
2. **Bad migration:** `python -m alembic downgrade -1` only if the migration
   is reversible and no dependent data was written. The RLS migration has a
   downgrade that drops its policies and helpers. Prefer restoring the
   pre-release backup when data changed.
3. **Corrupt or lost database:** restore the latest dump, verify with §8.2,
   point the API at the restored database, then rotate `POSTGRES_PASSWORD`.
4. **Compromised secret:** rotate `SECRET_KEY` (invalidates every access
   token, media link and refresh session), then force re-login. Rotate the
   database password and any optional provider keys.
5. **Lost media volume:** restore the most recent media archive and run the
   API again; memories whose files are missing return 404 rather than
   broken pages.

Deploy order for a new release: backup → run migrations as owner → deploy
API → deploy web → smoke test `/api/ready`, login, one authenticated read
and one media fetch.

---

## 10. CI/CD recommendations

- Run the backend suite on PostgreSQL with RLS, not only SQLite:

  ```bash
  # once per run, as the owner
  python -c "from tests.conftest import _reset_postgres"   # or recreate manually
  SAFAR_TEST_DATABASE_URL=postgresql+psycopg://safar_app:...@host:5432/safar_test_rls \
  SAFAR_TEST_PREPARED=1 python -m pytest -q
  ```

  The prepared mode connects as an unprivileged, non-owner role so FORCE RLS
  is exercised by every request.
- Build both images, run `npm audit`/`pip-audit` or the platform scanner,
  and fail on critical findings.
- Gate merges on: backend tests, `npm test`, `npm run lint`, `tsc --noEmit`
  and a migration dry run against a scratch database.
- Keep secrets in the CI secret store; pass `NEXT_PUBLIC_*` only as build
  args (they are public), and never pass `SECRET_KEY` into the web build.
- Migrations are a release step, not a build step: run them once per
  environment and keep the previous image deployable for rollback.

---

## 11. Known deployment limits

- Rate limiting, WebSocket fan-out and the in-memory client map are
  per-process. Run one API process, or add a shared limiter and a
  broadcast bus before scaling out.
- Media lives on a local volume. For multi-node deployments, move it to
  shared/object storage and keep signed URLs.
- The API does not trust proxy headers by default; misconfiguration either
  breaks IP-based limits (if enabled too eagerly) or collapses all clients
  into the proxy IP (if disabled behind a proxy).
- A complete restore drill, container build and reverse-proxy/TLS setup were
  **not** executed in the development environment. They must be performed
  and recorded for the target infrastructure before claiming production
  readiness.
