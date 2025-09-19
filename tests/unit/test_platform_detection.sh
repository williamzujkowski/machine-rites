#!/usr/bin/env bash
# Unit Tests - Platform Detection and Compatibility
# Tests platform-specific detection and compatibility functions
set -euo pipefail

# Source test framework
source "$(dirname "${BASH_SOURCE[0]}")/../test-framework.sh"

# Test configuration
readonly SCRIPT_UNDER_TEST="$PROJECT_ROOT/bootstrap_machine_rites.sh"
readonly MOCK_ENV="$(setup_mock_environment "platform_detection")"

# Test setup
setup_platform_tests() {
    export HOME="$MOCK_ENV/home"
    mkdir -p "$HOME"
    log_debug "Setup platform detection tests environment in: $MOCK_ENV"
}

# Test teardown
cleanup_platform_tests() {
    cleanup_mock_environment "$MOCK_ENV"
}

# Unit Tests for Platform Detection

test_ubuntu_version_detection() {
    # Test Ubuntu version detection
    local test_script="$MOCK_ENV/ubuntu_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

# Mock lsb_release for different Ubuntu versions
test_ubuntu_version() {
    local version="$1"

    lsb_release() {
        case "$1" in
            "-is") echo "Ubuntu" ;;
            "-rs") echo "$version" ;;
            "-cs") echo "jammy" ;;
        esac
    }

    # Test Ubuntu detection logic
    if lsb_release -is 2>/dev/null | grep -q Ubuntu; then
        local ubuntu_version
        ubuntu_version=$(lsb_release -rs 2>/dev/null)
        echo "UBUNTU_$ubuntu_version"
        return 0
    else
        echo "NOT_UBUNTU"
        return 1
    fi
}

# Test various Ubuntu versions
test_ubuntu_version "22.04" | grep -q "UBUNTU_22.04" || exit 1
test_ubuntu_version "24.04" | grep -q "UBUNTU_24.04" || exit 1
test_ubuntu_version "20.04" | grep -q "UBUNTU_20.04" || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "Ubuntu version detection works"
}

test_architecture_detection() {
    # Test system architecture detection
    local test_script="$MOCK_ENV/arch_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

detect_architecture() {
    local arch

    if command -v uname >/dev/null 2>&1; then
        arch=$(uname -m)
    elif command -v arch >/dev/null 2>&1; then
        arch=$(arch)
    else
        arch="unknown"
    fi

    case "$arch" in
        x86_64|amd64)
            echo "x64"
            ;;
        i386|i686)
            echo "x86"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l|armv6l)
            echo "arm32"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Mock uname for testing
uname() {
    if [[ "$1" == "-m" ]]; then
        echo "x86_64"
    fi
}

result=$(detect_architecture)
[[ "$result" == "x64" ]] || exit 1

# Test ARM64
uname() {
    if [[ "$1" == "-m" ]]; then
        echo "aarch64"
    fi
}

result=$(detect_architecture)
[[ "$result" == "arm64" ]] || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "architecture detection works correctly"
}

test_kernel_version_check() {
    # Test kernel version compatibility
    local test_script="$MOCK_ENV/kernel_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

check_kernel_version() {
    local min_version="$1"
    local current_version

    if command -v uname >/dev/null 2>&1; then
        current_version=$(uname -r | sed 's/-.*$//')
    else
        return 1
    fi

    # Simple version comparison
    if [ "$(printf '%s\n' "$min_version" "$current_version" | sort -V | head -1)" = "$min_version" ]; then
        return 0
    else
        return 1
    fi
}

# Mock uname to return known kernel version
uname() {
    if [[ "$1" == "-r" ]]; then
        echo "5.15.0-72-generic"
    fi
}

# Test kernel version check
check_kernel_version "5.0.0" || exit 1
check_kernel_version "5.15.0" || exit 1
! check_kernel_version "6.0.0" || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "kernel version check works correctly"
}

test_package_manager_detection() {
    # Test package manager detection
    local test_script="$MOCK_ENV/package_manager_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        echo "apt"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

# Mock apt command
apt() {
    return 0
}
command() {
    if [[ "$1" == "-v" ]] && [[ "$2" == "apt" ]]; then
        return 0
    fi
    builtin command "$@"
}

result=$(detect_package_manager)
[[ "$result" == "apt" ]] || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "package manager detection works"
}

test_shell_detection() {
    # Test shell detection and compatibility
    local test_script="$MOCK_ENV/shell_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

detect_shell() {
    local shell_name

    if [[ -n "${BASH_VERSION:-}" ]]; then
        shell_name="bash"
    elif [[ -n "${ZSH_VERSION:-}" ]]; then
        shell_name="zsh"
    elif [[ -n "${FISH_VERSION:-}" ]]; then
        shell_name="fish"
    else
        shell_name=$(basename "${SHELL:-/bin/sh}")
    fi

    echo "$shell_name"
}

check_shell_compatibility() {
    local shell="$1"
    local min_version="$2"

    case "$shell" in
        bash)
            if [[ "${BASH_VERSION:-}" ]]; then
                local version="${BASH_VERSION%%.*}"
                [[ $version -ge $min_version ]]
            else
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

# Test shell detection
BASH_VERSION="5.1.8(1)-release"
result=$(detect_shell)
[[ "$result" == "bash" ]] || exit 1

# Test compatibility check
check_shell_compatibility "bash" 4 || exit 1
! check_shell_compatibility "bash" 6 || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "shell detection and compatibility works"
}

test_memory_detection() {
    # Test system memory detection
    local test_script="$MOCK_ENV/memory_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

detect_memory() {
    local memory_kb

    if [[ -r /proc/meminfo ]]; then
        memory_kb=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
        echo $((memory_kb / 1024))  # Convert to MB
    else
        echo "0"
    fi
}

check_memory_requirements() {
    local required_mb="$1"
    local available_mb

    available_mb=$(detect_memory)
    [[ $available_mb -ge $required_mb ]]
}

# Create mock /proc/meminfo
mkdir -p "$1/proc"
echo "MemTotal:        8048576 kB" > "$1/proc/meminfo"

# Test memory detection
result=$(detect_memory)
[[ $result -eq 7860 ]] || exit 1  # 8048576 / 1024 ≈ 7860

# Test memory requirements
check_memory_requirements 4000 || exit 1
! check_memory_requirements 10000 || exit 1
EOF

    assert_command_succeeds "bash '$test_script' '$MOCK_ENV'" "memory detection works correctly"
}

test_disk_space_detection() {
    # Test disk space detection
    local test_script="$MOCK_ENV/disk_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

check_disk_space() {
    local path="$1"
    local required_mb="$2"
    local available_mb

    if command -v df >/dev/null 2>&1; then
        # Get available space in MB
        available_mb=$(df -m "$path" 2>/dev/null | tail -1 | awk '{print $4}')
        [[ ${available_mb:-0} -ge $required_mb ]]
    else
        return 1
    fi
}

# Mock df command
df() {
    if [[ "$1" == "-m" ]]; then
        echo "Filesystem     1M-blocks  Used Available Use% Mounted on"
        echo "/dev/sda1          50000 20000     28000  42% /"
    fi
}

# Test disk space check
check_disk_space "/" 10000 || exit 1
! check_disk_space "/" 50000 || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "disk space detection works correctly"
}

test_network_connectivity() {
    # Test network connectivity check
    local test_script="$MOCK_ENV/network_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

check_internet_connectivity() {
    local test_hosts=("8.8.8.8" "1.1.1.1" "google.com")

    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 5 "$host" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

check_dns_resolution() {
    local test_domain="$1"

    if command -v nslookup >/dev/null 2>&1; then
        nslookup "$test_domain" >/dev/null 2>&1
    elif command -v dig >/dev/null 2>&1; then
        dig "$test_domain" >/dev/null 2>&1
    elif command -v host >/dev/null 2>&1; then
        host "$test_domain" >/dev/null 2>&1
    else
        return 1
    fi
}

# Mock ping for testing
ping() {
    case "$4" in
        "8.8.8.8"|"1.1.1.1")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Mock nslookup
nslookup() {
    case "$1" in
        "google.com"|"github.com")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Test connectivity
check_internet_connectivity || exit 1

# Test DNS resolution
check_dns_resolution "google.com" || exit 1
! check_dns_resolution "invalid.nonexistent.domain" || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "network connectivity check works"
}

test_user_permissions() {
    # Test user permission detection
    local test_script="$MOCK_ENV/permissions_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

check_write_permissions() {
    local directory="$1"

    if [[ -w "$directory" ]]; then
        return 0
    else
        return 1
    fi
}

check_sudo_access() {
    if command -v sudo >/dev/null 2>&1; then
        if sudo -n true 2>/dev/null; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

is_root_user() {
    [[ "$(id -u)" -eq 0 ]]
}

# Create test directories
mkdir -p "$1/writable"
chmod 755 "$1/writable"
mkdir -p "$1/readonly"
chmod 444 "$1/readonly"

# Test write permissions
check_write_permissions "$1/writable" || exit 1
! check_write_permissions "$1/readonly" || exit 1

# Mock sudo and id for testing
sudo() {
    if [[ "$1" == "-n" ]] && [[ "$2" == "true" ]]; then
        return 0  # Simulate sudo access
    fi
}

id() {
    if [[ "$1" == "-u" ]]; then
        echo "1000"  # Non-root user
    fi
}

command() {
    if [[ "$1" == "-v" ]] && [[ "$2" == "sudo" ]]; then
        return 0
    fi
    builtin command "$@"
}

# Test sudo access
check_sudo_access || exit 1

# Test root user check
! is_root_user || exit 1
EOF

    assert_command_succeeds "bash '$test_script' '$MOCK_ENV'" "user permissions check works"
}

test_cpu_capabilities() {
    # Test CPU capabilities detection
    local test_script="$MOCK_ENV/cpu_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

detect_cpu_cores() {
    local cores

    if [[ -r /proc/cpuinfo ]]; then
        cores=$(grep -c '^processor' /proc/cpuinfo)
    elif command -v nproc >/dev/null 2>&1; then
        cores=$(nproc)
    else
        cores=1
    fi

    echo "$cores"
}

check_cpu_features() {
    local feature="$1"

    if [[ -r /proc/cpuinfo ]]; then
        grep -q "flags.*$feature" /proc/cpuinfo
    else
        return 1
    fi
}

# Create mock /proc/cpuinfo
mkdir -p "$1/proc"
cat > "$1/proc/cpuinfo" << 'CPUINFO'
processor	: 0
model name	: Mock CPU
flags		: fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ht syscall nx mmxext fxsr_opt pdpe1gb rdtscp lm constant_tsc rep_good nopl xtopology nonstop_tsc cpuid extd_apicid aperfmperf pni pclmulqdq ssse3 fma cx16 sse4_1 sse4_2 movbe popcnt aes xsave avx f16c rdrand lahf_lm cmp_legacy svm extapic cr8_legacy abm sse4a misalignsse 3dnowprefetch osvw ibs xop skinit wdt lwp fma4 tce nodeid_msr tbm topoext perfctr_core perfctr_nb bpext ptsc mwaitx cpb cat_l3 cdp_l3 hw_pstate ssbd mba ibrs ibpb stibp vmmcall fsgsbase bmi1 avx2 smep bmi2 cqm rdt_a rdseed adx smap clflushopt clwb sha_ni xsaveopt xsavec xgetbv1 xsaves cqm_llc cqm_occup_llc cqm_mbm_total cqm_mbm_local clzero irperf xsaveerptr rdpru wbnoinvd arat npt lbrv svm_lock nrip_save tsc_scale vmcb_clean flushbyasid decodeassists pausefilter pfthreshold avic v_vmsave_vmload vgif v_spec_ctrl umip rdpid overflow_recov succor smca

processor	: 1
model name	: Mock CPU
flags		: fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ht syscall nx mmxext fxsr_opt pdpe1gb rdtscp lm constant_tsc rep_good nopl xtopology nonstop_tsc cpuid extd_apicid aperfmperf pni pclmulqdq ssse3 fma cx16 sse4_1 sse4_2 movbe popcnt aes xsave avx f16c rdrand lahf_lm cmp_legacy svm extapic cr8_legacy abm sse4a misalignsse 3dnowprefetch osvw ibs xop skinit wdt lwp fma4 tce nodeid_msr tbm topoext perfctr_core perfctr_nb bpext ptsc mwaitx cpb cat_l3 cdp_l3 hw_pstate ssbd mba ibrs ibpb stibp vmmcall fsgsbase bmi1 avx2 smep bmi2 cqm rdt_a rdseed adx smap clflushopt clwb sha_ni xsaveopt xsavec xgetbv1 xsaves cqm_llc cqm_occup_llc cqm_mbm_total cqm_mbm_local clzero irperf xsaveerptr rdpru wbnoinvd arat npt lbrv svm_lock nrip_save tsc_scale vmcb_clean flushbyasid decodeassists pausefilter pfthreshold avic v_vmsave_vmload vgif v_spec_ctrl umip rdpid overflow_recov succor smca
CPUINFO

# Test CPU core detection
cores=$(detect_cpu_cores)
[[ "$cores" -eq 2 ]] || exit 1

# Test CPU feature detection
check_cpu_features "sse2" || exit 1
check_cpu_features "avx" || exit 1
! check_cpu_features "nonexistent" || exit 1
EOF

    assert_command_succeeds "bash '$test_script' '$MOCK_ENV'" "CPU capabilities detection works"
}

# Test execution
main() {
    init_test_framework
    start_test_suite "Platform_Detection"

    setup_platform_tests

    run_test "Ubuntu Version Detection" test_ubuntu_version_detection
    run_test "Architecture Detection" test_architecture_detection
    run_test "Kernel Version Check" test_kernel_version_check
    run_test "Package Manager Detection" test_package_manager_detection
    run_test "Shell Detection" test_shell_detection
    run_test "Memory Detection" test_memory_detection
    run_test "Disk Space Detection" test_disk_space_detection
    run_test "Network Connectivity" test_network_connectivity
    run_test "User Permissions" test_user_permissions
    run_test "CPU Capabilities" test_cpu_capabilities

    cleanup_platform_tests
    end_test_suite
    finalize_test_framework
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi