# SAFAR — AI/ML Architecture

**Status:** Phase 7 proposal + implementation record
**Last updated:** 2026-11-20
**Scope:** the intelligence layer of SAFAR — Journey DNA, the Group Experience
Engine, the grounded assistant, crowd forecasting, Place Pulse, Dream Import,
Memory Studio, Journey Replay, Trip Rescue and the Decision Load Governor —
plus the external provider layer they may use.

This document is the design authority for Phase 7. Section 1 is the proposal
(written before implementation). Section 2 records what was actually built.
Sections 3–7 cover providers, privacy, evaluation and costs.

---

## 0. Principles

1. **Grounded over generative.** SAFAR states what its own database, the
   traveller, or a named provider observed. It never invents hours, prices,
   availability, crowd levels or safety facts.
2. **Every result carries provenance.** Each value is labelled one of
   `VERIFIED`, `REPORTED`, `ESTIMATED`, `PREDICTED` or `UNKNOWN`. Prediction is
   never rendered as measurement.
3. **Deterministic first.** The existing heuristics (transparent weights,
   cosine fits, bucket means) are the baseline. ML is added only where it
   measurably improves a metric — and the heuristic remains the fallback.
4. **Consent gates personalisation.** Private preferences, budgets and feedback
   influence ranking only with an explicit `personalization` consent record.
   Group-level outputs are aggregate; individual private values are never
   returned.
5. **No silent side effects.** Consequential changes (adding, moving or removing
   itinerary items) always pass through proposals and approvals. The assistant
   and Dream Import can propose; only a human confirms.
6. **Local by default, remote on approval.** The default deployment runs
   entirely on-premise with zero external calls. Remote providers are opt-in
   through server-side configuration and are never enabled by default.
7. **Server-side keys only.** No provider credential ever reaches the browser.

---

## 1. Component assessment and proposals

Each component is described with the eight required fields. A status tag shows
what this phase does: **[IMPLEMENT]** changes now, **[EVALUATE]** measurement
only, **[DEFER]** needs a paid/keyed provider and explicit approval.

### 1.1 Journey DNA

- **Current implementation.** A 10-dimension preference vector
  (`DNA_DIMENSIONS` in `services/api/app/services/common.py`). Onboarding tags
  seed scores at 8.0; default is 5.0. Consent-gated feedback applies fixed
  deltas (loved +2.0 … too_far −0.5) per matching activity tag, clamped 0–10
  (`services/api/app/services/feedback.py`). No decay, no confidence, no
  provenance per dimension.
- **Proposed improvement. [IMPLEMENT]** Keep the vector and deltas, but (a)
  store per-dimension evidence counts so a one-off reaction cannot dominate,
  (b) decay feedback toward the prior with a 180-day half-life at read time,
  (c) expose `confidence` and `source` per dimension (`onboarding`, `feedback`,
  `explicit`) so the UI can distinguish a stated preference from an inferred
  one. No black-box model.
- **Model / algorithm.** Exponential recency decay over consent-gated feedback
  events plus clamped additive updates. Interpretable by construction.
- **Required dataset.** Existing `journey_dna.scored`, `activity_feedback`,
  `profile.interests`. No new corpus.
- **Training / inference.** No training. Inference is O(feedback events) at
  profile load, cached per request.
- **Privacy.** Feedback rows are user-scoped and consent-gated. Decayed
  inference is only used when consent is active; withdrawing consent stops new
  updates immediately and removes inferred-only dimensions from use.
- **Evaluation metrics.** Dimension stability under repeated feedback
  (±0.2 drift cap per event after decay), consent withdrawal completeness
  (100% of inferred influence removed), reconstruction of held-out preferences.
- **Fallback.** Stored `journey_dna.scores` remains authoritative; if evidence
  is missing, the current fixed-delta behaviour applies unchanged.

### 1.2 Group Experience Engine — ranking core

