# Terraform Bootstrap Infrastructure

## Overview

The **bootstrap infrastructure** is the foundational layer that enables your AWS cloud applications. It creates the essential resources needed for infrastructure-as-code (IaC) management, CI/CD pipelines, and application deployment.

This bootstrap is designed to be **run once per AWS account/environment** and provides the base layer for all subsequent application infrastructure.

---

## 🎯 What Does the Bootstrap Create?

### Core Infrastructure (Always Created)

1. **S3 State Bucket**
   - Stores Terraform state files
   - Versioning enabled (rollback capability)
   - Encryption at rest (AES-256)
   - Public access blocked
   - Lifecycle policies for old versions

2. **GitHub OIDC Provider**
   - Enables credential-less authentication from GitHub Actions
   - No need to store AWS access keys in GitHub secrets
   - Fine-grained permissions per repository/branch

3. **IAM Roles for GitHub Actions**
   - Separate roles for each compute option (Lambda, App Runner, EKS)
   - Least-privilege permissions
   - Deployment and health check policies

### Optional Components (Feature Flags)

4. **ECR Repositories** (when `enable_ecr = true` or any container-based compute is enabled)
   - Stores Docker images for your applications
   - Lifecycle policies (retain last N images, remove old images)
   - Scan on push for vulnerabilities
   - Separate repositories per service

5. **Lambda Resources** (when `enable_lambda = true`)
   - Lambda execution role
   - CloudWatch Logs permissions
   - X-Ray tracing (optional)
   - VPC access (optional)
   - GitHub Actions deployment permissions

6. **App Runner Resources** (when `enable_apprunner = true`)
   - App Runner access role (ECR image pull)
   - App Runner instance role (service execution)
   - GitHub Actions deployment permissions
   - VPC connector (optional)

7. **EKS Cluster** (when `enable_eks = true`)
   - Complete EKS cluster with managed node groups
   - Cluster IAM role and policies
   - Node group IAM role and policies
   - EKS add-ons (CoreDNS, kube-proxy, VPC CNI)
   - OIDC provider for service accounts
   - GitHub Actions deployment permissions

8. **VPC Network** (when `enable_vpc = true`)
   - VPC with configurable CIDR
   - Public and private subnets across availability zones
   - NAT Gateways for private subnet internet access
   - Internet Gateway for public subnets
   - Route tables and security groups
   - VPC Flow Logs (optional)

---

## 📋 Architecture Diagram

```
┌────────────────────────────────────────────────────────────────┐
│                         AWS Account                            │
│                                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                 Bootstrap Infrastructure                │   │
│  │                                                         │   │
│  │  ┌──────────────┐      ┌─────────────────┐              │   │
│  │  │  S3 Bucket   │      │  GitHub OIDC    │              │   │
│  │  │              │      │  Provider       │              │   │
│  │  │ Terraform    │      │                 │              │   │
│  │  │ State Store  │      │  Trust: GitHub  │              │   │
│  │  └──────────────┘      └─────────────────┘              │   │
│  │                                                         │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │          IAM Roles (GitHub Actions)              │   │   │
│  │  │  • Lambda Deployment Role                        │   │   │
│  │  │  • App Runner Deployment Role                    │   │   │
│  │  │  • EKS Deployment Role                           │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  │                                                         │   │
│  │  ┌──────────────┐      ┌─────────────────┐              │   │
│  │  │ ECR Registry │      │  VPC Network    │              │   │
│  │  │              │      │                 │              │   │
│  │  │ Docker       │      │  Public/Private │              │   │
│  │  │ Images       │      │  Subnets        │              │   │
│  │  └──────────────┘      └─────────────────┘              │   │
│  │                                                         │   │
│  │  ┌─────────────────────────────────────────┐            │   │
│  │  │   Compute Resources (Optional)          │            │   │
│  │  │                                         │            │   │
│  │  │  • Lambda: Execution Role               │            │   │
│  │  │  • App Runner: Access + Instance Roles  │            │   │
│  │  │  • EKS: Cluster + Node Groups           │            │   │
│  │  └─────────────────────────────────────────┘            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Application Infrastructure                 │   │
│  │              (Deployed using bootstrap)                 │   │
│  │                                                         │   │
│  │  State stored in → S3 Bucket (above)                    │   │
│  │  Deployed via   → GitHub Actions + OIDC (above)         │   │
│  └─────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────┘
```

---

## 🚀 Quick Start

### Prerequisites

- **AWS Account** with admin access
- **AWS CLI** configured (`aws configure`)
- **Terraform** >= 1.13
- **uv** (for Python): `curl -LsSf https://astral.sh/uv/install.sh | sh`
- **GitHub Repository** for your project

### Deployment Steps

The bootstrap process is **fully automated** in 4 steps:

#### Step 1: Configure

```bash
# Copy and edit configuration
cp bootstrap/terraform.tfvars.example bootstrap/terraform.tfvars
vim bootstrap/terraform.tfvars
```

**Required settings:**

```hcl
project_name = "my-app"       # Your project name
github_org   = "my-org"       # GitHub org/username
github_repo  = "my-app"       # GitHub repository
aws_region   = "us-east-1"    # AWS region

# Choose your compute stack
enable_lambda    = true       # Serverless functions
enable_apprunner = false      # Web applications
enable_eks       = false      # Kubernetes cluster
```

See [Configuration Examples](#-configuration-examples) for complete scenarios.

#### Step 2: Create S3 State Bucket

```bash
# Automatically creates S3 bucket with:
# - Name: {project_name}-terraform-state-{account_id}
# - Versioning enabled (for S3 locking, no DynamoDB!)
# - AES256 encryption
# - Public access blocked
make bootstrap-create-backend
```

#### Step 3: Initialize Terraform

```bash
# Automatically:
# - Configures S3 backend
# - Imports existing S3 bucket (if created manually)
# - Imports existing OIDC provider (if exists)
make bootstrap-init
```

#### Step 4: Deploy

```bash
# Review changes
make bootstrap-plan

# Deploy infrastructure
make bootstrap-apply

# Generate backend configs for application Terraform
make setup-backend

# (Optional) Generate example application Terraform files
make setup-app-terraform

# (Optional) Sync to .env file
make sync-env
```

**What gets created:**
- ✅ S3 backend (state storage with locking)
- ✅ GitHub OIDC (passwordless CI/CD auth)
- ✅ IAM roles (per environment: dev, test, prod)
- ✅ ECR repositories (if using containers)
- ✅ VPC/EKS (if enabled)

### Post-Deployment: Configure GitHub

After bootstrap completes, add these to your GitHub repository:

**Secrets:**
- `AWS_ACCOUNT_ID` - Your AWS account ID
- `AWS_REGION` - AWS region (e.g., us-east-1)

**Environment-specific secrets** (per environment: dev, test, production):
- `AWS_ROLE_ARN_DEV` - From bootstrap output
- `AWS_ROLE_ARN_TEST` - From bootstrap output (if enabled)
- `AWS_ROLE_ARN_PROD` - From bootstrap output

Get values from:
```bash
make bootstrap-output
```

### Optional: Sync to .env File

Sync terraform.tfvars to `.env` file for use in shell scripts, Docker, and applications:

```bash
# From bootstrap directory
cd ..

# Sync to .env (creates environment variables from terraform.tfvars)
make sync-env

# Or manually
uv run python scripts/sync-tfvars-to-env.py
```

This creates a `.env` file with all your configuration variables:
```bash
# .env (example)
PROJECT_NAME=my-app
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=123456789012
ENABLE_LAMBDA=true
# ... etc
```

**Use cases:**
- Source in shell scripts: `source .env && echo $PROJECT_NAME`
- Docker Compose: `docker-compose --env-file .env up`
- GitHub Actions: Load variables from .env
- Application configuration

See [Scripts Documentation](SCRIPTS.md#5-sync-tfvars-to-envpy) for details.

---

## 🏗️ Setting Up Application Infrastructure

After completing the bootstrap, you need to create your **application infrastructure** (Lambda functions, API Gateway, databases, etc.). The bootstrap provides the foundation, but your application resources are managed separately in the `terraform/` directory.

### Quick Start: Generate Example Lambda Application

For a quick start with Lambda-based applications, use the built-in generator:

```bash
# Generate example Terraform files for Lambda deployment
make setup-app-terraform
```

**This creates:**
- `terraform/main.tf` - Main configuration and AWS provider
- `terraform/variables.tf` - Variable definitions
- `terraform/lambda.tf` - Lambda function with container image
- `terraform/api-gateway.tf` - Optional API Gateway configuration
- `terraform/outputs.tf` - Output values (URLs, ARNs, etc.)
- `terraform/environments/dev.tfvars` - Dev environment variables
- `terraform/environments/test.tfvars` - Test environment variables
- `terraform/environments/prod.tfvars` - Prod environment variables
- `terraform/README.md` - Documentation

**Features of the generated configuration:**
- Lambda functions using container images from ECR
- Lambda Function URLs enabled (no API Gateway needed)
- CloudWatch Logs with JSON formatting
- Environment-specific configurations
- Lifecycle rules for CI/CD compatibility

### Deploying Your Application

⚠️ **IMPORTANT: All AWS deployments must be done through GitHub Actions.**

**Recommended deployment workflow:**

```bash
# 1. Generate GitHub Actions workflows
make setup-workflows

# 2. Configure GitHub repository secrets (from bootstrap outputs)
make bootstrap-output  # Get role ARNs and configuration

# Add to GitHub repository secrets:
# - AWS_ACCOUNT_ID
# - AWS_REGION
# - AWS_ROLE_ARN_DEV (in dev environment)
# - AWS_ROLE_ARN_PROD (in production environment)

# 3. Write your application code
vim backend/main.py

# 4. Test locally
cd backend && uv run python -c "from main import handler; print(handler({'name':'World'}, None))"

# 5. Deploy via GitHub Actions
git add .
git commit -m "feat: Add Lambda application"
git push origin main

# GitHub Actions automatically:
# - Runs tests
# - Builds arm64 Docker image
# - Pushes to ECR
# - Deploys infrastructure with Terraform
# - Runs smoke tests

# 6. Monitor deployment
# Visit: https://github.com/<your-org>/<your-repo>/actions

# 7. Deploy to production (when ready)
git tag v1.0.0
git push origin v1.0.0
```

**Why GitHub Actions only?**
- ✅ Consistent arm64 builds (no QEMU/emulation required)
- ✅ Automated testing before deployment
- ✅ Complete audit trail
- ✅ No manual AWS credential management
- ✅ Reproducible deployments

### Customizing Application Infrastructure

Edit the generated files or create your own:

**Example: Add a DynamoDB table**
```hcl
# terraform/dynamodb.tf
resource "aws_dynamodb_table" "main" {
  name           = "${var.project_name}-${var.environment}-table"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Environment = var.environment
  }
}
```

**Example: Add environment variables to Lambda**
```hcl
# In terraform/lambda.tf
resource "aws_lambda_function" "api" {
  # ... existing config ...

  environment {
    variables = {
      ENVIRONMENT   = var.environment
      TABLE_NAME    = aws_dynamodb_table.main.name  # Add this
      API_KEY       = var.api_key                    # Add this
    }
  }
}
```

**Example: Enable API Gateway**
```hcl
# In terraform/environments/dev.tfvars
enable_api_gateway = true  # Change from false to true
```

### Application Infrastructure vs Bootstrap

| Aspect | Bootstrap | Application |
|--------|-----------|-------------|
| **Purpose** | Foundation (S3, IAM, ECR) | Your app resources |
| **Location** | `bootstrap/` directory | `terraform/` directory |
| **Frequency** | Once per AWS account | Per deployment |
| **Examples** | S3 bucket, OIDC, ECR | Lambda, API Gateway, DynamoDB |
| **State** | `bootstrap/terraform.tfstate` | `environments/{env}/terraform.tfstate` |

### Common Application Patterns

**Pattern 1: REST API (Lambda + Function URL)**
```bash
make setup-app-terraform
# Edit terraform/lambda.tf to add your API logic
make app-apply-dev
```

**Pattern 2: REST API (Lambda + API Gateway)**
```bash
make setup-app-terraform
# Set enable_api_gateway = true in terraform/environments/dev.tfvars
make app-apply-dev
```

**Pattern 3: Custom Resources**
```bash
# Create your own Terraform files in terraform/
# - main.tf (provider, backend)
# - your-resources.tf (your infrastructure)
# - environments/*.tfvars (per-environment config)
make app-init-dev
make app-apply-dev
```

See [terraform/README.md](../terraform/README.md) after running `make setup-app-terraform` for detailed application infrastructure documentation.

---

## 📐 Configuration Examples

### ECR Repository Configuration

The bootstrap creates ECR (Elastic Container Registry) repositories for your container images. You can configure this in two ways:

#### Option 1: Single Repository (Default)

**Configuration:**
```hcl
# bootstrap/terraform.tfvars
ecr_repositories = []  # Empty list
```

**Result:**
- Creates one repository: `{project_name}` (e.g., `my-project`)
- All images (Lambda, EKS, App Runner) use the same repository
- Good for: Simple projects, single service

**Image tagging strategy:**
```
my-project/
├── dev-api-abc1234     # Dev Lambda
├── dev-api-latest
├── prod-api-def5678    # Prod Lambda
├── prod-api-latest
└── dev-latest
```

#### Option 2: Separate Repositories (Recommended)

**Configuration:**
```hcl
# bootstrap/terraform.tfvars
ecr_repositories = ["lambda", "eks"]
```

**Result:**
- Creates: `{project_name}-lambda` and `{project_name}-eks`
- Separate repos for Lambda and EKS/Kubernetes images
- Good for: Multiple services, different lifecycle policies

**Image tagging strategy:**
```
my-project-lambda/
├── dev-api-abc1234
├── dev-api-latest
├── dev-worker-xyz9876  # Additional Lambda
├── dev-worker-latest
└── prod-api-def5678

my-project-eks/
├── dev-api-abc1234
├── dev-frontend-xyz9876  # Frontend service
└── dev-backend-abc1234   # Backend service
```

#### Option 3: Custom Repository Names

**Configuration:**
```hcl
# bootstrap/terraform.tfvars
ecr_repositories = ["api", "worker", "frontend", "backend"]
```

**Result:**
- Creates multiple repos: `my-project-api`, `my-project-worker`, etc.
- Fine-grained control over repository lifecycle policies
- Good for: Microservices, complex architectures

#### Image Tagging Convention

The generated GitHub Actions workflows use this tagging convention:

**Format:** `{environment}-{service}-{git-sha-short}`

**Tags created for each build:**
1. **Primary tag:** `dev-api-abc1234` (environment-service-sha)
2. **Service latest:** `dev-api-latest` (latest for this service in this environment)
3. **Environment latest:** `dev-latest` (latest for this environment)

**Benefits:**
- Easy to identify deployed version
- Simple rollback with `-latest` tags
- Git SHA allows tracing back to code
- Environment prefix prevents dev/prod confusion

**Workflow Integration:**

The `generate-workflows.sh` script automatically detects your ECR configuration:
- Looks for repos with "lambda" in the name → uses for Lambda workflows
- Looks for repos with "eks" in the name → uses for EKS workflows
- Falls back to first available repo if specific names not found

**To change ECR configuration after bootstrap:**
```bash
# 1. Edit bootstrap/terraform.tfvars
vim bootstrap/terraform.tfvars
# Add: ecr_repositories = ["lambda", "eks"]

# 2. Apply changes
make bootstrap-plan   # Review
make bootstrap-apply  # Create new repos

# 3. Regenerate workflows
make setup-workflows  # Picks up new repo names
```

---

### Example 1: Lambda Only (Serverless)

**Use case:** API backends, event processors, scheduled tasks

```hcl
project_name   = "my-serverless-app"
aws_region     = "us-east-1"
aws_account_id = "123456789012"

github_org  = "my-org"
github_repo = "my-serverless-app"

# Compute
enable_lambda    = true
enable_apprunner = false
enable_eks       = false

# Lambda configuration
lambda_use_container_image = true  # Use Docker (recommended)
lambda_architecture        = "arm64"  # Graviton2 (20% cost savings)

# Networking
enable_vpc = false  # Lambda doesn't require VPC for most use cases

# Tags
tags = {
  Environment = "production"
  ManagedBy   = "terraform"
  CostCenter  = "engineering"
}
```

**Resources Created:**
- S3 state bucket
- GitHub OIDC provider
- ECR repository (for container images)
- Lambda execution role
- GitHub Actions Lambda deployment role

**Estimated Cost:** ~$5-10/month (S3 storage only, Lambda billed per use)

### Example 2: Lambda + App Runner (Hybrid)

**Use case:** Web app (App Runner) + background jobs (Lambda)

```hcl
project_name   = "my-web-app"
aws_region     = "us-east-1"
aws_account_id = "123456789012"

github_org  = "my-org"
github_repo = "my-web-app"

# Compute
enable_lambda    = true   # Background jobs
enable_apprunner = true   # Web frontend
enable_eks       = false

# Lambda configuration
lambda_use_container_image = true
lambda_architecture        = "arm64"

# App Runner configuration
apprunner_cpu    = "1024"   # 1 vCPU
apprunner_memory = "2048"   # 2 GB

# Networking
enable_vpc = false  # Neither requires VPC for basic use

# ECR
ecr_repositories = [
  "my-web-app/frontend",     # App Runner image
  "my-web-app/worker"        # Lambda background job image
]

tags = {
  Environment = "production"
  ManagedBy   = "terraform"
}
```

**Resources Created:**
- S3 state bucket
- GitHub OIDC provider
- 2 ECR repositories
- Lambda execution role
- App Runner access role (ECR pull)
- App Runner instance role (service execution)
- GitHub Actions deployment roles for both

**Estimated Cost:** ~$50-100/month (App Runner minimum + Lambda per use)

### Example 3: Complete Stack (Lambda + App Runner + EKS)

**Use case:** Microservices platform, complex applications

```hcl
project_name   = "my-platform"
aws_region     = "us-east-1"
aws_account_id = "123456789012"

github_org  = "my-org"
github_repo = "my-platform"

# Compute (all enabled)
enable_lambda    = true   # Serverless functions
enable_apprunner = true   # Simple web services
enable_eks       = true   # Microservices

# VPC (required for EKS)
enable_vpc     = true
vpc_cidr       = "10.0.0.0/16"
public_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnets = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

# EKS configuration
eks_cluster_version = "1.28"
eks_node_groups = {
  general = {
    instance_types = ["t3.medium"]
    desired_size   = 2
    min_size       = 1
    max_size       = 4
    disk_size      = 50
  }
}

# ECR
ecr_repositories = [
  "my-platform/api",
  "my-platform/web",
  "my-platform/worker",
  "my-platform/analytics"
]

tags = {
  Environment = "production"
  ManagedBy   = "terraform"
  Platform    = "kubernetes"
}
```

**Resources Created:**
- S3 state bucket
- GitHub OIDC provider
- VPC with public/private subnets, NAT gateways
- EKS cluster with managed node group
- 4 ECR repositories
- Lambda execution role
- App Runner access + instance roles
- EKS cluster + node roles
- GitHub Actions deployment roles for all

**Estimated Cost:** ~$265-340/month (EKS cluster + node groups + NAT gateways)

---

## 🔧 Important Configuration Variables

### Required Variables

| Variable | Type | Description | Example |
|----------|------|-------------|---------|
| `project_name` | string | Project identifier (used in resource names) | `"my-app"` |
| `aws_region` | string | Primary AWS region | `"us-east-1"` |
| `aws_account_id` | string | AWS account ID | `"123456789012"` |
| `github_org` | string | GitHub organization/user | `"my-org"` |
| `github_repo` | string | GitHub repository name | `"my-app"` |

### Feature Flags

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_lambda` | bool | `true` | Create Lambda resources |
| `enable_apprunner` | bool | `false` | Create App Runner resources |
| `enable_eks` | bool | `false` | Create EKS cluster |
| `enable_vpc` | bool | `false` | Create VPC (required for EKS) |

### Lambda Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `lambda_use_container_image` | bool | `true` | Use container images (vs ZIP) |
| `lambda_architecture` | string | `"arm64"` | CPU architecture (`arm64` or `x86_64`) |
| `lambda_runtime` | string | `"python3.13"` | Runtime version (if using ZIP) |

### App Runner Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `apprunner_cpu` | string | `"1024"` | CPU units (1024 = 1 vCPU) |
| `apprunner_memory` | string | `"2048"` | Memory in MB |
| `apprunner_port` | number | `8080` | Application port |

### EKS Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `eks_cluster_version` | string | `"1.28"` | Kubernetes version |
| `eks_node_groups` | map | See variables.tf | Node group configurations |

### VPC Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `vpc_cidr` | string | `"10.0.0.0/16"` | VPC CIDR block |
| `public_subnets` | list(string) | 3 subnets | Public subnet CIDRs |
| `private_subnets` | list(string) | 3 subnets | Private subnet CIDRs |

---

## 📤 Bootstrap Outputs

After applying the bootstrap, Terraform outputs critical information needed for application deployment:

### View All Outputs

```bash
terraform output
```

### Key Outputs

**State Management:**
```bash
terraform output -raw terraform_state_bucket
# Output: my-app-terraform-state

terraform output -raw backend_config
# Output: Complete backend configuration for app infrastructure
```

**GitHub Actions:**
```bash
terraform output -raw github_actions_role_arn
# Output: arn:aws:iam::123456789012:role/my-app-github-actions-lambda

terraform output -raw github_oidc_provider_arn
# Output: arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com
```

**Container Registries:**
```bash
terraform output -json ecr_repositories
# Output: Map of repository names to URLs
```

**Networking (if VPC enabled):**
```bash
terraform output -raw vpc_id
terraform output -json private_subnet_ids
terraform output -json public_subnet_ids
```

**EKS (if enabled):**
```bash
terraform output -raw eks_cluster_endpoint
terraform output -raw eks_cluster_name

# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name $(terraform output -raw eks_cluster_name)
```

### Syncing Outputs to .env

You can export Terraform outputs to a `.env` file for use in shell scripts and applications:

```bash
# Export outputs to HCL format
cd bootstrap
terraform output -json | jq -r 'to_entries | map("\(.key) = \"\(.value.value)\"") | .[]' > outputs.tfvars

# Sync to .env
cd ..
uv run python scripts/sync-tfvars-to-env.py --tfvars bootstrap/outputs.tfvars
```

Example `.env` generated from outputs:
```bash
TERRAFORM_STATE_BUCKET=my-app-terraform-state-123456789012
GITHUB_ACTIONS_ROLE_ARN=arn:aws:iam::123456789012:role/my-app-github-actions-lambda
ECR_REPOSITORY_URL=123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app
LAMBDA_EXECUTION_ROLE_ARN=arn:aws:iam::123456789012:role/my-app-lambda-execution
VPC_ID=vpc-0abcd1234
```

Use in shell scripts:
```bash
source .env
aws lambda update-function-configuration \
  --function-name my-function \
  --role $LAMBDA_EXECUTION_ROLE_ARN
```

---

## 🔄 State Management Strategy

The bootstrap uses a **two-tier state management** approach:

### Tier 1: Bootstrap State (This Layer)

- **Location:** S3 bucket created by bootstrap
- **Purpose:** Stores the bootstrap infrastructure state
- **Access:** Admin access required
- **Frequency:** Changed rarely (only when adding/removing compute options)

**Backend Configuration:**
```hcl
# Generated after first apply
terraform {
  backend "s3" {
    bucket  = "my-app-terraform-state"
    key     = "bootstrap/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
```

### Tier 2: Application State

- **Location:** Same S3 bucket, different key prefix
- **Purpose:** Stores application infrastructure state
- **Access:** Developer access via GitHub Actions
- **Frequency:** Changed frequently (application deployments)

**Backend Configuration for Apps:**
```hcl
# terraform/backend.tf (in application repo)
terraform {
  backend "s3" {
    bucket  = "my-app-terraform-state"  # From bootstrap output
    key     = "environments/prod/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
```

**State Organization:**
```
my-app-terraform-state/
├── bootstrap/
│   └── terraform.tfstate              # Bootstrap infrastructure
├── environments/
│   ├── dev/terraform.tfstate          # Dev application
│   ├── test/terraform.tfstate         # Test application
│   └── prod/terraform.tfstate         # Prod application
└── services/
    ├── api/terraform.tfstate          # API service
    └── worker/terraform.tfstate       # Worker service
```

---

## 🔐 Security Best Practices

### 1. State File Security

The S3 state bucket is configured with:
- ✅ Server-side encryption (AES-256)
- ✅ Versioning enabled (rollback capability)
- ✅ Public access blocked
- ✅ Bucket policies restrict access to authorized principals
- ✅ MFA delete (optional, recommended for production)

**Enable MFA Delete:**
```bash
aws s3api put-bucket-versioning \
  --bucket my-app-terraform-state \
  --versioning-configuration Status=Enabled,MFADelete=Enabled \
  --mfa "arn:aws:iam::123456789012:mfa/user 123456"
```

### 2. GitHub OIDC Configuration

The OIDC provider uses **least-privilege trust policies**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:my-org/my-app:*"
        }
      }
    }
  ]
}
```

**Security Features:**
- ✅ Scoped to specific repository
- ✅ No long-lived credentials
- ✅ Audit trail in CloudTrail
- ✅ Can restrict to specific branches/tags

### 3. IAM Role Permissions

Each compute option has **separate IAM roles** with minimal permissions:

**Lambda Deployment Role:**
- Update Lambda function code
- Read/write to ECR
- Read from S3 state bucket
- CloudWatch Logs (write only)

**App Runner Deployment Role:**
- Create/update App Runner services
- Read/write to ECR
- Read from S3 state bucket

**EKS Deployment Role:**
- Update EKS cluster configuration
- Manage Kubernetes resources
- Read/write to ECR

### 4. VPC Security

When VPC is enabled:
- ✅ Public subnets: Internet Gateway (for NAT, Load Balancers)
- ✅ Private subnets: NAT Gateway (outbound only)
- ✅ Network ACLs (default: allow all, can be restricted)
- ✅ Security Groups (default: least privilege)
- ✅ VPC Flow Logs (optional, recommended)

**Enable VPC Flow Logs:**
```hcl
# In terraform.tfvars
enable_vpc_flow_logs = true
```

### 5. ECR Image Scanning

ECR repositories are configured for security scanning:
- ✅ Scan on push enabled
- ✅ Vulnerability reports in ECR console
- ✅ Can block deployment of vulnerable images

---

## 🔄 Updating the Bootstrap

### Adding New Compute Options

You can add compute options **without disrupting existing resources**:

**Example: Adding EKS to existing Lambda setup**

```bash
# Edit terraform.tfvars
vim bootstrap/terraform.tfvars

# Change:
enable_eks = true
enable_vpc = true  # Required for EKS

# Review changes
terraform plan -var-file=terraform.tfvars

# Apply
terraform apply -var-file=terraform.tfvars
```

**What Changes:**
- ✅ New: EKS cluster and node groups
- ✅ New: VPC and networking
- ✅ New: EKS IAM roles
- ✅ **Unchanged:** Existing Lambda resources
- ✅ **Unchanged:** Existing ECR repositories
- ✅ **Unchanged:** S3 state bucket

See [docs/INCREMENTAL-ADOPTION.md](INCREMENTAL-ADOPTION.md) for detailed migration guides.

### Updating Terraform Providers

```bash
# Update provider versions
terraform init -upgrade

# Review changes
terraform plan -var-file=terraform.tfvars

# Apply if needed
terraform apply -var-file=terraform.tfvars
```

### Updating EKS Version

```bash
# Edit terraform.tfvars
eks_cluster_version = "1.29"  # New version

# Plan (EKS upgrades are in-place)
terraform plan -var-file=terraform.tfvars

# Apply (may take 20-30 minutes)
terraform apply -var-file=terraform.tfvars
```

---

## 🗑️ Destroying the Bootstrap

**⚠️ WARNING:** Destroying the bootstrap will delete:
- S3 state bucket (and all state files)
- All IAM roles and permissions
- ECR repositories (and all images)
- EKS cluster and node groups
- VPC and networking

**This will break all applications using this bootstrap.**

### Safe Destruction Process

1. **Destroy all application infrastructure first:**
   ```bash
   cd terraform/environments/prod
   terraform destroy

   cd terraform/environments/dev
   terraform destroy
   ```

2. **Backup state files:**
   ```bash
   aws s3 sync s3://my-app-terraform-state ./state-backup/
   ```

3. **Destroy bootstrap:**
   ```bash
   cd bootstrap
   terraform destroy -var-file=terraform.tfvars
   ```

4. **Manual cleanup** (if needed):
   - ECR images (if repositories have retention policies)
   - CloudWatch Log groups
   - S3 versioned objects

---

## 📊 Cost Breakdown

### Base Cost (Always Incurred)

| Resource | Cost | Notes |
|----------|------|-------|
| S3 State Bucket | ~$0.50/month | 1 GB storage + requests |
| GitHub OIDC | Free | No charge for OIDC provider |
| IAM Roles | Free | No charge for roles |

**Base Total:** ~$1-2/month

### Lambda Option

| Resource | Cost | Notes |
|----------|------|-------|
| ECR Storage | ~$1-5/month | Per GB image storage |
| Lambda Execution | Pay per use | Free tier: 1M requests/month |

**Lambda Total:** ~$5-20/month (depending on usage)

### App Runner Option

| Resource | Cost | Notes |
|----------|------|-------|
| ECR Storage | ~$1-5/month | Per GB image storage |
| App Runner | ~$25-50/month | 1 vCPU, 2GB RAM, minimal traffic |

**App Runner Total:** ~$30-60/month

### EKS Option

| Resource | Cost | Notes |
|----------|------|-------|
| ECR Storage | ~$1-5/month | Per GB image storage |
| EKS Cluster | $73/month | Fixed cost per cluster |
| NAT Gateway | ~$32/month | Per AZ (~$32 × 2 = $64) |
| EC2 Nodes | ~$60-150/month | t3.medium × 2 nodes |
| Data Transfer | ~$10-50/month | Outbound traffic |

**EKS Total:** ~$240-350/month

### VPC Option (without EKS)

| Resource | Cost | Notes |
|----------|------|-------|
| VPC | Free | No charge for VPC |
| NAT Gateway | ~$32/month | Per AZ |
| Data Transfer | ~$5-20/month | Through NAT |

**VPC Total:** ~$40-70/month

---

## 🔍 Troubleshooting

### Issue: State Bucket Already Exists

**Error:**
```
Error: creating Amazon S3 Bucket (my-app-terraform-state): BucketAlreadyExists
```

**Solution:**
```bash
# Option 1: Use a different bucket name
# Edit terraform.tfvars:
state_bucket_name = "my-app-terraform-state-v2"

# Option 2: Import existing bucket
terraform import aws_s3_bucket.terraform_state my-app-terraform-state
```

### Issue: OIDC Provider Already Exists

**Error:**
```
Error: creating IAM OIDC Provider: EntityAlreadyExists
```

**Solution:**
```bash
# Import existing OIDC provider
terraform import aws_iam_openid_connect_provider.github \
  arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com
```

### Issue: VPC CIDR Conflicts

**Error:**
```
Error: VPC CIDR 10.0.0.0/16 overlaps with existing VPC
```

**Solution:**
```bash
# Choose a different CIDR block
# Edit terraform.tfvars:
vpc_cidr = "10.1.0.0/16"
public_subnets = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
private_subnets = ["10.1.11.0/24", "10.1.12.0/24", "10.1.13.0/24"]
```

### Issue: EKS Node Group Fails

**Error:**
```
Error: waiting for EKS Node Group creation: ResourceNotReady
```

**Solution:**
```bash
# Check subnet tags (required for EKS)
# Must have: kubernetes.io/cluster/<cluster-name> = shared

# Verify IAM roles have correct policies
aws iam list-attached-role-policies \
  --role-name my-app-eks-node-group-role

# Check CloudWatch logs for node group
aws eks describe-nodegroup \
  --cluster-name my-app-cluster \
  --nodegroup-name general
```

### Issue: GitHub Actions Cannot Assume Role

**Error:**
```
Error: AccessDenied - User is not authorized to perform: sts:AssumeRoleWithWebIdentity
```

**Solution:**
```bash
# Verify OIDC provider thumbprint
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com

# Verify trust policy
aws iam get-role --role-name my-app-github-actions-lambda

# Check GitHub Actions workflow permissions
# Must have: id-token: write
```

---

## 📚 Related Documentation

- **[README.md](../README.md)** - Project overview and quick start
- **[INCREMENTAL-ADOPTION.md](INCREMENTAL-ADOPTION.md)** - How to start with Lambda and add EKS later
- **[PRE-COMMIT.md](PRE-COMMIT.md)** - Python code quality automation
- **[SCRIPTS.md](SCRIPTS.md)** - Automation scripts documentation

---

## 🆘 Support

### Common Commands Reference

```bash
# Initialize bootstrap
cd bootstrap
terraform init

# Plan changes
terraform plan -var-file=terraform.tfvars

# Apply changes
terraform apply -var-file=terraform.tfvars

# View outputs
terraform output

# View specific output
terraform output -raw terraform_state_bucket

# View state
terraform show

# Refresh state
terraform refresh -var-file=terraform.tfvars

# Format Terraform files
terraform fmt -recursive

# Validate configuration
terraform validate

# Destroy (careful!)
terraform destroy -var-file=terraform.tfvars
```

### Makefile Shortcuts

```bash
# Bootstrap commands
make bootstrap-init      # Initialize Terraform
make bootstrap-plan      # Review changes
make bootstrap-apply     # Apply changes
make bootstrap-destroy   # Destroy (careful!)

# View outputs
make bootstrap-outputs

# Format and validate
make format-terraform
make validate-terraform
```

---

## 🎓 Best Practices

1. **Start Small**
   - Begin with Lambda only
   - Add App Runner or EKS when needed
   - Avoid over-engineering early

2. **Use Version Control**
   - Store `terraform.tfvars` in version control (without secrets)
   - Use `.tfvars` files for different environments
   - Tag releases for rollback capability

3. **State Management**
   - Always use S3 backend for team collaboration
   - Enable versioning for rollback
   - Use separate state files per environment

4. **Security**
   - Use GitHub OIDC (no long-lived credentials)
   - Apply least-privilege IAM policies
   - Enable MFA for production accounts
   - Scan ECR images for vulnerabilities

5. **Cost Optimization**
   - Use ARM64 for Lambda (20% savings)
   - Right-size EKS node groups
   - Monitor unused resources
   - Use lifecycle policies for ECR images

6. **Monitoring**
   - Enable CloudWatch Logs
   - Set up billing alarms
   - Monitor state file changes
   - Track resource usage

---

## ✅ Checklist: Before Production

- [ ] Review all IAM policies (least privilege)
- [ ] Enable MFA delete on S3 state bucket
- [ ] Enable VPC Flow Logs (if using VPC)
- [ ] Set up CloudWatch billing alarms
- [ ] Configure ECR image scanning
- [ ] Document disaster recovery procedures
- [ ] Test GitHub Actions workflows
- [ ] Review and tag all resources
- [ ] Enable Terraform state locking
- [ ] Set up monitoring and alerting
- [ ] Review compliance requirements
- [ ] Backup state files to separate location
- [ ] Test rollback procedures

---

**Last Updated:** November 2025
**Terraform Version:** >= 1.13
**AWS Provider Version:** >= 5.0
