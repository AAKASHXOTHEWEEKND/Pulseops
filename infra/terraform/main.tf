provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  name = "${var.project}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags,
  )
}

# --------------------------------------------------------------------------- #
# Networking: VPC with public + private subnets, NAT, boundaries.
# --------------------------------------------------------------------------- #
module "network" {
  source      = "./modules/network"
  name        = local.name
  vpc_cidr    = var.vpc_cidr
  az_count    = var.az_count
  common_tags = local.common_tags
}

# --------------------------------------------------------------------------- #
# Data stores: RDS PostgreSQL (private) + ElastiCache Redis (private).
# Secrets (DB password) live in Secrets Manager, never in code/state literals.
# --------------------------------------------------------------------------- #
module "data" {
  source             = "./modules/data"
  name               = local.name
  environment        = var.environment
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  # App SG lives in the network module to avoid a data<->compute cycle.
  app_security_group = module.network.app_security_group_id
  db_instance_class  = var.db_instance_class
  common_tags        = local.common_tags
}

# --------------------------------------------------------------------------- #
# Container registry for the app + web images.
# --------------------------------------------------------------------------- #
module "ecr" {
  source      = "./modules/ecr"
  name        = local.name
  common_tags = local.common_tags
}

# --------------------------------------------------------------------------- #
# Compute: ECS Fargate cluster, ALB, API service, worker service, IAM.
# --------------------------------------------------------------------------- #
module "compute" {
  source = "./modules/compute"

  name                  = local.name
  environment           = var.environment
  aws_region            = var.aws_region
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  private_subnet_ids    = module.network.private_subnet_ids
  app_security_group_id = module.network.app_security_group_id
  alb_security_group_id = module.network.alb_security_group_id

  api_image = var.api_image
  web_image = var.web_image

  api_desired_count    = var.api_desired_count
  worker_desired_count = var.worker_desired_count
  api_cpu              = var.api_cpu
  api_memory           = var.api_memory
  worker_cpu           = var.worker_cpu
  worker_memory        = var.worker_memory

  database_url_secret_arn = module.data.database_url_secret_arn
  redis_url               = module.data.redis_url
  log_retention_days      = var.log_retention_days

  common_tags = local.common_tags
}
