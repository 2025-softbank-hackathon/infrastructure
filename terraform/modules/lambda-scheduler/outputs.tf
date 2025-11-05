output "stop_function_arn" {
  description = "ARN of stop infrastructure Lambda function"
  value       = aws_lambda_function.stop_infrastructure.arn
}

output "start_function_arn" {
  description = "ARN of start infrastructure Lambda function"
  value       = aws_lambda_function.start_infrastructure.arn
}

output "stop_function_name" {
  description = "Name of stop infrastructure Lambda function"
  value       = aws_lambda_function.stop_infrastructure.function_name
}

output "start_function_name" {
  description = "Name of start infrastructure Lambda function"
  value       = aws_lambda_function.start_infrastructure.function_name
}

output "stop_schedule" {
  description = "Stop schedule (KST)"
  value       = "00:00 KST (15:00 UTC)"
}

output "start_schedule" {
  description = "Start schedule (KST)"
  value       = "08:00 KST (23:00 UTC)"
}
