#!/usr/bin/env bash
# lib/common.sh - Common utility functions for machine-rites
#
# Provides logging, error handling, and basic utility functions
# Used across all machine-rites scripts for consistent messaging
#
# Functions:
#   - say()    : Success messages (green)
#   - info()   : Informational messages (blue)
#   - warn()   : Warning messages (yellow)
#   - die()    : Error messages and exit (red)
#   - debug_var() : Debug variable inspection
#
# Dependencies: None (pure bash)
# Idempotent: Yes
# Self-contained: Yes

set -euo pipefail

# Color codes for consistent terminal output
if [[ -z "${C_G:-}" ]]; then
    declare -r C_G="\033[1;32m"  # Green for success
    declare -r C_Y="\033[1;33m"  # Yellow for warnings
    declare -r C_R="\033[1;31m"  # Red for errors
    declare -r C_B="\033[1;34m"  # Blue for info
    declare -r C_N="\033[0m"     # Reset/normal
fi

# Function: say
# Purpose: Display success/positive messages in green
# Args: $* - Message to display
# Returns: 0
# Example: say "Installation successful"
say() {
    printf "${C_G}[+] %s${C_N}\n" "$*"
}

# Function: info
# Purpose: Display informational messages in blue
# Args: $* - Message to display
# Returns: 0
# Example: info "Checking system configuration"
info() {
    printf "${C_B}[i] %s${C_N}\n" "$*"
}

# Function: warn
# Purpose: Display warning messages in yellow
# Args: $* - Message to display
# Returns: 0
# Example: warn "Configuration file not found, using defaults"
warn() {
    printf "${C_Y}[!] %s${C_N}\n" "$*"
}

# Function: die
# Purpose: Display error message in red and exit with code 1
# Args: $* - Error message to display
# Returns: Does not return (exits)
# Example: die "Critical error: Unable to continue"
die() {
    printf "${C_R}[✘] %s${C_N}\n" "$*" >&2
    exit 1
}

# Function: debug_var
# Purpose: Debug helper to inspect variable values with escaping
# Args: $1 - Variable name to inspect
# Returns: 0
# Example: debug_var "HOME"
debug_var() {
    local var_name="$1"
    local var_value="${!1:-<unset>}"
    printf "[debug] %s=%s (%%q:%q)\n" "$var_name" "$var_value" "$var_value"
}

# Function: require_root
# Purpose: Ensure script is running with root privileges
# Args: None
# Returns: 0 if root, calls die() if not
# Example: require_root
require_root() {
    [[ $EUID -eq 0 ]] || die "This operation requires root privileges"
}

# Function: require_user
# Purpose: Ensure script is NOT running as root
# Args: None
# Returns: 0 if not root, calls die() if root
# Example: require_user
require_user() {
    [[ $EUID -ne 0 ]] || die "This operation should not be run as root"
}

# Function: check_dependencies
# Purpose: Check that required commands are available
# Args: $* - List of required commands
# Returns: 0 if all found, calls die() if any missing
# Example: check_dependencies git curl wget
check_dependencies() {
    local missing=()
    local cmd

    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required dependencies: ${missing[*]}"
    fi
}

# Function: confirm
# Purpose: Interactive confirmation prompt
# Args: $1 - Prompt message (optional)
# Returns: 0 for yes, 1 for no
# Example: confirm "Delete all files?" && rm -rf /tmp/*
confirm() {
    local prompt="${1:-Continue?}"
    local reply

    printf "%s [y/N] " "$prompt"
    read -r reply
    [[ $reply =~ ^[Yy]$ ]]
}

# Source guard to prevent multiple loading
if [[ -n "${__LIB_COMMON_LOADED:-}" ]]; then
    return 0
fi

# Library metadata
readonly LIB_COMMON_VERSION="1.0.0"
readonly LIB_COMMON_LOADED=1
readonly __LIB_COMMON_LOADED=1