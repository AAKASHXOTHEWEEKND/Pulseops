# Remote state with locking. Backends cannot use variables, so the bucket /
# table / key are supplied at init time from the environment's backend config:
#
#   terraform init -backend-config=envs/staging/backend.hcl
#
# The bucket + DynamoDB lock table are created once as a bootstrap step
# (see infra/terraform/bootstrap/ and the README). This is the only
# documented manual bootstrap action.
terraform {
  backend "s3" {
    encrypt = true
    # bucket / key / region / dynamodb_table injected via -backend-config
  }
}
