# Deployment Runbook

Audience: an engineer who needs to ship, verify, promote, or roll back a release — possibly at 3 AM.

## TL;DR

| Action | Command |
|--------|---------|
| Deploy (cloud) | Merge to `main` → `deploy.yml` runs automatically |
| Verify a release | `python scripts/smoke_test.py --base-url <url>` |
| Roll back a service | `CLUSTER=pulseops-staging-cluster bash infra/scripts/rollback.sh api` |
| Promote staging image → prod | Re-tag the same digest; see [Promotion](#promoting-a-tested-image) |
| Find logs | CloudWatch `/ecs/pulseops-<env>/{api,worker,web}` |

## How to deploy and verify a release

### Cloud (AWS ECS)
1. Open a PR. CI lints, unit-tests, scans, validates Terraform, and **stands up an ephemeral compose environment and runs the smoke test**. All must pass.
2. Merge to `main`. `deploy.yml`:
   - builds immutable images tagged with the 12-char git SHA and pushes to ECR;
   - runs DB migrations as a one-off ECS task (deploy aborts if they fail);
   - updates the api, worker, and web services to the new task-def revision;
   - waits for ECS stability (the **deployment circuit breaker auto-rolls-back** a service that can't stabilize);
   - runs the smoke test against the live ALB URL. A red smoke test fails the pipeline.
3. Confirm the "Deploy summary" in the job output shows the expected SHA and URL.

### Local / self-hosted
```bash
make up             # build + start web/api/worker/db/redis
make smoke          # BASE_URL defaults to http://localhost:8000
```
Web portal: <http://localhost:8080>. API: <http://localhost:8000>. Readiness: <http://localhost:8000/health/ready>.

## How to roll back

ECS keeps every task-definition revision, so rollback = point the service at the prior revision.

```bash
export CLUSTER=pulseops-staging-cluster
bash infra/scripts/rollback.sh api      # roll API back one revision
bash infra/scripts/rollback.sh worker
```
Then **verify**:
```bash
python scripts/smoke_test.py --base-url http://<alb-dns> --timeout 90
```

Locally, the controlled-failure demo uses the same idea via env flag:
```bash
make break      # inject failure (readiness returns 503)
make rollback   # restore healthy config
make smoke      # verify
```

Automatic rollback is also built in: the ECS `deployment_circuit_breaker { rollback = true }` reverts a bad rollout without human action.

## Promoting a tested image

The **same image** that passed staging is promoted to production — never rebuilt. Two options:

- **Re-tag by digest** (preferred): copy the exact image digest from the staging ECR repo into the production repo, then set `api_image`/`web_image` in `production.tfvars` to that digest/tag and apply. Because the digest is identical, the bits are byte-for-byte the same.
- **Shared registry**: point both environments' task defs at the same registry/tag; production's Terraform var references the SHA that passed staging.

Immutable tags (git SHA) make "which version is running where" unambiguous, and ECR repos are set `IMMUTABLE` so a tag can never be silently overwritten.

## Database migration sequencing

- Migrations run **before** the new app version rolls out, as a one-off ECS task (`run_migrations.sh`).
- Write migrations **expand/contract** (backward-compatible) so the currently-running version keeps working while the new version rolls in: add columns/tables first, deploy code that uses them, remove old columns in a later release.
- If the migration task exits non-zero, the deploy aborts and the app is **not** rolled out.

## How to locate logs, metrics, and deployment events

- **Logs**: CloudWatch Logs groups `/ecs/pulseops-<env>/api`, `/worker`, `/web`. Logs are structured JSON — filter by `correlation_id` (the job id) to trace one job across API and worker.
- **Metrics**: `GET /metrics` on API and worker (Prometheus format); ECS Container Insights for CPU/mem/task counts; ALB metrics for request/error/latency.
- **Deployment events**: ECS console → service → "Deployments" and "Events" tabs; `aws ecs describe-services`.
- **Alerts**: CloudWatch alarms publish to the `pulseops-<env>-alerts` SNS topic.

## Concurrency & safeguards
- `deploy.yml` uses `concurrency: deploy-staging` with `cancel-in-progress: false` → no two deploys to the same environment at once.
- OIDC short-lived credentials; no long-lived AWS keys in CI.
- GitHub `environment: staging` allows adding required reviewers for production promotion.
