#!/usr/bin/env bash
# Test bootstrap deployment on fresh VM/container
# This simulates a clean system deployment

set -euo pipefail

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test-framework.sh"

# Test configuration
readonly TEST_NAME="Fresh VM Bootstrap"
readonly TEST_DISTROS=("ubuntu-24" "ubuntu-22" "debian-12")

# Test functions
test_fresh_deployment() {
    local distro="$1"
    local container_name="test-bootstrap-${distro}-$$"

    test_start "Testing fresh deployment on ${distro}"

    # Build and run container with bootstrap
    if docker run --rm \
        --name "${container_name}" \
        -v "${SCRIPT_DIR}/../../:/workspace:ro" \
        -e CI=true \
        -e TEST_MODE=fresh \
        "machine-rites:${distro}" \
        /bin/bash -c "
            set -e
            cd /workspace

            # Simulate fresh system
            rm -rf ~/.bashrc ~/.bashrc.d ~/.config 2>/dev/null || true

            # Run bootstrap
            echo '=== Starting Bootstrap ==='
            timeout 120 bash bootstrap_machine_rites.sh --unattended --test || exit 1

            # Verify installation
            echo '=== Verifying Installation ==='

            # Check bashrc exists
            test -f ~/.bashrc || { echo 'ERROR: .bashrc not found'; exit 1; }

            # Check bashrc.d modules
            test -d ~/.bashrc.d || { echo 'ERROR: .bashrc.d not found'; exit 1; }

            # Check starship config
            test -f ~/.config/starship.toml || { echo 'ERROR: starship.toml not found'; exit 1; }

            # Source and test shell
            echo '=== Testing Shell Configuration ==='
            bash -c 'source ~/.bashrc && echo \"Shell configuration loaded successfully\"' || exit 1

            echo '=== All checks passed for ${distro} ==='
        "; then
        test_pass "Fresh deployment on ${distro}"
        return 0
    else
        test_fail "Fresh deployment on ${distro}"
        return 1
    fi
}

test_bootstrap_idempotency() {
    local distro="$1"

    test_start "Testing bootstrap idempotency on ${distro}"

    if docker run --rm \
        -v "${SCRIPT_DIR}/../../:/workspace:ro" \
        -e CI=true \
        "machine-rites:${distro}" \
        /bin/bash -c "
            set -e
            cd /workspace

            # First run
            bash bootstrap_machine_rites.sh --unattended --test || exit 1

            # Second run (should be idempotent)
            bash bootstrap_machine_rites.sh --unattended --test || exit 1

            echo 'Bootstrap is idempotent'
        "; then
        test_pass "Bootstrap idempotency on ${distro}"
        return 0
    else
        test_fail "Bootstrap idempotency on ${distro}"
        return 1
    fi
}

test_minimal_installation() {
    local distro="$1"

    test_start "Testing minimal installation on ${distro}"

    if docker run --rm \
        -v "${SCRIPT_DIR}/../../:/workspace:ro" \
        -e CI=true \
        "machine-rites:${distro}" \
        /bin/bash -c "
            set -e
            cd /workspace

            # Run minimal bootstrap
            bash bootstrap_machine_rites.sh --unattended --minimal --test || exit 1

            # Verify minimal installation
            test -f ~/.bashrc || exit 1

            echo 'Minimal installation successful'
        "; then
        test_pass "Minimal installation on ${distro}"
        return 0
    else
        test_fail "Minimal installation on ${distro}"
        return 1
    fi
}

# Main test execution
main() {
    local total_tests=0
    local passed_tests=0
    local failed_tests=0

    echo "======================================"
    echo "    Fresh VM Bootstrap Test Suite    "
    echo "======================================"
    echo

    # Check Docker availability
    if ! command -v docker >/dev/null 2>&1; then
        echo "ERROR: Docker is required for VM testing"
        exit 1
    fi

    # Build test images if needed
    for distro in "${TEST_DISTROS[@]}"; do
        echo "Preparing ${distro} test environment..."
        make docker-build DISTRO="${distro}" >/dev/null 2>&1 || {
            echo "WARNING: Failed to build ${distro} image, skipping"
            continue
        }

        # Run tests for this distro
        echo
        echo "Testing ${distro}..."
        echo "------------------------"

        # Test 1: Fresh deployment
        ((total_tests++))
        if test_fresh_deployment "${distro}"; then
            ((passed_tests++))
        else
            ((failed_tests++))
        fi

        # Test 2: Idempotency
        ((total_tests++))
        if test_bootstrap_idempotency "${distro}"; then
            ((passed_tests++))
        else
            ((failed_tests++))
        fi

        # Test 3: Minimal installation
        ((total_tests++))
        if test_minimal_installation "${distro}"; then
            ((passed_tests++))
        else
            ((failed_tests++))
        fi
    done

    # Summary
    echo
    echo "======================================"
    echo "           Test Summary              "
    echo "======================================"
    echo "Total Tests: ${total_tests}"
    echo "Passed: ${passed_tests}"
    echo "Failed: ${failed_tests}"

    if [[ ${failed_tests} -eq 0 ]]; then
        echo
        echo "✅ All tests passed!"
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