output "alb_sg_id" {
  description = "ALB Security Group ID"
  value       = aws_security_group.alb.id
}

output "ecs_sg_id" {
  description = "ECS Security Group ID"
  value       = aws_security_group.ecs.id
}

output "redis_sg_id" {
  description = "Redis Security Group ID"
  value       = aws_security_group.redis.id
}
