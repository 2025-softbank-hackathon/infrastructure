variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "blue_service_name" {
  description = "Blue ECS service name"
  type        = string
}

variable "green_service_name" {
  description = "Green ECS service name"
  type        = string
}

variable "blue_desired_count" {
  description = "Blue service desired count when running"
  type        = number
  default     = 1
}

variable "green_desired_count" {
  description = "Green service desired count when running"
  type        = number
  default     = 1
}
