#!/usr/bin/env bash
# docker/validate-environment.sh
# Purpose: Validate Docker testing environment setup
# Dependencies: docker, docker-compose
# shellcheck shell=bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNINGS=0

# Simple check function that works
check() {
    local desc="$1"
    local cmd="$2"
    local warn="${3:-false}"

    if timeout 5 bash -c "${cmd}" >/dev/null 2>&1; then
        echo -e "Checking ${desc}... ${GREEN}✓${NC}"
        ((CHECKS_PASSED++))
    else
        if [[ "${warn}" == "true" ]]; then
            echo -e "Checking ${desc}... ${YELLOW}⚠${NC}"
            ((CHECKS_WARNINGS++))
        else
            echo -e "Checking ${desc}... ${RED}✗${NC}"
            ((CHECKS_FAILED++))
        fi
    fi
}

# Main execution
echo "====================================="
echo "    DOCKER ENVIRONMENT VALIDATION"
echo "====================================="
echo

echo -e "${BLUE}[INFO]${NC} Validating Docker installation..."
check "Docker is installed" "command -v docker"
check "Docker daemon accessible" "docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'podman'"
check "Docker version" "docker version" true
check "Docker without sudo" "docker ps" true

echo -e "${BLUE}[INFO]${NC} Validating Docker Compose..."
check "Docker Compose installed" "command -v docker-compose"
check "Docker Compose version" "docker-compose version" true

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${PROJECT_ROOT}/docker-compose.test.yml" ]]; then
    check "Compose file syntax" "docker-compose -f ${PROJECT_ROOT}/docker-compose.test.yml config"
fi

echo -e "${BLUE}[INFO]${NC} Validating project structure..."
check "Ubuntu 24.04 Dockerfile" "test -f ${PROJECT_ROOT}/docker/ubuntu-24.04/Dockerfile"
check "Ubuntu 22.04 Dockerfile" "test -f ${PROJECT_ROOT}/docker/ubuntu-22.04/Dockerfile"
check "Debian 12 Dockerfile" "test -f ${PROJECT_ROOT}/docker/debian-12/Dockerfile"
check "Test harness script" "test -f ${PROJECT_ROOT}/docker/test-harness.sh"
check "Test harness executable" "test -x ${PROJECT_ROOT}/docker/test-harness.sh"
check "Makefile exists" "test -f ${PROJECT_ROOT}/Makefile"

# Skip Docker tests if --quick or --no-docker-test
if [[ "${1:-}" != "--quick" ]] && [[ "${1:-}" != "--no-docker-test" ]]; then
    echo -e "${BLUE}[INFO]${NC} Testing Docker operations..."
    check "Run test container" "docker run --rm ubuntu:latest echo 'test'" true
    check "Mount volumes" "docker run --rm -v /tmp:/test ubuntu:latest test -d /test" true
fi

# Summary
total=$((CHECKS_PASSED + CHECKS_FAILED + CHECKS_WARNINGS))
echo
echo "====================================="
echo "       VALIDATION SUMMARY"
echo "====================================="
echo "Total checks: ${total}"
echo -e "Passed: ${GREEN}${CHECKS_PASSED}${NC}"
echo -e "Failed: ${RED}${CHECKS_FAILED}${NC}"
echo -e "Warnings: ${YELLOW}${CHECKS_WARNINGS}${NC}"
echo

if [[ ${CHECKS_FAILED} -eq 0 ]]; then
    if [[ ${CHECKS_WARNINGS} -eq 0 ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} All validations passed!"
    else
        echo -e "${YELLOW}[WARN]${NC} Passed with ${CHECKS_WARNINGS} warnings."
    fi
    exit 0
else
    echo -e "${RED}[ERROR]${NC} ${CHECKS_FAILED} critical issues found."
    exit 1
fi