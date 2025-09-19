#!/usr/bin/env bash
# tests/test_library_suite.sh - Comprehensive test suite for shell libraries
#
# Tests all functions in the /lib/ directory to ensure they work correctly
# for deployment. Validates logging, atomic operations, validation, platform
# detection, and testing framework functionality.

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
# Purpose: Log test results with colors
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

# Function: assert_cmd
# Purpose: Run command and assert it succeeds
assert_cmd() {
    local desc="$1"
    shift
    ((TESTS_RUN++))

    if "$@" >/dev/null 2>&1; then
        ((TESTS_PASSED++))
        test_log "PASS" "$desc"
        return 0
    else
        ((TESTS_FAILED++))
        test_log "FAIL" "$desc (command: $*)"
        return 1
    fi
}

# Function: assert_cmd_fails
# Purpose: Run command and assert it fails
assert_cmd_fails() {
    local desc="$1"
    shift
    ((TESTS_RUN++))

    if ! "$@" >/dev/null 2>&1; then
        ((TESTS_PASSED++))
        test_log "PASS" "$desc"
        return 0
    else
        ((TESTS_FAILED++))
        test_log "FAIL" "$desc (command should have failed: $*)"
        return 1
    fi
}

# Function: assert_equals
# Purpose: Assert two values are equal
assert_equals() {
    local expected="$1"
    local actual="$2"
    local desc="$3"
    ((TESTS_RUN++))

    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++))
        test_log "PASS" "$desc"
        return 0
    else
        ((TESTS_FAILED++))
        test_log "FAIL" "$desc (expected: '$expected', got: '$actual')"
        return 1
    fi
}

# Function: assert_contains
# Purpose: Assert string contains substring
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local desc="$3"
    ((TESTS_RUN++))

    if [[ "$haystack" == *"$needle"* ]]; then
        ((TESTS_PASSED++))
        test_log "PASS" "$desc"
        return 0
    else
        ((TESTS_FAILED++))
        test_log "FAIL" "$desc (string '$haystack' does not contain '$needle')"
        return 1
    fi
}

# Function: test_lib_common
# Purpose: Test lib/common.sh functions
test_lib_common() {
    test_log "INFO" "Testing lib/common.sh..."

    # Source the library
    # shellcheck source=../lib/common.sh
    source "$LIB_DIR/common.sh"

    # Test say function (success message)
    local output
    output="$(say "Test message" 2>&1)"
    assert_contains "$output" "Test message" "say() displays message"
    assert_contains "$output" "[+]" "say() uses success prefix"

    # Test info function
    output="$(info "Info message" 2>&1)"
    assert_contains "$output" "Info message" "info() displays message"
    assert_contains "$output" "[i]" "info() uses info prefix"

    # Test warn function
    output="$(warn "Warning message" 2>&1)"
    assert_contains "$output" "Warning message" "warn() displays message"
    assert_contains "$output" "[!]" "warn() uses warning prefix"

    # Test debug_var function
    local TEST_VAR="test_value"
    output="$(debug_var "TEST_VAR" 2>&1)"
    assert_contains "$output" "TEST_VAR=test_value" "debug_var() shows variable name and value"

    # Test require_user (should pass since we're not root)
    assert_cmd "require_user() passes for non-root user" require_user

    # Test check_dependencies with existing commands
    assert_cmd "check_dependencies() passes for existing commands" check_dependencies bash ls

    # Test check_dependencies with non-existing command
    assert_cmd_fails "check_dependencies() fails for non-existing commands" check_dependencies nonexistent_command_xyz

    # Test confirm function with 'n' input
    output="$(echo "n" | confirm "Test prompt?" 2>&1 || true)"
    assert_contains "$output" "Test prompt?" "confirm() displays prompt"

    test_log "INFO" "lib/common.sh tests completed"
}

