variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "프로젝트 이름"
  type        = string
  default     = "chatapp"
}

variable "environment" {
  description = "환경 이름"
  type        = string
  default     = "dev"
}

# VPC 설정
variable "vpc_cidr" {
  description = "VPC의 CIDR 블록"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "가용 영역 (ALB는 최소 2개의 서로 다른 AZ 서브넷 필요)"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "public_subnet_cidrs" {
  description = "퍼블릭 서브넷 CIDR 블록 (ALB용 최소 2개 필요)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "프라이빗 서브넷 CIDR 블록 (2개 AZ에 배포하되, 실제 리소스는 비용 절감을 위해 최소화)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

# ECS 설정
variable "container_image" {
  description = "채팅 애플리케이션용 Docker 이미지"
  type        = string
  default     = "nginx:latest" # 실제 채팅 앱 이미지로 변경 필요
}

variable "container_port" {
  description = "컨테이너 포트"
  type        = number
  default     = 3000
}

variable "fargate_cpu" {
  description = "Fargate CPU 유닛"
  type        = number
  default     = 256
}

variable "fargate_memory" {
  description = "Fargate 메모리 (MB)"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Fargate 태스크 희망 개수 (해커톤/개발 환경에서는 1로 설정하여 비용 절감)"
  type        = number
  default     = 1
}

# ECR 설정
variable "ecr_image_tag_mutability" {
  description = "ECR 이미지 태그 변경 가능 여부 (MUTABLE 또는 IMMUTABLE)"
  type        = string
  default     = "MUTABLE"
}

variable "ecr_scan_on_push" {
  description = "이미지 푸시 시 자동 보안 스캔 활성화"
  type        = bool
  default     = true
}

variable "ecr_image_retention_count" {
  description = "ECR에 보관할 이미지 개수"
  type        = number
  default     = 10
}

# Blue/Green 배포 설정
variable "blue_weight" {
  description = "Blue 타겟 그룹 트래픽 가중치 (0-100)"
  type        = number
  default     = 90
}

variable "green_weight" {
  description = "Green 타겟 그룹 트래픽 가중치 (0-100)"
  type        = number
  default     = 10
}

# ElastiCache 설정
variable "redis_node_type" {
  description = "ElastiCache Redis 노드 타입"
  type        = string
  default     = "cache.t4g.micro"
}

variable "redis_num_cache_nodes" {
  description = "캐시 노드 개수 (멀티 AZ: 프라이머리 1 + 리드 리플리카 1)"
  type        = number
  default     = 2
}

variable "redis_engine_version" {
  description = "Redis 엔진 버전"
  type        = string
  default     = "7.0"
}

# DynamoDB 설정
variable "dynamodb_billing_mode" {
  description = "DynamoDB 과금 모드"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB 읽기 용량 유닛 (PROVISIONED 모드용)"
  type        = number
  default     = 5
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB 쓰기 용량 유닛 (PROVISIONED 모드용)"
  type        = number
  default     = 5
}

# CloudFront & S3 설정
variable "s3_bucket_name" {
  description = "정적 웹사이트 호스팅용 S3 버킷 이름"
  type        = string
  default     = "" # 실제 고유한 버킷 이름으로 변경 필요
}

# Slack 알림 설정
variable "slack_webhook_parameter_name" {
  description = "Slack Webhook URL이 저장된 AWS Parameter Store 경로"
  type        = string
  default     = "/chatapp/slack/webhook-url"
}

variable "enable_alb_health_notifications" {
  description = "ALB 타겟 헬스 체크 결과를 Slack으로 알림 (옵션)"
  type        = bool
  default     = false
}
