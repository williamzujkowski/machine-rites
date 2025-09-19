#!/usr/bin/env bash
# tests/lib/run_all_tests.sh - Test runner for all library modules
#
# Runs all library tests and generates a comprehensive report
# Ensures all library modules work correctly together

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../lib" && pwd)"

# Load testing framework
source "$LIB_DIR/testing.sh"

# Colors for output
declare -r C_PASS="\033[32m"   # Green
declare -r C_FAIL="\033[31m"   # Red
declare -r C_INFO="\033[34m"   # Blue
declare -r C_WARN="\033[33m"   # Yellow
declare -r C_RESET="\033[0m"   # Reset

# Test results tracking
declare -g TOTAL_SUITES=0
declare -g PASSED_SUITES=0
declare -g FAILED_SUITES=0
declare -a FAILED_SUITE_NAMES=()

# Function: run_test_suite
# Purpose: Run a single test suite and track results
# Args: $1 - test script path
run_test_suite() {
    local test_script="$1"
    local test_name
    local result=0

    test_name="$(basename "$test_script" .sh)"

    printf "${C_INFO}Running %s...${C_RESET}\n" "$test_name"

    # Run test in isolated environment
    if (
        cd "$(dirname "$test_script")"
        export TEST_VERBOSE=0
        bash "$test_script"
    ) 2>&1; then
        printf "${C_PASS}✓ %s PASSED${C_RESET}\n" "$test_name"
        ((PASSED_SUITES++))
    else
        result=$?
        printf "${C_FAIL}✗ %s FAILED (exit code: %d)${C_RESET}\n" "$test_name" "$result"
        ((FAILED_SUITES++))
        FAILED_SUITE_NAMES+=("$test_name")
    fi

    ((TOTAL_SUITES++))
    echo
}

# Function: run_integration_tests
# Purpose: Run integration tests that test libraries together
run_integration_tests() {
    local temp_script

    printf "${C_INFO}Running integration tests...${C_RESET}\n"

    # Create temporary integration test
    temp_script="$(mktemp)"
    cat > "$temp_script" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Load all libraries
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/atomic.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/validation.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/platform.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/testing.sh"

# Test that all libraries loaded successfully
test_library_loading() {
    assert_equals "1" "$LIB_COMMON_LOADED" "Common library should be loaded"
    assert_equals "1" "$LIB_ATOMIC_LOADED" "Atomic library should be loaded"
    assert_equals "1" "$LIB_VALIDATION_LOADED" "Validation library should be loaded"
    assert_equals "1" "$LIB_PLATFORM_LOADED" "Platform library should be loaded"
    assert_equals "1" "$LIB_TESTING_LOADED" "Testing library should be loaded"
}

# Test inter-library functionality
test_inter_library_functionality() {
    local test_file="$TEST_TMPDIR/integration_test.txt"
    local test_content="Integration test content"

    # Use validation to check email, then atomic write, then common logging
    assert_true validate_email "test@example.com" "Email validation should work"

    # Use atomic write
    echo "$test_content" | write_atomic "$test_file"
    assert_exists "$test_file" "Atomic write should create file"

    # Use common functions for logging (capture output)
    local log_output
    log_output="$(info "Integration test successful" 2>&1)"
    assert_contains "$log_output" "Integration test successful" "Common logging should work"

    # Use platform detection
    local os
    os="$(detect_os)"
    assert_true test -n "$os" "Platform detection should work"
}

# Test error handling across libraries
test_error_handling_integration() {
    # Test that validation catches bad input before atomic operations
    assert_false validate_email "invalid-email" "Validation should catch bad email"

    # Test that atomic operations handle bad paths gracefully
    assert_false bash -c 'echo "test" | write_atomic ""' "Atomic write should fail with empty path"
}

# Run integration tests
main() {
    setup_test_env

    run_tests \
        test_library_loading \
        test_inter_library_functionality \
        test_error_handling_integration

    cleanup_test_env
}

main "$@"
EOF

    chmod +x "$temp_script"

    # Run integration test
    if (
        cd "$SCRIPT_DIR"
        export TEST_VERBOSE=0
        bash "$temp_script"
    ) 2>&1; then
        printf "${C_PASS}✓ Integration tests PASSED${C_RESET}\n"
        ((PASSED_SUITES++))
    else
        printf "${C_FAIL}✗ Integration tests FAILED${C_RESET}\n"
        ((FAILED_SUITES++))
        FAILED_SUITE_NAMES+=("integration_tests")
    fi

    ((TOTAL_SUITES++))
    rm -f "$temp_script"
    echo
}

# Function: run_shellcheck_tests
# Purpose: Run shellcheck on all library files
run_shellcheck_tests() {
    printf "${C_INFO}Running shellcheck tests...${C_RESET}\n"

    local lib_files shellcheck_passed=0 shellcheck_failed=0
    lib_files=("$LIB_DIR"/*.sh)

    if command -v shellcheck >/dev/null 2>&1; then
        local file
        for file in "${lib_files[@]}"; do
            if [[ -f "$file" ]]; then
                printf "  Checking %s... " "$(basename "$file")"
                if shellcheck -x -S warning "$file" >/dev/null 2>&1; then
                    printf "${C_PASS}PASS${C_RESET}\n"
                    ((shellcheck_passed++))
                else
                    printf "${C_FAIL}FAIL${C_RESET}\n"
                    ((shellcheck_failed++))
                fi
            fi
        done

        if [[ $shellcheck_failed -eq 0 ]]; then
            printf "${C_PASS}✓ Shellcheck tests PASSED (%d files)${C_RESET}\n" "$shellcheck_passed"
            ((PASSED_SUITES++))
        else
            printf "${C_FAIL}✗ Shellcheck tests FAILED (%d failed, %d passed)${C_RESET}\n" "$shellcheck_failed" "$shellcheck_passed"
            ((FAILED_SUITES++))
            FAILED_SUITE_NAMES+=("shellcheck")
        fi
    else
        printf "${C_WARN}! Shellcheck not available, skipping${C_RESET}\n"
    fi

    ((TOTAL_SUITES++))
    echo
}

# Function: run_performance_tests
# Purpose: Run basic performance tests on library functions
run_performance_tests() {
    printf "${C_INFO}Running performance tests...${C_RESET}\n"

    local temp_script
    temp_script="$(mktemp)"

    cat > "$temp_script" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Load libraries
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/atomic.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/validation.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/platform.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/testing.sh"

# Performance test functions
test_validation_performance() {
    local start_time end_time duration
    local i

    start_time="$(date +%s%N)"
    for ((i=0; i<1000; i++)); do
        validate_email "test@example.com" >/dev/null
    done
    end_time="$(date +%s%N)"

    duration=$(((end_time - start_time) / 1000000))  # Convert to ms

    # Should complete 1000 validations in reasonable time (< 1000ms)
    assert_true test "$duration" -lt 1000 "Email validation should be fast (${duration}ms for 1000 iterations)"
}

test_platform_detection_performance() {
    local start_time end_time duration
    local i

    start_time="$(date +%s%N)"
    for ((i=0; i<100; i++)); do
        detect_os >/dev/null
        detect_distro >/dev/null
        detect_arch >/dev/null
    done
    end_time="$(date +%s%N)"

    duration=$(((end_time - start_time) / 1000000))  # Convert to ms

    # Should complete 100 detections quickly due to caching (< 100ms)
    assert_true test "$duration" -lt 100 "Platform detection should be fast due to caching (${duration}ms for 100 iterations)"
}

test_atomic_write_performance() {
    local start_time end_time duration
    local i test_file

    start_time="$(date +%s%N)"
    for ((i=0; i<50; i++)); do
        test_file="$TEST_TMPDIR/perf_test_$i.txt"
        echo "test content $i" | write_atomic "$test_file"
    done
    end_time="$(date +%s%N)"

    duration=$(((end_time - start_time) / 1000000))  # Convert to ms

    # Should complete 50 atomic writes in reasonable time (< 2000ms)
    assert_true test "$duration" -lt 2000 "Atomic writes should be reasonably fast (${duration}ms for 50 writes)"
}

# Run performance tests
main() {
    setup_test_env

    run_tests \
        test_validation_performance \
        test_platform_detection_performance \
        test_atomic_write_performance

    cleanup_test_env
}

main "$@"
EOF

    chmod +x "$temp_script"

    # Run performance test
    if (
        cd "$SCRIPT_DIR"
        export TEST_VERBOSE=0
        bash "$temp_script"
    ) 2>&1; then
        printf "${C_PASS}✓ Performance tests PASSED${C_RESET}\n"
        ((PASSED_SUITES++))
    else
        printf "${C_FAIL}✗ Performance tests FAILED${C_RESET}\n"
        ((FAILED_SUITES++))
        FAILED_SUITE_NAMES+=("performance_tests")
    fi

    ((TOTAL_SUITES++))
    rm -f "$temp_script"
    echo
}

# Function: generate_report
# Purpose: Generate final test report
generate_report() {
    local end_time duration
    end_time="$(date +%s)"
    duration=$((end_time - START_TIME))

    echo "==================== TEST REPORT ===================="
    echo "Test Duration: ${duration}s"
    echo "Total Suites:  $TOTAL_SUITES"
    printf "Passed:        ${C_PASS}%d${C_RESET}\n" "$PASSED_SUITES"
    printf "Failed:        ${C_FAIL}%d${C_RESET}\n" "$FAILED_SUITES"
    echo

    if [[ $FAILED_SUITES -gt 0 ]]; then
        printf "${C_FAIL}FAILED SUITES:${C_RESET}\n"
        local suite
        for suite in "${FAILED_SUITE_NAMES[@]}"; do
            printf "  - ${C_FAIL}%s${C_RESET}\n" "$suite"
        done
        echo
        printf "${C_FAIL}OVERALL RESULT: FAILED${C_RESET}\n"
        return 1
    else
        printf "${C_PASS}OVERALL RESULT: ALL TESTS PASSED!${C_RESET}\n"
        return 0
    fi
}

# Main function
main() {
    local START_TIME
    START_TIME="$(date +%s)"

    echo "==================== LIBRARY TEST SUITE ===================="
    echo "Testing machine-rites library modules..."
    echo "Start time: $(date)"
    echo

    # Find and run all test scripts
    local test_scripts
    test_scripts=("$SCRIPT_DIR"/test_*.sh)

    if [[ ${#test_scripts[@]} -eq 0 || ! -f "${test_scripts[0]}" ]]; then
        printf "${C_WARN}No test scripts found in %s${C_RESET}\n" "$SCRIPT_DIR"
        return 1
    fi

    # Run individual test suites
    local test_script
    for test_script in "${test_scripts[@]}"; do
        if [[ -f "$test_script" && "$test_script" != "${BASH_SOURCE[0]}" ]]; then
            run_test_suite "$test_script"
        fi
    done

    # Run additional test categories
    run_integration_tests
    run_shellcheck_tests
    run_performance_tests

    # Generate final report
    generate_report
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi