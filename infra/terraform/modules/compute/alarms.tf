# Observability: an SNS topic + CloudWatch alarms on product-health signals.
# Subscribe an email/Slack/PagerDuty endpoint to the topic out of band.

resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
  tags = var.common_tags
}

# 1) API 5xx errors from the ALB (customer-facing failures).
resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.name}-api-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "API returning 5xx errors — likely a broken release or dependency."
  treat_missing_data  = "notBreaching"
  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
    TargetGroup  = aws_lb_target_group.api.arn_suffix
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = var.common_tags
}

# 2) No healthy API tasks behind the ALB (hard outage — page immediately).
resource "aws_cloudwatch_metric_alarm" "api_unhealthy_hosts" {
  alarm_name          = "${var.name}-api-no-healthy-hosts"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "No healthy API targets — service is down."
  treat_missing_data  = "breaching"
  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
    TargetGroup  = aws_lb_target_group.api.arn_suffix
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = var.common_tags
}

# 3) Worker service running below desired count (jobs may back up).
resource "aws_cloudwatch_metric_alarm" "worker_running_count" {
  alarm_name          = "${var.name}-worker-not-running"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = var.worker_desired_count
  alarm_description   = "Worker running fewer tasks than desired — jobs may not process."
  treat_missing_data  = "breaching"
  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = aws_ecs_service.worker.name
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = var.common_tags
}
