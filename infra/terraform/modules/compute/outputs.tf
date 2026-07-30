output "alb_dns_name" {
  value       = aws_lb.this.dns_name
  description = "Public ALB DNS name (frontend + API entrypoint)."
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "api_service_name" {
  value = aws_ecs_service.api.name
}

output "worker_service_name" {
  value = aws_ecs_service.worker.name
}

output "web_service_name" {
  value = aws_ecs_service.web.name
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}
