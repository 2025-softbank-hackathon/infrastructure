output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.main.arn
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix (CloudWatch 메트릭용)"
  value       = aws_lb.main.arn_suffix
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "ALB zone ID"
  value       = aws_lb.main.zone_id
}

output "blue_target_group_arn" {
  description = "Blue target group ARN"
  value       = aws_lb_target_group.blue.arn
}

output "blue_target_group_arn_suffix" {
  description = "Blue target group ARN suffix (CloudWatch 메트릭용)"
  value       = aws_lb_target_group.blue.arn_suffix
}

output "green_target_group_arn" {
  description = "Green target group ARN"
  value       = aws_lb_target_group.green.arn
}

output "green_target_group_arn_suffix" {
  description = "Green target group ARN suffix (CloudWatch 메트릭용)"
  value       = aws_lb_target_group.green.arn_suffix
}

output "listener_arn" {
  description = "HTTP listener ARN"
  value       = aws_lb_listener.http.arn
}
