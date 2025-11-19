#!/bin/bash
# =============================================================================
# Setup Pre-Commit Hooks
# =============================================================================
# Installs pre-commit hooks for automatic code quality checks
# Tools: Ruff (format + lint), Pyright (type check), pre-commit hooks
# =============================================================================

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 Setting up pre-commit hooks...${NC}"
echo ""

# Check if uv is installed
if ! command -v uv &> /dev/null; then
    echo -e "${RED}❌ Error: uv is not installed${NC}"
    echo "   Install with: curl -LsSf https://astral.sh/uv/install.sh | sh"
    echo "   Or visit: https://docs.astral.sh/uv/"
    exit 1
fi

echo -e "${GREEN}✅ uv is installed${NC}"
echo ""

# Install dev dependencies
echo -e "${BLUE}📦 Installing dev dependencies with uv...${NC}"
uv sync --no-build

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to install dependencies${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Dependencies installed${NC}"
echo ""

# Install pre-commit hooks
echo -e "${BLUE}🪝 Installing pre-commit hooks...${NC}"
uv run pre-commit install

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to install pre-commit hooks${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Pre-commit hooks installed${NC}"
echo ""

# Optional: Run on all files to check
echo -e "${BLUE}🧪 Testing pre-commit on all files (this may take a minute)...${NC}"
uv run pre-commit run --all-files || {
    echo -e "${YELLOW}⚠️  Some files needed formatting/fixing (this is normal for first run)${NC}"
    echo -e "${YELLOW}   Files have been auto-fixed. Review changes with: git diff${NC}"
}

echo ""
echo -e "${GREEN}✅ Pre-commit hooks installed successfully!${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}📋 What happens now:${NC}"
echo ""
echo -e "   Every ${GREEN}git commit${NC} will automatically:"
echo -e "   ${GREEN}1.${NC} Format code with ${BLUE}Ruff${NC}"
echo -e "   ${GREEN}2.${NC} Lint and auto-fix issues with ${BLUE}Ruff${NC}"
echo -e "   ${GREEN}3.${NC} Type check with ${BLUE}Pyright${NC}"
echo -e "   ${GREEN}4.${NC} Check for common issues (trailing spaces, large files, etc.)"
echo -e "   ${GREEN}5.${NC} Format and validate Terraform files"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}💡 Manual commands:${NC}"
echo ""
echo -e "   ${GREEN}make lint${NC}              # Check code quality"
echo -e "   ${GREEN}make lint-fix${NC}          # Auto-fix issues"
echo -e "   ${GREEN}make typecheck${NC}         # Type check with Pyright"
echo -e "   ${GREEN}make test${NC}              # Run tests"
echo -e "   ${GREEN}make pre-commit-all${NC}    # Run all hooks manually"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}📖 Tips:${NC}"
echo ""
echo -e "   • Hooks run automatically on ${GREEN}git commit${NC}"
echo -e "   • If checks fail, files are auto-fixed where possible"
echo -e "   • Re-stage fixed files: ${GREEN}git add .${NC}"
echo -e "   • Then commit again: ${GREEN}git commit${NC}"
echo -e "   • To skip hooks (emergency only): ${YELLOW}git commit --no-verify${NC}"
echo -e "   • Update hooks: ${GREEN}make pre-commit-update${NC}"
echo ""
