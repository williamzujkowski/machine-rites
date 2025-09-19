#!/usr/bin/env bash
# bootstrap/modules/50-secrets.sh - GPG and Pass setup module
#
# Description: Sets up GPG keys and Pass password manager
# Version: 1.0.0
# Dependencies: lib/common.sh, 20-system-packages.sh
# Idempotent: Yes (checks existing setup)
# Rollback: Partial (warns about manual cleanup needed)
#
# This module sets up GPG keys for encryption and initializes Pass password
# manager for secure secret storage. It also handles migration from plaintext
# secrets to Pass.

set -euo pipefail

# Module metadata
readonly MODULE_NAME="50-secrets"
readonly MODULE_VERSION="1.0.0"
readonly MODULE_DESCRIPTION="GPG and Pass setup"

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"
# shellcheck source=../../lib/atomic.sh
source "$SCRIPT_DIR/../../lib/atomic.sh" 2>/dev/null || true

# Module state
GPG_KEY_GENERATED=0
PASS_INITIALIZED=0
SECRETS_MIGRATED=0

# Function: validate
# Purpose: Validate GPG and Pass prerequisites
# Args: None
# Returns: 0 if valid, 1 if not
validate() {
    info "Validating GPG and Pass prerequisites for $MODULE_NAME"

    # Check required tools are available
    local required_tools=("gpg" "pass")
    local tool

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            die "$tool not available (should be installed by 20-system-packages)"
        fi
    done

    # Check required variables
    if [[ -z "${PASS_PREFIX:-}" ]]; then
        die "PASS_PREFIX not set (should be set by 00-prereqs)"
    fi

    if [[ -z "${XDG_CONFIG_HOME:-}" ]]; then
        die "XDG_CONFIG_HOME not set (should be set by 00-prereqs)"
    fi

    return 0
}

# Function: execute
# Purpose: Execute GPG and Pass setup
# Args: None
# Returns: 0 if successful, 1 if failed
execute() {
    info "Executing GPG and Pass setup for $MODULE_NAME"

    # Ensure GPG key exists
    _ensure_gpg_key

    # Initialize Pass if needed
    _initialize_pass

    # Migrate plaintext secrets to Pass
    _migrate_plaintext_secrets

    say "GPG and Pass setup completed"
    return 0
}

# Function: verify
# Purpose: Verify GPG and Pass were set up correctly
# Args: None
# Returns: 0 if verified, 1 if not
verify() {
    info "Verifying GPG and Pass setup for $MODULE_NAME"

    # Check GPG has secret keys
    if ! gpg --list-secret-keys --with-colons 2>/dev/null | grep -q '^sec:'; then
        warn "No GPG secret keys found"
        return 1
    fi

    # Check Pass is initialized
    if ! pass ls >/dev/null 2>&1; then
        warn "Pass is not initialized"
        return 1
    fi

    # Test Pass functionality
    local test_entry="${PASS_PREFIX}/test-$(date +%s)"
    if echo "test-value" | pass insert -m "$test_entry" >/dev/null 2>&1; then
        # Clean up test entry
        pass rm "$test_entry" >/dev/null 2>&1 || true
        info "Pass functionality verified"
    else
        warn "Pass functionality test failed"
        return 1
    fi

    say "GPG and Pass verification completed successfully"
    return 0
}

# Function: rollback
# Purpose: Rollback GPG and Pass setup (limited)
# Args: None
# Returns: 0 if successful, 1 if failed
rollback() {
    info "Rolling back GPG and Pass setup for $MODULE_NAME"

    warn "GPG and Pass rollback is limited for security reasons"
    warn "Manual cleanup may be required:"
    warn "  - GPG keys: gpg --delete-secret-keys <KEY_ID>"
    warn "  - Pass store: rm -rf ~/.password-store"
    warn "  - GPG directory: rm -rf ~/.gnupg"

    # We don't automatically remove GPG keys or Pass stores as they may
    # contain important user data

    info "GPG and Pass rollback completed (manual cleanup required)"
    return 0
}

# Internal function: _ensure_gpg_key
# Purpose: Ensure a GPG key exists for encryption
_ensure_gpg_key() {
    info "Ensuring GPG key exists"

    # Check if we already have secret keys
    if gpg --list-secret-keys --with-colons 2>/dev/null | grep -q '^sec:'; then
        info "GPG secret key already exists"

        # Get key information for logging
        local key_info
        key_info=$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^sec:/ {print $5; exit}')
        info "Using existing GPG key: ${key_info:0:16}..."
        return 0
    fi

    warn "No GPG key found for pass encryption"

    if [[ "${UNATTENDED:-0}" -eq 0 ]] && [[ -t 0 ]]; then
        echo "Options:"
        echo "  1) Generate a new GPG key now (recommended)"
        echo "  2) Import existing GPG key"
        echo "  3) Skip GPG setup (pass won't work)"
        read -rp "Choice [1-3]: " -n 1 -r
        echo

        case "$REPLY" in
            1)
                _generate_gpg_key
                ;;
            2)
                echo "Please import your GPG key manually:"
                echo "  gpg --import /path/to/key.asc"
                echo "Then run this module again."
                return 1
                ;;
            3)
                warn "Skipping GPG key setup"
                return 1
                ;;
            *)
                warn "Invalid choice, skipping GPG setup"
                return 1
                ;;
        esac
    else
        info "In unattended mode - skipping GPG key generation"
        info "To generate a GPG key manually: gpg --full-generate-key"
        return 1
    fi
}

