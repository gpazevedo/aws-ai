# =============================================================================
# Lambda Functions Configuration
# =============================================================================

# Lambda execution role (from bootstrap)
data "aws_iam_role" "lambda_execution" {
  name = "${var.project_name}-lambda-execution-role"
}

# Example Lambda function using container image
resource "aws_lambda_function" "api" {
  function_name = "${var.project_name}-${var.environment}-api"
  role          = data.aws_iam_role.lambda_execution.arn

  # Container image configuration
  package_type = "Image"
  # Using hierarchical tag format: api-{environment}-latest
  image_uri    = "${data.aws_ecr_repository.app.repository_url}:api-${var.environment}-latest"

  # Resource configuration
  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout
  architectures = [var.lambda_architecture]

  # Environment variables
  environment {
    variables = {
      ENVIRONMENT   = var.environment
      PROJECT_NAME  = var.project_name
      LOG_LEVEL     = var.environment == "prod" ? "INFO" : "DEBUG"
    }
  }

  # Logging configuration
  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.lambda_api.name
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-api"
    Description = "Main API Lambda function"
  }

  # Note: Image must exist in ECR before first apply
  # Build and push via GitHub Actions or manually:
  #   1. Build: cd backend && docker build --build-arg SERVICE_FOLDER=api --platform linux/arm64 -f Dockerfile.lambda -t myapp:latest .
  #   2. Push: Use GitHub Actions workflow or 'make docker-push-dev'
  lifecycle {
    ignore_changes = [
      image_uri  # Allow image updates without Terraform (managed by CI/CD)
    ]
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_api" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}-api"
  retention_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Name = "${var.project_name}-${var.environment}-api-logs"
  }
}

# Lambda Function URL (alternative to API Gateway)
resource "aws_lambda_function_url" "api" {
  function_name      = aws_lambda_function.api.function_name
  authorization_type = "NONE"  # Change to "AWS_IAM" for authentication

  cors {
    allow_credentials = true
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["*"]
    max_age          = 86400
  }
}
