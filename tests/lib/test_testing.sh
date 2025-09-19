#!/usr/bin/env bash
# tests/lib/test_testing.sh - Unit tests for lib/testing.sh
#
# Tests all functions in the testing framework library module
# Ensures proper test functionality and assertions

set -euo pipefail

# Load the library to test
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/testing.sh"

# Test function for assert_equals()
test_assert_equals_function() {
    # Test successful assertion
    local result=0
    assert_equals "hello" "hello" "Equal strings" || result=$?
    test "$result" -eq 0 || {
        echo "FAIL: assert_equals should succeed for equal strings"
        return 1
    }

    # Test failed assertion
    result=0
    assert_equals "hello" "world" "Different strings" || result=$?
    test "$result" -ne 0 || {
        echo "FAIL: assert_equals should fail for different strings"
        return 1
    }

    echo "PASS: assert_equals function works correctly"
}

# Test function for assert_not_equals()
test_assert_not_equals_function() {
    # Test successful assertion
    local result=0
    assert_not_equals "hello" "world" "Different strings" || result=$?
    test "$result" -eq 0 || {
        echo "FAIL: assert_not_equals should succeed for different strings"
        return 1
    }

    # Test failed assertion
    result=0
    assert_not_equals "hello" "hello" "Same strings" || result=$?
    test "$result" -ne 0 || {
        echo "FAIL: assert_not_equals should fail for same strings"
        return 1
    }

    echo "PASS: assert_not_equals function works correctly"
}

# Test function for assert_true()
test_assert_true_function() {
    # Test successful assertion
    local result=0
    assert_true test 1 -eq 1 || result=$?
    test "$result" -eq 0 || {
        echo "FAIL: assert_true should succeed for true condition"
        return 1
    }

    # Test failed assertion
    result=0
    assert_true test 1 -eq 2 || result=$?
    test "$result" -ne 0 || {
        echo "FAIL: assert_true should fail for false condition"
        return 1
    }

    echo "PASS: assert_true function works correctly"
}

# Test function for assert_false()
test_assert_false_function() {
    # Test successful assertion
    local result=0
    assert_false test 1 -eq 2 || result=$?
    test "$result" -eq 0 || {
        echo "FAIL: assert_false should succeed for false condition"
        return 1
    }

    # Test failed assertion
    result=0
    assert_false test 1 -eq 1 || result=$?
    test "$result" -ne 0 || {
        echo "FAIL: assert_false should fail for true condition"
        return 1
    }

    echo "PASS: assert_false function works correctly"
}

# Test function for assert_exists()
test_assert_exists_function() {
    local temp_file="/tmp/test_exists_$$"

    # Create test file
    touch "$temp_file"

    # Test successful assertion
    local result=0
    assert_exists "$temp_file" "File should exist" || result=$?
    test "$result" -eq 0 || {
        echo "FAIL: assert_exists should succeed for existing file"
        rm -f "$temp_file"
        return 1
    }

    # Clean up and test failed assertion
    rm -f "$temp_file"
    result=0
    assert_exists "$temp_file" "File should not exist" || result=$?
    test "$result" -ne 0 || {
        echo "FAIL: assert_exists should fail for non-existent file"
        return 1
    }

    echo "PASS: assert_exists function works correctly"
}

# Test function for assert_not_exists()
test_assert_not_exists_function() {
    local temp_file="/tmp/test_not_exists_$$"

    # Test successful assertion (file doesn't exist)
    local result=0
    assert_not_exists "$temp_file" "File should not exist" || result=$?
    test "$result" -eq 0 || {
        echo "FAIL: assert_not_exists should succeed for non-existent file"
        return 1
    }

    # Create file and test failed assertion
    touch "$temp_file"
    result=0
    assert_not_exists "$temp_file" "File should exist" || result=$?
    test "$result" -ne 0 || {
        echo "FAIL: assert_not_exists should fail for existing file"
        rm -f "$temp_file"
        return 1
    }

    # Clean up
    rm -f "$temp_file"
    echo "PASS: assert_not_exists function works correctly"
}

