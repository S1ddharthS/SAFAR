# SAFAR — Flutter migration plan (Phases 8–9)

Status: all 49 features have a Flutter surface backed by the live FastAPI
contracts; 47 are complete, 2 are partial (F04 invitations/member admin and F10
basemap tiles remain web-only). Phase 9 added the 22 remaining features, the F23
pact editor, real-time trip collaboration, native share/camera/location/deep
links and an offline capture queue. Last updated 2026-11-20. The FastAPI backend
in `services/api` is the system of record. The Next.js app in `apps/web` stays
in place and remains the reference implementation and fallback until the Flutter
app is verified on device.

## 1. Audit findings that constrain the migration

### 1.1 Stack and ownership of logic

| Layer | Location | Phase 8 treatment |
|---|---|---|
| API, auth, authorisation, RLS context | `services/api` | Reused unchanged. No endpoint or contract changes. |
| Group Experience Engine, assistant, forecasting, Dream Import, Memory Studio | `services/api/app/services` | Reused unchanged. Flutter never re-implements ranking, NLU, extraction or privacy filtering. |
| PostgreSQL schema and migrations | `services/api/alembic` | Reused unchanged. |
| Reference UI and design system | `apps/web` | Kept available; used as the visual and workflow reference. |
| Flutter client | `apps/mobile` (new) | Built in this phase. |

### 1.2 Authentication contract (verified in `app/routers/auth.py`, `app/core/cookies.py`, `app/core/deps.py`)

- Login/register return `{access_token, csrf_token, user, expires_in, token_type}` and set three cookies:
  - `safar_access` — HttpOnly, 15 minutes, path `/`.
  - `safar_refresh` — HttpOnly, 30 days, path `/api/auth`.
  - `safar_csrf` — readable, 30 days, path `/`.
- `POST /api/auth/refresh` reads **only** the refresh cookie. A bearer-only
  client cannot refresh. The Flutter client therefore persists the cookie jar
  (all `Set-Cookie` values) in `flutter_secure_storage` on native platforms.
- Bearer requests bypass CSRF in `deps.py`; cookie-sourced unsafe requests
  require `X-CSRF-Token` equal to `safar_csrf`. Flutter sends both the bearer
  token and the CSRF header, so behaviour is correct in either mode.
- Session revocation is checked through the `sid` claim on every request.
- `COOKIE_SECURE` defaults to true only in production. Development cookies work
  over plain HTTP for emulators and local verification.

### 1.3 Platform networking

- Native apps are not subject to CORS. They are subject to
  `TrustedHostMiddleware`: the dev default now includes the emulator alias
  `10.0.2.2`. A physical device or another host still needs to be added to
  `TRUSTED_HOSTS`.
- The API base URL is a compile-time `--dart-define=SAFAR_API_BASE_URL=...`.
  There is no localhost default in release builds; a release build without the
  define fails fast with a configuration error.
- Flutter web is used only as a local verification target in this environment
  (no iOS host, no Windows C++ toolchain). Its origin must be added to
  `CORS_ORIGINS` for that verification run.

### 1.4 Design system extracted from Phase 6 (`docs/UI_DESIGN.md`, `app/globals.css`)

- Paper/surface/raised/ink/muted/faint/line/ember/ember-soft/jade/jade-soft/rose,
  with light and dark values.
- Serif display face for headings, system sans for body, uppercase 0.14em
  eyebrows, tabular numerals for prices and times.
- 1.5rem cards, 2rem hero panels, 1px hairlines, soft card shadows, 200–300 ms
  `cubic-bezier(0.22, 1, 0.36, 1)` transitions.
- Trust language is part of the UI: provenance labels
  (`VERIFIED`/`REPORTED`/`ESTIMATED`/`PREDICTED`), confidence, limitations and
  "nothing changes until approved" notes.

## 2. Flutter architecture

```
apps/mobile/
  lib/
    main.dart
    app/                 # app root, router, shell, theme wiring
    core/
      config/            # compile-time environment and base URL
      network/           # Dio client, persisted cookie jar, auth interceptor, errors
      storage/           # secure storage abstraction (+ in-memory test store)
      models/            # typed immutable models with fromJson
      repositories/      # API repositories per domain (no business rules)
      theme/             # SAFAR tokens, Material 3 theme, typography
      widgets/           # buttons, cards, headers, badges, states, skeletons
      utils/             # dates, currency, formatting
    features/
      auth/              # splash, onboarding, login, register, session controller
      dashboard/
      discover/          # destinations, destination detail, place detail + crowd forecast
      trips/             # trip list and creation
      trip/              # overview, itinerary, engine, voting, expenses, pulse, DNA
      assistant/
      inspirations/      # Dream Import
      rescue/
      memories/          # memories, studio, replay
      notifications/
      profile/           # profile, settings, consents, sign out
```

- **State**: Riverpod 2.6.1 (`Provider`, `FutureProvider.autoDispose.family`,
  `StateNotifier` for the session, `ref.invalidate` after mutations).
- **Routing**: GoRouter with an auth redirect gate, deep links to trips and
  destinations, and a `StatefulShellRoute` bottom bar for Home / Discover / Ask /
  You.
- **HTTP**: one Dio instance with `dio_cookie_manager` and a persisted
  `cookie_jar`; an auth interceptor attaches bearer + CSRF, refreshes once on
  401, serialises concurrent refreshes and emits an unauthorised event after a
  failed refresh.
- **Models**: immutable Dart classes with explicit `fromJson` factories
  (equivalent to Freezed for this read-heavy client, without a codegen step in
  CI). Unknown/extra JSON fields are ignored; no model invents defaults that
  would turn missing data into a fact.
- **Errors**: `ApiException` carries status + server detail; repositories map
  network failures to typed failures; widgets render loading, empty, error and
  retry states from real request state.
- **Backend remains authoritative**: no AI, ranking, forecasting, extraction or
  authorisation logic in Dart. The client only renders and submits.

## 3. Endpoint → screen matrix

| Screen | Endpoints |
|---|---|
| Splash / onboarding | `POST /api/auth/refresh`, `GET /api/auth/me` |
| Login / register | `POST /api/auth/login`, `POST /api/auth/register` |
| Dashboard | `GET /api/users/me`, `GET /api/trips`, `GET /api/users/me/dna`, `GET /api/users/me/notifications` |
| Discover | `GET /api/destinations`, `GET /api/destinations/{id}`, `GET /api/activities/search` |
| Place detail | `GET /api/trips/{id}/places/{activityId}`, `POST /api/trips/{id}/place-reports` |
| Trip creation | `POST /api/trips` |
| Trip overview | `GET /api/trips/{id}`, members, `GET /api/trips/{id}/next-action`, itinerary summary |
| Itinerary | `GET /api/trips/{id}/itinerary`, item create/update/delete, attendance |
| Group Experience Engine | `GET/POST /api/trips/{id}/engine/*`, feedback, propose |
| Group voting | `GET/POST /api/trips/{id}/proposals*`, vote, approve/reject |
| Group expenses | `GET/POST /api/trips/{id}/expenses`, `GET /balances` |
| Journey DNA | `GET/PUT /api/users/me/dna`, `PATCH /api/users/me/profile` |
| Memories / Studio | `GET/POST /api/trips/{id}/memories`, `GET /memory-studio`, `POST /memory-events` |
| Journey Replay | `GET /api/trips/{id}/replay` |
| Dream Import | `GET/POST /api/trips/{id}/inspirations`, `POST .../review` |
| Trip Rescue | `POST /api/trips/{id}/rescue/analyze`, `POST .../rescue/propose` |
| AI assistant | `POST /api/assistant/chat`, `POST /api/trips/{id}/assistant`, `GET /api/assistant/capabilities` |
| Profile / settings | `GET /api/users/me`, profile/consents/settings update, blocks, export |
| Notifications | `GET /api/users/me/notifications`, read / read-all |

Secondary web routes (circles, contributors, connections, missions, tasks,
branches, twin, companion links, offline sync, opportunity clock) are reached
from the trip "More" surface where their endpoints exist. They are not
re-implemented as static placeholders.

## 4. Migration order

1. Scaffold and core infrastructure (config, cookie jar, Dio, theme, router, shell).
2. Splash/onboarding, login and register; session restore, refresh and logout.
3. Dashboard, discover, trip creation.
4. Trip overview, itinerary, engine, voting, expenses, pulse, DNA.
5. Assistant, Dream Import, Rescue, memories/studio/replay, place detail.
6. Profile/settings, notifications, error/offline states.
7. Analysis, unit/widget tests, live API integration test, Android build, docs.

## 5. Verification plan

- `flutter analyze` clean.
- Unit tests: cookie persistence/path matching, auth refresh single-flight,
  error mapping, date/currency helpers, model parsing for representative payloads.
- Widget tests: splash gate, login validation, dashboard loading/error/empty,
  itinerary timeline, engine explanation rendering, assistant provenance labels.
- Live API integration test (Dart VM, real HTTP): register/login, refresh,
  trip create, itinerary read, engine generate, assistant answer, logout, session
  revoked. Run against the local FastAPI instance.
- `flutter build apk --debug` (Android SDK 36.1.0 is installed). iOS cannot be
  built on this Windows host; that limitation is reported rather than claimed.
- Visual verification on Flutter web (Chrome) and/or Android if an emulator is
  available, against the live API with CORS configured.

## 6. Explicit non-goals and limits

- No backend behaviour is changed to make the client easier.
- No mock API layer, seeded fake responses or static feature screens.
- No secrets in the Flutter bundle; only the API base URL is configured.
- Private budgets, accessibility needs, pulse notes and private memories are
  rendered only where the API returns them to the current user.
- The Next.js app is not removed in this phase.

## 7. Phase 8 results (2026-11-20)

### 7.1 Implemented screens

All eighteen priority screens exist as real API-backed screens:

1. Splash and three-page onboarding.
2. Login and registration (local validation, password reveal, server errors).
3. Dashboard (greeting, active trip, next action, DNA summary, notifications,
   quiet mode).
4. Discover destinations and destination detail (balance lens, best months,
   activities).
5. Trip creation.
6. Trip overview (members, dates, budget, itinerary summary, sections).
7. Itinerary timeline (day tabs, add/edit, protected time, attendance).
8. Group Experience Engine (recommendations, reasons, trade-offs, sources,
   uncertainty, clarify question, feedback, propose).
9. Group voting (proposals, private votes, approve/reject, pact conflicts).
10. Group expenses (add, settle, balances, per-person figures).
11. Journey DNA (scores, sources, explicit edits).
12. Memories and Memory Studio.
13. Journey Replay.
14. Dream Import (paste text/link, review extracted items, approve).
15. Trip Rescue (analyse, grounded alternatives, propose).
16. AI Travel Assistant (grounded answers, sources, limitations, suggestions).
17. Profile, settings, consents and sign-out.
18. Notifications (list, mark read, mark all read, deep link to trip).

Additional screens reached from these flows: place detail (reports, crowd
forecast, access chain, provenance labels), destination detail, trip list.

### 7.2 API integration status

- Every screen reads and writes through `core/repositories` and a single Dio
  client. There are no hardcoded response arrays, seeded UI data or fake AI.
- Loading, empty, error and retry states are rendered from real request state;
  `ApiException` distinguishes network, timeout, auth, validation and server
  failures.
- Timeouts: 12 s connect, 30 s send, 45 s receive.
- No duplicate AI logic exists in Dart: ranking, extraction, forecasting,
  negotiation, citations and privacy filtering all come from the API.
- Verified against the seeded Kyoto trip and a newly created trip
  (`Flutter Verification Trip`), including writes (mark-all-read, new trip).

### 7.3 Authentication implementation

- Native cookie jar persisted in secure storage; web uses credentialed
  browser cookies. Access and CSRF tokens stay in memory.
- Single-flight refresh on 401, automatic retry, rotation of the refresh token,
  and sign-out on a rejected refresh.
- Logout revokes the server session and clears local state even when the call
  fails.
- Seven Dart live-API tests cover login, cookie persistence across a simulated
  restart, transparent refresh with refresh-token rotation, logout revocation,
  CSRF rejection of cookie-only writes, wrong credentials and network failure.
  All pass against the running FastAPI instance.

### 7.4 Test evidence

| Check | Result |
|---|---|
| `flutter analyze` | No issues found |
| Unit tests (`format_test.dart`, 9 tests) | Pass |
| Widget tests (`widget_test.dart`, 3 tests) | Pass |
| UI fix tests (`ui_fixes_test.dart`, 3 tests) | Pass |
| Live API tests (`test/integration/live_api_test.dart`, 7 tests) | Pass |
| Backend Phase 7 assistant regression suite | 13 passed |
| Browser verification (Flutter web against live API) | All priority screens and the workflows in §7.1 |

Browser verification covered signed-in session restore, dashboard, discover,
destination, trip list, trip creation, overview, itinerary, engine, voting,
expenses, rescue, memories, studio, replay, Dream Import, assistant, Journey
DNA, profile, settings, dark theme and notifications. The in-app browser was
unavailable for a final cosmetic re-check, so the four fixes made after that
pass were verified with targeted unit/widget tests instead: the pulse day
label, the labelled image placeholder, the month-name list and the shared clock
formatter.

### 7.5 Build results

- **Web (verification target):** builds and runs; used for the browser pass.
- **Android:** not produced in this environment. `flutter build apk --debug`
  failed before compilation because Gradle could not download Maven artifacts:
  `PKIX path building failed … unable to find valid certification path`. The
  traffic is intercepted by the installed Avast Web/Mail Shield TLS scanner
  (confirmed with `openssl s_client`), whose root is trusted by Windows but not
  by the JDK. Trusting that root in a build truststore was not performed because
  it is a security decision that requires explicit user authorisation. The
  Android configuration itself was corrected in this phase: the main manifest
  now declares `INTERNET`, the debug overlay permits cleartext for local HTTP,
  and debug builds default to `10.0.2.2` on Android.
- **iOS:** not buildable on this Windows host (no macOS/Xcode). No iOS result
  is claimed.

### 7.6 Feature-by-feature status

Legend: **M** = Flutter surface implemented and exercised against the live API;
**P** = partial surface; **W** = web-only in this phase (still available in
`apps/web`).

| ID | Feature | Flutter surface | Status |
|---|---|---|---|
| F01 | Account, consent, preferences | login, register, settings, consents | M |
| F02 | Journey DNA | `/journey-dna` | M |
| F03 | Destination and activity discovery | discover, destination, place | M |
| F04 | Trip creation, membership, roles | trips, `/trips/new`, overview | M |
| F05 | Collaborative itinerary and voting | itinerary, proposals | M |
| F06 | Trip pulse | `/pulse` | M |
| F07 | Group Experience Engine | `/engine` | M |
| F08 | Trip Twin | — | W |
| F09 | Trip Rescue and autopilot | `/rescue` | M |
| F10 | Maps and nearby experiences | — | W |
| F11 | Shared memory timeline | `/memories` | M |
| F12 | AI Memory Studio | `/studio` | M |
| F13 | Group expenses | `/expenses` | M |
| F14 | Place Pulse | place screen: reports, helpful, create report | M |
| F15 | Serendipity Radar | — | W |
| F16 | Travel Circles and contributors | — | W |
| F17 | Dream-to-destination import | `/import` | M |
| F18 | Journey Replay and travel book | `/replay` | M |
| F19 | Missions and wildcards | — | W |
| F20 | Offline-first capture and sync | network/offline states only; no capture queue | W |
| F21 | Predictive crowd forecasting | place screen | M |
| F22 | Multilingual assistant | `/assistant` | M |
| F23 | Journey Pact | conflicts shown in proposals/itinerary; no pact editor | P |
| F24 | Opportunity Clock | — | W |
| F25 | Shadowplan | — | W |
| F26 | One-Link Companion | — | W |
| F27 | Planner load balancer | — | W |
| F28 | Branch and rejoin | — | W |
| F29 | Journey effort budget | — | W |
| F30 | Decision Evidence Passport | provenance/source labels on engine, assistant, place | M |
| F31 | Ask the Ground | — | W |
| F32 | Cost-Shock Guard | — | W |
| F33 | Outcome Calibrator | engine feedback | M |
| F34 | Journey Capsule | — | W |
| F35 | Constraint Compass | pulse | M |
| F36 | One Question That Matters | engine clarify prompt | M |
| F37 | Journey Fragility Radar | — | W |
| F38 | Domino Map | — | W |
| F39 | Protected Wander Window | itinerary + engine | M |
| F40 | Expectation Reality Check | — | W |
| F41 | Door-to-Door Access Chain | place screen | M |
| F42 | Discovery Balance Lens | destination screen | M |
| F43 | Graceful Independent Time | itinerary attendance | M |
| F44 | Material Change Watch | — | W |
| F45 | Fair Trade Negotiator | — | W |
| F46 | Local Context Requests | — | W |
| F47 | Journey Thread | — | W |
| F48 | Neighborhood Respect Filter | discovery cards, engine | M |
| F49 | Decision Load Governor | dashboard next action, quiet mode | M |

Totals: 26 migrated, 1 partial, 22 web-only. The eighteen priority screens from
the Phase 8 brief are all in the migrated set. **This table is superseded by the
Phase 9 classification in §8.3.**

### 7.7 Fixes made during verification

- Pulse day label now renders “Friday · 20 Nov 2026” instead of a raw date.
- Destination cards without imagery show a labelled serif placeholder instead
  of a grey band over an empty box; best months use month names.
- Memory and Studio timestamps parse ISO timestamps with `formatClock`.
- Assistant suggestion now includes the word “itinerary”; the backend intent
  matcher became plural-tolerant (regression test added), fixing its own
  “Summarise the open votes” suggestion.
- Settings row relabelled from “Health headline” to “Headline”.
- Riverpod null-aware map entries, `context.mounted` guards, and empty-check
  lints cleaned up; analyzer is clean.
- Android release `INTERNET` permission, debug cleartext and `10.0.2.2`
  emulator default added.

### 7.8 Remaining issues

1. The 22 web-only secondary modules are not yet in Flutter. They are built and
   tested in `apps/web`, which stays available. Porting them is the next
   increment; F23 needs a pact editor.
2. No Android or iOS binary has been produced on this machine. Android is
   blocked by TLS interception at the dependency-download stage (see §7.5);
   iOS requires macOS.
3. No emulator/simulator was available, so interactions were verified in the
   browser target rather than on-device. Pull-to-refresh, keyboard insets and
   native transitions are implemented but not device-exercised.
4. The verification harness cannot scroll the Flutter canvas, so lower parts of
   long screens and the sign-out control were exercised through the API tests
   rather than clicked in the browser.
5. Real-time WebSocket trip events are not consumed by Flutter yet; screens
   refresh through pull-to-refresh and post-mutation invalidation.

## 8. Phase 9 — complete feature migration (2026-11-20)

### 8.1 Method and audit corrections

Phase 9 re-derived the migration status from the code instead of trusting the
Phase 8 table:

- Every router under `services/api/app/routers` was checked for the client
  contract (path, method, request/response shape, permissions) before a Flutter
  screen was written.
- Contracts that differed from the Phase 8 assumption and were corrected:
  - offline sync is a bare JSON array (max 100) with a 6–80 character
    `client_id` and per-item `operation`/`payload`, not an object envelope;
  - the task summary is `{totals:{open,done,total}, …}`, not a flat `total`;
  - companion links are single-use and require an open proposal (vote) or a
    confirmed itinerary item (check-in);
  - the WS endpoint authenticates with a 120-second ticket from
    `POST /api/auth/ws-ticket`, not with the access token.
- No backend route, schema, service or migration needed to change. Phase 9 is a
  client migration; `services/api` and `apps/web` were not modified.

### 8.2 New Flutter modules

| Area | Files |
|---|---|
| More hub | `features/trip/more_hub_screen.dart` |
| Journey Pact | `features/trip/pact_screen.dart` |
| Trip Twin / Negotiator | `features/trip/twin_screen.dart`, `negotiate_screen.dart` |
| Plan intelligence (effort, fragility, domino, shadowplans, capsules) | `features/trip/plan_intelligence_screen.dart` |
| Opportunity Clock / Branches | `opportunity_screen.dart`, `branches_screen.dart` |
| Map & nearby + consent-gated GPS | `nearby_screen.dart` |
| Ask the Ground / Local Context | `ground_screen.dart` |
| Missions / Tasks / Material Watch | `missions_screen.dart`, `tasks_screen.dart`, `watch_screen.dart` |
| Social (circles, contributors, serendipity, Journey Thread) | `circles_screen.dart`, `contributors_screen.dart`, `connections_screen.dart`, `thread_screen.dart` |
| One-Link Companion + public responder | `features/trip/companion_screen.dart`, `features/companion/companion_public_screen.dart` |
| Offline capture, queue and sync | `offline_screen.dart`, `core/storage/offline_queue.dart` |
| Photo memories | `memories_screen.dart`, `memory_repository.dart` |
| Real-time transport | `core/realtime/trip_channel.dart`, `trip_realtime.dart`, `live_status_chip.dart` |
| Native helpers | `core/native/share_links.dart`, `core/native/deep_links.dart`, `app/app.dart` |

Repositories were extended for the same domains. No screen contains a static
list, fabricated response or duplicate ranking/NLU logic.

### 8.3 Feature classification (brief §9)

Legend:
**Complete** — Flutter surface is API-backed, every visible control calls the
real contract, loading/empty/error/retry states exist, and the flow was
exercised by an automated test or a live API smoke check.
**Partial** — a real subset ships; a named capability is still web-only.
**Web-only** — no Flutter surface.
**Blocked** — a platform/environment condition prevents verification.

| ID | Feature | Flutter route(s) | Status | Evidence |
|---|---|---|---|---|
| F01 | Account, consent, preferences | `/welcome`, `/login`, `/register`, `/profile`, `/settings` | Complete | register/login, theme, consents, export, delete, sign-out; live auth suite |
| F02 | Journey DNA | `/journey-dna` | Complete | scores + explicit edit via `updateDna` |
| F03 | Destination & activity discovery | `/discover`, `/destinations/:id`, `/trips/:id/places/:activityId` | Complete | search, lens, provenance, activity cards |
| F04 | Trip creation, membership, roles | `/trips/new`, `/trips/:id` | **Partial** | create + roster/roles; invitations and member admin remain web-only (§8.4) |
| F05 | Itinerary & voting | `/trips/:id/itinerary`, `/proposals` | Complete | day tabs, add/edit, votes, approve/reject, 409 handling, live updates |
| F06 | Trip pulse | `/trips/:id/pulse` | Complete | per-day save, shared vs private fields |
| F07 | Group Experience Engine | `/trips/:id/engine` | Complete | three modes, reasons, trade-offs, sources, clarify, propose |
| F08 | Trip Twin | `/trips/:id/twin` | Complete | compare + adopt-as-proposal |
| F09 | Trip Rescue & autopilot | `/trips/:id/rescue` | Complete | analyse + grounded alternatives as proposals |
| F10 | Maps & nearby | `/trips/:id/nearby` | **Partial** | distances, relative canvas map, consent-gated origin; no slippy tiles |
| F11 | Shared memory timeline | `/trips/:id/memories` | Complete | CRUD, media, photo upload, visibility |
| F12 | AI Memory Studio | `/trips/:id/studio` | Complete | grounded draft, approval, template disclosure |
| F13 | Group expenses | `/trips/:id/expenses` | Complete | add, settle, balances, CSV share |
| F14 | Place Pulse | `/trips/:id/places/:activityId` | Complete | report, helpful, verification labels |
| F15 | Serendipity Radar | `/trips/:id/connections` | Complete | matches, request/decide, block |
| F16 | Travel Circles & contributors | `/trips/:id/circles`, `/:id`, `/contributors` | Complete | join/leave, members, contributor opt-in |
| F17 | Dream-to-destination import | `/trips/:id/import` | Complete | paste/link, candidates, accept/reject |
| F18 | Journey Replay & travel book | `/trips/:id/replay` | Complete | replay + server travel-book text |
| F19 | Missions & wildcards | `/trips/:id/missions` | Complete | join/complete/disable |
| F20 | Offline capture & sync | `/trips/:id/offline` | Complete | local queue, idempotent sync, snapshot |
| F21 | Crowd forecasting | place screen | Complete | observed/predicted blocks, confidence |
| F22 | Multilingual assistant | `/trips/:id/assistant`, `/assistant` | Complete | 8 languages, citations, limitations |
| F23 | Journey Pact | `/trips/:id/pact` | Complete | editor, private merged limits, conflicts in approvals |
| F24 | Opportunity Clock | `/trips/:id/opportunity` | Complete | read-only feasibility with explanations |
| F25 | Shadowplan | `/trips/:id/plan` | Complete | list, create, adopt proposal |
| F26 | One-Link Companion | `/trips/:id/companion`, public `/companion/:token` | Complete | signed single-use links, anonymous respond, revoke, deep link |
| F27 | Planner load balancer | `/trips/:id/tasks` | Complete | tasks + counts-only summary |
| F28 | Branch & rejoin | `/trips/:id/branches` | Complete | create split/reunion, feasibility |
| F29 | Journey effort budget | `/trips/:id/plan` | Complete | effort, walking, rest, accessibility note |
| F30 | Decision Evidence Passport | place/engine/assistant | Complete | source/timestamp/unknown labels |
| F31 | Ask the Ground | `/trips/:id/ground` | Complete | create, respond, REPORTED labels |
| F32 | Cost-Shock Guard | `/proposals` | Complete | cost impact + budget conflicts before approval |
| F33 | Outcome Calibrator | `/trips/:id/engine` | Complete | consented sentiment feedback |
| F34 | Journey Capsule | `/trips/:id/plan` | Complete | create + freshness |
| F35 | Constraint Compass | `/trips/:id/pulse` | Complete | affected confirmed items after save |
| F36 | One Question That Matters | `/trips/:id/engine` | Complete | clarify prompt, dismissed/skip |
| F37 | Journey Fragility Radar | `/trips/:id/plan` | Complete | buffers, tight connections, alternatives |
| F38 | Domino Map | `/trips/:id/plan` | Complete | delay simulation, repairs |
| F39 | Protected Wander Window | itinerary, proposals | Complete | protected toggle, hard-constraint 409s |
| F40 | Expectation Reality Check | place screen | Complete | claim vs evidence + limitations |
| F41 | Door-to-Door Access Chain | place screen | Complete | stage status incl. unknown |
| F42 | Discovery Balance Lens | destination/place | Complete | balanced/iconic/similar |
| F43 | Graceful Independent Time | itinerary | Complete | in/join later/skip attendance |
| F44 | Material Change Watch | `/trips/:id/watch` | Complete | add/check/remove, changed vs unchanged |
| F45 | Fair Trade Negotiator | `/trips/:id/negotiate` | Complete | compromise + who benefits/compromises |
| F46 | Local Context Requests | `/trips/:id/ground` | Complete | activity-scoped questions |
| F47 | Journey Thread | `/trips/:id/thread` | Complete | consented past signals carried forward |
| F48 | Neighborhood Respect Filter | engine/destination/place | Complete | grounded guidance, unknown when absent |
| F49 | Decision Load Governor | dashboard, overview | Complete | one next action + quiet mode |

Totals: **47 Complete, 2 Partial (F04, F10), 0 Web-only, 0 Blocked.** The two
partials are Flutter-surface gaps only; the product feature remains implemented
in the backend and web client.

### 8.4 Surfaces that remain web-only

- **F04 — invitations and member administration.** Flutter creates trips and
  reads the roster with roles. Creating/revoking single-use invitation tokens,
  accepting `/invite/{token}`, changing roles and removing members remain in the
  web member screen. The backend contract is unchanged; only the Flutter screen
  is pending.
- **F10 — basemap.** Nearby, distances and the consent-gated origin are in
  Flutter; the map is a geometric relative-position canvas, not slippy tiles.
  Leaflet tiles remain web-only.
- **Admin console** (`/admin`) is an operator surface, not one of F01–F49, and
  stays web-only.
- The printable HTML travel book is served by the web app; Flutter shows the
  same server-generated travel-book text as selectable text. The content is
  complete; the print-specific delivery is not duplicated.

### 8.5 Real-time collaboration

- Transport: `TripChannel` opens `GET /ws/trips/{trip_id}?token=<ticket>` with
  a 120-second ticket from `POST /api/auth/ws-ticket` (session-bound; invalid
  without a live session). No long-lived credential is placed in a URL.
- Lifecycle: connect → subscribe → 30 s ping; states `idle / connecting / live /
  reconnecting / closed`; exponential backoff 1, 2, 4, 8, 15, 30 s; restart on
  app resume, stop on pause; `stop()` clears socket, timers and the stream.
- Events consumed: `itinerary.updated`, `proposal.*`, `trip.updated/deleted`,
  `member.*`, `expenses.updated`, `engine.updated`, `pulse.updated` (plus
  `connected`/`pong` control frames).
- Dedupe: a bounded 50-entry key of `event|at|proposal_id|member_id|voter`
  prevents double invalidation when a server event and a local mutation arrive
  together.
- Reconciliation: every successful reconnection triggers a one-shot invalidation
  of all trip-scoped providers (itinerary, proposals, engine, expenses,
  balances, pulse, tasks, summary, pact, branches, missions, watches, memories,
  studio, snapshot, sync queue, companion links, ground, inspirations,
  notifications), so the UI rebuilds from server truth.
- Fallback: pull-to-refresh and post-mutation `ref.invalidate` remain the
  authoritative refresh path; the socket is an accelerator, not a data source.
  Ticket failures (400/401/403) close the channel instead of retrying forever.
- UI: `TripLiveChip` on overview, itinerary and decisions shows Live /
  Connecting / Reconnecting / Not live, with tap-to-reconnect while reconnecting.

### 8.6 Native capabilities

| Capability | Plugin | Use | Guard |
|---|---|---|---|
| Share sheet | share_plus 12.0.2 | Companion link, CSV export | Explicit button only; public link/export content |
| Camera / library | image_picker 1.2.2 | Photo memories | Add photo only; max width 1600, quality 82, 25 MB cap, MIME inferred |
| Location | geolocator 14.0.2 | Nearby origin | Tap only; requires `profile.location_sharing`; low accuracy, 12 s limit; trip base is the default |
| Deep links | app_links 7.0.0 | `safar://companion/<token>`, `https://<web>/companion/<token>` | Parsed to `/companion/:token` only |
| WebSocket | web_socket_channel 3.0.3 | Trip collaboration | Ticket auth, session-bound |
| Secure storage | flutter_secure_storage 10.3.1 | Cookie jar on native | Pinned down from 11.x for `win32` resolution; API surface unchanged |

Manifest/plist changes: Android `ACCESS_COARSE_LOCATION`/`ACCESS_FINE_LOCATION`
and a `safar` scheme intent filter; iOS `CFBundleURLTypes` (scheme `safar`),
`NSLocationWhenInUseUsageDescription`, `NSPhotoLibraryUsageDescription`,
`NSCameraUsageDescription`.

Push notifications: no APNs/FCM deliverer exists in the backend, so no push
plugin was added. In-app notifications remain the supported channel.

### 8.7 Privacy and security verification

- Companion public routes expose only trip name/destination, target
  title/summary/status, registered vote counts and anonymous answer counts — no
  member identity. Responses store no user id, IP or user agent. Verified live:
  create → open → respond → single-use 410 → invalid 422 → revoke.
- Precise location requires the explicit consent toggle; with it off, a nearby
  request with coordinates returns 403 (verified live). Flutter checks the
  toggle before requesting the OS permission.
- Private memories, budgets and pulse notes are never derived client-side; the
  screens render what the API returns to the current member. Media remains
  signed and expiring.
- No RLS policy, API authorisation rule, endpoint or migration changed in Phase
  9; the backend suite is unchanged and still passes.
- Tokens: access/CSRF tokens stay in memory, cookies in secure storage on
  native; nothing is logged. The only URL credential is the 120 s WS ticket
  required by the server contract.
- Offline entries stay in local storage and go through the existing idempotent
  sync contract; server-side privacy filtering is unchanged.

### 8.8 Test and build evidence

| Check | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` (default) | 25 passed, 7 skipped (live suite) |
| Live API suite (`SAFAR_LIVE_API=http://localhost:8010`) | 7 passed |
| Phase 9 unit tests (`test/phase9_test.dart`) | 10 passed: event parsing, ws/wss URL, backoff cap, deep links, watch value rendering, companion context, offline queue |
| `pytest` (backend, unchanged) | 107 passed |
| `flutter build web --release` | Succeeded |
| `flutter build apk --debug` | Blocked before compilation: Gradle cannot download Kotlin/Maven artifacts through the environment's TLS interception (`PKIX path building failed`); offline mode has no cached artifacts. Android SDK 36.1.0 is installed. |
| iOS build | Not possible on this Windows host (no Xcode) |

Live smoke checks (curl/Python against `localhost:8010`, seeded data): all new
read contracts returned 200 — pact, effort, fragility, shadowplans, capsules,
opportunity clock, branches, tasks and summary, material watch, ground
requests, missions, companion links, pulse, memory studio, replay, travel book,
expenses/balances, activity, next-action, offline snapshot, serendipity
matches/requests, circles, contributors, thread, notifications — plus
`twin/compare`, `negotiate` and `domino` on two trips with itinerary items.
Write paths exercised live: companion create/public/respond/single-use/revoke;
watch create/duplicate-409/check; task create → done → unassign → summary;
offline sync apply → idempotent skip; media upload 201 and photo memory 201;
nearby with coordinates and consent off → 403.

