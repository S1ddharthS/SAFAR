# SAFAR — Comprehensive Functional Audit

**Date:** 2026-11-22  
**Scope:** Complete Product-Wide Audit (F01–F49), End-to-End Integrity, Mobile (Flutter), Backend (FastAPI), Database (Supabase PostgreSQL 17 with RLS), and Staging Environment.  
**Tested Devices/Platforms:** Physical Motorola Edge 50 Pro (Android 14/15, LAN IP `192.168.29.x`), Host Staging API (`192.168.29.69:8020`), Supabase Session Pooler.

---

## 1. Executive Summary & Audit Methodology

SAFAR has successfully completed initial feature prototyping, Flutter mobile migration, release baseline stabilization, and local Wi-Fi connectivity to the physical Motorola Edge 50 Pro. However, a rigorous end-to-end evaluation across the complete stack:

$$\text{Flutter UI} \longrightarrow \text{API Client} \longrightarrow \text{FastAPI Endpoint} \longrightarrow \text{Business / ML Logic} \longrightarrow \text{PostgreSQL / Storage} \longrightarrow \text{Response} \longrightarrow \text{Flutter UI}$$

reveals significant functional gaps between what is rendered on screen or documented in registries, and what is genuinely operational.

### Verification Criteria Applied
Every feature was audited against ten strict operational questions:
1. **Screen Load:** Does the Flutter screen mount and render without layout errors or uncaught exceptions?
2. **User Action:** Can the user trigger all advertised buttons, inputs, and gestures?
3. **API Request:** Does the client execute the correct HTTP method, endpoint, headers, and payload?
4. **Backend Implementation:** Is the backend logic genuinely implemented rather than returning static templates or stubbed responses?
5. **Data Persistence:** Are state modifications properly committed to PostgreSQL 17 or local media storage?
6. **UI Reflection:** Does the UI update in response to server state changes (via response or WebSocket)?
7. **Multi-User Correctness:** Do concurrent members in different roles (owner, admin, member) see consistent, partitioned state?
8. **Permissions & Privacy:** Are RLS, route guards, pact privacy, and consent boundaries strictly enforced?
9. **Error & Offline Resilience:** Does the feature handle network disconnections, 4xx/5xx responses, and queue offline mutations?
10. **Physical Android Device Verification:** Does the feature work natively on the Motorola Edge 50 Pro over Wi-Fi?

### Classification Standard
- **COMPLETE:** Fully implemented and verified end-to-end across Flutter, API, Database, and Physical Device.
- **PARTIAL:** Real, functional subset works, but important advertised behaviours, export actions, or inputs are missing.
- **BROKEN:** Code exists and executes, but fails to deliver the expected result (e.g. dumping raw HTML markup into a text field).
- **UI_ONLY:** Flutter interface exists with mock/stubbed state or missing backend mutations.
- **NOT_IMPLEMENTED:** Capability does not exist in backend or mobile codebase.
- **BLOCKED:** Requires an external provider, binary dependency, or infrastructure not present in the current environment.

---

## 2. Feature-by-Feature Operational Audit (F01–F49)

> **Note on Feature Cross-Referencing:**  
> In the master prompt and earlier specification iterations, feature numbering shifted across expansions. Specifically:
> - **Journey Replay & Travel Book** is catalogued as **F18** in `docs/FEATURE_REGISTRY.md` and referred to as **F44** in the recent prompt.
> - **AI Memory Studio** is catalogued as **F12** in `docs/FEATURE_REGISTRY.md` and referred to as **F43** in the recent prompt.
> - **Graceful Independent Time** is **F43** in the Feature Registry.
> - **Material Change Watch** is **F44** in the Feature Registry.  
> Both IDs are explicitly cross-referenced below for complete clarity.

