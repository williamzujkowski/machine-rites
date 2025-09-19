#!/bin/bash
# Docker CI Test Runner Script
# Handles different test scenarios for machine-rites

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
TEST_RESULTS_DIR="${TEST_RESULTS_DIR:-/test-results}"
TEST_SCENARIO="${TEST_SCENARIO:-fresh}"
TIMEOUT_DURATION="${TIMEOUT_DURATION:-300}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${TEST_RESULTS_DIR}/test.log"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${TEST_RESULTS_DIR}/test.log"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${TEST_RESULTS_DIR}/test.log"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${TEST_RESULTS_DIR}/test.log"
}

# Create test results directory
mkdir -p "${TEST_RESULTS_DIR}"

# Initialize test log
echo "=== Docker CI Test Runner ===" > "${TEST_RESULTS_DIR}/test.log"
echo "Scenario: ${TEST_SCENARIO}" >> "${TEST_RESULTS_DIR}/test.log"
echo "Start time: $(date)" >> "${TEST_RESULTS_DIR}/test.log"
echo "Environment: $(lsb_release -d 2>/dev/null || echo 'Unknown')" >> "${TEST_RESULTS_DIR}/test.log"
echo "User: $(whoami)" >> "${TEST_RESULTS_DIR}/test.log"
echo "Working directory: ${WORKSPACE_DIR}" >> "${TEST_RESULTS_DIR}/test.log"
echo "=============================" >> "${TEST_RESULTS_DIR}/test.log"

# Change to workspace directory
cd "${WORKSPACE_DIR}"

# Function to run tests with timeout
run_with_timeout() {
    local timeout_duration=$1
    shift
    local command=("$@")

    log_info "Running command with ${timeout_duration}s timeout: ${command[*]}"

    if timeout "${timeout_duration}" "${command[@]}" 2>&1 | tee -a "${TEST_RESULTS_DIR}/test.log"; then
        log_success "Command completed successfully"
        return 0
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log_error "Command timed out after ${timeout_duration} seconds"
        else
            log_error "Command failed with exit code $exit_code"
        fi
        return $exit_code
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local required_tools=("git" "bash" "make" "shellcheck")
    local missing_tools=()

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        else
            log_info "$tool: $(command -v "$tool")"
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        return 1
    fi

    log_success "All prerequisites met"
    return 0
}

# Function to run fresh installation test
run_fresh_test() {
    log_info "Starting fresh installation test..."

    # Ensure clean environment
    rm -rf ~/.bashrc.d ~/.config/chezmoi 2>/dev/null || true

    # Run bootstrap script
    if run_with_timeout "${TIMEOUT_DURATION}" bash bootstrap_machine_rites.sh --unattended --test; then
        log_success "Bootstrap script completed successfully"
        echo "Fresh installation completed successfully" > "${TEST_RESULTS_DIR}/result.txt"
    else
        log_error "Bootstrap script failed"
        echo "Fresh installation failed" > "${TEST_RESULTS_DIR}/result.txt"
        return 1
    fi

    # Run CI tests
    if run_with_timeout 120 make ci-test; then
        log_success "CI tests passed"
        echo "CI tests passed" >> "${TEST_RESULTS_DIR}/result.txt"
    else
        log_error "CI tests failed"
        echo "CI tests failed" >> "${TEST_RESULTS_DIR}/result.txt"
        return 1
    fi

    return 0
}

# Function to run upgrade test
run_upgrade_test() {
    log_info "Starting upgrade scenario test..."

    # First, install minimal version
    log_info "Setting up existing installation..."
    if run_with_timeout 180 bash bootstrap_machine_rites.sh --unattended --minimal; then
        log_success "Minimal installation completed"
    else
        log_error "Minimal installation failed"
        return 1
    fi

    # Now run upgrade
    log_info "Running upgrade..."
    if run_with_timeout "${TIMEOUT_DURATION}" bash bootstrap_machine_rites.sh --unattended --upgrade; then
        log_success "Upgrade completed successfully"
        echo "Upgrade completed successfully" > "${TEST_RESULTS_DIR}/result.txt"
    else
        log_error "Upgrade failed"
        echo "Upgrade failed" > "${TEST_RESULTS_DIR}/result.txt"
        return 1
    fi

    # Run CI tests
    if run_with_timeout 120 make ci-test; then
        log_success "Post-upgrade CI tests passed"
        echo "Post-upgrade CI tests passed" >> "${TEST_RESULTS_DIR}/result.txt"
    else
        log_error "Post-upgrade CI tests failed"
        echo "Post-upgrade CI tests failed" >> "${TEST_RESULTS_DIR}/result.txt"
        return 1
    fi

    return 0
}

# Function to run minimal installation test
run_minimal_test() {
    log_info "Starting minimal installation test..."

    # Ensure clean environment
    rm -rf ~/.bashrc.d ~/.config/chezmoi 2>/dev/null || true

    # Run minimal bootstrap
    if run_with_timeout 180 bash bootstrap_machine_rites.sh --unattended --minimal; then
        log_success "Minimal installation completed successfully"
        echo "Minimal installation completed successfully" > "${TEST_RESULTS_DIR}/result.txt"
    else
        log_error "Minimal installation failed"
        echo "Minimal installation failed" > "${TEST_RESULTS_DIR}/result.txt"
        return 1
    fi

    # Run basic tests
    if run_with_timeout 60 make lint; then
        log_success "Linting tests passed"
        echo "Linting tests passed" >> "${TEST_RESULTS_DIR}/result.txt"
    else
        log_error "Linting tests failed"
        echo "Linting tests failed" >> "${TEST_RESULTS_DIR}/result.txt"
        return 1
    fi

    return 0
}

# Function to collect system information
collect_system_info() {
    log_info "Collecting system information..."

    {
        echo "=== System Information ==="
        echo "OS: $(lsb_release -d 2>/dev/null || echo 'Unknown')"
        echo "Kernel: $(uname -r)"
        echo "Architecture: $(uname -m)"
        echo "User: $(whoami)"
        echo "Home: $HOME"
        echo "PWD: $(pwd)"
        echo "Shell: $SHELL"
        echo ""
        echo "=== Environment Variables ==="
        env | grep -E '^(CI|TEST_|GITHUB_|PATH)' | sort
        echo ""
        echo "=== Tool Versions ==="
        for tool in bash git make chezmoi shellcheck; do
            if command -v "$tool" >/dev/null 2>&1; then
                echo "$tool: $(command -v "$tool") - $("$tool" --version 2>/dev/null | head -1 || echo 'version unknown')"
            else
                echo "$tool: NOT FOUND"
            fi
        done
        echo ""
        echo "=== Disk Usage ==="
        df -h / 2>/dev/null || echo "Cannot get disk usage"
        echo ""
        echo "=== Memory Usage ==="
        free -h 2>/dev/null || echo "Cannot get memory usage"
    } > "${TEST_RESULTS_DIR}/system-info.txt"

    log_success "System information collected"
}

# Main execution
main() {
    log_info "Starting Docker CI test runner for scenario: ${TEST_SCENARIO}"

    # Collect system information
    collect_system_info

    # Check prerequisites
    if ! check_prerequisites; then
        log_error "Prerequisites check failed"
        exit 1
    fi

    # Run the appropriate test scenario
    case "${TEST_SCENARIO}" in
        fresh)
            run_fresh_test
            ;;
        upgrade)
            run_upgrade_test
            ;;
        minimal)
            run_minimal_test
            ;;
        *)
            log_error "Unknown test scenario: ${TEST_SCENARIO}"
            log_error "Valid scenarios: fresh, upgrade, minimal"
            exit 1
            ;;
    esac

    local test_exit_code=$?

    # Log completion
    echo "End time: $(date)" >> "${TEST_RESULTS_DIR}/test.log"
    echo "Exit code: $test_exit_code" >> "${TEST_RESULTS_DIR}/test.log"

    if [ $test_exit_code -eq 0 ]; then
        log_success "Test scenario '${TEST_SCENARIO}' completed successfully"
    else
        log_error "Test scenario '${TEST_SCENARIO}' failed with exit code $test_exit_code"
    fi

    exit $test_exit_code
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi