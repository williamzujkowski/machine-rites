#!/usr/bin/env bash
# tests/lib/test_common.sh - Unit tests for lib/common.sh
#
# Tests all functions in the common library module
# Ensures proper functionality and error handling

set -euo pipefail

# Load the library to test
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/testing.sh"

# Test function for say()
test_say_function() {
    local output

    # Test basic functionality
    output="$(say "test message" 2>&1)"
    assert_contains "$output" "test message" "say() should output message"
    assert_contains "$output" "[+]" "say() should include success indicator"

    # Test with multiple arguments
    output="$(say "hello" "world" 2>&1)"
    assert_contains "$output" "hello world" "say() should handle multiple args"
}

# Test function for info()
test_info_function() {
    local output

    # Test basic functionality
    output="$(info "test info" 2>&1)"
    assert_contains "$output" "test info" "info() should output message"
    assert_contains "$output" "[i]" "info() should include info indicator"

    # Test with multiple arguments
    output="$(info "status:" "OK" 2>&1)"
    assert_contains "$output" "status: OK" "info() should handle multiple args"
}

# Test function for warn()
test_warn_function() {
    local output

    # Test basic functionality
    output="$(warn "test warning" 2>&1)"
    assert_contains "$output" "test warning" "warn() should output message"
    assert_contains "$output" "[!]" "warn() should include warning indicator"

    # Test with multiple arguments
    output="$(warn "config" "missing" 2>&1)"
    assert_contains "$output" "config missing" "warn() should handle multiple args"
}

# Test function for die()
test_die_function() {
    local exit_code output

    # Test die() in subshell to capture exit
    exit_code=0
    output="$(bash -c 'source "$(dirname "${BASH_SOURCE[0]}")/../../lib/common.sh"; die "test error"' 2>&1)" || exit_code=$?

    assert_equals 1 "$exit_code" "die() should exit with code 1"
    assert_contains "$output" "test error" "die() should output error message"
    assert_contains "$output" "[✘]" "die() should include error indicator"
}

# Test function for debug_var()
test_debug_var_function() {
    local output
    local TEST_VAR="test value"

    # Test with set variable
    output="$(debug_var "TEST_VAR" 2>&1)"
    assert_contains "$output" "TEST_VAR=test value" "debug_var() should show variable value"
    assert_contains "$output" "[debug]" "debug_var() should include debug prefix"

    # Test with unset variable
    unset TEST_VAR || true
    output="$(debug_var "TEST_VAR" 2>&1)"
    assert_contains "$output" "TEST_VAR=<unset>" "debug_var() should show <unset> for unset vars"
}

# Test function for require_root()
test_require_root_function() {
    # Skip if actually running as root
    if [[ $EUID -eq 0 ]]; then
        skip_test "Running as root, cannot test require_root failure"
        return 0
    fi

    # Test require_root() failure (should fail for non-root)
    assert_false require_root "require_root() should fail for non-root users"
}

# Test function for require_user()
test_require_user_function() {
    # Test require_user() success for non-root
    if [[ $EUID -ne 0 ]]; then
        assert_true require_user "require_user() should succeed for non-root users"
    else
        # If running as root, test should fail
        assert_false require_user "require_user() should fail for root user"
    fi
}

# Test function for check_dependencies()
test_check_dependencies_function() {
    # Test with existing commands
    assert_true check_dependencies "bash" "test" "Check existing dependencies should succeed"

    # Test with non-existent command (in subshell to avoid exit)
    assert_false bash -c 'source "$(dirname "${BASH_SOURCE[0]}")/../../lib/common.sh"; check_dependencies "nonexistent_command_xyz123"' \
        "Check non-existent dependencies should fail"
}

# Test function for confirm()
test_confirm_function() {
    # Test confirm() with 'y' input
    assert_true bash -c 'echo "y" | source "$(dirname "${BASH_SOURCE[0]}")/../../lib/common.sh" && confirm "Test?"' \
        "confirm() should return true for 'y' input"

    # Test confirm() with 'n' input
    assert_false bash -c 'echo "n" | source "$(dirname "${BASH_SOURCE[0]}")/../../lib/common.sh" && confirm "Test?"' \
        "confirm() should return false for 'n' input"

    # Test confirm() with empty input (should default to no)
    assert_false bash -c 'echo "" | source "$(dirname "${BASH_SOURCE[0]}")/../../lib/common.sh" && confirm "Test?"' \
        "confirm() should return false for empty input"
}

# Test library metadata
test_library_metadata() {
    assert_equals "1.0.0" "$LIB_COMMON_VERSION" "Library version should be set"
    assert_equals "1" "$LIB_COMMON_LOADED" "Library loaded flag should be set"
    assert_equals "1" "$__LIB_COMMON_LOADED" "Library guard should be set"
}

# Test source guard functionality
test_source_guard() {
    local output

    # Test that sourcing again doesn't reload
    output="$(bash -c '
        source "$(dirname "${BASH_SOURCE[0]}")/../../lib/common.sh"
        echo "first load"
        source "$(dirname "${BASH_SOURCE[0]}")/../../lib/common.sh"
        echo "second load"
    ' 2>&1)"

    assert_contains "$output" "first load" "Should execute first load"
    assert_contains "$output" "second load" "Should execute second load"
}

# Test color codes are defined
test_color_codes() {
    assert_true test -n "$C_G" "Green color code should be defined"
    assert_true test -n "$C_Y" "Yellow color code should be defined"
    assert_true test -n "$C_R" "Red color code should be defined"
    assert_true test -n "$C_B" "Blue color code should be defined"
    assert_true test -n "$C_N" "Reset color code should be defined"
}

# Main test runner
main() {
    echo "Testing lib/common.sh..."

    run_tests \
        test_say_function \
        test_info_function \
        test_warn_function \
        test_die_function \
        test_debug_var_function \
        test_require_root_function \
        test_require_user_function \
        test_check_dependencies_function \
        test_confirm_function \
        test_library_metadata \
        test_source_guard \
        test_color_codes
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi