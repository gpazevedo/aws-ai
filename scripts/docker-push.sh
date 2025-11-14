#!/bin/bash
# =============================================================================
# Push Docker Image to ECR
# =============================================================================
# This script builds and pushes a Docker image to Amazon ECR
# Usage: ./docker-push.sh [environment] [repository-name] [dockerfile]
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
REPOSITORY_NAME="${2:-}"
DOCKERFILE="${3:-Dockerfile.lambda}"

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|test|prod)$ ]]; then
  echo -e "${RED}❌ Error: Invalid environment '${ENVIRONMENT}'${NC}"
  echo "   Usage: $0 [dev|test|prod] [repository-name] [dockerfile]"
  exit 1
fi

echo -e "${BLUE}🐳 Docker Push Script${NC}"
echo "   Environment: ${ENVIRONMENT}"
echo "   Dockerfile: ${DOCKERFILE}"
echo ""

# Check if bootstrap directory exists
BOOTSTRAP_DIR="bootstrap"
if [ ! -d "$BOOTSTRAP_DIR" ]; then
  echo -e "${RED}❌ Error: Bootstrap directory not found: $BOOTSTRAP_DIR${NC}"
  echo "   Please run bootstrap first: make bootstrap-apply"
  exit 1
fi

# Read bootstrap outputs
echo -e "${BLUE}📖 Reading bootstrap outputs...${NC}"
cd "$BOOTSTRAP_DIR"

# Get project name
PROJECT_NAME=$(terraform output -raw project_name 2>/dev/null)
if [ -z "$PROJECT_NAME" ]; then
  echo -e "${RED}❌ Error: Could not read project_name from bootstrap${NC}"
  exit 1
fi

# Get AWS account ID
AWS_ACCOUNT_ID=$(terraform output -raw aws_account_id 2>/dev/null)
if [ -z "$AWS_ACCOUNT_ID" ]; then
  echo -e "${RED}❌ Error: Could not read aws_account_id from bootstrap${NC}"
  exit 1
fi

# Get AWS region
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")

# Get ECR repositories
ECR_REPOS_JSON=$(terraform output -json ecr_repositories 2>/dev/null || echo "{}")

cd ..

# Determine repository name
if [ -z "$REPOSITORY_NAME" ]; then
  # If no repository name provided, use project name
  REPOSITORY_NAME="$PROJECT_NAME"
fi

# Build full ECR repository URL
FULL_REPO_NAME="${PROJECT_NAME}-${REPOSITORY_NAME}"
ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${FULL_REPO_NAME}"

echo -e "${GREEN}✅ Configuration:${NC}"
echo "   Project: ${PROJECT_NAME}"
echo "   Repository: ${FULL_REPO_NAME}"
echo "   ECR URL: ${ECR_URL}"
echo "   AWS Account: ${AWS_ACCOUNT_ID}"
echo "   AWS Region: ${AWS_REGION}"
echo ""

# Check if Dockerfile exists
if [ ! -f "$DOCKERFILE" ]; then
  echo -e "${RED}❌ Error: Dockerfile not found: $DOCKERFILE${NC}"
  echo ""
  echo "Available Dockerfiles:"
  ls -1 Dockerfile.* 2>/dev/null || echo "  None found"
  exit 1
fi

# Login to ECR
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

# Build Docker image (always use arm64 for production)
echo -e "${BLUE}🏗️  Building Docker image for arm64 (production)...${NC}"
IMAGE_TAG="${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S)"
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "local")
ARCH="arm64"

docker build \
  --platform=linux/${ARCH} \
  -f "$DOCKERFILE" \
  -t "${FULL_REPO_NAME}:${IMAGE_TAG}-${ARCH}" \
  -t "${FULL_REPO_NAME}:${ENVIRONMENT}-${ARCH}-latest" \
  -t "${FULL_REPO_NAME}:${GIT_SHA}-${ARCH}" \
  -t "${FULL_REPO_NAME}:${IMAGE_TAG}" \
  -t "${FULL_REPO_NAME}:${ENVIRONMENT}-latest" \
  -t "${FULL_REPO_NAME}:${GIT_SHA}" \
  --build-arg ENVIRONMENT="${ENVIRONMENT}" \
  .

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Error: Docker build failed${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Docker image built successfully${NC}"
echo ""

# Tag images for ECR (with architecture tags)
echo -e "${BLUE}🏷️  Tagging images for ECR...${NC}"
docker tag "${FULL_REPO_NAME}:${IMAGE_TAG}" "${ECR_URL}:${IMAGE_TAG}"
docker tag "${FULL_REPO_NAME}:${IMAGE_TAG}-${ARCH}" "${ECR_URL}:${IMAGE_TAG}-${ARCH}"
docker tag "${FULL_REPO_NAME}:${ENVIRONMENT}-latest" "${ECR_URL}:${ENVIRONMENT}-latest"
docker tag "${FULL_REPO_NAME}:${ENVIRONMENT}-${ARCH}-latest" "${ECR_URL}:${ENVIRONMENT}-${ARCH}-latest"
docker tag "${FULL_REPO_NAME}:${GIT_SHA}" "${ECR_URL}:${GIT_SHA}"
docker tag "${FULL_REPO_NAME}:${GIT_SHA}-${ARCH}" "${ECR_URL}:${GIT_SHA}-${ARCH}"

echo -e "${GREEN}✅ Images tagged${NC}"
echo ""

# Push to ECR
echo -e "${BLUE}📤 Pushing images to ECR...${NC}"

echo "   Pushing: ${IMAGE_TAG}"
docker push "${ECR_URL}:${IMAGE_TAG}"

echo "   Pushing: ${IMAGE_TAG}-${ARCH}"
docker push "${ECR_URL}:${IMAGE_TAG}-${ARCH}"

echo "   Pushing: ${ENVIRONMENT}-latest"
docker push "${ECR_URL}:${ENVIRONMENT}-latest"

echo "   Pushing: ${ENVIRONMENT}-${ARCH}-latest"
docker push "${ECR_URL}:${ENVIRONMENT}-${ARCH}-latest"

echo "   Pushing: ${GIT_SHA}"
docker push "${ECR_URL}:${GIT_SHA}"

echo "   Pushing: ${GIT_SHA}-${ARCH}"
docker push "${ECR_URL}:${GIT_SHA}-${ARCH}"

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Error: Failed to push to ECR${NC}"
  exit 1
fi

echo ""
echo -e "${GREEN}✅ Successfully pushed images to ECR!${NC}"
echo ""
echo -e "${BLUE}📋 Image URIs (arm64 architecture):${NC}"
echo "   ${ECR_URL}:${IMAGE_TAG}"
echo "   ${ECR_URL}:${IMAGE_TAG}-${ARCH}"
echo "   ${ECR_URL}:${ENVIRONMENT}-latest"
echo "   ${ECR_URL}:${ENVIRONMENT}-${ARCH}-latest"
echo "   ${ECR_URL}:${GIT_SHA}"
echo "   ${ECR_URL}:${GIT_SHA}-${ARCH}"
echo ""
echo -e "${YELLOW}💡 Next steps:${NC}"
echo "   Use these image URIs in your Terraform configuration or deployment workflows"
echo ""
