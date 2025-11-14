# =============================================================================
# App Runner Resources
# =============================================================================
# Creates App Runner-specific IAM roles and policies
# Enabled when: enable_apprunner = true
# =============================================================================

# =============================================================================
# App Runner Access Role (ECR Pull)
# =============================================================================
# This role allows App Runner to pull container images from ECR

resource "aws_iam_role" "apprunner_access" {
  count = var.enable_apprunner ? 1 : 0

  name        = "${var.project_name}-apprunner-access"
  description = "Allows App Runner to pull images from ECR for ${var.project_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "build.apprunner.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# Attach AWS managed ECR read-only policy
resource "aws_iam_role_policy_attachment" "apprunner_ecr_access" {
  count = var.enable_apprunner ? 1 : 0

  role       = aws_iam_role.apprunner_access[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}

# =============================================================================
# App Runner Instance Role (Service Execution)
# =============================================================================
# This role is assumed by the App Runner service for application runtime

resource "aws_iam_role" "apprunner_instance" {
  count = var.enable_apprunner ? 1 : 0

  name        = "${var.project_name}-apprunner-instance"
  description = "Instance role for ${var.project_name} App Runner services"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "tasks.apprunner.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# CloudWatch Logs access for App Runner
resource "aws_iam_role_policy" "apprunner_logs" {
  count = var.enable_apprunner ? 1 : 0

  name = "${var.project_name}-apprunner-logs"
  role = aws_iam_role.apprunner_instance[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/apprunner/${var.project_name}-*:*"
      }
    ]
  })
}

# =============================================================================
# App Runner Deployment Policy for GitHub Actions
# =============================================================================

resource "aws_iam_policy" "apprunner_deploy" {
  count = var.enable_apprunner ? 1 : 0

  name        = "${var.project_name}-apprunner-deploy"
  description = "Allows GitHub Actions to deploy App Runner services for ${var.project_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # App Runner service management
      {
        Effect = "Allow"
        Action = [
          "apprunner:CreateService",
          "apprunner:DeleteService",
          "apprunner:DescribeService",
          "apprunner:ListServices",
          "apprunner:UpdateService",
          "apprunner:PauseService",
          "apprunner:ResumeService",
          "apprunner:StartDeployment",
          "apprunner:TagResource",
          "apprunner:UntagResource",
          "apprunner:ListTagsForResource"
        ]
        Resource = "arn:aws:apprunner:${var.aws_region}:${local.account_id}:service/${var.project_name}-*/*"
      },
      # App Runner operations (list all)
      {
        Effect = "Allow"
        Action = [
          "apprunner:ListOperations"
        ]
        Resource = "*"
      },
      # Auto-scaling configuration
      {
        Effect = "Allow"
        Action = [
          "apprunner:CreateAutoScalingConfiguration",
          "apprunner:DeleteAutoScalingConfiguration",
          "apprunner:DescribeAutoScalingConfiguration",
          "apprunner:ListAutoScalingConfigurations"
        ]
        Resource = "arn:aws:apprunner:${var.aws_region}:${local.account_id}:autoscalingconfiguration/${var.project_name}-*/*/*"
      },
      # VPC connector (if using VPC)
      {
        Effect = "Allow"
        Action = [
          "apprunner:CreateVpcConnector",
          "apprunner:DeleteVpcConnector",
          "apprunner:DescribeVpcConnector",
          "apprunner:ListVpcConnectors"
        ]
        Resource = "arn:aws:apprunner:${var.aws_region}:${local.account_id}:vpcconnector/${var.project_name}-*/*"
      },
      # IAM role passing (required for App Runner creation)
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          var.enable_apprunner ? aws_iam_role.apprunner_access[0].arn : "*",
          var.enable_apprunner ? aws_iam_role.apprunner_instance[0].arn : "*"
        ]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = [
              "build.apprunner.amazonaws.com",
              "tasks.apprunner.amazonaws.com"
            ]
          }
        }
      },
      # EC2 permissions for VPC connector
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach App Runner deployment policy to dev role
resource "aws_iam_role_policy_attachment" "dev_apprunner_deploy" {
  count = var.enable_apprunner ? 1 : 0

  role       = aws_iam_role.github_actions_dev.name
  policy_arn = aws_iam_policy.apprunner_deploy[0].arn
}

# Attach App Runner deployment policy to test role
resource "aws_iam_role_policy_attachment" "test_apprunner_deploy" {
  count = var.enable_apprunner && var.enable_test_environment ? 1 : 0

  role       = aws_iam_role.github_actions_test[0].name
  policy_arn = aws_iam_policy.apprunner_deploy[0].arn
}

# Attach App Runner deployment policy to prod role
resource "aws_iam_role_policy_attachment" "prod_apprunner_deploy" {
  count = var.enable_apprunner ? 1 : 0

  role       = aws_iam_role.github_actions_prod.name
  policy_arn = aws_iam_policy.apprunner_deploy[0].arn
}
