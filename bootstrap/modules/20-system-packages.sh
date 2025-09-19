#!/usr/bin/env bash
# bootstrap/modules/20-system-packages.sh - System package installation module
#
# Description: Installs required system packages and tools
# Version: 1.0.0
# Dependencies: lib/common.sh, 00-prereqs.sh
# Idempotent: Yes (checks existing packages)
# Rollback: Partial (can remove installed packages)
#
# This module installs essential system packages including development tools,
# security tools, and utilities. It handles package manager operations safely
# and tracks installations for potential rollback.

set -euo pipefail

# Module metadata
readonly MODULE_NAME="20-system-packages"
readonly MODULE_VERSION="1.0.0"
readonly MODULE_DESCRIPTION="System package installation"

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"
# shellcheck source=../../lib/atomic.sh
source "$SCRIPT_DIR/../../lib/atomic.sh" 2>/dev/null || true

# Package lists
readonly ESSENTIAL_PACKAGES=(
    curl
    git
    gnupg
    pass
    age
    bash-completion
    openssh-client
    wget
    unzip
    tar
    gzip
)

readonly DEVELOPMENT_PACKAGES=(
    build-essential
    python3-pip
    pipx
    nodejs
    npm
    jq
)

readonly SECURITY_PACKAGES=(
    gitleaks
)

# Module state
INSTALLED_PACKAGES=()
FAILED_PACKAGES=()

# Function: validate
# Purpose: Validate package installation prerequisites
# Args: None
# Returns: 0 if valid, 1 if not
validate() {
    info "Validating package installation prerequisites for $MODULE_NAME"

    # Check if we have package manager access
    if [[ $EUID -eq 0 ]]; then
        # Running as root, can use apt directly
        if ! command -v apt-get >/dev/null 2>&1; then
            die "apt-get not available (not a Debian/Ubuntu system?)"
        fi
    else
        # Not root, need sudo
        if ! command -v sudo >/dev/null 2>&1; then
            die "sudo not available and not running as root"
        fi

        # Test sudo access
        if ! sudo -n true 2>/dev/null; then
            warn "sudo may prompt for password during package installation"
        fi
    fi

    # Check network connectivity
    if ! curl -s --connect-timeout 5 https://packages.ubuntu.com >/dev/null 2>&1; then
        warn "Network connectivity check failed - package installation may fail"
        if [[ "${UNATTENDED:-0}" -eq 0 ]] && [[ -t 0 ]]; then
            read -rp "Continue anyway? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                die "Aborted due to network connectivity issues"
            fi
        fi
    fi

    return 0
}

# Function: execute
# Purpose: Execute package installation
# Args: None
# Returns: 0 if successful, 1 if failed
execute() {
    info "Executing package installation for $MODULE_NAME"

    # Set non-interactive frontend
    export DEBIAN_FRONTEND=noninteractive

    # Update package index
    _update_package_index

    # Install essential packages
    _install_package_group "essential" ESSENTIAL_PACKAGES[@]

    # Install development packages (optional)
    if [[ "${INSTALL_DEV_PACKAGES:-1}" -eq 1 ]]; then
        _install_package_group "development" DEVELOPMENT_PACKAGES[@]
    fi

    # Install security packages
    _install_package_group "security" SECURITY_PACKAGES[@]

    # Install chezmoi via official installer (not from apt)
    _install_chezmoi

    # Set up pipx if available
    _setup_pipx

    # Install additional tools via pipx
    _install_pipx_packages

    # Install Starship prompt (optional)
    _install_starship

    # Verify critical tools
    _verify_critical_tools

    # Store installation record
    _store_installation_record

    say "Package installation completed"
    return 0
}

# Function: verify
# Purpose: Verify packages were installed correctly
# Args: None
# Returns: 0 if verified, 1 if not
verify() {
    info "Verifying package installation for $MODULE_NAME"

    local verification_failed=0

    # Check essential packages
    local package
    for package in "${ESSENTIAL_PACKAGES[@]}"; do
        if ! _verify_package_installed "$package"; then
            warn "Essential package not properly installed: $package"
            ((verification_failed++))
        fi
    done

    # Check critical commands are available
    local critical_commands=(
        "git"
        "curl"
        "gpg"
        "pass"
        "chezmoi"
    )

    local cmd
    for cmd in "${critical_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            warn "Critical command not available: $cmd"
            ((verification_failed++))
        fi
    done

    # Check versions of critical tools
    _verify_tool_versions

    if [[ "$verification_failed" -gt 0 ]]; then
        warn "Package verification failed: $verification_failed issues found"
        return 1
    fi

    say "Package verification completed successfully"
    return 0
}

# Function: rollback
# Purpose: Remove packages installed by this module
# Args: None
# Returns: 0 if successful, 1 if failed
rollback() {
    info "Rolling back package installation for $MODULE_NAME"

    local installation_record="${BACKUP_DIR:-$HOME}/.installed_packages_${MODULE_NAME}"

    if [[ ! -f "$installation_record" ]]; then
        warn "No installation record found, cannot rollback packages"
        return 1
    fi

    warn "Package rollback can be dangerous and is not recommended"
    warn "Consider manual review of packages to remove"

    if [[ "${FORCE_ROLLBACK:-0}" -ne 1 ]]; then
        if [[ "${UNATTENDED:-0}" -eq 0 ]] && [[ -t 0 ]]; then
            read -rp "Really remove installed packages? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                info "Package rollback cancelled"
                return 0
            fi
        else
            info "Package rollback skipped in unattended mode (use FORCE_ROLLBACK=1 to override)"
            return 0
        fi
    fi

    info "Attempting to remove packages installed during this session"

    local removed_count=0
    while IFS= read -r package; do
        [[ -z "$package" ]] && continue
        [[ "$package" == \#* ]] && continue

        if _remove_package "$package"; then
            ((removed_count++))
        fi
    done < "$installation_record"

    say "Package rollback completed: $removed_count packages removed"
    return 0
}

# Internal function: _update_package_index
# Purpose: Update package manager index
_update_package_index() {
    info "Updating package index"

    if [[ $EUID -eq 0 ]]; then
        apt-get update -y
    else
        sudo apt-get update -y
    fi
}

# Internal function: _install_package_group
# Purpose: Install a group of packages
# Args: $1 - Group name, $2 - Array name containing packages
_install_package_group() {
    local group_name="$1"
    local -n packages_ref=$2

    info "Installing $group_name packages"

    # Check which packages are missing
    local missing_packages=()
    local package

    for package in "${packages_ref[@]}"; do
        if ! _verify_package_installed "$package"; then
            missing_packages+=("$package")
        fi
    done

    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        info "All $group_name packages already installed"
        return 0
    fi

    info "Installing missing $group_name packages: ${missing_packages[*]}"

    # Install missing packages
    if [[ $EUID -eq 0 ]]; then
        apt-get install -y "${missing_packages[@]}" || {
            warn "Some $group_name packages failed to install"
            FAILED_PACKAGES+=("${missing_packages[@]}")
        }
    else
        sudo apt-get install -y "${missing_packages[@]}" || {
            warn "Some $group_name packages failed to install"
            FAILED_PACKAGES+=("${missing_packages[@]}")
        }
    fi

    # Track successfully installed packages
    for package in "${missing_packages[@]}"; do
        if _verify_package_installed "$package"; then
            INSTALLED_PACKAGES+=("$package")
        fi
    done
}

# Internal function: _verify_package_installed
# Purpose: Check if a package is installed
# Args: $1 - Package name
# Returns: 0 if installed, 1 if not
_verify_package_installed() {
    local package="$1"
    dpkg -s "$package" >/dev/null 2>&1
}

# Internal function: _remove_package
# Purpose: Remove a package
# Args: $1 - Package name
# Returns: 0 if successful, 1 if failed
_remove_package() {
    local package="$1"

    info "Removing package: $package"

    if [[ $EUID -eq 0 ]]; then
        apt-get remove -y "$package" 2>/dev/null
    else
        sudo apt-get remove -y "$package" 2>/dev/null
    fi
}

# Internal function: _install_chezmoi
# Purpose: Install chezmoi via official installer
_install_chezmoi() {
    if command -v chezmoi >/dev/null 2>&1; then
        info "chezmoi already installed"
        return 0
    fi

    info "Installing chezmoi via official installer"

    # Create local bin directory
    mkdir -p "$HOME/.local/bin"

    # Download and install
    if curl -fsLS get.chezmoi.io | sh -s -- -b "$HOME/.local/bin"; then
        # Add to PATH if not already there
        case ":$PATH:" in
            *":$HOME/.local/bin:"*) ;;
            *) export PATH="$HOME/.local/bin:$PATH" ;;
        esac

        if command -v chezmoi >/dev/null 2>&1; then
            say "chezmoi installed successfully"
            INSTALLED_PACKAGES+=("chezmoi")
        else
            warn "chezmoi installation failed - not found on PATH"
            FAILED_PACKAGES+=("chezmoi")
        fi
    else
        warn "chezmoi installation failed"
        FAILED_PACKAGES+=("chezmoi")
    fi
}

# Internal function: _setup_pipx
# Purpose: Set up pipx for Python package management
_setup_pipx() {
    if ! command -v pipx >/dev/null 2>&1; then
        warn "pipx not found, skipping pipx setup"
        return 0
    fi

    info "Setting up pipx"

    # Ensure pipx path
    pipx ensurepath >/dev/null 2>&1 || true

    # Add pipx bin to PATH if not already there
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) export PATH="$HOME/.local/bin:$PATH" ;;
    esac
}

# Internal function: _install_pipx_packages
# Purpose: Install Python packages via pipx
_install_pipx_packages() {
    if ! command -v pipx >/dev/null 2>&1; then
        info "pipx not available, skipping pipx packages"
        return 0
    fi

    local pipx_packages=(
        "pre-commit"
    )

    local package
    for package in "${pipx_packages[@]}"; do
        if ! command -v "$package" >/dev/null 2>&1; then
            info "Installing $package via pipx"
            if pipx install "$package" >/dev/null 2>&1; then
                INSTALLED_PACKAGES+=("pipx:$package")
            else
                warn "Failed to install $package via pipx"
                FAILED_PACKAGES+=("pipx:$package")
            fi
        else
            info "$package already available"
        fi
    done
}

# Internal function: _install_starship
# Purpose: Install Starship prompt (optional)
_install_starship() {
    if command -v starship >/dev/null 2>&1; then
        info "Starship already installed"
        return 0
    fi

    # Skip if explicitly disabled
    if [[ "${INSTALL_STARSHIP:-}" == "0" ]]; then
        info "Starship installation disabled"
        return 0
    fi

    # Prompt in interactive mode
    if [[ "${UNATTENDED:-0}" -eq 0 ]] && [[ -t 0 ]]; then
        read -rp "Install Starship prompt? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Starship installation skipped"
            return 0
        fi
    elif [[ "${INSTALL_STARSHIP:-}" != "1" ]]; then
        info "Starship installation skipped (set INSTALL_STARSHIP=1 to install in unattended mode)"
        return 0
    fi

    info "Installing Starship prompt"

    if curl -sS https://starship.rs/install.sh | sh -s -- -b "$HOME/.local/bin" -y; then
        say "Starship installed successfully"
        INSTALLED_PACKAGES+=("starship")
    else
        warn "Starship installation failed"
        FAILED_PACKAGES+=("starship")
    fi
}

# Internal function: _verify_critical_tools
# Purpose: Verify critical tools and their versions
_verify_critical_tools() {
    info "Verifying critical tools and versions"

    local tools_with_versions=(
        "chezmoi:2.0"
        "git:2.25"
        "gpg:2.0"
    )

    local tool_spec
    for tool_spec in "${tools_with_versions[@]}"; do
        local tool="${tool_spec%:*}"
        local min_version="${tool_spec#*:}"

        if command -v "$tool" >/dev/null 2>&1; then
            if declare -f need_version >/dev/null 2>&1; then
                if ! need_version "$tool" "$min_version"; then
                    warn "$tool version is old (minimum: $min_version)"
                fi
            fi

            if [[ "${VERBOSE:-0}" -eq 1 ]]; then
                local version
                version=$("$tool" --version 2>/dev/null | head -1 || echo "version unknown")
                info "$tool: $version"
            fi
        else
            warn "Critical tool not found: $tool"
        fi
    done
}

# Internal function: _store_installation_record
# Purpose: Store record of installed packages for rollback
_store_installation_record() {
    local installation_record="${BACKUP_DIR:-$HOME}/.installed_packages_${MODULE_NAME}"

    info "Storing installation record: $installation_record"

    cat > "$installation_record" <<EOF
# Package installation record for $MODULE_NAME
# Generated at: $(date -Iseconds)
# Installed packages (one per line):
EOF

    local package
    for package in "${INSTALLED_PACKAGES[@]}"; do
        echo "$package" >> "$installation_record"
    done

    if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
        echo "# Failed packages:" >> "$installation_record"
        for package in "${FAILED_PACKAGES[@]}"; do
            echo "# FAILED: $package" >> "$installation_record"
        done
    fi

    # Make record readable by owner only
    chmod 600 "$installation_record" 2>/dev/null || true
}

# Module execution guard
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    validate && execute && verify
fi