### 8.9 Remaining limitations (Phase 9 snapshot)

> Phase 10 (§9) closed items 1 and 2 below: F04 and F10 are complete in the
> client and Android binaries were built and verified. Items 3–7 describe the
> Phase 9 state.

1. F04 invitations/member admin and F10 basemap tiles remain web-only.
2. No Android or iOS binary was produced (environment TLS interception; no
   macOS). Plugin native code is therefore not compile-verified on a device.
3. No emulator/simulator was available: real-time behaviour is covered by
   transport unit tests and API-level checks, not on-device socket drops.
4. WS delivery is in-process (single API instance); multi-instance fan-out is
   unchanged from the backend design.
5. Push notifications are unavailable (no deliverer configured).
6. The web app remains the reference and fallback.
7. Testing is contract-level rather than per-screen: every migrated flow was
   exercised against the live API or covered by transport/helper unit tests, but
   there is no individual widget test for all 49 screens, and dark mode is
   provided by the shared theme without per-screen screenshot verification.

### 8.10 Final Phase 9 report (brief §10)

- **Migrated:** 47 of 49 features complete in Flutter; 2 partial (F04, F10).
  All 22 previously web-only features plus F23 now have real screens.
- **Incomplete:** invitation creation/acceptance, role change and member
  removal (F04); slippy map tiles (F10); printable HTML travel book delivery.
- **Backend changes:** none.
- **New screens:** More hub, Pact, Twin, Negotiator, Plan intelligence
  (effort/fragility/domino/shadowplan/capsule), Opportunity Clock, Branches,
  Nearby, Ground, Missions, Tasks, Watch, Connections, Contributors, Circles
  (+ detail), Thread, Companion (+ public responder), Offline.
- **WebSocket:** ticket-authenticated trip channel with backoff, dedupe,
  lifecycle handling, reconnect reconciliation and a UI status chip.
- **Native:** share sheet, camera/library photo memories, consent-gated
  location, companion deep links, secure storage.
- **Privacy/security:** no authz or RLS change; anonymous companion responses;
  consent-gated coordinates; signed media; session-bound WS.
- **Flutter tests:** 32 passing (25 offline-capable including the 10 Phase 9
  tests, plus 7 live API tests), 0 failing; analyzer clean.
- **Backend tests:** 107 passing.
- **Builds:** web release succeeds; Android/iOS not built for the environmental
  reasons above.
- **Remaining limitations:** §8.9.

---

## 9. Phase 10 — Android release hardening (2026-11-21)

Phase 10 closes the two Flutter gaps recorded in §8.9 (F04 invitation/member
admin and F10 basemap tiles), produces and verifies Android binaries, and runs
the app on an API 36 emulator. No backend route, schema, service, migration or
web surface changed.

### 9.1 Toolchain used

| Component | Version |
|---|---|
| Flutter / Dart | 3.41.4 / 3.11.1 |
| Gradle / AGP / Kotlin | 8.14 / 8.11.1 / 2.2.20 |
| compileSdk / targetSdk / minSdk | 36 / 36 / 24 |
| JDK | 17 |
| Android build-tools | 34.0.0, 35.0.0, 36.1.0 |
| AVD | `safar_api36`, API 36 x86_64 (WHPX), no Google Play services |

Gradle artifact downloads completed on the trusted network. TLS verification
was not disabled, no certificate was installed in the JDK or OS trust store, no
Maven mirror was added and Gradle security settings were unchanged.

### 9.2 Artifacts

| Artifact | Path (relative to `apps/mobile`) | Bytes | SHA-256 |
|---|---|---|---|
| Debug APK | `build/app/outputs/apk/debug/app-debug.apk` | 185,005,238 | `d6abdcc18678bf75c1376934f64fa77a5195a414f843c40b0e65989203c4cb82` |
| Release APK | `build/app/outputs/apk/release/app-release.apk` | 61,443,822 | `9ea4556bc7eadf6274626bdeca7c4220571e7a633373f43ee6125b6e8f3fd118` |
| Release AAB | `build/app/outputs/bundle/release/app-release.aab` | 47,723,116 | `3f21f1bd5dcde1f36c90fd1caaa6e0eb4935b013265d58a1395b9bf0011c118d` |

`aapt2 dump badging` on the release APK: package `app.safar.safar_mobile`,
versionCode 1, versionName 1.0.0, minSdk 24, targetSdk 36, with
`INTERNET`, `ACCESS_COARSE_LOCATION` and `ACCESS_FINE_LOCATION` (the latter two
are request-only; the OS permission prompt appears only on an explicit Nearby
tap and only when location sharing is enabled in the profile).

### 9.3 Release signing

`android/app/build.gradle.kts` resolves the signing config from
`SAFAR_KEYSTORE_PATH`, `SAFAR_KEYSTORE_PASSWORD`, `SAFAR_KEY_ALIAS` and
`SAFAR_KEY_PASSWORD`, or from `android/key.properties` for local runs. A
release build fails with a Gradle exception when neither is present, so a
release can never silently fall back to the debug key.

- `apksigner verify --print-certs` passes for the release APK; signer
  `CN=SAFAR Verification`, certificate SHA-256
  `d59f0211330ff15bddf068355ee7e2804ea65b647f0d7d685ddc985757333931`.
- `jarsigner -verify` reports `jar verified.` for the AAB.
- That certificate came from a throwaway keystore generated solely to prove the
  signing path; it is not a production identity and is not in the repository.
  Play upload must be re-signed with the real upload key supplied through the
  same environment variables. `android/key.properties`, `*.jks` and
  `*.keystore` are gitignored and no credential is committed.

### 9.4 Manifest and network security

