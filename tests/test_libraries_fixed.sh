#!/usr/bin/env bash
# tests/test_libraries_fixed.sh - Fixed comprehensive test suite for shell libraries
#
# Tests all functions in the /lib/ directory with proper error handling

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$PROJECT_ROOT/lib"

# Colors for output
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[1;33m'
readonly C_BLUE='\033[0;34m'
readonly C_NC='\033[0m' # No Color

# Test counters
declare -g TESTS_RUN=0
declare -g TESTS_PASSED=0
declare -g TESTS_FAILED=0
declare -g TEST_START_TIME=$(date +%s)

# Function: test_log
test_log() {
    local level="$1"
    shift
    local color=""

    case "$level" in
        PASS) color="$C_GREEN" ;;
        FAIL) color="$C_RED" ;;
        INFO) color="$C_BLUE" ;;
        WARN) color="$C_YELLOW" ;;
    esac

    printf "${color}[%s]${C_NC} %s\n" "$level" "$*"
}

# Function: run_test
# Purpose: Run a test and record results
run_test() {
    local test_name="$1"
    local test_command="$2"
    ((TESTS_RUN++))

    if eval "$test_command" >/dev/null 2>&1; then
        ((TESTS_PASSED++))
        test_log "PASS" "$test_name"
        return 0
    else
        ((TESTS_FAILED++))
        test_log "FAIL" "$test_name"
        return 1
    fi
}

# Function: run_test_with_output
# Purpose: Run test and check output
run_test_with_output() {
    local test_name="$1"
    local test_command="$2"
    local expected_pattern="$3"
    ((TESTS_RUN++))

    local output
    if output=$(eval "$test_command" 2>&1) && [[ "$output" == *"$expected_pattern"* ]]; then
        ((TESTS_PASSED++))
        test_log "PASS" "$test_name"
        return 0
    else
        ((TESTS_FAILED++))
        test_log "FAIL" "$test_name (output: $output)"
        return 1
    fi
}

# Function: test_lib_common
test_lib_common() {
    test_log "INFO" "Testing lib/common.sh..."

    # Test library loading
    run_test "common.sh loads successfully" "source '$LIB_DIR/common.sh'"

    # Test logging functions
    run_test_with_output "say() function works" "source '$LIB_DIR/common.sh' && say 'test message'" "[+]"
    run_test_with_output "info() function works" "source '$LIB_DIR/common.sh' && info 'test message'" "[i]"
    run_test_with_output "warn() function works" "source '$LIB_DIR/common.sh' && warn 'test message'" "[!]"

    # Test debug_var
    run_test_with_output "debug_var() function works" "TEST_VAR='test' source '$LIB_DIR/common.sh' && debug_var 'TEST_VAR'" "TEST_VAR=test"

    # Test require_user (should pass for non-root)
    run_test "require_user() passes for non-root" "source '$LIB_DIR/common.sh' && require_user"

    # Test check_dependencies with existing commands
    run_test "check_dependencies() with valid commands" "source '$LIB_DIR/common.sh' && check_dependencies bash ls"

    # Test version variable
    run_test_with_output "Library version available" "source '$LIB_DIR/common.sh' && echo \$LIB_COMMON_VERSION" "1.0.0"

    test_log "INFO" "lib/common.sh tests completed"
}

# Function: test_lib_atomic
test_lib_atomic() {
    test_log "INFO" "Testing lib/atomic.sh..."

    local test_dir="/tmp/atomic_test_$$"

    # Test library loading
    run_test "atomic.sh loads successfully" "source '$LIB_DIR/atomic.sh'"

    # Test write_atomic function
    run_test "write_atomic() creates file" "
        mkdir -p '$test_dir' && cd '$test_dir' &&
        source '$LIB_DIR/atomic.sh' &&
        echo 'test content' | write_atomic 'test_file.txt' &&
        test -f 'test_file.txt' &&
        grep -q 'test content' 'test_file.txt'
    "

    # Test backup_file function
    run_test "backup_file() creates backup" "
        mkdir -p '$test_dir' && cd '$test_dir' &&
        source '$LIB_DIR/atomic.sh' &&
        echo 'original' > 'original.txt' &&
        backup_file 'original.txt' >/dev/null &&
        ls backups/original.txt.* >/dev/null 2>&1
    "

    # Test mktemp_secure function
    run_test "mktemp_secure() creates secure temp file" "
        source '$LIB_DIR/atomic.sh' &&
        temp_file=\$(mktemp_secure) &&
        test -f \"\$temp_file\" &&
        rm -f \"\$temp_file\"
    "

    # Test atomic_append function
    run_test "atomic_append() appends content" "
        mkdir -p '$test_dir' && cd '$test_dir' &&
        source '$LIB_DIR/atomic.sh' &&
        echo 'line1' > 'append_test.txt' &&
        echo 'line2' | atomic_append 'append_test.txt' &&
        grep -q 'line1' 'append_test.txt' &&
        grep -q 'line2' 'append_test.txt'
    "

    # Test atomic_replace function
    run_test "atomic_replace() replaces content" "
        mkdir -p '$test_dir' && cd '$test_dir' &&
        source '$LIB_DIR/atomic.sh' &&
        echo 'old text here' > 'replace_test.txt' &&
        atomic_replace 'replace_test.txt' 'old' 'new' &&
        grep -q 'new text here' 'replace_test.txt'
    "

    # Cleanup
    rm -rf "$test_dir"

    test_log "INFO" "lib/atomic.sh tests completed"
}

# Function: test_lib_validation
test_lib_validation() {
    test_log "INFO" "Testing lib/validation.sh..."

    # Test library loading
    run_test "validation.sh loads successfully" "source '$LIB_DIR/validation.sh'"

    # Test email validation
    run_test "validate_email() accepts valid email" "source '$LIB_DIR/validation.sh' && validate_email 'user@example.com'"
    run_test "validate_email() rejects invalid email" "source '$LIB_DIR/validation.sh' && ! validate_email 'invalid-email'"

    # Test URL validation
    run_test "validate_url() accepts valid URL" "source '$LIB_DIR/validation.sh' && validate_url 'https://example.com'"
    run_test "validate_url() rejects invalid URL" "source '$LIB_DIR/validation.sh' && ! validate_url 'not-a-url'"

    # Test hostname validation
    run_test "validate_hostname() accepts valid hostname" "source '$LIB_DIR/validation.sh' && validate_hostname 'example.com'"
    run_test "validate_hostname() rejects invalid hostname" "source '$LIB_DIR/validation.sh' && ! validate_hostname 'invalid_hostname.com'"

    # Test port validation
    run_test "validate_port() accepts valid port" "source '$LIB_DIR/validation.sh' && validate_port '8080'"
    run_test "validate_port() rejects invalid port" "source '$LIB_DIR/validation.sh' && ! validate_port '65536'"

    # Test IP validation
    run_test "validate_ip() accepts valid IP" "source '$LIB_DIR/validation.sh' && validate_ip '192.168.1.1'"
    run_test "validate_ip() rejects invalid IP" "source '$LIB_DIR/validation.sh' && ! validate_ip '256.1.1.1'"

    # Test sanitize_filename
    run_test_with_output "sanitize_filename() works" "source '$LIB_DIR/validation.sh' && sanitize_filename 'test/file.txt'" "test_file.txt"

    # Test is_safe_string
    run_test "is_safe_string() accepts safe string" "source '$LIB_DIR/validation.sh' && is_safe_string 'safe_string'"
    run_test "is_safe_string() rejects unsafe string" "source '$LIB_DIR/validation.sh' && ! is_safe_string 'unsafe\$(command)'"

    # Test validate_version
    run_test "validate_version() accepts semantic version" "source '$LIB_DIR/validation.sh' && validate_version '1.2.3'"
    run_test "validate_version() rejects invalid version" "source '$LIB_DIR/validation.sh' && ! validate_version '1.2'"

    # Test validate_numeric
    run_test "validate_numeric() accepts number" "source '$LIB_DIR/validation.sh' && validate_numeric '42'"
    run_test "validate_numeric() rejects non-number" "source '$LIB_DIR/validation.sh' && ! validate_numeric 'abc'"

    test_log "INFO" "lib/validation.sh tests completed"
}

# Function: test_lib_platform
test_lib_platform() {
    test_log "INFO" "Testing lib/platform.sh..."

    # Test library loading
    run_test "platform.sh loads successfully" "source '$LIB_DIR/platform.sh'"

    # Test OS detection
    run_test_with_output "detect_os() returns OS" "source '$LIB_DIR/platform.sh' && detect_os" "linux"

    # Test distribution detection
    run_test "detect_distro() returns distribution" "source '$LIB_DIR/platform.sh' && test -n \"\$(detect_distro)\""

    # Test architecture detection
    run_test "detect_arch() returns architecture" "source '$LIB_DIR/platform.sh' && test -n \"\$(detect_arch)\""

    # Test package manager detection
    run_test "get_package_manager() returns package manager" "source '$LIB_DIR/platform.sh' && test -n \"\$(get_package_manager)\""

    # Test supported platform check
    run_test "is_supported_platform() works" "source '$LIB_DIR/platform.sh' && is_supported_platform"

    # Test kernel version check
    run_test "check_kernel_version() works with old version" "source '$LIB_DIR/platform.sh' && check_kernel_version '2.6.0'"

    # Test system info
    run_test_with_output "get_system_info() provides info" "source '$LIB_DIR/platform.sh' && get_system_info" "System Information"

    # Test distro version
    run_test "get_distro_version() returns version" "source '$LIB_DIR/platform.sh' && test -n \"\$(get_distro_version)\""

    test_log "INFO" "lib/platform.sh tests completed"
}

