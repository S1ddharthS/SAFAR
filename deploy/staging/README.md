# SAFAR staging deployment templates

**Status: templates only.** Nothing in this directory is applied by CI, pushed
to a registry, or executed against a cloud project. Owner approval, a chosen
provider/region and real secrets are still required.

These templates assume the blueprint's suggested initial route: Cloud Run for
the API/web containers, managed PostgreSQL, Secret Manager and a private media
backend. They are intentionally single-region and small (`maxScale: 2`) for a
one-node pilot.

## Files

| File | Purpose |
|---|---|
| `api-service.yaml` | Cloud Run service for the FastAPI app. Uses `/api/ready` and `/api/health`, secure cookies, explicit hosts/origins and secret references. |
| `web-service.yaml` | Cloud Run service for the Next.js app. `NEXT_PUBLIC_API_URL` is baked into the image at build time. |
| `migrate-job.yaml` | One-shot Alembic migration job. Uses a separate migration-capable DB secret, never the RLS-restricted application role. |

## Placeholders to replace locally

| Placeholder | Meaning |
|---|---|
| `PROJECT_ID` | Approved cloud project id. |
| `REGION` | Approved region for all staging resources. |
| `TAG` | Immutable image tag, normally the verified commit SHA. |
| `SAFAR_STAGING_RUNTIME_SA` | Least-privilege runtime service account. |
| `STAGING_DOMAIN` | Real staging domain, e.g. `staging.example.com`. |

Required Secret Manager entries (names only, no values):

- `safar-staging-database-url` — application DB URL using the non-owner role.
- `safar-staging-migration-database-url` — migration role, used only by the job.
- `safar-staging-secret-key` — unique staging signing key.

Required GitHub environment variables/secrets for the manual preflight:

- Secrets: `STAGING_DATABASE_URL`, `STAGING_SECRET_KEY`
- Variables: `STAGING_CORS_ORIGINS`, `STAGING_TRUSTED_HOSTS`

`staging-preflight.yml` is `workflow_dispatch` only. It runs the test suite,
validates the redacted config with `scripts/check_config.py`, and builds Docker
images locally without pushing. It has no auth, registry, migration or deploy
step.

## Owner-run deployment outline (not automated)

1. Render each template locally and review the result before applying it.
2. Build and push both images with the same immutable `TAG`.
3. Build the web image with `--build-arg NEXT_PUBLIC_API_URL=https://api.STAGING_DOMAIN`.
4. Execute `migrate-job.yaml` and verify success before promoting the API.
5. Apply `api-service.yaml` and `web-service.yaml`; verify TLS, CORS, cookies and both probes.
6. Run the RLS verifier and the media authorization matrix against the disposable staging data.
7. Record request IDs, probe results and the exact image tags in the release dossier.

Rollback: redeploy the previous verified image tag. Do not assume an automatic
database downgrade is safe; use a reviewed forward fix or a tested downgrade.

No persistent data migration or outbound message is authorized by this
document.