# Internal function: _generate_gpg_key
# Purpose: Generate a new GPG key interactively
_generate_gpg_key() {
    info "Generating new GPG key"

    # Check if we can run GPG key generation
    if [[ ! -t 0 ]]; then
        warn "Cannot generate GPG key without interactive terminal"
        return 1
    fi

    say "Starting GPG key generation (this will prompt for user input)"

    if gpg --full-generate-key; then
        GPG_KEY_GENERATED=1
        say "GPG key generated successfully"

        # Display key information
        local key_info
        key_info=$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^sec:/ {print $5; exit}')
        info "Generated GPG key: ${key_info:0:16}..."

        return 0
    else
        warn "GPG key generation failed"
        return 1
    fi
}

# Internal function: _initialize_pass
# Purpose: Initialize Pass password store
_initialize_pass() {
    info "Initializing Pass password store"

    # Check if Pass is already initialized
    if pass ls >/dev/null 2>&1; then
        info "Pass already initialized"
        return 0
    fi

    # Get GPG key for Pass initialization
    local gpg_key
    gpg_key=$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^sec:/ {print $5; exit}')

    if [[ -z "$gpg_key" ]]; then
        warn "No GPG key available for Pass initialization"
        return 1
    fi

    info "Initializing Pass with GPG key: ${gpg_key:0:16}..."

    if pass init "$gpg_key"; then
        PASS_INITIALIZED=1
        say "Pass initialized successfully"
        return 0
    else
        warn "Pass initialization failed"
        return 1
    fi
}

# Internal function: _migrate_plaintext_secrets
# Purpose: Migrate plaintext secrets to Pass
_migrate_plaintext_secrets() {
    local secrets_file="$XDG_CONFIG_HOME/secrets.env"

    if [[ ! -f "$secrets_file" ]]; then
        info "No plaintext secrets file found, skipping migration"
        return 0
    fi

    if ! pass ls >/dev/null 2>&1; then
        warn "Pass not initialized, cannot migrate secrets"
        return 1
    fi

    info "Migrating plaintext secrets to Pass"

    local migrated_count=0
    local failed_count=0

    while IFS= read -r line; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        # Split on first '=' only
        local key="${line%%=*}"
        local val="${line#*=}"

        # Trim whitespace around key/val
        key="${key#"${key%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"
        val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"

        # Strip matching surrounding quotes
        if [[ "$val" == \"*\" && "$val" == *\" ]]; then
            val="${val%\"}"; val="${val#\"}"
        elif [[ "$val" == \'*\' && "$val" == *\' ]]; then
            val="${val%\'}"; val="${val#\'}"
        fi

        # Only store valid shell identifiers
        if [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            local lowercase_key
            lowercase_key=$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')
            local pass_entry="${PASS_PREFIX}/${lowercase_key}"

            if printf '%s\n' "$val" | pass insert -m "$pass_entry" >/dev/null 2>&1; then
                ((migrated_count++))
                info "Migrated secret: $key -> $pass_entry"
            else
                ((failed_count++))
                warn "Failed to migrate secret: $key"
            fi
        else
            warn "Skipping invalid key format: $key"
            ((failed_count++))
        fi
    done < "$secrets_file"

    if [[ "$migrated_count" -gt 0 ]]; then
        SECRETS_MIGRATED=1
        say "Migrated $migrated_count secrets to Pass"

        if [[ "$failed_count" -gt 0 ]]; then
            warn "$failed_count secrets failed to migrate"
        fi

        # Offer to remove plaintext file
        _offer_plaintext_cleanup "$secrets_file"
    else
        info "No secrets migrated"
    fi
}

# Internal function: _offer_plaintext_cleanup
# Purpose: Offer to securely remove plaintext secrets file
# Args: $1 - Path to plaintext secrets file
_offer_plaintext_cleanup() {
    local secrets_file="$1"

    if [[ "${UNATTENDED:-0}" -eq 0 ]] && [[ -t 0 ]]; then
        echo
        warn "Plaintext secrets have been migrated to Pass"
        read -rp "Securely delete plaintext secrets file? [y/N] " -n 1 -r
        echo

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if command -v shred >/dev/null 2>&1; then
                if shred -u "$secrets_file"; then
                    say "Plaintext secrets file securely deleted"
                else
                    warn "Failed to securely delete plaintext secrets file"
                fi
            else
                if rm -f "$secrets_file"; then
                    say "Plaintext secrets file deleted (shred not available)"
                else
                    warn "Failed to delete plaintext secrets file"
                fi
            fi
        else
            info "Plaintext secrets file preserved at: $secrets_file"
            warn "Consider deleting it manually after verifying Pass migration"
        fi
    else
        info "In unattended mode - plaintext secrets file preserved"
        info "Location: $secrets_file"
        info "Consider deleting manually after verifying Pass migration"
    fi
}

# Module execution guard
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    validate && execute && verify
fi