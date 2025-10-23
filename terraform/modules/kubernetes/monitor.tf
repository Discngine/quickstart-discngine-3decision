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

# CloudWatch Alarm for Unhealthy Target Count - All Services
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_targets" {
  count = var.enable_alb_monitoring ? 1 : 0

  alarm_name          = "3decision-alb-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  threshold           = "0"
  alarm_description   = "This metric monitors unhealthy targets across all 3Decision ALB target groups"
  alarm_actions       = var.monitoring_email != "" ? [aws_sns_topic.alb_health_alerts[0].arn] : []
  ok_actions          = var.monitoring_email != "" ? [aws_sns_topic.alb_health_alerts[0].arn] : []
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "e1"
    expression  = "m1 + m2 + m3"
    label       = "Total Unhealthy Hosts"
    return_data = "true"
  }

  metric_query {
    id = "m1"
    metric {
      metric_name = "UnHealthyHostCount"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Maximum"
      dimensions = {
        LoadBalancer = data.aws_lb.tdecision_alb[0].arn_suffix
        TargetGroup  = data.aws_lb_target_group.tdecision_nest_front[0].arn_suffix
      }
    }
  }

  metric_query {
    id = "m2"
    metric {
      metric_name = "UnHealthyHostCount"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Maximum"
      dimensions = {
        LoadBalancer = data.aws_lb.tdecision_alb[0].arn_suffix
        TargetGroup  = data.aws_lb_target_group.tdecision_react[0].arn_suffix
      }
    }
  }

  metric_query {
    id = "m3"
    metric {
      metric_name = "UnHealthyHostCount"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Maximum"
      dimensions = {
        LoadBalancer = data.aws_lb.tdecision_alb[0].arn_suffix
        TargetGroup  = data.aws_lb_target_group.tdecision_angular[0].arn_suffix
      }
    }
  }

  tags = {
    Name        = "3decision-alb-unhealthy-targets"
    Environment = "production"
    Service     = "3decision"
  }
}
