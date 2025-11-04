output "cluster_id" {
  description = "ECS cluster ID"
  value       = aws_ecs_cluster.main.id
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "blue_service_name" {
  description = "Blue ECS service name"
  value       = aws_ecs_service.blue.name
}

output "green_service_name" {
  description = "Green ECS service name"
  value       = aws_ecs_service.green.name
}

output "service_name" {
  description = "Primary ECS service name (blue)"
  value       = aws_ecs_service.blue.name
}

output "blue_task_definition_arn" {
  description = "Blue task definition ARN"
  value       = aws_ecs_task_definition.blue.arn
}

output "green_task_definition_arn" {
  description = "Green task definition ARN"
  value       = aws_ecs_task_definition.green.arn
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = var.log_group_name
}
