# Environment & Release Strategy

Environments: **local → CI (ephemeral) → staging → production**. (Preview-per-PR is a documented next step, below.)

## Configuration & secrets across environments
- **Same images everywhere**; only environment variables and secrets differ.
- Non-secret config: env vars in compose (local/CI) and task-definition `environment` (staging/prod), driven by Terraform `*.tfvars` per environment.
- Secrets: Secrets Manager per environment (`pulseops/<env>/database-url`). Never in code.

## Infrastructure state & ownership
- Terraform state in **S3 with DynamoDB locking**, one state key per environment (`envs/<env>/backend.hcl`).
- One reusable root module; environments differ only by `*.tfvars` — no copy-pasted stacks.
- Platform team owns the Terraform; product engineers consume via the pipeline.

## Database migrations
- Alembic; run as a one-off task **before** app rollout. **Expand/contract** style so old and new code both work mid-rollout.

## Image promotion & release versioning
- Images tagged with the **12-char git SHA** (immutable). The exact digest that passed staging is promoted to production — **never rebuilt**. See [runbook-deployment.md](runbook-deployment.md#promoting-a-tested-image).

## Test data & access controls
- No production data in lower environments. Staging uses synthetic jobs (the smoke test's `hello platform`). Access to prod secrets/DB is restricted by IAM.

## Preview environments & cost controls (next step)
- Per-PR preview could reuse the compose stack (as CI already does) or a lightweight per-PR ECS namespace. Lifecycle: create on PR open, destroy on merge/close. Cost controls: single small task each, TTL cleanup, no Multi-AZ.
- Today the **ephemeral compose environment in CI** already gives per-PR verification of the real business flow without standing cloud cost.

## Key question: which staging/prod differences are acceptable vs. dangerous?

**Acceptable (cost/scale only):**
- Fewer/smaller tasks; single-AZ RDS and single Redis node in staging.
- Shorter log retention; smaller instance classes.
- Synthetic vs. real data volume.

**Dangerous — creates false confidence (keep these identical):**
- **Different images or dependency versions** — then staging didn't test what ships. We use the same digest.
- **Different config *shape*** (missing env var, different secret wiring) — a gap that only appears in prod. Same task-def structure both sides.
- **Different migration path** — always exercise migrations in staging first.
- **Auth/network topology differences** (e.g. public DB in staging) — hides security/connectivity bugs. Both environments keep the private-subnet + SG boundary.
- **Readiness/health semantics differing** — would mask deploy-gating bugs.

Rule: differences may only be **quantitative (size/scale/retention)**, never **qualitative (image, config shape, security posture, code path)**.
