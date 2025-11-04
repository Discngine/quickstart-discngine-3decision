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

# Lambda function for recurring alarm notifications with detailed service info
resource "aws_lambda_function" "recurring_alarm_notifier" {
  count = var.enable_alb_monitoring ? 1 : 0

  filename         = "${path.module}/recurring_notifier.zip"
  function_name    = "3decision-recurring-alarm-notifier"
  role            = aws_iam_role.lambda_role[0].arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 60

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.alb_health_alerts[0].arn
      ALARM_NAME = "3decision${local.monitoring_suffix}-unhealthy-targets"
      ALB_ARN_SUFFIX = data.aws_lb.tdecision_alb[0].arn_suffix
      TARGET_GROUPS = jsonencode({
        "nest-front" = {
          arn_suffix = data.aws_lb_target_group.tdecision_nest_front[0].arn_suffix
          port = "3000"
          description = "NEST-FRONT Service (main application frontend)"
        }
        "react" = {
          arn_suffix = data.aws_lb_target_group.tdecision_react[0].arn_suffix
          port = "9020"
          description = "REACT Service (React-based components)"
        }
        "angular" = {
          arn_suffix = data.aws_lb_target_group.tdecision_angular[0].arn_suffix
          port = "9003"
          description = "ANGULAR Service (Angular-based components)"
        }
      })
    }
  }

  depends_on = [data.archive_file.lambda_zip]

  tags = {
    Name        = "3decision-recurring-alarm-notifier"
    Environment = "production"
    Service     = "3decision"
  }
}

# Create Lambda deployment package with detailed service checking
data "archive_file" "lambda_zip" {
  count = var.enable_alb_monitoring ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/recurring_notifier.zip"
  
  source {
    content = <<EOF
import boto3
import json
import os
from datetime import datetime

def handler(event, context):
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    alarm_name = os.environ['ALARM_NAME']
    alb_arn_suffix = os.environ['ALB_ARN_SUFFIX']
    target_groups = json.loads(os.environ['TARGET_GROUPS'])
    
    try:
        # Check if the main alarm is in ALARM state
        response = cloudwatch.describe_alarms(AlarmNames=[alarm_name])
        
        if not response['MetricAlarms']:
            return {
                'statusCode': 404,
                'body': json.dumps('Alarm not found')
            }
        
        alarm = response['MetricAlarms'][0]
        
        if alarm['StateValue'] != 'ALARM':
            return {
                'statusCode': 200,
                'body': json.dumps('Alarm not in ALARM state')
            }
        
        # Get detailed metrics for each service to identify which are unhealthy
        unhealthy_services = []
        total_unhealthy = 0
        
        for service_name, service_info in target_groups.items():
            metric_response = cloudwatch.get_metric_statistics(
                Namespace='AWS/ApplicationELB',
                MetricName='UnHealthyHostCount',
                Dimensions=[
                    {
                        'Name': 'LoadBalancer',
                        'Value': alb_arn_suffix
                    },
                    {
                        'Name': 'TargetGroup',
                        'Value': service_info['arn_suffix']
                    }
                ],
                StartTime=datetime.utcnow().replace(minute=0, second=0, microsecond=0),
                EndTime=datetime.utcnow(),
                Period=300,
                Statistics=['Maximum']
            )
            
            if metric_response['Datapoints']:
                latest_value = max(point['Maximum'] for point in metric_response['Datapoints'])
                if latest_value > 0:
                    unhealthy_services.append({
                        'name': service_name,
                        'port': service_info['port'],
                        'description': service_info['description'],
                        'unhealthy_count': int(latest_value)
                    })
                    total_unhealthy += int(latest_value)
        
        if unhealthy_services:
            # Build detailed notification message
            message = "🚨 RECURRING ALERT - 3Decision ALB Health Issues\\n\\n"
            message += f"Time: {datetime.utcnow().isoformat()}Z\\n"
            message += f"Total Unhealthy Targets: {total_unhealthy}\\n\\n"
            message += "AFFECTED SERVICES:\\n"
            message += "=" * 50 + "\\n"
            
            for service in unhealthy_services:
                message += f"\\n• SERVICE: {service['name'].upper()}\\n"
                message += f"  Port: {service['port']}\\n"
                message += f"  Description: {service['description']}\\n"
                message += f"  Unhealthy Targets: {service['unhealthy_count']}\\n"
            
            message += "\\n" + "=" * 50 + "\\n"
            message += f"\\nAlarm: {alarm_name}\\n"
            message += f"State Since: {alarm['StateUpdatedTimestamp'].isoformat()}\\n"
            message += f"Reason: {alarm['StateReason']}\\n\\n"
            message += "IMMEDIATE ACTION REQUIRED:\\n"
            message += "• Check Kubernetes pod health\\n"
            message += "• Verify application logs\\n"
            message += "• Confirm network connectivity\\n"
            message += "• Review resource utilization\\n\\n"
            message += "This notification will repeat every hour until all services are healthy."
            
            subject_services = ", ".join([s['name'].upper() for s in unhealthy_services])
            subject = f"🚨 RECURRING: 3Decision Health Issues - {subject_services} ({total_unhealthy} unhealthy targets)"
            
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject=subject,
                Message=message
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps(f'Sent detailed notification for {len(unhealthy_services)} unhealthy services')
            }
        else:
            return {
                'statusCode': 200,
                'body': json.dumps('Alarm in ALARM state but no unhealthy targets found in recent metrics')
            }
            
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
EOF
    filename = "index.py"
  }
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  count = var.enable_alb_monitoring ? 1 : 0

  name = "3decision-recurring-notifier-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "3decision-recurring-notifier-role"
    Environment = "production"
    Service     = "3decision"
  }
}

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  count = var.enable_alb_monitoring ? 1 : 0

  name = "3decision-recurring-notifier-policy"
  role = aws_iam_role.lambda_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarms",
          "cloudwatch:GetMetricStatistics"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.alb_health_alerts[0].arn
      }
    ]
  })
}

# CloudWatch Event Rule to trigger Lambda every hour
resource "aws_cloudwatch_event_rule" "recurring_check" {
  count = var.enable_alb_monitoring ? 1 : 0

  name                = "3decision-recurring-alarm-check"
  description         = "Trigger recurring alarm notifications every hour"
  schedule_expression = "rate(1 hour)"

  tags = {
    Name        = "3decision-recurring-alarm-check"
    Environment = "production"
    Service     = "3decision"
  }
}

# CloudWatch Event Target
resource "aws_cloudwatch_event_target" "lambda_target" {
  count = var.enable_alb_monitoring ? 1 : 0

  rule      = aws_cloudwatch_event_rule.recurring_check[0].name
  target_id = "RecurringAlarmNotifierTarget"
  arn       = aws_lambda_function.recurring_alarm_notifier[0].arn
}

# Lambda permission for CloudWatch Events
resource "aws_lambda_permission" "allow_cloudwatch" {
  count = var.enable_alb_monitoring ? 1 : 0

  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.recurring_alarm_notifier[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.recurring_check[0].arn
}

# Single CloudWatch Alarm that monitors all services
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_targets_combined" {
  count = var.enable_alb_monitoring ? 1 : 0

  alarm_name          = "3decision${local.monitoring_suffix}-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  threshold           = "0"
  alarm_description   = "3Decision ALB has unhealthy targets. Services monitored: NEST-FRONT (port 3000), REACT (port 9020), ANGULAR (port 9003). Check individual metrics m1, m2, m3 to identify which service(s) are affected."
  alarm_actions       = var.monitoring_email != "" ? [aws_sns_topic.alb_health_alerts[0].arn] : []
  ok_actions          = var.monitoring_email != "" ? [aws_sns_topic.alb_health_alerts[0].arn] : []
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "e1"
    expression  = "m1 + m2 + m3"
    label       = "Total Unhealthy Hosts Across All Services"
    return_data = "true"
  }

  metric_query {
    id    = "m1"
    label = "NEST-FRONT (port 3000) Unhealthy Hosts"
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
    id    = "m2"
    label = "REACT (port 9020) Unhealthy Hosts"
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
    id    = "m3"
    label = "ANGULAR (port 9003) Unhealthy Hosts"
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
    Name    = "3decision-unhealthy-targets"
    Service = "3decision"
  }
}

locals {
  monitoring_suffix = var.monitoring_account != "" ? "-${var.monitoring_account}" : ""
}

# Output ALB monitoring information for reference
output "alb_monitoring_info" {
  value = var.enable_alb_monitoring ? {
    alb_arn        = data.aws_lb.tdecision_alb[0].arn
    alb_dns_name   = data.aws_lb.tdecision_alb[0].dns_name
    alb_name       = data.aws_lb.tdecision_alb[0].name
    alb_arn_suffix = data.aws_lb.tdecision_alb[0].arn_suffix
    sns_topic_arn  = aws_sns_topic.alb_health_alerts[0].arn
    alarm_name     = aws_cloudwatch_metric_alarm.alb_unhealthy_targets_combined[0].alarm_name
    lambda_function_name = aws_lambda_function.recurring_alarm_notifier[0].function_name
    recurring_schedule = aws_cloudwatch_event_rule.recurring_check[0].schedule_expression
    # Debug information
    target_groups = {
      nest_front = data.aws_lb_target_group.tdecision_nest_front[0].arn_suffix
      react      = data.aws_lb_target_group.tdecision_react[0].arn_suffix
      angular    = data.aws_lb_target_group.tdecision_angular[0].arn_suffix
    }
  } : null
  description = "Information about ALB monitoring setup with single combined alarm and hourly recurring detailed notifications"
}
