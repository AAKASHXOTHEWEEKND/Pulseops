output "repository_urls" {
  value = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "app_repository_url" {
  value = aws_ecr_repository.this["app"].repository_url
}

output "web_repository_url" {
  value = aws_ecr_repository.this["web"].repository_url
}
