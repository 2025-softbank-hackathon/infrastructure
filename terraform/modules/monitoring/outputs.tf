output "ecs_log_group_name" {
  description = "ECS CloudWatch 로그 그룹 이름"
  value       = aws_cloudwatch_log_group.ecs.name
}

output "ecs_log_group_arn" {
  description = "ECS CloudWatch 로그 그룹 ARN"
  value       = aws_cloudwatch_log_group.ecs.arn
}
