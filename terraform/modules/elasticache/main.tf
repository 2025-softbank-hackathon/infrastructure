# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.project_name}-${var.environment}-redis-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name        = "${var.project_name}-${var.environment}-redis-subnet-group"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ElastiCache Parameter Group
resource "aws_elasticache_parameter_group" "redis" {
  name   = "${var.project_name}-${var.environment}-redis-params"
  family = "redis7"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-redis-params"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ElastiCache Replication Group (Redis) - 멀티 AZ 구성
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "${var.project_name}-${var.environment}-redis"
  replication_group_description = "Redis cluster for ${var.project_name} ${var.environment} (Multi-AZ)"
  engine                     = "redis"
  engine_version             = var.engine_version
  node_type                  = var.node_type
  num_cache_clusters         = var.num_cache_nodes  # 2 = 프라이머리 1 + 리드 리플리카 1
  port                       = 6379
  parameter_group_name       = aws_elasticache_parameter_group.redis.name
  subnet_group_name          = aws_elasticache_subnet_group.redis.name
  security_group_ids         = var.security_group_ids
  automatic_failover_enabled = var.num_cache_nodes > 1 ? true : false  # 멀티 AZ 자동 페일오버
  multi_az_enabled           = var.num_cache_nodes > 1 ? true : false  # 멀티 AZ 활성화
  at_rest_encryption_enabled = true
  transit_encryption_enabled = false # WebSocket 연결 시 성능을 위해 비활성화

  # 자동 백업 설정 (hackathon/dev: disabled for cost saving)
  snapshot_retention_limit = 0  # 0 = disabled
  maintenance_window       = "mon:05:00-mon:07:00"

  tags = {
    Name        = "${var.project_name}-${var.environment}-redis"
    Project     = var.project_name
    Environment = var.environment
    MultiAZ     = var.num_cache_nodes > 1 ? "true" : "false"
  }
}
