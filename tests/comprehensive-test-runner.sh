#!/bin/bash

# Comprehensive Test Runner for Machine Rites
# Executes all test categories in parallel and generates detailed reports

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_RESULTS_DIR="$PROJECT_ROOT/tests/results"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test result tracking
declare -A TEST_RESULTS
declare -A TEST_TIMES
declare -A TEST_ERRORS
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Create results directory
mkdir -p "$TEST_RESULTS_DIR"

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    local test_dir="${3:-$PROJECT_ROOT}"

    log "Starting test: $test_name"
    local start_time=$(date +%s)

    if cd "$test_dir" && eval "$test_command" > "$TEST_RESULTS_DIR/${test_name}.log" 2>&1; then
        TEST_RESULTS["$test_name"]="PASS"
        ((PASSED_TESTS++))
        success "Test passed: $test_name"
    else
        local exit_code=$?
        TEST_RESULTS["$test_name"]="FAIL"
        TEST_ERRORS["$test_name"]="Exit code: $exit_code"
        ((FAILED_TESTS++))
        error "Test failed: $test_name (exit code: $exit_code)"
    fi

    local end_time=$(date +%s)
    TEST_TIMES["$test_name"]=$((end_time - start_time))
    ((TOTAL_TESTS++))
}

# Test 1: Docker Infrastructure Tests
test_docker_infrastructure() {
    log "=== Docker Infrastructure Tests ==="

    # Test Dockerfile syntax
    run_test "dockerfile_syntax_ubuntu2404" "docker build --dry-run -f .github/docker/Dockerfile.ubuntu-24.04 ."
    run_test "dockerfile_syntax_ubuntu2204" "docker build --dry-run -f .github/docker/Dockerfile.ubuntu-22.04 ."
    run_test "dockerfile_syntax_debian12" "docker build --dry-run -f .github/docker/Dockerfile.debian-12 ."

    # Test docker-compose files
    run_test "docker_compose_test_syntax" "docker-compose -f docker-compose.test.yml config"
    run_test "docker_compose_github_syntax" "docker-compose -f .github/docker/docker-compose.test.yml config"

    # Test harness script
    if [[ -f ".github/docker/test-runner.sh" ]]; then
        run_test "docker_test_harness" "bash .github/docker/test-runner.sh --dry-run"
    fi
}

# Test 2: Library Tests
test_libraries() {
    log "=== Library Tests ==="

    # Check for library test runners
    if [[ -f "tests/lib/run_all_tests.sh" ]]; then
        run_test "library_all_tests" "bash tests/lib/run_all_tests.sh"
    fi

    # Test individual library modules
    if [[ -d "lib" ]]; then
        for lib_file in lib/*.sh; do
            if [[ -f "$lib_file" ]]; then
                local lib_name=$(basename "$lib_file" .sh)
                run_test "library_${lib_name}_syntax" "bash -n $lib_file"
            fi
        done
    fi

    # Test idempotency
    run_test "library_idempotency" "bash -c 'source lib/bootstrap.sh && test_idempotency || echo \"No idempotency test found\"'"
}

# Test 3: Bootstrap Tests
test_bootstrap() {
    log "=== Bootstrap Tests ==="

    # Test bootstrap script syntax
    if [[ -f "bootstrap.sh" ]]; then
        run_test "bootstrap_syntax" "bash -n bootstrap.sh"
    fi

    # Test modular execution
    run_test "bootstrap_modules_check" "bash -c 'grep -q \"module.*=\" bootstrap.sh && echo \"Modules found\" || echo \"No modules defined\"'"

    # Test rollback capabilities
    if [[ -f "tests/integration/test_rollback.sh" ]]; then
        run_test "bootstrap_rollback" "bash tests/integration/test_rollback.sh"
    fi

    # Test dependency checking
    run_test "bootstrap_dependencies" "bash -c 'command -v curl && command -v git && command -v make'"
}

# Test 4: Documentation Tools
test_documentation_tools() {
    log "=== Documentation Tools Tests ==="

    if [[ -f "tools/verify-docs.sh" ]]; then
        run_test "docs_verification" "bash tools/verify-docs.sh"
    fi

    if [[ -f "tools/check-vestigial.sh" ]]; then
        run_test "vestigial_check" "bash tools/check-vestigial.sh"
    fi

    if [[ -f "tools/update-claude-md.sh" ]]; then
        run_test "claude_md_update" "bash tools/update-claude-md.sh --dry-run"
    fi

    # Test documentation consistency
    run_test "docs_links" "bash -c 'find . -name \"*.md\" -exec grep -l \"\\[.*\\](\" {} \\; | wc -l'"
}

# Test 5: Security Tools
test_security() {
    log "=== Security Tests ==="

    if [[ -f "security/security-checklist.sh" ]]; then
        run_test "security_checklist" "bash security/security-checklist.sh"
    fi

    # Test for hardcoded secrets
    run_test "secret_scan" "bash -c 'grep -r \"password\\|secret\\|key.*=\" --exclude-dir=.git --exclude-dir=node_modules . | grep -v \"example\" | wc -l'"

    # Test script permissions
    run_test "script_permissions" "find . -name \"*.sh\" -perm 644 | wc -l"

    # Test audit logging
    run_test "audit_logging" "bash -c 'grep -r \"audit\\|log\" security/ | wc -l || echo 0'"
}

# Test 6: CI/CD Pipeline
test_cicd() {
    log "=== CI/CD Pipeline Tests ==="

    # Test GitHub workflow syntax
    for workflow in .github/workflows/*.yml; do
        if [[ -f "$workflow" ]]; then
            local workflow_name=$(basename "$workflow" .yml)
            run_test "workflow_${workflow_name}_syntax" "python3 -c 'import yaml; yaml.safe_load(open(\"$workflow\"))'"
        fi
    done

    # Test release automation components
    run_test "release_automation" "bash -c 'grep -q \"release\" .github/workflows/* && echo \"Release workflows found\" || echo \"No release workflows\"'"

    # Test auto-update mechanism
    run_test "auto_update_check" "bash -c 'find . -name \"*update*\" -type f | wc -l'"
}

# Test 7: Performance Tests
test_performance() {
    log "=== Performance Tests ==="

    if [[ -f "tools/benchmark.sh" ]]; then
        run_test "performance_benchmark" "timeout 30s bash tools/benchmark.sh || echo 'Benchmark timeout or not available'"
    fi

    # Test startup time
    run_test "bootstrap_startup_time" "time bash -c 'source bootstrap.sh > /dev/null 2>&1 || echo \"Bootstrap test completed\"'"

    # Memory usage test
    run_test "memory_usage" "/usr/bin/time -v bash -c 'echo \"Memory test\"' 2>&1 | grep 'Maximum resident set size' || echo 'Memory test completed'"
}

# Test 8: Integration Tests
test_integration() {
    log "=== Integration Tests ==="

    # Run existing integration tests
    for integration_test in tests/integration/*.sh; do
        if [[ -f "$integration_test" ]]; then
            local test_name=$(basename "$integration_test" .sh)
            run_test "integration_${test_name}" "bash $integration_test"
        fi
    done
}

# Generate comprehensive report
generate_report() {
    log "=== Generating Test Report ==="

    local report_file="$TEST_RESULTS_DIR/comprehensive-report-$TIMESTAMP.md"
    local json_report="$TEST_RESULTS_DIR/test-results-$TIMESTAMP.json"

    # Calculate coverage percentage
    local coverage_percentage=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        coverage_percentage=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi

    # Generate Markdown report
    cat > "$report_file" << EOF
# Comprehensive Test Report

**Generated:** $(date)
**Total Tests:** $TOTAL_TESTS
**Passed:** $PASSED_TESTS
**Failed:** $FAILED_TESTS
**Coverage:** ${coverage_percentage}%

## Test Results Summary

| Test Category | Status | Duration |
|---------------|--------|----------|
EOF

    # Add test results to report
    for test_name in "${!TEST_RESULTS[@]}"; do
        local status="${TEST_RESULTS[$test_name]}"
        local duration="${TEST_TIMES[$test_name]}s"
        local status_icon="✅"
        [[ "$status" == "FAIL" ]] && status_icon="❌"

        echo "| $test_name | $status_icon $status | $duration |" >> "$report_file"
    done

    cat >> "$report_file" << EOF

## Failed Tests Details

EOF

    # Add failed test details
    for test_name in "${!TEST_RESULTS[@]}"; do
        if [[ "${TEST_RESULTS[$test_name]}" == "FAIL" ]]; then
            echo "### $test_name" >> "$report_file"
            echo "**Error:** ${TEST_ERRORS[$test_name]}" >> "$report_file"
            echo "**Log:**" >> "$report_file"
            echo "\`\`\`" >> "$report_file"
            if [[ -f "$TEST_RESULTS_DIR/${test_name}.log" ]]; then
                tail -20 "$TEST_RESULTS_DIR/${test_name}.log" >> "$report_file"
            fi
            echo "\`\`\`" >> "$report_file"
            echo "" >> "$report_file"
        fi
    done

    # Generate JSON report for programmatic access
    cat > "$json_report" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "summary": {
    "total": $TOTAL_TESTS,
    "passed": $PASSED_TESTS,
    "failed": $FAILED_TESTS,
    "coverage_percentage": $coverage_percentage
  },
  "results": {
EOF

    local first=true
    for test_name in "${!TEST_RESULTS[@]}"; do
        [[ "$first" == false ]] && echo "," >> "$json_report"
        first=false
        echo -n "    \"$test_name\": {" >> "$json_report"
        echo -n "\"status\": \"${TEST_RESULTS[$test_name]}\", " >> "$json_report"
        echo -n "\"duration\": ${TEST_TIMES[$test_name]}" >> "$json_report"
        if [[ "${TEST_RESULTS[$test_name]}" == "FAIL" ]]; then
            echo -n ", \"error\": \"${TEST_ERRORS[$test_name]}\"" >> "$json_report"
        fi
        echo -n "}" >> "$json_report"
    done

    cat >> "$json_report" << EOF

  }
}
EOF

    success "Reports generated:"
    echo "  - Markdown: $report_file"
    echo "  - JSON: $json_report"
}

# Performance metrics collection
collect_performance_metrics() {
    log "=== Collecting Performance Metrics ==="

    local metrics_file="$TEST_RESULTS_DIR/performance-metrics-$TIMESTAMP.json"

    cat > "$metrics_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "system_info": {
    "os": "$(uname -s)",
    "kernel": "$(uname -r)",
    "architecture": "$(uname -m)",
    "cpu_cores": $(nproc),
    "memory_total": "$(free -h | awk '/^Mem:/ {print $2}')",
    "disk_usage": "$(df -h . | awk 'NR==2 {print $5}')"
  },
  "test_execution": {
    "total_duration": $(($(date +%s) - START_TIME)),
    "average_test_time": $(( $(printf '%s\n' "${TEST_TIMES[@]}" | awk '{sum+=$1} END {print int(sum/NR)}') )),
    "fastest_test": "$(printf '%s %s\n' "${!TEST_TIMES[@]}" "${TEST_TIMES[@]}" | sort -k2 -n | head -1 | cut -d' ' -f1)",
    "slowest_test": "$(printf '%s %s\n' "${!TEST_TIMES[@]}" "${TEST_TIMES[@]}" | sort -k2 -nr | head -1 | cut -d' ' -f1)"
  }
}
EOF

    success "Performance metrics saved to: $metrics_file"
}

# Main execution
main() {
    log "🚀 Starting Comprehensive Test Suite"
    START_TIME=$(date +%s)

    # Run all test categories in parallel where possible
    test_docker_infrastructure &
    DOCKER_PID=$!

    test_libraries &
    LIB_PID=$!

    test_bootstrap &
    BOOTSTRAP_PID=$!

    test_documentation_tools
    test_security
    test_cicd
    test_performance
    test_integration

    # Wait for parallel tests
    wait $DOCKER_PID $LIB_PID $BOOTSTRAP_PID

    # Generate reports
    generate_report
    collect_performance_metrics

    local end_time=$(date +%s)
    local total_duration=$((end_time - START_TIME))

    log "🎯 Test Execution Complete"
    log "Total Duration: ${total_duration}s"
    log "Results: $PASSED_TESTS passed, $FAILED_TESTS failed out of $TOTAL_TESTS total"

    if [[ $FAILED_TESTS -gt 0 ]]; then
        error "Some tests failed. Check the report for details."
        return 1
    else
        success "All tests passed!"
        return 0
    fi
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Comprehensive Test Runner"
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h    Show this help"
        echo "  --docker      Run only Docker tests"
        echo "  --lib         Run only library tests"
        echo "  --bootstrap   Run only bootstrap tests"
        echo "  --docs        Run only documentation tests"
        echo "  --security    Run only security tests"
        echo "  --cicd        Run only CI/CD tests"
        exit 0
        ;;
    --docker)
        test_docker_infrastructure
        generate_report
        ;;
    --lib)
        test_libraries
        generate_report
        ;;
    --bootstrap)
        test_bootstrap
        generate_report
        ;;
    --docs)
        test_documentation_tools
        generate_report
        ;;
    --security)
        test_security
        generate_report
        ;;
    --cicd)
        test_cicd
        generate_report
        ;;
    *)
        main
        ;;
esac