# ECS Fargate cluster + API/web/worker services. All three run the immutable
# images built in CI; the api and worker share one image, differing by command.

resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  tags = var.common_tags
}

# --- CloudWatch log groups (one per service) ---
resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.name}/api"
  retention_in_days = var.log_retention_days
  tags              = var.common_tags
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/${var.name}/worker"
  retention_in_days = var.log_retention_days
  tags              = var.common_tags
}

resource "aws_cloudwatch_log_group" "web" {
  name              = "/ecs/${var.name}/web"
  retention_in_days = var.log_retention_days
  tags              = var.common_tags
}

locals {
  # Env common to api + worker.
  app_env = [
    { name = "APP_ENV", value = var.environment },
    { name = "REDIS_URL", value = var.redis_url },
    { name = "LOG_LEVEL", value = "INFO" },
  ]
  # DATABASE_URL is injected from Secrets Manager (never a literal).
  app_secrets = [
    { name = "DATABASE_URL", valueFrom = var.database_url_secret_arn },
  ]
}

# --------------------------------------------------------------------------- #
# API task definition + service
# --------------------------------------------------------------------------- #
resource "aws_ecs_task_definition" "api" {
  family                   = "${var.name}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.api_cpu
  memory                   = var.api_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name         = "api"
      image        = var.api_image
      essential    = true
      command      = ["gunicorn", "pulseops.api:app", "-c", "gunicorn_conf.py"]
      portMappings = [{ containerPort = 8000, protocol = "tcp" }]
      environment  = local.app_env
      secrets      = local.app_secrets
      stopTimeout  = 30
      healthCheck = {
        command     = ["CMD-SHELL", "curl -fsS http://localhost:8000/health/live || exit 1"]
        interval    = 15
        timeout     = 3
        retries     = 3
        startPeriod = 20
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.api.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "api"
        }
      }
    }
  ])
  tags = var.common_tags
}

resource "aws_ecs_service" "api" {
  name            = "${var.name}-api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.api_desired_count
  launch_type     = "FARGATE"

  # Rolling deploy with a circuit breaker that auto-rolls-back a bad release.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.app_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.http]
  tags       = var.common_tags
}

# --------------------------------------------------------------------------- #
# Worker task definition + service (no load balancer; scales independently)
# --------------------------------------------------------------------------- #
resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.name}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.worker_cpu
  memory                   = var.worker_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name        = "worker"
      image       = var.api_image
      essential   = true
      command     = ["python", "-m", "pulseops.worker"]
      environment = local.app_env
      secrets     = local.app_secrets
      # Give in-flight jobs time to finish on SIGTERM before SIGKILL.
      stopTimeout = 30
      healthCheck = {
        command     = ["CMD-SHELL", "curl -fsS http://localhost:8080/health/ready || exit 1"]
        interval    = 15
        timeout     = 3
        retries     = 3
        startPeriod = 20
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.worker.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "worker"
        }
      }
    }
  ])
  tags = var.common_tags
}

resource "aws_ecs_service" "worker" {
  name            = "${var.name}-worker"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = var.worker_desired_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.app_security_group_id]
    assign_public_ip = false
  }
  tags = var.common_tags
}

# --------------------------------------------------------------------------- #
# Web (nginx) task definition + service
# --------------------------------------------------------------------------- #
resource "aws_ecs_task_definition" "web" {
  family                   = "${var.name}-web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name         = "web"
      image        = var.web_image
      essential    = true
      portMappings = [{ containerPort = 8080, protocol = "tcp" }]
      # Browser calls the API on the same ALB origin; the ALB routes API paths
      # to the API target group. So the frontend uses the ALB DNS as its base.
      environment = [
        { name = "API_BASE_URL", value = "http://${aws_lb.this.dns_name}" },
        { name = "API_UPSTREAM", value = "127.0.0.1:8000" },
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://localhost:8080/healthz || exit 1"]
        interval    = 15
        timeout     = 3
        retries     = 3
        startPeriod = 10
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.web.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "web"
        }
      }
    }
  ])
  tags = var.common_tags
}

resource "aws_ecs_service" "web" {
  name            = "${var.name}-web"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.app_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "web"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.http]
  tags       = var.common_tags
}