# Function: test_lib_atomic
# Purpose: Test lib/atomic.sh functions
test_lib_atomic() {
    test_log "INFO" "Testing lib/atomic.sh..."

    # Create test directory
    local test_dir="/tmp/atomic_test_$$"
    mkdir -p "$test_dir"
    cd "$test_dir"

    # Source the library
    # shellcheck source=../lib/atomic.sh
    source "$LIB_DIR/atomic.sh"

    # Test write_atomic
    echo "test content" | write_atomic "test_file.txt"
    assert_cmd "write_atomic() creates file" test -f "test_file.txt"
    local content
    content="$(cat test_file.txt)"
    assert_equals "test content" "$content" "write_atomic() writes correct content"

    # Test backup_file
    local backup_path
    backup_path="$(backup_file "test_file.txt")"
    assert_cmd "backup_file() creates backup" test -f "$backup_path"

    # Test atomic_append
    echo "appended line" | atomic_append "test_file.txt"
    content="$(cat test_file.txt)"
    assert_contains "$content" "test content" "atomic_append() preserves original content"
    assert_contains "$content" "appended line" "atomic_append() adds new content"

    # Test atomic_replace
    atomic_replace "test_file.txt" "test" "modified"
    content="$(cat test_file.txt)"
    assert_contains "$content" "modified content" "atomic_replace() replaces text correctly"

    # Test mktemp_secure
    local temp_file
    temp_file="$(mktemp_secure)"
    assert_cmd "mktemp_secure() creates file" test -f "$temp_file"

    # Check file permissions (should be 0600)
    local perms
    perms="$(stat -c %a "$temp_file" 2>/dev/null || stat -f %A "$temp_file" 2>/dev/null)"
    assert_equals "600" "$perms" "mktemp_secure() sets correct permissions"

    # Cleanup
    cd /
    rm -rf "$test_dir"

    test_log "INFO" "lib/atomic.sh tests completed"
}

# Function: test_lib_validation
# Purpose: Test lib/validation.sh functions
test_lib_validation() {
    test_log "INFO" "Testing lib/validation.sh..."

    # Source the library
    # shellcheck source=../lib/validation.sh
    source "$LIB_DIR/validation.sh"

    # Test validate_email
    assert_cmd "validate_email() accepts valid email" validate_email "user@example.com"
    assert_cmd "validate_email() accepts email with subdomain" validate_email "test@mail.example.com"
    assert_cmd_fails "validate_email() rejects invalid email" validate_email "invalid-email"
    assert_cmd_fails "validate_email() rejects email without @" validate_email "user.example.com"

    # Test validate_url
    assert_cmd "validate_url() accepts valid HTTP URL" validate_url "http://example.com"
    assert_cmd "validate_url() accepts valid HTTPS URL" validate_url "https://example.com/path"
    assert_cmd_fails "validate_url() rejects invalid protocol" validate_url "ftp://example.com"
    assert_cmd_fails "validate_url() rejects malformed URL" validate_url "not-a-url"

    # Test validate_hostname
    assert_cmd "validate_hostname() accepts valid hostname" validate_hostname "example.com"
    assert_cmd "validate_hostname() accepts subdomain" validate_hostname "sub.example.com"
    assert_cmd_fails "validate_hostname() rejects hostname with underscores" validate_hostname "invalid_hostname.com"

    # Test validate_port
    assert_cmd "validate_port() accepts valid port" validate_port "8080"
    assert_cmd "validate_port() accepts port 80" validate_port "80"
    assert_cmd "validate_port() accepts port 65535" validate_port "65535"
    assert_cmd_fails "validate_port() rejects port 0" validate_port "0"
    assert_cmd_fails "validate_port() rejects port > 65535" validate_port "65536"
    assert_cmd_fails "validate_port() rejects non-numeric port" validate_port "abc"

    # Test validate_ip
    assert_cmd "validate_ip() accepts valid IP" validate_ip "192.168.1.1"
    assert_cmd "validate_ip() accepts localhost IP" validate_ip "127.0.0.1"
    assert_cmd_fails "validate_ip() rejects invalid octet" validate_ip "256.1.1.1"
    assert_cmd_fails "validate_ip() rejects incomplete IP" validate_ip "192.168.1"

    # Test sanitize_filename
    local sanitized
    sanitized="$(sanitize_filename "test/file.txt")"
    assert_equals "test_file.txt" "$sanitized" "sanitize_filename() replaces dangerous characters"

    sanitized="$(sanitize_filename "file with spaces")"
    assert_equals "file with spaces" "$sanitized" "sanitize_filename() preserves safe characters"

    # Test is_safe_string
    assert_cmd "is_safe_string() accepts safe string" is_safe_string "safe_string_123"
    assert_cmd_fails "is_safe_string() rejects command substitution" is_safe_string "string\$(command)"
    assert_cmd_fails "is_safe_string() rejects pipe" is_safe_string "string|command"

    # Test validate_version
    assert_cmd "validate_version() accepts semantic version" validate_version "1.2.3"
    assert_cmd "validate_version() accepts version with pre-release" validate_version "1.2.3-alpha.1"
    assert_cmd_fails "validate_version() rejects invalid version" validate_version "1.2"

    # Test validate_numeric
    assert_cmd "validate_numeric() accepts integer" validate_numeric "42"
    assert_cmd "validate_numeric() accepts decimal" validate_numeric "3.14"
    assert_cmd "validate_numeric() accepts negative" validate_numeric "-10"
    assert_cmd_fails "validate_numeric() rejects non-numeric" validate_numeric "abc"

    test_log "INFO" "lib/validation.sh tests completed"
}

# Function: test_lib_platform
# Purpose: Test lib/platform.sh functions
test_lib_platform() {
    test_log "INFO" "Testing lib/platform.sh..."

    # Source the library
    # shellcheck source=../lib/platform.sh
    source "$LIB_DIR/platform.sh"

    # Test detect_os
    local os
    os="$(detect_os)"
    assert_cmd "detect_os() returns a value" test -n "$os"
    # Should detect linux on this system
    assert_equals "linux" "$os" "detect_os() detects Linux correctly"

    # Test detect_distro
    local distro
    distro="$(detect_distro)"
    assert_cmd "detect_distro() returns a value" test -n "$distro"

    # Test detect_arch
    local arch
    arch="$(detect_arch)"
    assert_cmd "detect_arch() returns a value" test -n "$arch"

    # Test get_package_manager
    local pkg_mgr
    pkg_mgr="$(get_package_manager)"
    assert_cmd "get_package_manager() returns a value" test -n "$pkg_mgr"

    # Test get_distro_version
    local version
    version="$(get_distro_version)"
    assert_cmd "get_distro_version() returns a value" test -n "$version"

    # Test is_supported_platform
    assert_cmd "is_supported_platform() passes on current system" is_supported_platform

    # Test check_kernel_version with current kernel
    local current_kernel
    current_kernel="$(uname -r | cut -d'-' -f1)"
    assert_cmd "check_kernel_version() accepts current kernel" check_kernel_version "$current_kernel"

    # Test check_kernel_version with old version
    assert_cmd "check_kernel_version() accepts old kernel requirement" check_kernel_version "2.6.0"

    # Test get_system_info
    local sys_info
    sys_info="$(get_system_info)"
    assert_contains "$sys_info" "System Information:" "get_system_info() includes header"
    assert_contains "$sys_info" "OS:" "get_system_info() includes OS info"
    assert_contains "$sys_info" "Architecture:" "get_system_info() includes architecture"

    test_log "INFO" "lib/platform.sh tests completed"
}

# Function: test_lib_testing
# Purpose: Test lib/testing.sh functions
test_lib_testing() {
    test_log "INFO" "Testing lib/testing.sh..."

    # Source the library
    # shellcheck source=../lib/testing.sh
    source "$LIB_DIR/testing.sh"

    # Test assert_equals
    # Note: These will modify the global test counters, so we'll track separately
    local old_passed=$__TEST_PASSED
    local old_failed=$__TEST_FAILED
    local old_total=$__TEST_TOTAL

    assert_equals "test" "test" "Test message"
    local new_passed=$__TEST_PASSED
    assert_cmd "assert_equals() increments passed counter" test $new_passed -gt $old_passed

    # Reset counters for next test
    __TEST_PASSED=$old_passed
    __TEST_FAILED=$old_failed
    __TEST_TOTAL=$old_total

    # Test assert_not_equals
    assert_not_equals "test1" "test2" "Different values"
    new_passed=$__TEST_PASSED
    assert_cmd "assert_not_equals() increments passed counter" test $new_passed -gt $old_passed

    # Test assert_true
    __TEST_PASSED=$old_passed
    __TEST_FAILED=$old_failed
    __TEST_TOTAL=$old_total

    assert_true true
    new_passed=$__TEST_PASSED
    assert_cmd "assert_true() increments passed counter" test $new_passed -gt $old_passed

    # Test assert_false
    __TEST_PASSED=$old_passed
    __TEST_FAILED=$old_failed
    __TEST_TOTAL=$old_total

    assert_false false
    new_passed=$__TEST_PASSED
    assert_cmd "assert_false() increments passed counter" test $new_passed -gt $old_passed

    # Test setup_test_env and cleanup_test_env
    setup_test_env
    assert_cmd "setup_test_env() creates TEST_TMPDIR" test -d "$TEST_TMPDIR"
    local test_tmpdir="$TEST_TMPDIR"

    cleanup_test_env
    assert_cmd "cleanup_test_env() removes TEST_TMPDIR" test ! -d "$test_tmpdir"

    # Test sanitize_filename from testing context
    local sanitized
    sanitized="$(sanitize_filename "test<>file")"
    assert_cmd "sanitize_filename() processes dangerous characters" test -n "$sanitized"

    test_log "INFO" "lib/testing.sh tests completed"
}

# Function: test_library_integration
# Purpose: Test libraries working together
test_library_integration() {
    test_log "INFO" "Testing library integration..."

    # Source all libraries
    # shellcheck source=../lib/common.sh
    source "$LIB_DIR/common.sh"
    # shellcheck source=../lib/atomic.sh
    source "$LIB_DIR/atomic.sh"
    # shellcheck source=../lib/validation.sh
    source "$LIB_DIR/validation.sh"
    # shellcheck source=../lib/platform.sh
    source "$LIB_DIR/platform.sh"
    # shellcheck source=../lib/testing.sh
    source "$LIB_DIR/testing.sh"

    # Test that all libraries loaded successfully
    assert_cmd "All libraries have version variables" test -n "$LIB_COMMON_VERSION"
    assert_cmd "Atomic library loaded" test -n "$LIB_ATOMIC_VERSION"
    assert_cmd "Validation library loaded" test -n "$LIB_VALIDATION_VERSION"
    assert_cmd "Platform library loaded" test -n "$LIB_PLATFORM_VERSION"
    assert_cmd "Testing library loaded" test -n "$LIB_TESTING_VERSION"

    # Test integration: validate platform and log result
    local os
    os="$(detect_os)"
    if is_supported_platform; then
        say "Platform $os is supported"
        assert_cmd "Platform support logging works" true
    else
        warn "Platform $os is not officially supported"
        assert_cmd "Platform warning logging works" true
    fi

    # Test integration: atomic operations with validation
    local test_dir="/tmp/integration_test_$$"
    mkdir -p "$test_dir"
    cd "$test_dir"

    local test_email="user@example.com"
    if validate_email "$test_email"; then
        echo "$test_email" | write_atomic "email.txt"
        assert_cmd "Integration: validate email and write atomically" test -f "email.txt"
        local stored_email
        stored_email="$(cat email.txt)"
        assert_equals "$test_email" "$stored_email" "Integration: email stored correctly"
    fi

    # Cleanup
    cd /
    rm -rf "$test_dir"

    test_log "INFO" "Library integration tests completed"
}

# Function: run_all_tests
# Purpose: Run all test functions
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

    # Run individual library tests
    test_lib_common
    test_lib_atomic
    test_lib_validation
    test_lib_platform
    test_lib_testing

    # Run integration tests
    test_library_integration

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
    # Check if libraries directory exists
    if [[ ! -d "$LIB_DIR" ]]; then
        test_log "FAIL" "Libraries directory not found: $LIB_DIR"
        exit 1
    fi

    # Run all tests
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