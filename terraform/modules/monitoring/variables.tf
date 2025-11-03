variable "project_name" {
  description = "프로젝트 이름"
  type        = string
}

variable "environment" {
  description = "환경 이름"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix (CloudWatch 메트릭용)"
  type        = string
}

variable "blue_target_group_arn_suffix" {
  description = "Blue 타겟 그룹 ARN suffix"
  type        = string
}

variable "green_target_group_arn_suffix" {
  description = "Green 타겟 그룹 ARN suffix"
  type        = string
}
