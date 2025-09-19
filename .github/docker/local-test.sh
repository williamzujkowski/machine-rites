#!/bin/bash
# Local Docker CI Testing Script
# Runs the same tests as GitHub Actions locally

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Local Docker CI testing for machine-rites

OPTIONS:
    -s, --scenario SCENARIO   Test scenario: fresh, upgrade, minimal, all (default: fresh)
    -d, --distro DISTRO      Target distribution: ubuntu-24.04, ubuntu-22.04, debian-12, all (default: all)
    -c, --clean              Clean Docker images and volumes before testing
    -p, --parallel           Run tests in parallel (default: sequential)
    -v, --verbose            Verbose output
    -h, --help               Show this help

EXAMPLES:
    $0                       # Run fresh tests on all distros
    $0 -s all -d ubuntu-24.04  # Run all scenarios on Ubuntu 24.04
    $0 -c -p                 # Clean and run parallel tests
    $0 --scenario upgrade    # Run upgrade tests on all distros

EOF
}

# Default values
SCENARIO="fresh"
DISTRO="all"
CLEAN=false
PARALLEL=false
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--scenario)
            SCENARIO="$2"
            shift 2
            ;;
        -d|--distro)
            DISTRO="$2"
            shift 2
            ;;
        -c|--clean)
            CLEAN=true
            shift
            ;;
        -p|--parallel)
            PARALLEL=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate scenario
case "$SCENARIO" in
    fresh|upgrade|minimal|all) ;;
    *)
        log_error "Invalid scenario: $SCENARIO"
        log_error "Valid scenarios: fresh, upgrade, minimal, all"
        exit 1
        ;;
esac

# Validate distro
case "$DISTRO" in
    ubuntu-24.04|ubuntu-22.04|debian-12|all) ;;
    *)
        log_error "Invalid distro: $DISTRO"
        log_error "Valid distros: ubuntu-24.04, ubuntu-22.04, debian-12, all"
        exit 1
        ;;
esac

# Check Docker
if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker is not installed or not in PATH"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    log_error "Docker daemon is not running or not accessible"
    exit 1
fi

# Check Docker Compose
if ! command -v docker-compose >/dev/null 2>&1; then
    log_error "docker-compose is not installed or not in PATH"
    exit 1
fi

cd "$PROJECT_ROOT"

# Clean if requested
if [ "$CLEAN" = true ]; then
    log_info "Cleaning Docker images and volumes..."
    docker-compose -f .github/docker/docker-compose.test.yml down --volumes --remove-orphans || true
    docker system prune -f || true
    log_success "Cleanup completed"
fi

# Function to run single test
run_single_test() {
    local test_distro=$1
    local test_scenario=$2

    log_info "Running $test_scenario test on $test_distro..."

    local compose_file=".github/docker/docker-compose.test.yml"
    local service_name="test-${test_distro//./-}"

    if [ "$test_scenario" != "fresh" ]; then
        service_name="${service_name}-${test_scenario}"
    fi

    # Set environment variables
    export TEST_SCENARIO="$test_scenario"

    local docker_args=(
        -f "$compose_file"
        run
        --rm
    )

    if [ "$VERBOSE" = true ]; then
        docker_args+=(--service-ports)
    fi

    docker_args+=("$service_name")

    if docker-compose "${docker_args[@]}"; then
        log_success "$test_scenario test on $test_distro: PASSED"
        return 0
    else
        log_error "$test_scenario test on $test_distro: FAILED"
        return 1
    fi
}

# Function to run tests in parallel
run_parallel_tests() {
    local scenarios=("$@")
    local distros=()
    local pids=()
    local results=()

    # Determine distros to test
    if [ "$DISTRO" = "all" ]; then
        distros=("ubuntu-24.04" "ubuntu-22.04" "debian-12")
    else
        distros=("$DISTRO")
    fi

    log_info "Running tests in parallel..."
    log_info "Scenarios: ${scenarios[*]}"
    log_info "Distros: ${distros[*]}"

    # Start all tests in background
    for scenario in "${scenarios[@]}"; do
        for distro in "${distros[@]}"; do
            (
                run_single_test "$distro" "$scenario"
                echo $? > "/tmp/test-result-${distro}-${scenario}"
            ) &
            pids+=($!)
        done
    done

    # Wait for all tests to complete
    log_info "Waiting for ${#pids[@]} tests to complete..."
    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    # Collect results
    local total_tests=0
    local passed_tests=0
    local failed_tests=0

    for scenario in "${scenarios[@]}"; do
        for distro in "${distros[@]}"; do
            total_tests=$((total_tests + 1))
            if [ -f "/tmp/test-result-${distro}-${scenario}" ]; then
                local result
                result=$(cat "/tmp/test-result-${distro}-${scenario}")
                if [ "$result" -eq 0 ]; then
                    passed_tests=$((passed_tests + 1))
                else
                    failed_tests=$((failed_tests + 1))
                fi
                rm "/tmp/test-result-${distro}-${scenario}"
            else
                failed_tests=$((failed_tests + 1))
            fi
        done
    done

    log_info "Parallel test results:"
    log_info "Total: $total_tests, Passed: $passed_tests, Failed: $failed_tests"

    if [ "$failed_tests" -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# Function to run tests sequentially
run_sequential_tests() {
    local scenarios=("$@")
    local distros=()
    local total_tests=0
    local passed_tests=0
    local failed_tests=0

    # Determine distros to test
    if [ "$DISTRO" = "all" ]; then
        distros=("ubuntu-24.04" "ubuntu-22.04" "debian-12")
    else
        distros=("$DISTRO")
    fi

    log_info "Running tests sequentially..."
    log_info "Scenarios: ${scenarios[*]}"
    log_info "Distros: ${distros[*]}"

    for scenario in "${scenarios[@]}"; do
        for distro in "${distros[@]}"; do
            total_tests=$((total_tests + 1))
            if run_single_test "$distro" "$scenario"; then
                passed_tests=$((passed_tests + 1))
            else
                failed_tests=$((failed_tests + 1))
            fi
        done
    done

    log_info "Sequential test results:"
    log_info "Total: $total_tests, Passed: $passed_tests, Failed: $failed_tests"

    if [ "$failed_tests" -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# Main execution
main() {
    log_info "Starting local Docker CI tests..."
    log_info "Working directory: $PROJECT_ROOT"
    log_info "Scenario: $SCENARIO"
    log_info "Distro: $DISTRO"
    log_info "Parallel: $PARALLEL"
    log_info "Clean: $CLEAN"

    # Determine scenarios to run
    local scenarios=()
    if [ "$SCENARIO" = "all" ]; then
        scenarios=("fresh" "upgrade" "minimal")
    else
        scenarios=("$SCENARIO")
    fi

    # Run tests
    if [ "$PARALLEL" = true ]; then
        if run_parallel_tests "${scenarios[@]}"; then
            log_success "All tests passed!"
            exit 0
        else
            log_error "Some tests failed!"
            exit 1
        fi
    else
        if run_sequential_tests "${scenarios[@]}"; then
            log_success "All tests passed!"
            exit 0
        else
            log_error "Some tests failed!"
            exit 1
        fi
    fi
}

# Run main function
main "$@"