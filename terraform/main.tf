# VPC Module
module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# Security Groups Module
module "security_groups" {
  source = "./modules/security-groups"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = var.vpc_cidr
}

# IAM Module
module "iam" {
  source = "./modules/iam"

  project_name         = var.project_name
  environment          = var.environment
  dynamodb_table_arn   = module.dynamodb.all_table_arns
  ecr_repository_arns  = [] # ECR 사용 시 추가
}

# DynamoDB Module
module "dynamodb" {
  source = "./modules/dynamodb"

  project_name    = var.project_name
  environment     = var.environment
  billing_mode    = var.dynamodb_billing_mode
  read_capacity   = var.dynamodb_read_capacity
  write_capacity  = var.dynamodb_write_capacity
}

# ElastiCache Redis Module
module "elasticache" {
  source = "./modules/elasticache"

  project_name        = var.project_name
  environment         = var.environment
  node_type           = var.redis_node_type
  num_cache_nodes     = var.redis_num_cache_nodes
  engine_version      = var.redis_engine_version
  subnet_ids          = module.vpc.private_subnet_ids
  security_group_ids  = [module.security_groups.redis_sg_id]
}

# ALB Module
module "alb" {
  source = "./modules/alb"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  security_group_ids = [module.security_groups.alb_sg_id]
  container_port     = var.container_port
  blue_weight        = var.blue_weight
  green_weight       = var.green_weight
}

# ECS Fargate Module
module "ecs" {
  source = "./modules/ecs"

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  security_group_ids    = [module.security_groups.ecs_sg_id]
  container_image       = var.container_image
  container_port        = var.container_port
  fargate_cpu           = var.fargate_cpu
  fargate_memory        = var.fargate_memory
  desired_count         = var.desired_count
  task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  task_role_arn         = module.iam.ecs_task_role_arn
  blue_target_group_arn = module.alb.blue_target_group_arn
  green_target_group_arn = module.alb.green_target_group_arn

  # 환경 변수
  environment_variables = {
    REDIS_HOST          = module.elasticache.redis_endpoint
    REDIS_PORT          = tostring(module.elasticache.redis_port)
    DYNAMODB_TABLE_NAME = module.dynamodb.table_name
    AWS_REGION          = var.aws_region
  }
}

# API Gateway WebSocket Module
module "api_gateway" {
  source = "./modules/api-gateway"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  security_group_ids = [module.security_groups.vpc_link_sg_id]
  alb_listener_arn   = module.alb.listener_arn
}

# CloudFront & S3 Module
module "cloudfront" {
  source = "./modules/cloudfront"

  project_name    = var.project_name
  environment     = var.environment
  s3_bucket_name  = var.s3_bucket_name != "" ? var.s3_bucket_name : "${var.project_name}-${var.environment}-static-${random_id.bucket_suffix.hex}"
}

# Random ID for S3 bucket name uniqueness
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# VPC Endpoint for DynamoDB
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  tags = {
    Name        = "${var.project_name}-${var.environment}-dynamodb-endpoint"
    Project     = var.project_name
    Environment = var.environment
  }
}
