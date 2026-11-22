# SAFAR — Deep Technical Audit & Implementation Verification

Date: 2026-11-19
Scope: F01–F49, runtime behaviour, data integrity, security, AI authenticity,
UI/UX and end-to-end workflows.

This audit was performed against the running system, not the page inventory.
Every status below is backed by an automated test, a live API probe, a browser
check, or an explicit code inspection. Anything not verified is labelled as such.

> **Phase 5 supersedes the repository numbers in §1:** there are now 55 model
> tables (56 including `alembic_version`), 68 backend tests, and PostgreSQL 16
> is the production target with row-level security. The Phase 5 evidence is in
> §15 and `docs/SECURITY.md`; earlier sections are retained as the Phase 1–4
> record.

## 1. Repository state

| Area | Result |
|---|---|
| Apps | `apps/web` (Next.js 15.5.29 / React 19.3.1), `services/api` (FastAPI 0.115) |
| Screens | 46 page routes under `app/` |
| API | 121 OpenAPI paths / 150 operations + one WebSocket channel |
| Database | 54 tables, Alembic baseline + companion-link revision |
| Automated tests | 49 backend tests (`test_api.py` + `test_audit_fixes.py` + `test_stabilisation.py` + `test_phase4.py`), 12 frontend unit tests |
| Build | `tsc --noEmit` clean; `next build` succeeds (exit 0) |
| Runtime | API `:8010` + production web build `:3010`, seeded demo data |

## 2. What was implemented

* **Foundation**: auth (register/login/logout), per-purpose consent with policy
  version, profile and Journey DNA editing, onboarding, settings, export,
  anonymising deletion, blocks.
* **Trips and decisions**: creation, invitations/roles, versioned itinerary,
  proposals/votes/approval gates, Trip Pulse, Journey Pact, planner tasks,
  branches, capsule and material watches.
* **Intelligence**: three-mode group engine with hard-constraint filtering and
  explanations, Trip Twin, Trip Rescue, fragility/domino/effort analysis,
  fair-trade negotiation, cost-impact estimates, clarifying question.
* **Discovery and place trust**: destination/activity search with lenses and
  hard filters, place detail with Decision Evidence Passport, access chain,
  crowd forecast, community reports, expectation check, respect notes,
  serendipity matching, circles, contributors, Ask the Ground.
* **Journey and memory**: memory timeline with per-memory permissions, Memory
  Studio suggestions and approvals, replay, printable travel book, expenses
  with settlements/export, offline snapshot and idempotent sync, missions,
  dream import, Journey Thread.
* **Operations**: health and capability disclosure, rate limiting, audit log,
  WebSocket events, seeded demo dataset, Alembic migrations, Docker files,
  README and architecture/feature docs.

## 3. Verification performed

### Automated

```
services/api$ python -m pytest -q             → 36 passed
apps/web$ npx tsc --noEmit                     → clean
apps/web$ npx vitest run                       → 2 files, 12 tests passed
apps/web$ npm run build                        → success (exit 0)
services/api$ alembic upgrade head     → fresh DB: 54 tables + alembic_version
services/api$ alembic check            → "No new upgrade operations detected"
services/api$ alembic downgrade base   → clean rollback
```

Backend tests cover: capability honesty, registration consent, member privacy,
engine recommendation-only behaviour, approval gating, member edit denial,
expense reconciliation and currency default, provenance and unknowns, community
report labelling, assistant grounding/limitations, offline idempotency, private
memories, pact limit privacy and merge semantics, ground answer labelling, circle
member privacy, WebSocket membership, invitation single-use/email binding, signed
media, private event metadata, engine budget semantics and all three modes,
no-destination failure, Trip Twin, Trip Rescue validation/non-mutation,
inspiration import, admin rejection, anonymising deletion, DNA consent gating,
constraint compass, reason-free attendance, WebSocket broadcast, and the replay
next-action link. The stabilisation suite adds structural inspiration parsing with
false-positive avoidance, Opportunity Clock read-only honesty, and One-Link
Companion single-use/signed/anonymous + expiry/revocation/scope behaviour.

### Live API smoke

A 67-endpoint feature smoke ran against the seeded Kyoto trip with a real JWT.
65 calls returned the expected 2xx. The two apparent failures were probe
mistakes, not product defects:

* `POST /api/inspirations` → 404: the real route is
  `POST /api/trips/{trip_id}/inspirations` (now covered by a test).
* `POST /api/trips/{trip_id}/rescue/propose` with `items: []` → 422: intentional
  validation; a valid replacement returns 201 (now covered by a test).

### Browser (production build at :3010, API at :8010)

Every authenticated route was loaded and checked for client exceptions and
rendered content:

dashboard · discover · discover/[id] · assistant · profile · settings ·
notifications · thread · circles · circles/[id] · contributors · connections ·
admin · trips/new · invite/[token] · onboarding · trip overview ·
itinerary · voting · pulse · engine · twin · rescue · insights · map ·
places · place detail · evidence redirect · memories · studio · replay ·
expenses · members · pact · tasks · branches · watch · inspirations ·
offline · ground · missions · assistant (trip) · more · opportunity ·
companion · public companion (`/companion/[token]`, answered anonymously) ·
public landing.

Additional live checks: WebSocket `connected` event received with the correct
trip and user; evidence panel expand; watch value formatting for both stored
shapes; engine generation after the copy fix; circle member list; dashboard
active-trip day computation.

Deep-audit browser checks:

* Responsive at 403–459 px: desktop sidebar `hidden lg:flex` is not rendered,
  top tab strip and fixed bottom nav are rendered, `scrollWidth <= innerWidth`
  (no horizontal overflow).
* Accessibility scan: one `h1` per page, correct heading order, no image missing
  `alt`, no unnamed button, no unlabelled form input.
* Simulated API failure: with `fetch` rejecting during a Pulse save, the UI
  showed “Could not save pulse — Failed to fetch (simulated outage)” and stayed
  usable instead of crashing.
* Skip link, `main#main-content` and a polite live region verified after rebuild.

Constraint: the browser automation viewport exposes no visible screenshot
surface (`NATIVE_BROWSER_VIEWPORT_UNAVAILABLE`), so visual checks were structural
(DOM, computed styles, text) rather than screenshot-based.

## 4. Defects found and fixed during verification

| Defect | Fix |
|---|---|
| Ground responses returned but never persisted | `db.add` + flush in `respond_ground_request` |
| Local contributors blocked by trip-membership check | Contributor status is the gate; trip is still validated, no trip data returned |
| “tomorrow” matched itinerary before weather | Reordered assistant intents so weather terms win |
| `/discover/[destinationId]` crashed (client exception) | Type and page matched the API's flattened destination shape |
| `/circles/[circleId]` crashed (members undefined) | API now returns `members` and post `status`; new regression test |
| Dashboard showed “0 days since it ended” for an active trip | Active-day computation plus “day of the journey” hint |
| `/watch` printed raw JSON for opening hours | Human-readable formatter for hours/price/step-free, both stored shapes |
| `/missions` printed raw constraint keys | Purposeful chips (cost, effort, focus, access) |
| `/itinerary` showed “1 items” | Correct pluralisation in day chips and version snapshots |
| Engine copy read “is a everyone wins pick” | Article selection fixed; covered by a test |
| `/api/health` reported `external_ai` from an unused key | Always false; truth lives in `/api/assistant/capabilities` |
| Production could create schema without migrations | `create_all` skipped when `ENVIRONMENT=production` |
| Invitation tokens were reusable and not email-bound | accept 409 after first use, 403 for a different email; preview reports `accepted_by_you` |
| `/media/...` was served unauthenticated | HMAC-signed URLs with 12 h expiry; unsigned/tampered requests 403 |
| Memory Studio events leaked private memory metadata | `visible_events()` filters unless every referenced memory is visible (studio and replay) |
| Default budget comfort acted as a hard cap | only a stated `budget_limit` filters; comfort is a soft ranking signal |
| Expense currency was required | defaults to the trip currency |
| Completed-trip next action linked to a missing route | links to `/trips/{id}/memories/replay` |
| Production secret could keep the development default | startup refuses default/short `SECRET_KEY` when `ENVIRONMENT=production` |
| Toasts were not announced to assistive technology | `role="status" aria-live="polite"` on the toast container |
| No keyboard bypass of navigation | “Skip to content” link targeting `main#main-content` |

No P0 (data-loss or unauthenticated cross-tenant read/write) defect was found in
this pass. The invitation and media issues were the highest-severity findings and
are fixed and regression-tested.

### Stabilisation pass (2026-11-19)

| Change | Verification |
|---|---|
| Metadata text below 12 px raised (`.eyebrow` and inline labels) | `tsc`, build, browser |
| Error toasts use `role="alert"`; other toasts `role="status"`; container labelled “Notifications” | browser DOM |
| F17 extraction rewritten as structural parsing: word-boundary phrases, URL text stripped before entity match, link-path destination match, hashtags, currency budgets, travel windows; still proposals only | `test_inspiration_import_parses_structure_and_avoids_false_positives` |
| F24 Opportunity Clock: new read-only service/router/page with honest open/closed/unknown/passed states and no plan mutation | `test_opportunity_clock_is_read_only_and_honest`; live API; browser |
| F26 One-Link Companion: signed, scoped, single-use, expiring links + anonymous response surface + migration `b1f6c2d84e71` | two companion tests; live create/context/respond/reuse; browser answer + success + 410 + 404 |

Database verification after the pass: `safar.db` has 54 tables including
`companion_links` and `companion_responses`; a live response row exists with only
`id, link_id, value, comment, created_at`, and the companion audit rows carry
`user_id = NULL`.

## 5. Security and privacy review

* All mutating trip routes resolve membership and role before acting. A
  non-member receives 404 on every trip-scoped route (verified live).
* Private member fields are omitted by serializers, not just concealed.
* Proposal approval re-checks pact and per-member hard budget; conflicts 409
  without revealing amounts.
* JWT verified on every request and on the WebSocket handshake; inactive,
  deleted and non-member users are rejected before `accept`.
* Deletion anonymises profile, memories, notifications, blocks and email, and
  revokes the existing token (test).
* Admin endpoints require `is_admin`; a normal user gets 403 (test).
* Rate limiting middleware applies per client; CORS is an explicit allow-list.
* Media upload validates MIME type and size; reads require a valid HMAC
  signature and expire after 12 h.
* No secret is read by the client bundle; only `NEXT_PUBLIC_API_URL` is public.
  `OPENAI_API_KEY` exists but no service uses it; health reports `external_ai: false`.
* Audit rows are written for approvals, verification, blocks, joins and
  moderation.
* Remaining gaps: no email verification/password reset (no mail provider), no
  RLS SQL policies, no APM/error monitoring, JWT in `localStorage` (XSS
  exposure), no CSRF token (header token mitigates).

## 6. Feature-by-feature verification (F01–F49)

Statuses: **COMPLETE** = UI + API + persistence + permissions + a verification
path exist. **PARTIAL** = a real subset ships but a named capability is absent.
**NOT IMPLEMENTED** = no surface claims it.

Fields per row: backend, frontend, persistence, permissions, automated test,
runtime probe, authenticity/gaps.

| ID | Feature | Status | Backend | Frontend | Persistence | Permissions | Automated | Runtime | Authenticity / gaps |
|---|---|---|---|---|---|---|---|---|---|
| F01 | Account, Consent & Preferences | COMPLETE | `auth`, `users` routers | `/register`, `/login`, `/onboarding`, `/profile`, `/settings` | users, profiles, consents, audit | self-only; admin deletion blocked | registration consent, deletion + token revoke, admin 403 | API smoke + browser | real JWT/auth; no email verification or reset |
| F02 | Journey DNA | COMPLETE | `GET/PUT /me/dna` | profile, onboarding | journey_dna | self-only | explicit edit clamp, unknown dimension 422, consent-gated feedback | API smoke | rule-based scores; no ML inference (by design) |
| F03 | Destination & Activity Discovery | COMPLETE | destinations, activities search | `/discover`, `/discover/[id]`, trip places | catalog tables | public catalog; trip checks on trip routes | provenance/report tests | API smoke + browser | curated seed data, labelled; no live inventory |
| F04 | Trip Creation, Membership & Roles | COMPLETE | trips, members, invitations | `/trips/new`, members, invite | trips, trip_members, invitations | owner/admin/member gates | invite single-use/email, member patch denial | API smoke + browser | n/a; no email delivery (links only) |
| F05 | Collaborative Itinerary & Voting | COMPLETE | itinerary, proposals, votes, versions, attendance | `/itinerary`, `/voting` | itinerary + proposals + votes + audit | approval gate; admin-only role changes | proposal gate, member denial, WS membership + broadcast | API smoke + browser | deterministic; no CRDT merge |
| F06 | Trip Pulse | COMPLETE | `GET/PUT /pulse` | `/pulse` | trip_pulses | shared fields only; budget/notes private | private fields, constraint compass | API smoke + browser | n/a; group view shows 3/7 shared |
| F07 | Group Experience Engine | COMPLETE | `services/engine.py` | `/engine`, `/insights` | recommendation batches/items | private inputs used, never exposed | 3 modes, explanations, fairness, no mutation, no-destination 422 | API smoke + browser | deterministic rule-based model `safar-group-engine-1.0`; no LLM |
| F08 | Trip Twin | COMPLETE | `/twin/compare`, `/twin/propose` | `/twin` | proposals | membership; adoption needs approval | compare read-only + adoption proposal | API smoke | deterministic comparison; estimates labelled |
| F09 | Trip Rescue & Autopilot | COMPLETE | `/rescue/analyze`, `/rescue/propose` | `/rescue` | proposals | membership; nothing applied directly | empty items 422, valid 201, confirmed plan unchanged | API smoke | heuristic replacement filter; no weather feed |
| F10 | Maps & Nearby Experiences | COMPLETE | `/nearby` | `/map` (Leaflet) | catalog geo | membership | — | API smoke + browser | straight-line distances; no live locations or routing |
| F11 | Shared Memory Timeline | COMPLETE | memory CRUD, media | `/memories` | memories, media files | per-memory visibility | private memory, event metadata, signed media | API smoke + browser | local disk; signed URLs |
| F12 | AI Memory Studio | COMPLETE | suggest-events, caption, approve | `/memories/studio` | memory_events | creator/admin approval; visibility filter | event privacy + approval; caption `ai_generated: false` | API smoke + T | template captions, no generative AI |
| F13 | Group Expenses | COMPLETE | expenses, balances, export | `/expenses` | expenses, shares | membership; split validation | reconcile, mismatch 422, currency default | API smoke + browser | deterministic arithmetic; no FX conversion |
| F14 | Place Pulse | COMPLETE | place reports, verify | place detail | place_reports | contributor/admin verification | provenance + REPORTED labelling; aggregate `verification` | API smoke + T + browser | REPORTED ≠ VERIFIED; “moderator-checked”, never official; no external verification |
| F15 | Serendipity Radar | COMPLETE | `/serendipity/*` | `/connections` | connections | opt-in, reciprocal, blocks | — | API smoke | rule-based matching; no exact locations |
| F16 | Travel Circles & Contributors | COMPLETE | circles, contributors | `/circles`, `/circles/[id]`, `/contributors` | circles, members | public member fields only | circle member privacy | API smoke + browser | seeded circles; no messaging |
| F17 | Dream-to-Destination Import | PARTIAL | `/trips/{id}/inspirations` | `/inspirations` | saved_inspirations | trip membership | structural parsing + false-positive regression | API smoke | structural text parsing (phrase boundaries, link paths, hashtags, budgets); no OCR/link fetch/image understanding (labelled) |
| F18 | Journey Replay & Travel Book | COMPLETE | `/replay`, book | `/memories/replay` | memories, events | visibility filters | private excluded from replay | API smoke + browser | deterministic; printable HTML only |
| F19 | Travel Missions & Wildcards | COMPLETE | `/missions*` | `/missions` | missions | owner/admin can disable | — | API smoke | template-generated; self-reported |
| F20 | Offline-First Capture & Sync | COMPLETE | snapshot, `/sync` | `/offline`, `/sync` | local queue (persist) | private fields excluded | idempotent sync | API smoke | SW caches shell (production only); no background sync |
| F21 | Predictive Crowd Forecasting | COMPLETE | `crowd_forecast` | place detail | place_reports | membership | 8-report threshold + ESTIMATED/PREDICTED + confidence test | API smoke + T + browser | statistical bucket mean; needs ≥8 reports, otherwise `insufficient_data`; predicted is ESTIMATED, never verified; no external provider (by design) |
| F22 | Multilingual Travel Conversation | PARTIAL | `/assistant/*` | `/assistant`, trip assistant | retrieval only | trip/public scoping | grounded + limitations | API smoke | retrieval, English only; locale stored, explicit note |
| F23 | Journey Pact | COMPLETE | `GET/PUT /pact` | `/pact` | journey_pacts | individual limits private | merge/privacy + 409 conflicts | API smoke + browser | n/a |
| F24 | Opportunity Clock | COMPLETE | `services/opportunity.py`, `GET /trips/{id}/opportunity-clock` | trip `/opportunity` | read-only; no writes | trip membership | read-only + honest-state test | API smoke + browser | deterministic; hours + travel estimates, `provenance: ESTIMATED`, `plan_unchanged: true` |
| F25 | Shadowplan | COMPLETE | `/shadowplans` | `/insights` | shadowplans | membership | — | API smoke | backups only; never auto-applies |
| F26 | One-Link Companion | COMPLETE | `services/companion.py`, `/trips/{id}/companion-links*`, public `/companion/{token}` | trip `/companion`, public `/companion/[token]` | companion_links, companion_responses | signed scoped token; anonymous response has no identity | single-use/signed/anonymous + expiry/revocation/scope tests | API smoke + browser (answer, 410 reuse, 404 tamper) | HMAC-SHA256, 5 min–7 d TTL, no user id/IP/UA columns; response audited anonymously |
| F27 | Planner Load Balancer | COMPLETE | `/tasks`, `GET /trips/{id}/tasks/summary` | `/tasks` | planner_tasks | membership/assignee; summary counts only | summary parity + privacy test | API smoke + T + browser | server-side counts match planner; no titles/descriptions in summary |
| F28 | Branch & Rejoin | COMPLETE | `/branches` | `/branches` | branches | membership | — | API smoke | feasibility estimates; plan untouched |
| F29 | Journey Effort Budget | COMPLETE | `/effort` | `/insights` | computed | membership | — | API smoke | deterministic; protected blocks count as rest |
| F30 | Decision Evidence Passport | COMPLETE | place detail + citations | place detail | catalog/reports | membership | provenance assertions | API smoke | sources/unknowns separated; estimates labelled |
| F31 | Ask the Ground | COMPLETE | `/ground-requests*` | `/ground` | requests + answers | opted-in contributors | contributor gate + REPORTED label | API smoke | self-reported observations |
| F32 | Cost-Shock Guard | COMPLETE | proposal impact | `/voting` | proposals | approval gate | approval gate test | API smoke | estimates; amounts never exposed on conflict |
| F33 | Outcome Calibrator | COMPLETE | activity/recommendation feedback | place detail, engine | activity_feedback | consent + personalisation gates | consent-gated DNA update | API smoke | deterministic deltas; no ML |
| F34 | Journey Capsule | COMPLETE | `/capsules` | `/insights` | capsules | membership | — | API smoke | timestamped snapshot with freshness |
| F35 | Constraint Compass | COMPLETE | pulse PUT response | `/pulse` | computed | private inputs respected | compass payload test | API smoke | deterministic |
| F36 | One Question That Matters | COMPLETE | engine `clarifying_question` | `/engine`, `/pulse?date=` | batch meta | names only members who have not answered | dynamic coverage + null-case test | API smoke + T + browser | only raised when an unshared pulse could change the top result; answer or skip |
| F37 | Journey Fragility Radar | COMPLETE | `/fragility` | `/insights` | computed | membership | — | API smoke | deterministic |
| F38 | Domino Map | COMPLETE | `/domino` | `/insights` | computed | membership | — | API smoke | deterministic |
| F39 | Protected Wander Window | COMPLETE | protected items + `services/schedule.py` | `/itinerary`, `/engine`, `/rescue` | itinerary_items | hard constraint in engine/propose/patch/approval/twin/rescue | five `test_f39_*` tests | API smoke + T + browser | reserve-time dialog; engine lists kept blocks/free windows; 409/422 on violation |
| F40 | Expectation Reality Check | COMPLETE | `/places/{id}/expectation` | place detail | computed over evidence | membership | — | API smoke | compares claims to evidence; states limitations |
| F41 | Door-to-Door Access Chain | COMPLETE | `access_chain` | place detail | catalog | membership | unknown handling | API smoke + browser | unknown stages labelled |
| F42 | Discovery Balance Lens | COMPLETE | search `lens` | `/discover/[id]`, trip places | computed | membership | — | API smoke | deterministic ranking |
| F43 | Graceful Independent Time | COMPLETE | attendance endpoint | `/itinerary` | itinerary_attendance | self, no reason stored | reason-free attendance test | API smoke | n/a |
| F44 | Material Change Watch | COMPLETE | `/material-watch*` | `/watch` | material_watches | trip membership | — | API smoke | check reports changed/unchanged |
| F45 | Fair Trade Negotiator | COMPLETE | `/negotiate` | `/twin` | computed | private constraints hidden | `for_date` past/today/future/outside test | API smoke + T + browser | deterministic trade-offs scored for the requested trip day |
| F46 | Local Context Requests | COMPLETE | shared with F31 | `/ground` | requests + answers | contributor opt-in | ground tests | API smoke | REPORTED (unverified) |
| F47 | Journey Thread | COMPLETE | `/me/thread` | `/thread` | consented signals | self-only | — | API smoke | repeat/modify/avoid only with consent |
| F48 | Neighborhood Respect Filter | COMPLETE | respect notes | discovery, engine, place detail | catalog flags | public guidance | engine grounding test | API smoke + T + browser | curated guidance; `unknown` when absent; not automated exclusion |
| F49 | Decision Load Governor | COMPLETE | `/next-action`, quiet mode | dashboard, trip header | notifications | per-user | replay link test | API smoke + browser | one next action; notifications suppressible |

## 7. AI/ML authenticity audit

| Component | What it actually is | External AI? | Honesty controls |
|---|---|---|---|
| Group Experience Engine | Deterministic weighted scoring over curated attributes, member DNA, pulse, budget and distance; explicit hard filters | No | `model_version`, ranking formula, excluded count, uncertainties, disclosure that travel times are estimates |
| Everyone Wins / Your Turn / Surprise Us | Three weightings of the same deterministic ranker | No | Mode label and explanation prefix match the actual mode |
| Trip Twin / Rescue / Domino / Fragility / Effort | Deterministic comparisons and heuristics over catalog + itinerary | No | Every output says comparison-only or proposal-only; estimates labelled |
| Assistant / multilingual answers | Grounded retrieval over trip and catalog rows with citations | No | `external_ai: false`; limitations and “translation not configured” notes |
| Memory Studio captions | Template composition from memory metadata | No | Drafts require approval; no generated claims |
| Dream import | Keyword/tag matching against destinations and activities | No | Image/link understanding explicitly reported as not configured |
| Crowd forecast | Bucket mean over timestamped reports | No | Requires ≥8 reports; otherwise `insufficient_data` with the latest observation |
| Journey DNA | Explicit edits plus consented sentiment deltas | No | Feedback changes DNA only with feedback + personalisation consent |

Data honesty: the catalog is curated seed data labelled `ESTIMATED` unless a
verified source exists; community input is labelled `REPORTED (unverified)`;
demo accounts and trips are seeded demo data, not presented as production
activity. No advertised AI capability is static or hardcoded to fake a result,
and no endpoint invents a response when inputs are missing (engine returns 422,
forecast returns `insufficient_data`, assistant states unknowns).

## 8. End-to-end workflows A–O

| Workflow | Result | Evidence |
|---|---|---|
| A. Register / login / onboarding | Pass | registration consent test, deletion test, live register/login, browser onboarding |
| B. Profile + Journey DNA | Pass | DNA edit/clamp/unknown-dimension test, consent-gated feedback test, browser profile |
| C. Trip create / invite | Pass | invite creation + RBAC tests, live trip creation |
| D. Join via invite link | Pass | single-use 409, email-bound 403, correct-email 200 tests; invite page states |
| E. Activities / itinerary collaboration | Pass | proposal approval gate, member edit denial, versions, WS broadcast test |
| F. All three engine modes | Pass | three-mode test: mode label, explanation, fairness, no mutation |
| G. Trip Twin | Pass | read-only compare + proposal-only adoption test |
| H. Disruption + Trip Rescue | Pass | empty replacement 422, valid replacement 201, confirmed plan unchanged |
| I. Expenses and calculations | Pass | split reconciliation, mismatch 422, currency default tests |
| J. Memories / timeline | Pass | private memory exclusion, signed media, event metadata privacy tests |
| K. Privacy and permissions | Pass | cross-user trip 404 (live), member field privacy, circle/pact privacy, admin 403 |
| L. Realtime multi-user | Pass | two WebSocket clients receive `pulse.updated`; non-member upgrade rejected |
| M. Mobile / desktop | Pass (structural) | 403–459 px: bottom nav shown, sidebar hidden, no horizontal overflow; `lg` breakpoints; a11y scan |
| N. Unavailable API / network failure | Pass | simulated fetch failure on Pulse save → error toast, UI usable; `ErrorState` + retry used across pages |
| O. Offline | Pass (API), partial (shell) | snapshot + idempotent sync test, private fields excluded; service worker caches shell only in production and was not exercised offline in this session |

## 9. UI/UX audit

Strengths: one shared design system (`Card`, `Button`, `Badge`, `ErrorState`,
`PageSkeleton`, `FlowNote`), consistent editorial typography and colour tokens,
route-level loading skeletons, empty states, human-readable error states with
retry, responsive navigation with a bottom bar on small screens, and progressive
disclosure through the “More” hub instead of an overloaded header.

Improvements made in this pass: skip-to-content link, `main` landmark id, a
polite live region for toasts, all metadata text raised to at least 12 px, and
per-toast `role="alert"` for errors inside the labelled live region.

Remaining P3 suggestions: add an automated axe/Playwright accessibility pass;
capture visual regression screenshots once a real browser viewport is available.

No unnecessary redesign was performed. Existing working screens were preserved.

## 10. Honest status summary

* **COMPLETE: 47 features.** F01–F16, F18–F21, F23–F49 — every feature except
  F17 and F22 (see below).
* **PARTIAL: 2 features.** F17 (structural text import, but no OCR/link fetch or
  image understanding) and F22 (English-only answers because no translation
  provider is configured). Both state the limitation in the product.
* **NOT IMPLEMENTED: 0 features.** F21, F27, F36, F39, F45 and F48 were
  completed and verified in Phase 4 (see §14).
* Every partial capability is labelled in the UI or documented; none is faked.
* Docker configuration is provided but was not built here (Docker unavailable).

See `docs/FEATURE_REGISTRY.md` for the per-feature evidence table.

## 11. Remaining external dependencies (intentionally absent)

| Dependency | Effect | Product behaviour |
|---|---|---|
| LLM provider | No generative answers/captions | Deterministic retrieval; template captions with approval |
| Weather API | No real forecast | Assistant/rescue state weather is unknown; rescue is user-driven |
| Translation service | No translated answers | Locale stored; answers English with explicit note |
| Live routing/traffic | No routed ETAs | Travel times are estimates, always labelled |
| Live availability/ticketing | No booking | Curated catalog labelled `ESTIMATED` unless verified |
| Object storage | Media on local disk | Type/size validation; signed, expiring URLs |
| Email/SMS delivery | No outbound messages | Invitations are shareable links; in-app notifications only |

## 12. Recommended next steps

1. Add external providers behind the existing service interfaces: weather for
   rescue and assistant, translation for F22, object storage for media.
2. Add Sentry/APM, structured JSON logging and a backup/restore runbook.
3. Add Playwright end-to-end tests (including offline and visual regression).
4. Ship RLS policies for Supabase and review them with the application-level
   checks as defence in depth.
5. Move the JWT out of `localStorage` (httpOnly cookie + CSRF token) if the
   deployment’s XSS posture requires it.

See `docs/FEATURE_REGISTRY.md` for the per-feature registry and the deep-audit
addendum.

## 13. Phase 3 — Complete Feature Validation & Integration Testing (2026-11-19)

Scope: validate that SAFAR works as one integrated platform, without adding
features. Every check below was executed against a running build; nothing is
inferred from the existence of a page or button.

### 13.1 Environment and evidence

| Layer | Configuration |
|---|---|
| API under test | `services/api` on `127.0.0.1:8011`, fresh seeded `validation_run.db`, `SAFAR_SEED=1`, `external_ai:false` |
| Empty-DB API | second process on `127.0.0.1:8012`, fresh `empty_run.db`, `SAFAR_SEED=0` |
| Web | production build (`next build`, `next start`) on `:3010`, `NEXT_PUBLIC_API_URL=http://localhost:8010` |
| Demo API | seeded `safar.db` on `:8010` (browser sign-in as `mira@safar.demo`) |
| Harnesses | `validate.py` (F01–F16, 97 checks), `validate2.py` (F17–F34, 78), `validate3.py` (F35–F49, 63), `validate4.py` (journeys + integrations, 38), `validate5.py`/`validate5b.py` (reliability, 40) |

Results: **275/276 feature checks pass** (the single failure is F48, described
below), **38/38 journey and integration checks pass**, **40/40 reliability
checks pass** after correcting two harness assumptions (seeded Jonas is already
a Kyoto admin, so isolation must use a fresh outsider account; and editing a
signed companion link's stored expiry invalidates the signature, so 404 is the
correct rejection there). `pytest`: 36 passed. `vitest`: 12 passed. `tsc
--noEmit`: clean. `next build`: clean.

Browser coverage: 51 URL loads in the production build — all 47 page routes,
dynamic trip/destination/circle/place/activity instances, the two auth redirects
(`/login`, `/register` → `/dashboard` when signed in), the legacy
`evidence/[activityId]` → `places/[activityId]` redirect, and one deliberate 404
(`/nowhere-404-check`, which correctly renders Next's 404). No route crashed and
no route rendered an application error. The only client-side errors observed were
the catalog 422s described in 13.2, and they disappeared after the fix (console
verified empty on a fresh page load).

### 13.2 Defects found and fixed in this phase

| Defect | Severity | Impact | Fix | Verification |
|---|---|---|---|---|
| Four trip pages requested `/api/activities/search?limit=100` while the API accepts `limit ≤ 60` | **High** (functional) | `watch`, `branches`, `ground`, `insights` received 422 and their activity pickers were empty; watching, grounding, branching and domino simulation could not select an activity | `apps/web/app/(app)/trips/[tripId]/{watch,branches,ground,insights}/page.tsx` now request `limit: 60` | Live API 200 at 60 vs 422 at 100; rebuilt and re-loaded all four pages — lists populated, console clean |
| Offline sync silently skipped a reused `client_id` whose payload had changed, returning the old `applied` outcome with no record | **Medium** (correctness) | A retried-but-edited capture could be lost while the client believed it synced | `routers/memories.py`: reused id with different operation/payload now returns `rejected` with a reason; identical retries still `skipped` | Reliability R7: applied 1 → skipped 1 → edited rejected; no schema change needed (`offline_sync_queue.payload` already stores content) |
| Generic non-Latin assistant questions received no translation disclosure (the note was only attached to named-activity answers) | **Medium** (honesty) | Users could read an English answer with no indication that translation was unavailable | `services/assistant.py`: `answer()` appends the translation limitation whenever a non-Latin message produced no `language_note` | F22 probes: named and generic non-Latin inputs both carry the note |

A 422 on invitation preview for expired tokens was also checked and is correct
(HTTP 410 is returned, matching the documented contract).

### 13.3 Journeys

| Journey | Result | Evidence |
|---|---|---|
| **A — Individual traveller**: discover → destination → create trip → generate → customise → save memories | Pass | Destination search discovered Kyoto; new account created an empty future trip; engine produced a batch without touching the confirmed plan; approved proposal created the first item; version incremented; memory persisted and appeared on the timeline (P4, 10 checks) |
| **B — Group travel**: create group → invite → preferences → engine → three modes → finalise | Pass | Bound invitation accepted; member pulse changed group ranking; all three modes returned differentiated explanations; approval finalised the plan; collaborator could not approve as if owner (P4/B) |
| **C — Trip management**: itinerary → modify → expenses → change → Rescue → persist | Pass | Item edit persisted with a new version; equal split reconciled; rescue analyse/propose returned proposals only; confirmed itinerary unchanged until approval (P4) |
| **D — During travel**: trip interface → opportunity clock → capture → offline → sync | Pass | Opportunity clock read-only (`plan_unchanged: true`); capture and offline snapshot; identical sync retry skipped; edited reuse rejected (P4, R7) |
| **E — Post-trip**: memories → organise → constellation → replay → privacy | Pass | Studio grouped memories and required approval; a private memory and any event referencing it were absent from another member's replay; travel book generated (P4) |

### 13.4 Cross-feature integrations

All ten requested integrations were exercised end-to-end against the API and,
where visual, in the browser:

| # | Integration | Result | Failure mode probed |
|---|---|---|---|
| I1 | Journey DNA ↔ recommendations | Pass | DNA change moved ranking without fabricating fit; consent-gated |
| I2 | Group pulse ↔ engine | Pass | A single member's shared pulse re-ordered group results; private fields stayed hidden |
| I3 | Trip Twin ↔ itinerary | Pass | Comparison was read-only; adoption produced a proposal, not a silent edit |
| I4 | Rescue ↔ constraints | Pass | Accessibility/pace constraints honoured in replacement candidates |
| I5 | Place Pulse ↔ discovery | Pass | Provenance labels propagated; community rows stayed `REPORTED` |
| I6 | Memory Constellation ↔ Replay | Pass | Private-memory events excluded from both surfaces |
| I7 | Expenses ↔ membership | Pass | Member join re-weighted splits and balances consistently |
| I8 | Circles ↔ connections | Pass | Reciprocal acceptance required; blocked users excluded |
| I9 | Opportunity Clock ↔ itinerary | Pass | Confirmed items deducted from free windows; nothing written |
| I10 | One-Link Companion ↔ group participation | Pass | Anonymous vote/check-in counted in the proposal result; identity never stored |

### 13.5 Per-feature validation table

Status legend: ✅ verified working in this phase · 🟡 working subset, named gap.
Evidence legend: **P1–P3** live API suites, **P4** journeys/integrations,
**R** reliability suite, **B** browser, **T** pytest. Database values are the
tables actually touched.

| Feature | Status | Frontend | Backend | Database | Integration | Tests | Issues |
|---|---|---|---|---|---|---|---|
| F01 Account, consent, preferences | ✅ | `/register`, `/login`, `/onboarding`, `/profile`, `/settings` | `routers/auth.py`, `routers/users.py` | users, profiles, consent_records, user_blocks | — | P1, T, B | None found |
| F02 Journey DNA | ✅ | `/profile`, `/onboarding` | `routers/users.py`, `services/discovery.py` | journey_dna, activity_feedback | I1 | P1, T, B | None |
| F03 Discovery | ✅ | `/discover`, `/discover/[id]`, trip places | `routers/places.py`, `services/discovery.py` | destinations, places, activities, place_sources | I5 | P1, B | None |
| F04 Trips, roles, invites | ✅ | `/trips/new`, `/trips/[id]`, `/members`, `/invite/[token]` | `routers/trips.py` | trips, trip_members, trip_invitations | I7 | P1, R4, T, B | Invite preview for expired tokens returns 410 as designed |
| F05 Itinerary, proposals, voting | ✅ | `/itinerary`, `/voting` | `routers/itinerary.py` | itineraries, itinerary_items, itinerary_versions, itinerary_proposals, itinerary_approvals, activity_votes | I3, I10 | P1, P4, T, B | None |
| F06 Trip Pulse | ✅ | `/pulse` | `routers/pulse.py` | trip_pulse | I2 | P1, P2, B | Private budget/notes never returned to other members |
| F07 Group Experience Engine | ✅ | `/engine`, `/insights` | `services/engine.py`, `routers/engine.py` | recommendation_batches, recommendations, trip_pulse | I1, I2, I3, I4 | P1, T, B | Engine payload has no `place` object, so it cannot show F48 respect notes |
| F08 Trip Twin | ✅ | `/twin` | `routers/twin.py` (service layer) | itinerary_items, recommendations | I3 | P1, B | None |
| F09 Rescue & Autopilot | ✅ | `/rescue` | `services/rescue.py` | itinerary_items, itinerary_proposals, journey_pacts | I4 | P1, P4, T, B | Does not branch on `is_protected` (see F39) |
| F10 Maps & nearby | ✅ | `/map` | `routers/places.py` (`/nearby`) | places, activities | I5 | P1, B | Static straight-line distances only, labelled |
| F11 Memory timeline | ✅ | `/memories` | `routers/memories.py` | trip_memories, memory_permissions | I6 | P1, T, B | None |
| F12 Memory Studio / Constellation | ✅ | `/memories/studio` | `services/memory_studio.py`, `routers/memories.py` | memory_events, trip_memories | I6 | P1, T, B | Template captions still send `ai_generated: true` (carry-over, cosmetic) |
| F13 Expenses | ✅ | `/expenses` | `routers/expenses.py` | expenses, expense_participants, expense_settlements | I7 | P1, P4, T, B | None |
| F14 Place Pulse | ✅ | `/places/[activityId]`, trip places | `routers/places.py`, `routers/admin.py` | places, place_reports, place_sources | I5 | P1, T, B | Admin verify keeps `provenance: REPORTED` with `verified: true` (carry-over, wording) |
| F15 Serendipity Radar | ✅ | `/connections` | `routers/serendipity.py` | traveller_matches, connection_requests | I8 | P1, T, B | None |
| F16 Circles & contributors | ✅ | `/circles`, `/circles/[id]`, `/contributors` | `routers/circles.py`, `routers/contributors.py` | travel_circles, circle_members, circle_posts, local_contributors | I8 | P1, B | None |
| F17 Dream-to-Destination Import | 🟡 | `/inspirations` | `services/discovery.py` | saved_inspiration | — | P2, T, B | Structural parsing only; no OCR, image understanding or link fetching |
| F18 Replay & Travel Book | ✅ | `/memories/replay` | `routers/memories.py` | trip_memories, memory_events | I6 | P2, P4, T, B | None |
| F19 Missions & wildcards | ✅ | `/missions` | `routers/missions.py` | trip_missions, user_missions | — | P2, B | None |
| F20 Offline capture & sync | ✅ | `/offline` | `routers/memories.py`, `services/offline.py` | offline_sync_queue, trip_memories | — | P2, R7, T, B | Fixed this phase: edited reuse of a client id is rejected, not silently skipped |
| F21 Crowd forecasting | 🟡 | place detail | `services/places.py` | place_reports, place_sources | I5 | P2, B | Needs ≥8 reports; otherwise `insufficient_data` with the latest observation |
| F22 Multilingual assistant | 🟡 | `/assistant`, trip assistant | `services/assistant.py` | trips, itinerary, place data, catalog | — | P2, T, B | English-only; fixed this phase so every non-Latin question carries the translation limitation |
| F23 Journey Pact | ✅ | `/pact` | `routers/pact.py` | journey_pacts | I4 | P2, T, B | None |
| F24 Opportunity Clock | ✅ | `/opportunity` | `services/opportunity.py`, `routers/pulse.py` | activities, itinerary_items, trips | I9 | P2, T, B | Read-only by design; 422 outside trip dates |
| F25 Shadowplan | ✅ | `/insights` | `services/optimizer.py` | shadowplans | — | P2, B | None |
| F26 One-Link Companion | ✅ | `/companion`, `/companion/[token]` | `services/companion.py`, `routers/companion.py` | companion_links, companion_responses | I10 | P2, R5, T, B | Tokens are not listed after creation by design |
| F27 Planner load balancer | ✅ | `/tasks` | `routers/tasks.py` | planner_tasks | — | P2, B | No server-side balance summary endpoint (carry-over) |
| F28 Branch & rejoin | ✅ | `/branches` | `routers/branches.py` | trip_branches | — | P2, B | None |
| F29 Effort budget | ✅ | `/insights` | `services/optimizer.py` | itinerary_items, activities | — | P2, B | None |
| F30 Evidence Passport | ✅ | `/places/[activityId]`, assistant citations | `services/places.py` | place_sources, place_reports | I5 | P2, T, B | None |
| F31 Ask the Ground | ✅ | `/ground` | `routers/trips.py` | ground_requests, ground_responses | — | P2, T, B | None |
| F32 Cost-Shock Guard | ✅ | `/voting` | `services/engine.py` (impact) | recommendations, trip_pulse | — | P2, T, B | None |
| F33 Outcome Calibrator | ✅ | place detail, `/engine` | `services/feedback.py` | activity_feedback, journey_dna | I1 | P2, T, B | None |
| F34 Journey Capsule | ✅ | `/insights` | `routers/capsules.py` | journey_capsules | — | P2, B | None |
| F35 Constraint Compass | ✅ | `/pulse` | `routers/pulse.py` | trip_pulse, itinerary_items | I2 | P3, B | Skips protected items by design |
| F36 One Question That Matters | ✅ | `/engine` | `services/engine.py` | trip_pulse, recommendations | I2 | P3, B | Conditional and lives in `meta.clarifying_question`; `null` on seeded data because top scores were not within 4 |
| F37 Fragility Radar | ✅ | `/insights` | `services/optimizer.py` | itinerary_items, trips | — | P3, B | None |
| F38 Domino Map | ✅ | `/insights` | `services/optimizer.py` | itinerary_items | — | P3, B | None |
| F39 Protected Wander Window | 🟡 | `/itinerary` | protection flags in itinerary, effort, fragility, compass, domino | itinerary_items.is_protected | — | P3, B | Enforced in effort rest, fragility, compass exclusion and domino repair wording; `services/rescue.py`/`engine.py` never read `is_protected`; no dedicated reserve-window wizard |
| F40 Expectation Reality Check | ✅ | place detail | `services/places.py` | places, place_sources, place_reports | I5 | P3, B | None |
| F41 Access Chain | ✅ | place detail | `services/places.py` | places (access JSON) | — | P3, T, B | Unknown stages stay explicitly unknown |
| F42 Discovery Balance Lens | ✅ | `/discover/[id]`, trip places | `services/discovery.py` | activities, destinations, journey_dna | I1 | P3, B | None |
| F43 Graceful Independent Time | ✅ | `/itinerary` | `routers/itinerary.py` | itinerary_attendance, itinerary_items | — | P3, T, B | None |
| F44 Material Change Watch | ✅ | `/watch` | `routers/watches.py` | material_watch, activities | — | P3, B | Catalog picker fixed this phase (limit 100→60) |
| F45 Fair Trade Negotiator | ✅ | `/twin` | `services/rescue.py` | recommendations, itinerary_items, journey_pacts | I3 | P3, B | Evaluates constraints against `date.today()`; options must be generated for today |
| F46 Local Context Requests | ✅ | `/ground` | `routers/trips.py` | ground_requests, ground_responses | — | P3, T, B | Catalog picker fixed this phase (limit 100→60) |
| F47 Journey Thread | ✅ | `/thread` | `routers/users.py` | journey_dna, activity_feedback, saved_inspiration | — | P3, B | None |
| F48 Neighborhood Respect Filter | 🟡 | `/discover`, `/discover/[id]`, place detail (missing `/engine`) | `services/discovery.py`, `services/places.py` | places (fragile flags), activities | I5 | P3, B | `respect_note` never reaches engine recommendations: `recommendation_out` serialises `activity_out` without a place. Discovery and place detail do show it. Registry previously overstated this |
| F49 Decision Load Governor | ✅ | dashboard, trip header, `/notifications` | `routers/trips.py` (`/next-action`) | trips, notifications | — | P3, B | None |

This table records the Phase 3 snapshot. Phase 4 (§14) superseded the noted
issues for F07/F09 (protected time), F12 (`ai_generated`), F14 (verification
wording), F21 (`predicted` state), F27 (summary endpoint), F36 (question
coverage), F39 (hard constraint), F45 (`for_date`) and F48 (engine respect).

### 13.6 Reliability and failure modes

| Scenario | Result |
|---|---|
| Empty database boots | Healthy; `auto_seed:false`; seeded logins 401; destinations `items: []`; first registration, empty DNA and empty trip list all work; unknown destination returns 404 |
| Multiple users / isolation | A fresh outsider gets 404 on overview, itinerary, members, memories, expenses, pulse, and on item/memory writes |
| Concurrent writes | 8 parallel itinerary additions → 8×201, exactly 8 rows, no 500s; 6 parallel pulse updates all 200 |
| Duplicate submissions | Identical offline retry skipped; edited reuse rejected; single-use companion link returns 410 on the second response |
| Invalid / expired invitations | Unknown 404; wrong email 403; used-by-other 403/409; same-user repeat 200; expired preview/accept 410 |
| Companion links | Tampered/malformed 404; used 410; revoked 410; edited expiry invalidates signature (404) |
| Session expiry | Protected routes 401 without/with garbage token; browser session with a corrupted token redirects to `/login?next=%2Fdashboard` and clears auth |
| Network/API failure | Against a dead API, `/companion/[token]` shows “Failed to fetch” with retry (no crash); signing in surfaces “Failed to fetch” inline |
| Large datasets | 100-entry sync accepted (100 applied); 101 rejected 422 with a clear message |
| Broken navigation / crashes | 51 URL loads, no crash; unknown trip id shows an error state with “Try again”; unknown path renders the 404 page |

### 13.7 Assumptions and limits of this validation

* Checks ran on SQLite with seeded demo data; PostgreSQL/Supabase row-level
  security was not exercised (application-level checks were).
* External providers (LLM, weather, translation, routing, email/SMS, object
  storage) remain intentionally absent; probes confirm the product claims and
  labels their absence rather than faking results.
* Concurrency was probed at 6–8 simultaneous local requests, not at production
  scale.
* Browser validation used the production build with desktop viewport; no
  automated accessibility or screen-reader audit was performed in this phase.
* F21's forecast could not be observed in the `predicted` state on seeded data
  (below the 8-report threshold); the `insufficient_data` contract was verified.
* F36's clarifying question was `null` on seeded data because the top-two scores
  were not within the threshold; the conditional field was verified in `meta`.

### 13.8 Recommended next phase

1. Carry `place`/`respect_note` into engine recommendation serialisation and
   surface it on `/engine` (F48), and decide whether rescue/engine should treat
   `is_protected` as a hard constraint (F39).
2. Feed F45's negotiation the caller's day instead of `date.today()`.
3. Add Playwright coverage for the five journeys, including an API-offline run,
   and run the suite against PostgreSQL with RLS enabled.
4. Extend F21 seed/report volume so the `predicted` state is exercised, and add
   a server-side load-balance summary for F27.
5. Move authentication to httpOnly cookies if XSS posture requires it; add
   structured logging, tracing and a backup/restore runbook.

## 14. Phase 4 — Feature Completion & Functional Refinement (2026-11-19)

Scope: close the Phase 3 gaps without adding unrelated features. Every change
below is covered by a regression test and, where it has a UI, was exercised in
a production build.

### 14.1 What changed

| Feature | Change | Files |
|---|---|---|
| F48 | Engine recommendations now include the place, producing a `respect` object (`fragile`, `status`, `guidance`, `provenance`). Guidance is the curated `place.respect_note`; absent notes report `unknown`. The engine page renders the guidance and an honest “no specific guidance” state. | `services/engine.py`, `routers/engine.py`, `apps/web/.../engine/page.tsx` |
| F39 | Protected time is a hard constraint. New shared `services/schedule.py` computes busy/protected windows, free windows, `max_free_minutes` and conflicts. The engine skips candidates that cannot fit the remaining free time (reason `protected_time`/`day_schedule`) and returns 422 when the day has no free window, with `meta.protected_time`. Itinerary add/PATCH, proposal approval, twin adoption and rescue refuse to overlap or remove protected blocks (409). Rescue lists protected items and `protected_respected`. The itinerary “Reserve time” dialog creates protected blocks and requires an end time. | `services/schedule.py`, `services/engine.py`, `services/rescue.py`, `routers/itinerary.py`, `routers/engine.py`, `apps/web/.../itinerary/page.tsx` |
| F45 | `POST /negotiate` scores against the caller's `for_date` instead of `date.today()`; days outside the trip return 422. The twin page sends the selected day. | `services/rescue.py`, `apps/web/.../twin/page.tsx` |
| F36 | The clarifying question names only members without a pulse for that day, is dismissible, and links to `/pulse?date=`, which prefills the day. It is `null` once coverage is complete. | `services/engine.py`, `apps/web/.../engine/page.tsx`, `apps/web/.../pulse/page.tsx` |
| F21 | Predicted state validated with a controlled dataset (below). No production code change was needed; labels and confidence bounds were already honest. | `services/places.py` |
| F27 | `GET /api/trips/{id}/tasks/summary` returns open totals, per-assignee/unassigned counts and descending load for active members — counts only, no titles or descriptions; non-members get 404. The tasks page labels it “counts from the API”. | `routers/tasks.py`, `apps/web/.../tasks/page.tsx` |
| F12 | Caption suggestions return `ai_generated: false`, `generator: "template"` and a template disclosure. | `services/memory_studio.py` |
| F14 | Moderator verification never promotes a community report: it stays `source_type=community`, `provenance=REPORTED`, with a note saying it is “still shown as REPORTED”. The place-detail aggregate now exposes `verification`, so the UI shows “official · verified” or “REPORTED · moderator-checked” rather than a bare “verified”. | `routers/admin.py`, `services/places.py`, `serializers.py`, `apps/web/.../places/[activityId]/page.tsx` |

The only new defect found during Phase 4 browser verification: the place-detail
aggregate omitted `verification`, so a moderator-checked community report
rendered a plain “verified” badge. Fixed by adding the field to
`aggregate_reports` and extending the F14 test to assert it.

### 14.2 Automated evidence

`services/api/tests/test_phase4.py` — 13 tests:

| Test | Proves |
|---|---|
| `test_f48_engine_respect_is_grounded_in_place_data` | Over four days, every fragile recommendation's guidance equals the curated place note (not invented), and fragile places do appear |
| `test_f39_engine_reports_protected_time_and_free_windows` | A 11:00–12:15 protected block yields free windows 09:30–11:00 and 12:15–22:00 and `max_free_minutes` 585 |
| `test_f39_engine_refuses_day_without_free_time` | A protected 08:00–21:30 day returns 422, and recovers to 201 after deletion |
| `test_f39_propose_rejects_protected_overlap` | Overlapping proposals return 409 with `protected: true`; non-overlapping succeeds |
| `test_f39_manual_edits_cannot_overwrite_protected_time` | Add and PATCH overlap 409; protected without end time 422; explicit reserve works |
| `test_f39_twin_adoption_cannot_remove_protected_block` | Twin proposal approval 409 with a protected conflict |
| `test_f39_rescue_never_targets_protected_time` | Rescue on a protected item returns no affected/proposals, lists it as protected and refuses to propose against it |
| `test_f45_negotiation_uses_the_requested_trip_date` | Past, today and future days negotiate; a day outside the trip returns 422 |
| `test_f21_forecast_requires_eight_reports_and_stays_estimated` | 7 reports → insufficient; 8 → `predicted`/PREDICTED/ESTIMATED/not verified with confidence ≤ 0.9; fresher reports raise confidence; inconsistent reports lower it |
| `test_f27_task_summary_matches_planner_and_stays_private` | Summary equals planner arithmetic, has no title/description keys, includes a “counts only” disclosure, and non-members get 404 |
| `test_f12_caption_is_a_template_not_ai` | `ai_generated: false`, template generator, approval required |
| `test_f14_moderator_verification_never_promotes_community_reports` | Community report stays REPORTED/moderator-checked in list and aggregate; official report is VERIFIED |
| `test_f36_question_only_mentions_members_who_have_not_answered` | Coverage is computed dynamically; the question matches it or is null |

Results: **`pytest` 49 passed · `vitest` 12 passed · `tsc --noEmit` clean ·
`next build` clean.**

### 14.3 Browser evidence (production build)

| Screen | Observed |
|---|---|
| Engine (day 2026-11-18) | “Protected time kept / 11:00–12:15 Tea ceremony at Camellia / Suggestions only use the free windows left in the day: 09:30–11:00, 12:15–22:00”; hard constraints list “remaining free time in the day, protected time blocks”; respect guidance on cards; conditional question with skip and `?date=` answer link |
| Itinerary | “Reserve time” dialog (Day, Start, End “Required for protected time”, Protect toggle); protected badge and start–end times |
| Rescue | “Protected time left untouched” with the targeted block after selecting it; replaces only non-protected items |
| Twin | Negotiation request captured with `for_date: "2026-11-20"` |
| Pulse `/pulse?date=2026-11-20` | Page title “TRIP PULSE · NOV 20, 2026” |
| Voting | Proposal impact renders “Protected time: Tea ceremony at Camellia — Protected time cannot be removed by this change.” |
| Tasks | “Load balance — 3 open · counts from the API” with per-assignee and unassigned counts |
| Place detail | Insufficient-data forecast text (“Showing the latest report instead of inventing a prediction”); “No recent traveller reports”; after moderation, “REPORTED · moderator-checked” (never verified fact) |

Console: no errors or assertions on the checked pages. Temporary verification
rows (one report, one protected block, one smoke task) were removed from the
demo database afterwards.

### 14.4 Still partial / unresolved

* **F17** — still no OCR, link fetching or image understanding; explicitly
  labelled in the product.
* **F22** — answers are English-only; no translation provider is configured.
* F21 has no external crowd provider by design; forecasts are bucket statistics
  over reports and say so. Production-scale data was not exercised.
* Validation remains SQLite + seeded demo data; PostgreSQL/RLS and
  production-scale concurrency are still untested.
* No automated Playwright/axe suite yet; browser evidence above is manual.

## 15. Phase 5 — Production Security & Infrastructure Hardening (2026-11-19)

Scope: make the existing application safe and operable for real users without
redesigning the UI or adding travel features. The full report, including the
eight required sections, is `docs/SECURITY.md`; this section records the audit
trail and evidence.

### 15.1 Findings and fixes

| ID | Severity | Finding | Fix | Evidence |
|---|---|---|---|---|
| V1 | High | Tokens in `localStorage`; no server-side revocation; XSS could steal a long-lived credential | HttpOnly access/refresh cookies, opaque refresh tokens hashed at rest, rotation with reuse detection, session check on every request, logout revocation; frontend memory-only | two hardening tests; browser §15.4 |
| V2 | High | No database-level tenant isolation | RLS on 55 tables / 220 policies / FORCE / fail-closed / non-owner role | §15.2; full suite on PG |
| V3 | Medium | Upload trusted declared content type | Magic-byte sniffing → 415 | `test_media_upload_rejects_a_spoofed_content_type` |
| V4 | Medium | No body-size ceiling | 25 MB ASGI limit → 413 | `test_oversized_body_is_rejected_before_validation` |
| V5 | Medium | Raw URL paths (companion/invitation tokens) reached logs | JSON logs, redacted segments, hashed IP, uvicorn access log disabled | `app/core/logging.py`; header test |
| V6 | Medium | Health endpoint exposed internals; no readiness signal | trimmed `/api/health`; `/api/ready` with DB check (503) | `test_health_and_ready_do_not_leak_internals`; live 200 |
| V7 | Medium | CSRF would be introduced by cookie auth | double-submit `safar_csrf` + `X-CSRF-Token`, constant-time compare | `test_cookie_sessions_require_csrf_for_writes` |
| V8 | Medium | `/nearby` accepted precise coordinates without location consent | requires `profile.location_sharing` (403 otherwise) | `test_precise_location_requires_the_privacy_toggle` |
| V9 | Medium | Deletion kept personal learning rows, pulse, memory text/media and private budgets | full erasure + media unlink + anonymised memberships + session/link revocation | `test_account_deletion_erases_personal_data` |
| V10 | Low | No retention for expired sessions/invitations/links/notifications/offline/audit | `services/retention.py`, `scripts/retention.py`, `RETENTION_*` | `test_retention_removes_only_expired_rows` |
| V11 | Low | Missing headers, trusted host, prod docs/CORS guards | security headers, TrustedHost, docs off, `*` rejected | header + host tests |
| V12 | Low | Seed wrote non-canonical consent kinds | canonical five kinds | `app/seed.py` |
| V13 | Low | No dedicated auth/companion/upload budgets | per-(client,bucket) limiter with `Retry-After` | `test_rate_limiter_buckets_and_retry_after` |

Tested with no finding: SQL injection, IDOR (cross-trip 404),
mass assignment (`is_admin`/`role`/`id` ignored), error-detail leakage,
anonymous scope, forged/expired tokens, companion/invitation token abuse.

### 15.2 RLS and PostgreSQL evidence

* Four migrations applied to a fresh PostgreSQL 16.4 database:
  `9c224ee10414` → `b1f6c2d84e71` → `c7d3e9a1f204` → `d9e4f1b2c305`.
* 56 relations (55 model tables + `alembic_version`), 220 policies, 35
  `safar_*` helpers, 55 tables with ENABLE + FORCE RLS, 220 grants to
  `safar_app`.
* Direct SQL as `safar_app` (non-owner, NOBYPASSRLS):
  no context trips **0**; mira **6**; jonas **3**; foreign trip / expenses /
  members **0**; system **9**; audit logs **0** without admin and **85** with
  `app.admin='on'`; spoofed insert rejected with
  `new row violates row-level security policy for table "trips"`.
* Full backend suite: **68 passed** on fresh PG under FORCE RLS (18.59 s) and
  **68 passed** on SQLite (19.71 s).
* Portable types: JSON columns and UTC-naive `DateTime`; no SQLite-only schema
  features. SQLite tests do not prove RLS — that is why the PG run exists.
* Timestamps are UTC-naive in both engines; acceptable now, `timestamptz` is a
  future option (SECURITY.md R10).

### 15.3 Backup and restore evidence

`pg_dump -Fc` produced a 358,169-byte dump; `pg_restore` into a new database
reproduced 56 tables, 220 policies, 55 FORCE-RLS tables and identical row
counts (users 20, trips 7, memories 9); RLS after restore returned 0 without
context and 6 for mira. Media is a Docker volume and is not covered by the
database dump; no WAL/PITR is configured. Full procedure and drill cadence:
`docs/DEPLOYMENT.md` §8.

### 15.4 Session changes and browser evidence

Cookies: HttpOnly `safar_access` (15 min, `/`), HttpOnly `safar_refresh`
(30 days, `/api/auth`, rotated), readable `safar_csrf` + `X-CSRF-Token`.
`Secure` in production, `SameSite=lax` default, `none` requires `Secure`.
WebSocket uses a two-minute `typ: ws` ticket bound to the session.

Production build, 2026-11-19: login at `/login` → `POST /api/auth/login` 200 →
`/dashboard` → `/trips/<id>/itinerary` renders the confirmed plan.
`document.cookie` contains only `safar_csrf`. Sign out → `/login?next=%2Fprofile`,
cookies cleared, `/api/auth/me` **401**, `/api/auth/refresh` **401**.

### 15.5 Remaining risks

External review not performed; Docker images not built (no Docker CLI); TLS
and proxy path untested; rate limiter is per-process; WebSocket token is in the
query string (2-minute ticket, WSS/proxy redaction required); no load testing;
no PITR; prepared PG test mode needs a fresh database; optional monitoring not
configured; seeded demo credentials must stay disabled in production. Full
severity/mitigation table: `docs/SECURITY.md` §7.

### 15.6 Production readiness verdict

**Hardened and PostgreSQL-verified, not production-certified.** The
application-level and database-level controls are implemented and tested on
both engines. Docker/TLS/CI execution, external review, PITR and load
testing remain outstanding, and the claim of production readiness is withheld
until they are completed. Conditions are listed in `docs/SECURITY.md` §8.

## 16. Phase 6 — Premium product UI/UX transformation (2026-11-19)

Scope: visual and interaction quality across the existing product. No API
contract, business rule, auth control or data source was changed. All 49
features keep their status. The design system is documented in
`docs/UI_DESIGN.md`; visual references are in `docs/screenshots/`.

### 16.1 Audit before implementation

- Enumerated all 52 App Router routes (public, auth, app, trip sub-routes) plus
  shared shells (`AppShell`, `TripShell`, `PublicHeader`, `RequireAuth`,
  `TripMap`), every modal, drawer, toast and empty/error/loading state.
- Recorded inconsistencies: mixed raw hex vs token colours, inconsistent card
  radii and padding, icon-only controls without labels, chips without
  pressed state, modals without focus management, duplicate page-header
  implementations, grammar/copy defects, and one itinerary page crash.
- The improvement plan (tokens → primitives → shell → core screens → secondary
  screens → responsive/a11y → verification) was agreed before implementation.

### 16.2 Design system delivered

Single source of truth: `app/globals.css` + `tailwind.config.ts` +
`components/ui.tsx`. Tokens, contrast measurements, type scale, spacing,
radius, elevation, motion, component APIs, patterns and governance rules are
in `docs/UI_DESIGN.md` §2–§8. Highlights:

- 11 semantic colour tokens with light/dark values, alpha-capable.
- Serif display + system sans + tabular numerals; editorial eyebrow tracking.
- `Button`, `LinkButton`, `IconButton`, `Card`, `Badge`, `Field`, `Input`,
  `Textarea`, `Select`, `Modal`, `Toggle`, `SegmentedControl`, `Tabs`,
  `Toasts`, `Skeleton`, `EmptyState`, `ErrorState`, `Stat`, `ScoreBar`,
  `PageHeader`, `SectionTitle`, `Avatar`, `Progress`, `FlowNote`.
- `.eyebrow`, `.card`, `.meta`, `.num`, `.skeleton`, `.scroll-fade-x`,
  `.tap-target`, `ease-editorial`, `shadow-card/lift/float`, `rounded-4xl`.
- Reduced-motion and print rules global.

### 16.3 Screens redesigned (functionality preserved)

| Area | Screens |
|---|---|
| Entry | `/login`, `/register`, `/onboarding`, `/` |
| Core | `/dashboard`, `/discover`, trip overview, `/itinerary`, `/engine`, `/voting`, `/memories` (+ studio, replay) |
| Secondary | `/pulse`, `/rescue`, `/twin`, `/tasks`, `/expenses`, `/map`, `/places`, `/branches`, `/inspirations`, `/opportunity`, `/watch`, `/missions`, `/insights`, `/pact`, `/ground`, `/companion`, `/assistant`, `/members`, `/more`, `/offline`, `/evidence/[activityId]`, `/places/[activityId]` |
| Global | `/trips/new`, `/connections`, `/circles`, `/notifications`, `/thread`, `/profile`, `/settings`, `/admin`, `/search` |

Shell work: fixed sidebar with grouped navigation and active-route indicator,
mobile drawer with focus trap and scroll lock, bottom tab bar, ⌘K command
palette, notification badge, theme switch, offline banner, skip link.

### 16.4 Defects found and fixed in this phase

| Defect | Impact | Fix |
|---|---|---|
| Itinerary crashed with "Rendered more hooks than during the previous render" | Plan page unusable after any day change | `useEffect` moved above the conditional returns |
| Engine meta grid printed "TARGET MEMBER null" | Looked like fabricated data | Empty/null meta values filtered out |
| Dashboard stat hint read "3 / day of the journey" | Copy defect | "days into the journey" |
| Generate button did not name the selected mode | Unclear action | `Generate {active mode label}` |
| Drawer/modal focused via `requestAnimationFrame` | Focus never moved in throttled/hidden tabs | Focus applied synchronously on mount |
| `--faint` measured 4.11:1 on `paper` | Small metadata below WCAG AA | Darkened to 4.68:1 (4.89:1 on `raised`) |
| Chips/toggles lacked selected state semantics | Screen readers could not tell selection | `aria-pressed` / `role="switch"` added across pulse, rescue, engine, voting, memories, branches, places, twin, inspirations, settings, onboarding, profile |

### 16.5 Responsive verification

Method: the in-app browser panel cannot be resized and was hidden during
verification, so the production build was exercised in same-origin iframes at
390, 768, 1024 and 1440px (media queries follow iframe width, cookies are
shared) and, for the final screenshots, in headless Chromium with device
metrics overrides.

- 35+ route × width combinations checked across all major routes; zero elements
  escaped the viewport outside sanctioned horizontal scroll strips; no page
  scrolled horizontally (verified by a no-op `window.scrollTo` at 390px).
- Horizontal scroll is confined to design: trip tab strip and day strip scroll
  internally with a partially visible pill as the affordance.
- Mobile: drawer navigation, bottom tabs, stacked cards, single-column forms,
  full-width primary actions, 16px inputs.
- Tablet: two-column grids, drawer navigation retained below `lg`.
- Desktop: fixed sidebar, three-column grids, sticky controls, 82rem cap.

### 16.6 Interaction and accessibility evidence (production build, :3010)

- Memories: typed a note → Save enabled → saved → "7 moments recorded" + toast;
  opened remove modal → "Keep it" kept the row → confirmed removal → back to
  "6 moments recorded" + toast; textarea reset.
- Itinerary: added "UI verification walk" → toast "Item added" + version 3→4;
  removed it through the confirmation modal → toast "Item removed" + version
  4→5; item absent from the plan; day strip `aria-pressed` correct.
- Voting: vote modal shows three `aria-pressed` chips (Yes/Abstain/No); proposed
  catalog picker exposes `aria-pressed` per activity and enables "Open
  proposal"; "Impact if approved" expands to cost delta, pact conflict and
  protected-time warnings.
- Engine: mode cards `aria-pressed`; generated a batch with toast; feedback chip
  persisted; meta grid contains only populated fields.
- Discovery: labelled search, country/sort selects, interest chips with
  `aria-pressed`, `role="status"` result count, working "Clear filters".
- Drawer: `role="dialog"`, `aria-label`, focus lands inside on open, `Tab`
  trapped, Escape closes, body scroll locked and restored.
- Modal: panel focused on open (verified after the fix), first `Tab` goes to the
  close control, `aria-modal="true"`, labelled by its title.
- Focus ring, skip link, reduced-motion rule and switch semantics confirmed by
  DOM/computed-style inspection.
- No "Application error", "Failed to fetch" or console-visible crash on any
  checked route.

Environment note: in a hidden browser tab, rAF-driven exit animations do not
complete, so unmounting dialogs/drawers can appear "stuck" during automated
inspection. State changes, toasts, API writes and data refreshes complete
immediately; behaviour in a visible tab is normal. This is a measurement
artifact of the automation environment, not a shipped regression.

### 16.7 Remaining UI issues (honest)

1. No automated accessibility scan (axe/Lighthouse) was run; findings are
   manual. A CI job should run axe on the route matrix.
2. `IconButton` hit area is 36px. It meets WCAG 2.5.8 AA (24px) but not the
   AAA 44px target; `.tap-target` exists for cases that need 44px.
3. The trip tab and day strips hide their scrollbars; on very narrow phones a
   partially visible pill is the only cue that more tabs exist.
4. Mobile screenshots of long pages are capped at 6000px (engine mobile);
   content below the cap is omitted from the image, not from the page.
5. Dark mode is implemented and token-complete but was spot-checked, not
   exhaustively photographed; no per-screen contrast audit of dark mode was run
   beyond the token table.
6. Toast copy stacks when many actions are performed quickly; no queue limit
   was exercised.
7. High-density desktop (>1600px) keeps the 82rem container by design; it does
   not scale cards further.

### 16.8 Automated evidence

- `npx tsc --noEmit` — clean.
- `npx vitest run` — 2 files, 12 tests passed.
- `npx next build` with `NEXT_PUBLIC_API_URL=http://localhost:8010` — clean,
  all 52 routes compiled.
- Production server on :3010 against API :8010; login, navigation, writes and
  refetches verified as above.
- Screenshots (headless Chromium, real data, logged-in session) in
  `docs/screenshots/`: dashboard (desktop/mobile), discover (desktop/mobile),
  trip overview (desktop), itinerary (desktop/mobile), engine (desktop/mobile),
  voting (desktop), memories (desktop/mobile), pulse (desktop), rescue
  (desktop).

## 17. Phase 7 — Advanced AI/ML intelligence and real-world integrations (2026-11-20)

Scope: strengthen the intelligence layer and add carefully bounded provider
integrations without replacing working deterministic systems. Full design and
evaluation record: `docs/AI_ML_ARCHITECTURE.md`.

### 17.1 Defects found and fixed in this phase

| Defect | Impact | Fix |
|---|---|---|
| `/api/health` reported engine `1.0` and assistant `1.0` after both versions changed | Operators and probes saw stale model versions | health now imports `ENGINE_VERSION` (`safar-group-engine-1.5`) and the assistant `GENERATOR` (`safar-grounded-i18n-2.0`) |
| Engine page eyebrow was hardcoded “v1.0” | UI disagreed with the batch’s `model_version` | eyebrow renders the batch version, defaulting to v1.5 |
| Dream Import link-path host matching kept `www.` in `source_hosts` | Host provenance looked inconsistent | normalised host handling and assertions |
| Crowd forecast response mixed observed reports with predictions | Prediction could be read as measurement | v2 returns separate `observed` (REPORTED) and `predicted` (ESTIMATED) blocks; the old `forecasts` key no longer exists in the predicted payload |
| Assistant evaluation probes used prompts that matched a higher-priority intent | Tests measured the wrong path, not a product defect | probes reworded to unambiguous intents; `intent` is now asserted explicitly |
| Capability endpoint test searched for the literal string “api_key” | Documentation legitimately names `OPENAI_API_KEY` in an inert note | test now asserts no secret value, no `sk-` prefix and no value/token/secret fields in provider states |

### 17.2 Component verification

| Component | What was verified | Evidence |
|---|---|---|
| Journey DNA | Existing consent-gated deltas unchanged; feedback now also produces a bounded aggregate ranking nudge | `test_phase7_recommendations.py` (consent, small-group disable, no leakage) |
| Group Experience Engine | Hard constraints still filter first; three modes preserved; feedback adjustment ≤ ±4; diversity selection bounded; `meta.evaluation` complete | 5 Phase 7 recommendation tests; live Everyone Wins batch: Jain 0.999, least-served 72.7, spread 6.5, violations 0, 3 primary tags, similarity 0.42 |
| Grounded assistant | Place facts use catalog and reports, state recorded hours and explicitly refuse live availability; privacy intent returns policy only; every probe returns `mutation="none"` | `test_phase7_evaluation.py`; live place/privacy answers |
| F22 multilingual | Eight languages, detection source, mixed/unsupported notes, destination names preserved, approval flags | 12 tests in `test_phase7_multilingual.py`; live `¿Cuál es el plan para hoy?` → Spanish, Hindi → Hindi |
| F21 forecasting | Threshold honesty, observed/predicted separation, MAD outliers, 120-day cap, stale flag, hierarchical fallback, 80% intervals, labels | 5 tests in `test_phase7_forecasting.py`; existing F21 test updated to v2; live Nishiki Market predicted card |
| F17 Dream Import | Spans, candidate ids, review workflow, disabled link honesty, local OCR, media scoping and SSRF rejection | 10 tests in `test_phase7_dream_import.py` |
| Provider layer | Keys never returned, defaults make no outbound call, disabled providers degrade honestly | `test_provider_capabilities_expose_no_secrets`; `/api/ai/capabilities` live |
| UI | Engine metrics, selection reasons and feedback disclosure render; place crowd card renders observed summary, interval, confidence and predicted label | browser checks against API 8011 on :3011 |

### 17.3 Automated and live evidence

- `pytest` — **106 passed** (38 Phase 7 tests across five files) on SQLite.
- `npx tsc --noEmit` — clean.
- `npx vitest run` — 12 passed.
- `next build` with `NEXT_PUBLIC_API_URL=http://localhost:8010` — clean, all routes.
- Live API on :8011: capabilities (LLM disabled, no external network), assistant
  in English/Spanish/Hindi, privacy policy answer, engine batch with evaluation
  and feedback learning, forecast with observed/predicted separation.
- Live UI on :3011: engine page shows “V1.5”, fairness/satisfaction/violations/
  diversity tiles and “Consented feedback used…”; place page shows 9 observed
  reports, predicted levels with intervals and moderate confidence.

### 17.4 Remaining limitations (honest)

1. No external LLM is wired. Free-form generative answers are absent by design;
   the assistant answers from records and templates.
2. Weather was verified in its disabled state only; the Open-Meteo adapter was
   not exercised against the live endpoint in this environment.
3. Link metadata was verified disabled and through SSRF unit probes; no real
   page fetch was performed with `SAFAR_LINK_FETCH_ENABLED=true`.
4. OCR depends on a server-side Tesseract binary; tests cover the adapter and
   failure messaging, and skip extraction when the binary is absent.
5. Forecast calibration uses synthetic buckets; there is no production crowd
   dataset, so interval coverage is validated on controlled fixtures only.
6. Translation is template-local, not a general translation model; unsupported
   phrasing outside the lexicons falls back to English with a note.
7. Latency is measured on local SQLite with the seeded catalog, not under load.
8. Recommendations remain explainable heuristics; no learned ranker was added,
   so evaluation is against rules and fixtures rather than online outcomes.

### 17.5 Verdict

Phase 7 meets its stated goal: F17 and F22 are implemented and tested, F21
uses a robust and honest forecasting model, and ranking gains measurable
fairness/diversity/feedback improvements without sacrificing explainability.
No paid provider or key is enabled, no private data leaves the deployment, and
every prediction remains labelled as such.
