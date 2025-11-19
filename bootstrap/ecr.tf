# =============================================================================
# ECR (Elastic Container Registry) Resources
# =============================================================================
# Creates ECR repositories for container images
# Enabled when: Lambda with containers, App Runner, or EKS
# =============================================================================

# =============================================================================
# ECR Repositories
# =============================================================================

resource "aws_ecr_repository" "app" {
  for_each = toset(local.ecr_repo_names)

  # Avoid duplication: if each.key is already project_name, don't add prefix
  name                 = each.key == var.project_name ? var.project_name : "${var.project_name}-${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = var.ecr_enable_scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(
    local.common_tags,
    {
      Name       = each.key == var.project_name ? var.project_name : "${var.project_name}-${each.key}"
      Repository = each.key
    }
  )
}

# =============================================================================
# ECR Lifecycle Policies
# =============================================================================
# Automatically clean up old images to save costs

resource "aws_ecr_lifecycle_policy" "app" {
  for_each = toset(local.ecr_repo_names)

  repository = aws_ecr_repository.app[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.ecr_image_retention_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.ecr_image_retention_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# =============================================================================
# ECR IAM Policy for GitHub Actions
# =============================================================================

resource "aws_iam_policy" "ecr_push_pull" {
  count = local.enable_ecr ? 1 : 0

  name        = "${var.project_name}-ecr-push-pull"
  description = "Allows GitHub Actions to push and pull images from ECR for ${var.project_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:DeleteImage"
        ]
        Resource = [
          for repo in aws_ecr_repository.app : repo.arn
        ]
      }
    ]
  })

  tags = local.common_tags
}

# Attach ECR policy to dev role
resource "aws_iam_role_policy_attachment" "dev_ecr" {
  count = local.enable_ecr ? 1 : 0

  role       = aws_iam_role.github_actions_dev.name
  policy_arn = aws_iam_policy.ecr_push_pull[0].arn
}

# Attach ECR policy to test role
resource "aws_iam_role_policy_attachment" "test_ecr" {
  count = local.enable_ecr && var.enable_test_environment ? 1 : 0

  role       = aws_iam_role.github_actions_test[0].name
  policy_arn = aws_iam_policy.ecr_push_pull[0].arn
}

# Attach ECR policy to prod role
resource "aws_iam_role_policy_attachment" "prod_ecr" {
  count = local.enable_ecr ? 1 : 0

  role       = aws_iam_role.github_actions_prod.name
  policy_arn = aws_iam_policy.ecr_push_pull[0].arn
}
