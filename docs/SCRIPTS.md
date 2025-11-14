# Scripts Documentation

## Overview

This project includes several automation scripts to streamline development and deployment workflows.

---

## 📜 Available Scripts

### 1. `setup-pre-commit.sh`

**Purpose**: Install and configure pre-commit hooks for automated code quality.

**Location**: `scripts/setup-pre-commit.sh`

**Usage**:
```bash
./scripts/setup-pre-commit.sh
# or
make setup-pre-commit
```

**What it does**:
1. Creates `pyproject.toml` from example if not exists
2. Installs Python dependencies with uv (Ruff, Pyright, pre-commit)
3. Installs pre-commit git hooks
4. Runs initial check on all files

**When to run**:
- Initial project setup
- After cloning the repository
- After updating `.pre-commit-config.yaml`

**See**: [docs/PRE-COMMIT.md](PRE-COMMIT.md) for complete documentation.

---

### 2. `setup-terraform-backend.sh`

**Purpose**: Auto-generates Terraform backend configuration files for application infrastructure.

**Location**: `scripts/setup-terraform-backend.sh`

**Usage**:
```bash
./scripts/setup-terraform-backend.sh
# or
make setup-backend
```

**What it does**:
1. Reads bootstrap outputs (`terraform_state_bucket`, `aws_region`)
2. Generates backend config files for each environment:
   - `terraform/environments/dev-backend.hcl`
   - `terraform/environments/test-backend.hcl`
   - `terraform/environments/prod-backend.hcl`

**Generated file example**:
```hcl
# terraform/environments/dev-backend.hcl
bucket       = "my-project-terraform-state-123456789012"
key          = "environments/dev/terraform.tfstate"
region       = "us-east-1"
encrypt      = true
use_lockfile = true
```

**When to run**:
- After initial bootstrap deployment
- After changing AWS region
- After recreating S3 state bucket

---

### 3. `setup-application-terraform.sh`

**Purpose**: Generates example Terraform configuration files for Lambda-based application infrastructure.

**Location**: `scripts/setup-application-terraform.sh`

**Usage**:
```bash
./scripts/setup-application-terraform.sh
# or
make setup-app-terraform
```

**What it does**:
1. Reads project configuration from `bootstrap/terraform.tfvars` (if available)
2. Creates `terraform/` directory structure
3. Generates complete Terraform configuration for Lambda deployment:
   - `terraform/main.tf` - Provider and backend configuration
   - `terraform/variables.tf` - Variable definitions
   - `terraform/lambda.tf` - Lambda function with container image
   - `terraform/api-gateway.tf` - Optional API Gateway setup
   - `terraform/outputs.tf` - Output values
   - `terraform/README.md` - Documentation
4. Creates environment-specific variable files:
   - `terraform/environments/dev.tfvars`
   - `terraform/environments/test.tfvars`
   - `terraform/environments/prod.tfvars`

**Generated infrastructure features**:
- Lambda function using container images from ECR
- Lambda Function URLs (no API Gateway needed by default)
- CloudWatch Logs with JSON formatting and retention policies
- Environment-specific memory/timeout configurations
- Lifecycle rules for CI/CD compatibility
- Optional API Gateway integration

**When to run**:
- After completing bootstrap setup
- When starting a new Lambda-based project
- To get example Terraform configuration for reference

**Customization**:
After generation, you can:
- Edit environment variable files (`terraform/environments/*.tfvars`)
- Modify Lambda configuration in `terraform/lambda.tf`
- Add additional resources (DynamoDB, SQS, etc.)
- Enable API Gateway by setting `enable_api_gateway = true`

**Example workflow**:
```bash
# 1. Generate application Terraform files
make setup-app-terraform

# 2. Customize the generated files
vim terraform/environments/dev.tfvars

# 3. Build and push Docker image
make docker-build
make docker-push-dev

# 4. Deploy application
make app-init-dev
make app-plan-dev
make app-apply-dev
```

---

### 4. `docker-push.sh`

**Purpose**: Build and push Docker images to Amazon ECR with proper tagging.

**Location**: `scripts/docker-push.sh`

**Usage**:
```bash
# Push to dev environment (default: Dockerfile.lambda)
./scripts/docker-push.sh dev

# Push to prod with specific repository name
./scripts/docker-push.sh prod api Dockerfile.apprunner

# Using make
make docker-push-dev
make docker-push-test
make docker-push-prod
```

**Arguments**:
1. **Environment** (required): `dev`, `test`, or `prod`
2. **Repository name** (optional): ECR repository name (defaults to project name)
3. **Dockerfile** (optional): Path to Dockerfile (defaults to `Dockerfile.lambda`)

**What it does**:
1. Reads bootstrap outputs (project name, AWS account, region)
2. Authenticates to Amazon ECR
3. Builds Docker image with multiple tags:
   - `{env}-{timestamp}` - Unique build tag
   - `{env}-latest` - Latest for environment
   - `{git-sha}` - Git commit SHA
4. Pushes all tags to ECR

