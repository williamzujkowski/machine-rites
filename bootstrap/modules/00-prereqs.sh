#!/usr/bin/env bash
# bootstrap/modules/00-prereqs.sh - Prerequisites and validation module
#
# Description: Validates system requirements and prerequisites
# Version: 1.0.0
# Dependencies: lib/common.sh, lib/platform.sh, lib/validation.sh
# Idempotent: Yes
# Rollback: No (validation only)
#
# This module validates that the system meets all requirements before
# proceeding with bootstrap. It checks OS compatibility, required tools,
# permissions, and sets up essential environment variables.

set -euo pipefail

# Module metadata
readonly MODULE_NAME="00-prereqs"
readonly MODULE_VERSION="1.0.0"
readonly MODULE_DESCRIPTION="Prerequisites and validation"

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"
# shellcheck source=../../lib/platform.sh
source "$SCRIPT_DIR/../../lib/platform.sh" 2>/dev/null || true
# shellcheck source=../../lib/validation.sh
source "$SCRIPT_DIR/../../lib/validation.sh" 2>/dev/null || true

# Function: validate
# Purpose: Validate prerequisites before execution
# Args: None
# Returns: 0 if all prerequisites met, 1 if not
validate() {
    info "Validating prerequisites for $MODULE_NAME"

    # Check if running as root (should not be)
    if [[ $EUID -eq 0 ]]; then
        warn "Running as root is not recommended"
        if [[ "${ALLOW_ROOT:-0}" != "1" ]]; then
            die "Please run as a regular user with sudo access"
        fi
    fi

    # Check sudo availability if not root
    if [[ $EUID -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
        die "This script needs 'sudo' for package installs. Install sudo or run as root."
    fi

    # Basic shell features
    if ! set -o | grep -q "pipefail.*on"; then
        die "Shell does not support pipefail (required)"
    fi

    return 0
}

# Function: execute
# Purpose: Execute prerequisites setup and validation
# Args: None
# Returns: 0 if successful, 1 if failed
execute() {
    info "Executing prerequisites validation for $MODULE_NAME"

    # OS validation
    _validate_os

    # Set up error handling
    _setup_error_handling

    # Set up XDG base directories
    _setup_xdg_directories

    # Validate environment
    _validate_environment

    # Set up repository variables
    _setup_repository_variables

    # Validate git configuration
    _validate_git_configuration

    # Version checking helper
    _setup_version_checking

    # Preflight debugging
    _run_preflight_scan

    return 0
}

# Function: verify
# Purpose: Verify that prerequisites are properly set up
# Args: None
# Returns: 0 if verified, 1 if not
verify() {
    info "Verifying prerequisites setup for $MODULE_NAME"

    # Check environment variables are set
    local required_vars=(
        "XDG_CONFIG_HOME"
        "XDG_DATA_HOME"
        "XDG_STATE_HOME"
        "XDG_CACHE_HOME"
        "REPO_DIR"
        "REPO_URL"
        "CHEZMOI_CFG"
        "CHEZMOI_SRC"
        "PASS_PREFIX"
    )

    local var
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            warn "Required environment variable not set: $var"
            return 1
        fi
    done

    # Check git user configuration
    if [[ -z "${GIT_NAME:-}" ]] || [[ -z "${GIT_EMAIL:-}" ]]; then
        warn "Git user configuration incomplete"
        return 1
    fi

    say "Prerequisites verification completed"
    return 0
}

# Function: rollback
# Purpose: Rollback changes (not applicable for prereqs)
# Args: None
# Returns: 0 (no-op)
rollback() {
    info "No rollback needed for $MODULE_NAME (validation only)"
    return 0
}

# Internal function: _validate_os
# Purpose: Validate operating system compatibility
_validate_os() {
    info "Validating operating system compatibility"

    if ! command -v lsb_release >/dev/null 2>&1; then
        warn "lsb_release not available, cannot determine OS"
        return 0
    fi

    local os_id
    os_id=$(lsb_release -is 2>/dev/null || echo "Unknown")

    if [[ "$os_id" != "Ubuntu" ]]; then
        warn "This script is designed for Ubuntu. Detected: $os_id"
        if [[ "${UNATTENDED:-0}" -eq 0 ]] && [[ -t 0 ]]; then
            read -rp "Continue anyway? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                die "Aborted by user"
            fi
        else
            warn "Continuing with non-Ubuntu OS in unattended mode"
        fi
    else
        info "Ubuntu detected: $(lsb_release -rs 2>/dev/null || echo 'Unknown version')"
    fi
}

# Internal function: _setup_error_handling
# Purpose: Set up comprehensive error handling
_setup_error_handling() {
    # Enhanced error trap
    trap 'echo "[ERR] rc=$? at ${BASH_SOURCE[0]}:${LINENO} running: ${BASH_COMMAND}" >&2' ERR

    # Debug mode setup
    if [[ "${DEBUG:-0}" -eq 1 ]]; then
        export PS4='+(${BASH_SOURCE##*/}:${LINENO}): ${FUNCNAME[0]:-main}(): '
        set -x
    fi

    # Verbose mode
    if [[ "${VERBOSE:-0}" -eq 1 ]]; then
        set -x
    fi
}

# Internal function: _setup_xdg_directories
# Purpose: Set up XDG Base Directory specification variables
_setup_xdg_directories() {
    info "Setting up XDG Base Directory specification"

    export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
    export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
    export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
    export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

    # Create directories if they don't exist
    mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

    if [[ "${VERBOSE:-0}" -eq 1 ]]; then
        debug_var "XDG_CONFIG_HOME"
        debug_var "XDG_DATA_HOME"
        debug_var "XDG_STATE_HOME"
        debug_var "XDG_CACHE_HOME"
    fi
}

# Internal function: _validate_environment
# Purpose: Validate shell environment and features
_validate_environment() {
    info "Validating shell environment"

    # Check bash version
    if [[ "${BASH_VERSION%%.*}" -lt 4 ]]; then
        warn "Bash version is old: $BASH_VERSION (recommended: 4.0+)"
    fi

    # Check for required shell options
    local required_options=("errexit" "nounset" "pipefail")
    local option
    for option in "${required_options[@]}"; do
        if ! set -o | grep -q "^$option.*on$"; then
            warn "Required shell option not set: $option"
        fi
    done

    # Check umask
    local current_umask
    current_umask=$(umask)
    if [[ "$current_umask" != "0027" ]] && [[ "$current_umask" != "0022" ]]; then
        info "Setting secure umask (was: $current_umask)"
        umask 027
    fi
}

# Internal function: _setup_repository_variables
# Purpose: Set up repository and chezmoi related variables
_setup_repository_variables() {
    info "Setting up repository variables"

    export REPO_DIR="${REPO_DIR:-$HOME/git/machine-rites}"
    export REPO_URL="${REPO_URL:-https://github.com/williamzujkowski/machine-rites}"
    export CHEZMOI_CFG="$XDG_CONFIG_HOME/chezmoi/chezmoi.toml"
    export CHEZMOI_SRC="$REPO_DIR/.chezmoi"
    export PASS_PREFIX="${PASS_PREFIX:-personal}"

    if [[ "${VERBOSE:-0}" -eq 1 ]]; then
        debug_var "REPO_DIR"
        debug_var "REPO_URL"
        debug_var "CHEZMOI_CFG"
        debug_var "CHEZMOI_SRC"
        debug_var "PASS_PREFIX"
    fi
}

# Internal function: _validate_git_configuration
# Purpose: Validate and set up git user configuration
_validate_git_configuration() {
    info "Validating git user configuration"

    export GIT_NAME="${GIT_NAME:-$(git config --global user.name 2>/dev/null || echo "")}"
    export GIT_EMAIL="${GIT_EMAIL:-$(git config --global user.email 2>/dev/null || echo "")}"

    # Prompt for email if not set and interactive
    if [[ -z "$GIT_EMAIL" ]] && [[ -t 0 ]] && [[ "${UNATTENDED:-0}" -eq 0 ]]; then
        read -rp "Git email not set. Enter email for chezmoi data: " GIT_EMAIL
        export GIT_EMAIL
    fi

    # Set defaults if still empty
    if [[ -z "$GIT_NAME" ]]; then
        GIT_NAME="$(whoami)"
        export GIT_NAME
    fi

    if [[ -z "$GIT_EMAIL" ]]; then
        GIT_EMAIL="$(whoami)@$(hostname)"
        export GIT_EMAIL
        warn "Using default git email: $GIT_EMAIL"
    fi

    if [[ "${VERBOSE:-0}" -eq 1 ]]; then
        debug_var "GIT_NAME"
        debug_var "GIT_EMAIL"
    fi
}

# Internal function: _setup_version_checking
# Purpose: Set up version checking helper function
_setup_version_checking() {
    # Export version checking function for use by other modules
    if ! declare -f need_version >/dev/null 2>&1; then
        # shellcheck disable=SC2034
        need_version() {
            local cmd="$1" min="$2" cur
            command -v "$cmd" >/dev/null || return 1
            cur="$("$cmd" --version 2>/dev/null | grep -Eo '[0-9]+(\.[0-9]+)+' | head -1 || true)"
            [[ -z "$cur" ]] && return 0  # Can't determine version, assume OK
            [[ "$(printf '%s\n' "$min" "$cur" | sort -V | head -1)" = "$min" ]] || return 1
        }
        export -f need_version
    fi
}

# Internal function: _run_preflight_scan
# Purpose: Run preflight scanning if debug mode is enabled
_run_preflight_scan() {
    if [[ "${DEBUG:-0}" -eq 1 ]]; then
        info "Running preflight scan"
        _preflight_scan
    fi
}

# Internal function: _preflight_scan
# Purpose: Debug scanning for common issues
_preflight_scan() {
    echo "[debug] Preflight scan…"
    local self cfg
    self="$(readlink -f "$0" 2>/dev/null || echo "$0")"
    cfg="$CHEZMOI_CFG"

    # Check for suspicious escapes in bootstrap script
    local bootstrap_script="${REPO_DIR:-$HOME/git/machine-rites}/bootstrap_machine_rites.sh"
    if [[ -f "$bootstrap_script" ]]; then
        if grep -nE '\\\$HOME|\\\$CHEZMOI(_|SRC)|\\\[' "$bootstrap_script" 2>/dev/null; then
            echo "[warn] Bootstrap script contains escaped variables/brackets above — fix before running."
        else
            echo "[debug] No escaped \$HOME/\$CHEZMOI_* or bracket escapes in bootstrap script."
        fi

        # Check for single-quoted variables
        if grep -nE "'.*\$[A-Za-z_][A-Za-z0-9_]*.*'" "$bootstrap_script" 2>/dev/null; then
            echo "[warn] Variables found inside single quotes in bootstrap script (won't expand)."
        else
            echo "[debug] No single-quoted variables in bootstrap script."
        fi
    fi

    # Check chezmoi config
    if [[ -f "$cfg" ]]; then
        echo "[debug] Found $cfg"
        if grep -nE '\$CHEZMOI|\\_' "$cfg" 2>/dev/null; then
            echo "[warn] Config contains escaped vars"
        fi
    else
        echo "[debug] No chezmoi.toml yet (will be created)."
    fi

    # Check chezmoi status
    if command -v chezmoi >/dev/null 2>&1; then
        echo "[debug] chezmoi sourceDir (template): $(chezmoi execute-template '{{ .chezmoi.sourceDir }}' 2>/dev/null || echo '<unknown>')"
        chezmoi doctor || true
    fi
}

# Self-lint check
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -x -S warning "${BASH_SOURCE[0]}" || warn "ShellCheck found issues in ${BASH_SOURCE[0]}"
fi

# Module execution guard
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    validate && execute && verify
fi