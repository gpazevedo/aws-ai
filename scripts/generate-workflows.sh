#!/bin/bash
# =============================================================================
# Generate GitHub Actions Workflows
# =============================================================================
# This script reads bootstrap outputs and generates GitHub Actions workflows
# based on enabled compute options (Lambda, App Runner, EKS)
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

BOOTSTRAP_DIR="bootstrap"
WORKFLOWS_DIR=".github/workflows"

echo -e "${BLUE}🔄 GitHub Actions Workflow Generator${NC}"
echo ""

# Check if bootstrap directory exists
if [ ! -d "$BOOTSTRAP_DIR" ]; then
  echo -e "${RED}❌ Error: Bootstrap directory not found: $BOOTSTRAP_DIR${NC}"
  echo "   Please run bootstrap first: make bootstrap-apply"
  exit 1
fi

# Read bootstrap outputs
echo -e "${BLUE}📖 Reading bootstrap configuration...${NC}"
cd "$BOOTSTRAP_DIR"

# Check if Terraform is initialized
if [ ! -d ".terraform" ]; then
  echo -e "${RED}❌ Error: Bootstrap Terraform not initialized${NC}"
  echo "   Please run: make bootstrap-init && make bootstrap-apply"
  exit 1
fi

# Read configuration
PROJECT_NAME=$(terraform output -raw project_name 2>/dev/null)
AWS_ACCOUNT_ID=$(terraform output -raw aws_account_id 2>/dev/null)
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
GITHUB_ORG=$(terraform output -json summary 2>/dev/null | jq -r '.github_actions_roles.dev' | cut -d':' -f5 | cut -d'/' -f1 || echo "")

# Read feature flags from summary
SUMMARY_JSON=$(terraform output -json summary 2>/dev/null)
ENABLE_LAMBDA=$(echo "$SUMMARY_JSON" | jq -r '.enabled_features.lambda // false')
ENABLE_APPRUNNER=$(echo "$SUMMARY_JSON" | jq -r '.enabled_features.apprunner // false')
ENABLE_EKS=$(echo "$SUMMARY_JSON" | jq -r '.enabled_features.eks // false')
ENABLE_TEST_ENV=$(echo "$SUMMARY_JSON" | jq -r '.enabled_features.test_env // false')

# Read IAM role ARNs
ROLE_DEV=$(terraform output -raw github_actions_role_dev_arn 2>/dev/null)
ROLE_TEST=$(terraform output -raw github_actions_role_test_arn 2>/dev/null || echo "")
ROLE_PROD=$(terraform output -raw github_actions_role_prod_arn 2>/dev/null)

# Read ECR repositories
ECR_REPOS=$(terraform output -json ecr_repositories 2>/dev/null | jq -r 'keys[]' | head -1 || echo "$PROJECT_NAME")

cd ..

# Validation
if [ -z "$PROJECT_NAME" ] || [ -z "$AWS_ACCOUNT_ID" ] || [ -z "$ROLE_DEV" ]; then
  echo -e "${RED}❌ Error: Could not read required bootstrap outputs${NC}"
  echo "   Please ensure bootstrap is applied: make bootstrap-apply"
  exit 1
fi

echo -e "${GREEN}✅ Configuration loaded:${NC}"
echo "   Project: ${PROJECT_NAME}"
echo "   AWS Account: ${AWS_ACCOUNT_ID}"
echo "   AWS Region: ${AWS_REGION}"
echo "   Lambda enabled: ${ENABLE_LAMBDA}"
echo "   App Runner enabled: ${ENABLE_APPRUNNER}"
echo "   EKS enabled: ${ENABLE_EKS}"
echo "   Test environment: ${ENABLE_TEST_ENV}"
echo ""

# Create workflows directory
mkdir -p "$WORKFLOWS_DIR"

# =============================================================================
# Generate Lambda Workflows
# =============================================================================

if [ "$ENABLE_LAMBDA" = "true" ]; then
  echo -e "${BLUE}📝 Generating Lambda workflows...${NC}"

  # Dev workflow
  cat > "$WORKFLOWS_DIR/deploy-lambda-dev.yml" <<EOF
name: Deploy Lambda - Dev

on:
  push:
    branches: [main]
    paths:
      - 'src/**'
      - 'pyproject.toml'
      - 'uv.lock'
      - 'Dockerfile.lambda'
      - '.github/workflows/deploy-lambda-dev.yml'

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: dev

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${ROLE_DEV}
          aws-region: ${AWS_REGION}

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and push Docker image
        env:
          ECR_REGISTRY: \${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: ${PROJECT_NAME}-${ECR_REPOS}
          IMAGE_TAG: dev-\${{ github.sha }}
        run: |
          docker build -f Dockerfile.lambda -t \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG .
          docker push \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG
          docker tag \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG \$ECR_REGISTRY/\$ECR_REPOSITORY:dev-latest
          docker push \$ECR_REGISTRY/\$ECR_REPOSITORY:dev-latest

      - name: Update Lambda function
        run: |
          aws lambda update-function-code \\
            --function-name ${PROJECT_NAME}-dev-api \\
            --image-uri \${{ steps.login-ecr.outputs.registry }}/${PROJECT_NAME}-${ECR_REPOS}:dev-\${{ github.sha }}
EOF

  echo -e "${GREEN}   ✅ Created deploy-lambda-dev.yml${NC}"

  # Prod workflow
  cat > "$WORKFLOWS_DIR/deploy-lambda-prod.yml" <<EOF
name: Deploy Lambda - Production

on:
  release:
    types: [published]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${ROLE_PROD}
          aws-region: ${AWS_REGION}

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and push Docker image
        env:
          ECR_REGISTRY: \${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: ${PROJECT_NAME}-${ECR_REPOS}
          IMAGE_TAG: prod-\${{ github.sha }}
        run: |
          docker build -f Dockerfile.lambda -t \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG .
          docker push \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG
          docker tag \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG \$ECR_REGISTRY/\$ECR_REPOSITORY:prod-latest
          docker push \$ECR_REGISTRY/\$ECR_REPOSITORY:prod-latest

      - name: Update Lambda function
        run: |
          aws lambda update-function-code \\
            --function-name ${PROJECT_NAME}-prod-api \\
            --image-uri \${{ steps.login-ecr.outputs.registry }}/${PROJECT_NAME}-${ECR_REPOS}:prod-\${{ github.sha }}
EOF

  echo -e "${GREEN}   ✅ Created deploy-lambda-prod.yml${NC}"
fi

# =============================================================================
# Generate App Runner Workflows
# =============================================================================

if [ "$ENABLE_APPRUNNER" = "true" ]; then
  echo -e "${BLUE}📝 Generating App Runner workflows...${NC}"

  # Dev workflow
  cat > "$WORKFLOWS_DIR/deploy-apprunner-dev.yml" <<EOF
name: Deploy App Runner - Dev

on:
  push:
    branches: [main]
    paths:
      - 'src/**'
      - 'pyproject.toml'
      - 'uv.lock'
      - 'Dockerfile.apprunner'
      - '.github/workflows/deploy-apprunner-dev.yml'

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: dev

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${ROLE_DEV}
          aws-region: ${AWS_REGION}

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and push Docker image
        env:
          ECR_REGISTRY: \${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: ${PROJECT_NAME}-${ECR_REPOS}
          IMAGE_TAG: dev-\${{ github.sha }}
        run: |
          docker build -f Dockerfile.apprunner -t \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG .
          docker push \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG
          docker tag \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG \$ECR_REGISTRY/\$ECR_REPOSITORY:dev-latest
          docker push \$ECR_REGISTRY/\$ECR_REPOSITORY:dev-latest

      - name: Deploy to App Runner
        run: |
          # Get App Runner service ARN (assumes service already exists from Terraform)
          SERVICE_ARN=\$(aws apprunner list-services --query "ServiceSummaryList[?ServiceName=='${PROJECT_NAME}-dev'].ServiceArn" --output text)

          if [ -n "\$SERVICE_ARN" ]; then
            echo "Starting deployment to App Runner service: \$SERVICE_ARN"
            aws apprunner start-deployment --service-arn "\$SERVICE_ARN"
          else
            echo "⚠️  App Runner service not found. Please deploy infrastructure first."
            exit 1
          fi
EOF

  echo -e "${GREEN}   ✅ Created deploy-apprunner-dev.yml${NC}"

  # Prod workflow
  cat > "$WORKFLOWS_DIR/deploy-apprunner-prod.yml" <<EOF
name: Deploy App Runner - Production

on:
  release:
    types: [published]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${ROLE_PROD}
          aws-region: ${AWS_REGION}

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and push Docker image
        env:
          ECR_REGISTRY: \${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: ${PROJECT_NAME}-${ECR_REPOS}
          IMAGE_TAG: prod-\${{ github.sha }}
        run: |
          docker build -f Dockerfile.apprunner -t \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG .
          docker push \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG
          docker tag \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG \$ECR_REGISTRY/\$ECR_REPOSITORY:prod-latest
          docker push \$ECR_REGISTRY/\$ECR_REPOSITORY:prod-latest

      - name: Deploy to App Runner
        run: |
          SERVICE_ARN=\$(aws apprunner list-services --query "ServiceSummaryList[?ServiceName=='${PROJECT_NAME}-prod'].ServiceArn" --output text)

          if [ -n "\$SERVICE_ARN" ]; then
            echo "Starting deployment to App Runner service: \$SERVICE_ARN"
            aws apprunner start-deployment --service-arn "\$SERVICE_ARN"
          else
            echo "⚠️  App Runner service not found. Please deploy infrastructure first."
            exit 1
          fi
EOF

  echo -e "${GREEN}   ✅ Created deploy-apprunner-prod.yml${NC}"
fi

# =============================================================================
# Generate EKS Workflows
# =============================================================================

if [ "$ENABLE_EKS" = "true" ]; then
  echo -e "${BLUE}📝 Generating EKS workflows...${NC}"

  # Dev workflow
  cat > "$WORKFLOWS_DIR/deploy-eks-dev.yml" <<EOF
name: Deploy to EKS - Dev

on:
  push:
    branches: [main]
    paths:
      - 'src/**'
      - 'pyproject.toml'
      - 'uv.lock'
      - 'Dockerfile.eks'
      - 'k8s/**'
      - '.github/workflows/deploy-eks-dev.yml'

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: dev

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${ROLE_DEV}
          aws-region: ${AWS_REGION}

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and push Docker image
        env:
          ECR_REGISTRY: \${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: ${PROJECT_NAME}-${ECR_REPOS}
          IMAGE_TAG: dev-\${{ github.sha }}
        run: |
          docker build -f Dockerfile.eks -t \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG .
          docker push \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG
          docker tag \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG \$ECR_REGISTRY/\$ECR_REPOSITORY:dev-latest
          docker push \$ECR_REGISTRY/\$ECR_REPOSITORY:dev-latest

      - name: Update kubeconfig
        run: |
          aws eks update-kubeconfig --name ${PROJECT_NAME} --region ${AWS_REGION}

      - name: Deploy to Kubernetes
        run: |
          # Update image in deployment
          kubectl set image deployment/${PROJECT_NAME}-api \\
            ${PROJECT_NAME}-api=\${{ steps.login-ecr.outputs.registry }}/${PROJECT_NAME}-${ECR_REPOS}:dev-\${{ github.sha }} \\
            -n dev

          # Wait for rollout
          kubectl rollout status deployment/${PROJECT_NAME}-api -n dev --timeout=5m
EOF

  echo -e "${GREEN}   ✅ Created deploy-eks-dev.yml${NC}"

  # Prod workflow
  cat > "$WORKFLOWS_DIR/deploy-eks-prod.yml" <<EOF
name: Deploy to EKS - Production

on:
  release:
    types: [published]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${ROLE_PROD}
          aws-region: ${AWS_REGION}

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and push Docker image
        env:
          ECR_REGISTRY: \${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: ${PROJECT_NAME}-${ECR_REPOS}
          IMAGE_TAG: prod-\${{ github.sha }}
        run: |
          docker build -f Dockerfile.eks -t \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG .
          docker push \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG
          docker tag \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG \$ECR_REGISTRY/\$ECR_REPOSITORY:prod-latest
          docker push \$ECR_REGISTRY/\$ECR_REPOSITORY:prod-latest

      - name: Update kubeconfig
        run: |
          aws eks update-kubeconfig --name ${PROJECT_NAME} --region ${AWS_REGION}

      - name: Deploy to Kubernetes
        run: |
          kubectl set image deployment/${PROJECT_NAME}-api \\
            ${PROJECT_NAME}-api=\${{ steps.login-ecr.outputs.registry }}/${PROJECT_NAME}-${ECR_REPOS}:prod-\${{ github.sha }} \\
            -n prod

          kubectl rollout status deployment/${PROJECT_NAME}-api -n prod --timeout=10m
EOF

  echo -e "${GREEN}   ✅ Created deploy-eks-prod.yml${NC}"
fi

# =============================================================================
# Generate Terraform Plan Workflow (Always)
# =============================================================================

echo -e "${BLUE}📝 Generating Terraform plan workflow...${NC}"

cat > "$WORKFLOWS_DIR/terraform-plan.yml" <<EOF
name: Terraform Plan

on:
  pull_request:
    paths:
      - 'terraform/**'
      - '.github/workflows/terraform-plan.yml'

jobs:
  plan:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        environment: [dev, prod]

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.13.0

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: \${{ matrix.environment == 'dev' && '${ROLE_DEV}' || '${ROLE_PROD}' }}
          aws-region: ${AWS_REGION}

      - name: Terraform Init
        working-directory: terraform
        run: |
          terraform init -backend-config=environments/\${{ matrix.environment }}-backend.hcl

      - name: Terraform Plan
        working-directory: terraform
        run: |
          terraform plan -var-file=environments/\${{ matrix.environment }}.tfvars -out=tfplan

      - name: Upload Plan
        uses: actions/upload-artifact@v4
        with:
          name: tfplan-\${{ matrix.environment }}
          path: terraform/tfplan
EOF

echo -e "${GREEN}   ✅ Created terraform-plan.yml${NC}"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo -e "${GREEN}✅ GitHub Actions workflows generated successfully!${NC}"
echo ""
echo -e "${BLUE}📋 Generated workflows:${NC}"

if [ "$ENABLE_LAMBDA" = "true" ]; then
  echo "   - deploy-lambda-dev.yml"
  echo "   - deploy-lambda-prod.yml"
fi

if [ "$ENABLE_APPRUNNER" = "true" ]; then
  echo "   - deploy-apprunner-dev.yml"
  echo "   - deploy-apprunner-prod.yml"
fi

if [ "$ENABLE_EKS" = "true" ]; then
  echo "   - deploy-eks-dev.yml"
  echo "   - deploy-eks-prod.yml"
fi

echo "   - terraform-plan.yml"

echo ""
echo -e "${YELLOW}💡 Next steps:${NC}"
echo "   1. Review generated workflows in .github/workflows/"
echo "   2. Commit and push workflows to GitHub"
echo "   3. Configure GitHub environments (dev, production) with required secrets:"
echo "      - No secrets needed! Using OIDC for authentication"
echo "   4. Push code to main branch or create a PR to trigger workflows"
echo ""
