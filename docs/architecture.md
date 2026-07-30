# Architecture

## Component flow

```
                          Internet
                             │
                             ▼
                   ┌───────────────────┐   PUBLIC
                   │  Application LB    │   (only public entrypoint)
                   │  :80  path-routes  │
                   └─────────┬─────────┘
              /  /api/*  /jobs  /health/*  │  everything else
                   │                       │
                   ▼                       ▼
          ┌─────────────────┐     ┌─────────────────┐   PRIVATE
          │  API (Fargate)  │     │  Web (Fargate)  │   subnets
          │  FastAPI :8000  │     │  nginx :8080    │
          │  2+ tasks, HPA  │     │  static SPA     │
          └────┬───────┬────┘     └─────────────────┘
               │       │
     enqueue   │       │  read/write
    (LPUSH)    │       │
               ▼       ▼
     ┌──────────────┐  ┌──────────────────┐
     │ Redis (queue)│  │ PostgreSQL (RDS) │   PRIVATE — no public IP
     │ ElastiCache  │  │ jobs table       │
     └──────┬───────┘  └────────┬─────────┘
            │ BLPOP             │ update status/result
            ▼                   ▲
     ┌──────────────────┐      │
     │ Worker (Fargate) │──────┘
     │ 1+ tasks, HPA    │
     │ own health :8080 │
     └──────────────────┘
```

## Public vs private boundary

| Component | Exposure | Notes |
|-----------|----------|-------|
| Application Load Balancer | **Public** | Only internet-facing resource. Path-routes to web/API target groups. |
| Web (nginx) | Private subnet | Reached only via ALB. Serves static SPA. |
| API (FastAPI) | Private subnet | Reached only via ALB on API paths. |
| Worker | Private subnet | No inbound from ALB; pulls from queue. Own health server for probes. |
| PostgreSQL (RDS) | Private subnet | `publicly_accessible = false`; SG allows only the app SG on 5432. |
| Redis (ElastiCache) | Private subnet | SG allows only the app SG on 6379. |
| Secrets Manager | AWS-managed | Holds `DATABASE_URL`; read by ECS execution role only. |

## Request → job lifecycle

1. Browser loads the SPA from the web service (via ALB).
2. Browser `POST /api/jobs` → ALB routes to API.
3. API writes a `QUEUED` row to Postgres, then `LPUSH` the job id to Redis, returns the id.
4. Worker `BLPOP`s the id, flips the row to `PROCESSING`, runs `transform()`, writes the `result` and flips to `COMPLETED`.
5. Browser polls `GET /api/jobs/{id}` until `COMPLETED` and renders the result.

## Key design choices

- **One image for API + worker.** They share code and differ only by container command. One artifact to build, scan, and promote unchanged from staging to production.
- **Redis list as the queue.** Simple, reliable `LPUSH`/`BLPOP`, trivial locally (compose) and in cloud (ElastiCache). SQS would be the managed alternative; Redis keeps the local/CI story identical to prod.
- **Readiness vs liveness split.** Liveness is cheap (process up); readiness checks DB + Redis so the ALB only sends traffic to tasks that can actually serve.
- **Same stack everywhere.** docker-compose (local/CI) and ECS (cloud) run the identical images and the identical smoke test, minimizing environment drift.
