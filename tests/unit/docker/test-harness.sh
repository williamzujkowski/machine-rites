#!/usr/bin/env bash
# docker/test-harness.sh
# Purpose: Comprehensive test harness runner for Docker-based testing
# Dependencies: docker, docker-compose
# Inputs: Distro selection, test type, specific test files
# Outputs: Test results, coverage reports, artifacts
# shellcheck shell=bash

set -euo pipefail

# Script metadata
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuration
readonly DOCKER_COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.test.yml"
readonly TEST_RESULTS_DIR="${PROJECT_ROOT}/test-results"
readonly LOG_DIR="${PROJECT_ROOT}/logs"

# Supported distros
readonly -a SUPPORTED_DISTROS=("ubuntu-24" "ubuntu-22" "debian-12")

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

# Error handling
die() {
    log_error "$*"
    exit 1
}

# Show usage information
show_usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS] COMMAND [ARGS]

COMMANDS:
    build [DISTRO]           Build Docker images for testing
    test [DISTRO] [TEST]     Run tests in specified distro
    shell [DISTRO]           Open interactive shell in container
    validate [DISTRO]        Run validation checks
    clean                    Clean up containers and images
    status                   Show container status
    logs [DISTRO]            Show container logs
    health                   Check container health
    all                      Run full test suite

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -q, --quiet             Suppress non-error output
    -d, --detach            Run containers in detached mode
    -f, --force             Force rebuild/cleanup
    --no-cache              Build without using cache
    --parallel              Run tests in parallel

DISTROS:
    ubuntu-24               Ubuntu 24.04 LTS
    ubuntu-22               Ubuntu 22.04 LTS
    debian-12               Debian 12 (Bookworm)
    all                     All supported distros

EXAMPLES:
    ${SCRIPT_NAME} build ubuntu-24
    ${SCRIPT_NAME} test ubuntu-24 bootstrap
    ${SCRIPT_NAME} shell debian-12
    ${SCRIPT_NAME} validate all
    ${SCRIPT_NAME} all --parallel

EOF
}

# Validate distro selection
validate_distro() {
    local distro="$1"

    if [[ "${distro}" == "all" ]]; then
        return 0
    fi

    for supported in "${SUPPORTED_DISTROS[@]}"; do
        if [[ "${distro}" == "${supported}" ]]; then
            return 0
        fi
    done

    die "Unsupported distro: ${distro}. Supported: ${SUPPORTED_DISTROS[*]} all"
}

# Setup environment
setup_environment() {
    # Create necessary directories
    mkdir -p "${TEST_RESULTS_DIR}" "${LOG_DIR}"

    # Change to project root
    cd "${PROJECT_ROOT}"

    # Verify docker-compose file exists
    [[ -f "${DOCKER_COMPOSE_FILE}" ]] || die "Docker compose file not found: ${DOCKER_COMPOSE_FILE}"

    log_info "Environment setup complete"
}

# Build Docker images
build_images() {
    local distro="${1:-all}"
    local build_args=()

    if [[ "${NO_CACHE:-false}" == "true" ]]; then
        build_args+=(--no-cache)
    fi

    if [[ "${FORCE:-false}" == "true" ]]; then
        build_args+=(--force-rm)
    fi

    validate_distro "${distro}"

    if [[ "${distro}" == "all" ]]; then
        log_info "Building all Docker images..."
        for d in "${SUPPORTED_DISTROS[@]}"; do
            log_info "Building ${d} image..."
            docker-compose -f "${DOCKER_COMPOSE_FILE}" build "${build_args[@]}" "${d}" || die "Failed to build ${d} image"
        done
    else
        log_info "Building ${distro} image..."
        docker-compose -f "${DOCKER_COMPOSE_FILE}" build "${build_args[@]}" "${distro}" || die "Failed to build ${distro} image"
    fi

    log_success "Image build complete"
}

# Start containers
start_containers() {
    local distro="${1:-all}"
    local start_args=()

    if [[ "${DETACH:-true}" == "true" ]]; then
        start_args+=(-d)
    fi

    validate_distro "${distro}"

    if [[ "${distro}" == "all" ]]; then
        log_info "Starting all containers..."
        docker-compose -f "${DOCKER_COMPOSE_FILE}" up "${start_args[@]}" || die "Failed to start containers"
    else
        log_info "Starting ${distro} container..."
        docker-compose -f "${DOCKER_COMPOSE_FILE}" up "${start_args[@]}" "${distro}" || die "Failed to start ${distro} container"
    fi

    # Wait for containers to be healthy
    wait_for_health "${distro}"

    log_success "Containers started successfully"
}

# Wait for container health
wait_for_health() {
    local distro="$1"
    local max_attempts=30
    local attempt=0

    local containers=()
    if [[ "${distro}" == "all" ]]; then
        containers=("${SUPPORTED_DISTROS[@]}")
    else
        containers=("${distro}")
    fi

    log_info "Waiting for containers to be healthy..."

    for container in "${containers[@]}"; do
        attempt=0
        while [[ ${attempt} -lt ${max_attempts} ]]; do
            if docker-compose -f "${DOCKER_COMPOSE_FILE}" ps "${container}" | grep -q "healthy"; then
                log_success "${container} container is healthy"
                break
            fi

            ((attempt++))
            if [[ ${attempt} -eq ${max_attempts} ]]; then
                die "${container} container failed health check after ${max_attempts} attempts"
            fi

            sleep 2
        done
    done
}

# Run tests
run_tests() {
    local distro="${1:-all}"
    local test_type="${2:-all}"
    local test_args=()

    validate_distro "${distro}"

    # Ensure containers are running
    start_containers "${distro}"

    if [[ "${distro}" == "all" ]]; then
        if [[ "${PARALLEL:-false}" == "true" ]]; then
            log_info "Running tests in parallel across all distros..."
            run_parallel_tests "${test_type}"
        else
            log_info "Running tests sequentially across all distros..."
            for d in "${SUPPORTED_DISTROS[@]}"; do
                run_single_test "${d}" "${test_type}"
            done
        fi
    else
        run_single_test "${distro}" "${test_type}"
    fi

    log_success "Test execution complete"
}

# Run tests on a single distro
run_single_test() {
    local distro="$1"
    local test_type="$2"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file="${LOG_DIR}/${distro}_${test_type}_${timestamp}.log"

    log_info "Running ${test_type} tests on ${distro}..."

    case "${test_type}" in
        "bootstrap")
            docker-compose -f "${DOCKER_COMPOSE_FILE}" exec -T "${distro}" \
                bash -c "cd /opt/machine-rites && ./bootstrap/bootstrap_machine_rites.sh --dry-run" \
                2>&1 | tee "${log_file}"
            ;;
        "unit")
            docker-compose -f "${DOCKER_COMPOSE_FILE}" exec -T "${distro}" \
                bash -c "cd /opt/machine-rites && make test-unit" \
                2>&1 | tee "${log_file}"
            ;;
        "integration")
            docker-compose -f "${DOCKER_COMPOSE_FILE}" exec -T "${distro}" \
                bash -c "cd /opt/machine-rites && make test-integration" \
                2>&1 | tee "${log_file}"
            ;;
        "all"|*)
            docker-compose -f "${DOCKER_COMPOSE_FILE}" exec -T "${distro}" \
                bash -c "cd /opt/machine-rites && make test" \
                2>&1 | tee "${log_file}"
            ;;
    esac

    # Check test results
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        log_success "Tests passed on ${distro}"
    else
        log_error "Tests failed on ${distro}. See log: ${log_file}"
        return 1
    fi
}