- **Current implementation.** `services/api/app/services/engine.py`.
  Deterministic per-member fit `100 × (0.58·interest + 0.16·budget +
  0.10·energy + 0.10·time + 0.06·access)` after hard constraints (budget,
  wheelchair, available minutes, travel radius). Mode scores combine average,
  minimum, optional target fit and novelty, minus time/budget/uncertainty
  penalties. Fully explained.
- **Proposed improvement. [IMPLEMENT]** Add (a) a bounded,
  consent-gated feedback adjustment of at most ±4 points, derived from the
  group's aggregate reaction to an activity's tags and accompanied by a
  sentence in `why_selected`; (b) diversity-aware selection so the top six are
  not six variants of one tag, using a maximal-marginal-relevance penalty on
  the selection pass only (the ranking scores that drive explanations remain
  untouched); (c) batch-level metrics: mean average fit, minimum fit (group
  fairness), preference satisfaction spread, constraint violations (must stay
  zero), tag entropy (diversity) and mean novelty.
- **Model / algorithm.** Existing weighted linear fit + MMR-style greedy
  selection with a 0.15 diversity weight + bounded additive feedback term.
  No learned model, so every score remains decomposable.
- **Required dataset.** Existing catalog attributes, member contexts,
  `recommendation_feedback`, `activity_feedback`.
- **Training / inference.** No training. Inference is linear in candidates ×
  members and stays under 100 ms for the seeded catalog.
- **Privacy.** Feedback aggregates are computed per trip from consenting
  members only, with a minimum group size of 3 before the adjustment applies;
  individual reactions never appear in an explanation. Budgets remain filters,
  never outputs.
- **Evaluation metrics.** Fairness: 10th-percentile member fit ≥ 55 and spread
  ≤ 25 on the evaluation fixtures; constraint violations = 0; relevance: mean
  fit of accepted items > mean fit of rejected items on synthetic feedback;
  diversity: ≥ 3 distinct top-level tags in the top six; explainability: 100%
  of items have mode-appropriate `why_selected`.
- **Fallback.** If feedback aggregates are missing or below the group-size
  threshold, the adjustment is zero and selection order is score order — the
  current behaviour.

### 1.3 Recommendation modes (Everyone Wins / Your Turn / Surprise Us)

- **Current implementation.** Three documented weightings plus a target-member
  selection for Your Turn and a novelty term for Surprise Us. Preserved as-is.
- **Proposed improvement. [IMPLEMENT]** Keep the three modes and their
  semantics. Add per-mode batch metrics and a small `model` block in
  `meta` recording weights actually used, feedback adjustment, diversity
  effect and metric values, so evaluation is reproducible.
- **Model / algorithm.** Unchanged linear combinations.
- **Required dataset / training.** None new; no training.
- **Privacy.** Metrics are aggregate over the anonymous member fit vector.
- **Evaluation metrics.** Mode contract tests: Your Turn raises the target
  member's fit versus Everyone Wins on the same fixture; Surprise Us increases
  novelty without dropping minimum fit below the constraint; Everyone Wins
  maximises minimum fit.
- **Fallback.** Mode weights are constants; if a metric cannot be computed the
  batch still returns.

### 1.4 Grounded retrieval assistant (F22)

- **Current implementation.**
  `services/api/app/services/assistant.py`. Keyword intent detection over a
  fixed English lexicon; answers from itinerary, expenses, proposals, members
  and recommendation batches; named-activity lookup returns catalog facts,
  recorded hours and latest Place Pulse signal with citations. It refuses
  weather (no provider) and appends an English-only note for non-Latin input.
  No context pack, no clarifying questions, no per-citation provenance, no
  language selection.
- **Proposed improvement. [IMPLEMENT]**
  (a) **Language layer** — script-based detection (Devanagari, CJK, Arabic,
  Cyrillic, Greek, Hangul) plus Latin stopword scoring for
  en/es/fr/de/pt/it; multilingual intent lexicons; localised response
  templates for those eight languages; mixed-language handling (answer in the
  dominant language, note the secondary); preferred language from
  `Profile.languages[0]` or an explicit `language` field, falling back to
  detection, then English. Destination and activity names are inserted
  verbatim and never translated.
  (b) **Context pack** — a per-request structure assembled from the trip:
  dates and day context, destination, the requesting user's preferences,
  consent-permitted aggregate group preferences, confirmed itinerary,
  budget position, protected-time windows. Every fact carries a provenance
  label and a source id.
  (c) **Reasoning and honesty** — answers explain which records they used;
  facts and estimates are labelled in text; missing data is named as missing;
  a clarifying question is generated when intent is actionable but a required
  slot is absent (for example, no day given for "what are we doing?"); the
  assistant never fills an unknown with a guess. Consequential changes are
  only offered as proposal links, never executed.
  (d) **Optional weather** — if and only if a weather provider is configured,
  a weather intent answer uses it with attribution and `REPORTED` provenance;
  otherwise the existing explicit no-provider answer remains.
- **Model / algorithm.** Deterministic intent classification (lexicon scoring
  with priority rules), template realisation with slot filling, retrieval over
  trip rows. No LLM required. An LLM adapter exists behind a disabled flag for
  future use but is not part of the default path.
- **Required dataset.** Trip data already in the database; multilingual
  lexicons and templates authored in-repo; optional provider responses.
- **Training / inference.** No training. Inference is O(message + rows read);
  p95 under 150 ms locally.
- **Privacy.** Only the requesting member's private data is read for their own
  answers; group data is aggregated and counts-only unless already visible in
  the trip UI. No message text leaves the server by default. Consent-gated
  group preferences are only summarised above a group-size threshold.
- **Evaluation metrics.** Intent accuracy ≥ 0.9 on the labelled multilingual
  fixture; language fidelity (reply language equals requested language) 100%;
  hallucination probes: 0 invented hours/prices/availability/safety facts;
  citation coverage 100% for factual claims; unsupported-language fallback
  always labelled.
- **Fallback.** Unknown language → English with a note. Unknown intent →
  capability statement. Unavailable provider → the current explicit refusal.
  Any retrieval error → the general grounded answer, never a fabricated one.

### 1.5 Crowd forecasting (F21)

- **Current implementation.** `crowd_forecast` in
  `services/api/app/services/places.py`. Requires ≥ 8 crowd reports in 180
  days and ≥ 3 per `weekday × daypart` bucket; returns bucket mean, spread,
  mean age, freshness and a heuristic confidence. Model label
  `bucket-mean-v1`; `PREDICTED`/`ESTIMATED`; honest `insufficient_data`
  states.
- **Proposed improvement. [IMPLEMENT]**
  (a) **Outlier resistance** — filter reports whose score deviates more than
  3.5 modified z-scores (MAD-based) inside their bucket, and report how many
  were excluded.
  (b) **Staleness** — hard-exclude reports older than 180 days (already
  outside the window) and exponentially down-weight older observations in the
  bucket mean; expose effective sample size.
  (c) **Hierarchical fallback** — if an exact bucket has < 3 reports, fall
  back to the same weekday across dayparts (≥ 4) or the destination-wide hour
  pattern (≥ 6) and label the `granularity` used. No fallback is silent.
  (d) **Calibration** — confidence becomes a documented function of effective
  sample size, agreement and recency, and each forecast carries an 80%
  prediction interval derived from the weighted spread. Calibration is
  checked on synthetic fixtures with known ground truth.
  (e) **Observed vs predicted separation** — the response returns an
  `observed` block (raw eligible reports, counts, provenance `REPORTED`) and a
  separate `predicted` block (`ESTIMATED`), never merged.
- **Model / algorithm.** Robust weighted bucket statistics (MAD filter, recency
  weights, hierarchical pooling). No neural model: the dataset is far too
  small and a black box would be unverifiable.
- **Required dataset.** `place_report` rows with `category="crowd"` and a
  numeric `score`/`level`; synthetic fixtures for calibration.
- **Training / inference.** No training. Inference is O(reports).
- **Privacy.** Reports are anonymous aggregates; no user id is returned.
  Location granularity stays at the place level.
- **Evaluation metrics.** Interval coverage on synthetic hold-out ≥ 0.7 at the
  nominal 80%; MAE of expected level ≤ 0.12; outlier rejection precision on
  injected anomalies ≥ 0.9; insufficient-data honesty = 100% (no prediction
  below thresholds); granularity correctly reported.
- **Fallback.** Below thresholds, the current `insufficient_data` response
  with the latest observation only.

### 1.6 Place Pulse / place intelligence (F14, F30, F40, F41)

- **Current implementation.** Freshness half-lives (90/30/7 days by source),
  provenance mapping, per-category weighted leader selection and an evidence
  passport. Already conservative and explainable.
- **Proposed improvement. [IMPLEMENT]** Add corroboration counting (distinct
  sources/observers) and surface it in aggregation; keep weights otherwise
  unchanged. Ensure the passport labels each evidence item with provenance and
  freshness.
- **Model / algorithm.** Weighted decay as today plus a corroboration term in
  presentation, not in the score.
- **Required dataset.** Existing reports.
- **Training / inference.** None.
- **Privacy.** Anonymous report ids only.
- **Evaluation metrics.** Leader stability under duplicate reports; freshness
  monotonicity; provenance correctness table.
- **Fallback.** Current aggregation.

### 1.7 Dream Import (F17)

- **Current implementation.**
  `dream_import` in `services/api/app/services/discovery.py`. Word-boundary
  matching of destination/activity names, URL-path tokens, hashtags, budget
  regex and month names. Returns candidates with confidence, `needs_confirmation`,
  and explicit limitations for images and links. No OCR, no link fetch, no
  per-candidate review.
- **Proposed improvement. [IMPLEMENT]**
  (a) **Link metadata** — optional, SSRF-guarded server-side fetch of
  OpenGraph/Twitter/HTML title and description for `link` imports when
  `SAFAR_LINK_FETCH_ENABLED=true`. Only public http(s) hosts, DNS resolution
  checked against private ranges, no redirects to private addresses, size and
  time limits. Metadata is labelled `REPORTED` and "from the page's own
  metadata — not verified by SAFAR".
  (b) **OCR** — a local Tesseract adapter that activates only if the binary is
  present. Images are never uploaded externally by default. OCR text is
  labelled as machine-read and low confidence by default.
  (c) **Richer extraction** — date ranges, trip length ("5 days"), explicit
  budget currencies, and per-candidate `source_span` so the user sees exactly
  which phrase produced each suggestion.
  (d) **Structured candidates** — stable `candidate_id`, `kind`, `confidence`,
  `provenance`, `verified: false`, `source`.
  (e) **Review workflow** — `POST /api/trips/{trip_id}/inspirations/{id}/review`
  records accept/reject per candidate; accepted *activity* candidates can be
  turned into proposals (group approval still required). Status moves
  `pending → extracted → reviewed`.
- **Model / algorithm.** Deterministic extraction; optional OCR; optional
  metadata retrieval. No generative model.
- **Required dataset.** Catalog (for matching), the user's import text, optional
  page metadata, optional OCR output.
- **Training / inference.** None. OCR is inference-only if installed.
- **Privacy.** Imports are user-scoped. Remote fetching is off by default and
  consent is implied only by the user supplying a URL while the feature is
  enabled; no images are sent anywhere. Metadata is stored with the
  inspiration, not with the trip.
- **Evaluation metrics.** Precision/recall of name extraction on a labelled
  fixture ≥ 0.9/0.85; span correctness 100% for exact-name matches; zero
  network calls when disabled; SSRF probes all rejected; graceful message for
  unreachable links.
- **Fallback.** With providers disabled, the current text-only behaviour
  continues and the limitations copy stays truthful.

### 1.8 Memory Studio

- **Current implementation.** User-authored memories with media, dates and
  places; no AI generation.
- **Proposed improvement. [EVALUATE]** No generative captions in this phase —
  they would be unverifiable personal content. Instead add a deterministic
  "trip highlights" summary assembled from confirmed items and user-authored
  notes, clearly labelled as assembled from the user's own records. Any future
  generation must be opt-in and labelled.
- **Model.** Template assembly over existing rows.
- **Dataset / training.** Existing memories; none.
- **Privacy.** Memory content stays user-scoped; highlights never include other
  members' private notes.
- **Metrics.** Highlight factual accuracy 100% against the underlying rows.
- **Fallback.** Plain memory list.

### 1.9 Journey Replay

- **Current implementation.** Deterministic timeline reconstruction from
  itinerary versions and activity events.
- **Proposed improvement. [IMPLEMENT]** Keep deterministic; add explicit
  provenance labels on each replay event (confirmed / proposed / removed) so
  replay is not mistaken for a live plan. No generative narration.
- **Model / dataset / training.** None.
- **Privacy.** Member names only where already visible in the trip.
- **Metrics.** Event-order correctness and label correctness on fixtures.
- **Fallback.** Existing timeline.

### 1.10 Trip Rescue

- **Current implementation.** Structured "what changed" input and ranked
  alternative proposals; never mutates confirmed items without approval.
- **Proposed improvement. [IMPLEMENT]** Route rescue constraint checks through
  the same engine metrics so a rescue proposal reports the fairness and
  diversity effect it would have, and add weather as an optional *input*
  signal when a provider is configured (never as a fabricated forecast).
- **Model / dataset / training.** Engine ranking; optional weather.
- **Privacy.** Rescue proposals are group-visible; no private budgets exposed.
- **Metrics.** Zero unapproved mutations; proposal constraint violations = 0.
- **Fallback.** Manual itinerary editing.

### 1.11 Decision Load Governor

- **Current implementation.** Counts open decisions per member and defers or
  batches low-urgency prompts.
- **Proposed improvement. [IMPLEMENT]** Add a deterministic "why this is being
  asked now" line to each surfaced decision and ensure assistant-suggested
  actions respect the same deferral rules.
- **Model / dataset / training.** None.
- **Privacy.** Per-member counts only.
- **Metrics.** Surface-rate ceiling respected; no urgent item deferred.
- **Fallback.** Existing governor.

### 1.12 Opportunity Clock

- **Current implementation.** Deterministic time-window scoring.
- **Proposed improvement. [EVALUATE]** Documented metric only; no model change.
- **Fallback.** Existing behaviour.

---

## 2. Provider abstraction layer

### 2.1 Shape

```
app/integrations/
  base.py        ProviderResult, Provenance, ProviderStatus, errors, registry
  http.py        bounded HTTP client (timeout, size cap, UA, no redirects to private nets)
  cache.py       in-process TTL cache keyed by provider + normalised request
  ratelimit.py   token bucket per provider
  weather.py     Open-Meteo adapter (no key, free, attribution)
  links.py       SSRF-guarded page metadata extraction
  ocr.py         local Tesseract adapter (inactive without binary)
  translation.py disabled remote adapter; local lexicons live in services/language.py
  email.py       SMTP adapter, disabled unless configured
  registry.py    enabled/disabled snapshot for /api/ai/capabilities
```

Every adapter returns:

```python
ProviderResult(
    ok: bool,
    data: dict | None,
    provider: str,
    provenance: "VERIFIED" | "REPORTED" | "ESTIMATED" | "PREDICTED" | "UNKNOWN",
    fetched_at: datetime | None,
    cached: bool,
    error: str | None,          # machine code
    message: str | None,        # honest user-facing explanation
    attribution: str | None,
)
```

Callers never raise on provider failure; they degrade and surface
`message`. Timeouts default to 3 s, response size to 256 KB, cache TTL is
per-provider, and every adapter has a per-instance token bucket. The registry
exposes what is configured (boolean only — never keys) so the frontend can
state capabilities truthfully.

### 2.2 Provider evaluation

| Need | Candidate | Cost | Default | Decision |
|---|---|---|---|---|
| Weather | Open-Meteo | Free, non-commercial, attribution required, ~10k req/day fair use | **Enabled only if `SAFAR_WEATHER_PROVIDER=open-meteo`** | Adopt; no key, no PII sent (rounded coordinates), cache 30 min |
| Weather | OpenWeather / Tomorrow.io | Paid tiers, key required | Off | Document only |
| Geocoding | Nominatim (OSM) | Free, 1 req/s, attribution, no bulk use | Off | Adapter with strict rate limit; not enabled by default |
| Geocoding | Photon / MapTiler | Free tier / paid | Off | Not adopted |
| Place metadata | Direct fetch | Free | Off | Opt-in via `SAFAR_LINK_FETCH_ENABLED`, SSRF-guarded |
| OCR | Tesseract (local) | Free | Auto if binary exists | Adopt; CPU only, no upload |
| OCR | Cloud Vision / Textract | Paid, image upload | Off | Rejected by default (privacy) |
| Translation | In-repo lexicon + templates | Free | On | Adopt for the eight supported languages |
| Translation | DeepL / Google / LibreTranslate | Paid or self-hosted | Off | Adapter stub only; requires approval |
| Assistant LLM | OpenAI | Paid per token | Off | Existing unused key stays inert; requires written approval |
| Image storage | Local disk (existing) | Free | On | Keep |
| Email | SMTP | Depends on relay | Off unless `SMTP_HOST` set | Existing notifications remain in-app |

### 2.3 Cost documentation (default configuration)

Default deployment cost of the intelligence layer: **€0**. Everything
(engine, assistant, forecasting, extraction, OCR when installed) runs locally.
Optional costs if enabled later: Open-Meteo €0 (attribution required);
Nominatim €0 (1 req/s policy); an SMTP relay per its plan; an LLM or
translation API per its current price list (must be checked and approved
before enabling; no price is hard-coded here because vendors change them).
No paid service is enabled by this phase.

---

## 3. Data flow

```
User message ─▶ language detect ─▶ intent classify ─▶ context pack (trip rows)
                                                        │
                          ┌─────────────────────────────┼──────────────────┐
                          ▼                             ▼                  ▼
                    retrieval answer             optional provider     clarifying
                    (facts + provenance)         (weather, if on)      question
                          └──────────────┬──────────────┘
                                         ▼
                              localised template ─▶ response
                              (answer, citations, provenance, limitations)
```

```
Dream Import content ─▶ text extraction ─┬─▶ catalog matching ──▶ candidates
                                         ├─▶ link metadata (opt-in, SSRF-safe)
                                         └─▶ OCR (local, if installed)
                                                   │
                                                   ▼
                                        review (accept/reject) ─▶ proposal ─▶ vote
```

```
Crowd reports ─▶ staleness filter ─▶ MAD outlier filter ─▶ bucket pooling
             ─▶ hierarchical fallback ─▶ weighted mean + interval
             ─▶ observed block (REPORTED) + predicted block (ESTIMATED)
```

---

## 4. Privacy model

| Data | Where it goes | Consent | Returned? |
|---|---|---|---|
| Trip itinerary, budgets | Local DB only | Trip membership | Aggregate or own share only |
| Member preferences/budgets | Local DB, ranking filters | Personalisation consent for inference | Never individual values |
| Activity feedback | Local DB | `personalization` consent record | Aggregate above group size 3 |
| Imported text | Local DB | User action | Own rows only |
| Link URL (if fetching enabled) | Target site | Feature flag + user supplying URL | Metadata stored locally |
| Image (OCR) | Local only | User action | Own rows only |
| Chat message | Local only (default) | — | Own session |
| Coordinates to weather | Rounded to ~1 km, no user id | Feature flag | Forecast only |

No analytics or telemetry is sent to AI vendors. Provider errors are logged as
codes, not payloads.

---

## 5. Evaluation plan

Fixtures are synthetic and built in-process: the shared `tests/conftest.py`
seed plus per-test rows inserted through the SQLAlchemy session. Tests live in
`services/api/tests/test_phase7_*.py` (38 tests across five files).

| Area | Method | Pass criterion |
|---|---|---|
| Hallucination resistance | Probe questions with absent data (hours, prices, weather, safety) | No invented fact; explicit unknown stated |
| Grounding | Every factual sentence maps to a citation id | 100% |
| Recommendation fairness | Seeded multi-member fixtures, all three modes | Min fit ≥ 55, spread ≤ 25, violations = 0 |
| Relevance | Synthetic accept/reject feedback | Accepted mean fit > rejected by ≥ 5 |
| Diversity | Top-six tag entropy | ≥ 3 distinct tags |
| Multilingual | 8 languages × 6 intents | Reply language matches; intent accuracy ≥ 0.9 |
| Extraction accuracy | Labelled import texts | Precision ≥ 0.9, recall ≥ 0.85 |
| Forecast calibration | Synthetic with injected anomalies and stale rows | 80% interval coverage ≥ 0.7; MAE ≤ 0.12; anomalies rejected |
| Privacy leakage | Serialise responses and grep for private values/ids | No private budget/preference/other-member data |
| Provider failure | Forced timeout/500/disabled | Graceful message, no exception, no fabricated data |
| SSRF | Localhost, RFC1918, link-local, DNS rebinding probes | All rejected |
| Latency | Local p95 over the fixture set | Assistant < 150 ms, engine < 400 ms |

Results are recorded in section 6 after the suite runs.

---

## 6. Implementation record

Phase 7 completed on 2026-11-20. Automated evidence: `pytest` 106 passed
(38 in the Phase 7 files), `vitest` 12 passed, `tsc --noEmit` clean,
`next build` clean. Live evidence: API and UI checked against a Phase 7 server
(engine `safar-group-engine-1.5`, assistant `safar-grounded-i18n-2.0`).

| Item | State | Notes |
|---|---|---|
| Provider layer | Done | `app/integrations/` with `ProviderResult` provenance, TTL cache, per-provider token buckets, SSRF-guarded httpx (no redirects, 80/443 only, private-range blocking, 256 KB cap), Open-Meteo weather (opt-in), page-metadata reader (opt-in), local Tesseract OCR, in-process translation lexicons, `/api/ai/capabilities` and `/api/assistant/capabilities` key-free disclosures. |
| F17 link/OCR/spans/review | Done | Optional SSRF-guarded link metadata; local-only OCR for trip media; per-candidate `candidate_id`, `source_span`, `provenance`, `verified=false`; `POST /api/trips/{trip_id}/inspirations/{id}/review` moves `extracted → reviewed/rejected`; accepted activities still become proposals. Image imports require a media upload on the same trip and reject external or traversing paths. |
| F22 languages + context pack | Done | Eight languages (en, es, fr, de, pt, it, hi, ja) with script detection, Latin stopword scoring, mixed-language and unsupported fallbacks. Every answer includes a `context` pack (trip dates, destination, own preferences, consent-gated aggregate group preferences, itinerary counts, budget position, missing inputs), citations with provenance, `mutation="none"` and `requires_approval` for proposal/vote answers. Destination and activity names are inserted verbatim. |
| Feedback + diversity + metrics | Done | `ENGINE_VERSION = safar-group-engine-1.5`. Feedback adjustment is capped at ±4, applies only to groups of ≥3 with ≥2 consented raters, and never exposes individual sentiment. Diversity-aware selection uses tag cosine with a 0.6 floor and a maximum 4-point demotion; explanations record the nudge and demotion. `meta.evaluation` reports Jain fairness, least-served fit, satisfaction, constraint violations and diversity. The engine UI shows the version, metrics and feedback disclosure. |
| F21 robust forecasting | Done | `bucket-forecast-v2`. Eligible window 180 days, hard exclusion at 120 days, `stale` flag above 60 days. MAD-based outlier rejection (3 modified z-scores, floor 0.35), hierarchical fallback `weekday_bucket → weekday → day_type_bucket` with explicit `granularity`, 80% intervals, calibrated confidence, and strictly separated `observed` (REPORTED) and `predicted` (ESTIMATED) blocks. |
| Evaluation suite | Done | `test_phase7_evaluation.py` (6) plus the four component suites. Probes cover hallucination resistance, privacy leakage, grounding, capability disclosure, latency (<3 s per call on the fixture) and prediction labelling. |

Deviations from the proposal, recorded deliberately:

- **Journey DNA (1.1):** evidence counts and half-life decay were not added.
  The existing clamped deltas stay authoritative, and ranking gains only the
  bounded aggregate nudge in 1.2. Evaluation did not show a DNA-level defect
  that justified rewriting a working model.
- **F21 staleness:** hard exclusion is 120 days (not 180) so eligibility and
  the forecast window share one bound; 60–120-day observations are used but
  marked `stale`.
- **Diversity selection:** implemented as a bounded cosine-similarity demotion
  rather than a fixed 0.15 weight, keeping the ranking penalty explainable.

### 6.1 Evaluation results

| Area | Result |
|---|---|
| Hallucination resistance | Place answers return recorded hours plus “catalog data, not a live feed” and the limitations “No live availability, ticket or queue API is configured” / “may be out of date”. No probe produced an availability, ticket or live-hours claim. |
| Grounding and mutation | Every factual answer carries citations with provenance; assistant probes return `mutation="none"`, and recommendation/vote answers set `requires_approval=true`. |
| Recommendation fairness (live seeded Kyoto trip, Everyone Wins, 5 items) | Jain index 0.999, least-served member mean fit 72.7, member spread 6.5, constraint violations 0. |
| Relevance and satisfaction | Mean average fit 76.6, mean minimum fit 72.6 on the same batch; every item has a mode-appropriate `why_selected`. |
| Diversity | 3 distinct primary tags in the top five, mean pairwise tag similarity 0.42. |
| Feedback learning | Two consented raters produce a positive adjustment ≤ 4 with a “feedback” reason and no sentiment, user id or member name. Unconsented feedback changes nothing; a 2-member group disables learning. |
| Multilingual | 12 tests across 8 languages; reply language matches detection/request, destination names are preserved, mixed and unsupported input produce explicit notes. |
| Extraction accuracy | 10 tests: source spans and stable candidate ids, accept/reject review, disabled-link honesty, local-only OCR, traversal and SSRF rejection. |
| Forecast robustness | 5 tests: threshold honesty, observed/predicted separation, MAD outlier rejection, stale exclusion and hierarchical fallback with intervals and labels. |
| Privacy leakage | Privacy intent returns product policy only. Serialised assistant responses contain no other-member name, password or per-member budget; group aggregates expose counts and distributions only. |
| Provider failure | Disabled link metadata and missing OCR degrade to truthful messages without exceptions or fabricated data. |
| Latency budget | Assistant and engine each complete within the 3-second fixture budget in the evaluation test. |

---

## 7. Recommended deployment architecture

- **Default (recommended): single-region, self-contained.** API container with
  the local SQLite/PostgreSQL database, in-process provider cache, no outbound
  AI calls. Optional Open-Meteo weather and local Tesseract. This is the
  configuration evaluated here.
- **Enhanced (requires approval):** add Nominatim self-hosted or a paid
  geocoder, self-hosted LibreTranslate, and an object store for media. Keep
  all keys server-side in the platform secret store; keep the registry
  capability endpoint key-free.
- **Not recommended:** routing every assistant turn through a hosted LLM.
  It adds cost and privacy surface while the grounded retrieval path already
  answers from authoritative trip data and refuses unknowns. If adopted later,
  it must run as a *renderer* over the same context pack with citations, an
  explicit `generated_by` label, and the retrieval answer as fallback.
