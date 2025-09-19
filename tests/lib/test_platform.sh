#!/usr/bin/env bash
# tests/lib/test_platform.sh - Unit tests for lib/platform.sh
#
# Tests all functions in the platform detection library module
# Ensures proper OS detection and platform-specific functionality

set -euo pipefail

# Load the libraries to test
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/platform.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/testing.sh"

# Test function for detect_os()
test_detect_os_function() {
    local os
    os="$(detect_os)"

    # Should return a valid OS name
    assert_true test -n "$os" "OS detection should return non-empty value"

    # Should be one of known OS types
    case "$os" in
        linux|darwin|windows|freebsd|openbsd|netbsd|unknown)
            assert_true true "Detected OS should be known type: $os"
            ;;
        *)
            assert_false true "Unknown OS detected: $os"
            ;;
    esac

    # Should cache result
    local os2
    os2="$(detect_os)"
    assert_equals "$os" "$os2" "OS detection should cache result"
}

# Test function for detect_distro()
test_detect_distro_function() {
    local distro
    distro="$(detect_distro)"

    # Should return a non-empty value
    assert_true test -n "$distro" "Distribution detection should return non-empty value"

    # On Linux, should detect common distros
    local os
    os="$(detect_os)"
    if [[ "$os" == "linux" ]]; then
        # Should be a known Linux distribution or unknown
        case "$distro" in
            ubuntu|debian|centos|rhel|fedora|arch|alpine|unknown)
                assert_true true "Detected Linux distro should be known type: $distro"
                ;;
            *)
                # Allow other distros, just warn
                info "Detected uncommon Linux distribution: $distro"
                ;;
        esac
    fi

    # Should cache result
    local distro2
    distro2="$(detect_distro)"
    assert_equals "$distro" "$distro2" "Distribution detection should cache result"
}

# Test function for detect_arch()
test_detect_arch_function() {
    local arch
    arch="$(detect_arch)"

    # Should return a non-empty value
    assert_true test -n "$arch" "Architecture detection should return non-empty value"

    # Should be one of known architectures
    case "$arch" in
        x86_64|arm64|armv7|armv6|i386)
            assert_true true "Detected architecture should be known type: $arch"
            ;;
        *)
            # Allow other architectures, just check it's reasonable
            assert_true test ${#arch} -gt 0 "Architecture should be non-empty: $arch"
            ;;
    esac

    # Should cache result
    local arch2
    arch2="$(detect_arch)"
    assert_equals "$arch" "$arch2" "Architecture detection should cache result"
}

# Test function for get_package_manager()
test_get_package_manager_function() {
    local pkg_mgr
    pkg_mgr="$(get_package_manager)"

    # Should return a non-empty value
    assert_true test -n "$pkg_mgr" "Package manager detection should return non-empty value"

    # Should be one of known package managers or unknown
    case "$pkg_mgr" in
        apt|dnf|yum|pacman|zypper|apk|brew|unknown)
            assert_true true "Detected package manager should be known type: $pkg_mgr"
            ;;
        *)
            assert_false true "Unknown package manager detected: $pkg_mgr"
            ;;
    esac

    # Should cache result
    local pkg_mgr2
    pkg_mgr2="$(get_package_manager)"
    assert_equals "$pkg_mgr" "$pkg_mgr2" "Package manager detection should cache result"
}

# Test function for is_wsl()
test_is_wsl_function() {
    # Test that function runs without error
    local result=0
    is_wsl || result=$?

    # Should return 0 or 1
    assert_true test "$result" -eq 0 -o "$result" -eq 1 "is_wsl should return 0 or 1"

    # If WSL environment variables are set, should detect WSL
    if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
        assert_true is_wsl "Should detect WSL when WSL_DISTRO_NAME is set"
    fi
}

