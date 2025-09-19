#!/usr/bin/env bash
# bootstrap/modules/30-chezmoi.sh - Chezmoi setup and configuration module
#
# Description: Sets up chezmoi dotfiles management system
# Version: 1.0.0
# Dependencies: lib/common.sh, lib/atomic.sh, 00-prereqs.sh, 20-system-packages.sh
# Idempotent: Yes (updates existing configuration)
# Rollback: Yes (removes chezmoi configuration)
#
# This module sets up chezmoi for dotfiles management, including repository
# cloning, configuration creation, and initial application of dotfiles.

set -euo pipefail

# Module metadata
readonly MODULE_NAME="30-chezmoi"
readonly MODULE_VERSION="1.0.0"
readonly MODULE_DESCRIPTION="Chezmoi setup and configuration"

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"
# shellcheck source=../../lib/atomic.sh
source "$SCRIPT_DIR/../../lib/atomic.sh" 2>/dev/null || true

# Module state
CHEZMOI_CONFIGURED=0
REPO_CLONED=0
CONFIG_CREATED=0

# Function: validate
# Purpose: Validate chezmoi setup prerequisites
# Args: None
# Returns: 0 if valid, 1 if not
validate() {
    info "Validating chezmoi prerequisites for $MODULE_NAME"

    # Check chezmoi is available
    if ! command -v chezmoi >/dev/null 2>&1; then
        die "chezmoi not available (should be installed by 20-system-packages)"
    fi

    # Check required variables are set
    local required_vars=(
        "REPO_DIR"
        "REPO_URL"
        "CHEZMOI_CFG"
        "CHEZMOI_SRC"
        "GIT_NAME"
        "GIT_EMAIL"
    )

    local var
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            die "Required variable not set: $var (should be set by 00-prereqs)"
        fi
    done

    # Check git is available
    if ! command -v git >/dev/null 2>&1; then
        die "git not available (should be installed by 20-system-packages)"
    fi

    return 0
}

# Function: execute
# Purpose: Execute chezmoi setup
# Args: None
# Returns: 0 if successful, 1 if failed
execute() {
    info "Executing chezmoi setup for $MODULE_NAME"

    # Clone or update repository
    _setup_repository

    # Create chezmoi configuration
    _create_chezmoi_config

    # Set up chezmoi source directory structure
    _setup_chezmoi_source

    # Create .chezmoiignore
    _create_chezmoiignore

    # Create README for chezmoi source
    _create_chezmoi_readme

    # Import existing dotfiles into chezmoi
    _import_existing_dotfiles

    # Apply chezmoi configuration
    _apply_chezmoi_config

    # Set up global gitignore
    _setup_global_gitignore

    say "Chezmoi setup completed"
    return 0
}

# Function: verify
# Purpose: Verify chezmoi was set up correctly
# Args: None
# Returns: 0 if verified, 1 if not
verify() {
    info "Verifying chezmoi setup for $MODULE_NAME"

    # Check repository exists and is a git repo
    if [[ ! -d "$REPO_DIR/.git" ]]; then
        warn "Repository not found or not a git repository: $REPO_DIR"
        return 1
    fi

    # Check chezmoi config exists and is valid
    if [[ ! -f "$CHEZMOI_CFG" ]]; then
        warn "Chezmoi config not found: $CHEZMOI_CFG"
        return 1
    fi

    # Verify chezmoi can read the config
    if ! chezmoi doctor >/dev/null 2>&1; then
        warn "Chezmoi configuration validation failed"
        return 1
    fi

    # Check chezmoi source directory exists
    if [[ ! -d "$CHEZMOI_SRC" ]]; then
        warn "Chezmoi source directory not found: $CHEZMOI_SRC"
        return 1
    fi

    # Verify chezmoi status
    if ! chezmoi status >/dev/null 2>&1; then
        warn "Chezmoi status check failed"
        return 1
    fi

    # Check that sourceDir is correctly set
    local configured_source
    configured_source=$(chezmoi execute-template '{{ .chezmoi.sourceDir }}' 2>/dev/null || echo "")

    if [[ "$configured_source" != "$CHEZMOI_SRC" ]]; then
        warn "Chezmoi sourceDir mismatch: expected $CHEZMOI_SRC, got $configured_source"
        return 1
    fi

    say "Chezmoi verification completed successfully"
    return 0
}

# Function: rollback
# Purpose: Remove chezmoi configuration and revert changes
# Args: None
# Returns: 0 if successful, 1 if failed
rollback() {
    info "Rolling back chezmoi configuration for $MODULE_NAME"

    # Remove chezmoi config file
    if [[ -f "$CHEZMOI_CFG" ]]; then
        rm -f "$CHEZMOI_CFG"
        info "Removed chezmoi config: $CHEZMOI_CFG"
    fi

    # Remove chezmoi config directory if empty
    local config_dir
    config_dir=$(dirname "$CHEZMOI_CFG")
    if [[ -d "$config_dir" ]] && [[ -z "$(ls -A "$config_dir" 2>/dev/null)" ]]; then
        rmdir "$config_dir" 2>/dev/null || true
        info "Removed empty chezmoi config directory: $config_dir"
    fi

    # Note: We don't remove the repository or source files as they may contain
    # user data. Manual cleanup may be required.

    warn "Repository and source files not removed (manual cleanup may be required)"
    warn "Repository: $REPO_DIR"
    warn "Chezmoi source: $CHEZMOI_SRC"

    say "Chezmoi rollback completed"
    return 0
}

# Internal function: _setup_repository
# Purpose: Clone or update the dotfiles repository
_setup_repository() {
    info "Setting up dotfiles repository"

    if [[ ! -d "$REPO_DIR/.git" ]]; then
        info "Cloning repository: $REPO_URL -> $REPO_DIR"

        # Create parent directory
        mkdir -p "$(dirname "$REPO_DIR")"

        if git clone "$REPO_URL" "$REPO_DIR"; then
            say "Repository cloned successfully"
            REPO_CLONED=1
        else
            die "Failed to clone repository: $REPO_URL"
        fi
    else
        info "Updating existing repository: $REPO_DIR"

        (
            cd "$REPO_DIR"
            if git fetch origin && git pull --ff-only 2>/dev/null; then
                say "Repository updated successfully"
            else
                warn "Could not update repository (may have local changes)"
            fi
        ) || warn "Repository update failed"
    fi
}

# Internal function: _create_chezmoi_config
# Purpose: Create chezmoi configuration file
_create_chezmoi_config() {
    info "Creating chezmoi configuration"

    # Create config directory
    mkdir -p "$(dirname "$CHEZMOI_CFG")"

    # Check if config already exists and has sourceDir
    if [[ -f "$CHEZMOI_CFG" ]] && grep -q 'sourceDir' "$CHEZMOI_CFG"; then
        info "Chezmoi config already exists, updating if necessary"

        # Ensure sourceDir is set correctly
        if ! grep -q "sourceDir = \"$CHEZMOI_SRC\"" "$CHEZMOI_CFG"; then
            info "Updating sourceDir in existing config"
            # Remove existing sourceDir line and add new one
            grep -v '^sourceDir' "$CHEZMOI_CFG" > "$CHEZMOI_CFG.tmp" || true
            echo "sourceDir = \"$CHEZMOI_SRC\"" >> "$CHEZMOI_CFG.tmp"
            mv "$CHEZMOI_CFG.tmp" "$CHEZMOI_CFG"
        fi
        return 0
    fi

    info "Creating new chezmoi configuration"

    # Use atomic write to create config
    write_atomic "$CHEZMOI_CFG" <<EOF
sourceDir = "$CHEZMOI_SRC"

[data]
  name  = "$GIT_NAME"
  email = "$GIT_EMAIL"

[diff]
  command = "diff"
  args    = ["--color=auto"]

[merge]
  command = "${EDITOR:-vi}"

[data.machine]
  hostname = "$(hostname)"
  os       = "$(lsb_release -is 2>/dev/null || echo 'Unknown')"
  version  = "$(lsb_release -rs 2>/dev/null || echo 'Unknown')"
EOF

    CONFIG_CREATED=1
    say "Chezmoi configuration created: $CHEZMOI_CFG"
}

# Internal function: _setup_chezmoi_source
# Purpose: Set up chezmoi source directory structure
_setup_chezmoi_source() {
    info "Setting up chezmoi source directory"

    # Create source directory
    mkdir -p "$CHEZMOI_SRC"

    # Initialize as git repository if needed
    if [[ ! -d "$CHEZMOI_SRC/.git" ]]; then
        (
            cd "$CHEZMOI_SRC"
            git init
            git config user.name "$GIT_NAME"
            git config user.email "$GIT_EMAIL"
        )
        info "Initialized git repository in chezmoi source"
    fi
}