# Test function for assert_contains()
test_assert_contains_function() {
    # Test successful assertion
    local result=0
    assert_contains "hello world" "world" "Should contain substring" || result=$?
    test "$result" -eq 0 || {
        echo "FAIL: assert_contains should succeed when substring is present"
        return 1
    }

    # Test failed assertion
    result=0
    assert_contains "hello world" "goodbye" "Should not contain substring" || result=$?
    test "$result" -ne 0 || {
        echo "FAIL: assert_contains should fail when substring is not present"
        return 1
    }

    echo "PASS: assert_contains function works correctly"
}

# Test function for assert_matches()
test_assert_matches_function() {
    # Test successful assertion
    local result=0
    assert_matches "hello123" "^hello[0-9]+$" "Should match pattern" || result=$?
    test "$result" -eq 0 || {
        echo "FAIL: assert_matches should succeed when pattern matches"
        return 1
    }

    # Test failed assertion
    result=0
    assert_matches "hello" "^[0-9]+$" "Should not match pattern" || result=$?
    test "$result" -ne 0 || {
        echo "FAIL: assert_matches should fail when pattern doesn't match"
        return 1
    }

    echo "PASS: assert_matches function works correctly"
}

# Test function for setup_test_env()
test_setup_test_env_function() {
    # Save current directory
    local original_dir="$(pwd)"
    local original_tmpdir="${TEST_TMPDIR:-}"

    # Setup test environment
    setup_test_env

    # Check that TEST_TMPDIR is set and exists
    test -n "$TEST_TMPDIR" || {
        echo "FAIL: TEST_TMPDIR should be set after setup_test_env"
        return 1
    }

    test -d "$TEST_TMPDIR" || {
        echo "FAIL: TEST_TMPDIR should exist after setup_test_env"
        return 1
    }

    # Check that we're in the test directory
    test "$(pwd)" = "$TEST_TMPDIR" || {
        echo "FAIL: Should be in TEST_TMPDIR after setup_test_env"
        return 1
    }

    # Check permissions
    local perms
    perms="$(stat -c "%a" "$TEST_TMPDIR" 2>/dev/null || stat -f "%Lp" "$TEST_TMPDIR" 2>/dev/null || echo "700")"
    test "$perms" = "700" || {
        echo "FAIL: TEST_TMPDIR should have 700 permissions"
        return 1
    }

    # Cleanup
    cleanup_test_env
    cd "$original_dir"

    # Restore original TEST_TMPDIR if it was set
    if [[ -n "$original_tmpdir" ]]; then
        export TEST_TMPDIR="$original_tmpdir"
    else
        unset TEST_TMPDIR
    fi

    echo "PASS: setup_test_env function works correctly"
}

# Test function for mock_command()
test_mock_command_function() {
    # Setup test environment first
    local original_dir="$(pwd)"
    setup_test_env

    # Mock a command
    mock_command "fake_cmd" "echo 'mocked output'"

    # Test that mock works
    local output
    output="$(fake_cmd)"
    test "$output" = "mocked output" || {
        echo "FAIL: Mocked command should produce expected output"
        cleanup_test_env
        cd "$original_dir"
        return 1
    }

    # Cleanup
    cleanup_test_env
    cd "$original_dir"

    echo "PASS: mock_command function works correctly"
}

# Test function for capture_output()
test_capture_output_function() {
    # Setup test environment
    local original_dir="$(pwd)"
    setup_test_env

    # Test capturing successful command output
    local result=0
    capture_output echo "test output" || result=$?

    test "$result" -eq 0 || {
        echo "FAIL: capture_output should succeed for successful command"
        cleanup_test_env
        cd "$original_dir"
        return 1
    }

    test "$CAPTURED_OUTPUT" = "test output" || {
        echo "FAIL: CAPTURED_OUTPUT should contain command output"
        cleanup_test_env
        cd "$original_dir"
        return 1
    }

    # Test capturing command with error
    result=0
    capture_output bash -c 'echo "error message" >&2; exit 1' || result=$?

    test "$result" -eq 1 || {
        echo "FAIL: capture_output should preserve command exit code"
        cleanup_test_env
        cd "$original_dir"
        return 1
    }

    test "$CAPTURED_ERROR" = "error message" || {
        echo "FAIL: CAPTURED_ERROR should contain error output"
        cleanup_test_env
        cd "$original_dir"
        return 1
    }

    # Cleanup
    cleanup_test_env
    cd "$original_dir"

    echo "PASS: capture_output function works correctly"
}

# Test test counter functionality
test_counter_functionality() {
    # Reset counters
    __TEST_PASSED=0
    __TEST_FAILED=0
    __TEST_TOTAL=0

    # Run some assertions
    assert_true true "Should pass"
    assert_false false "Should pass"
    assert_true false "Should fail" || true  # Ignore failure for test
    assert_false true "Should fail" || true  # Ignore failure for test

    # Check counters
    test "$__TEST_TOTAL" -eq 4 || {
        echo "FAIL: Total test count should be 4, got $__TEST_TOTAL"
        return 1
    }

    test "$__TEST_PASSED" -eq 2 || {
        echo "FAIL: Passed test count should be 2, got $__TEST_PASSED"
        return 1
    }

    test "$__TEST_FAILED" -eq 2 || {
        echo "FAIL: Failed test count should be 2, got $__TEST_FAILED"
        return 1
    }

    echo "PASS: Test counter functionality works correctly"
}

# Test library metadata
test_library_metadata() {
    test "$LIB_TESTING_VERSION" = "1.0.0" || {
        echo "FAIL: Library version should be 1.0.0, got $LIB_TESTING_VERSION"
        return 1
    }

    test "$LIB_TESTING_LOADED" = "1" || {
        echo "FAIL: Library loaded flag should be 1, got $LIB_TESTING_LOADED"
        return 1
    }

    test "$__LIB_TESTING_LOADED" = "1" || {
        echo "FAIL: Library guard should be 1, got $__LIB_TESTING_LOADED"
        return 1
    }

    echo "PASS: Library metadata is correct"
}

# Test benchmark_function()
test_benchmark_function() {
    # Setup test environment
    local original_dir="$(pwd)"
    setup_test_env

    # Create a simple function to benchmark
    simple_function() {
        local i
        for ((i=0; i<100; i++)); do
            true
        done
    }

    # Run benchmark (capture output to avoid cluttering test output)
    local benchmark_output
    benchmark_output="$(benchmark_function 5 simple_function 2>&1)"

    # Check that benchmark output contains expected information
    echo "$benchmark_output" | grep -q "Benchmark:" || {
        echo "FAIL: Benchmark output should contain 'Benchmark:'"
        cleanup_test_env
        cd "$original_dir"
        return 1
    }

    echo "$benchmark_output" | grep -q "Total time:" || {
        echo "FAIL: Benchmark output should contain 'Total time:'"
        cleanup_test_env
        cd "$original_dir"
        return 1
    }

    echo "$benchmark_output" | grep -q "Average time:" || {
        echo "FAIL: Benchmark output should contain 'Average time:'"
        cleanup_test_env
        cd "$original_dir"
        return 1
    }

    # Cleanup
    cleanup_test_env
    cd "$original_dir"

    echo "PASS: benchmark_function works correctly"
}

# Simple test runner (since we can't use the full test_suite function to test itself)
run_simple_tests() {
    local tests=(
        test_assert_equals_function
        test_assert_not_equals_function
        test_assert_true_function
        test_assert_false_function
        test_assert_exists_function
        test_assert_not_exists_function
        test_assert_contains_function
        test_assert_matches_function
        test_setup_test_env_function
        test_mock_command_function
        test_capture_output_function
        test_counter_functionality
        test_library_metadata
        test_benchmark_function
    )

    local passed=0
    local failed=0
    local test_func

    echo "Testing lib/testing.sh..."
    echo

    for test_func in "${tests[@]}"; do
        echo -n "Running $test_func... "
        if "$test_func" >/dev/null 2>&1; then
            echo "PASS"
            ((passed++))
        else
            echo "FAIL"
            # Run again to show error
            "$test_func"
            ((failed++))
        fi
    done

    echo
    echo "Results:"
    echo "  Passed: $passed"
    echo "  Failed: $failed"
    echo "  Total:  $((passed + failed))"

    if [[ $failed -eq 0 ]]; then
        echo
        echo "All tests PASSED!"
        return 0
    else
        echo
        echo "Some tests FAILED!"
        return 1
    fi
}

# Main test runner
main() {
    run_simple_tests
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi