#!/usr/bin/env bash
# tools/rollback.sh - Rollback system for machine-rites
#
# This script provides safe rollback capabilities for machine-rites:
# - Lists available backups from auto-update and manual backups
# - Rollback to specific version with validation
# - Preserves user data and configuration
# - Validates rollback success with health checks
# - Includes safety checks and confirmation prompts
#
# Usage:
#   ./tools/rollback.sh [options] [backup-id]
#
# Options:
#   -h, --help          Show this help message
#   -l, --list          List available backups
#   -f, --force         Skip confirmation prompts
#   -v, --verbose       Enable verbose output
#   -d, --dry-run       Show what would be restored without making changes
#   --preserve-config   Preserve current claude-flow config (default)
#   --restore-config    Restore claude-flow config from backup
#
# Examples:
#   ./tools/rollback.sh --list                    # List backups
#   ./tools/rollback.sh backup-20241201-143022    # Rollback to specific backup
#   ./tools/rollback.sh --dry-run latest          # Preview latest rollback
#   ./tools/rollback.sh --force latest            # Quick rollback to latest
#
# Dependencies: git, tar, lib/common.sh
# Self-contained: No (requires machine-rites environment)

set -euo pipefail

# Script directory and repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

# Source common utilities
# shellcheck source=../lib/common.sh
source "$REPO_DIR/lib/common.sh"

# Configuration
BACKUP_DIR="$REPO_DIR/backups/auto-update"
CLAUDE_FLOW_CONFIG="$HOME/.claude-flow"
DRY_RUN=false
FORCE_ROLLBACK=false
VERBOSE=false
LIST_ONLY=false
PRESERVE_CONFIG=true
SELECTED_BACKUP=""

# Function: show_help
# Purpose: Display comprehensive help information
show_help() {
    cat << 'EOF'
rollback.sh - Machine-Rites Rollback System

SYNOPSIS
    ./tools/rollback.sh [OPTIONS] [BACKUP-ID]

DESCRIPTION
    Safely rollback machine-rites to a previous version using backups created
    by auto-update.sh or manual backup processes. Preserves user configuration
    and validates rollback success.

OPTIONS
    -h, --help             Show this help message and exit
    -l, --list             List available backups and exit
    -f, --force            Skip confirmation prompts (use with caution)
    -v, --verbose          Enable verbose output for debugging
    -d, --dry-run          Show what would be restored without making changes
    --preserve-config      Keep current claude-flow config (default)
    --restore-config       Restore claude-flow config from backup period

ARGUMENTS
    BACKUP-ID              Specific backup to restore (see --list)
                          Special values:
                            latest    - Most recent backup
                            previous  - Second most recent backup

WORKFLOW
    1. Validate backup exists and is readable
    2. Create safety backup of current state
    3. Preserve or restore claude-flow configuration
    4. Extract backup to temporary location
    5. Replace current installation
    6. Validate rollback success
    7. Run health checks

EXAMPLES
    # List all available backups
    ./tools/rollback.sh --list

    # Preview rollback to latest backup
    ./tools/rollback.sh --dry-run latest

    # Rollback to specific backup with confirmation
    ./tools/rollback.sh machine-rites-backup-20241201-143022

    # Quick rollback to latest (skip prompts)
    ./tools/rollback.sh --force latest

    # Rollback and restore old claude-flow config
    ./tools/rollback.sh --restore-config latest

BACKUP SOURCES
    Auto-update backups:    ./backups/auto-update/machine-rites-backup-*.tar.gz
    Manual backups:         ./backups/manual/machine-rites-*.tar.gz
    Config backups:         ./backups/auto-update/claude-flow-config-*.tar.gz

SAFETY FEATURES
    - Creates safety backup before rollback
    - Validates backup integrity before proceeding
    - Preserves user configuration by default
    - Confirmation prompts for destructive operations
    - Health check validation after rollback
    - Automatic cleanup of failed rollback attempts

FILES
    $HOME/.claude-flow/               Claude-flow configuration
    ./backups/auto-update/            Auto-update backups
    ./backups/manual/                 Manual backups
    ./backups/rollback-safety/        Safety backups

EXIT CODES
    0    Success
    1    General error
    2    Backup not found
    3    Backup validation failed
    4    Rollback failed
    5    Health check failed
    6    User cancelled operation

AUTHOR
    Machine-Rites Development Team
EOF
}

# Function: check_dependencies
# Purpose: Verify required tools are available
check_rollback_deps() {
    check_dependencies git tar file

    if [[ ! -f "$REPO_DIR/lib/common.sh" ]]; then
        die "Common library not found at $REPO_DIR/lib/common.sh"
    fi

    if [[ ! -d "$BACKUP_DIR" ]]; then
        die "Backup directory not found at $BACKUP_DIR"
    fi
}

# Function: list_backups
# Purpose: Display available backups with details
list_backups() {
    local backup_files=() manual_backups=() config_backups=()
    local backup_file size date_str

    info "=== Available Backups ==="

    # Auto-update backups
    if [[ -d "$BACKUP_DIR" ]]; then
        readarray -t backup_files < <(find "$BACKUP_DIR" -name "machine-rites-backup-*.tar.gz" 2>/dev/null | sort -r)
    fi

    # Manual backups
    if [[ -d "$REPO_DIR/backups/manual" ]]; then
        readarray -t manual_backups < <(find "$REPO_DIR/backups/manual" -name "machine-rites-*.tar.gz" 2>/dev/null | sort -r)
    fi

    # Config backups
    if [[ -d "$BACKUP_DIR" ]]; then
        readarray -t config_backups < <(find "$BACKUP_DIR" -name "claude-flow-config-*.tar.gz" 2>/dev/null | sort -r)
    fi

    # Display auto-update backups
    if [[ ${#backup_files[@]} -gt 0 ]]; then
        echo
        info "Auto-Update Backups:"
        printf "%-40s %-10s %-20s\n" "BACKUP ID" "SIZE" "DATE"
        printf "%-40s %-10s %-20s\n" "$(printf '%.40s' "----------------------------------------")" "----------" "--------------------"

        for backup_file in "${backup_files[@]}"; do
            if [[ -f "$backup_file" ]]; then
                size=$(du -h "$backup_file" | cut -f1)
                date_str=$(stat -c %y "$backup_file" | cut -d' ' -f1,2 | cut -d'.' -f1)
                printf "%-40s %-10s %-20s\n" "$(basename "$backup_file" .tar.gz)" "$size" "$date_str"
            fi
        done
    else
        warn "No auto-update backups found"
    fi

    # Display manual backups
    if [[ ${#manual_backups[@]} -gt 0 ]]; then
        echo
        info "Manual Backups:"
        printf "%-40s %-10s %-20s\n" "BACKUP ID" "SIZE" "DATE"
        printf "%-40s %-10s %-20s\n" "$(printf '%.40s' "----------------------------------------")" "----------" "--------------------"

        for backup_file in "${manual_backups[@]}"; do
            if [[ -f "$backup_file" ]]; then
                size=$(du -h "$backup_file" | cut -f1)
                date_str=$(stat -c %y "$backup_file" | cut -d' ' -f1,2 | cut -d'.' -f1)
                printf "%-40s %-10s %-20s\n" "$(basename "$backup_file" .tar.gz)" "$size" "$date_str"
            fi
        done
    fi

    # Display config backups
    if [[ ${#config_backups[@]} -gt 0 ]]; then
        echo
        info "Configuration Backups:"
        printf "%-40s %-10s %-20s\n" "CONFIG BACKUP ID" "SIZE" "DATE"
        printf "%-40s %-10s %-20s\n" "$(printf '%.40s' "----------------------------------------")" "----------" "--------------------"

        for backup_file in "${config_backups[@]}"; do
            if [[ -f "$backup_file" ]]; then
                size=$(du -h "$backup_file" | cut -f1)
                date_str=$(stat -c %y "$backup_file" | cut -d' ' -f1,2 | cut -d'.' -f1)
                printf "%-40s %-10s %-20s\n" "$(basename "$backup_file" .tar.gz)" "$size" "$date_str"
            fi
        done
    fi

    echo
    info "Special backup IDs:"
    info "  latest    - Most recent backup"
    info "  previous  - Second most recent backup"
    echo
    info "Usage: ./tools/rollback.sh [backup-id]"
}

# Function: resolve_backup_id
# Purpose: Convert special backup IDs to actual backup paths
resolve_backup_id() {
    local backup_id="$1"
    local backup_files=() resolved_path

    # Handle special cases
    case "$backup_id" in
        "latest")
            readarray -t backup_files < <(find "$BACKUP_DIR" "$REPO_DIR/backups/manual" -name "machine-rites-*.tar.gz" 2>/dev/null | sort -r)
            if [[ ${#backup_files[@]} -eq 0 ]]; then
                die "No backups found for 'latest'"
            fi
            resolved_path="${backup_files[0]}"
            ;;
        "previous")
            readarray -t backup_files < <(find "$BACKUP_DIR" "$REPO_DIR/backups/manual" -name "machine-rites-*.tar.gz" 2>/dev/null | sort -r)
            if [[ ${#backup_files[@]} -lt 2 ]]; then
                die "No 'previous' backup found (need at least 2 backups)"
            fi
            resolved_path="${backup_files[1]}"
            ;;
        *)
            # Check if it's a full path
            if [[ -f "$backup_id" ]]; then
                resolved_path="$backup_id"
            # Check in auto-update backups
            elif [[ -f "$BACKUP_DIR/$backup_id.tar.gz" ]]; then
                resolved_path="$BACKUP_DIR/$backup_id.tar.gz"
            # Check in manual backups
            elif [[ -f "$REPO_DIR/backups/manual/$backup_id.tar.gz" ]]; then
                resolved_path="$REPO_DIR/backups/manual/$backup_id.tar.gz"
            else
                die "Backup not found: $backup_id"
            fi
            ;;
    esac

    if [[ ! -f "$resolved_path" ]]; then
        die "Backup file does not exist: $resolved_path"
    fi

    echo "$resolved_path"
}

# Function: validate_backup
# Purpose: Verify backup integrity and contents
validate_backup() {
    local backup_path="$1"

    info "Validating backup: $(basename "$backup_path")"

    # Check file exists and is readable
    if [[ ! -r "$backup_path" ]]; then
        die "Backup file is not readable: $backup_path"
    fi

    # Check if it's a valid tar.gz file
    if ! file "$backup_path" | grep -q "gzip compressed"; then
        die "Backup file is not a valid gzip archive: $backup_path"
    fi

    # Test archive integrity
    if ! tar -tzf "$backup_path" >/dev/null 2>&1; then
        die "Backup archive is corrupted or invalid: $backup_path"
    fi

    # Check if archive contains expected structure
    if ! tar -tzf "$backup_path" | grep -q "tools/"; then
        warn "Backup may not contain complete machine-rites structure"
    fi

    if [[ $VERBOSE == true ]]; then
        local archive_size file_count
        archive_size=$(du -h "$backup_path" | cut -f1)
        file_count=$(tar -tzf "$backup_path" | wc -l)
        info "Backup validation: $archive_size, $file_count files"
    fi

    say "Backup validation successful"
}

# Function: create_safety_backup
# Purpose: Create backup of current state before rollback
create_safety_backup() {
    local safety_dir="$REPO_DIR/backups/rollback-safety"
    local safety_backup safety_timestamp

    safety_timestamp=$(date +%Y%m%d-%H%M%S)
    safety_backup="$safety_dir/pre-rollback-$safety_timestamp.tar.gz"

    info "Creating safety backup before rollback..."
    mkdir -p "$safety_dir"

    if [[ $DRY_RUN == true ]]; then
        info "[DRY RUN] Would create safety backup: $safety_backup"
        return 0
    fi

    # Create safety backup
    if tar czf "$safety_backup" \
        --exclude='.git' \
        --exclude='backups' \
        --exclude='node_modules' \
        --exclude='.DS_Store' \
        -C "$REPO_DIR/.." \
        "$(basename "$REPO_DIR")"; then
        say "Safety backup created: $safety_backup"
    else
        die "Failed to create safety backup"
    fi

    # Keep only last 5 safety backups
    ls -t "$safety_dir"/pre-rollback-*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm

    if [[ $VERBOSE == true ]]; then
        info "Cleaned old safety backups, keeping last 5"
    fi
}

# Function: preserve_current_config
# Purpose: Backup current claude-flow configuration
preserve_current_config() {
    local config_backup="$BACKUP_DIR/claude-flow-current-$(date +%Y%m%d-%H%M%S).tar.gz"

    if [[ ! -d "$CLAUDE_FLOW_CONFIG" ]]; then
        warn "Claude-flow configuration not found at $CLAUDE_FLOW_CONFIG"
        return 0
    fi

    if [[ $PRESERVE_CONFIG == false ]]; then
        info "Skipping current config preservation (--restore-config specified)"
        return 0
    fi

    info "Preserving current claude-flow configuration..."
    mkdir -p "$BACKUP_DIR"

    if [[ $DRY_RUN == true ]]; then
        info "[DRY RUN] Would preserve current config to: $config_backup"
        return 0
    fi

    if tar czf "$config_backup" -C "$HOME" ".claude-flow"; then
        say "Current claude-flow config preserved: $config_backup"
    else
        warn "Failed to preserve current claude-flow configuration"
    fi
}

# Function: perform_rollback
# Purpose: Execute the actual rollback process
perform_rollback() {
    local backup_path="$1"
    local temp_dir rollback_dir

    temp_dir=$(mktemp -d)
    rollback_dir="$temp_dir/machine-rites-rollback"

    info "Performing rollback from $(basename "$backup_path")..."

    if [[ $DRY_RUN == true ]]; then
        info "[DRY RUN] Would extract: $backup_path"
        info "[DRY RUN] Would replace current installation"
        info "[DRY RUN] Would preserve: $(find "$REPO_DIR" -maxdepth 1 -name ".*" -not -name ".git" | wc -l) dotfiles"
        return 0
    fi

    # Extract backup to temporary directory
    mkdir -p "$rollback_dir"
    if ! tar xzf "$backup_path" -C "$rollback_dir"; then
        rm -rf "$temp_dir"
        die "Failed to extract backup archive"
    fi

    # Find the actual content directory
    local content_dir
    content_dir=$(find "$rollback_dir" -mindepth 1 -maxdepth 1 -type d | head -n1)
    if [[ -z "$content_dir" ]]; then
        rm -rf "$temp_dir"
        die "Invalid backup structure: no content directory found"
    fi

    # Preserve important files/directories
    local preserve_items=(".git" ".env.local" ".vscode" "backups")
    local temp_preserve="$temp_dir/preserve"
    mkdir -p "$temp_preserve"

    for item in "${preserve_items[@]}"; do
        if [[ -e "$REPO_DIR/$item" ]]; then
            cp -a "$REPO_DIR/$item" "$temp_preserve/"
            if [[ $VERBOSE == true ]]; then
                info "Preserved: $item"
            fi
        fi
    done

    # Remove current installation (except preserved items)
    find "$REPO_DIR" -mindepth 1 -maxdepth 1 ! -name ".git" ! -name "backups" -exec rm -rf {} +

    # Copy rollback content
    cp -a "$content_dir"/* "$REPO_DIR/"

    # Restore preserved items
    for item in "${preserve_items[@]}"; do
        if [[ -e "$temp_preserve/$item" ]]; then
            rm -rf "$REPO_DIR/$item"
            cp -a "$temp_preserve/$item" "$REPO_DIR/"
            if [[ $VERBOSE == true ]]; then
                info "Restored: $item"
            fi
        fi
    done

    # Cleanup
    rm -rf "$temp_dir"

    say "Rollback extraction completed"
}

# Function: restore_config_from_backup
# Purpose: Restore claude-flow config from backup period
restore_config_from_backup() {
    local backup_timestamp config_backup

    if [[ $PRESERVE_CONFIG == true ]]; then
        return 0  # Skip if preserving current config
    fi

    # Extract timestamp from backup filename to find matching config backup
    backup_timestamp=$(basename "$SELECTED_BACKUP" | grep -o '[0-9]\{8\}-[0-9]\{6\}' | head -n1)

    if [[ -z "$backup_timestamp" ]]; then
        warn "Cannot determine backup timestamp for config restoration"
        return 0
    fi

    config_backup="$BACKUP_DIR/claude-flow-config-$backup_timestamp.tar.gz"

    if [[ ! -f "$config_backup" ]]; then
        warn "No matching claude-flow config backup found for $backup_timestamp"
        return 0
    fi

    info "Restoring claude-flow configuration from backup period..."

    if [[ $DRY_RUN == true ]]; then
        info "[DRY RUN] Would restore config from: $config_backup"
        return 0
    fi

    # Remove current config and restore from backup
    rm -rf "$CLAUDE_FLOW_CONFIG"
    if tar xzf "$config_backup" -C "$HOME"; then
        say "Claude-flow configuration restored from backup period"
    else
        warn "Failed to restore claude-flow configuration from backup"
    fi
}

# Function: validate_rollback
# Purpose: Verify rollback was successful
validate_rollback() {
    info "Validating rollback..."

    if [[ $DRY_RUN == true ]]; then
        info "[DRY RUN] Would validate rollback success"
        info "[DRY RUN] Would run health checks"
        return 0
    fi

    # Basic file structure checks
    local required_files=("tools/doctor.sh" "lib/common.sh" "README.md")
    for file in "${required_files[@]}"; do
        if [[ ! -f "$REPO_DIR/$file" ]]; then
            die "Rollback validation failed: missing required file $file"
        fi
    done

    # Check git repository integrity
    if ! git status >/dev/null 2>&1; then
        die "Rollback validation failed: git repository corrupted"
    fi

    # Run health check if available
    if [[ -f "$REPO_DIR/tools/doctor.sh" ]]; then
        info "Running health check..."
        if "$REPO_DIR/tools/doctor.sh" --quiet; then
            say "Health check passed"
        else
            warn "Health check reported issues - rollback may be incomplete"
            return 1
        fi
    fi

    say "Rollback validation successful"
}

# Function: main
# Purpose: Main execution flow
main() {
    local backup_path

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -l|--list)
                LIST_ONLY=true
                shift
                ;;
            -f|--force)
                FORCE_ROLLBACK=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --preserve-config)
                PRESERVE_CONFIG=true
                shift
                ;;
            --restore-config)
                PRESERVE_CONFIG=false
                shift
                ;;
            -*)
                die "Unknown option: $1. Use --help for usage information."
                ;;
            *)
                if [[ -z "$SELECTED_BACKUP" ]]; then
                    SELECTED_BACKUP="$1"
                else
                    die "Multiple backup IDs specified. Use --help for usage information."
                fi
                shift
                ;;
        esac
    done

    # Check dependencies
    check_rollback_deps

    # Handle list-only mode
    if [[ $LIST_ONLY == true ]]; then
        list_backups
        exit 0
    fi

    # Require backup ID for rollback
    if [[ -z "$SELECTED_BACKUP" ]]; then
        die "No backup ID specified. Use --list to see available backups."
    fi

    # Header
    if [[ $DRY_RUN == true ]]; then
        info "=== Machine-Rites Rollback (DRY RUN) ==="
    else
        info "=== Machine-Rites Rollback ==="
    fi

    # Resolve and validate backup
    backup_path=$(resolve_backup_id "$SELECTED_BACKUP")
    validate_backup "$backup_path"

    # Show backup info
    info "Selected backup: $(basename "$backup_path")"
    if [[ $VERBOSE == true ]]; then
        info "Full path: $backup_path"
        info "Size: $(du -h "$backup_path" | cut -f1)"
        info "Date: $(stat -c %y "$backup_path" | cut -d'.' -f1)"
    fi

    # Confirmation (unless forced)
    if [[ $FORCE_ROLLBACK == false && $DRY_RUN == false ]]; then
        echo
        warn "This will replace your current machine-rites installation!"
        if [[ $PRESERVE_CONFIG == true ]]; then
            info "Claude-flow configuration will be preserved"
        else
            warn "Claude-flow configuration will be restored from backup period"
        fi
        echo

        if ! confirm "Continue with rollback?"; then
            info "Rollback cancelled by user"
            exit 6
        fi
    fi

    # Perform rollback workflow
    preserve_current_config
    create_safety_backup
    perform_rollback "$backup_path"
    restore_config_from_backup
    validate_rollback

    # Success message
    if [[ $DRY_RUN == true ]]; then
        say "Dry run complete - no changes made"
        info "Run without --dry-run to perform actual rollback"
    else
        say "Rollback completed successfully!"
        info "Restored from: $(basename "$backup_path")"

        if [[ $PRESERVE_CONFIG == true ]]; then
            info "Claude-flow configuration preserved"
        else
            info "Claude-flow configuration restored from backup period"
        fi

        info "Safety backup available in: $REPO_DIR/backups/rollback-safety/"
        info "Use ./tools/auto-update.sh to update to latest version"
    fi
}

# Execute main function with all arguments
main "$@"