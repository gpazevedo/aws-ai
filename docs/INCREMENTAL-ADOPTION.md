# Incremental Cloud Architecture Adoption

## Overview

This bootstrap infrastructure is designed for **incremental adoption** - start simple and grow as your needs evolve. You can begin with Lambda for serverless functions and seamlessly add App Runner or EKS later without disrupting existing resources.

---

## 🎯 Philosophy: Start Small, Scale Smart

### The Problem with Traditional Infrastructure

Traditional cloud infrastructure often forces you to choose your architecture upfront:
- ❌ Over-engineer: Build complex Kubernetes clusters from day one
- ❌ Under-engineer: Outgrow serverless and need complete rewrites
- ❌ Vendor lock-in: Architectural decisions become permanent

### Our Approach

✅ **Start simple** - Lambda for MVP and early development
✅ **Grow incrementally** - Add App Runner or EKS when needed
✅ **Keep what works** - Existing services stay untouched
✅ **Mix and match** - Run multiple compute options simultaneously

---

## 📊 Adoption Paths

### Path 1: Lambda → App Runner → EKS

```
Month 1-3: Lambda Only
├─ Fast development
├─ Low cost (~$5-20/month)
├─ Zero infrastructure management
└─ Perfect for: APIs, event processing, scheduled tasks

Month 4-6: Lambda + App Runner
├─ Add App Runner for web applications
├─ Keep Lambda for background jobs
├─ Moderate cost (~$50-100/month)
└─ Perfect for: Web frontends, long-running services

Month 7+: Lambda + App Runner + EKS
├─ Add EKS for microservices
├─ Keep Lambda for serverless functions
├─ Keep App Runner for simple web apps
├─ Higher cost (~$200-400/month)
└─ Perfect for: Complex architectures, multi-service platforms
```

### Path 2: Lambda → EKS (Skip App Runner)

```
Month 1-3: Lambda Only
└─ Build MVP with serverless

Month 4+: Lambda + EKS
├─ Add EKS for complex requirements
├─ Keep Lambda for lightweight functions
└─ Perfect for: Kubernetes expertise, complex networking
```

### Path 3: Hybrid from Start

```
Month 1+: Lambda + App Runner
├─ Lambda: Background jobs, events
├─ App Runner: User-facing APIs
└─ Perfect for: Known scaling requirements
```

---

## 🚀 Phase 1: Start with Lambda

### Initial Configuration

**File:** `bootstrap/terraform.tfvars`

```hcl
# Project Configuration
project_name = "my-app"
github_org   = "mycompany"
github_repo  = "my-app"

# Compute Stack
enable_lambda    = true   # ✅ Start here
enable_apprunner = false
enable_eks       = false

# Python Configuration
python_version = "3.13"
use_uv_builder = true
lambda_use_container_image = true
lambda_architecture = "arm64"  # Cost savings
```

### What Gets Created

```
AWS Resources:
✅ S3 State Bucket
   └─ my-app-terraform-state-123456789012

✅ GitHub OIDC Provider
   └─ Secure authentication for GitHub Actions

✅ IAM Roles (3)
   ├─ my-app-github-actions-dev
   ├─ my-app-github-actions-test (if enabled)
   └─ my-app-github-actions-prod

✅ ECR Repository
   └─ my-app (for Lambda container images)

✅ Lambda Execution Role
   └─ my-app-lambda-execution

✅ Lambda Deployment Policies
   └─ GitHub Actions can deploy Lambda functions

Total Resources: ~15
Monthly Cost: $5-20
```

### Deployment

```bash
# Deploy bootstrap
cd bootstrap/
terraform init
terraform apply

# Generate workflows
cd ..
make setup-workflows

# Deploy first Lambda
cd terraform/
terraform init -backend-config=environments/dev-backend.hcl
terraform apply -var-file=environments/dev.tfvars
```

### Use Cases: Lambda Phase

**Perfect for:**
- ✅ REST APIs (with API Gateway or Lambda Function URLs)
- ✅ Background job processing
- ✅ Scheduled tasks (cron jobs)
- ✅ Event-driven processing (S3, SNS, SQS)
- ✅ Image/video processing
- ✅ Data transformation pipelines
- ✅ Webhooks

**Example Architecture:**

```
┌─────────────────────────────────────────┐
│  Internet                               │
└────────────┬────────────────────────────┘
             │
             ▼
      ┌──────────────┐
      │ API Gateway  │
      │  or Lambda   │
      │ Function URL │
      └──────┬───────┘
             │
             ▼
      ┌──────────────┐         ┌──────────────┐
      │   Lambda     │────────▶│   DynamoDB   │
      │  (Python)    │         │   or RDS     │
      └──────┬───────┘         └──────────────┘
             │
             ▼
      ┌──────────────┐
      │      S3      │
      └──────────────┘
```

**Limitations:**
- ⚠️ 15-minute execution limit
- ⚠️ 10GB memory limit
- ⚠️ Cold start latency (~100-500ms)
- ⚠️ Concurrent execution limits (1,000 default)

### Where to Put Application Infrastructure

The bootstrap infrastructure (in `bootstrap/`) is **foundational and rarely changes**. Your application resources should be kept separate.

**Recommended structure:**

```
aws-base/
├── bootstrap/              # Bootstrap infrastructure (rarely changes)
│   ├── main.tf            # S3 state, OIDC, IAM roles, ECR, VPC
│   ├── lambda.tf          # Lambda execution roles (if enabled)
│   ├── apprunner.tf       # App Runner roles (if enabled)
│   ├── eks.tf             # EKS cluster (if enabled)
│   └── terraform.tfvars   # Bootstrap configuration
│
├── terraform/             # Application infrastructure (changes frequently)
│   ├── backend.tf         # Uses S3 backend from bootstrap outputs
│   ├── main.tf            # Provider and common config
│   │
│   ├── environments/      # Environment-specific configs
│   │   ├── dev.tfvars
│   │   ├── test.tfvars
│   │   └── prod.tfvars
│   │
│   └── resources/         # Application resources
│       ├── dynamodb.tf    # DynamoDB tables
│       ├── sqs.tf         # SQS queues
│       ├── sns.tf         # SNS topics
│       ├── api-gateway.tf # API Gateway
│       ├── lambda-functions.tf  # Lambda functions
│       ├── rds.tf         # RDS databases
│       └── s3-buckets.tf  # Application S3 buckets
│
└── backend/               # Python backend application
    ├── src/               # Application code
    ├── tests/             # Test suite
    ├── Dockerfile.lambda  # Container images
    └── pyproject.toml     # Dependencies
```

**Rule of thumb:**

| Resource Type | Location | Why |
|--------------|----------|-----|
| **S3 state bucket** | `bootstrap/` | Needed for all Terraform operations |
| **OIDC provider** | `bootstrap/` | Needed for GitHub Actions auth |
| **IAM deployment roles** | `bootstrap/` | Needed for CI/CD pipelines |
| **ECR repositories** | `bootstrap/` | Shared across all environments |
| **VPC/networking** | `bootstrap/` | Foundation for EKS/App Runner |
| **EKS cluster** | `bootstrap/` | Foundation for K8s workloads |
| **Lambda functions** | `terraform/` | Application code, changes frequently |
| **DynamoDB tables** | `terraform/` | Application data, changes frequently |
| **API Gateway** | `terraform/` | Application APIs, changes frequently |
| **RDS databases** | `terraform/` | Application data stores |
| **SQS/SNS** | `terraform/` | Application messaging |

**Example `terraform/backend.tf`:**

```hcl
# Configure backend using outputs from bootstrap
terraform {
  backend "s3" {
    # These values come from bootstrap outputs
    # Use: terraform init -backend-config=environments/dev-backend.hcl
    # Generated by: scripts/setup-terraform-backend.sh
  }
}
```

**Example `terraform/resources/lambda-functions.tf`:**

```hcl
# Reference bootstrap outputs for IAM roles, VPC, etc.
data "terraform_remote_state" "bootstrap" {
  backend = "s3"
  config = {
    bucket = var.terraform_state_bucket
    key    = "bootstrap/terraform.tfstate"
    region = var.aws_region
  }
}

resource "aws_lambda_function" "api" {
  function_name = "${var.project_name}-api-${var.environment}"
  role         = data.terraform_remote_state.bootstrap.outputs.lambda_execution_role_arn

  # ... rest of configuration
}

resource "aws_dynamodb_table" "users" {
  name         = "${var.project_name}-users-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"

  attribute {
    name = "user_id"
    type = "S"
  }
}
```

This separation keeps bootstrap stable while allowing rapid iteration on application resources.

---

## 📈 Phase 2: Add App Runner

### When to Add App Runner

**Signals you need App Runner:**
- 🔴 Need persistent connections (WebSockets, SSE)
- 🔴 Execution time > 15 minutes
- 🔴 Cold starts impacting user experience
- 🔴 Complex dependency management
- 🔴 Need custom runtime environment
- 🟡 Want simpler deployment than EKS

### Migration Process

**1. Update Configuration**

**File:** `bootstrap/terraform.tfvars`

```diff
  project_name = "my-app"
  github_org   = "mycompany"
  github_repo  = "my-app"

  enable_lambda    = true   # ✅ Keep Lambda
- enable_apprunner = false
+ enable_apprunner = true   # ✅ Add App Runner
  enable_eks       = false

+ # App Runner Configuration
+ apprunner_cpu    = 1024   # 1 vCPU
+ apprunner_memory = 2048   # 2 GB
```

**2. Review Changes**

```bash
cd bootstrap/
terraform plan

# Output shows:
# + ECR repository (for App Runner images)
# + App Runner access role (ECR pull)
# + App Runner instance role (execution)
# + IAM policy attachments
# ~ GitHub Actions roles (new policies attached)
# = S3 state bucket (UNCHANGED)
# = Lambda resources (UNCHANGED)
```

**3. Apply Changes**

```bash
terraform apply

# What happens:
# ✅ Creates App Runner IAM roles
# ✅ Attaches new policies to existing IAM roles
# ✅ Keeps all Lambda resources intact
# ✅ No downtime for existing Lambda functions
```

**4. Regenerate Workflows**

```bash
cd ..
make setup-workflows

# New workflows created:
# + deploy-apprunner-dev.yml
# + deploy-apprunner-prod.yml
# = deploy-lambda-dev.yml (still works)
# = deploy-lambda-prod.yml (still works)
```

### What Gets Added

```
New AWS Resources:
✅ App Runner Access Role
   └─ Pulls images from ECR

✅ App Runner Instance Role
   └─ Service execution permissions

✅ App Runner Deployment Policies
   └─ GitHub Actions can deploy App Runner

Updated Resources:
~ GitHub Actions IAM Roles
  └─ New App Runner policies attached
  └─ Existing Lambda policies unchanged

Total New Resources: ~5
Additional Monthly Cost: $30-80
```

### Hybrid Architecture

```
┌──────────────────────────────────────────────────────┐
│  Internet                                            │
└──────────────┬───────────────────────────────────────┘
               │
        ┌──────┴──────┐
        │             │
        ▼             ▼
  ┌──────────┐  ┌──────────────┐
  │  Lambda  │  │  App Runner  │
  │   API    │  │  Web App     │
  └────┬─────┘  └──────┬───────┘
       │               │
       └───────┬───────┘
               │
               ▼
        ┌──────────────┐
        │   Database   │
        └──────────────┘

Lambda:              App Runner:
- Background jobs    - Web frontend
- Event processing   - REST API
- Scheduled tasks    - WebSocket server
- Image processing   - Long-running jobs
```

---

## 🔧 Phase 3: Add EKS (Optional)

### When to Add EKS

**Signals you need EKS:**
- 🔴 Need Kubernetes orchestration
- 🔴 Complex microservices architecture
- 🔴 Existing Kubernetes expertise
- 🔴 Advanced networking requirements
- 🔴 Stateful workloads (databases, caches)
- 🔴 Multi-container applications
- 🟡 Need maximum control and flexibility

### Migration Process

**1. Update Configuration**

**File:** `bootstrap/terraform.tfvars`

```diff
  project_name = "my-app"
  github_org   = "mycompany"
  github_repo  = "my-app"

  enable_lambda    = true   # ✅ Keep Lambda
  enable_apprunner = true   # ✅ Keep App Runner
- enable_eks       = false
+ enable_eks       = true   # ✅ Add EKS

+ # EKS Configuration
+ eks_cluster_version     = "1.31"
+ eks_node_instance_types = ["t3.medium"]
+ eks_node_desired_size   = 2
+ eks_node_min_size       = 1
+ eks_node_max_size       = 5
+
+ # Networking (required for EKS)
+ create_vpc              = true
+ vpc_cidr                = "10.0.0.0/16"
+ vpc_availability_zones  = 2
```

**2. Review Changes**

```bash
cd bootstrap/
terraform plan

# Output shows MANY new resources:
# + VPC with subnets (public + private)
# + NAT Gateways (2)
# + Internet Gateway
# + Route Tables
# + Security Groups
# + EKS Cluster
# + EKS Node Group
# + EKS IAM Roles
# + EKS Add-ons
# ~ GitHub Actions roles (new EKS policies)
# = Lambda resources (UNCHANGED)
# = App Runner resources (UNCHANGED)
# = S3 state bucket (UNCHANGED)

# Total: ~40 new resources
```

**3. Apply Changes**

```bash
# This will take 10-15 minutes (EKS cluster creation)
terraform apply

# Monitor progress
terraform apply -auto-approve 2>&1 | tee apply.log
```

**4. Regenerate Workflows**

```bash
cd ..
make setup-workflows

# New workflows created:
# + deploy-eks-dev.yml
# + deploy-eks-prod.yml
# = deploy-lambda-dev.yml (still works)
# = deploy-lambda-prod.yml (still works)
# = deploy-apprunner-dev.yml (still works)
# = deploy-apprunner-prod.yml (still works)
```

### Complete Architecture

```
┌────────────────────────────────────────────────────────────┐
│  Internet                                                  │
└───────────────────┬────────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        │                       │
        ▼                       ▼
  ┌──────────┐          ┌──────────────┐
  │  Lambda  │          │  App Runner  │
  │   Jobs   │          │  Public API  │
  └────┬─────┘          └──────────────┘
       │
       │          ┌─────────────────────────┐
       │          │  VPC (10.0.0.0/16)      │
       │          │                         │
       │          │  ┌────────────────────┐ │
       └──────────┼─▶│  EKS Cluster       │ │
                  │  │                    │ │
                  │  │  Microservices:    │ │
                  │  │  - Auth Service    │ │
                  │  │  - Payment Service │ │
                  │  │  - Data Processing │ │
                  │  │  - Internal APIs   │ │
                  │  └──────────┬─────────┘ │
                  │             │           │
                  │             ▼           │
                  │  ┌────────────────────┐ │
                  │  │  RDS / ElastiCache │ │
                  │  │  (Private Subnet)  │ │
                  │  └────────────────────┘ │
                  └─────────────────────────┘

Lambda:              App Runner:           EKS:
- Event processing   - Public REST API     - Microservices
- Scheduled tasks    - Simple web app      - Internal services
- Image processing   - WebSocket server    - Stateful workloads
- Webhooks                                 - Complex networking
```

---

## 💰 Cost Evolution

### Phase 1: Lambda Only

```
Monthly Costs:
├─ Lambda Compute:          $2-10
├─ API Gateway:             $3-15
├─ ECR Storage:             $1-5
├─ S3 State Bucket:         $0.50
├─ CloudWatch Logs:         $1-5
└─ Total:                   $5-35/month

Best for: MVP, early stage, low traffic
```

### Phase 2: Lambda + App Runner

```
Monthly Costs:
├─ Lambda (existing):       $2-10
├─ App Runner (1 vCPU):     $30-60
├─ ECR Storage:             $2-10
├─ S3 State Bucket:         $1
├─ CloudWatch Logs:         $3-10
└─ Total:                   $40-90/month

Best for: Growing applications, moderate traffic
```

### Phase 3: Lambda + App Runner + EKS

```
Monthly Costs:
├─ Lambda (existing):       $2-10
├─ App Runner (existing):   $30-60
├─ EKS Control Plane:       $73
├─ EKS Nodes (2x t3.medium):$60
├─ NAT Gateway (2x):        $64
├─ Load Balancer:           $20-30
├─ ECR Storage:             $5-20
├─ S3 State Bucket:         $1
├─ CloudWatch Logs:         $10-20
└─ Total:                   $265-338/month

Best for: Production platforms, high traffic
```

---

## 🔄 State Management Across Phases

### Terraform State Organization

All phases share the same S3 state bucket:

```
S3 Bucket: my-app-terraform-state-123456789012
│
├── bootstrap/
│   └── terraform.tfstate
│       ├── Phase 1: Lambda resources
│       ├── Phase 2: + App Runner resources (added)
│       └── Phase 3: + EKS resources (added)
│
└── environments/
    ├── dev/
    │   └── terraform.tfstate
    │       ├── Lambda functions
    │       ├── App Runner services (added Phase 2)
    │       └── EKS workloads (added Phase 3)
    │
    └── prod/
        └── terraform.tfstate
            ├── Lambda functions
            ├── App Runner services
            └── EKS workloads
```

**Key Points:**
- ✅ One S3 bucket for all Terraform state
- ✅ Separate state files per environment
- ✅ No state migration needed between phases
- ✅ Resources from different phases coexist peacefully

---

## 🛡️ Safety Guarantees

### What NEVER Changes

When adding new compute options:

```
✅ UNCHANGED Resources:
├─ S3 state bucket
├─ GitHub OIDC provider
├─ Existing IAM role ARNs
├─ Existing Lambda functions
├─ Existing App Runner services
├─ ECR repository URLs
└─ All application data
```

### What Gets Modified

```
~ MODIFIED Resources:
└─ GitHub Actions IAM roles
   ├─ Existing policies: Unchanged
   └─ New policies: Added (for new compute option)
```

### What Gets Added

```
+ NEW Resources (per phase):
├─ Phase 2: App Runner roles, policies
└─ Phase 3: VPC, EKS cluster, node groups
```

---

## 📋 Migration Checklist

### Before Adding App Runner

- [ ] Review current Lambda usage and costs
- [ ] Identify services needing >15 min execution
- [ ] Identify services with cold start issues
- [ ] Update `bootstrap/terraform.tfvars`
- [ ] Run `terraform plan` to review changes
- [ ] Backup current state: `aws s3 cp s3://my-app-terraform-state-*/bootstrap/terraform.tfstate backup.tfstate`
- [ ] Apply changes: `terraform apply`
- [ ] Regenerate workflows: `make setup-workflows`
- [ ] Test existing Lambda deployments still work
- [ ] Deploy first App Runner service

### Before Adding EKS

- [ ] Confirm need for Kubernetes
- [ ] Review cost implications ($250-400/month minimum)
- [ ] Ensure team has Kubernetes expertise
- [ ] Plan VPC CIDR (default: 10.0.0.0/16)
- [ ] Choose availability zones (2 or 3)
- [ ] Update `bootstrap/terraform.tfvars`
- [ ] Run `terraform plan` (expect ~40 new resources)
- [ ] Backup current state
- [ ] Apply changes: `terraform apply` (10-15 min)
- [ ] Configure kubectl: `aws eks update-kubeconfig --name my-app`
- [ ] Install cluster add-ons (ALB controller, metrics server)
- [ ] Test existing Lambda & App Runner still work
- [ ] Deploy first EKS workload

---

## 🎯 Decision Matrix

### Which Compute Option for Which Use Case?

| Use Case | Lambda | App Runner | EKS |
|----------|--------|------------|-----|
| **REST API** | ✅ Best for low traffic | ✅ Best for consistent traffic | ⚠️ Overkill unless part of larger platform |
| **Background Jobs** | ✅✅ Perfect fit | ✅ If >15 min | ⚠️ Overkill |
| **Scheduled Tasks** | ✅✅ Perfect fit | ⚠️ Wasteful (always running) | ❌ Overkill |
| **WebSockets** | ❌ Not supported | ✅✅ Perfect fit | ✅ Good for complex cases |
| **Long-running** | ❌ 15 min limit | ✅✅ Perfect fit | ✅ Perfect fit |
| **Microservices** | ⚠️ Complex orchestration | ⚠️ Limited to simple cases | ✅✅ Perfect fit |
| **Stateful Apps** | ❌ Ephemeral only | ⚠️ Limited persistence | ✅✅ Full support |
| **Custom Networking** | ❌ Limited | ⚠️ Limited | ✅✅ Full control |

---

## 🚀 Quick Start Recommendations

### For New Projects

**Start with Lambda if:**
- ✅ Building an MVP
- ✅ Unsure about traffic patterns
- ✅ Want to minimize costs (<$50/month)
- ✅ Need fast iteration
- ✅ Team comfortable with serverless

**Start with Lambda + App Runner if:**
- ✅ Known requirement for persistent connections
- ✅ Existing containerized application
- ✅ Need >15 minute execution
- ✅ Budget allows ($100-200/month)

**Start with EKS only if:**
- ✅ Team has Kubernetes expertise
- ✅ Complex microservices from day one
- ✅ Budget allows ($300+/month)
- ✅ Advanced networking needed

---

## 📚 Related Documentation

- [README.md](../README.md) - Main documentation
- [docs/SCRIPTS.md](./SCRIPTS.md) - Automation scripts
- [docs/PRE-COMMIT.md](./PRE-COMMIT.md) - Code quality setup
- [bootstrap/terraform.tfvars.example](../bootstrap/terraform.tfvars.example) - Configuration examples

---

## ✅ Summary

**Key Principles:**

1. **Start Simple** - Begin with Lambda, add complexity only when needed
2. **Incremental Growth** - Add App Runner or EKS without disrupting existing services
3. **Preserve Investments** - Existing resources stay untouched during migration
4. **Mix and Match** - Run Lambda, App Runner, and EKS simultaneously
5. **Cost Aware** - Only pay for what you need, when you need it

**Migration is Safe:**
- ✅ No downtime
- ✅ No state migration
- ✅ No resource replacement
- ✅ Rollback possible (via Terraform)

**You're in Control:**
- ✅ Enable features via simple boolean flags
- ✅ Review changes before applying
- ✅ Keep what works, add what's needed
- ✅ Remove features if needed (with caution)

---

**This bootstrap is your foundation for growth - start small, scale smart!** 🚀
