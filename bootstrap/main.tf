# =============================================================================
# Bootstrap Infrastructure for CI/CD
# =============================================================================
# This Terraform configuration creates the foundational AWS resources needed
# for GitHub Actions CI/CD pipelines:
#   - S3 bucket for Terraform state storage
#   - OIDC provider for GitHub Actions authentication
#   - IAM roles for each environment (dev, test, prod)
#   - Optional: ECR repositories (if containers enabled)
#   - Optional: Lambda IAM roles (if Lambda enabled)
#   - Optional: App Runner IAM roles (if App Runner enabled)
#   - Optional: EKS cluster (if EKS enabled)
#   - Optional: VPC (if EKS or App Runner with VPC enabled)
#
# WARNING: This bootstrap state is stored in S3 (self-referencing).
# The S3 bucket is created on first apply, then Terraform migrates state to it.
# =============================================================================

terraform {
  required_version = ">= 1.13.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Bootstrap state is stored in S3 (self-referencing)
  # The bucket must exist before init, and will be created on first apply
  # Enable S3 native locking (Terraform 1.13+)
  # Configure via CLI flags or backend config file:
  # terraform init -backend-config="bucket=${PROJECT_NAME}-terraform-state-${ACCOUNT_ID}"
  backend "s3" {
    # Partial configuration - provide via -backend-config
    # bucket = "${project_name}-terraform-state-${account_id}"
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1" # Update if using different region
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Project       = var.project_name
        ManagedBy     = "terraform-bootstrap"
        Purpose       = "cicd-infrastructure"
        Terraform     = "true"
        PythonVersion = var.python_version
      },
      var.additional_tags
    )
  }
}

# =============================================================================
# Data Sources
# =============================================================================

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# =============================================================================
# Local Values
# =============================================================================

locals {
  # Use provided state_bucket_name or default to project_name-based naming
  state_bucket_name = var.state_bucket_name != null ? var.state_bucket_name : "${var.project_name}-terraform-state"

  # Auto-detect if VPC should be created
  create_vpc = var.create_vpc != null ? var.create_vpc : var.enable_eks

  # Determine if ECR is needed (Lambda containers, App Runner, or EKS)
  enable_ecr = var.enable_lambda && var.lambda_use_container_image || var.enable_apprunner || var.enable_eks

  # ECR repository names - use provided list or default to project name
  ecr_repo_names = length(var.ecr_repositories) > 0 ? var.ecr_repositories : (local.enable_ecr ? [var.project_name] : [])

  # Account ID for resource naming
  account_id = data.aws_caller_identity.current.account_id

  # GitHub OIDC provider ARN
  github_oidc_provider_arn = aws_iam_openid_connect_provider.github_actions.arn

  # Common tags
  common_tags = {
    Project   = var.project_name
    ManagedBy = "terraform-bootstrap"
  }
}

# =============================================================================
# S3 Bucket for Terraform State
# =============================================================================

resource "aws_s3_bucket" "terraform_state" {
  bucket = "${local.state_bucket_name}-${local.account_id}"

  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = false # Set to true after first apply
  }

  tags = {
    Name        = "Terraform State Bucket"
    Description = "Stores Terraform state files for ${var.project_name}"
  }
}

# Enable versioning for state file history and rollback capability
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Optional: Enable logging
resource "aws_s3_bucket_logging" "terraform_state" {
  count = var.enable_state_bucket_logging ? 1 : 0

  bucket = aws_s3_bucket.terraform_state.id

  target_bucket = aws_s3_bucket.terraform_state.id
  target_prefix = "logs/"
}

# Lifecycle policy to manage old versions
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    filter {} # Apply to all objects

    noncurrent_version_expiration {
      noncurrent_days = 90 # Keep 90 days of history
    }
  }

  rule {
    id     = "cleanup-incomplete-uploads"
    status = "Enabled"

    filter {} # Apply to all objects

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# =============================================================================
# GitHub Actions OIDC Provider
# =============================================================================

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  # GitHub's thumbprint (verified as of January 2025)
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
  ]

  tags = {
    Name        = "GitHub Actions OIDC Provider"
    Description = "Allows GitHub Actions to assume AWS roles"
  }
}

# =============================================================================
# Base IAM Policy - Terraform State Access
# =============================================================================
# This policy is attached to all environment roles for state file access

resource "aws_iam_policy" "terraform_state_access" {
  name        = "${var.project_name}-terraform-state-access"
  description = "Allows access to Terraform state bucket for ${var.project_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
      }
    ]
  })

  tags = local.common_tags
}

# =============================================================================
# Base IAM Policy - CloudWatch Logs
# =============================================================================

resource "aws_iam_policy" "cloudwatch_logs" {
  name        = "${var.project_name}-cloudwatch-logs"
  description = "CloudWatch Logs read access for ${var.project_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:*"
      }
    ]
  })

  tags = local.common_tags
}

# =============================================================================
# Environment-Specific IAM Roles
# =============================================================================

# Development Environment Role
resource "aws_iam_role" "github_actions_dev" {
  name                 = "${var.project_name}-github-actions-dev"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_assume_role_dev.json
  description          = "Role for GitHub Actions to deploy ${var.project_name} to dev environment"
  max_session_duration = var.max_session_duration

  tags = merge(
    local.common_tags,
    {
      Environment = "dev"
      Name        = "GitHub Actions Dev Role"
    }
  )
}

data "aws_iam_policy_document" "github_actions_assume_role_dev" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:environment:dev"]
    }
  }
}

# Attach base policies to dev role
resource "aws_iam_role_policy_attachment" "dev_terraform_state" {
  role       = aws_iam_role.github_actions_dev.name
  policy_arn = aws_iam_policy.terraform_state_access.arn
}

resource "aws_iam_role_policy_attachment" "dev_cloudwatch_logs" {
  role       = aws_iam_role.github_actions_dev.name
  policy_arn = aws_iam_policy.cloudwatch_logs.arn
}

# Test Environment Role (conditional)
resource "aws_iam_role" "github_actions_test" {
  count                = var.enable_test_environment ? 1 : 0
  name                 = "${var.project_name}-github-actions-test"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_assume_role_test[0].json
  description          = "Role for GitHub Actions to deploy ${var.project_name} to test environment"
  max_session_duration = var.max_session_duration

  tags = merge(
    local.common_tags,
    {
      Environment = "test"
      Name        = "GitHub Actions Test Role"
    }
  )
}

data "aws_iam_policy_document" "github_actions_assume_role_test" {
  count = var.enable_test_environment ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:environment:test"]
    }
  }
}

# Attach base policies to test role
resource "aws_iam_role_policy_attachment" "test_terraform_state" {
  count      = var.enable_test_environment ? 1 : 0
  role       = aws_iam_role.github_actions_test[0].name
  policy_arn = aws_iam_policy.terraform_state_access.arn
}

resource "aws_iam_role_policy_attachment" "test_cloudwatch_logs" {
  count      = var.enable_test_environment ? 1 : 0
  role       = aws_iam_role.github_actions_test[0].name
  policy_arn = aws_iam_policy.cloudwatch_logs.arn
}

# Production Environment Role
resource "aws_iam_role" "github_actions_prod" {
  name                 = "${var.project_name}-github-actions-prod"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_assume_role_prod.json
  description          = "Role for GitHub Actions to deploy ${var.project_name} to production environment"
  max_session_duration = var.max_session_duration

  tags = merge(
    local.common_tags,
    {
      Environment = "prod"
      Name        = "GitHub Actions Production Role"
    }
  )
}

data "aws_iam_policy_document" "github_actions_assume_role_prod" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:environment:production"]
    }
  }
}

# Attach base policies to prod role
resource "aws_iam_role_policy_attachment" "prod_terraform_state" {
  role       = aws_iam_role.github_actions_prod.name
  policy_arn = aws_iam_policy.terraform_state_access.arn
}

resource "aws_iam_role_policy_attachment" "prod_cloudwatch_logs" {
  role       = aws_iam_role.github_actions_prod.name
  policy_arn = aws_iam_policy.cloudwatch_logs.arn
}

# =============================================================================
# Optional: Create backup bucket for state backups
# =============================================================================

resource "aws_s3_bucket" "state_backup" {
  count  = var.create_backup_bucket ? 1 : 0
  bucket = "${var.project_name}-terraform-state-backup-${local.account_id}"

  lifecycle {
    prevent_destroy = false
  }

  tags = {
    Name        = "Terraform State Backup Bucket"
    Description = "Backup location for Terraform state files"
  }
}

resource "aws_s3_bucket_versioning" "state_backup" {
  count  = var.create_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.state_backup[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state_backup" {
  count  = var.create_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.state_backup[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state_backup" {
  count  = var.create_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.state_backup[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
