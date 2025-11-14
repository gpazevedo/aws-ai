# =============================================================================
# Lambda Resources
# =============================================================================
# Creates Lambda-specific IAM roles and policies
# Enabled when: enable_lambda = true
# =============================================================================

# =============================================================================
# Lambda Execution Role (Base Template)
# =============================================================================
# This is a base execution role that can be used by Lambda functions
# Individual functions may need additional permissions

resource "aws_iam_role" "lambda_execution" {
  count = var.enable_lambda ? 1 : 0

  name        = "${var.project_name}-lambda-execution"
  description = "Base execution role for ${var.project_name} Lambda functions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  count = var.enable_lambda ? 1 : 0

  role       = aws_iam_role.lambda_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# =============================================================================
# Lambda Deployment Policy for GitHub Actions
# =============================================================================

resource "aws_iam_policy" "lambda_deploy" {
  count = var.enable_lambda ? 1 : 0

  name        = "${var.project_name}-lambda-deploy"
  description = "Allows GitHub Actions to deploy Lambda functions for ${var.project_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Lambda function management
      {
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:DeleteFunction",
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:ListFunctions",
          "lambda:ListVersionsByFunction",
          "lambda:PublishVersion",
          "lambda:CreateAlias",
          "lambda:DeleteAlias",
          "lambda:GetAlias",
          "lambda:UpdateAlias",
          "lambda:ListAliases",
          "lambda:InvokeFunction",
          "lambda:TagResource",
          "lambda:UntagResource",
          "lambda:ListTags"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${local.account_id}:function:${var.project_name}-*"
      },
      # Lambda layer management
      {
        Effect = "Allow"
        Action = [
          "lambda:PublishLayerVersion",
          "lambda:DeleteLayerVersion",
          "lambda:GetLayerVersion",
          "lambda:ListLayers",
          "lambda:ListLayerVersions"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${local.account_id}:layer:${var.project_name}-*"
      },
      # IAM role passing (required for Lambda creation)
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = var.enable_lambda ? aws_iam_role.lambda_execution[0].arn : "*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "lambda.amazonaws.com"
          }
        }
      },
      # CloudWatch Logs for Lambda
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy",
          "logs:TagLogGroup"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-*"
      },
      # API Gateway integration (if needed)
      {
        Effect = "Allow"
        Action = [
          "apigateway:GET",
          "apigateway:POST",
          "apigateway:PUT",
          "apigateway:DELETE",
          "apigateway:PATCH"
        ]
        Resource = "arn:aws:apigateway:${var.aws_region}::/restapis/*"
      },
      # Lambda function URLs (if needed)
      {
        Effect = "Allow"
        Action = [
          "lambda:CreateFunctionUrlConfig",
          "lambda:DeleteFunctionUrlConfig",
          "lambda:GetFunctionUrlConfig",
          "lambda:UpdateFunctionUrlConfig",
          "lambda:AddPermission",
          "lambda:RemovePermission",
          "lambda:GetPolicy"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${local.account_id}:function:${var.project_name}-*"
      },
      # EventBridge/CloudWatch Events (if needed for triggers)
      {
        Effect = "Allow"
        Action = [
          "events:PutRule",
          "events:DeleteRule",
          "events:DescribeRule",
          "events:EnableRule",
          "events:DisableRule",
          "events:PutTargets",
          "events:RemoveTargets",
          "events:ListTargetsByRule"
        ]
        Resource = "arn:aws:events:${var.aws_region}:${local.account_id}:rule/${var.project_name}-*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach Lambda deployment policy to dev role
resource "aws_iam_role_policy_attachment" "dev_lambda_deploy" {
  count = var.enable_lambda ? 1 : 0

  role       = aws_iam_role.github_actions_dev.name
  policy_arn = aws_iam_policy.lambda_deploy[0].arn
}

# Attach Lambda deployment policy to test role
resource "aws_iam_role_policy_attachment" "test_lambda_deploy" {
  count = var.enable_lambda && var.enable_test_environment ? 1 : 0

  role       = aws_iam_role.github_actions_test[0].name
  policy_arn = aws_iam_policy.lambda_deploy[0].arn
}

# Attach Lambda deployment policy to prod role
resource "aws_iam_role_policy_attachment" "prod_lambda_deploy" {
  count = var.enable_lambda ? 1 : 0

  role       = aws_iam_role.github_actions_prod.name
  policy_arn = aws_iam_policy.lambda_deploy[0].arn
}

# =============================================================================
# Lambda Health Check Policy
# =============================================================================
# Read-only access for health checks and monitoring

resource "aws_iam_policy" "lambda_health" {
  count = var.enable_lambda ? 1 : 0

  name        = "${var.project_name}-lambda-health"
  description = "Read-only access for Lambda health checks for ${var.project_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:ListFunctions",
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${local.account_id}:function:${var.project_name}-*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach health check policy to all roles
resource "aws_iam_role_policy_attachment" "dev_lambda_health" {
  count = var.enable_lambda ? 1 : 0

  role       = aws_iam_role.github_actions_dev.name
  policy_arn = aws_iam_policy.lambda_health[0].arn
}

resource "aws_iam_role_policy_attachment" "test_lambda_health" {
  count = var.enable_lambda && var.enable_test_environment ? 1 : 0

  role       = aws_iam_role.github_actions_test[0].name
  policy_arn = aws_iam_policy.lambda_health[0].arn
}

resource "aws_iam_role_policy_attachment" "prod_lambda_health" {
  count = var.enable_lambda ? 1 : 0

  role       = aws_iam_role.github_actions_prod.name
  policy_arn = aws_iam_policy.lambda_health[0].arn
}