**Features**:
- ✅ Auto-detects project configuration from bootstrap
- ✅ Multi-tag support for rollback capabilities
- ✅ Color-coded output for better visibility
- ✅ Validates AWS credentials and Dockerfile existence
- ✅ Git SHA tagging for traceability

**Example output**:
```
🐳 Docker Push Script
   Environment: dev
   Dockerfile: Dockerfile.lambda

✅ Configuration:
   Project: my-api
   Repository: my-api-my-api
   ECR URL: 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-api-my-api
   AWS Account: 123456789012
   AWS Region: us-east-1

🔐 Logging into Amazon ECR...
✅ Successfully logged into ECR

🏗️  Building Docker image...
✅ Docker image built successfully

📤 Pushing images to ECR...
✅ Successfully pushed images to ECR!

📋 Image URIs:
   123456789012.dkr.ecr.us-east-1.amazonaws.com/my-api-my-api:dev-20231114-162500
   123456789012.dkr.ecr.us-east-1.amazonaws.com/my-api-my-api:dev-latest
   123456789012.dkr.ecr.us-east-1.amazonaws.com/my-api-my-api:abc1234
```

---

### 5. `generate-workflows.sh`

**Purpose**: Auto-generates GitHub Actions workflows based on enabled compute options.

**Location**: `scripts/generate-workflows.sh`

**Usage**:
```bash
./scripts/generate-workflows.sh
# or
make setup-workflows
```

**What it does**:
1. Reads bootstrap outputs to detect enabled features:
   - Lambda enabled?
   - App Runner enabled?
   - EKS enabled?
2. Reads IAM role ARNs for each environment
3. Generates appropriate GitHub Actions workflows in `.github/workflows/`

**Generated workflows**:

| Feature | Workflow Files | Trigger |
|---------|----------------|---------|
| **Lambda** | `deploy-lambda-dev.yml`<br>`deploy-lambda-prod.yml` | Push to main (dev)<br>Release/manual (prod) |
| **App Runner** | `deploy-apprunner-dev.yml`<br>`deploy-apprunner-prod.yml` | Push to main (dev)<br>Release/manual (prod) |
| **EKS** | `deploy-eks-dev.yml`<br>`deploy-eks-prod.yml` | Push to main (dev)<br>Release/manual (prod) |
| **Always** | `terraform-plan.yml` | Pull requests |

**Workflow features**:
- ✅ Uses OIDC for AWS authentication (no long-lived credentials)
- ✅ Builds and pushes Docker images to ECR
- ✅ Deploys to appropriate service (Lambda/App Runner/EKS)
- ✅ Environment-specific (dev, production)
- ✅ Proper tagging with Git SHA

**Example: Lambda Dev Workflow**
```yaml
name: Deploy Lambda - Dev

on:
  push:
    branches: [main]
    paths:
      - 'src/**'
      - 'pyproject.toml'
      - 'Dockerfile.lambda'

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: dev

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/my-project-github-actions-dev
          aws-region: us-east-1

      - name: Login to Amazon ECR
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and push Docker image
        run: |
          docker build -f Dockerfile.lambda -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG

      - name: Update Lambda function
        run: |
          aws lambda update-function-code \
            --function-name my-project-dev-api \
            --image-uri $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
```

**When to run**:
- After initial bootstrap deployment
- After enabling/disabling compute options
- After adding new environments

**Customization**:
After generation, you can customize:
- Trigger conditions (branches, paths)
- Build arguments
- Deployment strategies
- Environment variables
- Health checks

---

### 6. `sync-tfvars-to-env.py`

**Purpose**: Sync variables from `terraform.tfvars` (and Terraform outputs) to `.env` file for use in shell scripts, Docker, and applications.

**Location**: `scripts/sync-tfvars-to-env.py`

**Usage**:
```bash
# Sync bootstrap terraform.tfvars to .env (no prefix)
./scripts/sync-tfvars-to-env.py
# or
make sync-env

# Custom files
./scripts/sync-tfvars-to-env.py --tfvars custom.tfvars --env custom.env

# Add TF_VAR_ prefix (for Terraform input variables)
./scripts/sync-tfvars-to-env.py --tf-var-prefix

# Custom prefix
./scripts/sync-tfvars-to-env.py --prefix "APP_"

# Overwrite .env completely (default: merge)
./scripts/sync-tfvars-to-env.py --overwrite
```

**What it does**:
1. Parses `terraform.tfvars` file (no external dependencies)
2. Converts Terraform variables to environment variable format
3. Writes to `.env` file with proper formatting
4. **No prefix by default** (clean variable names for shell/Docker/apps)
5. Merges with existing `.env` (unless `--overwrite`)

**Variable Conversion**:
```hcl
# terraform.tfvars or outputs
project_name = "my-app"
enable_lambda = true
lambda_timeout = 300
ecr_repositories = ["api", "worker"]
lambda_function_arn = "arn:aws:lambda:us-east-1:123456789012:function:my-app"
```

```bash
# .env (generated - no prefix)
PROJECT_NAME=my-app
ENABLE_LAMBDA=true
LAMBDA_TIMEOUT=300
ECR_REPOSITORIES=api,worker
LAMBDA_FUNCTION_ARN=arn:aws:lambda:us-east-1:123456789012:function:my-app
```

