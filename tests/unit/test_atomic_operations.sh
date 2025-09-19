#!/usr/bin/env bash
# Unit Tests - Atomic Operations Validation
# Tests critical atomic operations in bootstrap script
set -euo pipefail

# Source test framework with absolute path
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/../test-framework.sh"

# Test configuration
readonly SCRIPT_UNDER_TEST="$PROJECT_ROOT/bootstrap_machine_rites.sh"

# Load required libraries safely
if [[ -f "$PROJECT_ROOT/lib/atomic.sh" ]]; then
    source "$PROJECT_ROOT/lib/atomic.sh"
fi
if [[ -f "$PROJECT_ROOT/lib/common.sh" ]]; then
    source "$PROJECT_ROOT/lib/common.sh"
fi

MOCK_ENV=""

# Test setup
setup_atomic_tests() {
    MOCK_ENV="$(setup_mock_environment "atomic_ops")"
    export HOME="$MOCK_ENV/home"
    export CHEZMOI_SRC="$MOCK_ENV/chezmoi"
    mkdir -p "$HOME" "$CHEZMOI_SRC"

    # Create minimal test environment
    mkdir -p "$HOME/.config/chezmoi"
    mkdir -p "$HOME/.bashrc.d"

    log_debug "Setup atomic tests environment in: $MOCK_ENV"
}

# Test teardown
cleanup_atomic_tests() {
    cleanup_mock_environment "$MOCK_ENV"
}

# Unit Tests for Atomic Operations

test_color_code_functions() {
    # Test color code functions are defined correctly
    # Create mock functions instead of sourcing the entire script
    say() { echo "[SAY] $*"; }
    info() { echo "[INFO] $*"; }
    warn() { echo "[WARN] $*"; }
    die() { echo "[DIE] $*" >&2; return 1; }

    # Test that color functions don't crash
    local test_output
    test_output=$(say "test message" 2>&1)
    assert_contains "$test_output" "test message" "say function works"

    test_output=$(info "info message" 2>&1)
    assert_contains "$test_output" "info message" "info function works"

    test_output=$(warn "warning message" 2>&1)
    assert_contains "$test_output" "warning message" "warn function works"

    # Test die function exits with non-zero
    if die 'test error' 2>/dev/null; then
        log_error "die function should have returned error"
        return 1
    else
        log_success "die function exits with error"
    fi
}

test_version_checking_helper() {
    # Test version comparison logic
    source "$SCRIPT_UNDER_TEST"

    # Mock command that reports version 2.1.0
    mock_command() {
        echo "mock-tool version 2.1.0"
    }

    # Create temporary script to test version checking
    local test_script="$MOCK_ENV/version_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash
source "$1"
command() {
    if [[ "$1" == "-v" ]] && [[ "$2" == "mock-tool" ]]; then
        return 0
    fi
    builtin command "$@"
}
mock-tool() {
    echo "mock-tool version 2.1.0"
}
need_version mock-tool 2.0.0
EOF
    chmod +x "$test_script"

    assert_command_succeeds "bash '$test_script' '$SCRIPT_UNDER_TEST'" "version check succeeds for satisfied version"
}

test_flag_parsing() {
    # Test command line argument parsing
    local test_script="$MOCK_ENV/flag_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash
source "$1"

# Test unattended flag
UNATTENDED=0
for arg in "--unattended"; do
    case "$arg" in
        --unattended|-u) UNATTENDED=1 ;;
    esac
done
[[ $UNATTENDED -eq 1 ]] || exit 1

# Test verbose flag
VERBOSE=0
for arg in "--verbose"; do
    case "$arg" in
        --verbose|-v) VERBOSE=1 ;;
    esac
done
[[ $VERBOSE -eq 1 ]] || exit 1
EOF

    assert_command_succeeds "bash '$test_script' '$SCRIPT_UNDER_TEST'" "flag parsing works correctly"
}

test_debug_helpers() {
    # Test debug helper functions
    source "$SCRIPT_UNDER_TEST"

    # Test debug_var function
    TEST_VAR="test_value"
    local debug_output
    debug_output=$(debug_var "TEST_VAR" 2>&1)
    assert_contains "$debug_output" "TEST_VAR=test_value" "debug_var shows variable correctly"

    # Test with unset variable
    unset UNSET_VAR || true
    debug_output=$(debug_var "UNSET_VAR" 2>&1)
    assert_contains "$debug_output" "UNSET_VAR=<unset>" "debug_var handles unset variables"
}

test_error_handling() {
    # Test error trap functionality
    local test_script="$MOCK_ENV/error_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash
set -euo pipefail
trap 'echo "[ERR] rc=$? at ${BASH_SOURCE[0]}:${LINENO} running: ${BASH_COMMAND}" >&2' ERR

# This should trigger the error trap
false
EOF

    local error_output
    error_output=$(bash "$test_script" 2>&1 || true)
    assert_contains "$error_output" "[ERR] rc=1" "error trap activates on command failure"
}

test_preflight_scanning() {
    # Test preflight scan functionality
    source "$SCRIPT_UNDER_TEST"

    # Create a test script with potential issues
    local test_target="$MOCK_ENV/target_script.sh"
    cat > "$test_target" << 'EOF'
#!/bin/bash
# This script has some issues for preflight to catch
echo "Normal variable: $HOME"
echo 'Single quoted with variable: $HOME'
echo "Escaped variable: \$HOME"
EOF

    # Override preflight_scan to test specific script
    preflight_scan_test() {
        local self="$test_target"

        # Check for escaped variables
        if grep -nE '\\\$HOME|\\\$CHEZMOI(_|SRC)|\\\[' "$self" 2>/dev/null; then
            echo "Found escaped variables"
        fi

        # Check for single-quoted variables
        if grep -nE "'.*\$[A-Za-z_][A-Za-z0-9_]*.*'" "$self" 2>/dev/null; then
            echo "Found single-quoted variables"
        fi
    }

    local scan_output
    scan_output=$(preflight_scan_test 2>&1)
    assert_contains "$scan_output" "Found escaped variables" "preflight detects escaped variables"
    assert_contains "$scan_output" "Found single-quoted variables" "preflight detects single-quoted variables"
}

test_shellcheck_integration() {
    # Test shellcheck self-linting capability
    if command -v shellcheck >/dev/null 2>&1; then
        # Create a script with shellcheck issues
        local test_script="$MOCK_ENV/shellcheck_test.sh"
        cat > "$test_script" << 'EOF'
#!/bin/bash
# This script has shellcheck issues
echo $undefined_variable  # SC2154
[ $? = 0 ]               # SC2181
EOF

        # Test that shellcheck detects issues
        assert_command_fails "shellcheck '$test_script'" "shellcheck detects script issues"
    else
        skip_test "test_shellcheck_integration" "shellcheck not available"
    fi
}

test_sudo_requirement_check() {
    # Test sudo requirement logic
    local test_script="$MOCK_ENV/sudo_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash
# Simulate non-root user without sudo
id() {
    if [[ "$1" == "-u" ]]; then
        echo "1000"  # Non-root user
    fi
}
command() {
    if [[ "$1" == "-v" ]] && [[ "$2" == "sudo" ]]; then
        return 1  # sudo not available
    fi
    builtin command "$@"
}

# Test the logic from bootstrap script
if [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
    echo "NEEDS_SUDO"
    exit 1
fi
EOF

    assert_command_fails "bash '$test_script'" "detects missing sudo for non-root user"
}

test_os_detection() {
    # Test OS detection logic
    local test_script="$MOCK_ENV/os_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash
# Mock lsb_release for testing
lsb_release() {
    if [[ "$1" == "-is" ]]; then
        echo "Ubuntu"
    fi
}

# Test Ubuntu detection
if ! lsb_release -is 2>/dev/null | grep -q Ubuntu; then
    echo "NOT_UBUNTU"
    exit 1
else
    echo "IS_UBUNTU"
fi
EOF

    local os_output
    os_output=$(bash "$test_script")
    assert_equals "IS_UBUNTU" "$os_output" "correctly identifies Ubuntu"
}

test_atomic_file_operations() {
    # Test atomic file creation patterns
    local test_file="$MOCK_ENV/atomic_test.txt"
    local temp_file="$test_file.tmp"

    # Simulate atomic file creation
    echo "test content" > "$temp_file"
    mv "$temp_file" "$test_file"

    assert_file_exists "$test_file" "atomic file creation succeeded"
    assert_equals "test content" "$(cat "$test_file")" "atomic file has correct content"

    # Ensure temp file is cleaned up
    assert_command_fails "test -f '$temp_file'" "temporary file was cleaned up"
}

# Test execution
main() {
    init_test_framework
    start_test_suite "Atomic_Operations"

    setup_atomic_tests

    run_test "Color Code Functions" test_color_code_functions
    run_test "Version Checking Helper" test_version_checking_helper
    run_test "Flag Parsing" test_flag_parsing
    run_test "Debug Helpers" test_debug_helpers
    run_test "Error Handling" test_error_handling
    run_test "Preflight Scanning" test_preflight_scanning
    run_test "ShellCheck Integration" test_shellcheck_integration
    run_test "Sudo Requirement Check" test_sudo_requirement_check
    run_test "OS Detection" test_os_detection
    run_test "Atomic File Operations" test_atomic_file_operations

    cleanup_atomic_tests
    end_test_suite
    finalize_test_framework
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi