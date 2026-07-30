# PulseOps

A small multi-service job platform — web → API → queue → worker → database — packaged as a reproducible, observable deployment with a rollback path.

Submit a text job in the portal; the API stores it and enqueues it; a worker processes it (`hello platform` → `HELLO PLATFORM`) and the result appears in the portal. The application logic is intentionally simple — the focus is the infrastructure and operational quality around it.

## Contents
- [Architecture](docs/architecture.md) — components, public/private boundary, request→job lifecycle
- [Deployment runbook](docs/runbook-deployment.md) · [Incident runbook](docs/runbook-incident.md)
- [Observability & on-call](docs/observability.md) · [Security & secrets](docs/security.md)
- [Environments & release strategy](docs/environments.md) · [Facets migration](docs/facets-migration.md)
- [Controlled failure & incident note](docs/incident-note.md) · [Cost & cleanup](docs/cost.md)

## Stack
| Layer | Choice | Why |
|-------|--------|-----|
| Frontend | Static SPA + nginx | No build step; runtime-configurable API URL; tiny image |
| API | FastAPI (Python 3.12) | Health + job endpoints; async-friendly |
| Worker | Same image, different command | One artifact to build/scan/promote |
| Database | PostgreSQL | Relational job store; managed via RDS in cloud |
| Queue | Redis list (`LPUSH`/`BLPOP`) | Simple, reliable; identical locally and in cloud |
| IaC | Terraform (AWS ECS Fargate) | Modular, remote state + locking |
| CI/CD | GitHub Actions | PR checks + ephemeral-env smoke test; main-branch deploy |

## Run it locally (primary path)

Requires Docker + Docker Compose.

```bash
cp .env.example .env          # optional; sensible defaults exist
make up                       # build & start web/api/worker/db/redis
```
- Web portal: <http://localhost:8080>
- API: <http://localhost:8000> — readiness at `/health/ready`, metrics at `/metrics`

Verify the full business flow with the post-deploy smoke test:
```bash
make smoke                    # submits a job, polls to COMPLETED, validates result
```
Tear down:
```bash
make down                     # stop (keep data)
make clean                    # stop + remove volumes
```
`make help` lists all targets.

## Minimum API contract
```
GET  /health/live      liveness (process up)
GET  /health/ready     readiness (DB + Redis reachable)
POST /jobs             {"input": "..."} -> 201 {id, status: QUEUED, ...}
GET  /jobs             recent jobs
GET  /jobs/{job_id}    single job (status QUEUED|PROCESSING|COMPLETED|FAILED)
```

## Tests & lint
```bash
cd app
pip install -r requirements-dev.txt
pytest          # unit tests (API, worker, processing) — no external services needed
ruff check .    # lint
```

## Infrastructure (AWS ECS Fargate)
Terraform under [infra/terraform](infra/terraform) provisions VPC (public/private), ALB, ECS services (API/worker/web), RDS PostgreSQL, ElastiCache Redis, ECR, IAM, CloudWatch logs + alarms, and Secrets Manager.

```bash
cd infra/terraform
terraform fmt -check -recursive
terraform init -backend=false && terraform validate     # offline validation
# For a real deploy: bootstrap remote state, then
#   terraform init -backend-config=envs/staging/backend.hcl
#   terraform plan -var-file=envs/staging/staging.tfvars
```
See the [deployment runbook](docs/runbook-deployment.md) and [cost & cleanup](docs/cost.md) for the full flow and teardown. Kubernetes was intentionally out of scope for the timebox; ECS was chosen as the simpler container platform.

## CI/CD
- `ci.yml` (every PR): ruff + pytest, `terraform fmt/validate`, gitleaks secret scan, image build + Trivy scan, and — most importantly — it stands up the full stack in CI and runs the smoke test against it, so every PR proves the business flow end to end.
- `deploy.yml` (merge to `main`): builds immutable images (git-SHA tags), pushes to ECR, runs migrations as a one-off task, rolls out the services, waits for stability (ECS circuit breaker auto-rolls-back bad releases), and smoke-tests the live URL. Guarded on AWS OIDC being configured.

## Deployment evidence without a cloud account
A public staging URL is optional. Because the CI pipeline builds the images and runs the real smoke test against a live ephemeral stack, a green CI run is itself reproducible deployment evidence. Locally, `make up && make smoke` demonstrates the same flow. See [incident-note.md](docs/incident-note.md) for the controlled-failure + rollback demonstration.

## Assumptions, trade-offs & known limitations
- Assumptions (chosen defaults, documented): region `ap-south-1`, VPC `10.20.0.0/16`, 2 AZs, uppercase transform as the job's work, git-SHA image tags.
- Trade-offs: single NAT gateway and single Redis node in staging (cost over HA — noted in [cost.md](docs/cost.md)); Redis-list queue over SQS (keeps local/CI identical to prod); Trivy is report-only initially.
- Known limitations: no live cloud deployment is included (Docker isn't available in the authoring environment, so images were not built here — the compose/CI path is the runnable evidence); at-least-once processing means a job could be reprocessed if a worker dies mid-job (idempotent transform makes this safe); no per-PR cloud preview yet (compose-in-CI stands in). HTTPS/ACM on the ALB is left as a follow-up (HTTP listener only).

## AI-tool disclosure
- Tool used: Claude (Anthropic) via an agentic coding assistant.
- Where: helped scaffold the FastAPI/worker code, Dockerfiles, Terraform modules, GitHub Actions workflows, the smoke test, and the docs in this folder.
- What was verified manually / in this environment: the Python unit tests (`pytest`, 13 passing) and lint (`ruff`) were run; the Terraform was checked with `terraform fmt` and `terraform validate` (both pass); all shell scripts pass `bash -n` and workflow/compose YAML parses. Docker image builds and a live AWS deploy were not executed in the authoring environment and should be validated where Docker/AWS are available.
- How generated code was validated: by running the above checks and by reading through each module. Everything here is intended to be explainable and modifiable — see the runbooks for operational reasoning.