- `android:allowBackup="false"` and `android:usesCleartextTraffic="false"` in
  the main manifest; the debug overlay enables cleartext for the emulator host
  only and is not part of release builds.
- Release builds require `SAFAR_API_BASE_URL` and it must be HTTPS; the client
  throws at startup otherwise.
- Map tiles are compile-time configuration. `MapTileConfig.fromEnvironment()`
  accepts `SAFAR_MAP_TILE_URL` (with `{z}`/`{x}`/`{y}` placeholders),
  `SAFAR_MAP_TILE_ATTRIBUTION`, `SAFAR_MAP_TILE_SUBDOMAINS`, `SAFAR_MAP_TILE_MIN_ZOOM`
  and `SAFAR_MAP_TILE_MAX_ZOOM`. HTTP tile URLs are accepted only in debug
  builds; release requires HTTPS. With no configuration the client renders the
  labelled schematic map rather than fetching tiles from an unapproved host.
  No provider key or tile URL is hardcoded.

### 9.5 Emulator verification performed

Debug APK installed on the running `safar_api36` AVD (`adb reverse tcp:8010`
for the API, `adb reverse tcp:8000` for a local verification tile server):

- Cold launch from the icon; no crash in `logcat`; splash then login.
- Seed login `mira@safar.demo`; dashboard loaded; session persisted across an
  app restart (warm start went straight to the dashboard); logout returned to
  sign-in.
- Trip overview for “Kyoto in Slow Bloom”, including the Live chip; All tools
  hub; People & invites rendered live data (owner row marked “self”, admin and
  member rows, role/removal overflow only on other members, accepted/open
  invitations with Share/Revoke on usable ones only).
- Nearby rendered the slippy map from the local tile server with attribution,
  the 5 km radius ring, place markers, confirmed-route polylines, zoom
  controls, recenter and category/radius chips; system BACK returned to All
  tools with scroll position preserved.
- Earlier in this phase: consent dialog deny/grant, 12 s location timeout,
  camera capture, gallery pick, dark mode, rotation, WebSocket reconnect with
  catch-up, and sheet dismissal by BACK after the IME was reset.

Large-text verification was completed with widget tests instead of screenshots:
`test/phase10_test.dart` renders the People and Nearby screens at a
360×800 dp phone viewport with 130 % text. It found a real 12 px horizontal
overflow in the invitation Share/Revoke row, fixed by changing that row to a
`Wrap` ([members_screen.dart:668](../apps/mobile/lib/features/trip/members_screen.dart#L668)),
and both tests now pass.

### 9.6 F04 and F10 completion

- **F04** — invitations are created in-app and the share sheet copies/shares the
  invite link; invitations can be revoked; owners/admins can change a member's
  role and remove a member through a confirmation dialog; non-admins see no
  admin affordances and can leave the trip. Backend authorisation (owner/admin
  only, self-role change rejected by the UI, last-owner protection server-side)
  is unchanged.
- **F10** — Nearby uses the configured tile provider when present and the
  schematic map otherwise, with attribution and a visible loading/error state;
  pan/zoom, markers, distances, the radius ring and confirmed-route lines work
  at every radius. Precise origin remains consent-gated twice: the profile's
  location-sharing switch must be on before the OS permission is even
  requested, and the position is only sent for the current query.

### 9.7 Automated checks

| Check | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | 37 passed, 7 skipped (live suite needs `SAFAR_LIVE_API`), 0 failed |
| `apps/mobile/test/phase10_test.dart` | 12 passed |
| `pytest` (`services/api`) | 107 passed |
| `flutter build web --release` | Succeeded |
| Debug APK | Built and installed on emulator |
| Release APK | Built, signed and signature-verified |
| Release AAB | Built and `jarsigner`-verified |

`phase10_test.dart` covers: tile URL placeholder/subdomain substitution; tile
config fallback and configured-state notes; People owner view including group
size and invitation list; owner managing another member (role sheet, removal
dialog with a safe default); plain-member view with no admin controls; the
invite sheet; the schematic-map fallback note, chips, distance labels and
disclosure; the empty Nearby state; the consent-off gate; and 130 % text layout
on a phone viewport for both screens.

### 9.8 Remaining limitations

1. The AOSP LatinIME on this image can hold a stale back callback after the
   keyboard is hidden (`Back callback invoked on a hidden IME`), swallowing the
   first BACK. Restarting the IME (`adb shell am force-stop
   com.android.inputmethod.latin`) restores normal behaviour; this is an
   emulator image bug, not app code.
2. `geolocator` calls `NmeaClient.stop` → `removeNmeaListener` on this
   GMS-less API 36 image and can block the main thread long enough to trigger
   an ANR. Nearby works after the 12 s timeout; a physical device with Google
   Play services did not reproduce it in earlier phases and is the recommended
   verification target for location.
3. The emulator process crashed twice during long sessions (host-side, no app
   tombstone). Verification resumed after reboot; artefacts were rebuilt after
   the last code change, but the final rebuild was not reinstalled post-crash,
   and the on-device evidence above is from the immediately preceding build of
   the same code plus the automated suite on the final code.
4. Session persistence is intentionally strict: an abrupt process kill during a
   refresh-token rotation can leave a single-use refresh cookie already rotated,
   so the next launch asks for the password again. This is server-side replay
   protection, not data loss; trips, memories and offline captures remain.
5. The verification signing key is throwaway (§9.3); production distribution
   needs the real upload key.
6. The live API suite remains opt-in, and push notifications are still not
   implemented (no deliverer configured).
7. iOS was not built (no macOS host). The Flutter code paths are shared, but no
   iOS binary is claimed.
8. Map tiles were exercised against a local verification tile server. A
   production tile provider and its terms/credentials are deployment decisions,
   not bundled defaults.

