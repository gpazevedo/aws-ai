# =============================================================================
# Bootstrap Infrastructure Variables
# =============================================================================
# This file defines all configuration variables for the bootstrap infrastructure.
# Users configure their setup by setting these values in terraform.tfvars
# =============================================================================

# =============================================================================
# Core Project Configuration
# =============================================================================

variable "aws_region" {
  description = "AWS region for bootstrap resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name (used for resource naming and tagging)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must consist of lowercase letters, numbers, and hyphens only, and cannot start or end with a hyphen"
  }
}

# =============================================================================
# Compute Options - Feature Flags
# =============================================================================

variable "enable_lambda" {
  description = "Create Lambda-specific resources (execution roles, ECR for container images)"
  type        = bool
  default     = true # Lambda is the default compute option
}

variable "enable_apprunner" {
  description = "Create App Runner resources (ECR repositories, App Runner IAM roles)"
  type        = bool
  default     = false
}

variable "enable_eks" {
  description = "Create EKS cluster resources (VPC, cluster, node groups, add-ons)"
  type        = bool
  default     = false
}

# =============================================================================
# Python + uv Configuration
# =============================================================================

variable "python_version" {
  description = "Python version for Lambda/containers (e.g., '3.13')"
  type        = string
  default     = "3.13"

  validation {
    condition     = can(regex("^3\\.(1[0-3]|[8-9])$", var.python_version))
    error_message = "Python version must be 3.8 through 3.13"
  }
}

variable "use_uv_builder" {
  description = "Use uv for dependency management and builds (recommended)"
  type        = bool
  default     = true
}

# =============================================================================
# Terraform State Configuration
# =============================================================================

variable "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state storage (defaults to '{project_name}-terraform-state')"
  type        = string
  default     = null

  validation {
    condition     = var.state_bucket_name == null || can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.state_bucket_name))
    error_message = "Bucket name must consist of lowercase letters, numbers, and hyphens only"
  }
}

variable "enable_state_bucket_logging" {
  description = "Enable access logging for the state bucket"
  type        = bool
  default     = false
}

variable "create_backup_bucket" {
  description = "Create a separate S3 bucket for state file backups"
  type        = bool
  default     = true
}

# =============================================================================
# ECR Configuration (conditional on apprunner OR eks OR lambda)
# =============================================================================

variable "ecr_repositories" {
  description = "List of ECR repository names to create (e.g., ['api', 'worker', 'frontend']). If empty and compute options enabled, creates one repo named after project."
  type        = list(string)
  default     = []
}

variable "ecr_image_retention_count" {
  description = "Number of images to retain in ECR repositories"
  type        = number
  default     = 10

  validation {
    condition     = var.ecr_image_retention_count >= 1 && var.ecr_image_retention_count <= 1000
    error_message = "Image retention count must be between 1 and 1000"
  }
}

variable "ecr_enable_scan_on_push" {
  description = "Enable automatic image scanning on push to ECR"
  type        = bool
  default     = true
}

# =============================================================================
# GitHub Actions Configuration
# =============================================================================

variable "github_org" {
  description = "GitHub organization or username (e.g., 'octocat' or 'your-org')"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.github_org))
    error_message = "GitHub org must contain only alphanumeric characters and hyphens"
  }
}

variable "github_repo" {
  description = "GitHub repository name (e.g., 'my-project')"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]+$", var.github_repo))
    error_message = "GitHub repo must contain only alphanumeric characters, hyphens, underscores, and dots"
  }
}

variable "enable_test_environment" {
  description = "Create IAM role for test environment (set to false if you only use dev and prod)"
  type        = bool
  default     = false
}

# =============================================================================
# EKS Configuration (if enabled)
# =============================================================================

variable "eks_cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.31"

  validation {
    condition     = can(regex("^1\\.(2[6-9]|3[0-9])$", var.eks_cluster_version))
    error_message = "EKS cluster version must be 1.26 or higher"
  }
}

variable "eks_node_instance_types" {
  description = "EC2 instance types for EKS node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "eks_node_desired_size" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 2

  validation {
    condition     = var.eks_node_desired_size >= 1
    error_message = "Desired node count must be at least 1"
  }
}

variable "eks_node_min_size" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  default     = 1

  validation {
    condition     = var.eks_node_min_size >= 1
    error_message = "Minimum node count must be at least 1"
  }
}

variable "eks_node_max_size" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 5

  validation {
    condition     = var.eks_node_max_size >= 1
    error_message = "Maximum node count must be at least 1"
  }
}

variable "eks_enable_cluster_autoscaler" {
  description = "Install Kubernetes Cluster Autoscaler for EKS"
  type        = bool
  default     = true
}

variable "eks_enable_metrics_server" {
  description = "Install Kubernetes Metrics Server for EKS"
  type        = bool
  default     = true
}

variable "eks_enable_alb_controller" {
  description = "Install AWS Load Balancer Controller for EKS"
  type        = bool
  default     = true
}

# =============================================================================
# Networking Configuration
# =============================================================================

variable "create_vpc" {
  description = "Create a VPC for compute resources (required for EKS, optional for App Runner)"
  type        = bool
  default     = null # Will auto-detect: true if EKS enabled, false otherwise
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block"
  }
}

variable "vpc_availability_zones" {
  description = "Number of availability zones to use (2 or 3 recommended for production)"
  type        = number
  default     = 2

  validation {
    condition     = var.vpc_availability_zones >= 2 && var.vpc_availability_zones <= 3
    error_message = "Must use 2 or 3 availability zones"
  }
}

# =============================================================================
# IAM Configuration
# =============================================================================

variable "use_custom_iam_policies" {
  description = "Use custom IAM policies instead of AdministratorAccess (recommended for production)"
  type        = bool
  default     = true
}

variable "max_session_duration" {
  description = "Maximum session duration for assumed roles (in seconds)"
  type        = number
  default     = 3600 # 1 hour

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "Session duration must be between 1 hour (3600) and 12 hours (43200)"
  }
}

# =============================================================================
# App Runner Configuration (if enabled)
# =============================================================================

variable "apprunner_cpu" {
  description = "CPU units for App Runner service (256 = 0.25 vCPU, 1024 = 1 vCPU, 2048 = 2 vCPU)"
  type        = number
  default     = 1024

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.apprunner_cpu)
    error_message = "CPU must be one of: 256, 512, 1024, 2048, 4096"
  }
}

variable "apprunner_memory" {
  description = "Memory in MB for App Runner service (512, 1024, 2048, 3072, 4096, etc.)"
  type        = number
  default     = 2048

  validation {
    condition     = var.apprunner_memory >= 512 && var.apprunner_memory <= 12288
    error_message = "Memory must be between 512 MB and 12288 MB (12 GB)"
  }
}

# =============================================================================
# Lambda Configuration (if enabled)
# =============================================================================

variable "lambda_architecture" {
  description = "Lambda function architecture (arm64 recommended for cost savings)"
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.lambda_architecture)
    error_message = "Architecture must be either 'x86_64' or 'arm64'"
  }
}

variable "lambda_use_container_image" {
  description = "Use container images for Lambda (more flexible than ZIP packages)"
  type        = bool
  default     = true
}

# =============================================================================
# Tags
# =============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
