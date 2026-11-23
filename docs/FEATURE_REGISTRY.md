# SAFAR — Feature Registry (F01–F49)

Honest status for every feature in the master prompt. "Implemented" means the
UI, API, persistence, permissions and at least one verification path exist.
"Partial" means a real, working subset ships but a named capability is missing.
"Not implemented" means no product surface claims to do it.

Legend: ✅ Implemented · 🟡 Partial · ⛔ Not implemented

Verification sources:

* **T** — automated tests in `services/api/tests/` (132 tests across 11 test modules:
  `test_api.py`, `test_audit_fixes.py`, `test_stabilisation.py`, `test_phase4.py`,
  `test_security_hardening.py`, `test_phase7_dream_import.py`, `test_phase7_forecasting.py`,
  `test_phase7_multilingual.py`, `test_phase7_recommendations.py`,
  `test_phase13_step6_observability.py`, `test_phase13_step6_focused_verification.py`),
  `apps/web/tests/*.test.ts` (12 Vitest tests), and `apps/mobile/test/` (61 unit and
  widget tests). The backend suite passes on SQLite and on Supabase PostgreSQL 17 with
  row-level security enforced under the restricted `safar_app` role.
* **B** — manually exercised in a production build in a browser against the
  seeded demo data (every `(app)` route was loaded and checked for runtime
  errors and content).
* **P** — Phase 13 Step 7 comprehensive production readiness assessment sign-off
  (`docs/PHASE13_STEP7_PRODUCTION_READINESS_REPORT.md`).

All automated tests pass on the commit this registry describes.

---

## Foundation — F01 to F22

| ID | Feature | Status | Where | Verification / notes |
|---|---|---|---|---|
| F01 | Account, Consent & Preferences | ✅ | `routers/auth.py`, `routers/users.py`; `/register`, `/login`, `/onboarding`, `/profile`, `/settings`, `settings_screen.dart` | **T** `test_registration_grants_only_required_consent`; per-purpose consent with policy version `2026-01`, profile, native JSON archive export (`FileExporter`), anonymising delete, blocks. **B** settings/profile. |
| F02 | Journey DNA | ✅ | `GET/PUT /api/me/dna`; profile + onboarding | Scores 0–10, explicit edits; feedback changes DNA only with feedback consent **and** personalisation consent (`services/feedback.py`). **B** profile. |
| F03 | Destination & Activity Discovery | ✅ | `/api/destinations*`, `/api/activities/search`; `/discover`, `/discover/[id]`, trip places search | Hard filters then ranking; lens balanced/iconic/similar; provenance and freshness labels. **B** both discovery routes incl. evidence toggle. |
| F04 | Trip Creation, Membership & Roles | ✅ | `/api/trips*`, members, invitations; `/trips/new`, trip members | Owner/admin/member roles, invite tokens single-use and email-bound, expiry, removal, role changes. **T** invite reuse 409 and foreign-email 403. **B** create form, members, invite page. |
| F05 | Collaborative Itinerary & Voting | ✅ | itinerary + proposals + votes + versions + attendance; `/itinerary`, `/voting` | **T** proposal approval gate, member PATCH denial, WebSocket membership. Versions audited, changes notified, realtime events. **B** both screens. |
| F06 | Trip Pulse | ✅ | `GET/PUT /api/trips/{id}/pulse`; `/pulse` | Per-member energy/time/radius/interests shared; budget comfort and notes private. **B** group shows 3/4 shared, private fields labelled. |
| F07 | Group Experience Engine | ✅ | `services/engine.py`; `/engine`, `/insights` | **T** all three modes return explained recommendations with fairness spread and never change confirmed items; a stated budget limit is a hard filter while budget comfort is soft; no destination returns an explicit 422 instead of fabricated results. Three modes, clarifying question (F36). **B** engine. |
| F08 | Trip Twin | ✅ | `/twin/compare`, `/twin/propose`; `/twin` | Day comparison (fit, cost, time, travel) read-only; adoption opens a proposal. **B** twin. |
| F09 | Trip Rescue & Autopilot | ✅ | `/rescue/analyze`, `/rescue/propose`; `/rescue` | Rain, closure, traffic, fatigue, budget shock, lost time; replacements are proposals only. **B** rescue. |
| F10 | Maps & Nearby Experiences | ✅ | `/nearby`, Leaflet map; `/map` | Straight-line distances from the shared trip base; no live member locations or routing. **B** map. |
| F11 | Shared Memory Timeline | ✅ | memory CRUD + media + permissions; `/memories`, `memories_screen.dart` | **T** private memory and its studio/replay event metadata excluded from other members; unsigned media URLs rejected (403), signed URLs expire. Upload validates type and 25 MB cap. **Native Mobile:** On-device microphone voice recording (`record` WAV 44.1kHz), live duration, audio preview player (`audioplayers`), gallery video selection, and reliable Dio multipart upload with progress tracking and `CancelToken` cancellation. **B** memories. |
| F12 | AI Memory Studio / Constellation | ✅ | `/memory-studio`, suggest-events, caption, event approval; `/memories/studio`, `studio_screen.dart` | Deterministic event grouping and grounded caption drafts; every draft requires approval. Captions return `ai_generated: false`, `generator: "template"` and a “not AI-generated” disclosure. Events referencing a private memory are hidden from other members. **Native Mobile AI:** On-device 128-d dense perceptual image feature extraction (`ImageFeatureExtractor`), local cosine similarity matching sheet, on-device speech-to-text dictation (`SpeechTranscriber`), and honest capability reporting. No external LLM or cloud vision API. **T** `test_f12_caption_is_a_template_not_ai`, `batch2_master_test.dart`. **B** studio. |
| F13 | Group Expenses | ✅ | expenses, balances, export; `/expenses`, `expenses_screen.dart` | **T** splits reconcile; custom split mismatch returns 422. Native CSV export (`FileExporter`); settlement suggestions. **B** expenses. |
| F14 | Place Pulse | ✅ | place detail, reports, helpful, verify; `/places/[activityId]` | **T** `test_f14_moderator_verification_never_promotes_community_reports`: a moderator-verified community report stays `source_type=community`, `provenance=REPORTED` with “still shown as REPORTED”; only official-source reports become VERIFIED. The place-detail aggregate now carries `verification`, so the UI shows “official · verified” or “REPORTED · moderator-checked” instead of a bare “verified”. **B** place detail. |
| F15 | Serendipity Radar | ✅ | `/api/serendipity/*`; `/connections` | Opt-in, reciprocal, blocked users excluded; mutual acceptance before contact; no exact locations. **B** connections. |
| F16 | Travel Circles & Local Contributors | ✅ | `/api/circles*`, `/api/contributors*`; `/circles`, `/circles/[id]`, `/contributors` | **T** circle detail lists members with only `user_id/display_name/role` (regression fixed). **B** all three screens. |
| F17 | Dream-to-Destination Import | ✅ | `/inspirations`, `services/discovery.py`, `import_screen.dart` | Structural parsing plus stable `candidate_id`, `source_span` and provenance per candidate. Optional SSRF-guarded link metadata; trip-scoped media safety. **Native Mobile:** Image gallery/camera selection, preview, remove/replace, and on-device OCR extraction via Google ML Kit Text Recognition (`google_mlkit_text_recognition`) into editable draft text before candidate extraction. Accept/reject review before anything becomes a proposal. **T** 10 tests in `test_phase7_dream_import.py`, `batch2_master_test.dart`. |
| F18 | Journey Replay & Travel Book | ✅ | `/replay`, `/travel-book`; `/memories/replay`, `replay_screen.dart` | **T** private memories excluded. **Native Mobile:** Editorial multi-page PDF Travel Book generation directly on-device (`PdfTravelBookGenerator` via `pdf` and `printing`), luxury coffee-table magazine layout (warm ivory, charcoal, terracotta, multi-page daily chronicles, expense summary, memoir colophon), native cache storage (`FileExporter.saveBytesToCache`), Android document viewer open and share sheet. HTML export retained as secondary option. **T** `batch1_export_test.dart`, `batch2_master_test.dart`. **B** replay. |
| F19 | Travel Missions & Wildcards | ✅ | `/missions*`; `/missions` | Generated, optional, self-reported; owner/admin can disable. **B** missions (constraint chips rewritten for readability). |
| F20 | Offline-First Capture & Sync | ✅ | `/offline`, `/sync`; `/offline` | **T** sync is idempotent and private fields are excluded from the snapshot; identical retries are skipped, while reusing a `client_id` with a different operation or payload is rejected with a reason. JSON snapshot download; local queue in Zustand; service worker. **B** offline. |
| F21 | Predictive Crowd Forecasting | ✅ | `services/places.py` `crowd_forecast`; place detail | `bucket-forecast-v2`: ≥8 eligible crowd reports in 180 days, hard age cap 120 days, `stale` flag above 60, MAD outlier rejection, hierarchical fallback (`weekday_bucket → weekday → day_type_bucket`) with explicit granularity, 80% interval and calibrated confidence. Observed reports (`REPORTED`) and predictions (`ESTIMATED`) are separate blocks; below thresholds the response stays `insufficient_data` with the latest observation. **T** 5 tests in `test_phase7_forecasting.py`; existing `test_f21_*` updated to v2. **B** place detail (predicted Nishiki Market card live: 9 reports, intervals, moderate confidence). |
| F22 | Multilingual Travel Conversation | ✅ | `/api/assistant/*`, `services/assistant.py`, `services/language.py`; `/assistant`, trip assistant | Eight languages (en, es, fr, de, pt, it, hi, ja) with script detection and stopword scoring, multilingual intent lexicons, localised answer templates, mixed-language and unsupported-language notes, and preferred-language selection. Every answer carries a context pack, citations with provenance, `mutation="none"` and `requires_approval` where a proposal is the next step. Destination and activity names stay verbatim. No message leaves the server; no external translation or LLM provider. **T** 12 tests in `test_phase7_multilingual.py`; live Spanish and Hindi answers verified. |

## First additive expansion — F23 to F34

| ID | Feature | Status | Where | Verification / notes |
|---|---|---|---|---|
| F23 | Journey Pact | ✅ | `GET/PUT /api/trips/{id}/pact`; `/pact` | **T** individual limits are private per member and merged, not replaced. Conflicts block proposal approval with 409. **B** pact. |
| F24 | Opportunity Clock | ✅ | `services/opportunity.py`, `GET /api/trips/{id}/opportunity-clock?on=`; trip `/opportunity` | Read-only feasibility for a chosen day: catalog opening hours parsed, confirmed itinerary deducted, 08:00–22:00 free gaps intersected with opening windows and haversine + `travel_minutes` estimates. Every item is `open_now` / `later_today` / `no_window` / `closed_today` / `unknown` / `window_missed` with an explanation and `provenance: ESTIMATED`. Response includes `plan_unchanged: True` and the confirmed version; nothing is written. 422 outside trip dates. **T** `test_opportunity_clock_is_read_only_and_honest`. **B** `/opportunity` (live: 16 candidates, 5 open now). |
| F25 | Shadowplan | ✅ | `/shadowplans`; `/insights` | Backups attached to confirmed items; engine/rescue can surface them; never changes the confirmed plan. **B** insights. |
| F26 | One-Link Companion | ✅ | `services/companion.py`, `/api/trips/{id}/companion-links*`, public `/api/companion/{token}`; trip `/companion`, public `/companion/[token]` | HMAC-signed `{link_id}.{expiry}.{sig}` tokens scoped to one vote or check-in, 5 min–7 day TTL, single-use, revocable. Public context returns only trip name/destination, target title/summary/status, registered vote counts, anonymous response count and options — no member identity. Responses are stored without user id, IP or user agent; audit row has `user_id=None`. Invalid/tampered 404, expired/revoked/used 410, closed target 409, bad value 422. **T** two tests: single-use/signed/anonymous and expiry/revocation/scope. **B** created a link, answered anonymously, saw the “Answer recorded” screen, then the friendly 410 page on reuse and 404 page for a tampered token. |
| F27 | Planner Load Balancer | ✅ | `GET /api/trips/{id}/tasks/summary`; `/tasks` | Optional planning tasks with assignment. The server-side summary returns open totals, per-assignee and unassigned counts and a descending load list — counts only, never task titles, descriptions or private member data — and any active member may read it. **T** `test_f27_task_summary_matches_planner_and_stays_private` (matches the planner, no title/description keys, disclosure, non-member 404). **B** tasks (“Load balance — 3 open · counts from the API”). |
| F28 | Branch & Rejoin | ✅ | `/branches`; `/branches` | Split groups with reunion place/time and estimated travel feasibility; does not touch the confirmed plan. **B** branches. |
| F29 | Journey Effort Budget | ✅ | `/effort`, `services/optimizer.py`; `/insights` | Walking km, transitions, effort points, rest; protected blocks count as rest; accessibility constraints never traded. **B** insights. |
| F30 | Decision Evidence Passport | ✅ | place detail + assistant citations; `/places/[activityId]` | Source, timestamp, cost/travel assumptions, reports, group suitability, unknowns shown separately. **T** provenance assertions. **B** place detail. |
| F31 | Ask the Ground | ✅ | `/ground-requests*`; `/ground` | **T** opted-in contributor required; answers stored and labelled `REPORTED (unverified)`; responses persist. **B** ground. |
| F32 | Cost-Shock Guard | ✅ | proposal impact `cost_impact`; `/voting` | Per-member estimate shown before approval; hard budget conflicts block approval without exposing amounts. **T** approval gate. **B** voting. |
| F33 | Outcome Calibrator | ✅ | activity + recommendation feedback; place detail, engine | Optional sentiments (loved / would return / okay / not for me / too expensive / too far) update DNA only with consent. Phase 7 adds a bounded engine nudge: groups of ≥3 with ≥2 consented raters receive at most ±4 points, explained in `why_selected` and disclosed in `meta.feedback_learning`; no individual sentiment, user id or member name is returned. **T** consent gating plus 5 tests in `test_phase7_recommendations.py`. |
| F34 | Journey Capsule | ✅ | `/capsules`; `/insights` | Timestamped snapshot with `stale_after`; UI shows freshness. **B** insights. |

## Latest additive expansion — F35 to F49

| ID | Feature | Status | Where | Verification / notes |
|---|---|---|---|---|
| F35 | Constraint Compass | ✅ | `PUT /pulse` → `constraint_compass`; `/pulse` | Updating today's pulse returns a summary plus exactly which confirmed items are affected. **B** pulse. |
| F36 | One Question That Matters | ✅ | engine `clarifying_question`; `/engine`, `/pulse?date=` | The question names only members who have not shared a Trip Pulse for the requested day, and is null once coverage is complete. Each question has a stable key, can be dismissed, and its answer link prefills the pulse date. **T** `test_f36_question_only_mentions_members_who_have_not_answered` asserts dynamic coverage and the null case. **B** engine (question with skip + `?date=` link); pulse page shows the prefilled day. |
| F37 | Journey Fragility Radar | ✅ | `/fragility`; `/insights` | Buffers, tight connections, risky schedules, alternative timings. **B** insights. |
| F38 | Domino Map | ✅ | `/domino`; `/insights` | Ripple effects for a chosen item and delay: affected vs unaffected, repairs needed. **B** insights. |
| F39 | Protected Wander Window | ✅ | `itinerary_items.is_protected`, `services/schedule.py`; `/itinerary`, `/engine`, `/rescue` | Protected blocks are hard constraints everywhere: the engine excludes overlapping candidates and returns 422 when the day has no free window, with `meta.protected_time` listing kept blocks and free windows; propose/add/PATCH and twin-proposal approval return 409 for protected overlaps; Rescue excludes protected items, reports `protected`/`protected_respected` and refuses to propose against one; cancelling a protected item in a proposal is blocked. A protected block requires an end time; the itinerary “Reserve time” dialog creates one. **T** five `test_f39_*` tests (engine windows and refusal, propose rejection, manual edits, twin adoption, rescue). **B** itinerary + reserve dialog, engine protected block, rescue “Protected time left untouched”. |
| F40 | Expectation Reality Check | ✅ | `/places/{id}/expectation`; place detail | Compares a claim against catalog evidence, official info, reports and unknowns; states limitations. **B** place detail. |
| F41 | Door-to-Door Access Chain | ✅ | `access_chain` in place detail; phase 5 UI | Transport → path → entrance → experience → facilities → return, with status per stage and unknown handling. **T** place detail unknowns. **B** place detail. |
| F42 | Discovery Balance Lens | ✅ | search `lens`; `/discover/[id]`, trip places | Iconic / similar / balanced; dreams are never dismissed, only compared. **B** discovery. |
| F43 | Graceful Independent Time | ✅ | attendance endpoint; `/itinerary` | “I'm in / Join later / Skip” with no reason required; attendance recorded per item. **B** itinerary. |
| F44 | Material Change Watch | ✅ | `/material-watch*`; `/watch` | Watches on hours/price/step-free; check returns changed vs unchanged; values rendered readably after a fix. **B** watch. |
| F45 | Fair Trade Negotiator | ✅ | `/negotiate`; `/twin` | Two options → compromise with explicit who-benefits/who-compromises trade-offs; private constraints never shown. Negotiation scores against the requested trip day (`for_date`, defaulting to today only when omitted) and rejects days outside the trip with 422; the twin page sends the selected day. **T** `test_f45_negotiation_uses_the_requested_trip_date` (past/today/future/outside). **B** twin request carried `for_date: 2026-11-20`. |
| F46 | Local Context Requests | ✅ | shared with F31; `/ground` | Focused, activity-scoped questions with timestamped, labelled observations. **T** ground tests. **B** ground. |
| F47 | Journey Thread | ✅ | `/api/me/thread`; `/thread` | Consented past signals carried forward; repeat/modify/avoid in a new trip. **B** thread. |
| F48 | Neighborhood Respect Filter | ✅ | `respect_note`, fragile flags; discovery, place detail and engine recommendations | Recommendations now serialise the place, so each engine card carries `respect` (`fragile`, `status`, `guidance`, `provenance`). Guidance is taken verbatim from the curated place data; places without a note report `unknown` rather than inventing one, and no precise local information is exposed. **T** `test_f48_engine_respect_is_grounded_in_place_data` (four days: every fragile recommendation's guidance equals `place.respect_note`, and at least one fragile place appears). **B** engine cards show respect guidance (Gion, Mount Daimonji). Not an automated exclusion system — curated guidance only. |
| F49 | Decision Load Governor | ✅ | `/next-action`, quiet mode; dashboard + trip header | One next action per journey; notifications already suppressed by quiet mode; every feature remains reachable via trip navigation. **B** dashboard/notifications. |

---

## Summary

| Status | Count |
|---|---|
| ✅ Implemented | 49 |
| 🟡 Partial | 0 |
| ⛔ Not implemented | 0 |

Phase 7 (2026-11-20) closed the last two partial features: F17 now supports
optional link metadata, local OCR and per-candidate review, and F22 answers in
eight languages with grounded context. F21 moved to a robust v2 model, and the
engine gained bounded consented-feedback learning, diversity-aware selection and
batch evaluation metrics. Features stay deterministic and explainable; no
external LLM or paid provider is enabled.

### Known external dependencies that are intentionally absent

| Dependency | Effect | Product behaviour |
|---|---|---|
| LLM provider | No generative answers, no AI captions | Deterministic grounded retrieval; caption drafts are template-based and require approval |
| Weather API | Real forecast only when `SAFAR_WEATHER_PROVIDER=open-meteo` (off by default) | Otherwise the assistant and rescue state that weather is unknown; rescue remains user-driven |
| Translation service | No remote translation provider | Eight languages answered with in-repo lexicons and templates; unsupported input falls back to English with a note |
| Link metadata | Off unless `SAFAR_LINK_FETCH_ENABLED=true` | Dream Import inspects the supplied URL string only and says the link was not read |
| Image OCR | Local Tesseract only; no cloud vision | Uploaded trip images are read on-server or reported as unavailable; never uploaded to a vendor |
| Live routing/traffic | No routed ETAs | Travel times are estimates, always labelled |
| Live availability/ticketing | No booking | Catalog is curated seed data, labelled ESTIMATED unless a verified source exists |
| Object storage | Media on local disk | Type/size validation; media served via expiring HMAC-signed URLs |
| Email/SMS delivery | No outbound messages | Invitations are shareable links; in-app notifications only |

## Deep audit addendum (2026-11-19)

Defects found by runtime probes and fixed, each now pinned by a regression test:

| Defect | Impact | Fix |
|---|---|---|
| Invitation tokens were reusable and not bound to the invited email | An intercepted link let any account join the trip | accept returns 409 after first use and 403 for a different email; preview reports `accepted_by_you` |
| `/media/...` was served unauthenticated to anyone who guessed a path | Private trip media could leak | HMAC-signed URLs with 12 h expiry; unsigned/tampered requests 403 |
| Memory Studio events leaked metadata of private memories | Other members saw event titles/dates referencing hidden memories | `visible_events()` filters events unless every referenced memory is visible (studio and replay) |
| Default budget comfort was treated as a hard budget cap | Members who never stated a limit silently lost affordable results | only a stated `budget_limit` filters; comfort is a soft preference used for ranking |
| Expense currency was required | Expenses failed when the trip currency should apply | currency defaults to the trip's currency |
| Completed-trip next action linked to a non-existent route | Dead link from the dashboard | links to `/trips/{id}/memories/replay` |
| OpenAI settings existed but nothing used them | Risk of implying generative AI | health/capabilities report `external_ai: false`; key is inert (now documented) |

Verification added in `services/api/tests/test_audit_fixes.py`: invite single-use and
email binding, signed media, private event metadata, engine budget semantics,
expense currency, rescue proposal validation and non-mutation, trip-scoped
inspiration import, admin rejection for non-admins, anonymising deletion with token
revocation, Journey DNA consent gating, three engine modes, explicit no-destination
failure, Trip Twin read-only adoption, constraint compass, reason-free independent
time, WebSocket broadcast to other members, and replay link correctness.

## Stabilisation pass (2026-11-19)

Fixes and additions made after the audit, each verified by test and, where it has
a UI, in a production build in the browser:

| Item | Change | Verification |
|---|---|---|
| P3 legibility | All 11/11.5 px metadata raised to 12 px (`.eyebrow` and inline labels) | `tsc`, build; browser |
| P3 assistive tech | Toasts now carry `role="alert"` for errors and `role="status"` otherwise, inside the labelled live region | browser DOM |
| F17 structural parsing | Word-boundary phrase matching; URL text stripped before entity matching; link-path destination match; hashtags; currency budgets; travel windows | `test_inspiration_import_parses_structure_and_avoids_false_positives` |
| F24 Opportunity Clock | Deterministic read-only day feasibility (new service, router, page) | `test_opportunity_clock_is_read_only_and_honest`; live API 16 candidates / 5 open; browser |
| F26 One-Link Companion | Signed, scoped, single-use, expiring links with anonymous responses (new service, models, migration, routers, pages) | two companion tests; live 201/200/200/410; browser success + 410 + 404 screens |

The new tables ship with Alembic revision `b1f6c2d84e71` (after `9c224ee10414`).
The companion response table has no user id, IP or user-agent column by design.

## Phase 3 validation (2026-11-19)

Full per-feature evidence (Feature · Status · Frontend · Backend · Database ·
Integration · Tests · Issues) is in `docs/AUDIT.md` §13.5.

| Area | Result |
|---|---|
| Feature checks F01–F49 | 275/276 passed; the one failure is F48 (no respect note in engine recommendations) |
| Journeys A–E | 5/5 passed |
| Integrations I1–I10 | 10/10 passed |
| Reliability | 40/40 passed (empty DB, fresh accounts, isolation, concurrency, duplicate/oversized sync, expired/used invitations and links, session expiry, API-offline UI, 100-item batch, crashes) |
| Automated | `pytest` 36 passed · `vitest` 12 passed · `tsc` clean · `next build` clean |
| Browser | 51 URL loads in the production build; no crashes; the deliberate 404 renders correctly |

Defects found and fixed in Phase 3:

1. **Catalog limit contract (high).** `watch`, `branches`, `ground` and
   `insights` requested `limit=100` while `/api/activities/search` accepts at
   most 60, producing 422s and empty activity pickers. All four now request 60;
   verified in the rebuilt browser build with a clean console.
2. **Offline sync client-id reuse (medium).** A reused `client_id` with changed
   content was silently skipped as `applied`. It is now `rejected` with a
   reason; identical retries remain `skipped`.
3. **Assistant translation disclosure (medium).** Generic non-Latin questions
   now receive the “translation is not configured” limitation as well as
   named-activity questions.

Assumptions: validation ran on SQLite with seeded demo data; PostgreSQL/RLS,
external providers and production-scale concurrency were not exercised. F21's
`predicted` state and F36's clarifying question were not observable on the
seeded data in Phase 3; both are covered in Phase 4.

## Phase 4 completion (2026-11-19)

| Feature | Change | Evidence |
|---|---|---|
| F48 | Engine recommendations now serialise the place and expose grounded `respect` guidance (`fragile`, `status`, `guidance`, `provenance`), `unknown` when absent | `test_f48_engine_respect_is_grounded_in_place_data`; browser cards |
| F39 | Protected time is a hard constraint in the engine, propose/add/PATCH, proposal approval, twin adoption and rescue; `meta.protected_time` reports kept blocks and free windows; “Reserve time” dialog creates protected blocks | five `test_f39_*` tests; browser itinerary/engine/rescue |
| F45 | Negotiation scored against `for_date` (caller-selected day) with 422 outside the trip; twin sends the selected day | `test_f45_negotiation_uses_the_requested_trip_date`; captured browser request |
| F36 | Question lists only members who have not shared a pulse for that day, is dismissible and links to a prefilled pulse date; null when coverage is complete | `test_f36_question_only_mentions_members_who_have_not_answered`; browser question and `/pulse?date=` |
| F21 | Predicted state validated with a controlled dataset: 8-report threshold, ESTIMATED/PREDICTED labels, confidence bounds, inconsistency penalty | `test_f21_forecast_requires_eight_reports_and_stays_estimated`; browser insufficient state |
| F27 | `GET /api/trips/{id}/tasks/summary` returns counts only for active members, matching the planner | `test_f27_task_summary_matches_planner_and_stays_private`; browser load-balance panel |
| F12 | Caption drafts explicitly `ai_generated: false` with template disclosure | `test_f12_caption_is_a_template_not_ai` |
| F14 | Place-detail aggregate exposes `verification`; community reports read “REPORTED · moderator-checked”, official sources “official · verified” | extended `test_f14_moderator_verification_never_promotes_community_reports`; browser badge |

Phase 4 totals: `pytest` 49 passed · `vitest` 12 passed · `tsc` clean ·
`next build` clean. Browser checks covered engine, itinerary, rescue, twin,
pulse, voting impact, tasks and place detail with no console errors.

## Phase 5 — Production security & infrastructure hardening (2026-11-19)

No new travel features. The 49 product features keep their status; this phase
changes how they are protected, persisted and operated. Full report:
`docs/SECURITY.md`; audit trail: `docs/AUDIT.md` §15; runbook:
`docs/DEPLOYMENT.md`.

| Area | Implementation | Evidence |
|---|---|---|
| Sessions | HttpOnly access/refresh cookies, server-side `auth_sessions`, rotation with reuse detection, revocation, 2-minute WS ticket | `test_refresh_rotation_rejects_a_replayed_token`, `test_logout_revokes_the_session_for_existing_tokens`; browser login/logout |
| CSRF | Double-submit `safar_csrf` + `X-CSRF-Token`, constant-time compare | `test_cookie_sessions_require_csrf_for_writes` |
| Database isolation | RLS on 55 tables, 220 policies, FORCE, fail-closed GUCs, non-owner role | direct SQL probes; 68 tests on PG |
| API hardening | Security headers, TrustedHost, body limit, per-bucket rate limits, harmless errors, docs off in production | 19 hardening tests |
| Uploads | Magic-byte sniffing; oversized/spoofed files rejected | `test_media_upload_rejects_a_spoofed_content_type` |
| Privacy | Erasure expanded, retention job, location consent required for precise coordinates | `test_account_deletion_erases_personal_data`, `test_retention_removes_only_expired_rows`, `test_precise_location_requires_the_privacy_toggle` |
| Secrets/config | No committed secrets; production guards for `SECRET_KEY`, CORS, cookies, docs, seeding; accurate `.env.example` | config review; `.env.example` |
| Recovery | `pg_dump -Fc` / `pg_restore` drill with schema, policy, row and RLS parity | `docs/DEPLOYMENT.md` §6 |

Phase 5 totals: `pytest` **68 passed on SQLite** and **68 passed on PostgreSQL
16.4 under FORCE RLS** · `vitest` 12 · `tsc` clean · `next build` clean.

Status note: the product is hardened and PostgreSQL-verified, but **not
declared production-ready**. Docker images were not built in this environment,
TLS/proxy behaviour was not exercised, no load test or external review was
performed, and backup/PITR coverage is logical-dump only. The explicit
conditions are in `docs/SECURITY.md` §8.

## Phase 6 — Premium UI/UX transformation (2026-11-19)

No feature was added, removed or re-scoped; this phase changes presentation and
interaction quality only. F01–F49 keep the states recorded above. Design system:
`docs/UI_DESIGN.md`. Audit trail and evidence: `docs/AUDIT.md` §16.
Screenshots: `docs/screenshots/`.

| Area | Change | Evidence |
|---|---|---|
| Design system | Token palette (11 semantic colours, light/dark), serif display scale, radii, shadows, motion tokens, 24 shared primitives | `app/globals.css`, `tailwind.config.ts`, `components/ui.tsx`; `docs/UI_DESIGN.md` |
| Shell | Grouped sidebar, mobile drawer with focus trap/scroll lock, bottom tabs, ⌘K palette, theme switch, notification badge | drawer open/Escape/focus checks; screenshot |
| Core screens | Dashboard, discovery, trip overview, itinerary, engine, voting, memories redesigned around one next action per journey | desktop + mobile screenshots; interaction checks |
| Secondary screens | Pulse, rescue, twin, tasks, expenses, map, places, branches, inspirations, opportunity, watch, missions, insights, pact, ground, companion, assistant, members, more, offline, evidence, place detail | route matrix at 390/768/1024/1440 |
| A11y | `aria-pressed` chips, `role="switch"` toggles, live regions, labelled icon buttons, dialog focus/trap/restore, skip link, visible focus, reduced motion | DOM inspection; `docs/UI_DESIGN.md` §6 |
| Contrast | `--faint` darkened to reach AA (4.11 → 4.68 on paper, 4.89 on raised) | computed WCAG ratios |
| Responsive | 35+ route × width checks; no page-level horizontal scroll; scroll confined to tab/day strips | iframe matrix + headless capture |
| Defects fixed | Itinerary hooks crash, engine null meta, dashboard stat copy, unnamed generate action, rAF-dependent focus | `docs/AUDIT.md` §16.4 |

Verification totals: `tsc` clean · `vitest` 12 passed · `next build` clean with
all 52 routes · production build on :3010 against API :8010 exercised with real
seeded data for create/delete/confirm flows.

Remaining UI caveats (not feature regressions): no automated axe/Lighthouse
scan, 36px icon-button targets (AA, not AAA), hidden scrollbars on tab strips
rely on a partially visible pill as the affordance, and long mobile screenshots
are capped at 6000px. Details in `docs/AUDIT.md` §16.7.

## Phase 7 — Advanced AI/ML intelligence and real-world integrations (2026-11-20)

F01–F49 keep their implemented state; this phase deepens the intelligence layer
without replacing deterministic systems. Design and evaluation record:
`docs/AI_ML_ARCHITECTURE.md`; audit trail: `docs/AUDIT.md` §17.

| Area | Change | Evidence |
|---|---|---|
| Provider layer | Server-side abstraction with provenance, TTL cache, token buckets, timeouts, SSRF guards and a key-free capability endpoint (`/api/ai/capabilities`) | `test_phase7_dream_import.py` (SSRF, disabled link), `test_phase7_evaluation.py::test_provider_capabilities_expose_no_secrets` |
| F17 Dream Import | Stable candidates with source spans, optional link metadata, local OCR, trip-scoped media safety, accept/reject review | 10 tests in `test_phase7_dream_import.py` |
| F22 Multilingual assistant | Eight languages, detection/fallbacks, localised templates, context pack, citations, approval flags | 12 tests in `test_phase7_multilingual.py`; live Spanish/Hindi |
| Engine ranking | Consent-gated feedback nudge (±4, groups ≥3, ≥2 raters), diversity-aware selection, `meta.evaluation` fairness/satisfaction/constraints/diversity | 5 tests in `test_phase7_recommendations.py`; live batch Jain 0.999, violations 0 |
| F21 Forecasting | `bucket-forecast-v2` with outlier rejection, stale cap, hierarchical fallback, intervals, observed/predicted separation | 5 tests in `test_phase7_forecasting.py`; existing F21 test updated |
| UI | Engine shows version 1.5, evaluation tiles, selection reasons and feedback disclosure; place detail shows observed/predicted forecast, intervals and confidence labels | browser checks on engine and Nishiki Market place pages |
| Evaluation suite | Hallucination resistance, privacy leakage, grounding, latency and prediction labelling through the API | 6 tests in `test_phase7_evaluation.py` |

Phase 7 totals: `pytest` **106 passed** (38 Phase 7 tests) · `vitest` 12 passed ·
`tsc` clean · `next build` clean. Live checks ran against API
`safar-group-engine-1.5` / `safar-grounded-i18n-2.0`.

Known limits after Phase 7: link metadata and weather are opt-in and were tested
in their disabled/default states; OCR depends on a local Tesseract binary that
may be absent; no external translation model is used, so free-form prose outside
the authored templates falls back to English with a note; evaluation fixtures are
synthetic and seeded, not a production traffic sample.

## Phase 9 — Flutter feature migration (2026-11-20)

Product status is unchanged: **49 ✅ / 0 🟡 / 0 ⛔**. Phase 9 migrates the
client surface to Flutter (`apps/mobile`) without changing any backend route,
schema, service or migration. The Next.js app stays available as reference and
fallback. Method, evidence and limitations: `docs/FLUTTER_MIGRATION_PLAN.md` §8.

Legend for the Flutter column: **C** complete API-backed surface · **P** partial
(a named capability is still web-only) · **W** web-only · **B** blocked.

| ID | Feature | Flutter | Note |
|---|---|---|---|
| F01 | Account, consent, preferences | C | login/register, settings, consents, native JSON archive export, delete |
| F02 | Journey DNA | C | scores + explicit edits |
| F03 | Discovery | C | search, lens, provenance |
| F04 | Trip creation, membership, roles | C | creation, roster, invite/create/share/revoke, role change, removal |
| F05 | Itinerary & voting | C | timeline, votes, approve/reject, live chip |
| F06 | Trip Pulse | C | shared/private fields |
| F07 | Group Experience Engine | C | three modes, clarify, feedback, propose |
| F08 | Trip Twin | C | compare + adopt as proposal |
| F09 | Trip Rescue | C | analyse + grounded proposals |
| F10 | Maps & nearby | C | tile provider or schematic fallback, pan/zoom, markers, routes, consent-gated origin |
| F11 | Memory timeline | C | CRUD, media, photo upload |
| F12 | Memory Studio | C | grounded drafts + approval disclosure |
| F13 | Group expenses | C | settle, balances, native CSV export & share |
| F14 | Place Pulse | C | report, helpful, verification labels |
| F15 | Serendipity Radar | C | matches, request/decide, block |
| F16 | Circles & contributors | C | join/leave, members, opt-in |
| F17 | Dream Import | C | candidates + accept/reject |
| F18 | Replay & travel book | C | replay + native HTML travel book export & viewer |
| F19 | Missions & wildcards | C | join/complete/disable |
| F20 | Offline capture & sync | C | local queue, idempotent sync, snapshot |
| F21 | Crowd forecasting | C | observed vs predicted |
| F22 | Multilingual assistant | C | 8 languages, citations |
| F23 | Journey Pact | C | editor, merged private limits, approval conflicts |
| F24 | Opportunity Clock | C | read-only feasibility |
| F25 | Shadowplan | C | list/create/adopt |
| F26 | One-Link Companion | C | signed single-use links, anonymous respond, revoke, deep link |
| F27 | Planner load balancer | C | tasks + counts-only summary |
| F28 | Branch & rejoin | C | split/reunion feasibility |
| F29 | Journey effort budget | C | effort, walking, rest |
| F30 | Evidence Passport | C | provenance labels |
| F31 | Ask the Ground | C | create/respond, REPORTED |
| F32 | Cost-Shock Guard | C | impact + budget conflicts before approval |
| F33 | Outcome Calibrator | C | consented feedback |
| F34 | Journey Capsule | C | create + freshness |
| F35 | Constraint Compass | C | affected items after paste |
| F36 | One Question That Matters | C | clarify prompt |
| F37 | Fragility Radar | C | buffers, alternatives |
| F38 | Domino Map | C | delay simulation |
| F39 | Protected Wander Window | C | protected toggle + hard 409s |
| F40 | Expectation Reality Check | C | claim vs evidence |
| F41 | Access Chain | C | stages incl. unknown |
| F42 | Balance Lens | C | balanced/iconic/similar |
| F43 | Independent Time | C | in/join later/skip |
| F44 | Material Change Watch | C | add/check/remove |
| F45 | Fair Trade Negotiator | C | compromise trade-offs |
| F46 | Local Context Requests | C | activity-scoped |
| F47 | Journey Thread | C | consented signals |
| F48 | Respect Filter | C | grounded guidance, unknown when absent |
| F49 | Decision Load Governor | C | next action + quiet mode |

Totals: 49 C · 0 P · 0 W · 0 B. All 49 features now have a complete
API-backed Flutter surface; the backend and web client are unchanged.

Verification for this phase:

* `flutter analyze` — no issues; `flutter test` — 25 passed / 7 live-suite
  skipped; live suite against the running API — 7 passed; Phase 9 unit tests —
  10 passed (`apps/mobile/test/phase9_test.dart`).
* `pytest` — 107 passed (suite unchanged; no backend code changed).
* `flutter build web --release` — succeeded. Android was blocked before
  compilation by the environment's TLS interception at Gradle artifact download
  (`PKIX path building failed`); iOS requires macOS. No binary is claimed.
* Live API smoke checks: all new read contracts returned 200 (pact, effort,
  fragility, shadowplans, capsules, opportunity, branches, tasks + summary,
  watch, ground, missions, companion links, pulse, studio, replay, travel book,
  expenses/balances, activity, next-action, offline, serendipity, circles,
  contributors, thread, notifications) and `twin/compare`, `negotiate` and
  `domino` were exercised on trips with itinerary items; companion lifecycle
  incl. single-use 410 and anonymous responses; watch duplicate 409; task
  summary shape; offline idempotent sync; media upload + photo memory;
  coordinates without location consent → 403.

New in Phase 9: real-time trip channel (ticket auth, exponential backoff,
dedupe, lifecycle pause/resume, reconnect reconciliation, status chip), native
share sheet, camera/library photo memories, consent-gated location, companion
deep links, and a device-local offline capture queue. Security posture unchanged:
no RLS/API authorisation change, companion responses remain anonymous, precise
location still requires consent, and media stays signed.

Phase 10 verification (2026-11-21):

* **F04 completed** — in-app invitation creation, share sheet/link copy and
  revoke; owner/admin role changes and member removal behind a confirmation
  dialog; non-admins see no admin affordances and can leave. `flutter test`
  `test/phase10_test.dart` covers the owner view, managing another member,
  the removal dialog's safe default, a plain member's view and the invite
  sheet.
* **F10 completed** — configurable tile provider (`--dart-define`
  `SAFAR_MAP_TILE_URL` and friends, HTTPS-only in release) with a labelled
  schematic fallback, pan/zoom, markers, radius ring, confirmed-route lines,
  attribution and loading/error states. Location sharing stays consent-based:
  profile consent is required before the OS prompt, and no coordinates are sent
  without it. `phase10_test.dart` covers tile URL substitution, fallback and
  configured notes, chips, distances, empty state, consent-off gate and 130 %
  text layout on a phone viewport.
* **Android artifacts** — debug APK 185,005,238 B
  (`sha256 d6abdcc18678bf75c137…`); release APK 61,443,822 B
  (`9ea4556bc7eadf627462…`, signed, signer certificate SHA-256
  `d59f0211330ff15bddf068355ee7e2804ea65b647f0d7d685ddc985757333931`); release
  AAB 47,723,116 B (`3f21f1bd5dcde1f36c90…`, `jar verified.`). The signing key
  was a throwaway verification key; production must supply the real upload key
  via the documented environment variables. No credential is committed.
* **Emulator** — debug APK installed and launched on the API 36 AVD; verified
  login, dashboard, session persistence across restart, logout, trip overview,
  All tools, People & invites with live data, and Nearby with local tiles,
  markers, routes, zoom/recenter and BACK restoration. Large-text checks found
  and fixed a 12 px invitation-row overflow.
* **Checks** — `flutter analyze` clean; `flutter test` 37 passed / 7 live-suite
  skipped / 0 failed; `pytest` 107 passed; web release built.
* **Limitations** — see `docs/FLUTTER_MIGRATION_PLAN.md` §9.8 (AOSP IME stale
  back callback, `geolocator` NMEA ANR on the GMS-less image, host emulator
  crashes, refresh-rotation re-login, throwaway signing key, iOS unbuilt,
  production tile provider/credentials not bundled).

---

## Phase 13, Step 6 — Monitoring, Observability & Operational Reliability (2026-11-21)

Comprehensive observability and operational telemetry foundation across backend and mobile:

* **Backend Structured JSON Logging** — `JsonFormatter` in `app/core/logging.py` emitting structured JSON with `timestamp`, `level`, `logger`, `message`, `environment`, and `request_id` (`X-Request-Id` correlation).
* **Sensitive Data Redaction** — `redact_path` sanitizes sensitive path segments (`companion`, `invitations`, `media`) and strips sensitive query parameters (`token`, `sig`, `key`, `password`, `secret`). `redact_sensitive_dict` scrubs authorization headers, passwords, and tokens from request/response logging.
* **Operational Metrics Collector** — `MetricsCollector` in `app/core/metrics.py` tracking:
  - HTTP counters (2xx, 3xx, 4xx, 5xx), request counts by path/method, rolling request latencies.
  - Security events (login success/failures, refresh success/failures, refresh reuse/theft detection, CSRF violations, rate-limit trips, unauthorized access attempts).
  - Database telemetry (total queries, slow queries exceeding 500 ms, connection pool errors, last ping latency).
  - WebSocket lifecycle (connections, disconnections, client errors, active connection count).
  - Offline sync metrics (applied operations, skipped idempotents, rejected conflicts).
  - Media upload tracking (successful uploads, MIME spoof rejections, oversized payload rejections).
* **Alert Management & Cooldown** — `AlertManager` in `app/core/alerting.py` categorizing alerts (`critical`, `warning`, `info`) with in-memory circular history and automated 5-minute cooldown per category to prevent log flooding. Dispatches structured logs to `safar.alert`.
* **Database Observability** — SQLAlchemy event listeners (`before_cursor_execute`, `after_cursor_execute`, `handle_error`) capturing query execution durations, triggering alerts on queries exceeding `SLOW_QUERY_THRESHOLD_MS` (500ms), and tracking pool status (`size`, `checked_in`, `checked_out`, `overflow`).
* **Health Probes** — Dual-probe architecture:
  - Liveness: `GET /api/health` returning basic service status.
  - Readiness: `GET /api/ready` executing `check_db_readiness()` and returning `{"status": "ready", "database": "ok"}` while failing closed (503 Service Unavailable) without leaking internal database engines, ping times, or connection strings.
* **Admin Operational Metrics** — Secured endpoint `GET /api/admin/metrics` requiring `require_admin` authorization. Exposes operational metrics, DB connection pool health, media storage volume/bytes, and backup manifest history.
* **Mobile Observability & Telemetry** —
  - `DiagnosticsService` in `apps/mobile/lib/core/services/diagnostics_service.dart` providing a bounded 100-event circular buffer, sensitive data redaction, and global unhandled error handlers (`FlutterError.onError`, `PlatformDispatcher.instance.onError`).
  - Network telemetry interceptor in `ApiClient` recording duration, HTTP status, and auth drops.
  - Realtime telemetry in `TripChannel` capturing WebSocket state transitions, disconnections, and reconnection backoff.
  - Offline queue state tracking in `OfflineQueue` with explicit states (`pending`, `syncing`, `failed`), retry counts, error reasons, and user-initiated recovery (`retryFailed()`).
* **Automated Staging Backup & Verification** — `services/api/scripts/backup_staging.py` utilizing `pg_dump -Fc`, SHA-256 integrity checksums, structured manifest updates (`storage_staging/backups/backup_manifest.json`), 7-backup retention enforcement, and non-destructive restore drill into temporary database (`safar_restore_verify`), confirming survival of all 56 tables, Alembic revision `e5c8a2b7d940`, 220 policies, 56 ENABLE / 55 FORCE RLS, and tenant isolation.
* **Verification**:
  - Backend: 125 pytest tests passing (including 13 dedicated observability tests).
  - Web: 12 vitest tests passing, 0 TypeScript errors.
  - Mobile: 61 unit/widget tests passing (including 4 observability tests), 0 `flutter analyze` issues, 12 live API integration tests passing against staging port 8020.
  - Staging RLS & Isolation: 100% verified against Supabase PostgreSQL 17 (`safar_app` role).

---

## Group-First Architecture with Integrated Solo Travel & Safety Centre (2026-11-22)

SAFAR preserves its identity as primarily a **Group Travel platform** (Priority 1: Group Travel default & prominent; Priority 2: Solo Travel integrated secondary capability).

* **Product Hierarchy & Philosophy**:
  - Group Travel remains the primary, default experience (creation defaults to group mode, collaborative voting, expense settlement, Journey DNA matching, group missions).
  - Solo Travel is an integrated secondary option accessible via the trip creation travel mode selector and dashboard indicators.
  - Solo journeys belong to individual travellers and do not enforce invitations, voting stalls, or required splits.

* **Backend Models & Migration (`f1a2b3c4d5e6_solo_travel_and_safety.py`)**:
  - `Trip.trip_type` (`group` or `solo`, server default `"group"`).
  - `EmergencyContact` (`trip_id`, `user_id`, `name`, `relationship`, `phone`, `email`, `notes`, `is_primary`).
  - `TripCheckIn` (`trip_id`, `user_id`, `status` [safe/delayed/needs_assistance/completed], `location_name`, `lat`, `lon`, `message`).
  - `SoloSafetySettings` (`trip_id`, `check_in_frequency_hours` [default 24], `last_check_in_at`, `next_check_in_due`, `location_sharing_enabled`, `share_token`).

* **API Endpoints (`routers/safety.py`)**:
  - `GET /api/trips/{trip_id}/safety` — Authenticated status check returning active check-in state, overdue hours, contacts, settings, and country-aware emergency dialer numbers.
  - `POST /api/trips/{trip_id}/safety/contacts` — Add primary or secondary emergency contact.
  - `DELETE /api/trips/{trip_id}/safety/contacts/{contact_id}` — Remove contact.
  - `POST /api/trips/{trip_id}/safety/check-in` — Submit live check-in; advances `last_check_in_at` and `next_check_in_due`.
  - `PATCH /api/trips/{trip_id}/safety/settings` — Update check-in interval (6h, 12h, 24h, 48h) or toggle public beacon.
  - `GET /api/safety/beacon/{token}` — Public unauthenticated read-only endpoint for family/friends to view traveler status and last check-in without an account.

* **Mobile Architecture (`apps/mobile`)**:
  - `TripCreateScreen` — Segmented Travel Mode selector (Group Journey [default/primary] vs Solo Journey [secondary]); dynamic personal budget and personal notes labels; single-traveller mode.
  - `DashboardScreen` — Group trips prominent; subtle `Solo` chip on individual journeys.
  - `TripOverviewScreen` — Dedicated Solo Safety Centre card for solo trips; `Safety` tool in Workspace grid.
  - `SoloSafetyScreen` (`/trips/:tripId/safety`) — Live status banner with overdue warnings; "Check In Now" modal; country-aware emergency dialers (Japan 110/119, UK 999, US/Canada 911, Europe/India 112, Australia 000) using `url_launcher`; offline SharedPreferences caching; Trusted Contact Beacon share button (`SharePlus`); emergency contact manager.
  - Clear non-emergency disclaimer: informational tool, not guaranteed dispatch or continuous GPS surveillance.

* **Verification**:
  - Backend: `services/api/tests/test_solo_travel.py` (4 tests passing: solo trip creation, contact management, check-in, beacon access & 404 security).
  - Mobile: `apps/mobile/test/solo_travel_test.dart` (6 tests passing: model deserialization, emergency dialers, mode selector).
  - Mobile full suite: 85 passed, 0 failed.
  - Flutter analyze: clean (0 errors, 0 warnings).

