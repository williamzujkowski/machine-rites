#!/usr/bin/env bash
# lib/atomic.sh - Atomic file operations for machine-rites
#
# Provides safe file operations that are atomic and transactional
# Prevents partial writes and corruption during script interruption
#
# Functions:
#   - write_atomic()     : Atomic file write with temp file
#   - backup_file()      : Create timestamped backup
#   - restore_backup()   : Restore from backup
#   - mktemp_secure()    : Create secure temporary file
#   - atomic_append()    : Atomic append to file
#   - atomic_replace()   : Atomic find-and-replace in file
#
# Dependencies: None (pure bash)
# Idempotent: Yes
# Self-contained: Yes

set -euo pipefail

# Source guard to prevent multiple loading
if [[ -n "${__LIB_ATOMIC_LOADED:-}" ]]; then
    return 0
fi

# Load common functions if available
if [[ -f "${BASH_SOURCE[0]%/*}/common.sh" ]]; then
    # shellcheck source=./common.sh
    source "${BASH_SOURCE[0]%/*}/common.sh"
fi

# Function: write_atomic
# Purpose: Write content to file atomically using temporary file
# Args: $1 - Target file path, stdin - content to write
# Returns: 0 on success, 1 on failure
# Example: echo "content" | write_atomic "/etc/config"
write_atomic() {
    local target="$1"
    local temp_file
    local target_dir

    # Validate input
    [[ -n "$target" ]] || {
        [[ -n "${warn:-}" ]] && warn "write_atomic: target path required"
        return 1
    }

    # Create target directory if needed
    target_dir="$(dirname "$target")"
    if [[ ! -d "$target_dir" ]]; then
        mkdir -p "$target_dir" || {
            [[ -n "${warn:-}" ]] && warn "write_atomic: cannot create directory $target_dir"
            return 1
        }
    fi

    # Create secure temporary file in same directory as target
    temp_file="$(mktemp "${target}.XXXXXX")" || {
        [[ -n "${warn:-}" ]] && warn "write_atomic: cannot create temporary file"
        return 1
    }

    # Set restrictive permissions on temp file
    chmod 0600 "$temp_file" || {
        rm -f "$temp_file"
        [[ -n "${warn:-}" ]] && warn "write_atomic: cannot set permissions on temporary file"
        return 1
    }

    # Write content to temporary file
    if ! cat > "$temp_file"; then
        rm -f "$temp_file"
        [[ -n "${warn:-}" ]] && warn "write_atomic: failed to write to temporary file"
        return 1
    fi

    # Atomically move temp file to target
    if ! mv "$temp_file" "$target"; then
        rm -f "$temp_file"
        [[ -n "${warn:-}" ]] && warn "write_atomic: failed to move temporary file to target"
        return 1
    fi

    # Set final permissions (readable by user, group)
    chmod 0644 "$target" 2>/dev/null || true

    return 0
}

# Function: backup_file
# Purpose: Create timestamped backup of file
# Args: $1 - File to backup, $2 - Backup directory (optional)
# Returns: 0 on success, 1 on failure
# Example: backup_file "/etc/config" "/backups"
backup_file() {
    local source_file="$1"
    local backup_dir="${2:-$(dirname "$source_file")/backups}"
    local timestamp
    local backup_path

    # Validate input
    [[ -n "$source_file" ]] || {
        [[ -n "${warn:-}" ]] && warn "backup_file: source file required"
        return 1
    }

    [[ -f "$source_file" ]] || {
        [[ -n "${warn:-}" ]] && warn "backup_file: source file does not exist: $source_file"
        return 1
    }

    # Create backup directory
    mkdir -p "$backup_dir" || {
        [[ -n "${warn:-}" ]] && warn "backup_file: cannot create backup directory: $backup_dir"
        return 1
    }

    # Generate timestamp and backup path
    timestamp="$(date +%Y%m%d-%H%M%S)"
    backup_path="$backup_dir/$(basename "$source_file").$timestamp"

    # Create backup
    if cp -a "$source_file" "$backup_path"; then
        [[ -n "${info:-}" ]] && info "Created backup: $backup_path"
        echo "$backup_path"  # Return backup path for caller
        return 0
    else
        [[ -n "${warn:-}" ]] && warn "backup_file: failed to create backup"
        return 1
    fi
}

# Function: restore_backup
# Purpose: Restore file from most recent backup
# Args: $1 - Original file path, $2 - Backup directory (optional)
# Returns: 0 on success, 1 on failure
# Example: restore_backup "/etc/config" "/backups"
restore_backup() {
    local target_file="$1"
    local backup_dir="${2:-$(dirname "$target_file")/backups}"
    local backup_pattern
    local latest_backup

    # Validate input
    [[ -n "$target_file" ]] || {
        [[ -n "${warn:-}" ]] && warn "restore_backup: target file required"
        return 1
    }

    [[ -d "$backup_dir" ]] || {
        [[ -n "${warn:-}" ]] && warn "restore_backup: backup directory does not exist: $backup_dir"
        return 1
    }

    # Find most recent backup
    backup_pattern="$backup_dir/$(basename "$target_file").*"
    latest_backup="$(ls -t $backup_pattern 2>/dev/null | head -1)" || {
        [[ -n "${warn:-}" ]] && warn "restore_backup: no backups found for $(basename "$target_file")"
        return 1
    }

    # Restore from backup
    if cp -a "$latest_backup" "$target_file"; then
        [[ -n "${info:-}" ]] && info "Restored from backup: $latest_backup"
        return 0
    else
        [[ -n "${warn:-}" ]] && warn "restore_backup: failed to restore from $latest_backup"
        return 1
    fi
}

# Function: mktemp_secure
# Purpose: Create secure temporary file with restrictive permissions
# Args: $1 - Template (optional, defaults to tmp.XXXXXX)
# Returns: 0 on success, prints temp file path
# Example: temp_file="$(mktemp_secure)"
mktemp_secure() {
    local template="${1:-tmp.XXXXXX}"
    local temp_file

    # Create temporary file
    temp_file="$(mktemp "$template")" || {
        [[ -n "${warn:-}" ]] && warn "mktemp_secure: failed to create temporary file"
        return 1
    }

    # Set restrictive permissions (owner read/write only)
    chmod 0600 "$temp_file" || {
        rm -f "$temp_file"
        [[ -n "${warn:-}" ]] && warn "mktemp_secure: failed to set permissions"
        return 1
    }

    echo "$temp_file"
    return 0
}

# Function: atomic_append
# Purpose: Atomically append content to file
# Args: $1 - Target file, stdin - content to append
# Returns: 0 on success, 1 on failure
# Example: echo "new line" | atomic_append "/etc/config"
atomic_append() {
    local target="$1"
    local temp_file

    # Validate input
    [[ -n "$target" ]] || {
        [[ -n "${warn:-}" ]] && warn "atomic_append: target file required"
        return 1
    }

    # Create temporary file
    temp_file="$(mktemp_secure "${target}.append.XXXXXX")" || return 1

    # Copy existing content if file exists
    if [[ -f "$target" ]]; then
        cat "$target" > "$temp_file" || {
            rm -f "$temp_file"
            [[ -n "${warn:-}" ]] && warn "atomic_append: failed to copy existing content"
            return 1
        }
    fi

    # Append new content
    if ! cat >> "$temp_file"; then
        rm -f "$temp_file"
        [[ -n "${warn:-}" ]] && warn "atomic_append: failed to append content"
        return 1
    fi

    # Atomically replace target
    if mv "$temp_file" "$target"; then
        chmod 0644 "$target" 2>/dev/null || true
        return 0
    else
        rm -f "$temp_file"
        [[ -n "${warn:-}" ]] && warn "atomic_append: failed to replace target file"
        return 1
    fi
}

# Function: atomic_replace
# Purpose: Atomically perform find-and-replace in file
# Args: $1 - Target file, $2 - search pattern, $3 - replacement
# Returns: 0 on success, 1 on failure
# Example: atomic_replace "/etc/config" "old_value" "new_value"
atomic_replace() {
    local target="$1"
    local search="$2"
    local replace="$3"
    local temp_file

    # Validate input
    [[ -n "$target" && -n "$search" && -n "$replace" ]] || {
        [[ -n "${warn:-}" ]] && warn "atomic_replace: target, search, and replace required"
        return 1
    }

    [[ -f "$target" ]] || {
        [[ -n "${warn:-}" ]] && warn "atomic_replace: target file does not exist: $target"
        return 1
    }

    # Create temporary file
    temp_file="$(mktemp_secure "${target}.replace.XXXXXX")" || return 1

    # Perform replacement using sed
    if sed "s/$search/$replace/g" "$target" > "$temp_file"; then
        # Atomically replace target
        if mv "$temp_file" "$target"; then
            chmod 0644 "$target" 2>/dev/null || true
            return 0
        else
            rm -f "$temp_file"
            [[ -n "${warn:-}" ]] && warn "atomic_replace: failed to replace target file"
            return 1
        fi
    else
        rm -f "$temp_file"
        [[ -n "${warn:-}" ]] && warn "atomic_replace: sed replacement failed"
        return 1
    fi
}

# Function: cleanup_temp_files
# Purpose: Clean up temporary files matching pattern
# Args: $1 - Directory to clean, $2 - Pattern (optional)
# Returns: 0 on success
# Example: cleanup_temp_files "/tmp" "*.tmp"
cleanup_temp_files() {
    local cleanup_dir="${1:-/tmp}"
    local pattern="${2:-*.tmp}"
    local count=0

    [[ -d "$cleanup_dir" ]] || return 0

    # Clean up files older than 1 hour
    while IFS= read -r -d '' file; do
        rm -f "$file" && ((count++))
    done < <(find "$cleanup_dir" -name "$pattern" -type f -mtime +0 -print0 2>/dev/null)

    [[ $count -gt 0 ]] && [[ -n "${info:-}" ]] && info "Cleaned up $count temporary files"
    return 0
}

# Library metadata
# shellcheck disable=SC2034  # Library version for compatibility checking
readonly LIB_ATOMIC_VERSION="1.0.0"
# shellcheck disable=SC2034  # Library guard to prevent multiple sourcing
readonly LIB_ATOMIC_LOADED=1
readonly __LIB_ATOMIC_LOADED=1