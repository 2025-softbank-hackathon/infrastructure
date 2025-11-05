# Lambda 함수 패키징을 위한 데이터 소스
data "archive_file" "lambda_package" {
  type        = "zip"
  source_file = "${path.module}/../../../lambda-slack-notification/slack_notification.py"
  output_path = "${path.module}/../../../lambda-slack-notification/slack_notification.zip"
}

# Lambda 실행 역할
resource "aws_iam_role" "slack_notification_lambda" {
  name = "${var.project_name}-${var.environment}-slack-notification-lambda"

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
    Name        = "${var.project_name}-${var.environment}-slack-notification-lambda-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Lambda 기본 실행 정책 (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.slack_notification_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Parameter Store 접근 정책
resource "aws_iam_role_policy" "parameter_store_access" {
  name = "${var.project_name}-${var.environment}-parameter-store-access"
  role = aws_iam_role.slack_notification_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:*:parameter/chatapp/slack/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

# Lambda 함수
resource "aws_lambda_function" "slack_notification" {
  filename         = data.archive_file.lambda_package.output_path
  function_name    = "${var.project_name}-${var.environment}-slack-notification"
  role            = aws_iam_role.slack_notification_lambda.arn
  handler         = "slack_notification.lambda_handler"
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
  runtime         = "python3.11"
  timeout         = 30
  memory_size     = 256

  environment {
    variables = {
      SLACK_WEBHOOK_PARAMETER = var.slack_webhook_parameter_name
      ENVIRONMENT             = var.environment
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-slack-notification"
    Environment = var.environment
    Project     = var.project_name
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "slack_notification" {
  name              = "/aws/lambda/${aws_lambda_function.slack_notification.function_name}"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-${var.environment}-slack-notification-logs"
    Environment = var.environment
    Project     = var.project_name
  }
}

# EventBridge 규칙: ECS Deployment State Change (COMPLETED/FAILED만)
resource "aws_cloudwatch_event_rule" "ecs_deployment_state_change" {
  name        = "${var.project_name}-${var.environment}-ecs-deployment-state-change"
  description = "Capture ECS deployment completed or failed events only"

  event_pattern = jsonencode({
    source      = ["aws.ecs"]
    detail-type = ["ECS Deployment State Change"]
    detail = {
      clusterArn       = [var.ecs_cluster_arn]
      deploymentStatus = ["COMPLETED", "FAILED"]
    }
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-ecs-deployment-state"
    Environment = var.environment
    Project     = var.project_name
  }
}

# EventBridge 타겟: Deployment State Change → Lambda
resource "aws_cloudwatch_event_target" "ecs_deployment_state_change" {
  rule      = aws_cloudwatch_event_rule.ecs_deployment_state_change.name
  target_id = "slack-notification-lambda"
  arn       = aws_lambda_function.slack_notification.arn
}

# Lambda 권한: Deployment State Change EventBridge
resource "aws_lambda_permission" "allow_eventbridge_deployment_state" {
  statement_id  = "AllowExecutionFromEventBridgeDeploymentState"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_notification.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ecs_deployment_state_change.arn
}

# EventBridge 규칙: ALB Target Health (선택적)
resource "aws_cloudwatch_event_rule" "alb_target_health" {
  count       = var.enable_alb_health_notifications ? 1 : 0
  name        = "${var.project_name}-${var.environment}-alb-target-health"
  description = "Capture ALB target health changes"

  event_pattern = jsonencode({
    source      = ["aws.elasticloadbalancing"]
    detail-type = ["Target Health"]
    detail = {
      targetGroupArn = var.target_group_arns
    }
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-alb-target-health"
    Environment = var.environment
    Project     = var.project_name
  }
}

# EventBridge 타겟: ALB Target Health → Lambda
resource "aws_cloudwatch_event_target" "alb_target_health" {
  count     = var.enable_alb_health_notifications ? 1 : 0
  rule      = aws_cloudwatch_event_rule.alb_target_health[0].name
  target_id = "slack-notification-lambda"
  arn       = aws_lambda_function.slack_notification.arn
}

# Lambda 권한: ALB Target Health EventBridge
resource "aws_lambda_permission" "allow_eventbridge_alb_health" {
  count         = var.enable_alb_health_notifications ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridgeALBHealth"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_notification.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.alb_target_health[0].arn
}
