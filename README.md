# SAFAR

**The Living Journey Network** — *Every Person. Every Moment. One Intelligent Journey.*

SAFAR is a collaborative travel platform where a group experience engine
recommends and the group decides. It plans around real hard constraints
(budget, accessibility, time, travel radius), protects private member data,
labels every estimate and report honestly, and turns the finished journey into
a story worth keeping.

- Feature-by-feature honesty: [`docs/FEATURE_REGISTRY.md`](docs/FEATURE_REGISTRY.md)
- Architecture and trust model: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Phase 13 Step 7 Production Readiness Report: [`docs/PHASE13_STEP7_PRODUCTION_READINESS_REPORT.md`](docs/PHASE13_STEP7_PRODUCTION_READINESS_REPORT.md)

---

## 1. Project architecture

```
apps/web        Next.js 15 (App Router) + React 19 + TypeScript + Tailwind
                TanStack Query · Zustand · React Hook Form + Zod · Framer Motion
                Lucide · Leaflet/OpenStreetMap · PWA (manifest + service worker)
apps/mobile     Flutter 3.41 (Dart 3) + Riverpod 2 + GoRouter + Dio
                Material 3 SAFAR design system · secure cookie jar · iOS/Android
services/api    FastAPI + SQLAlchemy 2 + Pydantic 2 + PyJWT
                Routers → services → models; Alembic migrations; pytest
docker-compose  web + api + PostgreSQL/PostGIS (production-like)
```

The web frontend and the Flutter client both talk to the same JSON API. Both
clients hold one WebSocket channel per trip (ticket-authenticated) and also
refresh on pull-to-refresh and after mutations.
The intelligence layer lives inside the API as separate deterministic services;
there is no external LLM, weather, routing or translation provider wired in.
See `docs/ARCHITECTURE.md` for the full diagram, data model groups and the
enforcement points for every privacy invariant.

```
apps/web/app/(app)/trips/[tripId]/   itinerary · voting · pulse · engine ·
                                     twin · rescue · insights · map · places ·
                                     memories · expenses · members · pact ·
                                     tasks · branches · watch · ground ·
                                     missions · offline · assistant · more
```

## 2. Technology stack

| Layer | Choice |
|---|---|
| Frontend (web) | Next.js 15.5 (App Router), React 19.3, TypeScript 5.7 (strict), Tailwind 3.4 |
| Frontend (mobile) | Flutter 3.41.4, Dart 3.11, Riverpod 2.6, GoRouter 17, Dio 5 |
| Client state | TanStack Query 5, Zustand 5 (persisted auth), React Hook Form 7 + Zod 3 |
| UI | Custom editorial design system, Framer Motion, Lucide, Leaflet + OSM |
| Backend | FastAPI 0.115, SQLAlchemy 2.0, Pydantic 2.10, PyJWT, uvicorn |
| Database | SQLite for development/tests; PostgreSQL (Supabase-compatible) in production |
| Migrations | Alembic (baseline revision committed; 56 tables) |
| Tests | pytest (132 tests) + FastAPI TestClient; Vitest + jsdom (12 tests); Flutter (61 unit/widget tests) |
| Realtime | In-process WebSocket hub, token-verified per trip |

## 3. Installation

Prerequisites: Python 3.12+, Node.js 20+, npm.

```bash
git clone <repo>
cd <repo>

# Backend
cd services/api
python -m venv .venv
source .venv/Scripts/activate        # Windows (bash)
# source .venv/bin/activate          # macOS/Linux
pip install -r requirements.txt

# Frontend
cd ../../apps/web
npm ci
```

## 4. Environment variables

Copy the template and edit:

```bash
cp .env.example .env
```

| Variable | Default | Purpose |
|---|---|---|
| `DATABASE_URL` | SQLite `services/api/safar.db` | `postgresql+psycopg://…` for PostgreSQL |
| `SECRET_KEY` | dev placeholder | JWT signing key — **must** be set in production |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | `10080` | Access token lifetime |
| `CORS_ORIGINS` | `http://localhost:3000` | Comma-separated allowed browser origins |
| `ENVIRONMENT` | `development` | `production` disables auto `create_all` |
| `SAFAR_SEED` | true outside production | Idempotent demo dataset |
| `RATE_LIMIT_PER_MINUTE` | `240` | Per-client request budget |
| `NEXT_PUBLIC_API_URL` | `http://localhost:8000` | API base URL, baked at build time |

`OPENAI_API_KEY` exists in configuration but **no service calls it**; setting it
changes nothing. The assistant reports `external_llm: false` at
`/api/assistant/capabilities`.

## 5. Database setup

Development and tests need no setup — SQLite is created automatically and seeded
with deterministic demo data on first start.

Production / Supabase:

```bash
cd services/api
export DATABASE_URL="postgresql+psycopg://user:password@host:5432/safar"
python -m alembic upgrade head
```

The app does not create schema in production; migrations are the source of
truth. `python -m alembic check` verifies the models and migrations agree.

## 6. Running the frontend

Web:

```bash
cd apps/web
npm run dev          # http://localhost:3000
```

Flutter (see [`apps/mobile/README.md`](apps/mobile/README.md) for the full
platform matrix and troubleshooting):

```bash
cd apps/mobile
flutter pub get
flutter run --dart-define=SAFAR_API_BASE_URL=http://10.0.2.2:8010   # Android emulator
flutter run --dart-define=SAFAR_API_BASE_URL=http://localhost:8010  # iOS simulator
```

The base URL is compile-time configuration. Debug builds default to the host
address for the emulator (`10.0.2.2` on Android, `localhost` elsewhere); release
builds must pass `SAFAR_API_BASE_URL` and fail fast without it.

Production build:

```bash
NEXT_PUBLIC_API_URL=http://localhost:8000 npm run build
npm run start        # http://localhost:3000
```

## 7. Running the backend

```bash
cd services/api
python -m uvicorn app.main:app --reload --port 8000
```

- Health: `GET /api/health`
- Interactive API docs: `/api/docs`
- OpenAPI JSON: `/api/openapi.json`

Demo accounts (seeded, password `safar-demo-123`):

| Email | Role |
|---|---|
| `mira@safar.demo` | Owner of the active Kyoto trip |
| `aiko@safar.demo` | Member with accessibility needs |
| `jonas@safar.demo` | Member |
| `leo@safar.demo` | Member who proposes changes |
| `noor@safar.demo` | Opt-in Kyoto local contributor (not a trip member) |
| `mateo@safar.demo` | Opt-in Lisbon contributor |

## 8. Running ML services

There is no separate ML service to run. The intelligence layer is in-process and
deterministic: `services/engine.py`, `ranking.py`, `places.py`, `memory.py`,
`assistant.py`, `feedback.py`, `twin.py`, `rescue.py`, `optimizer.py`,
`fairness.py`, `impact.py`. Each service is testable through the HTTP API and
emits its own labels, uncertainties and provenance. If an external model is
added later, it must go behind one of these service interfaces so the API's
capability disclosure stays truthful.

## 9. Running migrations

```bash
cd services/api
python -m alembic current            # applied revision for DATABASE_URL
python -m alembic upgrade head       # apply
python -m alembic revision --autogenerate -m "describe change"
python -m alembic downgrade -1       # roll back one revision
```

Only one baseline revision is committed today (52 tables). Future schema work
must ship with a migration.

## 10. Testing

```bash
# Backend — 16 API/rule tests on a temporary seeded SQLite database
cd services/api
python -m pytest tests -q

# Frontend — 12 unit tests (formatting, offline queue, toasts)
cd apps/web
npm run typecheck
npm test
npm run build
```

Flutter:

```bash
cd apps/mobile
flutter analyze
flutter test
# live session/CSRF/refresh/logout tests against a running, seeded API
SAFAR_LIVE_API=http://localhost:8010 flutter test test/integration/live_api_test.dart
```

The live suite makes roughly ten auth calls; give the verification API headroom
(`AUTH_RATE_LIMIT_PER_MINUTE=100` is sufficient). The Flutter migration status
and its known limits are recorded in
[`docs/FLUTTER_MIGRATION_PLAN.md`](docs/FLUTTER_MIGRATION_PLAN.md).

The backend tests assert the non-negotiable product rules: engine recommends
without changing the plan, approval gates, member privacy, provenance labels,
idempotent sync, private memories, pact limits, ground-answer labelling, circle
member privacy, and WebSocket membership.

Browser verification: every `(app)` route was loaded in a production build
against the seeded data and checked for runtime errors and rendered content.
See `docs/FEATURE_REGISTRY.md` for per-feature evidence.

## 11. Deployment

### Docker (recommended)

