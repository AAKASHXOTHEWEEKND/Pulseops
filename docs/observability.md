# Observability & On-Call

Goal: know whether the **product** is healthy, not merely whether containers are running.

## Signals we emit

### Structured logs
JSON to stdout (shipped to CloudWatch). Every line carries `timestamp`, `level`, `logger`, `message`, `correlation_id`, `app_version`, `app_env`. The `correlation_id` is the job id, so a single job can be traced across API → worker with one filter.

### Metrics (Prometheus, `GET /metrics` on API :8000 and worker :8080)

| Metric | Meaning | On-call use |
|--------|---------|-------------|
| `pulseops_http_requests_total{method,path,status}` | API request counts | error rate, traffic |
| `pulseops_http_request_duration_seconds` | API latency histogram | p95/p99 latency |
| `pulseops_jobs_submitted_total` | jobs accepted | arrival rate |
| `pulseops_jobs_processed_total{status}` | jobs completed/failed | throughput, failure rate |
| `pulseops_job_processing_seconds` | per-job processing time | worker slowness |
| `pulseops_queue_depth` | current backlog | queue growth |
| `pulseops_worker_last_success_timestamp_seconds` | last successful job time | "worker silently stalled" |

Container restarts, deployment status, CPU/mem come from ECS Container Insights; request/error/latency at the edge come from ALB metrics.

## Alerts (CloudWatch → SNS `pulseops-<env>-alerts`)

Defined in [modules/compute/alarms.tf](../infra/terraform/modules/compute/alarms.tf):

1. **API 5xx > 5 in 2 min** — broken release or failing dependency.
2. **API healthy host count < 1** — hard outage.
3. **Worker running task count < desired for 3 min** — jobs won't process.

Subscribe email/Slack/PagerDuty to the SNS topic (kept out-of-band so the channel isn't in code).

Locally, the same product signals are visible via `GET /metrics` and the compose health checks.

## On-call judgement — what wakes someone at 3 AM

**Page immediately (customer-impacting, won't self-heal):**
- API healthy-host count = 0 (portal down — users can't submit or view jobs).
- Sustained API 5xx (submissions failing).
- Database unavailable (everything depends on it).

**Wait for business hours (degraded but functioning, or self-healing):**
- Modest queue backlog that autoscaling is already draining — jobs are async; a few minutes of extra latency isn't an outage.
- A single container restart that recovered (ECS already replaced it).
- Trivy HIGH/CRITICAL findings with no active exploit — patch in normal work.
- Elevated latency still within SLO.

**Why:** the worker path is asynchronous and designed to absorb bursts, so backlog that is actively draining is a capacity note, not an outage. The synchronous API path and the database are on the critical user path — if they're down, the product is down, so those page. The rule of thumb: *page when customers are blocked and it won't fix itself; queue it for daytime when the system is degrading gracefully or already recovering.*
