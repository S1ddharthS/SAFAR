SAFAR — Next Phases Implementation Blueprint
Project: SAFAR — The Living Journey Network
Baseline: SAFAR Master Document (49 pages) + uploaded Development Handover (November 22, 2026)
Status: Proposed implementation backlog; not a record of code changes.
Product principle: The Engine Recommends, The Group Decides.

1. Source-of-truth and current baseline

- Master document: governs product direction, F01–F49 definitions, ethics, group experience engine, AI/ML design, UX, evaluation, and architecture principles.
- Development handover: reports all F01–F49 as implemented; FastAPI + SQLAlchemy/Alembic + PostgreSQL; Next.js/React web; Flutter mobile; 129 passing backend tests, 61 Flutter tests, 51 web routes; 56 RLS-enabled tables, 55 FORCE RLS, and 220 policies.
- Important limitation: These are reported claims. There has been no independent execution of the repository in this review. The code is local at C:\Users\LENOVO\Downloads\SAFAR\SAFAR and was not supplied. Verify actual code and CI before claiming a release-ready state.
- AI gap: Handover describes deterministic ranking, template assistant, clustering, heuristics, and no external LLM dependencies. Master proposes selected data-driven AI/ML approaches when justified. Do not call a heuristic a trained model or imply real-time external data that is not connected.

