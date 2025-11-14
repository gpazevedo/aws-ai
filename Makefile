# =============================================================================
# AWS Bootstrap Infrastructure - Makefile
# =============================================================================

.PHONY: help bootstrap-create-backend bootstrap-init bootstrap-plan bootstrap-apply bootstrap-output setup-backend sync-env

# Default target
help:
	@echo "AWS Bootstrap Infrastructure Commands"
	@echo ""
	@echo "Bootstrap (one-time setup):"
	@echo "  make bootstrap-create-backend  Create S3 bucket for Terraform state (run first!)"
	@echo "  make bootstrap-init            Initialize bootstrap Terraform"
	@echo "  make bootstrap-plan            Plan bootstrap changes"
	@echo "  make bootstrap-apply           Apply bootstrap infrastructure"
	@echo "  make bootstrap-output          Show bootstrap outputs"
	@echo "  make bootstrap-destroy         Destroy bootstrap infrastructure (DANGER!)"
	@echo ""
	@echo "Setup:"
	@echo "  make setup-backend           Generate backend configs for application Terraform"
	@echo "  make setup-app-terraform     Generate example application Terraform files"
	@echo "  make setup-workflows         Generate GitHub Actions workflows"
	@echo "  make setup-pre-commit        Setup pre-commit hooks (Ruff + Pyright)"
	@echo "  make sync-env                Sync terraform.tfvars to .env file"
	@echo ""
	@echo "Application (per environment):"
	@echo "  make app-init-dev            Initialize application Terraform for dev"
	@echo "  make app-init-test           Initialize application Terraform for test"
	@echo "  make app-init-prod           Initialize application Terraform for prod"
	@echo "  make app-plan-dev            Plan application changes for dev"
	@echo "  make app-apply-dev           Apply application infrastructure to dev"
	@echo ""
	@echo "Python Code Quality:"
	@echo "  make lint                    Check code with Ruff"
	@echo "  make lint-fix                Auto-fix issues with Ruff"
	@echo "  make typecheck               Type check with Pyright"
	@echo "  make test                    Run tests with pytest"
	@echo "  make pre-commit-all          Run all pre-commit hooks"
	@echo ""
	@echo "Docker:"
	@echo "  make docker-build            Build Docker image (arm64 by default, set ARCH=amd64 for local)"
	@echo "  make docker-build-amd64      Build Docker image for amd64 (local testing)"
	@echo "  make docker-push-dev         Push Docker image to dev ECR (always arm64)"
	@echo "  make docker-push-test        Push Docker image to test ECR (always arm64)"
	@echo "  make docker-push-prod        Push Docker image to prod ECR (always arm64)"
	@echo ""
	@echo "Utilities:"
	@echo "  make format-all              Format Python + Terraform"
	@echo "  make clean                   Remove build artifacts"
	@echo ""

# =============================================================================
# Bootstrap Commands
# =============================================================================

bootstrap-create-backend:
	@echo "🪣 Creating S3 backend for Terraform state..."
	@echo ""
	@# Read configuration from terraform.tfvars
	@PROJECT_NAME=$$(grep '^project_name' bootstrap/terraform.tfvars | cut -d'=' -f2 | cut -d'#' -f1 | tr -d ' "'); \
	AWS_REGION=$$(grep '^aws_region' bootstrap/terraform.tfvars | cut -d'=' -f2 | cut -d'#' -f1 | tr -d ' "'); \
	AWS_ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text); \
	BUCKET_NAME="$${PROJECT_NAME}-terraform-state-$${AWS_ACCOUNT_ID}"; \
	\
	echo "📋 Configuration:"; \
	echo "   Project: $${PROJECT_NAME}"; \
	echo "   Region: $${AWS_REGION}"; \
	echo "   Account: $${AWS_ACCOUNT_ID}"; \
	echo "   Bucket: $${BUCKET_NAME}"; \
	echo ""; \
	\
	if aws s3 ls "s3://$${BUCKET_NAME}" 2>/dev/null; then \
		echo "✅ S3 bucket already exists: $${BUCKET_NAME}"; \
	else \
		echo "🪣 Creating S3 bucket: $${BUCKET_NAME}"; \
		if [ "$${AWS_REGION}" = "us-east-1" ]; then \
			aws s3api create-bucket \
				--bucket "$${BUCKET_NAME}" \
				--region "$${AWS_REGION}"; \
		else \
			aws s3api create-bucket \
				--bucket "$${BUCKET_NAME}" \
				--region "$${AWS_REGION}" \
				--create-bucket-configuration LocationConstraint="$${AWS_REGION}"; \
		fi; \
		\
		echo "🔒 Enabling versioning (for state locking)..."; \
		aws s3api put-bucket-versioning \
			--bucket "$${BUCKET_NAME}" \
			--versioning-configuration Status=Enabled; \
		\
		echo "🔐 Enabling encryption..."; \
		aws s3api put-bucket-encryption \
			--bucket "$${BUCKET_NAME}" \
			--server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'; \
		\
		echo "🚫 Blocking public access..."; \
		aws s3api put-public-access-block \
			--bucket "$${BUCKET_NAME}" \
			--public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"; \
		\
		echo "✅ S3 bucket created and configured with versioning for state locking"; \
	fi; \
	\
	echo ""; \
	echo "✅ Backend ready! Next steps:"; \
	echo "   1. Run: make bootstrap-init"; \
	echo "   2. Run: make bootstrap-apply"

bootstrap-init:
	@echo "🔧 Initializing bootstrap Terraform..."
	@PROJECT_NAME=$$(grep '^project_name' bootstrap/terraform.tfvars | cut -d'=' -f2 | cut -d'#' -f1 | tr -d ' "'); \
	AWS_REGION=$$(grep '^aws_region' bootstrap/terraform.tfvars | cut -d'=' -f2 | cut -d'#' -f1 | tr -d ' "'); \
	AWS_ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text); \
	BUCKET_NAME="$${PROJECT_NAME}-terraform-state-$${AWS_ACCOUNT_ID}"; \
	\
	if [ -f bootstrap/.terraform/terraform.tfstate ]; then \
		echo "⚠️  Terraform already initialized"; \
		cd bootstrap && terraform init -reconfigure \
			-backend-config="bucket=$${BUCKET_NAME}" \
			-backend-config="region=$${AWS_REGION}"; \
	else \
		echo "📦 Initializing with S3 backend: $${BUCKET_NAME}"; \
		cd bootstrap && terraform init \
			-backend-config="bucket=$${BUCKET_NAME}" \
			-backend-config="region=$${AWS_REGION}"; \
	fi; \
	\
	echo ""; \
	echo "🔍 Checking if S3 resources need to be imported..."; \
	if aws s3 ls "s3://$${BUCKET_NAME}" 2>/dev/null; then \
		cd bootstrap && terraform state show aws_s3_bucket.terraform_state >/dev/null 2>&1 || { \
			echo "📥 Importing existing S3 bucket into Terraform state..."; \
			terraform import aws_s3_bucket.terraform_state "$${BUCKET_NAME}" || true; \
		}; \
		cd bootstrap && terraform state show aws_s3_bucket_versioning.terraform_state >/dev/null 2>&1 || { \
			echo "📥 Importing bucket versioning..."; \
			terraform import aws_s3_bucket_versioning.terraform_state "$${BUCKET_NAME}" || true; \
		}; \
		cd bootstrap && terraform state show aws_s3_bucket_server_side_encryption_configuration.terraform_state >/dev/null 2>&1 || { \
			echo "📥 Importing bucket encryption..."; \
			terraform import aws_s3_bucket_server_side_encryption_configuration.terraform_state "$${BUCKET_NAME}" || true; \
		}; \
		cd bootstrap && terraform state show aws_s3_bucket_public_access_block.terraform_state >/dev/null 2>&1 || { \
			echo "📥 Importing bucket public access block..."; \
			terraform import aws_s3_bucket_public_access_block.terraform_state "$${BUCKET_NAME}" || true; \
		}; \
		echo "✅ S3 import check complete!"; \
	fi; \
	\
	echo ""; \
	echo "🔍 Checking if GitHub Actions OIDC provider needs to be imported..."; \
	OIDC_ARN=$$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')].Arn" --output text 2>/dev/null || echo ""); \
	if [ -n "$${OIDC_ARN}" ]; then \
		echo "   Found existing OIDC provider: $${OIDC_ARN}"; \
		cd bootstrap && terraform state show aws_iam_openid_connect_provider.github_actions >/dev/null 2>&1 || { \
			echo "📥 Importing existing GitHub Actions OIDC provider into Terraform state..."; \
			terraform import aws_iam_openid_connect_provider.github_actions "$${OIDC_ARN}" || true; \
		}; \
		echo "✅ OIDC provider import check complete!"; \
	else \
		echo "   No existing OIDC provider found - Terraform will create it"; \
	fi

bootstrap-plan:
	@echo "📋 Planning bootstrap changes..."
	cd bootstrap && terraform plan

bootstrap-apply:
	@echo "🚀 Applying bootstrap infrastructure..."
	cd bootstrap && terraform apply
	@echo ""
	@echo "✅ Bootstrap complete! Next steps:"
	@echo "   make setup-backend"
	@echo "   make setup-workflows"

bootstrap-output:
	@echo "📊 Bootstrap outputs:"
	cd bootstrap && terraform output

bootstrap-destroy:
	@echo "⚠️  WARNING: This will destroy ALL bootstrap infrastructure!"
	@echo "This includes:"
	@echo "  - S3 state bucket (and all state files)"
	@echo "  - GitHub Actions IAM roles"
	@echo "  - ECR repositories (and all images)"
	@echo "  - EKS cluster (if created)"
	@echo "  - VPC and networking (if created)"
	@echo ""
	@read -p "Are you ABSOLUTELY sure? Type 'yes' to continue: " confirm && \
	if [ "$$confirm" = "yes" ]; then \
		cd bootstrap && terraform destroy; \
	else \
		echo "Cancelled."; \
	fi

# =============================================================================
# Setup Commands
# =============================================================================

setup-backend:
	@echo "📝 Generating Terraform backend configurations..."
	./scripts/setup-terraform-backend.sh

setup-app-terraform:
	@echo "🏗️  Generating example application Terraform files..."
	./scripts/setup-application-terraform.sh

setup-workflows:
	@echo "🔄 Generating GitHub Actions workflows..."
	./scripts/generate-workflows.sh

sync-env:
	@echo "🔄 Syncing terraform.tfvars to .env file..."
	uv run python scripts/sync-tfvars-to-env.py

# =============================================================================
# Application Commands - Dev Environment
# =============================================================================

app-init-dev:
	@echo "🔧 Initializing Terraform for dev environment..."
	cd terraform && terraform init -backend-config=environments/dev-backend.hcl

app-plan-dev:
	@echo "📋 Planning changes for dev environment..."
	cd terraform && terraform plan -var-file=environments/dev.tfvars

app-apply-dev:
	@echo "🚀 Applying changes to dev environment..."
	cd terraform && terraform apply -var-file=environments/dev.tfvars

app-destroy-dev:
	@echo "⚠️  Destroying dev environment infrastructure..."
	cd terraform && terraform destroy -var-file=environments/dev.tfvars

# =============================================================================
# Application Commands - Test Environment
# =============================================================================

app-init-test:
	@echo "🔧 Initializing Terraform for test environment..."
	cd terraform && terraform init -backend-config=environments/test-backend.hcl -reconfigure

app-plan-test:
	@echo "📋 Planning changes for test environment..."
	cd terraform && terraform plan -var-file=environments/test.tfvars

app-apply-test:
	@echo "🚀 Applying changes to test environment..."
	cd terraform && terraform apply -var-file=environments/test.tfvars

# =============================================================================
# Application Commands - Prod Environment
# =============================================================================

app-init-prod:
	@echo "🔧 Initializing Terraform for prod environment..."
	cd terraform && terraform init -backend-config=environments/prod-backend.hcl -reconfigure

app-plan-prod:
	@echo "📋 Planning changes for prod environment..."
	cd terraform && terraform plan -var-file=environments/prod.tfvars

app-apply-prod:
	@echo "🚀 Applying changes to prod environment..."
	cd terraform && terraform apply -var-file=environments/prod.tfvars

# =============================================================================
# Docker Commands
# =============================================================================

docker-build:
	@echo "🐳 Building Docker image with uv..."
	@if [ -f bootstrap/terraform.tfvars ]; then \
		PROJECT_NAME=$$(grep '^project_name' bootstrap/terraform.tfvars | cut -d'=' -f2 | cut -d'#' -f1 | tr -d ' "'); \
	else \
		PROJECT_NAME="myapp"; \
	fi; \
	ARCH=$${ARCH:-arm64}; \
	DOCKERFILE=$${DOCKERFILE:-Dockerfile.lambda}; \
	echo "   Project: $${PROJECT_NAME}"; \
	echo "   Architecture: $${ARCH}"; \
	echo "   Dockerfile: backend/$${DOCKERFILE}"; \
	docker build \
		--platform=linux/$${ARCH} \
		-t "$${PROJECT_NAME}:$${ARCH}-latest" \
		-t "$${PROJECT_NAME}:latest" \
		-f backend/$${DOCKERFILE} \
		backend/

docker-build-amd64:
	@echo "🐳 Building Docker image for amd64 (local testing)..."
	@$(MAKE) docker-build ARCH=amd64

docker-push-dev:
	@echo "📤 Pushing Docker image to dev ECR..."
	./scripts/docker-push.sh dev

docker-push-test:
	@echo "📤 Pushing Docker image to test ECR..."
	./scripts/docker-push.sh test

docker-push-prod:
	@echo "📤 Pushing Docker image to prod ECR..."
	./scripts/docker-push.sh prod

# =============================================================================
# Python Code Quality Commands
# =============================================================================

setup-pre-commit:
	@echo "🔧 Setting up pre-commit hooks..."
	./scripts/setup-pre-commit.sh

lint:
	@echo "🔍 Checking code quality with Ruff..."
	cd backend && uv run ruff check .

lint-fix:
	@echo "🔧 Auto-fixing issues with Ruff..."
	cd backend && uv run ruff check --fix .
	cd backend && uv run ruff format .

format-python:
	@echo "🎨 Formatting Python code with Ruff..."
	cd backend && uv run ruff format .

typecheck:
	@echo "🔎 Type checking with Pyright..."
	cd backend && uv run pyright .

test:
	@echo "🧪 Running tests..."
	cd backend && uv run pytest . -v --cov=. --cov-report=term-missing

test-watch:
	@echo "👀 Running tests in watch mode..."
	cd backend && uv run pytest-watch . -v

pre-commit-all:
	@echo "🪝 Running pre-commit on all files..."
	cd backend && uv run pre-commit run --all-files

pre-commit-update:
	@echo "⬆️  Updating pre-commit hooks..."
	cd backend && uv run pre-commit autoupdate

# =============================================================================
# Terraform Utility Commands
# =============================================================================

format-terraform:
	@echo "🎨 Formatting Terraform files..."
	terraform fmt -recursive bootstrap/
	terraform fmt -recursive terraform/

format-all: format-terraform format-python
	@echo "✅ Formatted all files"

validate:
	@echo "✅ Validating Terraform configurations..."
	cd bootstrap && terraform validate
	cd terraform && terraform validate

clean:
	@echo "🧹 Cleaning artifacts..."
	@echo "   Cleaning Terraform..."
	find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@echo "   Cleaning Python..."
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".ruff_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name ".coverage" -delete 2>/dev/null || true
	find . -type d -name "htmlcov" -exec rm -rf {} + 2>/dev/null || true
	@echo "✅ Done!"
