# ALB Health Monitoring Module
# This module creates CloudWatch alarms to monitor ALB target group health
# and sends email notifications when health checks fail

# Data source to find the ALB created by the AWS Load Balancer Controller
data "aws_lb" "tdecision_alb" {
  count = var.enable_alb_monitoring ? 1 : 0

  name = "lb-3dec"

  depends_on = [helm_release.tdecision_chart]
}

# Data source to get the target groups for the ALB
data "aws_lb_target_group" "tdecision_nest_front" {
  count = var.enable_alb_monitoring ? 1 : 0

  tags = {
    "ingress.k8s.aws/resource" = "tdecision/tdecision-ingress-tdecision-nest-front:3000"
  }

  depends_on = [helm_release.tdecision_chart]
}

data "aws_lb_target_group" "tdecision_react" {
  count = var.enable_alb_monitoring ? 1 : 0

  tags = {
    "ingress.k8s.aws/resource" = "tdecision/tdecision-ingress-tdecision-react:9020"
  }

  depends_on = [helm_release.tdecision_chart]
}

data "aws_lb_target_group" "tdecision_angular" {
  count = var.enable_alb_monitoring ? 1 : 0

  tags = {
    "ingress.k8s.aws/resource" = "tdecision/tdecision-ingress-tdecision-angular:9003"
  }

  depends_on = [helm_release.tdecision_chart]
}

# SNS Topic for ALB health notifications
resource "aws_sns_topic" "alb_health_alerts" {
  count = var.enable_alb_monitoring ? 1 : 0

  name         = "3decision-alb-health-alerts"
  display_name = "3Decision ALB Health Alerts"

  tags = {
    Name        = "3decision-alb-health-alerts"
    Environment = "production"
    Service     = "3decision"
  }
}

# SNS Topic subscription for email notifications
resource "aws_sns_topic_subscription" "alb_health_email" {
  count = var.enable_alb_monitoring && var.monitoring_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alb_health_alerts[0].arn
  protocol  = "email"
  endpoint  = var.monitoring_email
}

locals {
  monitoring_suffix = var.monitoring_account != "" ? "-${var.monitoring_account}" : ""
}

# Individual alarms for each service to provide detailed notifications
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_targets_nest_front" {
  count = var.enable_alb_monitoring ? 1 : 0

  alarm_name          = "3decision${local.monitoring_suffix}-nest-front-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "3Decision NEST-FRONT Service (port 3000) has unhealthy targets. This affects the main application frontend."
  alarm_actions       = var.monitoring_email != "" ? [aws_sns_topic.alb_health_alerts[0].arn] : []
  ok_actions          = var.monitoring_email != "" ? [aws_sns_topic.alb_health_alerts[0].arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = data.aws_lb.tdecision_alb[0].arn_suffix
    TargetGroup  = data.aws_lb_target_group.tdecision_nest_front[0].arn_suffix
  }

  tags = {
    Name    = "3decision-nest-front-unhealthy-targets"
    Service = "3decision-nest-front"
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_targets_react" {
  count = var.enable_alb_monitoring ? 1 : 0

  alarm_name          = "3decision${local.monitoring_suffix}-react-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "3Decision REACT Service (port 9020) has unhealthy targets. This affects the React-based components."
  alarm_actions       = var.monitoring_email != "" ? [aws_sns_topic.alb_health_alerts[0].arn] : []
  ok_actions          = var.monitoring_email != "" ? [aws_sns_topic.alb_health_alerts[0].arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = data.aws_lb.tdecision_alb[0].arn_suffix
    TargetGroup  = data.aws_lb_target_group.tdecision_react[0].arn_suffix
  }

  tags = {
    Name    = "3decision-react-unhealthy-targets"
    Service = "3decision-react"
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_targets_angular" {
  count = var.enable_alb_monitoring ? 1 : 0

  alarm_name          = "3decision${local.monitoring_suffix}-angular-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "3Decision ANGULAR Service (port 9003) has unhealthy targets. This affects the Angular-based components."
  alarm_actions       = var.monitoring_email != "" ? [aws_sns_topic.alb_health_alerts[0].arn] : []
  ok_actions          = var.monitoring_email != "" ? [aws_sns_topic.alb_health_alerts[0].arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = data.aws_lb.tdecision_alb[0].arn_suffix
    TargetGroup  = data.aws_lb_target_group.tdecision_angular[0].arn_suffix
  }

  tags = {
    Name    = "3decision-angular-unhealthy-targets"
    Service = "3decision-angular"
  }
}

# Output ALB monitoring information for reference
output "alb_monitoring_info" {
  value = var.enable_alb_monitoring ? {
    alb_arn        = data.aws_lb.tdecision_alb[0].arn
    alb_dns_name   = data.aws_lb.tdecision_alb[0].dns_name
    alb_name       = data.aws_lb.tdecision_alb[0].name
    alb_arn_suffix = data.aws_lb.tdecision_alb[0].arn_suffix
    sns_topic_arn  = aws_sns_topic.alb_health_alerts[0].arn
    individual_alarm_names = [
      aws_cloudwatch_metric_alarm.alb_unhealthy_targets_nest_front[0].alarm_name,
      aws_cloudwatch_metric_alarm.alb_unhealthy_targets_react[0].alarm_name,
      aws_cloudwatch_metric_alarm.alb_unhealthy_targets_angular[0].alarm_name
    ]
    # Debug information
    target_groups = {
      nest_front = data.aws_lb_target_group.tdecision_nest_front[0].arn_suffix
      react      = data.aws_lb_target_group.tdecision_react[0].arn_suffix
      angular    = data.aws_lb_target_group.tdecision_angular[0].arn_suffix
    }
  } : null
  description = "Information about ALB monitoring setup with individual service alarms"
}