**Options**:
- `--tfvars PATH` - Path to terraform.tfvars (default: `bootstrap/terraform.tfvars`)
- `--env PATH` - Path to .env file (default: `.env`)
- `--prefix PREFIX` - Variable prefix (default: none)
- `--tf-var-prefix` - Add TF_VAR_ prefix (for Terraform input variables)
- `--overwrite` - Overwrite .env completely (default: merge)

**When to run**:
- After `terraform apply` to capture resource ARNs and IDs
- After creating/updating `terraform.tfvars`
- Before running shell scripts that need Terraform outputs
- To share configuration between Terraform and application code

**Use cases**:
```bash
# Use Terraform outputs in shell scripts
terraform output -json > outputs.tfvars  # Export outputs
./scripts/sync-tfvars-to-env.py --tfvars outputs.tfvars
source .env
aws lambda invoke --function-name $LAMBDA_FUNCTION_ARN output.json

# Use in Docker Compose
docker-compose --env-file .env up

# Use in GitHub Actions
- name: Load environment
  run: |
    source .env
    echo "LAMBDA_ARN=$LAMBDA_FUNCTION_ARN" >> $GITHUB_ENV
```

**Note**: The `.env` file is automatically added to `.gitignore` to prevent committing sensitive data.

---

## 🔄 Typical Workflow

### Initial Setup
```bash
# 1. Deploy bootstrap
make bootstrap-apply

# 2. Generate backend configs
make setup-backend

# 3. Sync tfvars to .env
make sync-env

# 4. Generate GitHub Actions workflows
make setup-workflows

# 5. Commit workflows
git add .github/workflows/
git commit -m "Add auto-generated workflows"
git push
```

### Daily Development
```bash
# Build and push Docker image
make docker-push-dev

# Or push directly
./scripts/docker-push.sh dev my-api Dockerfile.lambda
```

### Updating Workflows
```bash
# After changing bootstrap configuration (enable_lambda, etc.)
make bootstrap-apply
make setup-workflows

# Review changes
git diff .github/workflows/

# Commit if happy
git add .github/workflows/
git commit -m "Update workflows for new configuration"
```

---

## 🛠️ Script Requirements

### `setup-pre-commit.sh`
- ✅ `uv` installed
- ✅ Git repository initialized
- ✅ `pyproject.toml.example` (included in repo)

### `setup-terraform-backend.sh`
- ✅ Bootstrap Terraform initialized and applied
- ✅ `terraform` CLI installed
- ✅ `jq` (optional, for JSON parsing)

### `docker-push.sh`
- ✅ Bootstrap Terraform applied
- ✅ Docker installed and running
- ✅ AWS CLI configured
- ✅ AWS credentials with ECR permissions
- ✅ Git (optional, for SHA tagging)

### `generate-workflows.sh`
- ✅ Bootstrap Terraform applied
- ✅ `jq` installed (for JSON parsing)

### `sync-tfvars-to-env.py`
- ✅ `uv` installed (for `uv run python`)
- ✅ Python 3.13+ (included with uv)
- ✅ `terraform.tfvars` file exists (default: `bootstrap/terraform.tfvars`)
- ❌ No external Python packages required (pure Python)

**Install jq**:
```bash
# Ubuntu/Debian
sudo apt-get install jq

# macOS
brew install jq

# Or download binary from https://stedolan.github.io/jq/
```

---

## 🐛 Troubleshooting

### Backend setup fails
**Problem**: "Error: Bootstrap directory not found"

**Solution**:
```bash
cd bootstrap/
terraform init
terraform apply
cd ..
./scripts/setup-terraform-backend.sh
```

### Docker push fails with auth error
**Problem**: "Error: Failed to login to ECR"

**Solution**:
```bash
# Check AWS credentials
aws sts get-caller-identity

# Manually login
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  123456789012.dkr.ecr.us-east-1.amazonaws.com

# Then retry
./scripts/docker-push.sh dev
```

### Workflow generation produces empty workflows
**Problem**: No feature flags detected

**Solution**:
```bash
# Verify bootstrap outputs
cd bootstrap/
terraform output summary

# Should show enabled_features
# If not, update terraform.tfvars and re-apply
```

---

## 📝 Script Maintenance

All scripts are designed to be:
- **Self-contained**: No external dependencies except CLI tools
- **Idempotent**: Safe to run multiple times
- **Verbose**: Clear output with color-coding
- **Error-handling**: Validates inputs and exits gracefully

To modify scripts:
1. Edit in `scripts/` directory
2. Test with `bash -x scripts/script-name.sh` for debugging
3. Ensure executable: `chmod +x scripts/script-name.sh`
4. Update this documentation

---

## 🔗 Related Documentation

- [README.md](../README.md) - Main project documentation
- [Bootstrap outputs](../bootstrap/outputs.tf) - Available Terraform outputs
- [GitHub Actions docs](https://docs.github.com/en/actions)

---

**Questions or issues?** Open an issue or check the troubleshooting section in the main README.
