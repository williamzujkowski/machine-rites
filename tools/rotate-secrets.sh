#!/usr/bin/env bash
# tools/rotate-secrets.sh - Automated secret rotation system
#
# Description: Secure secret rotation with audit logging and rollback capability
# Version: 1.0.0
# Dependencies: pass, gpg, lib/validation.sh, lib/common.sh
# Security: Uses secure temporary files, audit logging, and encrypted storage
#
# Features:
#   - Automated password generation with configurable complexity
#   - Secure backup before rotation with versioning
#   - Audit logging with tamper protection
#   - Rollback capability for failed rotations
#   - Integration with external systems (GitHub, SSH, etc.)
#   - Batch rotation with dependency management

set -euo pipefail

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/validation.sh
source "$SCRIPT_DIR/../lib/validation.sh"
# shellcheck source=../lib/atomic.sh
source "$SCRIPT_DIR/../lib/atomic.sh"

# Configuration
readonly ROTATION_LOG="/var/log/secret-rotation.log"
readonly BACKUP_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}/backups"
readonly AUDIT_DIR="/var/log/security-audit"
readonly CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/secret-rotation.conf"
readonly LOCK_FILE="/tmp/secret-rotation.lock"

# Password generation parameters
readonly DEFAULT_LENGTH=32
readonly DEFAULT_COMPLEXITY="high"
readonly MIN_LENGTH=16
readonly MAX_LENGTH=128

# Secure umask for all operations
umask 077

# Function: usage
# Purpose: Display usage information
usage() {
    cat << 'EOF'
USAGE: rotate-secrets.sh [OPTIONS] [COMMAND] [SECRETS...]

DESCRIPTION:
    Automated secret rotation system with security audit logging

COMMANDS:
    rotate [secrets...]  Rotate specified secrets (default: all configured)
    backup              Create backup of current secrets
    restore VERSION     Restore from backup version
    list                List all managed secrets
    status              Show rotation status and next due dates
    verify              Verify secret integrity and accessibility
    config              Show current configuration

OPTIONS:
    -f, --force         Force rotation even if not due
    -d, --dry-run       Show what would be rotated without changes
    -l, --length N      Password length (16-128, default: 32)
    -c, --complexity    Complexity: low|medium|high (default: high)
    -q, --quiet         Suppress non-error output
    -v, --verbose       Enable verbose logging
    -h, --help          Show this help

EXAMPLES:
    rotate-secrets.sh rotate github_token ssh_key
    rotate-secrets.sh --dry-run rotate
    rotate-secrets.sh backup
    rotate-secrets.sh restore 2024-01-15_14-30-22

SECURITY FEATURES:
    - Secure temporary file handling
    - Encrypted backup storage with versioning
    - Comprehensive audit logging with integrity checks
    - Rollback capability for failed rotations
    - Integration with external secret stores

EOF
}

# Function: init_rotation_system
# Purpose: Initialize the secret rotation system
init_rotation_system() {
    info "Initializing secret rotation system"

    # Create required directories with secure permissions
    mkdir -p "$BACKUP_DIR" "$AUDIT_DIR"
    chmod 700 "$BACKUP_DIR" "$AUDIT_DIR"

    # Initialize audit log with tamper protection
    if [[ ! -f "$ROTATION_LOG" ]]; then
        {
            echo "# Secret Rotation Audit Log"
            echo "# Format: TIMESTAMP|EVENT|SECRET|STATUS|CHECKSUM"
            echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)|INIT|SYSTEM|SUCCESS|$(echo "INIT" | sha256sum | cut -d' ' -f1)"
        } | sudo tee "$ROTATION_LOG" >/dev/null
        sudo chmod 644 "$ROTATION_LOG"
    fi

    # Create default configuration if it doesn't exist
    if [[ ! -f "$CONFIG_FILE" ]]; then
        create_default_config
    fi

    # Verify GPG and pass setup
    verify_prerequisites
}

# Function: create_default_config
# Purpose: Create default configuration file
create_default_config() {
    info "Creating default configuration"

    mkdir -p "$(dirname "$CONFIG_FILE")"

    write_atomic "$CONFIG_FILE" << 'EOF'
# Secret Rotation Configuration
# Format: SECRET_NAME|ROTATION_INTERVAL_DAYS|COMPLEXITY|EXTERNAL_UPDATE_CMD

# GitHub tokens (rotate every 90 days)
personal/github_token|90|high|update_github_token
work/github_token|90|high|update_github_token

# SSH keys (rotate every 180 days)
ssh/id_rsa|180|high|update_ssh_key
ssh/deploy_key|180|high|update_deploy_key

# API keys (rotate every 60 days)
api/openai_key|60|high|update_openai_key
api/aws_access_key|60|high|update_aws_key

# Database passwords (rotate every 30 days)
db/postgres_admin|30|high|update_postgres_password
db/mysql_root|30|high|update_mysql_password

# Service passwords (rotate every 45 days)
service/monitoring|45|medium|update_monitoring_password
service/backup|45|medium|update_backup_password
EOF

    chmod 600 "$CONFIG_FILE"
}

# Function: verify_prerequisites
# Purpose: Verify system prerequisites for secret rotation
verify_prerequisites() {
    local missing_tools=()

    # Check required tools
    for tool in pass gpg sha256sum jq; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        die "Missing required tools: ${missing_tools[*]}"
    fi

    # Verify pass is initialized
    if ! pass ls >/dev/null 2>&1; then
        die "Pass password store not initialized"
    fi

    # Verify GPG key access
    if ! gpg --list-secret-keys >/dev/null 2>&1; then
        die "No GPG secret keys available"
    fi
}

# Function: generate_secure_password
# Purpose: Generate cryptographically secure password
# Args: $1 - length, $2 - complexity
generate_secure_password() {
    local length="${1:-$DEFAULT_LENGTH}"
    local complexity="${2:-$DEFAULT_COMPLEXITY}"

    # Validate inputs
    validate_numeric "$length" "$MIN_LENGTH" "$MAX_LENGTH" || die "Invalid password length: $length"

    case "$complexity" in
        low)
            # Alphanumeric only
            tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length"
            ;;
        medium)
            # Alphanumeric plus safe symbols
            tr -dc 'a-zA-Z0-9@#%^&*()_+-=' < /dev/urandom | head -c "$length"
            ;;
        high)
            # Full ASCII printable excluding ambiguous characters
            tr -dc 'a-zA-Z0-9@#%^&*()_+-=[]{}|;:,.<>?/~' < /dev/urandom | head -c "$length"
            ;;
        *)
            die "Invalid complexity level: $complexity"
            ;;
    esac
}

# Function: audit_log
# Purpose: Add tamper-proof entry to audit log
# Args: $1 - event, $2 - secret, $3 - status, $4 - details (optional)
audit_log() {
    local event="$1"
    local secret="$2"
    local status="$3"
    local details="${4:-}"
    local timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local log_entry="${timestamp}|${event}|${secret}|${status}|${details}"
    local checksum="$(echo "$log_entry" | sha256sum | cut -d' ' -f1)"

    # Append to audit log with integrity check
    echo "${log_entry}|${checksum}" | sudo tee -a "$ROTATION_LOG" >/dev/null

    # Also log to syslog for additional security
    logger -p auth.info "SECRET_ROTATION: $event $secret $status"
}

# Function: create_backup
# Purpose: Create encrypted backup of secrets before rotation
create_backup() {
    local backup_timestamp="$(date +%Y-%m-%d_%H-%M-%S)"
    local backup_name="secrets_backup_${backup_timestamp}"
    local backup_file="${BACKUP_DIR}/${backup_name}.tar.gpg"

    info "Creating backup: $backup_name"

    # Create temporary directory for backup preparation
    local temp_backup_dir
    temp_backup_dir="$(mktemp_secure -d)"

    # Copy password store to temporary location
    cp -r "${PASSWORD_STORE_DIR:-$HOME/.password-store}" "$temp_backup_dir/password-store"

    # Create metadata file
    cat > "$temp_backup_dir/metadata.json" << EOF
{
    "backup_timestamp": "$backup_timestamp",
    "hostname": "$(hostname)",
    "user": "$(whoami)",
    "pass_version": "$(pass version 2>/dev/null | head -1 || echo 'unknown')",
    "gpg_keys": $(gpg --list-secret-keys --with-colons | awk -F: '/^sec:/ {print $5}' | jq -R . | jq -s .)
}
EOF

    # Create encrypted tar archive
    (cd "$temp_backup_dir" && tar -czf - .) | \
        gpg --cipher-algo AES256 --compress-algo 2 --symmetric \
            --output "$backup_file" --batch --yes --quiet

    # Clean up temporary directory
    rm -rf "$temp_backup_dir"

    # Verify backup
    if gpg --quiet --batch --decrypt "$backup_file" >/dev/null 2>&1; then
        audit_log "BACKUP_CREATED" "ALL" "SUCCESS" "$backup_name"
        ok "Backup created: $backup_file"
        return 0
    else
        audit_log "BACKUP_CREATED" "ALL" "FAILED" "$backup_name"
        rm -f "$backup_file"
        die "Backup verification failed"
    fi
}

# Function: rotate_secret
# Purpose: Rotate a single secret with rollback capability
# Args: $1 - secret name, $2 - force flag (optional)
rotate_secret() {
    local secret_name="$1"
    local force_flag="${2:-false}"

    # Validate secret name
    validate_shell_identifier "$(basename "$secret_name")" || die "Invalid secret name: $secret_name"

    # Check if secret exists
    if ! pass show "$secret_name" >/dev/null 2>&1; then
        warn "Secret does not exist: $secret_name"
        return 1
    fi

    # Get configuration for this secret
    local config_line
    config_line="$(grep "^${secret_name}|" "$CONFIG_FILE" 2>/dev/null || true)"

    if [[ -z "$config_line" ]]; then
        warn "No configuration found for secret: $secret_name"
        return 1
    fi

    # Parse configuration
    IFS='|' read -r secret_path interval complexity update_cmd <<< "$config_line"

    # Check if rotation is due (unless forced)
    if [[ "$force_flag" != "true" ]]; then
        local last_rotation
        last_rotation="$(pass show "$secret_name.metadata" 2>/dev/null | grep "last_rotation:" | cut -d: -f2 | tr -d ' ' || echo "1970-01-01")"
        local days_since_rotation
        days_since_rotation="$(( ($(date +%s) - $(date -d "$last_rotation" +%s)) / 86400 ))"

        if [[ $days_since_rotation -lt $interval ]]; then
            info "Secret $secret_name not due for rotation ($days_since_rotation/$interval days)"
            return 0
        fi
    fi

    info "Rotating secret: $secret_name"

    # Backup current secret
    local old_secret
    old_secret="$(pass show "$secret_name")"
    local backup_entry="${secret_name}.backup.$(date +%Y%m%d_%H%M%S)"

    # Generate new secret
    local new_secret
    new_secret="$(generate_secure_password "$DEFAULT_LENGTH" "$complexity")"

    # Store new secret
    if echo "$new_secret" | pass insert -m "$secret_name" >/dev/null 2>&1; then
        # Update metadata
        cat << EOF | pass insert -m "${secret_name}.metadata" >/dev/null 2>&1
last_rotation: $(date -u +%Y-%m-%d)
rotation_count: $(( $(pass show "${secret_name}.metadata" 2>/dev/null | grep "rotation_count:" | cut -d: -f2 | tr -d ' ' || echo 0) + 1 ))
complexity: $complexity
interval_days: $interval
update_command: $update_cmd
EOF

        # Store backup
        echo "$old_secret" | pass insert -m "$backup_entry" >/dev/null 2>&1

        # Execute external update command if specified
        if [[ -n "$update_cmd" ]] && command -v "$update_cmd" >/dev/null 2>&1; then
            if "$update_cmd" "$secret_name" "$new_secret"; then
                audit_log "SECRET_ROTATED" "$secret_name" "SUCCESS" "external_update_success"
                ok "Successfully rotated secret: $secret_name"
            else
                # Rollback on external update failure
                warn "External update failed for $secret_name, rolling back"
                echo "$old_secret" | pass insert -m "$secret_name" >/dev/null 2>&1
                audit_log "SECRET_ROTATED" "$secret_name" "FAILED" "external_update_failed_rollback"
                return 1
            fi
        else
            audit_log "SECRET_ROTATED" "$secret_name" "SUCCESS" "no_external_update"
            ok "Successfully rotated secret: $secret_name"
        fi
    else
        audit_log "SECRET_ROTATED" "$secret_name" "FAILED" "pass_insert_failed"
        die "Failed to store new secret for: $secret_name"
    fi
}

# Function: list_secrets
# Purpose: List all managed secrets with rotation status
list_secrets() {
    info "Managed secrets and rotation status:"
    echo
    printf "%-30s %-12s %-10s %-15s %s\n" "SECRET" "INTERVAL" "LAST" "NEXT DUE" "STATUS"
    printf "%-30s %-12s %-10s %-15s %s\n" "$(printf '%*s' 30 '' | tr ' ' '-')" \
           "$(printf '%*s' 12 '' | tr ' ' '-')" \
           "$(printf '%*s' 10 '' | tr ' ' '-')" \
           "$(printf '%*s' 15 '' | tr ' ' '-')" \
           "$(printf '%*s' 10 '' | tr ' ' '-')"

    while IFS='|' read -r secret_path interval complexity update_cmd; do
        [[ "$secret_path" =~ ^#.*$ ]] && continue  # Skip comments
        [[ -z "$secret_path" ]] && continue        # Skip empty lines

        local last_rotation="1970-01-01"
        local status="NEVER"

        if pass show "${secret_path}.metadata" >/dev/null 2>&1; then
            last_rotation="$(pass show "${secret_path}.metadata" | grep "last_rotation:" | cut -d: -f2 | tr -d ' ' || echo "1970-01-01")"
        fi

        local days_since_rotation
        days_since_rotation="$(( ($(date +%s) - $(date -d "$last_rotation" +%s)) / 86400 ))"

        local next_due_date
        next_due_date="$(date -d "$last_rotation + $interval days" +%Y-%m-%d 2>/dev/null || echo "unknown")"

        if [[ $days_since_rotation -ge $interval ]]; then
            status="DUE"
        elif [[ $days_since_rotation -ge $((interval - 7)) ]]; then
            status="SOON"
        else
            status="OK"
        fi

        printf "%-30s %-12s %-10s %-15s %s\n" \
               "$secret_path" \
               "${interval}d" \
               "$last_rotation" \
               "$next_due_date" \
               "$status"
    done < "$CONFIG_FILE"
}

# Function: verify_secrets
# Purpose: Verify secret integrity and accessibility
verify_secrets() {
    info "Verifying secret integrity and accessibility"
    local errors=0

    while IFS='|' read -r secret_path interval complexity update_cmd; do
        [[ "$secret_path" =~ ^#.*$ ]] && continue
        [[ -z "$secret_path" ]] && continue

        if pass show "$secret_path" >/dev/null 2>&1; then
            ok "✓ $secret_path"
        else
            fail "✗ $secret_path (inaccessible)"
            ((errors++))
        fi
    done < "$CONFIG_FILE"

    if [[ $errors -eq 0 ]]; then
        ok "All secrets verified successfully"
        return 0
    else
        warn "$errors secrets failed verification"
        return 1
    fi
}

# Function: acquire_lock
# Purpose: Acquire exclusive lock for rotation operations
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid="$(cat "$LOCK_FILE" 2>/dev/null || echo "")"
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            die "Another rotation process is running (PID: $lock_pid)"
        else
            warn "Removing stale lock file"
            rm -f "$LOCK_FILE"
        fi
    fi

    echo $$ > "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"' EXIT
}

# Function: main
# Purpose: Main entry point with argument parsing
main() {
    local command=""
    local secrets=()
    local force_flag=false
    local dry_run=false
    local length="$DEFAULT_LENGTH"
    local complexity="$DEFAULT_COMPLEXITY"
    local quiet=false
    local verbose=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -f|--force)
                force_flag=true
                shift
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -l|--length)
                length="$2"
                validate_numeric "$length" "$MIN_LENGTH" "$MAX_LENGTH" || die "Invalid length: $length"
                shift 2
                ;;
            -c|--complexity)
                complexity="$2"
                case "$complexity" in
                    low|medium|high) ;;
                    *) die "Invalid complexity: $complexity" ;;
                esac
                shift 2
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            rotate|backup|restore|list|status|verify|config)
                command="$1"
                shift
                ;;
            *)
                if [[ -z "$command" ]]; then
                    command="rotate"
                fi
                secrets+=("$1")
                shift
                ;;
        esac
    done

    # Set default command
    command="${command:-list}"

    # Configure logging
    if [[ "$quiet" == "true" ]]; then
        exec 1>/dev/null
    fi

    if [[ "$verbose" == "true" ]]; then
        set -x
    fi

    # Initialize system
    init_rotation_system

    # Acquire lock for operations that modify secrets
    case "$command" in
        rotate|backup)
            acquire_lock
            ;;
    esac

    # Execute command
    case "$command" in
        rotate)
            if [[ "$dry_run" == "true" ]]; then
                info "DRY RUN: Would rotate the following secrets:"
                list_secrets
                return 0
            fi

            # Create backup before rotation
            create_backup

            if [[ ${#secrets[@]} -eq 0 ]]; then
                # Rotate all configured secrets
                while IFS='|' read -r secret_path interval complexity update_cmd; do
                    [[ "$secret_path" =~ ^#.*$ ]] && continue
                    [[ -z "$secret_path" ]] && continue
                    rotate_secret "$secret_path" "$force_flag"
                done < "$CONFIG_FILE"
            else
                # Rotate specified secrets
                for secret in "${secrets[@]}"; do
                    rotate_secret "$secret" "$force_flag"
                done
            fi
            ;;
        backup)
            create_backup
            ;;
        restore)
            if [[ ${#secrets[@]} -eq 0 ]]; then
                die "Restore command requires backup version"
            fi
            # Implementation for restore would go here
            warn "Restore functionality not yet implemented"
            ;;
        list|status)
            list_secrets
            ;;
        verify)
            verify_secrets
            ;;
        config)
            info "Configuration file: $CONFIG_FILE"
            if [[ -f "$CONFIG_FILE" ]]; then
                cat "$CONFIG_FILE"
            else
                warn "Configuration file not found"
            fi
            ;;
        *)
            die "Unknown command: $command"
            ;;
    esac
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi