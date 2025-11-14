# =============================================================================
# Bootstrap Infrastructure Outputs
# =============================================================================
# These outputs provide information needed by application Terraform
# and GitHub Actions workflows
# =============================================================================

# =============================================================================
# AWS Account Information
# =============================================================================

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region"
  value       = var.aws_region
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

# =============================================================================
# Terraform State Bucket
# =============================================================================

output "terraform_state_bucket" {
  description = "S3 bucket name for Terraform state storage"
  value       = aws_s3_bucket.terraform_state.id
}

output "terraform_state_bucket_arn" {
  description = "ARN of the Terraform state bucket"
  value       = aws_s3_bucket.terraform_state.arn
}

output "terraform_state_bucket_region" {
  description = "Region of the Terraform state bucket"
  value       = aws_s3_bucket.terraform_state.region
}

# Backend configuration for easy copy-paste
output "terraform_backend_config" {
  description = "Terraform backend configuration (use for application terraform)"
  value = {
    bucket       = aws_s3_bucket.terraform_state.id
    region       = var.aws_region
    encrypt      = true
    use_lockfile = true
  }
}

# =============================================================================
# GitHub Actions IAM Roles
# =============================================================================

output "github_actions_role_dev_arn" {
  description = "ARN of the GitHub Actions IAM role for dev environment"
  value       = aws_iam_role.github_actions_dev.arn
}

output "github_actions_role_test_arn" {
  description = "ARN of the GitHub Actions IAM role for test environment"
  value       = var.enable_test_environment ? aws_iam_role.github_actions_test[0].arn : null
}

output "github_actions_role_prod_arn" {
  description = "ARN of the GitHub Actions IAM role for prod environment"
  value       = aws_iam_role.github_actions_prod.arn
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider"
  value       = aws_iam_openid_connect_provider.github_actions.arn
}

# =============================================================================
# ECR Repositories
# =============================================================================

output "ecr_repositories" {
  description = "Map of ECR repository names to URLs"
  value = local.enable_ecr ? {
    for name, repo in aws_ecr_repository.app : name => repo.repository_url
  } : {}
}

output "ecr_repository_arns" {
  description = "Map of ECR repository names to ARNs"
  value = local.enable_ecr ? {
    for name, repo in aws_ecr_repository.app : name => repo.arn
  } : {}
}

# =============================================================================
# Lambda Resources
# =============================================================================

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = var.enable_lambda ? aws_iam_role.lambda_execution[0].arn : null
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = var.enable_lambda ? aws_iam_role.lambda_execution[0].name : null
}

# =============================================================================
# App Runner Resources
# =============================================================================

output "apprunner_access_role_arn" {
  description = "ARN of the App Runner access role (for ECR pull)"
  value       = var.enable_apprunner ? aws_iam_role.apprunner_access[0].arn : null
}

output "apprunner_instance_role_arn" {
  description = "ARN of the App Runner instance role (for service execution)"
  value       = var.enable_apprunner ? aws_iam_role.apprunner_instance[0].arn : null
}

# =============================================================================
# EKS Resources
# =============================================================================

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = var.enable_eks ? aws_eks_cluster.main[0].name : null
}

output "eks_cluster_endpoint" {
  description = "Endpoint of the EKS cluster"
  value       = var.enable_eks ? aws_eks_cluster.main[0].endpoint : null
}

output "eks_cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = var.enable_eks ? aws_eks_cluster.main[0].arn : null
}

output "eks_cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = var.enable_eks ? aws_eks_cluster.main[0].version : null
}

output "eks_cluster_certificate_authority_data" {
  description = "Certificate authority data for the EKS cluster"
  value       = var.enable_eks ? aws_eks_cluster.main[0].certificate_authority[0].data : null
  sensitive   = true
}

output "eks_node_group_id" {
  description = "ID of the EKS node group"
  value       = var.enable_eks ? aws_eks_node_group.main[0].id : null
}

# =============================================================================
# VPC Resources
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = local.create_vpc ? aws_vpc.main[0].id : null
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = local.create_vpc ? aws_vpc.main[0].cidr_block : null
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = local.create_vpc ? aws_subnet.public[*].id : []
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = local.create_vpc ? aws_subnet.private[*].id : []
}

output "default_security_group_id" {
  description = "ID of the default security group"
  value       = local.create_vpc ? aws_security_group.default[0].id : null
}

# =============================================================================
# Summary Output
# =============================================================================

output "summary" {
  description = "Summary of created resources"
  value = {
    project_name           = var.project_name
    aws_account_id         = local.account_id
    aws_region             = var.aws_region
    terraform_state_bucket = aws_s3_bucket.terraform_state.id

    enabled_features = {
      lambda    = var.enable_lambda
      apprunner = var.enable_apprunner
      eks       = var.enable_eks
      vpc       = local.create_vpc
      ecr       = local.enable_ecr
      test_env  = var.enable_test_environment
    }

    github_actions_roles = {
      dev  = aws_iam_role.github_actions_dev.arn
      test = var.enable_test_environment ? aws_iam_role.github_actions_test[0].arn : "not_created"
      prod = aws_iam_role.github_actions_prod.arn
    }
  }
}

# =============================================================================
# Next Steps
# =============================================================================

output "next_steps" {
  description = "Next steps after bootstrap"
  value       = <<-EOT

  Bootstrap completed successfully! Next steps:

  1. Generate application Terraform backend configs:
     ./scripts/setup-terraform-backend.sh

  2. Configure GitHub repository secrets:
     - AWS_ACCOUNT_ID: ${local.account_id}
     - AWS_REGION: ${var.aws_region}

  3. Configure GitHub repository variables:
     - PROJECT_NAME: ${var.project_name}
     - TERRAFORM_STATE_BUCKET: ${aws_s3_bucket.terraform_state.id}

  4. Set up GitHub environments (dev, ${var.enable_test_environment ? "test, " : ""}prod) and add role ARNs:
     - Dev: ${aws_iam_role.github_actions_dev.arn}
     ${var.enable_test_environment ? "- Test: ${aws_iam_role.github_actions_test[0].arn}" : ""}
     - Prod: ${aws_iam_role.github_actions_prod.arn}

  5. Initialize application Terraform:
     cd terraform/
     terraform init -backend-config=environments/dev-backend.hcl

  6. Deploy application infrastructure:
     make app-plan-dev
     make app-apply-dev

  Enabled features:
  - Lambda: ${var.enable_lambda}
  - App Runner: ${var.enable_apprunner}
  - EKS: ${var.enable_eks}
  - ECR: ${local.enable_ecr}
  - VPC: ${local.create_vpc}

  EOT
}
