# Controlled Failure & Incident Note

We ship a **safe, reversible** failure switch to demonstrate detection, diagnosis, and rollback: the `BREAK_READINESS` environment flag. When true, `GET /health/ready` returns `503` **without crashing the process** — modelling a bad config release (e.g. a broken readiness contract) that health checks catch.

## How to reproduce (local)

```bash
make up                 # healthy baseline
make smoke              # PASS

make break              # redeploy API with BREAK_READINESS=true
curl -i http://localhost:8000/health/ready     # HTTP/1.1 503 ... {"status":"not_ready",...}
make smoke              # FAILS at the readiness phase (non-zero exit)

make rollback           # redeploy API with BREAK_READINESS=false
make smoke              # PASS again
```

## How it appears in CI/CD
If this flag (or any genuinely broken release) shipped, the deploy pipeline catches it two ways:
1. **`aws ecs wait services-stable`** never succeeds because the ALB health check on `/health/ready` fails → the **ECS deployment circuit breaker rolls the service back automatically**.
2. Even if a task started, the **post-deploy smoke test** fails at the readiness phase and **fails the pipeline** (non-zero exit), blocking promotion.

## Where the evidence shows up
- **CI/CD run**: the "Wait for services to stabilize" or "Smoke test" step goes red; smoke test prints `SMOKE FAIL: API never became ready`.
- **Logs**: API log group shows readiness returning 503 with `reason: break_readiness flag enabled`.
- **Monitoring**: `pulseops-*-api-no-healthy-hosts` and/or `-api-5xx` alarm transitions to ALARM and notifies SNS.

## Diagnostic path
1. Smoke test / alarm fires → check `GET /health/ready`: it reports `not_ready` and the reason.
2. Confirm scope: liveness is still 200 (process healthy) but readiness is 503 → **config/readiness problem, not a crash**.
3. Correlate with the most recent deployment in ECS "Events" → the bad revision.
4. Roll back to the previous task-def revision.

## Incident note (template, filled for this demo)

| Field | Content |
|-------|---------|
| **What failed** | API readiness probe returned 503 (broken readiness contract) after a config release; ALB drained the API tasks. |
| **User impact** | Web portal could not submit or fetch jobs — the API was pulled out of the load balancer. Worker/DB unaffected; queued jobs were not lost. |
| **Detection** | Post-deploy smoke test failed at the readiness phase; `api-no-healthy-hosts` CloudWatch alarm fired to SNS. |
| **Root cause** | A configuration flag (`BREAK_READINESS`) made `/health/ready` report unhealthy. (In a real incident: a bad env/config change to the readiness path.) |
| **Recovery** | Rolled the API service back to the previous task-definition revision (`rollback.sh api`); verified with the smoke test reaching COMPLETED. |
| **Prevention** | (1) Smoke test gates every deploy and blocks promotion on failure. (2) ECS circuit breaker auto-rolls-back unstable rollouts. (3) Config changes go through PR + the ephemeral-env smoke test before merge. (4) Alarm on healthy-host count so detection doesn't rely on a human noticing. |

## Guardrail that prevents recurrence
The **automated smoke test as a required deploy gate** plus the **ECS deployment circuit breaker** mean a release that breaks readiness can neither stay live nor be promoted — it is reverted automatically and the pipeline goes red.
