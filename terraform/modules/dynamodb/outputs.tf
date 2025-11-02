output "table_name" {
  description = "DynamoDB messages table name"
  value       = aws_dynamodb_table.chat_messages.name
}

output "table_arn" {
  description = "DynamoDB messages table ARN"
  value       = aws_dynamodb_table.chat_messages.arn
}

output "connections_table_name" {
  description = "DynamoDB connections table name"
  value       = aws_dynamodb_table.connections.name
}

output "connections_table_arn" {
  description = "DynamoDB connections table ARN"
  value       = aws_dynamodb_table.connections.arn
}

output "user_counter_table_name" {
  description = "DynamoDB user counter table name"
  value       = aws_dynamodb_table.user_counter.name
}

output "user_counter_table_arn" {
  description = "DynamoDB user counter table ARN"
  value       = aws_dynamodb_table.user_counter.arn
}

output "all_table_arns" {
  description = "List of all DynamoDB table ARNs"
  value = [
    aws_dynamodb_table.chat_messages.arn,
    aws_dynamodb_table.connections.arn,
    aws_dynamodb_table.user_counter.arn
  ]
}
