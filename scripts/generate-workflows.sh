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
ECR_REPOS_JSON=$(terraform output -json ecr_repositories 2>/dev/null || echo "{}")
# Use single ECR repository for all services
ECR_REPOSITORY=$(echo "$ECR_REPOS_JSON" | jq -r 'keys[]' | head -1)

# Fallback to project name if no repos found
if [ -z "$ECR_REPOSITORY" ]; then
  ECR_REPOSITORY="${PROJECT_NAME}"
fi

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
echo "   ECR Repository: ${ECR_REPOSITORY}"
echo ""

# Create workflows directory
mkdir -p "$WORKFLOWS_DIR"

# =============================================================================
# Detect Backend Services
# =============================================================================

echo -e "${BLUE}🔍 Detecting backend services...${NC}"

# Find all directories in backend/ (excluding Dockerfile* and other files)
BACKEND_SERVICES=()
if [ -d "backend" ]; then
  for dir in backend/*/; do
    if [ -d "$dir" ]; then
      service_name=$(basename "$dir")
      # Skip if it's a Dockerfile or other non-service directory
      if [[ ! "$service_name" =~ ^Dockerfile ]]; then
        BACKEND_SERVICES+=("$service_name")
      fi
    fi
  done
fi

if [ ${#BACKEND_SERVICES[@]} -eq 0 ]; then
  BACKEND_SERVICES=("api")
  echo -e "${YELLOW}⚠️  No backend services found, using default: api${NC}"
else
  echo -e "${GREEN}✅ Found services: ${BACKEND_SERVICES[*]}${NC}"
fi
echo ""

# Generate path filter configuration for GitHub Actions
SERVICES_FILTER=""
for service in "${BACKEND_SERVICES[@]}"; do
  SERVICES_FILTER="${SERVICES_FILTER}            $service:
              - 'backend/$service/**'
              - 'backend/Dockerfile.lambda'
"
done

# Generate JSON array for matrix strategy: ["api", "worker"]
SERVICES_JSON="["
first=true
for service in "${BACKEND_SERVICES[@]}"; do
  if [ "$first" = true ]; then
    SERVICES_JSON="${SERVICES_JSON}\"$service\""
    first=false
  else
    SERVICES_JSON="${SERVICES_JSON}, \"$service\""
  fi
done
SERVICES_JSON="${SERVICES_JSON}]"

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
      - 'backend/**'
      - '.github/workflows/deploy-lambda-dev.yml'

jobs:
  # Detect which services changed
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      services: \${{ steps.filter.outputs.changes }}
    steps:
      - uses: actions/checkout@v4
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
$SERVICES_FILTER

  deploy:
    needs: detect-changes
    if: \${{ needs.detect-changes.outputs.services != '[]' }}
    runs-on: ubuntu-latest
    environment: dev
    permissions:
      id-token: write
      contents: read
    strategy:
      matrix:
        service: \${{ fromJSON(needs.detect-changes.outputs.services) }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${ROLE_DEV}
          aws-region: ${AWS_REGION}

      - name: Build and push Lambda Docker image
        run: |
          # Use centralized docker-push.sh script for consistent builds
          ./scripts/docker-push.sh dev \${{ matrix.service }} Dockerfile.lambda

      - name: Update Lambda function
        run: |
          # Use the service-environment-latest tag for Lambda deployments
          ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
          IMAGE_URI="\${ECR_REGISTRY}/${ECR_REPOSITORY}:\${{ matrix.service }}-dev-latest"

          aws lambda update-function-code \\
            --function-name ${PROJECT_NAME}-dev-\${{ matrix.service }} \\
            --image-uri "\${IMAGE_URI}"
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
    permissions:
      id-token: write
      contents: read
    strategy:
      matrix:
        # Services detected from backend/ directory
        service: ${SERVICES_JSON}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${ROLE_PROD}
          aws-region: ${AWS_REGION}

      - name: Build and push Lambda Docker image
        run: |
          # Use centralized docker-push.sh script for consistent builds
          ./scripts/docker-push.sh prod \${{ matrix.service }} Dockerfile.lambda

      - name: Update Lambda function
        run: |
          # Use the service-environment-latest tag for Lambda deployments
          ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
          IMAGE_URI="\${ECR_REGISTRY}/${ECR_REPOSITORY}:\${{ matrix.service }}-prod-latest"

          aws lambda update-function-code \\
            --function-name ${PROJECT_NAME}-prod-\${{ matrix.service }} \\
            --image-uri "\${IMAGE_URI}"

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
      - 'backend/**'
      - '.github/workflows/deploy-apprunner-dev.yml'

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: dev
    permissions:
      id-token: write
      contents: read
    strategy:
      matrix:
        # Keep simple for now - add more services as needed
        service: [api]

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${ROLE_DEV}
          aws-region: ${AWS_REGION}

      - name: Build and push App Runner Docker image
        run: |
          # Use centralized docker-push.sh script for consistent builds
          ./scripts/docker-push.sh dev ${{ matrix.service }} Dockerfile.apprunner

      - name: Deploy to App Runner
        run: |
          # Get App Runner service ARN (assumes service already exists from Terraform)
          SERVICE_ARN=\$(aws apprunner list-services --query "ServiceSummaryList[?ServiceName=='${PROJECT_NAME}-dev-\${{ matrix.service }}'].ServiceArn" --output text)

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
    permissions:
      id-token: write
      contents: read
    strategy:
      matrix:
        # Keep simple for now - add more services as needed
        service: [api]

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${ROLE_PROD}
          aws-region: ${AWS_REGION}

      - name: Build and push App Runner Docker image
        run: |
          # Use centralized docker-push.sh script for consistent builds
          ./scripts/docker-push.sh prod ${{ matrix.service }} Dockerfile.apprunner

      - name: Deploy to App Runner
        run: |
          SERVICE_ARN=\$(aws apprunner list-services --query "ServiceSummaryList[?ServiceName=='${PROJECT_NAME}-prod-${{ matrix.service }}'].ServiceArn" --output text)

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
      - 'backend/**'
      - 'k8s/**'
      - '.github/workflows/deploy-eks-dev.yml'

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: dev
    permissions:
      id-token: write
      contents: read
    strategy:
      matrix:
        # Keep simple for now - add more services as needed
        service: [api]

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${ROLE_DEV}
          aws-region: ${AWS_REGION}

      - name: Build and push EKS Docker image
        run: |
          # Use centralized docker-push.sh script for consistent builds
          ./scripts/docker-push.sh dev ${{ matrix.service }} Dockerfile.eks

      - name: Update kubeconfig
        run: |
          aws eks update-kubeconfig --name ${PROJECT_NAME} --region ${AWS_REGION}

      - name: Deploy to Kubernetes
        run: |
          # Use the service-environment-latest tag for EKS deployments
          ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
          IMAGE_URI="\${ECR_REGISTRY}/${ECR_REPOSITORY}:${{ matrix.service }}-dev-latest"

          kubectl set image deployment/${PROJECT_NAME}-${{ matrix.service }} \\
            ${PROJECT_NAME}-${{ matrix.service }}="\${IMAGE_URI}" \\
            -n dev

          # Wait for rollout
          kubectl rollout status deployment/${PROJECT_NAME}-${{ matrix.service }} -n dev --timeout=5m
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
    permissions:
      id-token: write
      contents: read
    strategy:
      matrix:
        # Keep simple for now - add more services as needed
        service: [api]

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${ROLE_PROD}
          aws-region: ${AWS_REGION}

      - name: Build and push EKS Docker image
        run: |
          # Use centralized docker-push.sh script for consistent builds
          ./scripts/docker-push.sh prod ${{ matrix.service }} Dockerfile.eks

      - name: Update kubeconfig
        run: |
          aws eks update-kubeconfig --name ${PROJECT_NAME} --region ${AWS_REGION}

      - name: Deploy to Kubernetes
        run: |
          # Use the service-environment-latest tag for EKS deployments
          ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
          IMAGE_URI="\${ECR_REGISTRY}/${ECR_REPOSITORY}:${{ matrix.service }}-prod-latest"

          kubectl set image deployment/${PROJECT_NAME}-${{ matrix.service }} \\
            ${PROJECT_NAME}-${{ matrix.service }}="\${IMAGE_URI}" \\
            -n prod

          kubectl rollout status deployment/${PROJECT_NAME}-${{ matrix.service }} -n prod --timeout=10m
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
    permissions:
      id-token: write
      contents: read

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
