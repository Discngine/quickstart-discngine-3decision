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
from datetime import datetime, timedelta
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    logger.info("=== Lambda function started ===")
    logger.info(f"Event: {json.dumps(event, default=str)}")
    logger.info(f"Context: {context}")
    
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    
    # Log environment variables
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    alarm_name = os.environ['ALARM_NAME']
    alb_arn_suffix = os.environ['ALB_ARN_SUFFIX']
    target_groups = json.loads(os.environ['TARGET_GROUPS'])
    
    logger.info(f"SNS Topic ARN: {sns_topic_arn}")
    logger.info(f"Alarm Name: {alarm_name}")
    logger.info(f"ALB ARN Suffix: {alb_arn_suffix}")
    logger.info(f"Target Groups: {json.dumps(target_groups, indent=2)}")
    
    try:
        # Check if the main alarm is in ALARM state
        logger.info(f"Checking alarm state for: {alarm_name}")
        response = cloudwatch.describe_alarms(AlarmNames=[alarm_name])
        logger.info(f"Describe alarms response: {json.dumps(response, default=str, indent=2)}")
        
        if not response['MetricAlarms']:
            logger.error(f"Alarm '{alarm_name}' not found!")
            return {
                'statusCode': 404,
                'body': json.dumps('Alarm not found')
            }
        
        alarm = response['MetricAlarms'][0]
        logger.info(f"Alarm state: {alarm['StateValue']}")
        logger.info(f"Alarm reason: {alarm.get('StateReason', 'No reason provided')}")
        logger.info(f"Alarm state updated: {alarm.get('StateUpdatedTimestamp', 'Unknown')}")
        
        if alarm['StateValue'] != 'ALARM':
            logger.info(f"Alarm is in '{alarm['StateValue']}' state, not 'ALARM'. No notification needed.")
            return {
                'statusCode': 200,
                'body': json.dumps(f"Alarm not in ALARM state (current: {alarm['StateValue']})")
            }
        
        logger.info("Alarm is in ALARM state. Checking individual target group metrics...")
        
        # Get detailed metrics for each service to identify which are unhealthy
        unhealthy_services = []
        total_unhealthy = 0
        
        # Use a wider time window for metric collection
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=1)  # Look back 1 hour
        
        logger.info(f"Querying metrics from {start_time.isoformat()}Z to {end_time.isoformat()}Z")
        
        for service_name, service_info in target_groups.items():
            logger.info(f"Checking metrics for service: {service_name}")
            logger.info(f"Service info: {json.dumps(service_info, indent=2)}")
            
            try:
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
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=300,  # 5 minute periods
                    Statistics=['Maximum', 'Average']
                )
                
                logger.info(f"Metric response for {service_name}: {json.dumps(metric_response, default=str, indent=2)}")
                
                if metric_response['Datapoints']:
                    datapoints = metric_response['Datapoints']
                    logger.info(f"Found {len(datapoints)} datapoints for {service_name}")
                    
                    # Sort datapoints by timestamp to get the latest
                    sorted_datapoints = sorted(datapoints, key=lambda x: x['Timestamp'], reverse=True)
                    latest_max = sorted_datapoints[0]['Maximum'] if sorted_datapoints else 0
                    latest_avg = sorted_datapoints[0]['Average'] if sorted_datapoints else 0
                    
                    logger.info(f"Latest metrics for {service_name}: Max={latest_max}, Avg={latest_avg}")
                    
                    if latest_max > 0:
                        unhealthy_services.append({
                            'name': service_name,
                            'port': service_info['port'],
                            'description': service_info['description'],
                            'unhealthy_count': int(latest_max),
                            'average_unhealthy': latest_avg
                        })
                        total_unhealthy += int(latest_max)
                        logger.info(f"Service {service_name} is UNHEALTHY: {int(latest_max)} targets")
                    else:
                        logger.info(f"Service {service_name} is HEALTHY: 0 unhealthy targets")
                else:
                    logger.warning(f"No datapoints found for service {service_name}")
                    
            except Exception as service_error:
                logger.error(f"Error querying metrics for {service_name}: {str(service_error)}")
                continue
        
        logger.info(f"Summary: {len(unhealthy_services)} unhealthy services found, total unhealthy targets: {total_unhealthy}")
        
        if unhealthy_services:
            logger.info("Building notification message...")
            
            # Build detailed notification message
            message = "RECURRING ALERT - 3Decision ALB Health Issues\\n\\n"
            message += f"Time: {datetime.utcnow().isoformat()}Z\\n"
            message += f"Total Unhealthy Targets: {total_unhealthy}\\n\\n"
            message += "AFFECTED SERVICES:\\n"
            message += "=" * 50 + "\\n"
            
            for service in unhealthy_services:
                message += f"\\n• SERVICE: {service['name'].upper()}\\n"
                message += f"  Port: {service['port']}\\n"
                message += f"  Description: {service['description']}\\n"
                message += f"  Unhealthy Targets: {service['unhealthy_count']}\\n"
                message += f"  Average Unhealthy: {service['average_unhealthy']:.2f}\\n"
            
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
            subject = f"RECURRING: 3Decision Health Issues - {subject_services} ({total_unhealthy} unhealthy targets)"
            
            logger.info(f"Sending SNS notification...")
            logger.info(f"Subject: {subject}")
            logger.info(f"Message preview: {message[:200]}...")
            
            sns_response = sns.publish(
                TopicArn=sns_topic_arn,
                Subject=subject,
                Message=message
            )
            
            logger.info(f"SNS publish response: {json.dumps(sns_response, default=str, indent=2)}")
            
            return {
                'statusCode': 200,
                'body': json.dumps(f'Sent detailed notification for {len(unhealthy_services)} unhealthy services. MessageId: {sns_response.get("MessageId", "Unknown")}')
            }
        else:
            logger.warning("Alarm is in ALARM state but no unhealthy targets found in recent metrics!")
            logger.info("This could indicate:")
            logger.info("1. The alarm condition was met briefly but targets are now healthy")
            logger.info("2. There's a delay between alarm triggering and metric availability")
            logger.info("3. The metric query parameters need adjustment")
            
            return {
                'statusCode': 200,
                'body': json.dumps('Alarm in ALARM state but no unhealthy targets found in recent metrics')
            }
            
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        logger.error(f"Error type: {type(e).__name__}")
        import traceback
        logger.error(f"Full traceback: {traceback.format_exc()}")
        
        # Try to send an error notification
        try:
            error_message = f"Error in 3Decision recurring alarm notifier:\\n\\nError: {str(e)}\\nTime: {datetime.utcnow().isoformat()}Z\\n\\nPlease check CloudWatch logs for details."
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject="ERROR: 3Decision Alarm Notifier Failed",
                Message=error_message
            )
            logger.info("Sent error notification via SNS")
        except Exception as sns_error:
            logger.error(f"Failed to send error notification: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

logger.info("=== Lambda function definition complete ===")
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