# Test function for is_container()
test_is_container_function() {
    # Test that function runs without error
    local result=0
    is_container || result=$?

    # Should return 0 or 1
    assert_true test "$result" -eq 0 -o "$result" -eq 1 "is_container should return 0 or 1"

    # If container indicators are present, should detect container
    if [[ -f /.dockerenv ]]; then
        assert_true is_container "Should detect Docker container"
    fi

    if [[ -n "${container:-}" ]]; then
        assert_true is_container "Should detect container when environment variable is set"
    fi
}

# Test function for get_system_info()
test_get_system_info_function() {
    local info
    info="$(get_system_info)"

    # Should return non-empty output
    assert_true test -n "$info" "System info should return non-empty output"

    # Should contain expected fields
    assert_contains "$info" "OS:" "System info should contain OS"
    assert_contains "$info" "Distribution:" "System info should contain distribution"
    assert_contains "$info" "Architecture:" "System info should contain architecture"
    assert_contains "$info" "Kernel:" "System info should contain kernel version"
    assert_contains "$info" "Package Manager:" "System info should contain package manager"
    assert_contains "$info" "CPU Cores:" "System info should contain CPU cores"
    assert_contains "$info" "Memory:" "System info should contain memory info"
    assert_contains "$info" "WSL:" "System info should contain WSL status"
    assert_contains "$info" "Container:" "System info should contain container status"
}

# Test function for check_kernel_version()
test_check_kernel_version_function() {
    # Test with very old version (should pass)
    assert_true check_kernel_version "2.6.0" "Should pass for very old required version"

    # Test with future version (should fail)
    assert_false check_kernel_version "99.99.99" "Should fail for future required version"

    # Test with invalid version format
    assert_false check_kernel_version "" "Should fail for empty version"

    # Test with current kernel version (should pass)
    local current_version
    current_version="$(uname -r | cut -d'-' -f1)"
    assert_true check_kernel_version "$current_version" "Should pass for current kernel version"
}

# Test function for get_distro_version()
test_get_distro_version_function() {
    local version
    version="$(get_distro_version)"

    # Should return non-empty value
    assert_true test -n "$version" "Distribution version should be non-empty"

    # Should not contain obvious error messages
    assert_false echo "$version" | grep -qi "error" "Version should not contain error messages"
}

# Test function for is_supported_platform()
test_is_supported_platform_function() {
    # Test that function runs without error
    local result=0
    is_supported_platform || result=$?

    # Should return 0 or 1
    assert_true test "$result" -eq 0 -o "$result" -eq 1 "is_supported_platform should return 0 or 1"

    # Most common platforms should be supported
    local os distro
    os="$(detect_os)"
    distro="$(detect_distro)"

    case "$os" in
        linux)
            case "$distro" in
                ubuntu|debian)
                    assert_true is_supported_platform "Ubuntu/Debian should be supported"
                    ;;
            esac
            ;;
        darwin)
            assert_true is_supported_platform "macOS should be supported"
            ;;
    esac
}

# Test caching functionality
test_caching_functionality() {
    # Clear cache variables
    __PLATFORM_OS=""
    __PLATFORM_DISTRO=""
    __PLATFORM_ARCH=""
    __PLATFORM_PKG_MGR=""

    # First calls should populate cache
    local os1 distro1 arch1 pkg_mgr1
    os1="$(detect_os)"
    distro1="$(detect_distro)"
    arch1="$(detect_arch)"
    pkg_mgr1="$(get_package_manager)"

    # Check that cache variables are set
    assert_equals "$os1" "$__PLATFORM_OS" "OS should be cached"
    assert_equals "$distro1" "$__PLATFORM_DISTRO" "Distro should be cached"
    assert_equals "$arch1" "$__PLATFORM_ARCH" "Arch should be cached"
    assert_equals "$pkg_mgr1" "$__PLATFORM_PKG_MGR" "Package manager should be cached"

    # Second calls should use cache
    local os2 distro2 arch2 pkg_mgr2
    os2="$(detect_os)"
    distro2="$(detect_distro)"
    arch2="$(detect_arch)"
    pkg_mgr2="$(get_package_manager)"

    assert_equals "$os1" "$os2" "Cached OS should match"
    assert_equals "$distro1" "$distro2" "Cached distro should match"
    assert_equals "$arch1" "$arch2" "Cached arch should match"
    assert_equals "$pkg_mgr1" "$pkg_mgr2" "Cached package manager should match"
}

# Test install_package function (mock test)
test_install_package_function() {
    # Skip if running as root (would actually install packages)
    if [[ $EUID -eq 0 ]]; then
        skip_test "Skipping install_package test when running as root"
        return 0
    fi

    # Test parameter validation
    assert_false install_package "Should fail with no packages specified"

    # Test with non-existent package manager
    local original_pkg_mgr="$__PLATFORM_PKG_MGR"
    __PLATFORM_PKG_MGR="nonexistent"

    assert_false install_package "fake-package" "Should fail with unknown package manager"

    # Restore original package manager
    __PLATFORM_PKG_MGR="$original_pkg_mgr"
}

# Test error handling and edge cases
test_error_handling() {
    # Test with manipulated environment
    local original_path="$PATH"

    # Test without common utilities (temporarily remove from PATH)
    export PATH="/bin:/usr/bin"  # Minimal PATH

    # Functions should still work with basic utilities
    assert_true test -n "$(detect_os)" "Should work with minimal PATH"

    # Restore PATH
    export PATH="$original_path"

    # Test kernel version with malformed input
    assert_false check_kernel_version "not.a.version" "Should handle malformed version"
}

# Test library metadata
test_library_metadata() {
    assert_equals "1.0.0" "$LIB_PLATFORM_VERSION" "Library version should be set"
    assert_equals "1" "$LIB_PLATFORM_LOADED" "Library loaded flag should be set"
    assert_equals "1" "$__LIB_PLATFORM_LOADED" "Library guard should be set"
}

# Test source guard functionality
test_source_guard() {
    # Test that sourcing again is safe
    local before_functions after_functions

    before_functions="$(declare -F | grep -c detect_os || echo 0)"
    source "$(dirname "${BASH_SOURCE[0]}")/../../lib/platform.sh"
    after_functions="$(declare -F | grep -c detect_os || echo 0)"

    assert_equals "$before_functions" "$after_functions" "Re-sourcing should not duplicate functions"
}

# Test platform-specific functionality
test_platform_specific() {
    local os pkg_mgr
    os="$(detect_os)"
    pkg_mgr="$(get_package_manager)"

    # Test that package manager matches OS
    case "$os" in
        linux)
            local distro
            distro="$(detect_distro)"
            case "$distro" in
                ubuntu|debian)
                    assert_equals "apt" "$pkg_mgr" "Ubuntu/Debian should use apt"
                    ;;
                centos|rhel|fedora)
                    assert_true test "$pkg_mgr" = "dnf" -o "$pkg_mgr" = "yum" "RHEL-based should use dnf or yum"
                    ;;
                arch)
                    assert_equals "pacman" "$pkg_mgr" "Arch should use pacman"
                    ;;
                alpine)
                    assert_equals "apk" "$pkg_mgr" "Alpine should use apk"
                    ;;
            esac
            ;;
        darwin)
            # On macOS, package manager depends on whether Homebrew is installed
            assert_true test "$pkg_mgr" = "brew" -o "$pkg_mgr" = "unknown" "macOS should use brew or unknown"
            ;;
    esac
}

# Main test runner
main() {
    echo "Testing lib/platform.sh..."

    run_tests \
        test_detect_os_function \
        test_detect_distro_function \
        test_detect_arch_function \
        test_get_package_manager_function \
        test_is_wsl_function \
        test_is_container_function \
        test_get_system_info_function \
        test_check_kernel_version_function \
        test_get_distro_version_function \
        test_is_supported_platform_function \
        test_caching_functionality \
        test_install_package_function \
        test_error_handling \
        test_library_metadata \
        test_source_guard \
        test_platform_specific
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi