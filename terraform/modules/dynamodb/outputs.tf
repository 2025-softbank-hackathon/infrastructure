output "table_name" {
  description = "DynamoDB messages table name"
  value       = aws_dynamodb_table.chat_messages.name
}

output "table_arn" {
  description = "DynamoDB messages table ARN"
  value       = aws_dynamodb_table.chat_messages.arn
}
