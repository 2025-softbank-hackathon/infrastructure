# S3 버킷 for ALB 액세스 로그
resource "aws_s3_bucket" "alb_logs" {
  bucket = "${var.project_name}-${var.environment}-alb-logs-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "${var.project_name}-${var.environment}-alb-logs"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 버킷 소유권 설정
resource "aws_s3_bucket_ownership_controls" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# S3 버킷 ACL
resource "aws_s3_bucket_acl" "alb_logs" {
  depends_on = [aws_s3_bucket_ownership_controls.alb_logs]
  bucket     = aws_s3_bucket.alb_logs.id
  acl        = "private"
}

# S3 버킷 정책 for ALB 액세스 로그
resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::600734575887:root"  # ap-northeast-2 ELB 서비스 계정
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/*"
      }
    ]
  })
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = var.security_group_ids
  subnets            = var.public_subnet_ids

  enable_deletion_protection       = false
  enable_http2                     = true
  enable_cross_zone_load_balancing = true

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    enabled = true
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-alb"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Blue Target Group (90% traffic)
resource "aws_lb_target_group" "blue" {
  name        = "${var.project_name}-${var.environment}-blue-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = {
    Name        = "${var.project_name}-${var.environment}-blue-tg"
    Project     = var.project_name
    Environment = var.environment
    Color       = "Blue"
  }
}

# Green Target Group (10% traffic)
resource "aws_lb_target_group" "green" {
  name        = "${var.project_name}-${var.environment}-green-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = {
    Name        = "${var.project_name}-${var.environment}-green-tg"
    Project     = var.project_name
    Environment = var.environment
    Color       = "Green"
  }
}

# ALB Listener (HTTP)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.blue.arn
        weight = var.blue_weight
      }

      target_group {
        arn    = aws_lb_target_group.green.arn
        weight = var.green_weight
      }

      stickiness {
        enabled  = true
        duration = 3600
      }
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-http-listener"
    Project     = var.project_name
    Environment = var.environment
  }
}

# 추가 리스너 규칙 (필요 시)
# WebSocket 업그레이드를 위한 규칙
resource "aws_lb_listener_rule" "websocket" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.blue.arn
        weight = var.blue_weight
      }

      target_group {
        arn    = aws_lb_target_group.green.arn
        weight = var.green_weight
      }

      stickiness {
        enabled  = true
        duration = 3600
      }
    }
  }

  condition {
    http_header {
      http_header_name = "Upgrade"
      values           = ["websocket"]
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-websocket-rule"
    Project     = var.project_name
    Environment = var.environment
  }
}
