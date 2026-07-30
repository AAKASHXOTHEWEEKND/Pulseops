# Approximate Monthly Cost & Cleanup

Rough **staging** estimate, AWS `ap-south-1`, on-demand, running 24×7. Real cost depends on traffic and region — figures are ballpark for planning, not a quote.

| Resource | Config | Est. USD/mo |
|----------|--------|-------------|
| ECS Fargate — API | 2 tasks × 0.25 vCPU / 0.5 GB | ~$18 |
| ECS Fargate — worker | 1 task × 0.25 vCPU / 0.5 GB | ~$9 |
| ECS Fargate — web | 1 task × 0.25 vCPU / 0.5 GB | ~$9 |
| Application Load Balancer | 1 ALB + LCUs | ~$18 |
| RDS PostgreSQL | db.t4g.micro, 20 GB gp3, single-AZ | ~$15 |
| ElastiCache Redis | cache.t4g.micro, 1 node | ~$12 |
| NAT Gateway | 1 gateway + data processing | ~$32 |
| CloudWatch logs/metrics | low volume, 14-day retention | ~$5 |
| ECR storage | a few small images | ~$1 |
| Secrets Manager | 1 secret | ~$0.40 |
| **Total (staging)** | | **~$120/mo** |

**Biggest levers:** the NAT gateway and ALB are the fixed costs. To cut staging spend: run the stack **only during working hours** (schedule ECS desired counts to 0 overnight), or run everything locally via `docker compose` at **$0**.

Production is higher (Multi-AZ RDS, larger tasks, 2× worker, longer retention) — estimate ~$250–350/mo at low traffic.

## Cleanup / destruction

**Local:**
```bash
make clean          # docker compose down -v (stops stack, removes volumes)
```

**Cloud (Terraform):**
```bash
cd infra/terraform
terraform destroy -var-file=envs/staging/staging.tfvars
```
Notes:
- Production RDS has `deletion_protection = true` and `skip_final_snapshot = false` — you must disable protection / allow the final snapshot before destroy (intentional guardrail).
- The S3 state bucket + DynamoDB lock table are created by the **bootstrap** module and are **not** destroyed by the main `destroy`. Remove them last, manually, once no environment needs state:
  ```bash
  cd infra/terraform/bootstrap && terraform destroy -var environment=staging
  ```
- ECR images incur trivial storage cost; the lifecycle policy expires untagged images after 14 days.

**Verify teardown:** `terraform state list` returns empty, and the ECS cluster / RDS / ElastiCache no longer appear in the console.
