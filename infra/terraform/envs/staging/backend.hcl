# Backend config for `terraform init -backend-config=envs/staging/backend.hcl`.
# The bucket + lock table are created once by the bootstrap step (see README).
bucket         = "pulseops-tfstate-staging"
key            = "staging/terraform.tfstate"
region         = "ap-south-1"
dynamodb_table = "pulseops-tflock"
encrypt        = true
