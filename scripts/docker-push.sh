#!/bin/bash
# =============================================================================
# Build and Push Docker Image to ECR
# =============================================================================
# This script builds and pushes a Docker image to Amazon ECR with hierarchical tagging
# Usage: ./docker-push.sh [environment] [service] [dockerfile]
# Examples:
#   ./docker-push.sh dev api Dockerfile.lambda
#   ./docker-push.sh prod worker Dockerfile.lambda
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
ENVIRONMENT="${1:-dev}"
SERVICE="${2:-api}"
DOCKERFILE="${3:-Dockerfile.lambda}"

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|test|prod)$ ]]; then
  echo -e "${RED}❌ Error: Invalid environment '${ENVIRONMENT}'${NC}"
  echo "   Usage: $0 [dev|test|prod] [service] [dockerfile]"
  exit 1
fi

echo -e "${BLUE}🐳 Docker Build & Push Script${NC}"
echo "   Environment: ${ENVIRONMENT}"
echo "   Service: ${SERVICE}"
echo "   Dockerfile: ${DOCKERFILE}"
echo ""

# =============================================================================
# Detect CPU Architecture and Setup QEMU if needed
# =============================================================================
HOST_ARCH=$(uname -m)
TARGET_ARCH="arm64"  # Always build for arm64 (AWS Graviton2)

echo -e "${BLUE}🖥️  Detecting host architecture...${NC}"
echo "   Host CPU: ${HOST_ARCH}"
echo "   Target: ${TARGET_ARCH} (AWS Graviton2)"
echo ""

# Check if we need QEMU (cross-platform build)
NEED_QEMU=false
if [[ "$HOST_ARCH" == "x86_64" ]] || [[ "$HOST_ARCH" == "amd64" ]]; then
  NEED_QEMU=true
  echo -e "${YELLOW}⚠️  Cross-platform build detected (x86_64 → arm64)${NC}"
  echo "   QEMU emulation required for arm64 builds"
  echo ""

  # Check if QEMU is already installed
  if docker buildx inspect --bootstrap 2>/dev/null | grep -q "linux/arm64"; then
    echo -e "${GREEN}✅ QEMU already installed and configured${NC}"
  else
    echo -e "${YELLOW}📦 Installing QEMU for cross-platform builds...${NC}"
    echo "   This is a one-time setup"
    echo ""

    # Install QEMU emulation
    docker run --privileged --rm tonistiigi/binfmt --install all

    if [ $? -eq 0 ]; then
      echo -e "${GREEN}✅ QEMU installed successfully${NC}"
    else
      echo -e "${RED}❌ Error: Failed to install QEMU${NC}"
      echo "   You can install it manually with:"
      echo "   docker run --privileged --rm tonistiigi/binfmt --install all"
      exit 1
    fi
  fi
  echo ""
elif [[ "$HOST_ARCH" == "aarch64" ]] || [[ "$HOST_ARCH" == "arm64" ]]; then
  echo -e "${GREEN}✅ Native arm64 build - no emulation needed${NC}"
  echo ""
else
  echo -e "${YELLOW}⚠️  Unknown architecture: ${HOST_ARCH}${NC}"
  echo "   Attempting build anyway..."
  echo ""
fi

# =============================================================================
# Read Bootstrap Configuration (or use environment variables)
# =============================================================================

# Check if required environment variables are set
if [ -z "$PROJECT_NAME" ] || [ -z "$AWS_ACCOUNT_ID" ] || [ -z "$AWS_REGION" ]; then
  echo -e "${BLUE}📖 Reading bootstrap outputs...${NC}"

  BOOTSTRAP_DIR="bootstrap"
  if [ ! -d "$BOOTSTRAP_DIR" ]; then
    echo -e "${RED}❌ Error: Bootstrap directory not found: $BOOTSTRAP_DIR${NC}"
    echo "   Please run bootstrap first: make bootstrap-apply"
    echo "   Or set environment variables: PROJECT_NAME, AWS_ACCOUNT_ID, AWS_REGION"
    exit 1
  fi

  cd "$BOOTSTRAP_DIR"

  # Get project name if not set
  if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME=$(terraform output -raw project_name 2>/dev/null)
    if [ -z "$PROJECT_NAME" ]; then
      echo -e "${RED}❌ Error: Could not read project_name from bootstrap${NC}"
      exit 1
    fi
  fi

  # Get AWS account ID if not set
  if [ -z "$AWS_ACCOUNT_ID" ]; then
    AWS_ACCOUNT_ID=$(terraform output -raw aws_account_id 2>/dev/null)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
      echo -e "${RED}❌ Error: Could not read aws_account_id from bootstrap${NC}"
      exit 1
    fi
  fi

  # Get AWS region if not set
  if [ -z "$AWS_REGION" ]; then
    AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
  fi

  cd ..
else
  echo -e "${GREEN}✅ Using environment variables${NC}"
fi

# ECR repository is always the project name
ECR_REPOSITORY="${PROJECT_NAME}"

# Build ECR URL
ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"

echo -e "${GREEN}✅ Configuration:${NC}"
echo "   Project: ${PROJECT_NAME}"
echo "   ECR Repository: ${ECR_REPOSITORY}"
echo "   ECR URL: ${ECR_URL}"
echo "   AWS Account: ${AWS_ACCOUNT_ID}"
echo "   AWS Region: ${AWS_REGION}"
echo ""

# =============================================================================
# Validate Dockerfile and Service
# =============================================================================
if [ ! -f "backend/$DOCKERFILE" ]; then
  echo -e "${RED}❌ Error: Dockerfile not found: backend/$DOCKERFILE${NC}"
  echo ""
  echo "Available Dockerfiles:"
  ls -1 backend/Dockerfile.* 2>/dev/null || echo "  None found"
  exit 1
fi

if [ ! -d "backend/$SERVICE" ]; then
  echo -e "${RED}❌ Error: Service directory not found: backend/$SERVICE${NC}"
  echo ""
  echo "Available services:"
  ls -d backend/*/ 2>/dev/null | xargs -n1 basename || echo "  None found"
  exit 1
fi

# =============================================================================
# Login to ECR
# =============================================================================
echo -e "${BLUE}🔐 Logging into Amazon ECR...${NC}"
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Error: Failed to login to ECR${NC}"
  echo "   Please check your AWS credentials"
  exit 1
fi

echo -e "${GREEN}✅ Successfully logged into ECR${NC}"
echo ""

# =============================================================================
# Build Docker Image
# =============================================================================
echo -e "${BLUE}🏗️  Building Docker image for ${TARGET_ARCH}...${NC}"

# Generate timestamp and git SHA
TIMESTAMP=$(date -u +%Y-%m-%d-%H-%M)
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "local")

# Hierarchical tag format: service-environment-datetime-sha
# Note: Using hyphens instead of slashes (Docker tags cannot contain /)
PRIMARY_TAG="${SERVICE}-${ENVIRONMENT}-${TIMESTAMP}-${GIT_SHA}"
SERVICE_LATEST_TAG="${SERVICE}-${ENVIRONMENT}-latest"
ENV_LATEST_TAG="${ENVIRONMENT}-latest"

echo "   Service folder: backend/${SERVICE}"
echo "   Target architecture: ${TARGET_ARCH}"
echo "   Primary tag: ${PRIMARY_TAG}"
echo ""

cd backend

docker build \
  --platform=linux/${TARGET_ARCH} \
  --build-arg SERVICE_FOLDER="${SERVICE}" \
  -f "${DOCKERFILE}" \
  -t "${ECR_URL}:${PRIMARY_TAG}" \
  -t "${ECR_URL}:${SERVICE_LATEST_TAG}" \
  -t "${ECR_URL}:${ENV_LATEST_TAG}" \
  .

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Error: Docker build failed${NC}"
  exit 1
fi

cd ..

echo -e "${GREEN}✅ Docker image built successfully${NC}"
echo ""

# =============================================================================
# Push to ECR
# =============================================================================
echo -e "${BLUE}📤 Pushing images to ECR...${NC}"
echo ""

echo "   Pushing: ${PRIMARY_TAG}"
docker push "${ECR_URL}:${PRIMARY_TAG}"

echo "   Pushing: ${SERVICE_LATEST_TAG}"
docker push "${ECR_URL}:${SERVICE_LATEST_TAG}"

echo "   Pushing: ${ENV_LATEST_TAG}"
docker push "${ECR_URL}:${ENV_LATEST_TAG}"

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Error: Failed to push to ECR${NC}"
  exit 1
fi

echo ""
echo -e "${GREEN}✅ Successfully pushed images to ECR!${NC}"
echo ""
echo -e "${BLUE}📋 Image URIs (${TARGET_ARCH} architecture):${NC}"
echo "   ${ECR_URL}:${PRIMARY_TAG}"
echo "   ${ECR_URL}:${SERVICE_LATEST_TAG}"
echo "   ${ECR_URL}:${ENV_LATEST_TAG}"
echo ""
echo -e "${BLUE}📊 Image Details:${NC}"
echo "   Repository: ${ECR_REPOSITORY}"
echo "   Service: ${SERVICE}"
echo "   Environment: ${ENVIRONMENT}"
echo "   Git SHA: ${GIT_SHA}"
echo "   Timestamp: ${TIMESTAMP}"
echo "   Architecture: ${TARGET_ARCH}"
echo ""
echo -e "${YELLOW}💡 Next steps:${NC}"
echo "   1. Verify images in ECR:"
echo "      aws ecr describe-images --repository-name ${ECR_REPOSITORY} --query 'imageDetails[?imageTags[?contains(@, \`${SERVICE}/${ENVIRONMENT}\`)]]'"
echo ""
echo "   2. Deploy with Terraform:"
echo "      make app-init-dev"
echo "      make app-plan-dev"
echo "      make app-apply-dev"
echo ""