# Run tests in parallel
run_parallel_tests() {
    local test_type="$1"
    local pids=()

    log_info "Starting parallel test execution..."

    for distro in "${SUPPORTED_DISTROS[@]}"; do
        run_single_test "${distro}" "${test_type}" &
        pids+=($!)
        log_info "Started tests for ${distro} (PID: $!)"
    done

    # Wait for all tests to complete
    local failed_tests=()
    for i in "${!pids[@]}"; do
        local pid="${pids[$i]}"
        local distro="${SUPPORTED_DISTROS[$i]}"

        if wait "${pid}"; then
            log_success "Parallel tests completed successfully for ${distro}"
        else
            log_error "Parallel tests failed for ${distro}"
            failed_tests+=("${distro}")
        fi
    done

    # Report results
    if [[ ${#failed_tests[@]} -eq 0 ]]; then
        log_success "All parallel tests passed"
    else
        log_error "Parallel tests failed for: ${failed_tests[*]}"
        return 1
    fi
}

# Open interactive shell
open_shell() {
    local distro="$1"

    validate_distro "${distro}"

    if [[ "${distro}" == "all" ]]; then
        die "Cannot open shell for 'all'. Please specify a single distro."
    fi

    # Ensure container is running
    start_containers "${distro}"

    log_info "Opening interactive shell in ${distro} container..."
    docker-compose -f "${DOCKER_COMPOSE_FILE}" exec "${distro}" /bin/bash
}

# Run validation checks
run_validation() {
    local distro="${1:-all}"

    validate_distro "${distro}"

    log_info "Running validation checks..."

    if [[ "${distro}" == "all" ]]; then
        for d in "${SUPPORTED_DISTROS[@]}"; do
            validate_single_distro "${d}"
        done
    else
        validate_single_distro "${distro}"
    fi

    log_success "Validation complete"
}

# Validate single distro
validate_single_distro() {
    local distro="$1"

    log_info "Validating ${distro} environment..."

    # Ensure container is running
    start_containers "${distro}"

    # Run validation commands
    local validation_commands=(
        "which bash"
        "which git"
        "which make"
        "which sudo"
        "id testuser"
        "sudo -l -U testuser"
        "test -d /opt/machine-rites"
        "test -w /opt/machine-rites"
    )

    for cmd in "${validation_commands[@]}"; do
        if docker-compose -f "${DOCKER_COMPOSE_FILE}" exec -T "${distro}" bash -c "${cmd}" >/dev/null 2>&1; then
            log_success "✓ ${cmd}"
        else
            log_error "✗ ${cmd}"
            return 1
        fi
    done

    log_success "Validation passed for ${distro}"
}

# Clean up containers and images
cleanup() {
    local force="${FORCE:-false}"

    log_info "Cleaning up Docker resources..."

    # Stop and remove containers
    docker-compose -f "${DOCKER_COMPOSE_FILE}" down --volumes --remove-orphans

    if [[ "${force}" == "true" ]]; then
        log_info "Force cleanup: removing images..."
        docker-compose -f "${DOCKER_COMPOSE_FILE}" down --rmi all --volumes --remove-orphans

        # Remove dangling images
        docker image prune -f

        # Remove unused volumes
        docker volume prune -f
    fi

    log_success "Cleanup complete"
}

# Show container status
show_status() {
    log_info "Container status:"
    docker-compose -f "${DOCKER_COMPOSE_FILE}" ps

    log_info "Image information:"
    docker images | grep -E "(machine-rites|REPOSITORY)"

    log_info "Volume information:"
    docker volume ls | grep -E "(machine-rites|DRIVER)"
}

# Show container logs
show_logs() {
    local distro="${1:-}"
    local log_args=()

    if [[ -n "${distro}" ]]; then
        validate_distro "${distro}"
        if [[ "${distro}" != "all" ]]; then
            log_args+=("${distro}")
        fi
    fi

    docker-compose -f "${DOCKER_COMPOSE_FILE}" logs -f "${log_args[@]}"
}

# Check container health
check_health() {
    log_info "Checking container health..."

    for distro in "${SUPPORTED_DISTROS[@]}"; do
        local status=$(docker-compose -f "${DOCKER_COMPOSE_FILE}" ps -q "${distro}" | xargs docker inspect --format='{{.State.Health.Status}}' 2>/dev/null || echo "not_running")

        case "${status}" in
            "healthy")
                log_success "${distro}: healthy"
                ;;
            "unhealthy")
                log_error "${distro}: unhealthy"
                ;;
            "starting")
                log_warn "${distro}: starting"
                ;;
            "not_running")
                log_warn "${distro}: not running"
                ;;
            *)
                log_warn "${distro}: unknown status (${status})"
                ;;
        esac
    done
}

# Run full test suite
run_full_suite() {
    log_info "Running full test suite..."

    # Build all images
    build_images "all"

    # Run validation
    run_validation "all"

    # Run all test types
    local test_types=("unit" "integration" "bootstrap")

    for test_type in "${test_types[@]}"; do
        log_info "Running ${test_type} tests..."
        if [[ "${PARALLEL:-false}" == "true" ]]; then
            run_tests "all" "${test_type}"
        else
            for distro in "${SUPPORTED_DISTROS[@]}"; do
                run_tests "${distro}" "${test_type}"
            done
        fi
    done

    log_success "Full test suite complete"
}

# Parse command line arguments
parse_args() {
    local command=""
    local args=()

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
            -d|--detach)
                DETACH=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            --no-cache)
                NO_CACHE=true
                shift
                ;;
            --parallel)
                PARALLEL=true
                shift
                ;;
            build|test|shell|validate|clean|status|logs|health|all)
                command="$1"
                shift
                break
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done

    if [[ -z "${command}" ]]; then
        show_usage
        die "No command specified"
    fi

    args=("$@")

    # Execute command
    case "${command}" in
        build)
            build_images "${args[0]:-all}"
            ;;
        test)
            run_tests "${args[0]:-all}" "${args[1]:-all}"
            ;;
        shell)
            open_shell "${args[0]:-ubuntu-24}"
            ;;
        validate)
            run_validation "${args[0]:-all}"
            ;;
        clean)
            cleanup
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs "${args[0]:-}"
            ;;
        health)
            check_health
            ;;
        all)
            run_full_suite
            ;;
        *)
            die "Unknown command: ${command}"
            ;;
    esac
}

# Main function
main() {
    # Setup
    setup_environment

    # Parse and execute
    parse_args "$@"
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi