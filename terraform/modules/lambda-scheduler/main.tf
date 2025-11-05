# Lambda 함수용 IAM Role
resource "aws_iam_role" "lambda_scheduler" {
  name = "${var.project_name}-${var.environment}-lambda-scheduler"

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
    Name        = "${var.project_name}-${var.environment}-lambda-scheduler"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Lambda 기본 실행 권한 (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_scheduler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ECS 제어 권한
resource "aws_iam_role_policy" "lambda_ecs" {
  name = "${var.project_name}-${var.environment}-lambda-ecs-policy"
  role = aws_iam_role.lambda_scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:ListServices"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda 함수 - Stop Infrastructure
resource "aws_lambda_function" "stop_infrastructure" {
  filename         = "${path.module}/../../../lambda-scheduler/stop_infrastructure.zip"
  function_name    = "${var.project_name}-${var.environment}-stop-infrastructure"
  role            = aws_iam_role.lambda_scheduler.arn
  handler         = "stop_infrastructure.lambda_handler"
  source_code_hash = filebase64sha256("${path.module}/../../../lambda-scheduler/stop_infrastructure.zip")
  runtime         = "python3.11"
  timeout         = 300  # 5분

  environment {
    variables = {
      CLUSTER_NAME     = var.cluster_name
      BLUE_SERVICE     = var.blue_service_name
      GREEN_SERVICE    = var.green_service_name
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-stop-infrastructure"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Lambda 함수 - Start Infrastructure
resource "aws_lambda_function" "start_infrastructure" {
  filename         = "${path.module}/../../../lambda-scheduler/start_infrastructure.zip"
  function_name    = "${var.project_name}-${var.environment}-start-infrastructure"
  role            = aws_iam_role.lambda_scheduler.arn
  handler         = "start_infrastructure.lambda_handler"
  source_code_hash = filebase64sha256("${path.module}/../../../lambda-scheduler/start_infrastructure.zip")
  runtime         = "python3.11"
  timeout         = 600  # 10분 (서비스 안정화 대기 포함)

  environment {
    variables = {
      CLUSTER_NAME        = var.cluster_name
      BLUE_SERVICE        = var.blue_service_name
      GREEN_SERVICE       = var.green_service_name
      BLUE_DESIRED_COUNT  = tostring(var.blue_desired_count)
      GREEN_DESIRED_COUNT = tostring(var.green_desired_count)
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-start-infrastructure"
    Project     = var.project_name
    Environment = var.environment
  }
}

# EventBridge Rule - Stop at 00:00 KST (15:00 UTC)
resource "aws_cloudwatch_event_rule" "stop_infrastructure" {
  name                = "${var.project_name}-${var.environment}-stop-infrastructure"
  description         = "Stop infrastructure at 00:00 KST (15:00 UTC) daily"
  schedule_expression = "cron(0 15 * * ? *)"  # 00:00 KST

  tags = {
    Name        = "${var.project_name}-${var.environment}-stop-infrastructure"
    Project     = var.project_name
    Environment = var.environment
  }
}

# EventBridge Rule - Start at 08:00 KST (23:00 UTC previous day)
resource "aws_cloudwatch_event_rule" "start_infrastructure" {
  name                = "${var.project_name}-${var.environment}-start-infrastructure"
  description         = "Start infrastructure at 08:00 KST (23:00 UTC previous day) daily"
  schedule_expression = "cron(0 23 * * ? *)"  # 08:00 KST

  tags = {
    Name        = "${var.project_name}-${var.environment}-start-infrastructure"
    Project     = var.project_name
    Environment = var.environment
  }
}

# EventBridge Target - Stop
resource "aws_cloudwatch_event_target" "stop_infrastructure" {
  rule      = aws_cloudwatch_event_rule.stop_infrastructure.name
  target_id = "StopInfrastructure"
  arn       = aws_lambda_function.stop_infrastructure.arn
}

# EventBridge Target - Start
resource "aws_cloudwatch_event_target" "start_infrastructure" {
  rule      = aws_cloudwatch_event_rule.start_infrastructure.name
  target_id = "StartInfrastructure"
  arn       = aws_lambda_function.start_infrastructure.arn
}

# Lambda Permission - Allow EventBridge to invoke Stop function
resource "aws_lambda_permission" "allow_eventbridge_stop" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stop_infrastructure.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_infrastructure.arn
}

# Lambda Permission - Allow EventBridge to invoke Start function
resource "aws_lambda_permission" "allow_eventbridge_start" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_infrastructure.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start_infrastructure.arn
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "stop_infrastructure" {
  name              = "/aws/lambda/${aws_lambda_function.stop_infrastructure.function_name}"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-${var.environment}-stop-infrastructure-logs"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "start_infrastructure" {
  name              = "/aws/lambda/${aws_lambda_function.start_infrastructure.function_name}"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-${var.environment}-start-infrastructure-logs"
    Project     = var.project_name
    Environment = var.environment
  }
}
