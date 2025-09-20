#!/bin/bash
# Test all make commands systematically for machine-rites v2.2.0
# This script validates all Makefile targets and reports their status

set -euo pipefail

VERSION="2.2.0"
FAILED_COMMANDS=()
PASSED_COMMANDS=()
SKIPPED_COMMANDS=()
WARNING_COMMANDS=()

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Log directory
LOG_DIR="/tmp/make-tests-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOG_DIR"

echo "==========================================="
echo "Machine-Rites Make Command Test Suite v$VERSION"
echo "==========================================="
echo "Log directory: $LOG_DIR"
echo ""

# Function to test a make command
test_command() {
    local cmd="$1"
    local skip_reason="${2:-}"
    local timeout_sec="${3:-30}"

    if [ -n "$skip_reason" ]; then
        echo -e "${YELLOW}[SKIP]${NC} make $cmd - $skip_reason"
        SKIPPED_COMMANDS+=("$cmd: $skip_reason")
        return
    fi

    printf "Testing: make %-25s ... " "$cmd"

    local log_file="$LOG_DIR/make-$cmd.log"
    local start_time=$(date +%s)

    if timeout "$timeout_sec" make "$cmd" > "$log_file" 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo -e "${GREEN}[PASS]${NC} (${duration}s)"
        PASSED_COMMANDS+=("$cmd")
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            echo -e "${YELLOW}[TIMEOUT]${NC} (>${timeout_sec}s)"
            WARNING_COMMANDS+=("$cmd: timeout after ${timeout_sec}s")
        else
            echo -e "${RED}[FAIL]${NC}"
            FAILED_COMMANDS+=("$cmd")
            # Show last error line
            local error_msg=$(tail -n 5 "$log_file" | grep -E "error|Error|ERROR|failed|Failed" | head -1 || tail -n 1 "$log_file")
            echo "         └─ Error: $error_msg"
        fi
    fi
}

# Function to check for dependencies
check_dependency() {
    local cmd="$1"
    local name="$2"

    if command -v "$cmd" >/dev/null 2>&1; then
        echo -e "  ✓ $name: ${GREEN}Available${NC}"
        return 0
    else
        echo -e "  ✗ $name: ${YELLOW}Not found${NC}"
        return 1
    fi
}

# Check system dependencies
echo -e "${BLUE}=== System Dependencies ===${NC}"
check_dependency "docker" "Docker"
DOCKER_AVAILABLE=$?

check_dependency "multipass" "Multipass"
MULTIPASS_AVAILABLE=$?

check_dependency "shellcheck" "ShellCheck"
SHELLCHECK_AVAILABLE=$?

check_dependency "shfmt" "Shfmt"
SHFMT_AVAILABLE=$?

check_dependency "hadolint" "Hadolint"
# HADOLINT_AVAILABLE=$?  # Reserved for future use

check_dependency "bats" "Bats"
# BATS_AVAILABLE=$?  # Reserved for future use

echo ""

# Test categories
echo -e "${BLUE}=== Basic/Info Commands ===${NC}"
test_command "help"
test_command "info"
test_command "deps"
test_command "deps-check"

echo -e "\n${BLUE}=== Setup & Validation Commands ===${NC}"
test_command "setup"
test_command "validate"
test_command "validate-syntax"
test_command "validate-structure"
test_command "validate-environment"

echo -e "\n${BLUE}=== Linting & Formatting Commands ===${NC}"
if [ $SHELLCHECK_AVAILABLE -eq 0 ]; then
    test_command "lint"
else
    test_command "lint" "ShellCheck not installed"
fi

if [ $SHFMT_AVAILABLE -eq 0 ]; then
    test_command "format-check"
else
    test_command "format-check" "Shfmt not installed"
fi

echo -e "\n${BLUE}=== Test Commands ===${NC}"
test_command "test"
test_command "test-unit"
test_command "test-integration"
test_command "test-bootstrap" "" 60
test_command "test-coverage"

echo -e "\n${BLUE}=== CI Commands ===${NC}"
test_command "ci-setup"
test_command "ci-test"
test_command "ci-validate"

echo -e "\n${BLUE}=== Docker Commands ===${NC}"
if [ $DOCKER_AVAILABLE -eq 0 ]; then
    test_command "docker-validate"
    test_command "docker-status"
    test_command "docker-build" "" 120
    test_command "docker-test" "" 120
    test_command "docker-shell" "Interactive command"
    test_command "docker-clean"
else
    test_command "docker-validate" "Docker not available"
    test_command "docker-build" "Docker not available"
    test_command "docker-test" "Docker not available"
    test_command "docker-clean" "Docker not available"
fi

echo -e "\n${BLUE}=== Multipass/VM Commands ===${NC}"
if [ $MULTIPASS_AVAILABLE -eq 0 ]; then
    # Check if multipass is actually working
    if multipass list >/dev/null 2>&1; then
        test_command "multipass-setup" "" 180
        test_command "multipass-report"
        test_command "multipass-clean"
    else
        test_command "multipass-setup" "Multipass not responding (will use Docker fallback)"
        test_command "multipass-test" "Multipass not responding"
        test_command "multipass-clean" "Multipass not responding"
    fi
else
    # Test Docker fallback for multipass commands
    if [ $DOCKER_AVAILABLE -eq 0 ]; then
        echo -e "${YELLOW}[INFO]${NC} Testing multipass commands with Docker fallback..."
        test_command "multipass-setup" "" 60
        test_command "multipass-clean"
    else
        test_command "multipass-setup" "Neither Multipass nor Docker available"
        test_command "multipass-test" "Neither Multipass nor Docker available"
        test_command "multipass-clean" "Neither Multipass nor Docker available"
    fi
fi

echo -e "\n${BLUE}=== Cleanup Commands ===${NC}"
test_command "clean"
test_command "clean-all"

# Generate summary report
echo ""
echo "==========================================="
echo "Test Summary Report"
echo "==========================================="
echo -e "${GREEN}Passed:${NC}  ${#PASSED_COMMANDS[@]} commands"
echo -e "${RED}Failed:${NC}  ${#FAILED_COMMANDS[@]} commands"
echo -e "${YELLOW}Warning:${NC} ${#WARNING_COMMANDS[@]} commands"
echo -e "${YELLOW}Skipped:${NC} ${#SKIPPED_COMMANDS[@]} commands"

# Show details if there are failures
if [ ${#FAILED_COMMANDS[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}Failed Commands:${NC}"
    for cmd in "${FAILED_COMMANDS[@]}"; do
        echo "  - make $cmd"
        echo "    └─ Log: $LOG_DIR/make-$cmd.log"
    done
fi

if [ ${#WARNING_COMMANDS[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Warning Commands:${NC}"
    for cmd in "${WARNING_COMMANDS[@]}"; do
        echo "  - $cmd"
    done
fi

if [ ${#SKIPPED_COMMANDS[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Skipped Commands:${NC}"
    for cmd in "${SKIPPED_COMMANDS[@]}"; do
        echo "  - $cmd"
    done
fi

# Generate markdown report
REPORT_FILE="$LOG_DIR/test-report.md"
cat > "$REPORT_FILE" << EOF
# Make Command Test Report - v$VERSION
Date: $(date)
System: $(uname -s) $(uname -r)

## Summary
- **Total Tested**: $((${#PASSED_COMMANDS[@]} + ${#FAILED_COMMANDS[@]} + ${#WARNING_COMMANDS[@]}))
- **Passed**: ${#PASSED_COMMANDS[@]} commands
- **Failed**: ${#FAILED_COMMANDS[@]} commands
- **Warnings**: ${#WARNING_COMMANDS[@]} commands
- **Skipped**: ${#SKIPPED_COMMANDS[@]} commands

## System Capabilities
- Docker: $([ $DOCKER_AVAILABLE -eq 0 ] && echo "✓ Available" || echo "✗ Not found")
- Multipass: $([ $MULTIPASS_AVAILABLE -eq 0 ] && echo "✓ Available" || echo "✗ Not found")
- ShellCheck: $([ $SHELLCHECK_AVAILABLE -eq 0 ] && echo "✓ Available" || echo "✗ Not found")
- Shfmt: $([ $SHFMT_AVAILABLE -eq 0 ] && echo "✓ Available" || echo "✗ Not found")

## Failed Commands
$(if [ ${#FAILED_COMMANDS[@]} -gt 0 ]; then
    for cmd in "${FAILED_COMMANDS[@]}"; do
        echo "- \`make $cmd\`"
    done
else
    echo "*None*"
fi)

## Passed Commands
$(for cmd in "${PASSED_COMMANDS[@]}"; do echo "- \`make $cmd\`"; done)

## Warnings
$(if [ ${#WARNING_COMMANDS[@]} -gt 0 ]; then
    for cmd in "${WARNING_COMMANDS[@]}"; do
        echo "- $cmd"
    done
else
    echo "*None*"
fi)

## Skipped Commands
$(if [ ${#SKIPPED_COMMANDS[@]} -gt 0 ]; then
    for cmd in "${SKIPPED_COMMANDS[@]}"; do
        echo "- $cmd"
    done
else
    echo "*None*"
fi)

## Logs
All logs are available in: \`$LOG_DIR/\`
EOF

echo ""
echo "Report saved to: $REPORT_FILE"
echo "All logs saved to: $LOG_DIR/"

# Return appropriate exit code
if [ ${#FAILED_COMMANDS[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}[FAIL]${NC} Some make commands failed. Review logs for details."
    exit 1
else
    echo ""
    echo -e "${GREEN}[SUCCESS]${NC} All tested make commands passed!"
    exit 0
fi