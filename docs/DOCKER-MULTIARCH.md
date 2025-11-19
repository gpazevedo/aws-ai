# Docker Multi-Architecture Support

This project supports building Docker images for both **arm64** (AWS Graviton2) and **amd64** (x86_64) architectures.

## Overview

- **arm64**: Production deployment to AWS Lambda (Graviton2), App Runner, and EKS
- **amd64**: Local testing on Intel/AMD x86_64 machines
- **Production**: Always uses arm64 for cost efficiency and performance
- **Local Development**: Use amd64 if your machine is x86_64-based

## Understanding Build vs Runtime Architecture

### Key Concept: Python is Different from Compiled Languages

**For compiled languages (Go, Rust, C++):**
- Builder stage runs on **BUILD platform** (host CPU) - fast native compilation
- Runtime stage uses **TARGET platform** (deployment CPU)
- Binary is compiled once, copied to runtime

**For Python (interpreted + native extensions):**
- Builder stage MUST run on **TARGET platform** (deployment CPU)
- Runtime stage uses same **TARGET platform**
- Python packages with C extensions (numpy, pillow, cryptography) must be compiled for TARGET architecture

### Why Our Dockerfiles Use TARGETPLATFORM for Both Stages

```dockerfile
# Build stage - uses TARGET platform
FROM --platform=$TARGETPLATFORM python:3.13-slim AS builder
RUN uv sync  # Installs/compiles packages for TARGET architecture

# Runtime stage - uses TARGET platform
FROM --platform=$TARGETPLATFORM python:3.13-slim
COPY --from=builder /app .  # Python code + compiled extensions for TARGET
```

**Why this approach?**
1. Python is interpreted - `.py` files don't need compilation
2. BUT packages like `numpy`, `pillow`, `cryptography` have C extensions
3. These extensions must match the TARGET architecture (where Python runs)
4. Using BUILDPLATFORM would compile extensions for the wrong CPU

**Performance consideration:**
- Building on BUILDPLATFORM (host) is faster but produces wrong binaries
- Building on TARGETPLATFORM may use emulation (slower) but produces correct binaries
- For production, correctness > build speed

### Comparison: Python vs Compiled Languages

| Aspect | Compiled (Go/Rust) | Python |
|--------|-------------------|---------|
| **Builder Platform** | BUILDPLATFORM (host) | TARGETPLATFORM (deployment) |
| **Builder Speed** | Fast (native) | May be slow (emulation) |
| **Builder Output** | CPU-specific binary | Arch-specific .so files + .py |
| **Runtime Platform** | TARGETPLATFORM | TARGETPLATFORM |
| **Why Different?** | Compile once, run anywhere | C extensions must match runtime |

**Example Scenario: Building arm64 on x86_64 host**

```dockerfile
# Go - Fast build (correct approach)
FROM --platform=$BUILDPLATFORM golang:1.21 AS builder
RUN GOARCH=arm64 go build -o app  # Cross-compiles to arm64
FROM --platform=$TARGETPLATFORM alpine
COPY --from=builder /app .  # arm64 binary

# Python - Slower build (but correct)
FROM --platform=$TARGETPLATFORM python:3.13-slim AS builder
RUN uv sync  # Uses emulation to compile C extensions for arm64
FROM --platform=$TARGETPLATFORM python:3.13-slim
COPY --from=builder /app .  # Python + arm64 C extensions
```

## Architecture Strategy

### Dockerfile.lambda

Uses platform-aware multi-arch base images (same as apprunner/eks):

```dockerfile
ARG TARGETPLATFORM
FROM --platform=$TARGETPLATFORM public.ecr.aws/lambda/python:3.13
```

**How it works:**
- `public.ecr.aws/lambda/python:3.13` is a **multi-platform manifest** supporting both amd64 and arm64
- `FROM --platform=$TARGETPLATFORM` forces Docker to pull the correct architecture variant
- When building with `--platform=linux/arm64`: Pulls the arm64 variant
- When building with `--platform=linux/amd64`: Pulls the amd64 variant
- Without `--platform=$TARGETPLATFORM`, Docker would pull based on the **host** architecture, not the target

### Dockerfile.apprunner & Dockerfile.eks

Uses platform-aware multi-arch base images:

```dockerfile
ARG TARGETPLATFORM
FROM --platform=$TARGETPLATFORM python:3.13-slim
```

**How it works:**
- `python:3.13-slim` is a **multi-platform manifest** supporting both amd64 and arm64
- `FROM --platform=$TARGETPLATFORM` forces Docker to pull the correct architecture variant
- Without `--platform=$TARGETPLATFORM`, Docker would pull based on the **host** architecture, not the target

**Why `FROM --platform=$TARGETPLATFORM` is required:**

The `python:3.13-slim` image is a multi-arch manifest, not a single image. When you pull it:
- On an x86_64 host: Docker pulls the amd64 variant by default
- On an ARM host: Docker pulls the arm64 variant by default

Using `FROM --platform=$TARGETPLATFORM` ensures the correct variant is pulled for cross-compilation.

## Building Images

### Production (arm64)

```bash
# Using Makefile (recommended)
make docker-build  # Defaults to arm64

# Direct docker command
cd backend
docker build --platform=linux/arm64 \
  --build-arg SERVICE_FOLDER=api \
  -t myapp:arm64-latest \
  -f Dockerfile.lambda .
```

### Local Testing (amd64)

```bash
# Using Makefile (recommended)
make docker-build-amd64

# Or specify architecture
make docker-build ARCH=amd64

# Direct docker command
cd backend
docker build --platform=linux/amd64 \
  --build-arg SERVICE_FOLDER=api \
  -t myapp:amd64-latest \
  -f Dockerfile.lambda .
```

### Specifying Dockerfile

```bash
# Build App Runner image for arm64
make docker-build DOCKERFILE=Dockerfile.apprunner

# Build EKS image for amd64
make docker-build ARCH=amd64 DOCKERFILE=Dockerfile.eks
```

## Pushing to ECR

Production deployments **always** push arm64 images:

```bash
# Push to dev environment (builds and pushes arm64)
make docker-push-dev

# Push to prod environment (builds and pushes arm64)
make docker-push-prod

# Direct script usage
./scripts/docker-push.sh dev app Dockerfile.lambda
```

**Tags created:**
- `dev-20250116-143000` (no suffix, implicit arm64)
- `dev-20250116-143000-arm64` (explicit architecture)
- `dev-arm64-latest`
- `dev-latest` (no suffix, implicit arm64)
- `abc1234-arm64` (git SHA)
- `abc1234` (git SHA, no suffix, implicit arm64)

## Docker BuildKit Variables

Docker BuildKit automatically provides these build arguments:

| Variable | Description | Example |
|----------|-------------|---------|
| `BUILDPLATFORM` | Platform performing the build | `linux/amd64` |
| `BUILDARCH` | Architecture performing the build | `amd64` |
| `TARGETPLATFORM` | Platform being built for | `linux/arm64` |
| `TARGETARCH` | Architecture being built for | `arm64` |

**Usage in Dockerfiles:**

```dockerfile
# Access TARGETARCH (automatically set by BuildKit)
ARG TARGETARCH
FROM public.ecr.aws/lambda/python:3.13-${TARGETARCH}

# Access TARGETPLATFORM (automatically set by BuildKit)
ARG TARGETPLATFORM
FROM --platform=$TARGETPLATFORM python:3.13-slim
```

## Why Multi-Architecture?

### Benefits of arm64 (Graviton2) in Production:
- **Cost**: Up to 20% cheaper than x86_64 (amd64)
- **Performance**: Better price-performance ratio
- **AWS Native**: Optimized for AWS Lambda, App Runner, EKS

### Benefits of amd64 for Local Development:
- **Compatibility**: Most development machines are x86_64
- **Testing**: Test before deploying to production
- **Debugging**: Easier to debug on local architecture

## Common Issues

### Issue: "exec format error" when building arm64 on amd64 host

**Cause**: Trying to run arm64 binaries on an amd64 host without emulation.

**Solution**: Use Docker BuildX with QEMU emulation:
```bash
# Install QEMU emulators (one-time setup)
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

# Create buildx builder (one-time setup)
docker buildx create --name multiarch --use
docker buildx inspect --bootstrap

# Build with buildx
docker buildx build --platform=linux/arm64 \
  --build-arg SERVICE_FOLDER=api \
  -t myapp:arm64-latest \
  -f backend/Dockerfile.lambda \
  --load \
  backend/
```

**Alternative**: Build arm64 images on arm64 hardware:
- AWS EC2 arm64 instance (t4g, c7g, etc.)
- Apple Silicon Mac (M1/M2/M3) - native arm64
- GitHub Actions with arm64 runners

### Issue: "image with reference was found but does not match the specified platform"

**Cause**: Building without `--platform` flag on a different architecture host.

**Solution**: Always use `--platform` flag or the Makefile commands:
```bash
make docker-build              # arm64
make docker-build-amd64        # amd64
```

### Issue: Wrong architecture after build

**Verify built image architecture:**
```bash
docker inspect myapp:arm64-latest | grep Architecture
# Should show: "Architecture": "arm64"

docker inspect myapp:amd64-latest | grep Architecture
# Should show: "Architecture": "amd64"
```

### Issue: Performance issues on Apple Silicon (M1/M2/M3)

Apple Silicon Macs are arm64-based. Building arm64 images is **native** and fast:

```bash
# Fast on Apple Silicon (native)
make docker-build

# Slower on Apple Silicon (emulation required)
make docker-build-amd64
```

On Intel Macs, the opposite is true - amd64 is native, arm64 requires emulation.

## Best Practices

1. **Production**: Always use arm64
   ```bash
   make docker-push-dev
   make docker-push-prod
   ```

2. **Local Testing**: Use your host architecture
   ```bash
   # On Apple Silicon (M1/M2/M3)
   make docker-build  # Use arm64 (native)

   # On Intel Mac or x86_64 Linux
   make docker-build-amd64  # Use amd64 (native)
   ```

3. **CI/CD**: Always build arm64 for production
   ```yaml
   # GitHub Actions
   - name: Build Docker image
     run: make docker-build  # Builds arm64
   ```

4. **Multi-Platform Builds**: Use docker buildx for building both simultaneously
   ```bash
   docker buildx build --platform linux/amd64,linux/arm64 \
     --build-arg SERVICE_FOLDER=api \
     -t myapp:latest \
     -f backend/Dockerfile.lambda \
     backend/
   ```

## References

- [Docker BuildKit Documentation](https://docs.docker.com/build/buildkit/)
- [Multi-platform images](https://docs.docker.com/build/building/multi-platform/)
- [AWS Lambda on Graviton2](https://aws.amazon.com/blogs/aws/aws-lambda-functions-powered-by-aws-graviton2-processor-run-your-functions-on-arm-and-get-up-to-34-better-price-performance/)
- [AWS App Runner on Graviton2](https://aws.amazon.com/about-aws/whats-new/2023/04/aws-app-runner-aws-graviton2-processor/)
