#!/usr/bin/env bash
# lib/platform.sh - Platform detection and compatibility for machine-rites
#
# Provides reliable OS detection and platform-specific functionality
# Ensures compatibility across different Linux distributions and versions
#
# Functions:
#   - detect_os()          : Detect operating system
#   - detect_distro()      : Detect Linux distribution
#   - detect_arch()        : Detect system architecture
#   - get_package_manager(): Get system package manager
#   - is_wsl()            : Check if running in WSL
#   - is_container()      : Check if running in container
#   - get_system_info()   : Get comprehensive system information
#   - check_kernel_version() : Check kernel version requirements
#
# Dependencies: common.sh (optional)
# Idempotent: Yes
# Self-contained: Yes

set -euo pipefail

# Source guard to prevent multiple loading
if [[ -n "${__LIB_PLATFORM_LOADED:-}" ]]; then
    return 0
fi

# Load common functions if available
if [[ -f "${BASH_SOURCE[0]%/*}/common.sh" ]]; then
    # shellcheck source=./common.sh
    source "${BASH_SOURCE[0]%/*}/common.sh"
fi

# Global variables for caching platform information
declare -g __PLATFORM_OS=""
declare -g __PLATFORM_DISTRO=""
declare -g __PLATFORM_ARCH=""
declare -g __PLATFORM_PKG_MGR=""

# Function: detect_os
# Purpose: Detect the operating system
# Args: None
# Returns: 0, prints OS name (linux, darwin, etc.)
# Example: os="$(detect_os)"
detect_os() {
    if [[ -n "$__PLATFORM_OS" ]]; then
        echo "$__PLATFORM_OS"
        return 0
    fi

    case "$(uname -s)" in
        Linux*)
            __PLATFORM_OS="linux"
            ;;
        Darwin*)
            __PLATFORM_OS="darwin"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            __PLATFORM_OS="windows"
            ;;
        FreeBSD*)
            __PLATFORM_OS="freebsd"
            ;;
        OpenBSD*)
            __PLATFORM_OS="openbsd"
            ;;
        NetBSD*)
            __PLATFORM_OS="netbsd"
            ;;
        *)
            __PLATFORM_OS="unknown"
            ;;
    esac

    echo "$__PLATFORM_OS"
}

# Function: detect_distro
# Purpose: Detect Linux distribution
# Args: None
# Returns: 0, prints distribution name
# Example: distro="$(detect_distro)"
detect_distro() {
    if [[ -n "$__PLATFORM_DISTRO" ]]; then
        echo "$__PLATFORM_DISTRO"
        return 0
    fi

    local os
    os="$(detect_os)"

    if [[ "$os" != "linux" ]]; then
        __PLATFORM_DISTRO="$os"
        echo "$__PLATFORM_DISTRO"
        return 0
    fi

    # Check /etc/os-release first (standardized)
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        __PLATFORM_DISTRO="${ID:-unknown}"
    # Fallback to lsb_release
    elif command -v lsb_release >/dev/null 2>&1; then
        __PLATFORM_DISTRO="$(lsb_release -si 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    # Legacy detection methods
    elif [[ -f /etc/debian_version ]]; then
        __PLATFORM_DISTRO="debian"
    elif [[ -f /etc/redhat-release ]]; then
        __PLATFORM_DISTRO="rhel"
    elif [[ -f /etc/arch-release ]]; then
        __PLATFORM_DISTRO="arch"
    elif [[ -f /etc/alpine-release ]]; then
        __PLATFORM_DISTRO="alpine"
    else
        __PLATFORM_DISTRO="unknown"
    fi

    echo "$__PLATFORM_DISTRO"
}

# Function: detect_arch
# Purpose: Detect system architecture
# Args: None
# Returns: 0, prints architecture (x86_64, arm64, etc.)
# Example: arch="$(detect_arch)"
detect_arch() {
    if [[ -n "$__PLATFORM_ARCH" ]]; then
        echo "$__PLATFORM_ARCH"
        return 0
    fi

    case "$(uname -m)" in
        x86_64|amd64)
            __PLATFORM_ARCH="x86_64"
            ;;
        aarch64|arm64)
            __PLATFORM_ARCH="arm64"
            ;;
        armv7l)
            __PLATFORM_ARCH="armv7"
            ;;
        armv6l)
            __PLATFORM_ARCH="armv6"
            ;;
        i386|i686)
            __PLATFORM_ARCH="i386"
            ;;
        *)
            __PLATFORM_ARCH="$(uname -m)"
            ;;
    esac

    echo "$__PLATFORM_ARCH"
}

# Function: get_package_manager
# Purpose: Detect system package manager
# Args: None
# Returns: 0, prints package manager name
# Example: pkg_mgr="$(get_package_manager)"
get_package_manager() {
    if [[ -n "$__PLATFORM_PKG_MGR" ]]; then
        echo "$__PLATFORM_PKG_MGR"
        return 0
    fi

    local distro
    distro="$(detect_distro)"

    case "$distro" in
        ubuntu|debian)
            __PLATFORM_PKG_MGR="apt"
            ;;
        centos|rhel|fedora|rocky|almalinux)
            if command -v dnf >/dev/null 2>&1; then
                __PLATFORM_PKG_MGR="dnf"
            elif command -v yum >/dev/null 2>&1; then
                __PLATFORM_PKG_MGR="yum"
            else
                __PLATFORM_PKG_MGR="unknown"
            fi
            ;;
        arch|manjaro)
            __PLATFORM_PKG_MGR="pacman"
            ;;
        opensuse*|suse)
            __PLATFORM_PKG_MGR="zypper"
            ;;
        alpine)
            __PLATFORM_PKG_MGR="apk"
            ;;
        darwin)
            if command -v brew >/dev/null 2>&1; then
                __PLATFORM_PKG_MGR="brew"
            else
                __PLATFORM_PKG_MGR="unknown"
            fi
            ;;
        *)
            __PLATFORM_PKG_MGR="unknown"
            ;;
    esac

    echo "$__PLATFORM_PKG_MGR"
}

# Function: is_wsl
# Purpose: Check if running in Windows Subsystem for Linux
# Args: None
# Returns: 0 if WSL, 1 if not
# Example: is_wsl && echo "Running in WSL"
is_wsl() {
    [[ -n "${WSL_DISTRO_NAME:-}" ]] || \
    [[ -f /proc/version && $(grep -i microsoft /proc/version) ]] || \
    [[ -f /proc/sys/kernel/osrelease && $(grep -i microsoft /proc/sys/kernel/osrelease) ]]
}

# Function: is_container
# Purpose: Check if running in a container (Docker, LXC, etc.)
# Args: None
# Returns: 0 if container, 1 if not
# Example: is_container && echo "Running in container"
is_container() {
    # Check for Docker
    [[ -f /.dockerenv ]] && return 0

    # Check for LXC
    [[ -f /proc/1/cgroup ]] && grep -q '/lxc/' /proc/1/cgroup 2>/dev/null && return 0

    # Check for systemd in container
    [[ -f /run/systemd/container ]] && return 0

    # Check for container environment variables
    [[ -n "${container:-}" ]] && return 0

    # Check init process
    [[ -f /proc/1/comm ]] && {
        local init_process
        init_process="$(cat /proc/1/comm 2>/dev/null)"
        [[ "$init_process" == "systemd" ]] && [[ ! -d /sys/fs/cgroup/systemd ]] && return 0
    }

    return 1
}

# Function: get_system_info
# Purpose: Get comprehensive system information
# Args: None
# Returns: 0, prints formatted system information
# Example: get_system_info
get_system_info() {
    local os distro arch pkg_mgr kernel_version
    local memory_total memory_available disk_usage
    local uptime_days cpu_cores

    os="$(detect_os)"
    distro="$(detect_distro)"
    arch="$(detect_arch)"
    pkg_mgr="$(get_package_manager)"
    kernel_version="$(uname -r)"

    # Memory information
    if [[ -f /proc/meminfo ]]; then
        memory_total="$(awk '/MemTotal/ {printf "%.1f GB", $2/1024/1024}' /proc/meminfo)"
        memory_available="$(awk '/MemAvailable/ {printf "%.1f GB", $2/1024/1024}' /proc/meminfo)"
    else
        memory_total="N/A"
        memory_available="N/A"
    fi

    # Disk usage
    disk_usage="$(df -h / 2>/dev/null | awk 'NR==2 {print $5}' || echo "N/A")"

    # Uptime
    if [[ -f /proc/uptime ]]; then
        uptime_days="$(awk '{printf "%.1f days", $1/86400}' /proc/uptime)"
    else
        uptime_days="N/A"
    fi

    # CPU cores
    cpu_cores="$(nproc 2>/dev/null || echo "N/A")"

    # Print formatted information
    cat << EOF
System Information:
  OS: $os
  Distribution: $distro
  Architecture: $arch
  Kernel: $kernel_version
  Package Manager: $pkg_mgr
  CPU Cores: $cpu_cores
  Memory: $memory_available available / $memory_total total
  Disk Usage: $disk_usage
  Uptime: $uptime_days
  WSL: $(is_wsl && echo "Yes" || echo "No")
  Container: $(is_container && echo "Yes" || echo "No")
EOF
}

# Function: check_kernel_version
# Purpose: Check if kernel version meets minimum requirement
# Args: $1 - minimum version (e.g., "5.4.0")
# Returns: 0 if meets requirement, 1 if not
# Example: check_kernel_version "5.4.0" || die "Kernel too old"
check_kernel_version() {
    local min_version="$1"
    local current_version

    [[ -n "$min_version" ]] || {
        [[ -n "${warn:-}" ]] && warn "check_kernel_version: minimum version required"
        return 1
    }

    current_version="$(uname -r | cut -d'-' -f1)"

    # Use sort -V for version comparison
    if [[ "$(printf '%s\n' "$min_version" "$current_version" | sort -V | head -1)" == "$min_version" ]]; then
        return 0
    else
        return 1
    fi
}

# Function: get_distro_version
# Purpose: Get distribution version
# Args: None
# Returns: 0, prints version string
# Example: version="$(get_distro_version)"
get_distro_version() {
    local version=""

    # Check /etc/os-release first
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        version="${VERSION_ID:-${VERSION:-unknown}}"
    # Fallback to lsb_release
    elif command -v lsb_release >/dev/null 2>&1; then
        version="$(lsb_release -sr 2>/dev/null || echo "unknown")"
    else
        version="unknown"
    fi

    echo "$version"
}

# Function: is_supported_platform
# Purpose: Check if current platform is supported
# Args: None
# Returns: 0 if supported, 1 if not
# Example: is_supported_platform || die "Unsupported platform"
is_supported_platform() {
    local os distro
    os="$(detect_os)"
    distro="$(detect_distro)"

    case "$os" in
        linux)
            case "$distro" in
                ubuntu|debian|centos|rhel|fedora|arch|alpine)
                    return 0
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
        darwin)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function: install_package
# Purpose: Install package using system package manager
# Args: $* - package names
# Returns: 0 on success, 1 on failure
# Example: install_package git curl wget
install_package() {
    local pkg_mgr packages=("$@")

    [[ ${#packages[@]} -gt 0 ]] || {
        [[ -n "${warn:-}" ]] && warn "install_package: no packages specified"
        return 1
    }

    pkg_mgr="$(get_package_manager)"

    case "$pkg_mgr" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            if [[ $EUID -eq 0 ]]; then
                apt-get update && apt-get install -y "${packages[@]}"
            else
                sudo apt-get update && sudo apt-get install -y "${packages[@]}"
            fi
            ;;
        dnf)
            if [[ $EUID -eq 0 ]]; then
                dnf install -y "${packages[@]}"
            else
                sudo dnf install -y "${packages[@]}"
            fi
            ;;
        yum)
            if [[ $EUID -eq 0 ]]; then
                yum install -y "${packages[@]}"
            else
                sudo yum install -y "${packages[@]}"
            fi
            ;;
        pacman)
            if [[ $EUID -eq 0 ]]; then
                pacman -Sy --noconfirm "${packages[@]}"
            else
                sudo pacman -Sy --noconfirm "${packages[@]}"
            fi
            ;;
        apk)
            if [[ $EUID -eq 0 ]]; then
                apk update && apk add "${packages[@]}"
            else
                sudo apk update && sudo apk add "${packages[@]}"
            fi
            ;;
        brew)
            brew install "${packages[@]}"
            ;;
        *)
            [[ -n "${warn:-}" ]] && warn "install_package: unsupported package manager: $pkg_mgr"
            return 1
            ;;
    esac
}

# Library metadata
readonly LIB_PLATFORM_VERSION="1.0.0"
readonly LIB_PLATFORM_LOADED=1
readonly __LIB_PLATFORM_LOADED=1