```bash
cp .env.example .env      # set SECRET_KEY; optionally POSTGRES_PASSWORD
docker compose up --build
# web: http://localhost:3000   api: http://localhost:8000
```

Compose runs PostgreSQL 16 + PostGIS, applies `alembic upgrade head` before the
API starts, seeds demo data when `SAFAR_SEED=true`, stores media in a named
volume and gates service startup on `/api/health`.

> The compose files and Dockerfiles follow standard patterns but were **not
> executed in the build environment** (Docker is not installed there). Validate
> them once on a machine with Docker before relying on them.

### Manual production

1. Set `ENVIRONMENT=production`, a strong `SECRET_KEY`, real `DATABASE_URL`,
   and exact `CORS_ORIGINS`.
2. `alembic upgrade head`.
3. `uvicorn app.main:app --host 0.0.0.0 --port 8000` behind TLS.
4. Build the web app with the public API URL and serve `next start` behind TLS.
5. Persist `services/api/storage` (media) and back it up with the database.

### Operational notes

- **Health checks**: Dual-probe architecture:
  - `/api/health` returns basic liveness status.
  - `/api/ready` validates database readiness (`{"status": "ready", "database": "ok"}`) and fails closed (503 Service Unavailable) without leaking engine or schema details.
- **Observability & Logging**:
  - Structured JSON logging (`JsonFormatter`) with ISO timestamps, environment tags, log level, and correlation IDs (`X-Request-Id`).
  - Automated sensitive data redaction for authentication tokens, signatures, passwords, and sensitive path parameters (`companion`, `invitations`, `media`).
  - In-memory metrics tracking (`app/core/metrics.py`) for HTTP status counts, latencies, security violations, database slow queries (>500ms), connection pool health, WebSocket traffic, and offline sync counts.
  - Alert manager (`app/core/alerting.py`) with 5-minute category cooldowns emitting to `safar.alert`.
  - Secured administrative metrics endpoint (`GET /api/admin/metrics`) restricted to admins.
- **Mobile Diagnostics**:
  - `DiagnosticsService` circular buffer with sensitive token scrubbing and unhandled error handling (`FlutterError.onError`, `PlatformDispatcher.instance.onError`).
  - Network and WebSocket telemetry interceptors.
  - Offline queue state tracking (`pending`, `syncing`, `failed`) and retry recovery.
- **Backups & Recovery**:
  - Automated backup script (`services/api/scripts/backup_staging.py`) creating logical PostgreSQL backups via `pg_dump -Fc`.
  - SHA-256 integrity checksumming and structured manifest recording (`storage_staging/backups/backup_manifest.json`).
  - 7-backup retention enforcement.
  - Non-destructive automated restore drill against temporary verification database (`safar_restore_verify`), asserting table counts, migrations, and PostgreSQL Row-Level Security (RLS) policies.
- **Security headers**: set on the Next.js app (`nosniff`, referrer policy,
  frame options); terminate TLS at the proxy.

## Privacy and security guarantees

- Private member budgets, accessibility details, pulse notes and private
  memories are filtered server-side, not hidden in the UI.
- Confirmed itineraries only change through explicit owner/admin edits or
  approved proposals; engines, rescue, twin and branches never write directly.
- Community reports stay `REPORTED` until moderated with a source; single
  observations never become `VERIFIED`.
- No exact live member locations are stored or exposed.
- Traveller connections require mutual acceptance; blocks remove discovery.
- Secrets live in environment variables; nothing secret is read by the browser
  bundle.

## Known limitations

Tracked honestly in `docs/FEATURE_REGISTRY.md`. Highlights:

- F17 Dream Import reads pasted text, optional page metadata (off by default)
  and local OCR when Tesseract is installed; it proposes candidates for review
  and never uploads images to a third party.
- F21 crowd forecasts need ≥8 recent reports and an identifiable time bucket;
  otherwise the place page shows insufficient data or the latest observation.
- F22 answers in eight languages using in-repo lexicons and templates. It is
  not a general translation model; unsupported phrasing falls back to English
  with a note.
- No external LLM is wired. Weather (Open-Meteo) and link metadata are optional,
  server-side and off by default; no email or object-storage provider is
  configured.
- PostgreSQL RLS is shipped for production; SQLite development relies on the
  application-layer filters.
- Docker files are provided but were not built in this environment.

---

SAFAR never invents travel facts, never silently rewrites a plan, and never
trades a member's hard constraint for a better average.
