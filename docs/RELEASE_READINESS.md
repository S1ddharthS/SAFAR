# SAFAR — Security-First Release Readiness

**Date:** 2026-11-22  
**Decision:** **NO-GO for public release.** A private, disposable staging pilot
may proceed only after owner approval and the gates below.  
**Evidence source:** [`docs/NEXT_PHASE_AUDIT.md`](NEXT_PHASE_AUDIT.md).

This is an owner/checklist document, not a claim that a phase is complete.
Roles are placeholders: assign real names before sign-off.

## 1. Non-negotiable invariants

| Invariant | Acceptance check | Current status |
|---|---|---|
| Engine recommends; group decides | No confirmed itinerary write without recorded approval; proposal-only tests pass | Automated tests pass; live trace not executed here |
| Private budgets/notes/accessibility stay private | API/log/UI/export probes with mixed-member fixtures | Automated tests pass; RLS re-verification blocked |
| Role checks and RLS enforced server-side | Cross-user, removed-member and no-identity DB probes | Code/tests exist; live PG not executed here |
| No automatic recommendation application | Inspect engine/rescue/twin write paths and approval gate | Static + automated evidence; live trace pending |
| Signed media has bounded lifetime | Unsigned/tampered/expired/revoked access tests | Local signed URLs tested; cloud revocation pending |
| Offline replay is idempotent | Duplicate, conflict and restart tests | Queue restored and local suite passes; live replay pending |
| Backups are restored, not merely configured | Timed restore drill with row/policy isolation proof | Scripts portable now; drill blocked |
| Degraded providers never invent facts | Unknown/stale/error assertions | Automated evidence for disabled providers |

## 2. Owners and gates

| Area | Owner role | Gate / definition of done | Evidence needed | Status |
|---|---|---|---|---|
| P0 baseline | Repo/release owner | API, web and mobile suites run from clean checkout; skips explained | Commands and counts in `NEXT_PHASE_AUDIT.md` §3 | **Pass locally** |
| Hosted config guard | Backend/release owner | SQLite, insecure cookies, memory media, seed/schema creation and test hosts rejected in staging/production | `test_config_hardening.py`; startup on real staging | **Pass locally; staged startup pending** |
| Credential hygiene | Security owner | Exposed staging credentials rotated; history review recorded; no secret values in source/docs | Rotation ticket + scan output | **Blocked — owner action** |
| PostgreSQL/RLS | DBA/security owner | `safar_app` non-owner role; 0 rows without identity; cross-trip isolation; policy count recorded | `verify_postgres_rls.py` output on disposable DB | **Blocked** |
| Backup/PITR | DBA/infra owner | Managed backups + PITR enabled; restore drill timed | Restore report with RPO/RTO | **Blocked** |
| Managed staging | Cloud/infra owner | Isolated HTTPS staging; exact CORS/Host/cookie settings; migrations as release step; rollback tested | Deploy log, probe results, rollback log | **Not started** |
| Private media | Cloud/infra owner | Private bucket; expiring URLs; member/outsider/revocation/delete tests; migration rollback | Authorization matrix | **Adapter seam done; cloud backend not started** |
| Invitation email | Product/security owner | SPF/DKIM/DMARC; expiry and rate limit; no private content; link fallback preserved | Provider report + abuse test | **Not started** |
| Observability | Ops owner | Dashboards/alerts for 5xx, auth failures, refresh reuse, CSRF, slow queries, sync conflicts, readiness | Alert firing test; redaction scan | **Partial — code/tests only** |
| Multi-node | Infra owner | Shared rate limits/pub-sub and WS reconnect/resync tests if >1 instance | Failure-injection report | **Deferred** |
| Android release | Mobile owner | Production upload key + Play App Signing; internal track; deep links | Signed AAB + test report | **Blocked** |
| iOS release | Mobile owner | macOS/Xcode build, signing, TestFlight, deep links | TestFlight report | **Blocked** |
| Pilot | Product owner | 7 days, 3–5 groups, baseline comparison, severe-blocker checklist | Signed pilot report | **Not started** |

## 3. Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Previously committed credentials are still valid | Medium | Critical | Rotate immediately; audit access logs; supply via secret manager only |
| Hosted deployment inherits development defaults | Medium | High | Fail-closed startup checks in `config.py`; verify on real staging before traffic |
| RLS regression during managed migration | Medium | Critical | Run RLS verifier in CI/release gate on disposable DB before cutover |
| Local media lost or exposed on multi-node deploy | High | High | Private bucket adapter with feature flag and compatibility rollback |
| Signed URL TTL too long for sensitive media | Medium | High | Review TTL per media class; test revocation limits explicitly |
| In-process rate limits bypassed across instances | High if scaled | High | Stay one-node for pilot; add shared limiter before scale-out |
| WebSocket drops on server timeout | Medium | Medium | Reconnect/backoff already in client; add resync proof before multi-node |
| Invitation email leaks trip context | Low | High | Template contains link only; no budgets/notes/location; log redaction |
| PITR target claimed without drill | Medium | High | Publish measured RPO/RTO only after restore test |
| Throwaway Android signing key used for release | High if shipped | High | Production upload key and Play App Signing before internal track |
| Heuristics presented as trained AI/live data | Medium | High | Keep deterministic labels; no external provider claims without evidence |

## 4. Required external prerequisites

* Approved cloud account, region, domains/DNS and secret manager.
* Isolated managed PostgreSQL with non-owner role and PITR capability.
* Private object storage bucket and credentials with least-privilege IAM.
* Transactional email provider with a verified sending domain.
* Log/monitoring sink and alert routes.
* Production Android upload key / Google Play enrollment and macOS/Xcode +
  Apple Developer access for iOS.
* Owner authorization for any persistent data migration or outbound message.

## 5. Sign-off block

Release may be reconsidered only when every Critical/High gate above is
evidenced, the live group-trip acceptance path has been executed, and an owner
records the decision with rollback steps. Until then: **NO-GO**.
