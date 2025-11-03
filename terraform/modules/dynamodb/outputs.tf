output "table_name" {
  description = "DynamoDB messages table name"
  value       = aws_dynamodb_table.chat_messages.name
}

output "table_arn" {
  description = "DynamoDB messages table ARN"
  value       = aws_dynamodb_table.chat_messages.arn
}

output "all_table_arns" {
  description = "List of all DynamoDB table ARNs (for IAM policies)"
  value = [
    aws_dynamodb_table.chat_messages.arn
  ]
}
