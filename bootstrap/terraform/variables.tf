# =============================================================================
# Application Infrastructure - Variables
# =============================================================================

variable "project_name" {
  description = "Project name (must match bootstrap configuration)"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (org/repo)"
  type        = string
}

variable "ecr_repository_name" {
  description = "ECR repository name for Lambda container images"
  type        = string
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "lambda_architecture" {
  description = "Lambda function architecture (x86_64 or arm64)"
  type        = string
  default     = "arm64"
}

variable "enable_api_gateway" {
  description = "Enable API Gateway for Lambda functions"
  type        = bool
  default     = true
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
