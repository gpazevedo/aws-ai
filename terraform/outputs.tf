# =============================================================================
# Application Infrastructure - Outputs
# =============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.api.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.api.arn
}

output "lambda_function_url" {
  description = "Lambda Function URL endpoint"
  value       = aws_lambda_function_url.api.function_url
}

output "api_gateway_url" {
  description = "API Gateway endpoint URL"
  value       = var.enable_api_gateway ? aws_api_gateway_stage.api[0].invoke_url : "Not enabled"
}

output "cloudwatch_log_group" {
  description = "CloudWatch Log Group name for Lambda"
  value       = aws_cloudwatch_log_group.lambda_api.name
}

output "ecr_repository_url" {
  description = "ECR repository URL for container images"
  value       = data.aws_ecr_repository.app.repository_url
}

output "environment" {
  description = "Current environment"
  value       = var.environment
}
