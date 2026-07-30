# Backend config for `terraform init -backend-config=envs/production/backend.hcl`.
bucket         = "pulseops-tfstate-production"
key            = "production/terraform.tfstate"
region         = "ap-south-1"
dynamodb_table = "pulseops-tflock"
encrypt        = true
