#!/usr/bin/env bash
# lib/testing.sh - Test assertion and framework functions for machine-rites
#
# Provides comprehensive testing capabilities for shell scripts
# Includes assertions, test runners, and reporting functionality
#
# Functions:
#   - assert_equals()      : Assert two values are equal
#   - assert_not_equals()  : Assert two values are not equal
#   - assert_true()        : Assert condition is true
#   - assert_false()       : Assert condition is false
#   - assert_exists()      : Assert file/directory exists
#   - assert_not_exists()  : Assert file/directory does not exist
#   - test_suite()         : Run a test suite
#   - test_report()        : Generate test report
#   - mock_command()       : Mock external commands
#   - setup_test_env()     : Setup isolated test environment
#
# Dependencies: common.sh (optional)
# Idempotent: Yes
# Self-contained: Yes

set -euo pipefail

# Source guard to prevent multiple loading
if [[ -n "${__LIB_TESTING_LOADED:-}" ]]; then
    return 0
fi

# Load common functions if available
if [[ -f "${BASH_SOURCE[0]%/*}/common.sh" ]]; then
    # shellcheck source=./common.sh
    source "${BASH_SOURCE[0]%/*}/common.sh"
fi

# Global test state variables
declare -g __TEST_PASSED=0
declare -g __TEST_FAILED=0
declare -g __TEST_TOTAL=0
declare -g __TEST_CURRENT=""
declare -g __TEST_START_TIME=""
declare -g __TEST_VERBOSE=${TEST_VERBOSE:-0}
declare -g __TEST_CLEANUP_FILES=()
declare -g __TEST_CLEANUP_DIRS=()

# Test result colors
declare -r __TEST_C_PASS="\033[32m"   # Green
declare -r __TEST_C_FAIL="\033[31m"   # Red
declare -r __TEST_C_INFO="\033[34m"   # Blue
declare -r __TEST_C_WARN="\033[33m"   # Yellow
declare -r __TEST_C_RESET="\033[0m"   # Reset

# Function: test_log
# Purpose: Internal logging for test framework
# Args: $1 - level, $2+ - message
# Returns: 0
test_log() {
    local level="$1"
    shift
    local color=""

    case "$level" in
        PASS) color="$__TEST_C_PASS" ;;
        FAIL) color="$__TEST_C_FAIL" ;;
        INFO) color="$__TEST_C_INFO" ;;
        WARN) color="$__TEST_C_WARN" ;;
        *) color="$__TEST_C_RESET" ;;
    esac

    printf "${color}[%s]${__TEST_C_RESET} %s\n" "$level" "$*"
}

# Function: assert_equals
# Purpose: Assert that two values are equal
# Args: $1 - expected, $2 - actual, $3 - message (optional)
# Returns: 0 if equal, 1 if not
# Example: assert_equals "hello" "$output" "Greeting should be hello"
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Expected '$expected', got '$actual'}"

    ((__TEST_TOTAL++))

    if [[ "$expected" == "$actual" ]]; then
        ((__TEST_PASSED++))
        [[ $__TEST_VERBOSE -eq 1 ]] && test_log "PASS" "$message"
        return 0
    else
        ((__TEST_FAILED++))
        test_log "FAIL" "$message"
        test_log "FAIL" "  Expected: '$expected'"
        test_log "FAIL" "  Actual:   '$actual'"
        return 1
    fi
}

# Function: assert_not_equals
# Purpose: Assert that two values are not equal
# Args: $1 - not expected, $2 - actual, $3 - message (optional)
# Returns: 0 if not equal, 1 if equal
# Example: assert_not_equals "error" "$status" "Should not be error"
assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local message="${3:-Expected NOT '$not_expected', got '$actual'}"

    ((__TEST_TOTAL++))

    if [[ "$not_expected" != "$actual" ]]; then
        ((__TEST_PASSED++))
        [[ $__TEST_VERBOSE -eq 1 ]] && test_log "PASS" "$message"
        return 0
    else
        ((__TEST_FAILED++))
        test_log "FAIL" "$message"
        test_log "FAIL" "  Should not equal: '$not_expected'"
        test_log "FAIL" "  Actual:          '$actual'"
        return 1
    fi
}

# Function: assert_true
# Purpose: Assert that a condition is true (exit code 0)
# Args: $* - command to test
# Returns: 0 if command succeeds, 1 if fails
# Example: assert_true test -f "/etc/passwd"
assert_true() {
    local message="Command should succeed: $*"

    ((__TEST_TOTAL++))

    if "$@" >/dev/null 2>&1; then
        ((__TEST_PASSED++))
        [[ $__TEST_VERBOSE -eq 1 ]] && test_log "PASS" "$message"
        return 0
    else
        ((__TEST_FAILED++))
        test_log "FAIL" "$message"
        return 1
    fi
}

# Function: assert_false
# Purpose: Assert that a condition is false (exit code != 0)
# Args: $* - command to test
# Returns: 0 if command fails, 1 if succeeds
# Example: assert_false test -f "/nonexistent"
assert_false() {
    local message="Command should fail: $*"

    ((__TEST_TOTAL++))

    if ! "$@" >/dev/null 2>&1; then
        ((__TEST_PASSED++))
        [[ $__TEST_VERBOSE -eq 1 ]] && test_log "PASS" "$message"
        return 0
    else
        ((__TEST_FAILED++))
        test_log "FAIL" "$message"
        return 1
    fi
}

# Function: assert_exists
# Purpose: Assert that a file or directory exists
# Args: $1 - path, $2 - message (optional)
# Returns: 0 if exists, 1 if not
# Example: assert_exists "/tmp/test.txt" "Test file should exist"
assert_exists() {
    local path="$1"
    local message="${2:-Path should exist: $path}"

    ((__TEST_TOTAL++))

    if [[ -e "$path" ]]; then
        ((__TEST_PASSED++))
        [[ $__TEST_VERBOSE -eq 1 ]] && test_log "PASS" "$message"
        return 0
    else
        ((__TEST_FAILED++))
        test_log "FAIL" "$message"
        return 1
    fi
}

# Function: assert_not_exists
# Purpose: Assert that a file or directory does not exist
# Args: $1 - path, $2 - message (optional)
# Returns: 0 if not exists, 1 if exists
# Example: assert_not_exists "/tmp/deleted.txt" "File should be deleted"
assert_not_exists() {
    local path="$1"
    local message="${2:-Path should not exist: $path}"

    ((__TEST_TOTAL++))

    if [[ ! -e "$path" ]]; then
        ((__TEST_PASSED++))
        [[ $__TEST_VERBOSE -eq 1 ]] && test_log "PASS" "$message"
        return 0
    else
        ((__TEST_FAILED++))
        test_log "FAIL" "$message"
        return 1
    fi
}

# Function: assert_contains
# Purpose: Assert that a string contains a substring
# Args: $1 - haystack, $2 - needle, $3 - message (optional)
# Returns: 0 if contains, 1 if not
# Example: assert_contains "$output" "success" "Output should contain success"
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain '$needle'}"

    ((__TEST_TOTAL++))

    if [[ "$haystack" == *"$needle"* ]]; then
        ((__TEST_PASSED++))
        [[ $__TEST_VERBOSE -eq 1 ]] && test_log "PASS" "$message"
        return 0
    else
        ((__TEST_FAILED++))
        test_log "FAIL" "$message"
        test_log "FAIL" "  Looking for: '$needle'"
        test_log "FAIL" "  In string:   '$haystack'"
        return 1
    fi
}

# Function: assert_matches
# Purpose: Assert that a string matches a regex pattern
# Args: $1 - string, $2 - pattern, $3 - message (optional)
# Returns: 0 if matches, 1 if not
# Example: assert_matches "$email" "^[^@]+@[^@]+$" "Should be valid email"
assert_matches() {
    local string="$1"
    local pattern="$2"
    local message="${3:-String should match pattern '$pattern'}"

    ((__TEST_TOTAL++))

    if [[ "$string" =~ $pattern ]]; then
        ((__TEST_PASSED++))
        [[ $__TEST_VERBOSE -eq 1 ]] && test_log "PASS" "$message"
        return 0
    else
        ((__TEST_FAILED++))
        test_log "FAIL" "$message"
        test_log "FAIL" "  Pattern: '$pattern'"
        test_log "FAIL" "  String:  '$string'"
        return 1
    fi
}

# Function: setup_test_env
# Purpose: Setup isolated test environment
# Args: None
# Returns: 0, sets TEST_TMPDIR
# Example: setup_test_env
setup_test_env() {
    # Create unique test directory
    export TEST_TMPDIR="$(mktemp -d "/tmp/test.XXXXXX")"
    __TEST_CLEANUP_DIRS+=("$TEST_TMPDIR")

    # Set safe permissions
    chmod 700 "$TEST_TMPDIR"

    # Change to test directory
    cd "$TEST_TMPDIR"

    # Initialize test counters
    __TEST_PASSED=0
    __TEST_FAILED=0
    __TEST_TOTAL=0
    __TEST_START_TIME="$(date +%s)"

    test_log "INFO" "Test environment: $TEST_TMPDIR"
}

# Function: cleanup_test_env
# Purpose: Clean up test environment
# Args: None
# Returns: 0
# Example: cleanup_test_env
cleanup_test_env() {
    # Clean up files
    local file
    for file in "${__TEST_CLEANUP_FILES[@]}"; do
        [[ -f "$file" ]] && rm -f "$file"
    done

    # Clean up directories
    local dir
    for dir in "${__TEST_CLEANUP_DIRS[@]}"; do
        [[ -d "$dir" ]] && rm -rf "$dir"
    done

    # Reset arrays
    __TEST_CLEANUP_FILES=()
    __TEST_CLEANUP_DIRS=()
}

# Function: test_suite
# Purpose: Run a test suite with setup and teardown
# Args: $1 - test function name
# Returns: 0 if all tests pass, 1 if any fail
# Example: test_suite "test_my_function"
test_suite() {
    local test_function="$1"

    [[ -n "$test_function" ]] || {
        test_log "FAIL" "test_suite: test function name required"
        return 1
    }

    # Check if function exists
    if ! declare -F "$test_function" >/dev/null; then
        test_log "FAIL" "test_suite: function '$test_function' not found"
        return 1
    fi

    __TEST_CURRENT="$test_function"
    test_log "INFO" "Starting test suite: $test_function"

    # Setup
    setup_test_env

    # Run tests with error handling
    local test_result=0
    if ! "$test_function"; then
        test_result=1
    fi

    # Report results
    test_report

    # Cleanup
    cleanup_test_env

    return $test_result
}

# Function: test_report
# Purpose: Generate and display test report
# Args: None
# Returns: 0
# Example: test_report
test_report() {
    local end_time duration
    end_time="$(date +%s)"
    duration=$((end_time - __TEST_START_TIME))

    echo
    test_log "INFO" "Test Results for: ${__TEST_CURRENT:-Unknown}"
    test_log "INFO" "Duration: ${duration}s"
    test_log "INFO" "Total:    $__TEST_TOTAL"
    test_log "PASS" "Passed:   $__TEST_PASSED"

    if [[ $__TEST_FAILED -gt 0 ]]; then
        test_log "FAIL" "Failed:   $__TEST_FAILED"
        echo
        test_log "FAIL" "Test suite FAILED"
        return 1
    else
        echo
        test_log "PASS" "Test suite PASSED"
        return 0
    fi
}

# Function: mock_command
# Purpose: Mock external command for testing
# Args: $1 - command name, $2 - mock script content
# Returns: 0
# Example: mock_command "git" "echo 'mocked git'"
mock_command() {
    local command="$1"
    local mock_content="$2"
    local mock_file="$TEST_TMPDIR/mock_$command"

    [[ -n "$command" && -n "$mock_content" ]] || {
        test_log "FAIL" "mock_command: command and content required"
        return 1
    }

    # Create mock script
    cat > "$mock_file" << EOF
#!/usr/bin/env bash
$mock_content
EOF

    # Make executable
    chmod +x "$mock_file"

    # Add to PATH
    export PATH="$TEST_TMPDIR:$PATH"

    # Track for cleanup
    __TEST_CLEANUP_FILES+=("$mock_file")

    test_log "INFO" "Mocked command: $command"
}

# Function: run_tests
# Purpose: Run multiple test functions
# Args: $* - test function names
# Returns: 0 if all pass, 1 if any fail
# Example: run_tests test_function1 test_function2
run_tests() {
    local test_functions=("$@")
    local failed_tests=()
    local passed_tests=()
    local func

    [[ ${#test_functions[@]} -gt 0 ]] || {
        test_log "FAIL" "run_tests: no test functions specified"
        return 1
    }

    test_log "INFO" "Running ${#test_functions[@]} test suites"

    for func in "${test_functions[@]}"; do
        if test_suite "$func"; then
            passed_tests+=("$func")
        else
            failed_tests+=("$func")
        fi
    done

    echo
    test_log "INFO" "Overall Results:"
    test_log "PASS" "Passed: ${#passed_tests[@]}"
    test_log "FAIL" "Failed: ${#failed_tests[@]}"

    if [[ ${#failed_tests[@]} -gt 0 ]]; then
        local failed_list="${failed_tests[*]}"
        test_log "FAIL" "Failed tests: $failed_list"
        return 1
    else
        test_log "PASS" "All tests passed!"
        return 0
    fi
}

# Library metadata
readonly LIB_TESTING_VERSION="1.0.0"
readonly LIB_TESTING_LOADED=1
readonly __LIB_TESTING_LOADED=1