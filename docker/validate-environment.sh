#!/usr/bin/env bash
# docker/validate-environment.sh
# Purpose: Validate Docker testing environment setup
# Dependencies: docker, docker-compose
# Inputs: Optional distro specification
# Outputs: Validation results and recommendations
# shellcheck shell=bash

set -euo pipefail

# Script metadata
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

# Validation counters
CHECKS_TOTAL=0
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNINGS=0

# Run a validation check
run_check() {
    local description="$1"
    local command="$2"
    local is_warning="${3:-false}"

    ((CHECKS_TOTAL++))

    echo -n "Checking ${description}... "

    if eval "${command}" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        ((CHECKS_PASSED++))
        return 0
    else
        if [[ "${is_warning}" == "true" ]]; then
            echo -e "${YELLOW}⚠${NC}"
            ((CHECKS_WARNINGS++))
        else
            echo -e "${RED}✗${NC}"
            ((CHECKS_FAILED++))
        fi
        return 1
    fi
}

# Validate Docker installation
validate_docker() {
    log_info "Validating Docker installation..."

    run_check "Docker is installed" "command -v docker"
    run_check "Docker daemon is running" "docker info"
    run_check "Docker version is recent" "docker version --format '{{.Server.Version}}' | grep -E '^[2-9][0-9]|^1[3-9]'"
    run_check "User can run Docker without sudo" "docker ps"

    # Check Docker memory allocation
    local docker_memory
    docker_memory=$(docker system info --format '{{.MemTotal}}' 2>/dev/null || echo "0")
    if [[ "${docker_memory}" -gt 2147483648 ]]; then  # 2GB in bytes
        log_success "Docker has sufficient memory allocated ($(( docker_memory / 1073741824 ))GB)"
        ((CHECKS_PASSED++))
    else
        log_warn "Docker may have insufficient memory allocated. Consider increasing to 4GB+"
        ((CHECKS_WARNINGS++))
    fi
    ((CHECKS_TOTAL++))
}

# Validate Docker Compose
validate_docker_compose() {
    log_info "Validating Docker Compose..."

    run_check "Docker Compose is installed" "command -v docker-compose"
    run_check "Docker Compose version is recent" "docker-compose version --short | grep -E '^[2-9]|^1\.[2-9][0-9]'"

    # Check if compose file exists
    if [[ -f "${PROJECT_ROOT}/docker-compose.test.yml" ]]; then
        run_check "Docker Compose file syntax is valid" "docker-compose -f ${PROJECT_ROOT}/docker-compose.test.yml config"
    else
        log_error "Docker Compose test file not found: ${PROJECT_ROOT}/docker-compose.test.yml"
        ((CHECKS_FAILED++))
        ((CHECKS_TOTAL++))
    fi
}

# Validate project structure
validate_project_structure() {
    log_info "Validating project structure..."

    local required_files=(
        "docker/ubuntu-24.04/Dockerfile"
        "docker/ubuntu-22.04/Dockerfile"
        "docker/debian-12/Dockerfile"
        "docker-compose.test.yml"
        "docker/test-harness.sh"
        "Makefile"
    )

    for file in "${required_files[@]}"; do
        run_check "Required file exists: ${file}" "test -f ${PROJECT_ROOT}/${file}"
    done

    # Check if test-harness.sh is executable
    run_check "Test harness is executable" "test -x ${PROJECT_ROOT}/docker/test-harness.sh"

    # Check for .dockerignore
    run_check ".dockerignore exists" "test -f ${PROJECT_ROOT}/docker/.dockerignore" true
}

# Validate Dockerfile syntax
validate_dockerfiles() {
    log_info "Validating Dockerfile syntax..."

    local dockerfiles=(
        "docker/ubuntu-24.04/Dockerfile"
        "docker/ubuntu-22.04/Dockerfile"
        "docker/debian-12/Dockerfile"
    )

    for dockerfile in "${dockerfiles[@]}"; do
        if [[ -f "${PROJECT_ROOT}/${dockerfile}" ]]; then
            # Use hadolint if available, otherwise basic checks
            if command -v hadolint >/dev/null 2>&1; then
                run_check "Dockerfile lint: ${dockerfile}" "hadolint ${PROJECT_ROOT}/${dockerfile}" true
            else
                run_check "Dockerfile syntax: ${dockerfile}" "docker build --no-cache -f ${PROJECT_ROOT}/${dockerfile} ${PROJECT_ROOT}/docker/$(dirname ${dockerfile#docker/}) -t test-validation:$(basename $(dirname ${dockerfile#docker/})) --dry-run" true
            fi
        fi
    done
}

# Validate system resources
validate_system_resources() {
    log_info "Validating system resources..."

    # Check available disk space
    local available_space
    available_space=$(df "${PROJECT_ROOT}" | awk 'NR==2 {print $4}')
    if [[ "${available_space}" -gt 5242880 ]]; then  # 5GB in KB
        log_success "Sufficient disk space available ($(( available_space / 1048576 ))GB)"
        ((CHECKS_PASSED++))
    else
        log_warn "Low disk space. Docker builds may fail. Available: $(( available_space / 1048576 ))GB"
        ((CHECKS_WARNINGS++))
    fi
    ((CHECKS_TOTAL++))

    # Check available memory
    local available_memory
    available_memory=$(free -m | awk 'NR==2{print $7}')
    if [[ "${available_memory}" -gt 2048 ]]; then  # 2GB
        log_success "Sufficient memory available (${available_memory}MB)"
        ((CHECKS_PASSED++))
    else
        log_warn "Low memory available. Consider closing other applications. Available: ${available_memory}MB"
        ((CHECKS_WARNINGS++))
    fi
    ((CHECKS_TOTAL++))

    # Check CPU cores
    local cpu_cores
    cpu_cores=$(nproc)
    if [[ "${cpu_cores}" -gt 1 ]]; then
        log_success "Multiple CPU cores available (${cpu_cores})"
        ((CHECKS_PASSED++))
    else
        log_warn "Single CPU core detected. Parallel builds may be slower."
        ((CHECKS_WARNINGS++))
    fi
    ((CHECKS_TOTAL++))
}

# Validate network connectivity
validate_network() {
    log_info "Validating network connectivity..."

    run_check "Internet connectivity" "ping -c 1 8.8.8.8" true
    run_check "DNS resolution" "nslookup google.com" true
    run_check "HTTPS connectivity" "curl -s --connect-timeout 5 https://www.google.com" true

    # Check if Docker can pull base images
    run_check "Can pull Ubuntu 24.04" "docker pull ubuntu:24.04 --quiet" true
    run_check "Can pull Ubuntu 22.04" "docker pull ubuntu:22.04 --quiet" true
    run_check "Can pull Debian 12" "docker pull debian:12 --quiet" true
}

# Test basic Docker operations
test_docker_operations() {
    log_info "Testing basic Docker operations..."

    # Test container creation and execution
    run_check "Can create and run container" "docker run --rm ubuntu:latest echo 'test'"
    run_check "Can mount volumes" "docker run --rm -v /tmp:/test ubuntu:latest test -d /test"

    # Test Docker Compose operations
    if [[ -f "${PROJECT_ROOT}/docker-compose.test.yml" ]]; then
        run_check "Can validate compose file" "docker-compose -f ${PROJECT_ROOT}/docker-compose.test.yml config -q"
    fi
}

# Clean up test resources
cleanup_validation() {
    log_info "Cleaning up validation resources..."

    # Remove any test images created during validation
    docker images -q test-validation:* 2>/dev/null | xargs -r docker rmi -f >/dev/null 2>&1 || true

    # Prune stopped containers
    docker container prune -f >/dev/null 2>&1 || true
}

# Show validation summary
show_summary() {
    echo
    echo "====================================="
    echo "       VALIDATION SUMMARY"
    echo "====================================="
    echo "Total checks: ${CHECKS_TOTAL}"
    echo -e "Passed: ${GREEN}${CHECKS_PASSED}${NC}"
    echo -e "Failed: ${RED}${CHECKS_FAILED}${NC}"
    echo -e "Warnings: ${YELLOW}${CHECKS_WARNINGS}${NC}"
    echo

    if [[ ${CHECKS_FAILED} -eq 0 ]]; then
        if [[ ${CHECKS_WARNINGS} -eq 0 ]]; then
            log_success "All validations passed! Environment is ready for testing."
        else
            log_warn "Validations passed with ${CHECKS_WARNINGS} warnings. Review warnings above."
        fi
        return 0
    else
        log_error "Validation failed! ${CHECKS_FAILED} critical issues found."
        return 1
    fi
}

# Show recommendations
show_recommendations() {
    echo
    echo "====================================="
    echo "      RECOMMENDATIONS"
    echo "====================================="

    if [[ ${CHECKS_FAILED} -gt 0 ]]; then
        echo "To fix critical issues:"
        echo "1. Ensure Docker is installed and running"
        echo "2. Ensure Docker Compose is installed"
        echo "3. Verify user permissions for Docker"
        echo "4. Check that all required files exist"
        echo
    fi

    if [[ ${CHECKS_WARNINGS} -gt 0 ]]; then
        echo "To address warnings:"
        echo "1. Increase Docker memory allocation (4GB+ recommended)"
        echo "2. Free up disk space (10GB+ recommended for builds)"
        echo "3. Install hadolint for Dockerfile linting: 'brew install hadolint' or 'apt install hadolint'"
        echo "4. Ensure stable internet connection for image pulls"
        echo
    fi

    echo "Optional improvements:"
    echo "1. Install bats for advanced testing: 'npm install -g bats'"
    echo "2. Install shellcheck for script validation: 'apt install shellcheck'"
    echo "3. Consider using Docker BuildKit for faster builds: 'export DOCKER_BUILDKIT=1'"
    echo
}

# Show usage
show_usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Validate Docker testing environment for machine-rites project.

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -q, --quiet             Suppress detailed output
    --no-network           Skip network connectivity tests
    --no-cleanup           Skip cleanup after validation
    --quick                Run only essential checks

EXAMPLES:
    ${SCRIPT_NAME}                    # Full validation
    ${SCRIPT_NAME} --quick            # Quick validation
    ${SCRIPT_NAME} --no-network       # Skip network tests

EOF
}

# Main validation function
main() {
    local network_tests=true
    local cleanup_tests=true
    local quick_mode=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            -q|--quiet)
                exec 2>/dev/null
                shift
                ;;
            --no-network)
                network_tests=false
                shift
                ;;
            --no-cleanup)
                cleanup_tests=false
                shift
                ;;
            --quick)
                quick_mode=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    echo "====================================="
    echo "    DOCKER ENVIRONMENT VALIDATION"
    echo "====================================="
    echo

    # Run validation steps
    validate_docker
    validate_docker_compose
    validate_project_structure

    if [[ "${quick_mode}" == "false" ]]; then
        validate_dockerfiles
        validate_system_resources

        if [[ "${network_tests}" == "true" ]]; then
            validate_network
        fi

        test_docker_operations
    fi

    # Cleanup if requested
    if [[ "${cleanup_tests}" == "true" ]]; then
        cleanup_validation
    fi

    # Show results
    show_summary
    local exit_code=$?

    show_recommendations

    exit ${exit_code}
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi