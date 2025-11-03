# CloudWatch 알람 for ALB 타겟 헬스 체크
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "0"
  alarm_description   = "This metric monitors unhealthy ALB targets"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.blue_target_group_arn_suffix
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-alb-unhealthy-hosts"
    Project     = var.project_name
    Environment = var.environment
  }
}

# CloudWatch 알람 for ALB 4xx 에러율
resource "aws_cloudwatch_metric_alarm" "alb_4xx_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_4XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Sum"
  threshold           = "50"  # 1분에 50개 이상의 4xx 에러
  alarm_description   = "This metric monitors ALB 4xx error rate"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-alb-4xx-errors"
    Project     = var.project_name
    Environment = var.environment
  }
}

# CloudWatch 알람 for ALB 5xx 에러율
resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Sum"
  threshold           = "10"  # 1분에 10개 이상의 5xx 에러
  alarm_description   = "This metric monitors ALB 5xx error rate"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-alb-5xx-errors"
    Project     = var.project_name
    Environment = var.environment
  }
}

# CloudWatch 알람 for ALB Target Response Time (P95)
resource "aws_cloudwatch_metric_alarm" "alb_target_response_time" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-response-time-p95"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  threshold           = "2.0"  # 2초

  metric_query {
    id          = "m1"
    return_data = true

    metric {
      metric_name = "TargetResponseTime"
      namespace   = "AWS/ApplicationELB"
      period      = "60"
      stat        = "p95"

      dimensions = {
        LoadBalancer = var.alb_arn_suffix
      }
    }
  }

  alarm_description  = "This metric monitors ALB target response time at p95"
  treat_missing_data = "notBreaching"

  tags = {
    Name        = "${var.project_name}-${var.environment}-alb-response-time-p95"
    Project     = var.project_name
    Environment = var.environment
  }
}

# CloudWatch 로그 그룹 for ECS
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}-${var.environment}"
  retention_in_days = 7  # 해커톤용 짧은 보관 기간

  tags = {
    Name        = "${var.project_name}-${var.environment}-ecs-logs"
    Project     = var.project_name
    Environment = var.environment
  }
}
