variable "project_name" {
  description = "프로젝트 이름"
  type        = string
}

variable "environment" {
  description = "환경 (dev, staging, prod 등)"
  type        = string
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
}

variable "ecs_cluster_arn" {
  description = "모니터링할 ECS 클러스터 ARN"
  type        = string
}

variable "slack_webhook_parameter_name" {
  description = "Slack Webhook URL이 저장된 Parameter Store 경로"
  type        = string
  default     = "/chatapp/slack/webhook-url"
}

variable "enable_alb_health_notifications" {
  description = "ALB 타겟 헬스 알림 활성화 여부"
  type        = bool
  default     = false
}

variable "target_group_arns" {
  description = "모니터링할 타겟 그룹 ARN 목록 (ALB 헬스 알림 활성화 시 필요)"
  type        = list(string)
  default     = []
}
