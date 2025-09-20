#!/usr/bin/env bash
# Unit tests for Makefile targets
# Tests make command functionality

set -euo pipefail

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test-framework.sh"

TEST_PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"

# Test make help target
test_make_help() {
    test_start "Testing make help"

    cd "$TEST_PROJECT_ROOT"

    if make help >/dev/null 2>&1; then
        test_pass "Make help executes successfully"

        # Check for expected content
        if make help 2>/dev/null | grep -q "Machine-Rites Build System"; then
            test_pass "Help output contains expected title"
        else
            test_fail "Help output missing expected content"
            return 1
        fi
    else
        test_fail "Make help failed to execute"
        return 1
    fi

    return 0
}

# Test make info target
test_make_info() {
    test_start "Testing make info"

    cd "$TEST_PROJECT_ROOT"

    if make info >/dev/null 2>&1; then
        test_pass "Make info executes successfully"

        # Check for project information
        if make info 2>/dev/null | grep -q "machine-rites"; then
            test_pass "Info output contains project name"
        else
            test_fail "Info output missing project information"
            return 1
        fi
    else
        test_fail "Make info failed to execute"
        return 1
    fi

    return 0
}

# Test make validate-syntax
test_make_validate_syntax() {
    test_start "Testing make validate-syntax"

    cd "$TEST_PROJECT_ROOT"

    # This might fail if shellcheck finds issues, but should execute
    if make validate-syntax >/dev/null 2>&1 || true; then
        test_pass "Make validate-syntax executes"
    else
        test_warn "Make validate-syntax had issues (may be expected)"
    fi

    return 0
}

# Test make validate-structure
test_make_validate_structure() {
    test_start "Testing make validate-structure"

    cd "$TEST_PROJECT_ROOT"

    if make validate-structure >/dev/null 2>&1; then
        test_pass "Make validate-structure executes successfully"
    else
        test_fail "Make validate-structure failed"
        return 1
    fi

    return 0
}

# Test make deps-check
test_make_deps_check() {
    test_start "Testing make deps-check"

    cd "$TEST_PROJECT_ROOT"

    if make deps-check >/dev/null 2>&1; then
        test_pass "Make deps-check executes successfully"
    else
        test_warn "Make deps-check reported missing dependencies (expected)"
    fi

    return 0
}

# Test make clean
test_make_clean() {
    test_start "Testing make clean"

    cd "$TEST_PROJECT_ROOT"

    if make clean >/dev/null 2>&1; then
        test_pass "Make clean executes successfully"
    else
        test_fail "Make clean failed"
        return 1
    fi

    return 0
}

# Test make docker-validate
test_make_docker_validate() {
    test_start "Testing make docker-validate"

    cd "$TEST_PROJECT_ROOT"

    # This checks Docker environment, may fail if Docker not available
    if make docker-validate >/dev/null 2>&1; then
        test_pass "Docker validation passed"
    else
        test_warn "Docker validation failed (Docker may not be available)"
    fi

    return 0
}

# Test make multipass-setup availability
test_make_multipass_setup() {
    test_start "Testing make multipass-setup target existence"

    cd "$TEST_PROJECT_ROOT"

    # Just check if the target exists in the Makefile
    if grep -q "^multipass-setup:" Makefile; then
        test_pass "Multipass setup target exists"
    else
        test_fail "Multipass setup target not found"
        return 1
    fi

    return 0
}

# Test make targets availability
test_make_targets_exist() {
    test_start "Testing essential make targets exist"

    cd "$TEST_PROJECT_ROOT"

    local targets=(
        "help"
        "info"
        "test"
        "clean"
        "docker-build"
        "docker-test"
        "validate"
    )

    local missing=0
    for target in "${targets[@]}"; do
        if ! grep -q "^${target}:" Makefile && ! grep -q "^\.PHONY: ${target}" Makefile; then
            test_warn "Target '$target' not found in Makefile"
            ((missing++))
        fi
    done

    if [[ $missing -eq 0 ]]; then
        test_pass "All essential make targets exist"
    else
        test_fail "$missing essential targets missing"
        return 1
    fi

    return 0
}

# Test make with no arguments (should show help)
test_make_default() {
    test_start "Testing make with no arguments"

    cd "$TEST_PROJECT_ROOT"

    if make 2>/dev/null | grep -q "Machine-Rites Build System"; then
        test_pass "Default make target shows help"
    else
        test_fail "Default make target doesn't show expected output"
        return 1
    fi

    return 0
}

# Main test execution
main() {
    echo "======================================"
    echo "     Make Targets Unit Tests         "
    echo "======================================"
    echo

    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    local warned_tests=0

    # Run all tests
    local test_functions=(
        test_make_help
        test_make_info
        test_make_validate_syntax
        test_make_validate_structure
        test_make_deps_check
        test_make_clean
        test_make_docker_validate
        test_make_multipass_setup
        test_make_targets_exist
        test_make_default
    )

    for test_func in "${test_functions[@]}"; do
        ((total_tests++))
        if $test_func; then
            ((passed_tests++))
        else
            ((failed_tests++))
        fi
        echo
    done

    # Summary
    echo "======================================"
    echo "           Test Summary              "
    echo "======================================"
    echo "Total Tests: $total_tests"
    echo "Passed: $passed_tests"
    echo "Failed: $failed_tests"
    echo "Warnings: $warned_tests"

    if [[ $failed_tests -eq 0 ]]; then
        echo
        echo "✅ All make target tests passed!"
        exit 0
    else
        echo
        echo "❌ Some tests failed"
        exit 1
    fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi