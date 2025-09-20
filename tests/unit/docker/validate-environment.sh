#!/usr/bin/env bash
# Simple validation script that doesn't hang

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "====================================="
echo "    DOCKER ENVIRONMENT VALIDATION"
echo "====================================="
echo

# Check Docker
if command -v docker >/dev/null 2>&1; then
    echo -e "Docker installed: ${GREEN}✓${NC}"
else
    echo -e "Docker installed: ${RED}✗${NC}"
fi

# Check project structure
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "${PROJECT_ROOT}/docker/ubuntu-24.04/Dockerfile" ]]; then
    echo -e "Ubuntu 24.04 Dockerfile: ${GREEN}✓${NC}"
else
    echo -e "Ubuntu 24.04 Dockerfile: ${RED}✗${NC}"
fi

if [[ -f "${PROJECT_ROOT}/docker/test-harness.sh" ]]; then
    echo -e "Test harness script: ${GREEN}✓${NC}"
else
    echo -e "Test harness script: ${RED}✗${NC}"
fi

if [[ -f "${PROJECT_ROOT}/Makefile" ]]; then
    echo -e "Makefile exists: ${GREEN}✓${NC}"
else
    echo -e "Makefile exists: ${RED}✗${NC}"
fi

echo
echo "====================================="
echo "       VALIDATION COMPLETE"
echo "====================================="

exit 0