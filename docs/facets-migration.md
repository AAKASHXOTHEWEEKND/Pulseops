# Migration Away from Facets

Goal: move from Facets-managed infrastructure to a transparent, portable, code-owned platform (Terraform + GitHub Actions), **incrementally and service-by-service**, never a big-bang replacement.

## Guiding principle
Migrate one non-critical service end-to-end first, prove parity and rollback, then repeat. At no point is a resource owned by **both** Facets and Terraform.

## 1. Inventory & discovery
Before touching anything, produce a baseline:
- **Workloads**: every service, its image, command, scaling, and dependencies.
- **Environments**: local/dev/staging/prod and how they differ.
- **State & data**: databases, queues, buckets — what is stateful and must be imported (not recreated).
- **Secrets**: where they live, who consumes them, rotation story.
- **Networking**: VPCs, subnets, security groups, DNS, load balancers, public/private boundaries.
- **Hidden assumptions**: manual console steps, Facets-injected env vars, implicit IAM, defaults Facets sets that nothing documents.

Deliverable: an architecture + ownership map, and a list of "manual dependencies" to eliminate.

## 2. Tool selection criteria
- **Terraform/OpenTofu** for cloud resources (VPC, RDS, ECS, IAM) — mature import story, huge provider coverage, matches this repo.
- **Provider-native app config** (ECS task defs here) kept in the same repo.
- **GitOps** (Actions) for delivery, so every change is a reviewed PR with an audit trail.
- Criteria: state import support, team familiarity, blast-radius control, drift detection, secret integration.

## 3. Import vs. recreate
- **Stateful resources (RDS, ElastiCache, buckets, DNS zones)**: **import** with `terraform import` (or `import` blocks) — recreating risks data loss.
- **Stateless resources (task defs, services, SGs, target groups)**: **recreate** as code — cleaner than importing, easy to diff.
- For each imported resource, run `terraform plan` until it shows **no changes** — that proves the code matches reality before Facets releases ownership.

## 4. Avoiding dual ownership
The cardinal risk. For each service:
1. Freeze changes to it in Facets.
2. Import/recreate in Terraform and reach a **zero-diff plan**.
3. **Remove the resource from Facets management** (stop it reconciling) in the same change window.
4. Only then let Terraform apply future changes.

Never have both systems reconciling one resource — that causes fight-loops and drift.

## 5. Incremental cutover path
```
Inventory
  → Baseline architecture & ownership
  → Select one NON-critical service (e.g. the worker)
  → Rebuild/import as code (zero-diff plan)
  → Compare behaviour & cost vs. Facets
  → Migrate in staging, validate with the smoke test
  → Validate rollback (flip ownership back if needed)
  → Migrate production during a low-traffic window
  → Remove old Facets ownership, document new operations
  → Repeat for the next service
```

## 6. Validating parity
- Same images/digests; same env/secret shape.
- Run the **existing smoke test** against the Terraform-managed environment — identical business-flow verification used everywhere else.
- Compare metrics/logs and monthly cost against the Facets baseline before declaring parity.

## 7. Rollback & cutover strategy
- Keep the Facets definition in place (but not reconciling) until the Terraform-managed version has soaked. If something regresses, re-enable Facets ownership for that one service and investigate — because we migrated one service at a time, blast radius is contained.
- DNS/ALB weighting can shift traffic gradually where a service is user-facing.

## 8. Documentation & training
- Update runbooks (this repo's `docs/`) as each service moves.
- Pair product engineers through one PR-driven deploy so the GitOps flow is understood before they're on call for it.
- Record every eliminated manual step so the platform stays reproducible.