# Internal function: _create_chezmoiignore
# Purpose: Create .chezmoiignore file
_create_chezmoiignore() {
    info "Creating .chezmoiignore file"

    local chezmoiignore="$CHEZMOI_SRC/.chezmoiignore"

    if [[ ! -f "$chezmoiignore" ]]; then
        write_atomic "$chezmoiignore" <<'IGNORE'
.bashrc.d/99-local.sh
README.md
.git
.gitignore
.DS_Store
*.tmp
*.swp
*~
IGNORE
        info "Created .chezmoiignore file"
    else
        info ".chezmoiignore file already exists"
    fi
}

# Internal function: _create_chezmoi_readme
# Purpose: Create README.md in chezmoi source directory
_create_chezmoi_readme() {
    local readme="$CHEZMOI_SRC/README.md"

    if [[ -f "$readme" ]]; then
        info "README.md already exists in chezmoi source"
        return 0
    fi

    info "Creating README.md in chezmoi source"

    write_atomic "$readme" <<'README'
# machine-rites — chezmoi source

This directory contains the chezmoi source for dotfiles management.

## Quick Start

```bash
# Apply changes
chezmoi apply

# Check what would change
chezmoi diff

# Update from repo
git pull && chezmoi apply

# Add new dotfile
chezmoi add ~/.newfile

# Edit existing dotfile
chezmoi edit ~/.bashrc
```

## Structure

- `dot_*` files become `.` files in home directory
- `private_*` files have restricted permissions
- `executable_*` files become executable
- `*.tmpl` files are templates processed by chezmoi

## More Information

- [Chezmoi documentation](https://www.chezmoi.io/)
- [Template syntax](https://www.chezmoi.io/user-guide/templating/)
README
}

# Internal function: _import_existing_dotfiles
# Purpose: Import existing dotfiles into chezmoi
_import_existing_dotfiles() {
    info "Importing existing dotfiles into chezmoi"

    # List of files to import
    local import_files=(
        "$HOME/.bashrc"
        "$HOME/.profile"
    )

    # Import directories
    local import_dirs=(
        "$HOME/.bashrc.d"
    )

    # Import individual files
    local file
    for file in "${import_files[@]}"; do
        if [[ -f "$file" ]]; then
            if chezmoi -S "$CHEZMOI_SRC" add "$file" 2>/dev/null; then
                info "Imported file: $file"
            else
                warn "Failed to import file: $file"
            fi
        fi
    done

    # Import directories
    local dir
    for dir in "${import_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            if chezmoi -S "$CHEZMOI_SRC" add "$dir" 2>/dev/null; then
                info "Imported directory: $dir"
            else
                warn "Failed to import directory: $dir"
            fi
        fi
    done
}

# Internal function: _apply_chezmoi_config
# Purpose: Apply chezmoi configuration
_apply_chezmoi_config() {
    info "Applying chezmoi configuration"

    if chezmoi -S "$CHEZMOI_SRC" apply; then
        say "Chezmoi configuration applied successfully"
        CHEZMOI_CONFIGURED=1
    else
        warn "Chezmoi apply failed - some files may not have been updated"
        # Don't fail completely as this might be due to permission issues
        # or conflicting files that need manual resolution
    fi
}

# Internal function: _setup_global_gitignore
# Purpose: Set up global gitignore for sensitive files
_setup_global_gitignore() {
    info "Setting up global gitignore"

    local gitignore_global="$HOME/.gitignore_global"

    # Create or update global gitignore
    touch "$gitignore_global"

    local patterns=(
        ".config/secrets.env"
        ".bashrc.d/99-local.sh"
        "*.swp"
        ".DS_Store"
        "*.tmp"
        "*~"
        ".vscode/settings.json"
        ".idea/"
    )

    local pattern
    for pattern in "${patterns[@]}"; do
        if ! grep -qxF "$pattern" "$gitignore_global" 2>/dev/null; then
            echo "$pattern" >> "$gitignore_global"
        fi
    done

    # Configure git to use global gitignore
    if git config --global core.excludesFile "$gitignore_global" 2>/dev/null; then
        info "Global gitignore configured: $gitignore_global"
    else
        warn "Failed to configure global gitignore"
    fi
}

# Module execution guard
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    validate && execute && verify
fi