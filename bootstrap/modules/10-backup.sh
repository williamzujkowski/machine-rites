#!/usr/bin/env bash
# bootstrap/modules/10-backup.sh - Backup creation and management module
#
# Description: Creates backups of existing dotfiles and configuration
# Version: 1.0.0
# Dependencies: lib/common.sh, lib/atomic.sh
# Idempotent: Yes (creates timestamped backups)
# Rollback: Yes (restores from backup)
#
# This module creates comprehensive backups of existing dotfiles and
# configurations before making any changes. It implements rollback
# functionality and maintains a cleanup policy for old backups.

set -euo pipefail

# Module metadata
readonly MODULE_NAME="10-backup"
readonly MODULE_VERSION="1.0.0"
readonly MODULE_DESCRIPTION="Backup creation and management"

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"
# shellcheck source=../../lib/atomic.sh
source "$SCRIPT_DIR/../../lib/atomic.sh" 2>/dev/null || true

# Module state variables
BACKUP_DIR=""
BACKUP_MANIFEST=""
BACKUP_TIMESTAMP=""

# Function: validate
# Purpose: Validate backup prerequisites
# Args: None
# Returns: 0 if valid, 1 if not
validate() {
    info "Validating backup prerequisites for $MODULE_NAME"

    # Check if backup should be skipped
    if [[ "${SKIP_BACKUP:-0}" -eq 1 ]]; then
        info "Backup skipped due to SKIP_BACKUP=1"
        return 0
    fi

    # Check if HOME is writable
    if [[ ! -w "$HOME" ]]; then
        die "HOME directory is not writable: $HOME"
    fi

    # Check available disk space (require at least 100MB)
    local available_kb
    available_kb=$(df "$HOME" | awk 'NR==2 {print $4}')
    if [[ "$available_kb" -lt 102400 ]]; then
        warn "Low disk space in HOME directory: ${available_kb}KB available"
        if [[ "${UNATTENDED:-0}" -eq 0 ]] && [[ -t 0 ]]; then
            read -rp "Continue with backup anyway? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                die "Backup aborted due to low disk space"
            fi
        fi
    fi

    return 0
}

# Function: execute
# Purpose: Execute backup creation
# Args: None
# Returns: 0 if successful, 1 if failed
execute() {
    info "Executing backup creation for $MODULE_NAME"

    # Skip if backup disabled
    if [[ "${SKIP_BACKUP:-0}" -eq 1 ]]; then
        info "Backup creation skipped"
        return 0
    fi

    # Set up backup directory and timestamp
    _setup_backup_environment

    # Clean up old backups first
    _cleanup_old_backups

    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    say "Creating backup: $BACKUP_DIR"

    # Initialize backup manifest
    _initialize_backup_manifest

    # Backup existing files
    _backup_dotfiles

    # Create rollback script
    _create_rollback_script

    # Store backup information for other modules
    _export_backup_info

    say "Backup creation completed: $BACKUP_DIR"
    return 0
}

# Function: verify
# Purpose: Verify backup was created successfully
# Args: None
# Returns: 0 if verified, 1 if not
verify() {
    info "Verifying backup creation for $MODULE_NAME"

    # Skip verification if backup was skipped
    if [[ "${SKIP_BACKUP:-0}" -eq 1 ]]; then
        info "Backup verification skipped"
        return 0
    fi

    # Check backup directory exists
    if [[ ! -d "$BACKUP_DIR" ]]; then
        warn "Backup directory not found: $BACKUP_DIR"
        return 1
    fi

    # Check manifest exists
    if [[ ! -f "$BACKUP_MANIFEST" ]]; then
        warn "Backup manifest not found: $BACKUP_MANIFEST"
        return 1
    fi

    # Check rollback script exists and is executable
    if [[ ! -x "$BACKUP_DIR/rollback.sh" ]]; then
        warn "Rollback script not found or not executable: $BACKUP_DIR/rollback.sh"
        return 1
    fi

    # Verify manifest entries exist
    local missing_count=0
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        case "$path" in \#*) continue;; esac

        local rel="${path#"$HOME/"}"
        local backup_file="$BACKUP_DIR/$rel"

        if [[ ! -e "$backup_file" ]]; then
            warn "Backup file missing: $backup_file"
            ((missing_count++))
        fi
    done < "$BACKUP_MANIFEST"

    if [[ "$missing_count" -gt 0 ]]; then
        warn "Backup verification failed: $missing_count files missing"
        return 1
    fi

    say "Backup verification completed successfully"
    return 0
}

# Function: rollback
# Purpose: Restore from backup
# Args: None
# Returns: 0 if successful, 1 if failed
rollback() {
    info "Rolling back from backup for $MODULE_NAME"

    if [[ -z "${BACKUP_DIR:-}" ]] || [[ ! -d "$BACKUP_DIR" ]]; then
        warn "No backup directory available for rollback"
        return 1
    fi

    local rollback_script="$BACKUP_DIR/rollback.sh"
    if [[ ! -x "$rollback_script" ]]; then
        warn "Rollback script not found or not executable: $rollback_script"
        return 1
    fi

    info "Executing rollback script: $rollback_script"
    if "$rollback_script"; then
        say "Rollback completed successfully"
        return 0
    else
        warn "Rollback script failed"
        return 1
    fi
}

# Internal function: _setup_backup_environment
# Purpose: Set up backup environment variables
_setup_backup_environment() {
    BACKUP_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
    BACKUP_DIR="$HOME/dotfiles-backup-$BACKUP_TIMESTAMP"
    BACKUP_MANIFEST="$BACKUP_DIR/.manifest"

    # Export for use by other modules and rollback
    export BACKUP_DIR BACKUP_MANIFEST BACKUP_TIMESTAMP
}

# Internal function: _cleanup_old_backups
# Purpose: Clean up old backup directories (keep latest 5)
_cleanup_old_backups() {
    info "Cleaning up old backups (keeping latest 5)"

    # Find and remove old backups
    # shellcheck disable=SC2012
    ls -dt "$HOME"/dotfiles-backup-* 2>/dev/null | tail -n +6 | while read -r old_backup; do
        if [[ -d "$old_backup" ]]; then
            rm -rf "$old_backup"
            info "Removed old backup: $(basename "$old_backup")"
        fi
    done || true
}

# Internal function: _initialize_backup_manifest
# Purpose: Initialize backup manifest file
_initialize_backup_manifest() {
    info "Initializing backup manifest"

    cat > "$BACKUP_MANIFEST" <<EOF
# Backup manifest - $BACKUP_TIMESTAMP
# Generated by $MODULE_NAME module
# Each line contains the full path of a backed up file
EOF
}

# Internal function: _backup_dotfiles
# Purpose: Backup existing dotfiles and configurations
_backup_dotfiles() {
    info "Backing up existing dotfiles and configurations"

    # List of files/directories to backup
    local backup_targets=(
        "$HOME/.bashrc"
        "$HOME/.profile"
        "$HOME/.bashrc.d"
        "${XDG_CONFIG_HOME:-$HOME/.config}/secrets.env"
        "$HOME/.gitignore_global"
        "${CHEZMOI_CFG:-$HOME/.config/chezmoi/chezmoi.toml}"
        "$HOME/.ssh/config"
        "$HOME/.gitconfig"
        "$HOME/.vimrc"
        "$HOME/.tmux.conf"
        "${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"
    )

    local backed_up_count=0
    local target

    for target in "${backup_targets[@]}"; do
        if [[ -e "$target" ]]; then
            _backup_single_item "$target"
            echo "$target" >> "$BACKUP_MANIFEST"
            ((backed_up_count++))

            if [[ "${VERBOSE:-0}" -eq 1 ]]; then
                info "  backed up: $target"
            fi
        fi
    done

    info "Backed up $backed_up_count items"
}

# Internal function: _backup_single_item
# Purpose: Backup a single file or directory
# Args: $1 - Path to backup
_backup_single_item() {
    local source_path="$1"
    local relative_path="${source_path#"$HOME/"}"
    local backup_path="$BACKUP_DIR/$relative_path"
    local backup_parent="$(dirname "$backup_path")"

    # Create parent directory in backup
    mkdir -p "$backup_parent"

    # Copy with attributes preserved
    if cp -a "$source_path" "$backup_path" 2>/dev/null; then
        return 0
    else
        warn "Failed to backup: $source_path"
        return 1
    fi
}

# Internal function: _create_rollback_script
# Purpose: Create executable rollback script
_create_rollback_script() {
    info "Creating rollback script"

    local rollback_script="$BACKUP_DIR/rollback.sh"

    cat > "$rollback_script" <<'ROLLBACK_EOF'
#!/usr/bin/env bash
# Rollback script - automatically generated
set -euo pipefail

# Color codes
C_G="\033[1;32m"; C_Y="\033[1;33m"; C_R="\033[1;31m"; C_N="\033[0m"
say(){ printf "${C_G}[+] %s${C_N}\n" "$*"; }
warn(){ printf "${C_Y}[!] %s${C_N}\n" "$*"; }
die(){ printf "${C_R}[✘] %s${C_N}\n" "$*" >&2; exit 1; }

BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$BACKUP_DIR/.manifest"

echo "[rollback] Restoring from $BACKUP_DIR"

if [[ ! -f "$MANIFEST" ]]; then
    die "No manifest found: $MANIFEST"
fi

restored_count=0
failed_count=0

while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    case "$path" in \#*) continue;; esac

    rel="${path#"$HOME/"}"
    src="$BACKUP_DIR/$rel"
    dst="$path"

    if [[ -e "$src" ]]; then
        # Create parent directory
        mkdir -p "$(dirname "$dst")"

        # Restore file/directory
        if cp -a "$src" "$dst" 2>/dev/null; then
            echo "  restored: $dst"
            ((restored_count++))
        else
            warn "  failed to restore: $dst"
            ((failed_count++))
        fi
    else
        warn "  backup file not found: $src"
        ((failed_count++))
    fi
done < "$MANIFEST"

say "Rollback completed: $restored_count restored, $failed_count failed"

if [[ "$failed_count" -gt 0 ]]; then
    warn "Some files failed to restore. Manual intervention may be required."
    exit 1
fi

echo
echo "Rollback successful. Run 'exec bash -l' to reload shell."
ROLLBACK_EOF

    chmod +x "$rollback_script"
    info "Rollback script created: $rollback_script"
}

# Internal function: _export_backup_info
# Purpose: Export backup information for use by other modules
_export_backup_info() {
    # Create backup info file for other modules
    local backup_info="$BACKUP_DIR/.backup_info"

    cat > "$backup_info" <<EOF
BACKUP_TIMESTAMP=$BACKUP_TIMESTAMP
BACKUP_DIR=$BACKUP_DIR
BACKUP_MANIFEST=$BACKUP_MANIFEST
MODULE_NAME=$MODULE_NAME
MODULE_VERSION=$MODULE_VERSION
CREATED_BY_USER=$(whoami)
CREATED_ON_HOST=$(hostname)
CREATED_AT=$(date -Iseconds)
EOF

    # Export environment variables for current session
    export BACKUP_DIR BACKUP_MANIFEST BACKUP_TIMESTAMP

    # Also create a symlink to latest backup
    local latest_link="$HOME/dotfiles-backup-latest"
    rm -f "$latest_link" 2>/dev/null || true
    ln -sf "$BACKUP_DIR" "$latest_link" 2>/dev/null || true
}

# Module execution guard
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    validate && execute && verify
fi