output "lambda_function_arn" {
  description = "Slack 알림 Lambda 함수 ARN"
  value       = aws_lambda_function.slack_notification.arn
}

output "lambda_function_name" {
  description = "Slack 알림 Lambda 함수 이름"
  value       = aws_lambda_function.slack_notification.function_name
}

output "lambda_role_arn" {
  description = "Lambda 실행 역할 ARN"
  value       = aws_iam_role.slack_notification_lambda.arn
}

output "eventbridge_rules" {
  description = "생성된 EventBridge 규칙 ARN 목록"
  value = {
    deployment_state_change = aws_cloudwatch_event_rule.ecs_deployment_state_change.arn
    alb_target_health       = var.enable_alb_health_notifications ? aws_cloudwatch_event_rule.alb_target_health[0].arn : null
  }
}

output "parameter_store_name" {
  description = "Slack Webhook URL Parameter Store 경로"
  value       = var.slack_webhook_parameter_name
}
