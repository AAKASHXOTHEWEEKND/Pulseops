output "alb_dns_name" {
  description = "Public URL for the web portal + API (http://<dns>)."
  value       = module.compute.alb_dns_name
}

output "api_base_url" {
  description = "API base URL for the smoke test."
  value       = "http://${module.compute.alb_dns_name}"
}

output "ecs_cluster" {
  value = module.compute.cluster_name
}

output "api_service_name" {
  value = module.compute.api_service_name
}

output "worker_service_name" {
  value = module.compute.worker_service_name
}

output "web_service_name" {
  value = module.compute.web_service_name
}

output "ecr_app_repository_url" {
  value = module.ecr.app_repository_url
}

output "ecr_web_repository_url" {
  value = module.ecr.web_repository_url
}

output "alerts_topic_arn" {
  value = module.compute.alerts_topic_arn
}

output "db_endpoint" {
  value     = module.data.db_endpoint
  sensitive = true
}
