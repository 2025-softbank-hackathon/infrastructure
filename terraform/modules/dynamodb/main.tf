# DynamoDB Table for Chat Messages
resource "aws_dynamodb_table" "chat_messages" {
  name           = "${var.project_name}-${var.environment}-messages"
  billing_mode   = var.billing_mode
  read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
  write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null
  hash_key       = "roomId"
  range_key      = "timestamp"

  attribute {
    name = "roomId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  attribute {
    name = "userId"
    type = "S"
  }

  # GSI for querying messages by user
  global_secondary_index {
    name            = "userId-timestamp-index"
    hash_key        = "userId"
    range_key       = "timestamp"
    projection_type = "ALL"
    read_capacity   = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
    write_capacity  = var.billing_mode == "PROVISIONED" ? var.write_capacity : null
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-messages"
    Project     = var.project_name
    Environment = var.environment
  }
}

# DynamoDB Table for WebSocket Connections
resource "aws_dynamodb_table" "connections" {
  name           = "${var.project_name}-${var.environment}-connections"
  billing_mode   = var.billing_mode
  read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
  write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null
  hash_key       = "connectionId"

  attribute {
    name = "connectionId"
    type = "S"
  }

  attribute {
    name = "userId"
    type = "S"
  }

  # GSI for querying connections by user
  global_secondary_index {
    name            = "userId-index"
    hash_key        = "userId"
    projection_type = "ALL"
    read_capacity   = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
    write_capacity  = var.billing_mode == "PROVISIONED" ? var.write_capacity : null
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-connections"
    Project     = var.project_name
    Environment = var.environment
  }
}

# DynamoDB Table for User Counter (auto-increment user IDs)
resource "aws_dynamodb_table" "user_counter" {
  name           = "${var.project_name}-${var.environment}-user-counter"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "counterId"

  attribute {
    name = "counterId"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-user-counter"
    Project     = var.project_name
    Environment = var.environment
  }
}
