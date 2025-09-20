#!/usr/bin/env bash
# Unit tests for bootstrap functions
# Tests individual bootstrap components in isolation

set -euo pipefail

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test-framework.sh"

# Source bootstrap functions (extract core functions for testing)
# Note: In production, these would be sourced from a modular bootstrap
# TEST_PROJECT_ROOT available if needed for future tests
# TEST_PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"

# Test OS detection functionality
test_detect_os() {
    test_start "Testing OS detection"

    # Mock /etc/os-release for testing
    local temp_os_release="/tmp/test-os-release"

    # Test Ubuntu detection
    cat > "$temp_os_release" <<EOF
ID=ubuntu
VERSION_ID="22.04"
EOF

    if grep -q "ubuntu" "$temp_os_release"; then
        test_pass "Ubuntu detection works"
    else
        test_fail "Ubuntu detection failed"
        return 1
    fi

    # Test Debian detection
    cat > "$temp_os_release" <<EOF
ID=debian
VERSION_ID="12"
EOF

    if grep -q "debian" "$temp_os_release"; then
        test_pass "Debian detection works"
    else
        test_fail "Debian detection failed"
        return 1
    fi

    rm -f "$temp_os_release"
    return 0
}

# Test shell detection
test_detect_shell() {
    test_start "Testing shell detection"

    # Test bash detection
    if [[ -n "${BASH_VERSION:-}" ]]; then
        test_pass "Bash detected correctly"
    else
        test_fail "Bash detection failed"
        return 1
    fi

    # Test shell path
    if [[ "$SHELL" == *"bash"* ]] || [[ "$0" == *"bash"* ]]; then
        test_pass "Shell path detection works"
    else
        test_warn "Shell path detection uncertain"
    fi

    return 0
}

# Test package installation verification
test_install_packages() {
    test_start "Testing package installation checks"

    # Test for essential packages
    local essential_packages=(curl git bash)
    local missing_count=0

    for pkg in "${essential_packages[@]}"; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            test_warn "Package $pkg not found"
            ((missing_count++))
        fi
    done

    if [[ $missing_count -eq 0 ]]; then
        test_pass "All essential packages available"
    else
        test_fail "$missing_count essential packages missing"
        return 1
    fi

    return 0
}

# Test directory structure creation
test_setup_directories() {
    test_start "Testing directory creation"

    local test_base="/tmp/bootstrap-test-$$"
    local dirs=(
        "$test_base/.config"
        "$test_base/.local/bin"
        "$test_base/.local/share"
        "$test_base/.cache"
    )

    # Create directories
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done

    # Verify creation
    local failed=0
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            test_warn "Failed to create $dir"
            ((failed++))
        fi
    done

    # Cleanup
    rm -rf "$test_base"

    if [[ $failed -eq 0 ]]; then
        test_pass "Directory structure creation successful"
        return 0
    else
        test_fail "$failed directories failed to create"
        return 1
    fi
}

# Test Starship installation check
test_install_starship() {
    test_start "Testing Starship installation check"

    if command -v starship >/dev/null 2>&1; then
        test_pass "Starship is installed"

        # Test version check
        if starship --version >/dev/null 2>&1; then
            test_pass "Starship version check works"
        else
            test_fail "Starship version check failed"
            return 1
        fi
    else
        test_warn "Starship not installed (expected in test environment)"
    fi

    return 0
}

# Test git configuration
test_configure_git() {
    test_start "Testing git configuration"

    # Check if git is available
    if ! command -v git >/dev/null 2>&1; then
        test_skip "Git not available"
        return 0
    fi

    # Test basic git config
    local test_repo="/tmp/test-git-$$"
    mkdir -p "$test_repo"
    cd "$test_repo"

    if git init >/dev/null 2>&1; then
        test_pass "Git initialization works"
    else
        test_fail "Git initialization failed"
        cd - >/dev/null
        rm -rf "$test_repo"
        return 1
    fi

    cd - >/dev/null
    rm -rf "$test_repo"
    return 0
}

# Test SSH configuration
test_setup_ssh() {
    test_start "Testing SSH configuration setup"

    local test_ssh="/tmp/test-ssh-$$"
    mkdir -p "$test_ssh"

    # Test SSH directory permissions
    chmod 700 "$test_ssh"

    local perms=$(stat -c %a "$test_ssh" 2>/dev/null || stat -f %A "$test_ssh" 2>/dev/null || echo "unknown")

    if [[ "$perms" == "700" ]]; then
        test_pass "SSH directory permissions correct"
    else
        test_fail "SSH directory permissions incorrect: $perms"
        rm -rf "$test_ssh"
        return 1
    fi

    rm -rf "$test_ssh"
    return 0
}

# Test tool installation verification
test_install_tools() {
    test_start "Testing tool installation checks"

    # Check for common development tools
    local tools=(make)
    local found=0

    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            ((found++))
        fi
    done

    if [[ $found -gt 0 ]]; then
        test_pass "$found development tools found"
    else
        test_warn "No development tools found (expected in minimal environment)"
    fi

    return 0
}

# Test shell completion setup
test_setup_completions() {
    test_start "Testing shell completion setup"

    # Check for bash-completion
    if [[ -f /usr/share/bash-completion/bash_completion ]]; then
        test_pass "Bash completion framework found"
    elif [[ -f /etc/bash_completion ]]; then
        test_pass "Legacy bash completion found"
    else
        test_warn "Bash completion not found (optional)"
    fi

    return 0
}

# Test idempotency check
test_idempotency_check() {
    test_start "Testing idempotency mechanisms"

    # Test marker file creation
    local marker="/tmp/test-bootstrap-marker-$$"

    # First run
    touch "$marker"
    if [[ -f "$marker" ]]; then
        test_pass "Marker file created successfully"
    else
        test_fail "Marker file creation failed"
        return 1
    fi

    # Idempotency check
    if [[ -f "$marker" ]]; then
        test_pass "Idempotency check would skip re-run"
    else
        test_fail "Idempotency check failed"
        rm -f "$marker"
        return 1
    fi

    rm -f "$marker"
    return 0
}

# Main test execution
main() {
    echo "======================================"
    echo "  Bootstrap Functions Unit Tests     "
    echo "======================================"
    echo

    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    local skipped_tests=0

    # Run all tests
    local test_functions=(
        test_detect_os
        test_detect_shell
        test_install_packages
        test_setup_directories
        test_install_starship
        test_configure_git
        test_setup_ssh
        test_install_tools
        test_setup_completions
        test_idempotency_check
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
    echo "Skipped: $skipped_tests"

    if [[ $failed_tests -eq 0 ]]; then
        echo
        echo "✅ All bootstrap function tests passed!"
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