# Function: test_lib_testing
test_lib_testing() {
    test_log "INFO" "Testing lib/testing.sh..."

    # Test library loading
    run_test "testing.sh loads successfully" "source '$LIB_DIR/testing.sh'"

    # Test setup and cleanup functions
    run_test "setup_test_env() and cleanup_test_env() work" "
        source '$LIB_DIR/testing.sh' &&
        setup_test_env &&
        test -d \"\$TEST_TMPDIR\" &&
        test_tmpdir=\"\$TEST_TMPDIR\" &&
        cleanup_test_env &&
        test ! -d \"\$test_tmpdir\"
    "

    # Test assertion functions existence
    run_test "assert_equals function exists" "source '$LIB_DIR/testing.sh' && declare -F assert_equals >/dev/null"
    run_test "assert_true function exists" "source '$LIB_DIR/testing.sh' && declare -F assert_true >/dev/null"
    run_test "assert_false function exists" "source '$LIB_DIR/testing.sh' && declare -F assert_false >/dev/null"
    run_test "assert_exists function exists" "source '$LIB_DIR/testing.sh' && declare -F assert_exists >/dev/null"

    test_log "INFO" "lib/testing.sh tests completed"
}

# Function: test_integration
test_integration() {
    test_log "INFO" "Testing library integration..."

    # Test loading multiple libraries together
    run_test "All libraries load together" "
        source '$LIB_DIR/common.sh' &&
        source '$LIB_DIR/atomic.sh' &&
        source '$LIB_DIR/validation.sh' &&
        source '$LIB_DIR/platform.sh' &&
        source '$LIB_DIR/testing.sh' &&
        test -n \"\$LIB_COMMON_VERSION\" &&
        test -n \"\$LIB_ATOMIC_VERSION\" &&
        test -n \"\$LIB_VALIDATION_VERSION\" &&
        test -n \"\$LIB_PLATFORM_VERSION\" &&
        test -n \"\$LIB_TESTING_VERSION\"
    "

    # Test integration scenario: validate email and store atomically
    run_test "Integration: validate and store email" "
        test_dir='/tmp/integration_test_$$' &&
        mkdir -p \"\$test_dir\" &&
        cd \"\$test_dir\" &&
        source '$LIB_DIR/validation.sh' &&
        source '$LIB_DIR/atomic.sh' &&
        validate_email 'test@example.com' &&
        echo 'test@example.com' | write_atomic 'email.txt' &&
        test -f 'email.txt' &&
        grep -q 'test@example.com' 'email.txt' &&
        cd / &&
        rm -rf \"\$test_dir\"
    "

    # Test integration: platform detection with logging
    run_test "Integration: platform detection with logging" "
        source '$LIB_DIR/platform.sh' &&
        source '$LIB_DIR/common.sh' &&
        os=\$(detect_os) &&
        info \"Detected OS: \$os\" >/dev/null 2>&1
    "

    test_log "INFO" "Library integration tests completed"
}

# Function: run_all_tests
run_all_tests() {
    test_log "INFO" "Starting comprehensive library test suite..."
    test_log "INFO" "Testing libraries in: $LIB_DIR"

    # Verify all libraries exist
    local libs=(common.sh atomic.sh validation.sh platform.sh testing.sh)
    local lib
    for lib in "${libs[@]}"; do
        if [[ ! -f "$LIB_DIR/$lib" ]]; then
            test_log "FAIL" "Library not found: $LIB_DIR/$lib"
            exit 1
        fi
    done

    # Run tests for each library
    test_lib_common
    test_lib_atomic
    test_lib_validation
    test_lib_platform
    test_lib_testing
    test_integration

    # Final report
    local end_time=$(date +%s)
    local duration=$((end_time - TEST_START_TIME))

    echo
    test_log "INFO" "=============================================="
    test_log "INFO" "TEST SUITE COMPLETE"
    test_log "INFO" "=============================================="
    test_log "INFO" "Duration: ${duration}s"
    test_log "INFO" "Tests run: $TESTS_RUN"
    test_log "PASS" "Tests passed: $TESTS_PASSED"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        test_log "FAIL" "Tests failed: $TESTS_FAILED"
        test_log "FAIL" "OVERALL RESULT: FAILED"
        return 1
    else
        test_log "PASS" "Tests failed: $TESTS_FAILED"
        test_log "PASS" "OVERALL RESULT: ALL TESTS PASSED"
        return 0
    fi
}

# Main execution
main() {
    if [[ ! -d "$LIB_DIR" ]]; then
        test_log "FAIL" "Libraries directory not found: $LIB_DIR"
        exit 1
    fi

    if run_all_tests; then
        exit 0
    else
        exit 1
    fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi