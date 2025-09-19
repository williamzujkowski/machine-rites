#!/usr/bin/env bash
# tools/auto-update.sh - Automated update system for machine-rites
#
# This script provides automated updates from GitHub with safety features:
# - Checks for updates from remote repository
# - Creates backup before updating
# - Downloads and applies updates safely
# - Validates update success
# - Preserves claude-flow configuration
# - Supports dry-run mode for testing
#
# Usage:
#   ./tools/auto-update.sh [options]
#
# Options:
#   -h, --help      Show this help message
#   -d, --dry-run   Show what would be updated without making changes
#   -f, --force     Force update even if no changes detected
#   -v, --verbose   Enable verbose output
#   -b, --backup    Create backup before update (default: yes)
#   --no-backup     Skip backup creation (not recommended)
#
# Examples:
#   ./tools/auto-update.sh                # Normal update
#   ./tools/auto-update.sh --dry-run      # Check for updates only
#   ./tools/auto-update.sh --force        # Force update
#
# Dependencies: git, curl, lib/common.sh
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
FORCE_UPDATE=false
VERBOSE=false
CREATE_BACKUP=true
GITHUB_REPO="williamzujkowski/machine-rites"
GITHUB_API="https://api.github.com/repos"

# Function: show_help
# Purpose: Display comprehensive help information
show_help() {
    cat << 'EOF'
auto-update.sh - Automated Machine-Rites Update System

SYNOPSIS
    ./tools/auto-update.sh [OPTIONS]

DESCRIPTION
    Safely updates machine-rites from GitHub with backup and validation.
    Preserves claude-flow configuration and user customizations.

OPTIONS
    -h, --help         Show this help message and exit
    -d, --dry-run      Show what would be updated without making changes
    -f, --force        Force update even if no changes detected
    -v, --verbose      Enable verbose output for debugging
    -b, --backup       Create backup before update (default)
    --no-backup        Skip backup creation (not recommended)

WORKFLOW
    1. Check current version and remote changes
    2. Create backup of current installation (if enabled)
    3. Preserve claude-flow configuration
    4. Download and apply updates
    5. Validate update success
    6. Restore claude-flow configuration

EXAMPLES
    # Check for available updates
    ./tools/auto-update.sh --dry-run

    # Perform normal update with backup
    ./tools/auto-update.sh

    # Force update with verbose output
    ./tools/auto-update.sh --force --verbose

    # Update without backup (risky)
    ./tools/auto-update.sh --no-backup

SAFETY FEATURES
    - Automatic backup before updates
    - Preserves claude-flow configuration
    - Validates git repository state
    - Checks for uncommitted changes
    - Rollback capability via tools/rollback.sh

FILES
    $HOME/.claude-flow/          Claude-flow configuration (preserved)
    ./backups/auto-update/       Update backups
    ./tools/rollback.sh          Rollback utility

EXIT CODES
    0    Success
    1    General error
    2    No updates available
    3    Backup failed
    4    Update failed
    5    Validation failed

AUTHOR
    Machine-Rites Development Team
EOF
}

# Function: check_dependencies
# Purpose: Verify required tools are available
check_auto_update_deps() {
    check_dependencies git curl jq tar

    if [[ ! -f "$REPO_DIR/lib/common.sh" ]]; then
        die "Common library not found at $REPO_DIR/lib/common.sh"
    fi
}

# Function: get_current_version
# Purpose: Get current git commit hash and branch
get_current_version() {
    local current_commit current_branch

    current_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")

    if [[ $VERBOSE == true ]]; then
        info "Current version: $current_commit on branch $current_branch"
    fi

    echo "$current_commit"
}

# Function: check_remote_updates
# Purpose: Check if updates are available from GitHub
check_remote_updates() {
    local current_commit="$1"
    local remote_commit remote_url

    info "Checking for updates from GitHub..."

    # Get remote commit from GitHub API
    remote_url="$GITHUB_API/$GITHUB_REPO/commits/main"

    if ! remote_commit=$(curl -s "$remote_url" | jq -r '.sha' 2>/dev/null); then
        die "Failed to fetch remote version from GitHub API"
    fi

    if [[ -z "$remote_commit" || "$remote_commit" == "null" ]]; then
        die "Invalid response from GitHub API"
    fi

    if [[ $VERBOSE == true ]]; then
        info "Remote version: $remote_commit"
    fi

    if [[ "$current_commit" == "$remote_commit" ]]; then
        if [[ $FORCE_UPDATE == false ]]; then
            say "Already up to date (${current_commit:0:8})"
            exit 2
        else
            warn "Forcing update even though already current"
        fi
    fi

    echo "$remote_commit"
}

# Function: check_git_status
# Purpose: Ensure repository is in clean state
check_git_status() {
    if [[ -n "$(git status --porcelain)" ]]; then
        warn "Repository has uncommitted changes:"
        git status --short

        if [[ $DRY_RUN == false ]]; then
            if ! confirm "Continue with update anyway?"; then
                die "Update cancelled due to uncommitted changes"
            fi
        fi
    fi
}

# Function: create_backup
# Purpose: Create timestamped backup of current state
create_backup() {
    if [[ $CREATE_BACKUP == false ]]; then
        warn "Skipping backup creation (--no-backup specified)"
        return 0
    fi

    local backup_timestamp backup_file
    backup_timestamp=$(date +%Y%m%d-%H%M%S)
    backup_file="$BACKUP_DIR/machine-rites-backup-$backup_timestamp.tar.gz"

    info "Creating backup..."
    mkdir -p "$BACKUP_DIR"

    if [[ $DRY_RUN == true ]]; then
        info "[DRY RUN] Would create backup: $backup_file"
        return 0
    fi

    # Create backup excluding .git directory and backups
    if tar czf "$backup_file" \
        --exclude='.git' \
        --exclude='backups' \
        --exclude='node_modules' \
        --exclude='.DS_Store' \
        -C "$REPO_DIR/.." \
        "$(basename "$REPO_DIR")"; then
        say "Backup created: $backup_file"
    else
        die "Failed to create backup"
    fi

    # Keep only last 10 backups
    ls -t "$BACKUP_DIR"/machine-rites-backup-*.tar.gz 2>/dev/null | tail -n +11 | xargs -r rm

    if [[ $VERBOSE == true ]]; then
        info "Cleaned old backups, keeping last 10"
    fi
}

# Function: preserve_claude_flow_config
# Purpose: Backup claude-flow configuration
preserve_claude_flow_config() {
    local config_backup="$BACKUP_DIR/claude-flow-config-$(date +%Y%m%d-%H%M%S).tar.gz"

    if [[ ! -d "$CLAUDE_FLOW_CONFIG" ]]; then
        warn "Claude-flow configuration not found at $CLAUDE_FLOW_CONFIG"
        return 0
    fi

    info "Preserving claude-flow configuration..."
    mkdir -p "$BACKUP_DIR"

    if [[ $DRY_RUN == true ]]; then
        info "[DRY RUN] Would preserve claude-flow config to: $config_backup"
        return 0
    fi

    if tar czf "$config_backup" -C "$HOME" ".claude-flow"; then
        say "Claude-flow config preserved: $config_backup"
    else
        warn "Failed to preserve claude-flow configuration"
    fi
}

# Function: perform_update
# Purpose: Execute the actual update process
perform_update() {
    local remote_commit="$1"

    info "Performing update to ${remote_commit:0:8}..."

    if [[ $DRY_RUN == true ]]; then
        info "[DRY RUN] Would update from $(get_current_version | cut -c1-8) to ${remote_commit:0:8}"
        info "[DRY RUN] Changes would include:"
        git log --oneline "HEAD..origin/main" 2>/dev/null || info "[DRY RUN] (unable to show changes - would fetch first)"
        return 0
    fi

    # Fetch latest changes
    if ! git fetch origin; then
        die "Failed to fetch updates from origin"
    fi

    # Show what will be updated
    if [[ $VERBOSE == true ]]; then
        info "Changes to be applied:"
        git log --oneline "HEAD..origin/main" || warn "No commit history available"
    fi

    # Perform update
    if git merge --ff-only origin/main; then
        say "Successfully updated to $(git rev-parse --short HEAD)"
    else
        die "Failed to apply updates (merge conflict or non-fast-forward)"
    fi
}

# Function: validate_update
# Purpose: Verify update was successful
validate_update() {
    local expected_commit="$1"
    local actual_commit

    actual_commit=$(get_current_version)

    if [[ $DRY_RUN == true ]]; then
        info "[DRY RUN] Would validate update to ${expected_commit:0:8}"
        return 0
    fi

    info "Validating update..."

    if [[ "$actual_commit" != "$expected_commit" ]]; then
        die "Update validation failed: expected $expected_commit, got $actual_commit"
    fi

    # Run basic health check
    if [[ -f "$REPO_DIR/tools/doctor.sh" ]]; then
        info "Running health check..."
        if "$REPO_DIR/tools/doctor.sh" --quiet; then
            say "Health check passed"
        else
            warn "Health check reported issues - update successful but system may need attention"
        fi
    fi

    say "Update validation successful"
}

# Function: restore_claude_flow_config
# Purpose: Restore claude-flow configuration if needed
restore_claude_flow_config() {
    # This is mostly a placeholder since claude-flow config is external to the repo
    # and shouldn't be affected by the update, but we preserve it as a safety measure

    if [[ $DRY_RUN == true ]]; then
        info "[DRY RUN] Would ensure claude-flow config is intact"
        return 0
    fi

    if [[ -d "$CLAUDE_FLOW_CONFIG" ]]; then
        info "Claude-flow configuration preserved successfully"
    else
        warn "Claude-flow configuration directory not found after update"
        info "You may need to reconfigure claude-flow"
    fi
}

# Function: main
# Purpose: Main execution flow
main() {
    local current_commit remote_commit

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE_UPDATE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -b|--backup)
                CREATE_BACKUP=true
                shift
                ;;
            --no-backup)
                CREATE_BACKUP=false
                shift
                ;;
            *)
                die "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done

    # Header
    if [[ $DRY_RUN == true ]]; then
        info "=== Machine-Rites Auto-Update (DRY RUN) ==="
    else
        info "=== Machine-Rites Auto-Update ==="
    fi

    # Pre-flight checks
    check_auto_update_deps
    check_git_status

    # Get current and remote versions
    current_commit=$(get_current_version)
    remote_commit=$(check_remote_updates "$current_commit")

    # Perform update workflow
    preserve_claude_flow_config
    create_backup
    perform_update "$remote_commit"
    validate_update "$remote_commit"
    restore_claude_flow_config

    # Success message
    if [[ $DRY_RUN == true ]]; then
        say "Dry run complete - no changes made"
        info "Run without --dry-run to perform actual update"
    else
        say "Auto-update completed successfully!"
        info "Updated from ${current_commit:0:8} to ${remote_commit:0:8}"

        if [[ $CREATE_BACKUP == true ]]; then
            info "Backup available in: $BACKUP_DIR"
            info "Use ./tools/rollback.sh to restore if needed"
        fi
    fi
}

# Execute main function with all arguments
main "$@"