2. Priorities and sequencing
Priority 0 — Establish a reproducible, auditable baseline (first task):
1. Inspect repository tree, installed dependencies, deployment configs, migrations, CI jobs, feature flags and test scripts.
1. Run existing backend, web, Flutter and PostgreSQL/RLS verification suites; record exact commands, pass/fail/skip counts and environment.
1. Trace one working end-to-end group trip through real persisted records on web and Flutter.
1. Build a feature-by-feature evidence matrix for F01–F49: implemented route/UI/API, test, data provenance, mobile parity, known limitations, and status (verified, partially verified, unverified).
1. Track the three skipped staging path tests; execute them in an appropriate staging environment or document an explicit blocker.
1. Create a security-first release-readiness.md showing owners, issues, acceptance checks, and risks.
Priority 1 — Private cloud staging and operations:
1. Choose one managed provider consistently; suggested initial route: Cloud Run for FastAPI (and optionally Next.js), Cloud SQL for PostgreSQL, Cloud Storage for private media, Secret Manager, Cloud Logging/Monitoring. Do not begin with a complex microservice rewrite.
1. Build container images and reproducible CI/CD pipeline with staging-only credentials, migrations and health/readiness checks. Keep web and mobile API URLs environment-specific.
1. Configure custom API/web domains and HTTPS; validate CORS/CSRF/security headers, auth tokens, cookie settings and browser/mobile deep links.
1. Create isolated staging DB, private media bucket, environment secrets, operational dashboards and error alerts.
1. Implement database backup retention, point-in-time recovery where supported, and run a documented restore drill. Target RPO <15 minutes and RTO <1 hour only if the drill validates them.
1. Integrate secure object storage behind an abstraction so media can move off services/api/storage_staging/. Migrate safely, keep compatibility until verified, use private buckets and expiring signed URLs, perform deleted-member permission tests and review URL TTL for sensitive media.
1. Integrate transactional invitation email via a provider with SPF/DKIM/DMARC, expiry and rate limiting; preserve link and share-sheet fallbacks.
1. Review in-process rate limits and WebSocket event fan-out. For one-node pilot, document limitations; before multi-node scaling, add shared rate limits and pub/sub (e.g., Redis) and implement reconnect/resync. For Cloud Run, WebSockets must reconnect on server timeout/disconnection.
1. Apply IAM least privilege, secrets management, log redaction, dependency vulnerability scans, and incident response/runbook.
1. Deploy to private staging with a rollback path; verify cold start, migrations, background jobs, large uploads, Android emulator/device and mobile API connectivity.
Priority 2 — Real-world feasibility and data:
1. Replace straight-line distance as the displayed travel-time proxy with routed travel durations via an approved routing provider. Straight-line estimates may remain as explicitly labelled fallback when routing is unknown.
1. Build provider-neutral adapters for routes/geocoding, official place data and weather. Version API response contracts; cache with TTLs and show timestamps and provider identities.
1. Keep source states separate: official, community reported, model estimated, simulated, unknown. A moderated user report is not automatically verified.
1. Protect budgets, accessibility constraints, closure states, protected wander windows and member consent before ranking. Never allow provider/LLM output to bypass hard constraint checks.
1. Add availability, error, rate-limit and stale-data fallback tests. No live availability claims without an appropriate real-time provider.
1. Expand route feasibility for Trip Twin, Domino Map, Shadowplan, Fragility Radar and Trip Rescue, while preserving confirmed reservations and explicit approval.
Priority 3 — Upgrade the intelligence core with evidence:
1. Introduce a stable ranking evaluation harness with fixed scenario datasets and consent-safe historical feedback where available.
1. Compare baseline ranking strategies: popularity, majority vote, equal-weight, and current fairness-aware engine.
1. Measure hard-constraint violation rate, feasible recommendation rate, top-K relevance, average fit, worst-served member fit, coverage, novelty, explanation faithfulness, and acceptance after real experience.
1. Benchmark Everyone Wins, Your Turn, and Surprise Us on distinct seeded scenarios; show that mode differences are meaningful, not random.
1. Use structured preference vectors/content similarity before trying learned ranking. Add a trained model only with a training dataset, separated validation/test sets, consent, metrics and a non-ML fallback.
1. Evaluate an OR-Tools constraint-solver prototype for day scheduling; adopt only if it improves feasibility/time-window violations against the current approach without disrupting manual plans.
1. Never claim a trained recommender, crowd prediction, automatically verified accessibility or generative assistant unless evidence exists. Keep explanations generated from actual reason codes.
1. Instrument consented recommendation-feedback loops and model versions; distinguish declared preferences from inferred ones.
1. Optionally test richer grounded conversational assistance behind a feature flag with retrieval, tool responses, refusal/unknown behavior, privacy redaction and human approval for edits. Do not make an LLM the source of factual truth.
Priority 4 — Reduce user friction (UX/mobile/offline):
1. Build a stage-based home: Plan → Decide → Experience → Adapt → Remember; surface the one next action while keeping all F01–F49 discoverable through progressive disclosure.
1. Minimize setup: create trip, invite group, select preferences, and reach first useful group suggestion without navigating unrelated pages.
1. Consolidate F07/F08/F09/F23/F37/F38/F45 as a coherent decision workspace with comparison, fairness reason, feasibility, vote and explicit approval.
1. Improve mobile-first states: skeletons, empty/error/offline states, accessibility labels/contrast/font resizing, internationalization parity and screen-reader flows.
1. Test offline queue replays across network flapping, duplicate submits, device restarts, version conflicts and expired permissions; use idempotency keys and visible sync status.
1. Improve memories through editable event clustering, privacy-scoped uploads and contribution permissions; don't invent events or feelings.
1. Test navigation and performance on mid-range Android hardware and mobile data connections.
1. Add data export/delete flows and first-run privacy choices that are clear rather than buried.
Priority 5 — Real traveller pilot and controlled launch:
1. Run a controlled seven-day pilot before public launch. Start with a handful of consenting groups of 3–8 travellers, with explicitly labelled simulated disruptions where used.
1. Use an independent, static-itinerary/group-chat baseline. Measure whether SAFAR makes group choices faster, feasible and fairer, rather than only asking whether participants like it.
1. Evaluate onboarding success, time to first shared decision, invitation success, recommendation acceptance, worst-member satisfaction, privacy understanding, recovery task completion and repeat usage intent.
1. Define severe blockers: accidental personal-data exposure, wrong group membership rights, automatic unapproved changes, financial/privacy corruption, uncorrectable media handling, and crash/blocking failures.
1. Follow regression → bug fixes → re-test → sign-off; maintain audit logs and issue tracking without collecting unnecessary personal data.
1. For Android, create production upload key, enrol Play App Signing, securely store/recover keys, build AAB, test internal track, verify app links and privacy disclosures.
1. For iOS, use macOS/Xcode CI or device environment with valid Apple signing; verify push/deep links, upload/privacy policies and TestFlight before App Store submission. Do not claim release before store review.
1. Reconfirm provider policy compliance, app-store rules, domain setup, support/incident channels, privacy policy, retention and deletion process.
1. Proposed issue backlog and completion tests
ID Priority Deliverable Definition of done
P14-01 P0 Reproducible baseline audit Commands and test evidence for API/web/mobile/RLS; skipped tests explained
P14-02 P0 Feature evidence matrix F01–F49 linked to endpoints, UI, tests and status
P14-03 P1 Managed cloud staging Secure HTTPS staging deployments; reproducible CI/CD; rollbacks
P14-04 P1 Private cloud media storage Upload/download/revoke/delete authorization tested; migration validated
P14-05 P1 Database recovery Backups + PITR configuration; timed restore exercise documented
P14-06 P1 Outbound invite emails Authenticated, deliverable, abuse-controlled email with fallback
P14-07 P1 Observability and security Dashboards, alerts, redaction, auth/RLS regression
P14-08 P1 Multi-node readiness Shared rate limits/pubsub + reconnect tests if scaling beyond one instance
P15-01 P2 Grounded route times Routed journey estimate with mode/source/freshness; safe fallback
P15-02 P2 Weather/place provider adapters Stale/offline/error behavior tested; simulated reports labelled
P15-03 P2 Recommendation benchmark Current engine compared against multiple baselines
P15-04 P2 ML prototype (conditional) Only retained if measurable benefit, documented training & data rights
P15-05 P2 Schedule optimization prototype Constraint violation and performance comparison before rollout
P16-01 P2 Unified group decision UX One coherent journey from pulse → choices → vote → approved itinerary
P16-02 P2 Mobile usability/accessibility Tested on real device; readable, discoverable, screen-reader accessible
P16-03 P2 Offline/retry resilience Duplicate/conflict/restart integration tests pass
P18-01 P1 7-day pilot Test report: observed data, issues, satisfaction/fairness/feasibility results
P19-01 P2 Android internal release Proper Play upload signing, internal distribution, verified flows
P19-02 P3 iOS TestFlight build macOS signing, real-device testing, working deep links
P19-03 P2 Public release decision Explicit gates met; owner signs off blockers and rollback plan

1. Critical system invariants

- The engine never edits confirmed itineraries silently; decisions require documented approval.
- Hard constraints must filter before scoring: member private budgets, accessibility needs, closed/unknown feasibility, protected time, trip memberships.
- Member-private constraints remain private in logs, UI, API errors, explanations and exports.
- Source and timestamp, or an explicit unknown/simulated state, accompany dynamic factual claims.
- Consent gates preference learning, social discovery, memory sharing and location use.
- Expired/removed member access must fail, including API and media. Signed URLs are bearer links and cannot be treated as revocable instantaneously without extra controls.
- Offline replay must be idempotent; newer server changes cannot be silently overwritten.
- Backups must be restored in a drill, not merely configured.
- Degraded provider/ML/network conditions must fall back safely without fictitious results.

5. End-to-end critical-path acceptance test
1. Register three to five distinct accounts (including at least one member with a protected private constraint).
1. Create one trip, send invite, join with correct permissions and reject an unauthorized invite.
1. Collect Journey DNA and Trip Pulse from varied members.
1. Request three group recommendation modes; inspect provenance, per-member utility indicators, and hard-constraint exclusions.
1. Produce a trip proposal, collect a vote, preview Trip Twin, approve and persist an updated itinerary; verify unapproved changes do not commit.
1. Introduce a simulated closure/delay and confirm Domino Map + Trip Rescue show a feasible, minimal repair preview rather than silently applying it.
1. Upload permitted memories, validate member/outsider access, edit one generated cluster and export a share-permitted replay.
1. Disconnect the device, queue a permitted offline update, reconnect, replay once and verify no duplicate record or overwritten newer revision.
1. Run a backup restore on a staging clone and prove the expected trip data is restored.
1. Capture API logs, test evidence, screenshots, performance and security results in the release dossier.
1. Pilot success criteria (proposed targets; adjust based on baseline)

- 100%: No unauthorized read of private trip/member/media data in the test matrix.
- 100%: No unapproved confirmed-itinerary modifications.
- 100%: No hard-constraint violating recommendations within the supported and fully populated fixture set.
- ≥90%: Key first-time user tasks completed without researcher intervention (target, not claim).
- ≥95%: Staging trip critical-path test completion across supported devices (target, not claim).
- Documented: Time-to-decision improvement versus a static-group-chat baseline; fairness and recovery metrics must be reported even if there is no improvement.
- Documented: Database restore RPO/RTO, cloud spend, provider failure fallback and unresolved risks.

7. Copy/paste IDE agent execution prompt — start with Phase 14
You are working in the existing SAFAR monorepo. Do not recreate the application. The master document is authoritative for product vision and F01–F49; the release handover is a reported implementation baseline, not proof. Preserve all existing features and naming. The core rule is: The Engine Recommends, The Group Decides.

First, inspect actual code in services/api, apps/web, apps/mobile, docs, CI/CD configs, tests and migrations. Find the real scripts before running commands. Do not invent paths or assume a dependency exists.

1. Run available FastAPI/pytest, web TypeScript/Vitest/build, Flutter analysis/tests, migrations and PostgreSQL RLS checks. Record baseline and environment. Revisit 3 previously skipped staging tests.
2. Create docs/NEXT_PHASE_AUDIT.md: precise repository findings, test results, working features, blockers, security gaps and mismatches from handover. Include a verified F01–F49 matrix linking relevant code and tests.
3. Create a short, ordered implementation plan for managed staging, private object storage, automated backups/PITR, invitation email and monitoring; use existing deployment abstractions if present. Prefer incremental and reversible changes.
4. Implement only the first safe, self-contained task after the audit (e.g. production-safe configuration/health checks, storage adapter with tests, or staging deployment manifests); do not assume you have cloud credentials or perform external deployment without explicit approval.
5. Add tests, run regressions, update documentation and present exact file changes, commands and remaining environment/secret prerequisites.
6. Never expose private budgets, member notes, credentials or precise locations; enforce role checks and RLS; never auto-apply recommendations. Preserve current local development setup.
Output must clearly distinguish: verified implementation, code added, tests actually executed, untested work, external accounts/credentials required, and next recommended commit. Do not mark any phase complete without passing checks.

7. What not to do yet

- Do not add a hotel/flight-booking marketplace, generic social feed, mandatory background GPS tracking or a huge LLM as the new centre of SAFAR.
- Do not migrate away from FastAPI/Next.js/Flutter just because an alternative sounds newer.
- Do not train new AI models without adequate consented data, useful labels and proper evaluation.
- Do not turn mock weather/crowds into apparently live signals or make unsupported accuracy claims.
- Do not pursue complex multi-region infrastructure before validating actual pilot usage and costs.

9. External reference notes (official documentation checked November 2026)

- Google Cloud Run WebSockets: <https://docs.cloud.google.com/run/docs/triggering/websockets> — timeout, reconnect, multi-instance pub/sub considerations.
- Google Cloud SQL PostgreSQL PITR: <https://docs.cloud.google.com/sql/docs/postgres/backup-recovery/configure-pitr> — PITR configuration.
- Google Cloud Storage signed URLs: <https://docs.cloud.google.com/storage/docs/access-control/signed-urls> — expiring bearer URLs and private buckets.
- Android App Signing: <https://developer.android.com/studio/publish/app-signing> — production upload key and Play App Signing.
 1. Scope and verification disclaimer
This document is an implementation blueprint, not a finished deployment or modified codebase. Cloud accounts, signing identities, API keys, domain ownership and Apple/Google developer access require actions by their owners. Publishing, sending invitations or migrating persistent user data must be explicitly approved and tested. Availability, costs and region support must be verified against selected providers when provisioning.
