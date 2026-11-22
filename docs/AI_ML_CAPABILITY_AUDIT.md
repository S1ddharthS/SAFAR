# SAFAR — AI & ML Capability Audit

**Date:** 2026-11-22  
**Scope:** Rigorous evaluation of all artificial intelligence, machine learning, heuristic optimization, vector embedding, OCR, speech, and predictive capabilities in SAFAR.

---

## 1. System-Wide AI Philosophy & Operational Integrity

SAFAR adheres to five fundamental rules for intelligence:
1. **Grounded Over Generative:** The system never hallucinates prices, opening hours, crowd numbers, or personal facts. Every claim is tied to an underlying database row, user observation, or named provider.
2. **Strict Provenance Tagging:** Every fact, prediction, or suggestion carries a clear provenance label:
   - `VERIFIED`: Confirmed by official sources or platform moderators.
   - `CURATED`: Authored editorial seed catalog data.
   - `REPORTED`: Unverified observations submitted by community members or local contributors.
   - `ESTIMATED`: Calculated via deterministic heuristics or statistical projections.
   - `PREDICTED`: Inferred via machine learning or predictive forecasting models.
3. **Deterministic First & Transparent Baselines:** Core travel decisions (fairness, budget caps, time feasibility) use transparent, interpretable algorithms (Jain fairness index, haversine distance, MAD outlier filtering) rather than unexplainable black boxes.
4. **Consent-Gated Personalization:** Personal preferences, budget limits, and feedback sentiments influence algorithms only with explicit user consent (`personalization` and `feedback` purposes).
5. **No Silent Mutations:** AI recommendations or rescue proposals never alter confirmed plans directly. Every consequential change requires explicit member voting and admin approval.

---

## 2. Comprehensive Capability-by-Capability Audit

### 1. Group Experience Engine Ranking Core (F07)
- **Model / Algorithm:** Multi-criteria weighted linear utility ranking + Maximal Marginal Relevance (MMR) diversity selection ($\lambda = 0.15$) + bounded feedback adjustment ($\pm 4.0$ points).
- **Input Data:**
  - Candidate activities in destination.
  - Member Journey DNA vectors ($10$ dimensions: culture, nature, food, adventure, wellness, night, history, art, shopping, budget).
  - Trip Pulse for requested day (energy, time available, travel radius).
  - Hard constraints: stated budget limits, wheelchair accessibility, minimum indoor suitability.
  - Consent-gated group feedback reactions.
- **Output Data:** Top-$K$ ranked activities, each with `score`, `fairness`, `novelty`, `why_selected` explanation, and batch-level metrics (Jain's fairness index, mean fit, constraint violations).
- **Training / Inference:** No offline training. Real-time inference $O(N \times M)$ where $N$ = candidate activities, $M$ = group members. Execution latency $< 80\text{ ms}$ on staging.
- **Dependencies:** Curated catalog in PostgreSQL. Zero external API calls.
- **Confidence & Uncertainty:** Hard constraints filter out unsuitable candidates with zero tolerance. If no options satisfy all constraints, returns HTTP 422 with an explicit failure reason rather than relaxed guesses.
- **Evaluation Method:** Batch evaluation suite (`test_phase7_recommendations.py`). Asserts 0 constraint violations, Jain fairness index $> 0.85$, and diversity entropy $> 1.2$.
- **Fallback Behaviour:** If feedback data is insufficient ($< 3$ members or $< 2$ consented raters), feedback nudge drops to $0.0$; selection defaults to pure score order.
- **Implementation Status:** **COMPLETE & OPERATIONAL** (Version `safar-group-engine-1.5`).

---

### 2. Engine Recommendation Modes: Everyone Wins, Your Turn, Surprise Us (F07)
- **Model / Algorithm:**
  - *Everyone Wins:* Maximizes minimum member utility $\max \min_i u_i$ (Rawlsian maximin fairness).
  - *Your Turn:* Prioritizes the member with the lowest historical inclusion score, applying a $1.8\times$ weight to their preference vector.
  - *Surprise Us:* Inverts familiarity weights, rewarding unexplored catalog categories while enforcing a minimum utility floor ($u_i \ge 0.50$).
- **Input Data:** Group member profiles, voting history, attendance history, and activity metadata.
- **Output Data:** Mode-customized candidate set and human-readable explanation of why this pick fits the chosen mode.
- **Training / Inference:** Deterministic linear scoring during recommendation request.
- **Confidence & Fallback:** If historical participation is equal, "Your Turn" rotates deterministically; if novelty options violate budget, "Surprise Us" falls back to safe moderate-novelty options.
- **Implementation Status:** **COMPLETE & OPERATIONAL**.

---

### 3. Predictive Crowd Forecasting (F21)
- **Model / Algorithm:** `bucket-forecast-v2` — Statistical time-series model combining:
  1. Median Absolute Deviation (MAD) outlier rejection ($\text{modified } z\text{-score} > 3.5$).
  2. Exponential recency weighting ($180$-day historical window, half-life $60$ days).
  3. Hierarchical fallback pooling (`weekday_daypart` $\to$ `weekday` $\to$ `destination_hour`).
  4. Calibrated $80\%$ prediction intervals ($[\text{lower}, \text{upper}]$).
- **Input Data:** Community reports in `place_reports` with `category='crowd'` and numeric level $1..5$.
- **Output Data:**
  - `observed`: Raw observations count, latest report, and provenance `REPORTED`.
  - `predicted`: Projected crowd score ($1.0..5.0$), $80\%$ confidence bounds, and granularity label.
- **Training / Inference:** Dynamic statistical aggregation per request.
- **Confidence & Uncertainty:** Requires $\ge 8$ eligible crowd reports in the window. If reports $< 8$, returns `insufficient_data` state with latest observation rather than a fabricated forecast.
- **Evaluation Method:** Synthetic validation suite (`test_phase7_forecasting.py`), verifying interval coverage and outlier elimination.
- **Fallback Behaviour:** Explicit `insufficient_data` card in UI; never invents crowd numbers.
- **Implementation Status:** **COMPLETE & OPERATIONAL**.

---

### 4. Multilingual Grounded Conversational Assistant (F22)
- **Model / Algorithm:** Rule-based natural language understanding (NLU):
  1. Unicode script detection (Devanagari, CJK, Latin, Arabic, Cyrillic).
  2. Stopword density scoring for Latin scripts (English, Spanish, French, German, Portuguese, Italian).
  3. Multilingual regex and keyword intent lexicons across 14 travel intents.
  4. Context-pack grounded slot filling and localized response realization.
- **Input Data:** User query string, user preferred language, active trip context (itinerary, budget, proposals, pact).
- **Output Data:** Localized answer text, citations with source IDs and provenance, `mutation='none'`, and actionable suggested action chips.
- **Training / Inference:** Pure regex/lexicon matching; zero remote API calls; response time $< 40\text{ ms}$.
- **Confidence & Uncertainty:** If intent is ambiguous or required slots are missing, generates a grounded clarifying question (F36). Unsupported scripts return a polite English explanation noting the detected script.
- **Evaluation Method:** Automated suite (`test_phase7_multilingual.py`) covering all 8 languages, translation disclosures, and anti-hallucination probes.
- **Fallback Behaviour:** Unsupported language $\to$ English response with localized disclaimer. Unknown intent $\to$ capability statement.
- **Implementation Status:** **COMPLETE & OPERATIONAL** (Version `safar-grounded-i18n-2.0`).

---

### 5. Memory Studio: Event Grouping (F12 / F43)
- **Model / Algorithm:** Temporal clustering + spatial proximity association:
  1. Memories grouped into sessions if captured within a rolling $3$-hour window ($\Delta t \le 3\text{h}$).
  2. Nearest itinerary item matched if within $1.0\text{ km}$ haversine distance or within $\pm 90$ minutes of scheduled start.
- **Input Data:** `trip_memories` (timestamps, latitude, longitude, author) and `itinerary_items`.
- **Output Data:** Proposed `memory_events` with auto-generated title ("Moments around Kinkaku-ji"), time span, member list, and summary.
- **Training / Inference:** Deterministic sessioning algorithm executed on `POST .../suggest-events`.
- **Confidence & Uncertainty:** If no nearby itinerary item matches, title falls back to date-based naming ("Moments on Nov 20"). All suggestions default to `status='suggested'` and require human approval.
- **Evaluation Method:** Verified in `services/api/tests/test_audit_fixes.py` (ensures private memory metadata is never leaked).
- **Implementation Status:** **COMPLETE & OPERATIONAL**. (Note: UI currently lacks drag-and-drop event splitting or manual re-grouping).

---

### 6. Memory Studio: Caption Grounding (F12 / F43)
- **Model / Algorithm:** Deterministic template slot-filler combining user note, confirmed itinerary context, upload timestamp, and media kind.
- **Input Data:** Target `trip_memory` row and trip itinerary.
- **Output Data:** Suggested caption text, `ai_generated: false`, `generator: 'template'`, and disclosure.
- **Implementation Status:** **COMPLETE & OPERATIONAL**. (Honest template realization; generative LLM captions intentionally absent).

---

### 7. Memory Studio: Image Embeddings & Visual Similarity (F12 / F43)
- **Claimed in UI:** Backend reports `image_embedding: false` (remote cloud embeddings disabled for privacy); Mobile UI reports `On-Device 128-d Vector: Active`.
- **Model / Algorithm:** On-device 128-dimensional dense perceptual unit embeddings (`ImageFeatureExtractor` in pure Dart):
  1. Downsamples image to 16x16 perceptual matrix with luminance and RGB normalization.
  2. 64-d quadrant chromatic distribution and warmth metrics: $(R - B) \in [-1.0, 1.0]$, contrast $\max(L) - \min(L)$, and HSV saturation.
  3. 32-d directional spatial gradient energy histograms: horizontal and vertical edge variations.
  4. L2 unit normalization: $\sum v_i^2 = 1.0$.
  5. Cosine similarity metric: $(A \cdot B) / (\|A\| \|B\|) \in [0.0, 1.0]$.
- **Execution:** 100% on-device in Flutter. Execution latency $< 40\text{ ms}$ on physical Android device (Motorola Edge 50 Pro).
- **Privacy:** 100% local; zero image bytes or embeddings are sent to third-party vision APIs.
- **Evaluation Method:** Verified in `batch2_master_test.dart` (asserts 128-d vector, unit norm, identical vector similarity = 1.0, and distinct scene discrimination).
- **Implementation Status:** **COMPLETE & OPERATIONAL (ON-DEVICE MOBILE)**.

---

### 8. Optical Character Recognition (OCR) (F12 / F17)
- **Claimed in UI:** Backend reports `ocr: false` (remote Tesseract disabled); Mobile UI reports `On-Device Google ML Kit OCR: Active`.
- **Model / Algorithm:** Google ML Kit Text Recognition (`google_mlkit_text_recognition`) Latin script recognition engine running on-device via Android ML Kit runtime.
- **Input Data:** Camera or gallery images ($\le 25\text{ MB}$) selected in `ImportScreen`.
- **Output Data:** Structured text blocks and lines, extracted string, and provenance tracking.
- **Human In The Loop:** Extracted text is presented in an editable review field before candidate extraction; users must approve or edit draft text. Never automatically commits unverified bookings.
- **Evaluation Method:** Verified in `batch2_master_test.dart` (preserves blocks, lines, error handling, and draft editing).
- **Implementation Status:** **COMPLETE & OPERATIONAL (ON-DEVICE MOBILE)**.

---

### 9. Speech to Text (STT) / Audio Transcription (F11 / F12 / F43)
- **Claimed in UI:** Backend reports `speech_to_text: false` (server-side Whisper disabled); Mobile UI reports `On-Device Speech Recognition: Active`.
- **Model / Algorithm:** On-device Android SpeechRecognizer service integrated via `speech_to_text` with microphone permission checks and `SpeechListenOptions`.
- **Input Data:** Live spoken audio stream from Android microphone.
- **Output Data:** Real-time recognized text stream with continuous partial results.
- **Integrations:**
  - `MemoriesScreen`: Voice dictation helper for memory captions.
  - `StudioScreen`: Voice dictation modal for rapid thought capture.
  - `VoiceRecorderService`: High-fidelity 44.1 kHz WAV recording (`record`) and audio playback preview (`audioplayers`).
- **Implementation Status:** **COMPLETE & OPERATIONAL (ON-DEVICE MOBILE)**.

---

### 10. Dream-to-Destination Import (F17)
- **Model / Algorithm:** Deterministic structural parser:
  1. Word-boundary token and phrase matching against catalog names.
  2. Hashtag and URL path segment tokenization.
  3. Regular expression extraction for budgets, dates, and trip durations.
  4. Provenance tracking: assigns stable `candidate_id` and exact `source_span` to each candidate.
- **Input Data:** Raw text notes, copied articles, URLs, or image screenshots/tickets via gallery/camera picker and on-device OCR.
- **Output Data:** List of `InspirationCandidate` items with match confidence ($0.0..1.0$) and review status (`pending`, `accepted`, `rejected`).
- **Dependencies:** Curated catalog. Optional link metadata (`app/integrations/links.py`, disabled by default).
- **Evaluation Method:** 10 automated test cases in `test_phase7_dream_import.py` and `batch2_master_test.dart`.
- **Implementation Status:** **COMPLETE & OPERATIONAL (TEXT, IMAGE & OCR)**.

---

### 11. Trip Rescue & Autopilot (F09)
- **Model / Algorithm:** Heuristic rule-based disruption solver:
  - Detects impact of rain (swaps outdoor for indoor), closure (finds open alternatives within travel radius), traffic/fatigue (reduces pace, increases rest buffers).
  - Enforces `is_protected` invariant: never reschedules protected wander windows.
- **Input Data:** Disruption kind, affected itinerary item, extra minutes delay, and confirmed itinerary.
- **Output Data:** Analyzed impact assessment + suggested replacement activities.
- **Implementation Status:** **COMPLETE & OPERATIONAL**.

---

### 12. Opportunity Clock (F24)
- **Model / Algorithm:** Temporal geometry & feasibility solver:
  - Parses catalog opening hours (`open_time`, `close_time`, days of week).
  - Deducts confirmed itinerary slots (08:00–22:00 window).
  - Computes haversine travel time between current location and candidate places.
  - Classifies candidates as `open_now`, `later_today`, `closed_today`, or `passed`.
- **Implementation Status:** **COMPLETE & OPERATIONAL**.

---

### 13. Fair Trade Negotiator (F45)
- **Model / Algorithm:** Pairwise multi-attribute compromise utility solver:
  - Evaluates two competing options against all group member preferences.
  - Computes net group gain, identifying who benefits ($+ \Delta u$) and who compromises ($-\Delta u$).
  - Never reveals private member budget numbers or private notes.
- **Implementation Status:** **COMPLETE & OPERATIONAL**.

---

### 14. Domino Map & Journey Fragility Radar (F37, F38)
- **Model / Algorithm:**
  - *Domino Map:* Simulates cascade delay ripples across remaining items of the day, calculating buffer depletion and identifying broken connections.
  - *Fragility Radar:* Calculates transition risk scores based on transfer times, tight buffers ($< 20\text{ mins}$), and dense afternoon schedules.
- **Implementation Status:** **COMPLETE & OPERATIONAL**.

---

### 15. External AI Provider Integration & Status
- **OpenAI / Remote LLM Integration:**
  - `OPENAI_API_KEY` configuration exists in settings, but is **deliberately disconnected**.
  - Health endpoint explicitly reports `"external_ai": false`.
  - Capabilities endpoint reports `"generative_ai": false`.
  - **Assessment:** Safely configured to fail-closed and report truth. No API keys are leaked to mobile clients.
