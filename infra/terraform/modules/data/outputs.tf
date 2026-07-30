output "database_url_secret_arn" {
  value       = aws_secretsmanager_secret.database_url.arn
  description = "Secrets Manager ARN holding the full DATABASE_URL."
}

output "db_endpoint" {
  value = aws_db_instance.this.endpoint
}

output "redis_url" {
  value       = "redis://${aws_elasticache_cluster.this.cache_nodes[0].address}:6379/0"
  description = "Redis connection URL (private)."
}