| ID | Feature Name | Master Spec Ref | Audit Status | Flutter Surface | Backend Route / Service | Storage / DB Table | Operational Findings & Gaps |
|---|---|---|---|---|---|---|---|
| **F01** | Account, Consent & Preferences | Foundation F01 | **PARTIAL** | `login_screen`, `profile_screen`, `settings_screen` | `/api/auth/*`, `/api/me`, `/api/me/export`, `/api/me/consents` | `users`, `consents`, `auth_sessions` | Core auth, password hashing, session cookies, and consent gating work. **Defect:** "Export data" in `settings_screen.dart` dumps raw JSON into `SelectableText` in a bottom sheet instead of downloading or sharing a JSON file. |
| **F02** | Journey DNA | Foundation F02 | **COMPLETE** | `journey_dna_screen.dart` | `GET/PUT /api/me/dna` | `journey_dna` | 10 dimensions, 0–10 sliders, explicit updates save to DB; feedback decay and consent gating functional. |
| **F03** | Destination & Activity Discovery | Foundation F03 | **COMPLETE** | `discover_screen.dart`, `destination_screen.dart` | `/api/destinations*`, `/api/activities/search` | `destinations`, `activities`, `places` | Filters (pace, budget, wheelchair, indoor) and lenses (balanced, iconic, similar) work correctly with provenance labels. |
| **F04** | Trip Creation, Membership & Roles | Foundation F04 | **COMPLETE** | `trip_create_screen.dart`, `members_screen.dart`, `invitation_screen.dart` | `/api/trips*`, `/api/trips/{id}/invitations*`, `/api/trips/{id}/members*` | `trips`, `trip_members`, `trip_invitations` | Roles (owner/admin/member), invite token creation, share sheet, single-use binding, email validation, and member removal verified. |
| **F05** | Collaborative Itinerary & Voting | Foundation F05 | **COMPLETE** | `itinerary_screen.dart`, `proposals_screen.dart` | `/api/trips/{id}/itinerary*`, `/api/trips/{id}/proposals*`, WebSocket | `itineraries`, `itinerary_items`, `proposals`, `votes`, `itinerary_versions` | Versioned itinerary, proposal voting, quorum check, pact conflict validation, and WebSocket live updates operational. |
| **F06** | Trip Pulse | Foundation F06 | **COMPLETE** | `pulse_screen.dart` | `GET/PUT /api/trips/{id}/pulse` | `trip_pulse` | Radar chart rendering, shared energy/time/radius vs strictly private budget comfort and notes. |
| **F07** | Group Experience Engine | Foundation F07 | **COMPLETE** | `engine_screen.dart` | `POST /api/trips/{id}/engine/recommend`, `GET /api/trips/{id}/insights` | `activities`, `places`, `recommendation_feedback` | Everyone Wins, Your Turn, and Surprise Us modes execute real ranking; Jain fairness index computed; proposals can be drafted directly. |
| **F08** | Trip Twin | Foundation F08 | **COMPLETE** | `twin_screen.dart` | `POST /api/trips/{id}/twin/compare`, `POST /api/trips/{id}/twin/propose` | `itinerary_items`, `activities` | Multi-activity comparison (fit, budget, time, travel) read-only; alternative adoption creates a group proposal. |
| **F09** | Trip Rescue & Autopilot | Foundation F09 | **COMPLETE** | `rescue_screen.dart` | `POST /api/trips/{id}/rescue/analyze`, `POST /api/trips/{id}/rescue/propose` | `itinerary_items`, `activities` | Rain, closure, traffic, fatigue, budget shock scenarios analyzed; replacements generated as proposals; protected time respected. |
| **F10** | Maps & Nearby Experiences | Foundation F10 | **COMPLETE** | `nearby_screen.dart`, `slippy_map.dart` | `GET /api/trips/{id}/nearby` | `places`, `activities` | Haversine distance from trip base; consent-gated member location; pan/zoom, schematic fallback, markers, and route lines work. |
| **F11** | Shared Memory Timeline | Foundation F11 | **PARTIAL** | `memories_screen.dart` | `GET/POST /api/trips/{id}/memories`, `POST /api/trips/{id}/media` | `trip_memories`, `memory_permissions`, local disk | Photo uploads and text memories work with HMAC signed URLs. **Defects:** No video picking, no audio recording for "voice" memories, no upload progress bar or cancel token. |
| **F12** | AI Memory Studio / Constellation | Foundation F12 *(User prompt: F43)* | **PARTIAL** | `studio_screen.dart` | `GET /api/trips/{id}/memory-studio`, `POST .../suggest-events`, `POST .../approve` | `memory_events`, `trip_memories` | Event grouping (3-hr time cluster + itinerary item) and template caption drafts work. **Defects:** Image embedding is FALSE (no vector model/db), OCR is FALSE (no Tesseract/pytesseract), Speech-to-Text is FALSE. No event reordering/splitting in UI. |
| **F13** | Group Expenses | Foundation F13 | **PARTIAL** | `expenses_screen.dart` | `/api/trips/{id}/expenses*`, `/api/trips/{id}/expenses/export` | `expenses`, `expense_splits`, `settlements` | Multi-currency splits, reconciliation, and debt settlement work. **Defect:** CSV export displays raw CSV text in a bottom sheet instead of sharing or saving an actual `.csv` file. |
| **F14** | Place Pulse | Foundation F14 | **COMPLETE** | `place_screen.dart` | `/api/activities/{id}/reports`, `/api/place-reports/{id}/helpful`, `/api/admin/place-reports/{id}/verify` | `place_reports` | Community reporting, helpful voting, moderator verification, and provenance labelling (`REPORTED` vs `VERIFIED`) functional. |
| **F15** | Serendipity Radar | Foundation F15 | **COMPLETE** | `connections_screen.dart` | `/api/serendipity/matches`, `/api/serendipity/requests`, `/api/serendipity/decide` | `connections`, `user_blocks` | Reciprocal opt-in matching, mutual consent before disclosure, and block list enforcement operational. |
| **F16** | Travel Circles & Local Contributors | Foundation F16 | **COMPLETE** | `circles_screen.dart`, `contributors_screen.dart` | `/api/circles*`, `/api/contributors*` | `travel_circles`, `circle_members`, `circle_posts`, `local_contributors` | Circle exploration, join/leave, member list privacy masking, and contributor opt-in working. |
| **F17** | Dream-to-Destination Import | Foundation F17 | **PARTIAL** | `import_screen.dart` | `GET/POST /api/trips/{id}/inspirations`, `POST .../review` | `inspirations`, `inspiration_candidates` | Note and link structural parsing works; candidate accept/reject works. **Defects:** "Image" option is missing in Flutter UI (`_ImportSheet` only has Note and Link); OCR backend is unavailable (Tesseract missing); link fetch disabled by default. |
| **F18** | Journey Replay & Travel Book | Foundation F18 *(User prompt: F44)* | **BROKEN** | `replay_screen.dart` | `GET /api/trips/{id}/replay`, `GET /api/trips/{id}/travel-book` | `itinerary_items`, `trip_memories`, `memory_events` | Replay stats and timeline load correctly. **Critical Defect:** "Open travel book" displays raw HTML source code in `SelectableText` in a bottom sheet. No WebView, no browser intent, no print/PDF export, no file saving. |
| **F19** | Travel Missions & Wildcards | Foundation F19 | **COMPLETE** | `missions_screen.dart` | `/api/trips/{id}/missions*` | `missions`, `mission_completions` | Deterministic generation from trip activities, self-reported completion, opt-out, and admin toggle functional. |
| **F20** | Offline-First Capture & Sync | Foundation F20 | **COMPLETE** | `offline_screen.dart`, `offline_queue.dart` | `GET /api/trips/{id}/offline`, `POST /api/trips/{id}/sync` | `offline_sync_queue` | Device-local queue in SharedPreferences, offline snapshot download, idempotent sync with `client_id` deduplication. |
| **F21** | Predictive Crowd Forecasting | Foundation F21 | **COMPLETE** | `place_screen.dart` | Integrated in `services/places.py` `crowd_forecast` | `place_reports` | `bucket-forecast-v2` with MAD outlier rejection, 8-report threshold, 180-day window, 80% interval, and confidence calibration. |
| **F22** | Multilingual Travel Conversation | Foundation F22 | **COMPLETE** | `assistant_screen.dart` | `/api/assistant/chat`, `/api/trips/{id}/assistant/chat`, `/api/assistant/capabilities` | In-memory lexicons, trip DB | 8 languages (en, es, fr, de, pt, it, hi, ja), script detection, intent lexicons, context pack, citations, approval flags, no external LLM. |
| **F23** | Journey Pact | Expansion F23 | **COMPLETE** | `pact_screen.dart` | `GET/PUT /api/trips/{id}/pact` | `journey_pacts` | Merged private limits, approval conflicts, and agreement tracking functional. |
| **F24** | Opportunity Clock | Expansion F24 | **COMPLETE** | `opportunity_screen.dart` | `GET /api/trips/{id}/opportunity-clock?on=` | `activities`, `places`, `itinerary_items` | Read-only feasibility: catalog opening hours parsed, confirmed itinerary deducted, haversine travel time estimated. Propose action works. |
| **F25** | Shadowplan | Expansion F25 | **COMPLETE** | `plan_intelligence_screen.dart` | `/api/trips/{id}/shadowplans*` | `shadowplans` | Backup options attached to confirmed items; proposal adoption functional. |
| **F26** | One-Link Companion | Expansion F26 | **COMPLETE** | `companion_screen.dart`, `companion_public_screen.dart` | `/api/trips/{id}/companion-links*`, `/api/companion/{token}*` | `companion_links`, `companion_responses` | HMAC-signed tokens, single-use, anonymous voting, expiration, and revocability verified. |
| **F27** | Planner Load Balancer | Expansion F27 | **COMPLETE** | `tasks_screen.dart` | `GET /api/trips/{id}/tasks/summary`, `/api/trips/{id}/tasks*` | `trip_tasks` | Counts-only summary protects private member details while balancing workload. |
| **F28** | Branch & Rejoin | Expansion F28 | **COMPLETE** | `branches_screen.dart` | `/api/trips/{id}/branches*` | `trip_branches` | Split group planning with reunion place/time and travel feasibility. |
| **F29** | Journey Effort Budget | Expansion F29 | **COMPLETE** | `plan_intelligence_screen.dart` | `GET /api/trips/{id}/effort` | `itinerary_items`, `activities` | Walking km, transitions, effort points, rest blocks; protected blocks counted as rest. |
| **F30** | Decision Evidence Passport | Expansion F30 | **COMPLETE** | `place_screen.dart` | In `GET /api/activities/{id}` | `activities`, `places`, `place_reports` | Provenance labels (`VERIFIED`, `CURATED`, `REPORTED`, `ESTIMATED`), confidence, cost/travel assumptions displayed. |
| **F31** | Ask the Ground | Expansion F31 | **COMPLETE** | `ground_screen.dart` | `/api/trips/{id}/ground-requests*`, `/api/ground-requests/{id}/respond` | `ground_requests`, `ground_responses` | Opted-in local contributor targeting, unverified reported responses stored and displayed. |
| **F32** | Cost-Shock Guard | Expansion F32 | **COMPLETE** | `proposals_screen.dart` | In proposal impact calculation | `journey_pacts`, `itinerary_items` | Per-member budget checks block approval with 409 without exposing amounts. |
| **F33** | Outcome Calibrator | Expansion F33 | **COMPLETE** | `place_screen.dart` | `POST /api/activities/{id}/feedback`, `services/feedback.py` | `activity_feedback`, `journey_dna` | Consented sentiments update DNA; bounded engine nudge (±4 points) for groups of ≥3 with ≥2 raters. |
| **F34** | Journey Capsule | Expansion F34 | **COMPLETE** | `plan_intelligence_screen.dart` | `/api/trips/{id}/capsules*` | `journey_capsules` | Immutable timestamped snapshot with freshness indicator. |
| **F35** | Constraint Compass | Expansion F35 | **COMPLETE** | `pulse_screen.dart` | In `PUT /api/trips/{id}/pulse` | `trip_pulse`, `itinerary_items` | Updating pulse returns exact confirmed items affected by constraints. |
| **F36** | One Question That Matters | Expansion F36 | **COMPLETE** | `engine_screen.dart` | In `POST /api/trips/{id}/engine/recommend` | `trip_pulse`, `trip_members` | Names members missing pulse; null when covered; links to prefilled pulse date. |
| **F37** | Journey Fragility Radar | Expansion F37 | **COMPLETE** | `plan_intelligence_screen.dart` | `GET /api/trips/{id}/fragility` | `itinerary_items` | Buffers, tight connections, risky schedules, and alternatives calculated. |
| **F38** | Domino Map | Expansion F38 | **COMPLETE** | `plan_intelligence_screen.dart` | `POST /api/trips/{id}/domino` | `itinerary_items` | Ripple effects for item delay simulated; affected vs unaffected items shown. |
| **F39** | Protected Wander Window | Expansion F39 | **COMPLETE** | `itinerary_screen.dart` | `itinerary_items.is_protected` | `itinerary_items` | Hard constraint in engine, proposal approval, and manual edits; 409 on overlap; rescue leaves untouched. |
| **F40** | Expectation Reality Check | Expansion F40 | **COMPLETE** | `place_screen.dart` | `POST /api/activities/{id}/expectation` | `activities`, `places`, `place_reports` | Compares marketing claims against catalog evidence, reports, and unknowns. |
| **F41** | Door-to-Door Access Chain | Expansion F41 | **COMPLETE** | `place_screen.dart` | In place detail `access_chain` | `activities`, `places` | Stages: transport, path, entrance, experience, facilities, return with unknown handling. |
| **F42** | Discovery Balance Lens | Expansion F42 | **COMPLETE** | `discover_screen.dart` | Param `lens` in `/api/activities/search` | `activities` | Balanced, iconic, and similar weighting across catalog searches. |
| **F43** | Graceful Independent Time | Expansion F43 | **COMPLETE** | `itinerary_screen.dart` | `POST /api/itinerary-items/{id}/attendance` | `itinerary_attendance` | In / Join later / Skip; no reason required; privacy preserved. |
| **F44** | Material Change Watch | Expansion F44 | **COMPLETE** | `watch_screen.dart` | `/api/trips/{id}/material-watches*` | `material_watches` | Watches on hours/price/step-free; detects and displays changes. |
| **F45** | Fair Trade Negotiator | Expansion F45 | **COMPLETE** | `negotiate_screen.dart` | `POST /api/trips/{id}/negotiate` | `activities`, `trip_pulse` | Scores compromises with explicit who-benefits/who-compromises trade-offs. |
| **F46** | Local Context Requests | Expansion F46 | **COMPLETE** | `ground_screen.dart` | Shared with F31 | `ground_requests` | Focused, activity-scoped questions with timestamped observations. |
| **F47** | Journey Thread | Expansion F47 | **COMPLETE** | `thread_screen.dart` | `GET /api/me/thread` | `journey_thread` | Consented past signals carried forward (repeat, modify, avoid) into new trips. |
| **F48** | Neighborhood Respect Filter | Expansion F48 | **COMPLETE** | `place_screen.dart`, `engine_screen.dart` | In place detail & recommendations | `places.respect_note` | Curated respect guidance and fragile area notes shown with provenance. |
| **F49** | Decision Load Governor | Expansion F49 | **COMPLETE** | `dashboard_screen.dart`, `trip_overview_screen.dart` | `/api/trips/{id}/next-action`, quiet mode | `notifications` | Single highest-priority next action surfaced per journey; notifications throttled. |

---

## 3. Audit Classification Summary

| Classification | Count | Features |
|---|---|---|
| **COMPLETE** | **43** | F02, F03, F04, F05, F06, F07, F08, F09, F10, F14, F15, F16, F19, F20, F21, F22, F23, F24, F25, F26, F27, F28, F29, F30, F31, F32, F33, F34, F35, F36, F37, F38, F39, F40, F41, F42, F43, F44, F45, F46, F47, F48, F49 |
| **PARTIAL** | **5** | F01 (Export data in UI), F11 (Voice/video upload missing), F12 (AI Memory Studio missing embeddings/OCR/STT), F13 (CSV export in UI), F17 (Image option missing in UI, OCR backend unavailable) |
| **BROKEN** | **1** | F18 (Journey Replay Travel Book displays raw HTML markup instead of rendering document/print) |
| **UI_ONLY** | **0** | All existing UI screens trigger real API requests |
| **NOT_IMPLEMENTED** | **0** | Core logic exists for all 49 features; gaps are capability sub-features (Image Embeddings, Voice STT) |
| **BLOCKED** | **0** | No core feature completely blocked, though OCR requires local binary or on-device integration |

---

## 4. Primary Root Cause Analysis

### A. Journey Replay & Travel Book (F18 / F44)
- **Defect:** "Open travel book" button displays raw HTML markup (`<!DOCTYPE html>...`) in a bottom sheet.
- **Root Cause:**
  1. Backend `GET /api/trips/{trip_id}/travel-book` returns `HTMLResponse(content=html)`.
  2. Flutter `MemoryRepository.travelBook()` parses response raw text.
  3. Flutter `ReplayScreen._openTravelBook()` wraps text in `SelectableText(book)`.
  4. Flutter mobile dependencies (`pubspec.yaml`) lack `url_launcher` (to open in Chrome/external browser), `webview_flutter` (to render in-app), and `printing` (to trigger Android print/PDF spooler).

### B. Memory Studio Unimplemented Capabilities (F12 / F43)
- **Defect:** Memory Studio UI displays red disabled icons for:
  - Image embedding: `false`
  - OCR: `false`
  - Speech to text: `false`
- **Root Cause:**
  1. Backend `services/api/app/routers/memories.py` explicitly hardcodes `"image_embedding": False`, `"ocr": False`, `"speech_to_text": False` in the capabilities dictionary.
  2. No image embedding model (e.g. CLIP/ONNX) or vector storage column exists in `trip_memories`.
  3. Tesseract binary is not installed on the server; `pytesseract` and `Pillow` are missing from `services/api/.venv`.
  4. No audio recording or speech-to-text pipeline exists for "voice" memories.

### C. Media & Export Workflows Across the Application
- **Defect:** Every export action in the app (Travel Book, CSV Expenses, GDPR Account Data) displays raw string text in a bottom sheet instead of offering real file downloads, system share sheets, or document viewing.
- **Root Cause:** Flutter screens rely on `SelectableText` as a placeholder for file export rather than writing temporary files to storage and launching native intents via `share_plus` (`shareXFile`) or `url_launcher`.
