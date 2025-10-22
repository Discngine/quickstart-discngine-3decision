# ALB Health Monitoring Module
# This module creates CloudWatch alarms to monitor ALB target group health
# and sends email notifications when health checks fail

# Data source to find the ALB created by the AWS Load Balancer Controller
data "aws_lb" "tdecision_alb" {
  count = var.enable_alb_monitoring ? 1 : 0

  name = "lb-3dec"

  depends_on = [helm_release.tdecision_chart]
}

# Data source to find target groups for the ALB
data "aws_lb_target_groups" "tdecision_tg" {
  count = var.enable_alb_monitoring ? 1 : 0

  load_balancer_arn = data.aws_lb.tdecision_alb[0].arn
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

# CloudWatch Alarm for Unhealthy Target Count
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_targets" {
  count = var.enable_alb_monitoring ? length(data.aws_lb_target_groups.tdecision_tg[0].arns) : 0

  alarm_name          = "3decision-alb-unhealthy-targets-${count.index}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "This metric monitors unhealthy targets in 3Decision ALB target group"
  alarm_actions       = var.monitoring_email != "" ? [aws_sns_topic.alb_health_alerts[0].arn] : []
  ok_actions          = var.monitoring_email != "" ? [aws_sns_topic.alb_health_alerts[0].arn] : []
  treat_missing_data  = "breaching"

  dimensions = {
    LoadBalancer = data.aws_lb.tdecision_alb[0].arn_suffix
    TargetGroup  = element(split("/", data.aws_lb_target_groups.tdecision_tg[0].arns[count.index]), 1)
  }

  tags = {
    Name        = "3decision-alb-unhealthy-targets-${count.index}"
    Environment = "production"
    Service     = "3decision"
  }
}

# CloudWatch Alarm for Target Response Time
resource "aws_cloudwatch_metric_alarm" "alb_high_response_time" {
  count = var.enable_alb_monitoring ? length(data.aws_lb_target_groups.tdecision_tg[0].arns) : 0

  alarm_name          = "3decision-alb-high-response-time-${count.index}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = "5"  # 5 seconds
  alarm_description   = "This metric monitors high response times for 3Decision ALB target group"
  alarm_actions       = var.monitoring_email != "" ? [aws_sns_topic.alb_health_alerts[0].arn] : []
  ok_actions          = var.monitoring_email != "" ? [aws_sns_topic.alb_health_alerts[0].arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = data.aws_lb.tdecision_alb[0].arn_suffix
    TargetGroup  = element(split("/", data.aws_lb_target_groups.tdecision_tg[0].arns[count.index]), 1)
  }

  tags = {
    Name        = "3decision-alb-high-response-time-${count.index}"
    Environment = "production"
    Service     = "3decision"
  }
}

# CloudWatch Alarm for HTTP 5XX Error Rate
resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  count = var.enable_alb_monitoring ? 1 : 0

  alarm_name          = "3decision-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"  # More than 10 5XX errors in 5 minutes
  alarm_description   = "This metric monitors 5XX errors from 3Decision ALB"
  alarm_actions       = var.monitoring_email != "" ? [aws_sns_topic.alb_health_alerts[0].arn] : []
  ok_actions          = var.monitoring_email != "" ? [aws_sns_topic.alb_health_alerts[0].arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = data.aws_lb.tdecision_alb[0].arn_suffix
  }

  tags = {
    Name        = "3decision-alb-5xx-errors"
    Environment = "production"
    Service     = "3decision"
  }
}

# CloudWatch Alarm for HTTP 4XX Error Rate (High volume)
resource "aws_cloudwatch_metric_alarm" "alb_4xx_errors" {
  count = var.enable_alb_monitoring ? 1 : 0

  alarm_name          = "3decision-alb-4xx-errors-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "HTTPCode_ELB_4XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "50"  # More than 50 4XX errors in 5 minutes
  alarm_description   = "This metric monitors high volume of 4XX errors from 3Decision ALB"
  alarm_actions       = var.monitoring_email != "" ? [aws_sns_topic.alb_health_alerts[0].arn] : []
  ok_actions          = var.monitoring_email != "" ? [aws_sns_topic.alb_health_alerts[0].arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = data.aws_lb.tdecision_alb[0].arn_suffix
  }

  tags = {
    Name        = "3decision-alb-4xx-errors-high"
    Environment = "production"
    Service     = "3decision"
  }
}

# CloudWatch Dashboard for ALB Monitoring
resource "aws_cloudwatch_dashboard" "alb_monitoring" {
  count = var.enable_alb_monitoring ? 1 : 0

  dashboard_name = "3Decision-ALB-Health-Dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = concat(
            [
              for i, tg_arn in data.aws_lb_target_groups.tdecision_tg[0].arns : [
                "AWS/ApplicationELB",
                "HealthyHostCount",
                "LoadBalancer", data.aws_lb.tdecision_alb[0].arn_suffix,
                "TargetGroup", element(split("/", tg_arn), 1)
              ]
            ],
            [
              for i, tg_arn in data.aws_lb_target_groups.tdecision_tg[0].arns : [
                "AWS/ApplicationELB",
                "UnHealthyHostCount",
                "LoadBalancer", data.aws_lb.tdecision_alb[0].arn_suffix,
                "TargetGroup", element(split("/", tg_arn), 1)
              ]
            ]
          )
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "ALB Target Health"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", data.aws_lb.tdecision_alb[0].arn_suffix],
            [".", "HTTPCode_ELB_5XX_Count", ".", "."],
            [".", "HTTPCode_ELB_4XX_Count", ".", "."],
            [".", "RequestCount", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "ALB Performance Metrics"
          period  = 300
        }
      }
    ]
  })
}

# Output ALB information for reference
output "alb_monitoring_info" {
  value = var.enable_alb_monitoring ? {
    alb_arn                = data.aws_lb.tdecision_alb[0].arn
    alb_dns_name          = data.aws_lb.tdecision_alb[0].dns_name
    target_group_arns     = data.aws_lb_target_groups.tdecision_tg[0].arns
    sns_topic_arn         = aws_sns_topic.alb_health_alerts[0].arn
    cloudwatch_dashboard  = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.alb_monitoring[0].dashboard_name}"
    alarm_names = concat(
      aws_cloudwatch_metric_alarm.alb_unhealthy_targets[*].alarm_name,
      aws_cloudwatch_metric_alarm.alb_high_response_time[*].alarm_name,
      [aws_cloudwatch_metric_alarm.alb_5xx_errors[0].alarm_name],
      [aws_cloudwatch_metric_alarm.alb_4xx_errors[0].alarm_name]
    )
  } : null
  description = "Information about ALB monitoring setup"
}