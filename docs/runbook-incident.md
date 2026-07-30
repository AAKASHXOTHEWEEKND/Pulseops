# Incident Runbook

Fast, symptom-first playbooks. Each: **detect → diagnose → mitigate → verify**.

First moves for almost any incident:
```bash
export CLUSTER=pulseops-staging-cluster
aws ecs describe-services --cluster $CLUSTER \
  --services pulseops-staging-api pulseops-staging-worker pulseops-staging-web \
  --query 'services[].{name:serviceName,running:runningCount,desired:desiredCount,deployments:length(deployments)}'
python scripts/smoke_test.py --base-url http://<alb-dns>   # is the business flow up?
```
Trace one job end-to-end: filter CloudWatch logs by its `correlation_id` (= job id).

---

## API unavailable (5xx / ALB shows no healthy hosts)
- **Detect**: `pulseops-*-api-5xx` or `-api-no-healthy-hosts` alarm; smoke test fails at readiness.
- **Diagnose**: `GET /health/ready` — which dependency is red (DB/Redis)? Check API log group for stack traces; check ECS "Events" for tasks failing to start.
- **Mitigate**: if it followed a deploy → `rollback.sh api`. If a dependency is down → see the DB/Redis sections below.
- **Verify**: smoke test green; healthy host count ≥ 1.

## Worker not processing jobs
- **Detect**: jobs stuck in `QUEUED`/`PROCESSING`; `pulseops-*-worker-not-running` alarm; `worker_last_success_timestamp` metric stale.
- **Diagnose**: worker running count vs desired; worker logs for `dequeue_error` / DB errors; is Redis reachable (`GET /health/ready` on worker :8080)?
- **Mitigate**: if crashed → ECS restarts it; if scaled to 0 → bump `worker_desired_count`; if Redis down → restore Redis. In-flight jobs are safe (graceful SIGTERM lets the current job finish).
- **Verify**: submit a job (or run smoke test) and watch it reach `COMPLETED`.

## Queue backlog increasing
- **Detect**: `pulseops_queue_depth` climbing; jobs slow to complete.
- **Diagnose**: is throughput < arrival rate? worker CPU high? one poisoned job blocking?
- **Mitigate**: worker autoscaling scales on CPU; manually raise `worker_desired_count` for a fast bump. Investigate any repeatedly-failing job.
- **Verify**: queue depth trends down; completion latency normal.

## Deployment stuck or unhealthy
- **Detect**: `deploy.yml` hangs on `services-stable`; ECS deployment stuck `IN_PROGRESS`.
- **Diagnose**: ECS "Events" for the failing service — image pull error, failing health check, insufficient capacity. The **circuit breaker** auto-rolls-back once it gives up.
- **Mitigate**: let the circuit breaker finish, or force `rollback.sh <service>`.
- **Verify**: service `PRIMARY` deployment `COMPLETED`; smoke test green.

## Database unavailable
- **Detect**: readiness reports `database: error`; API 5xx; connection errors in logs.
- **Diagnose**: RDS console status/events; is it a failover, storage-full, or connection exhaustion? Check DB SG still allows the app SG.
- **Mitigate**: Multi-AZ (production) fails over automatically; scale connection pool if exhausted; restore from automated backup if data-level.
- **Verify**: readiness `database: ok`; smoke test green.

## Container / task repeatedly crashing (CrashLoopBackOff-equivalent)
- **Detect**: ECS "Events" show tasks starting then stopping; running count oscillates.
- **Diagnose**: `aws ecs describe-tasks` → `stoppedReason` + container `exitCode`; read the last log lines. Common causes: missing env var/secret, bad migration, image regression.
- **Mitigate**: if config → fix the task def / secret and redeploy; if image → `rollback.sh`.
- **Verify**: tasks stay `RUNNING`; running == desired; smoke test green.

---

### Escalation / on-call judgement
See [observability.md](observability.md) for what pages at 3 AM vs. what waits for business hours.
