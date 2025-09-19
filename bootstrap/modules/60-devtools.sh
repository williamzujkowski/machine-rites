#!/usr/bin/env bash
# bootstrap/modules/60-devtools.sh - Optional developer tools module
#
# Description: Installs optional development tools and configurations
# Version: 1.0.0
# Dependencies: lib/common.sh, 20-system-packages.sh, 30-chezmoi.sh
# Idempotent: Yes (checks existing tools)
# Rollback: Partial (can remove some installed tools)
#
# This module installs optional development tools, sets up pre-commit hooks,
# creates helper scripts, and configures CI/CD workflows.

set -euo pipefail

# Module metadata
readonly MODULE_NAME="60-devtools"
readonly MODULE_VERSION="1.0.0"
readonly MODULE_DESCRIPTION="Optional developer tools"

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"
# shellcheck source=../../lib/atomic.sh
source "$SCRIPT_DIR/../../lib/atomic.sh" 2>/dev/null || true

# Module state
GITLEAKS_CONFIG_CREATED=0
PRECOMMIT_INSTALLED=0
HELPER_SCRIPTS_CREATED=0
CI_WORKFLOW_CREATED=0
STARSHIP_CONFIG_CREATED=0

# Function: validate
# Purpose: Validate developer tools prerequisites
# Args: None
# Returns: 0 if valid, 1 if not
validate() {
    info "Validating developer tools prerequisites for $MODULE_NAME"

    # Check if this module should be skipped
    if [[ "${SKIP_DEVTOOLS:-0}" -eq 1 ]]; then
        info "Developer tools installation skipped due to SKIP_DEVTOOLS=1"
        return 0
    fi

    # Check required variables
    if [[ -z "${REPO_DIR:-}" ]]; then
        die "REPO_DIR not set (should be set by 00-prereqs)"
    fi

    if [[ -z "${XDG_CONFIG_HOME:-}" ]]; then
        die "XDG_CONFIG_HOME not set (should be set by 00-prereqs)"
    fi

    # Check repository exists
    if [[ ! -d "$REPO_DIR" ]]; then
        warn "Repository directory not found: $REPO_DIR"
        warn "Some developer tools setup may fail"
    fi

    return 0
}

# Function: execute
# Purpose: Execute developer tools setup
# Args: None
# Returns: 0 if successful, 1 if failed
execute() {
    info "Executing developer tools setup for $MODULE_NAME"

    # Skip if disabled
    if [[ "${SKIP_DEVTOOLS:-0}" -eq 1 ]]; then
        info "Developer tools setup skipped"
        return 0
    fi

    # Set up Starship configuration
    _setup_starship_config

    # Set up gitleaks configuration
    _setup_gitleaks_config

    # Set up pre-commit hooks
    _setup_precommit_hooks

    # Create helper scripts
    _create_helper_scripts

    # Set up CI/CD workflow
    _setup_ci_workflow

    # Set up tool-specific completions
    _setup_tool_completions

    say "Developer tools setup completed"
    return 0
}

# Function: verify
# Purpose: Verify developer tools were set up correctly
# Args: None
# Returns: 0 if verified, 1 if not
verify() {
    info "Verifying developer tools setup for $MODULE_NAME"

    # Skip verification if disabled
    if [[ "${SKIP_DEVTOOLS:-0}" -eq 1 ]]; then
        info "Developer tools verification skipped"
        return 0
    fi

    local verification_failed=0

    # Check gitleaks config if repository exists
    if [[ -d "$REPO_DIR" ]] && [[ ! -f "$REPO_DIR/.gitleaks.toml" ]]; then
        warn "Gitleaks configuration not found: $REPO_DIR/.gitleaks.toml"
        ((verification_failed++))
    fi

    # Check pre-commit config if repository exists
    if [[ -d "$REPO_DIR" ]] && [[ ! -f "$REPO_DIR/.pre-commit-config.yaml" ]]; then
        warn "Pre-commit configuration not found: $REPO_DIR/.pre-commit-config.yaml"
        ((verification_failed++))
    fi

    # Check helper scripts
    local helper_scripts=(
        "$REPO_DIR/tools/doctor.sh"
        "$REPO_DIR/tools/update.sh"
        "$REPO_DIR/tools/backup-pass.sh"
    )

    local script
    for script in "${helper_scripts[@]}"; do
        if [[ -d "$REPO_DIR" ]] && [[ ! -x "$script" ]]; then
            warn "Helper script not found or not executable: $script"
            ((verification_failed++))
        fi
    done

    # Check CI workflow
    if [[ -d "$REPO_DIR" ]] && [[ ! -f "$REPO_DIR/.github/workflows/ci.yml" ]]; then
        warn "CI workflow not found: $REPO_DIR/.github/workflows/ci.yml"
        ((verification_failed++))
    fi

    if [[ "$verification_failed" -gt 0 ]]; then
        warn "Developer tools verification failed: $verification_failed issues found"
        return 1
    fi

    say "Developer tools verification completed successfully"
    return 0
}

# Function: rollback
# Purpose: Remove developer tools setup
# Args: None
# Returns: 0 if successful, 1 if failed
rollback() {
    info "Rolling back developer tools setup for $MODULE_NAME"

    # Remove created files
    local files_to_remove=(
        "$XDG_CONFIG_HOME/starship.toml"
        "$REPO_DIR/.gitleaks.toml"
        "$REPO_DIR/.pre-commit-config.yaml"
        "$REPO_DIR/tools/doctor.sh"
        "$REPO_DIR/tools/update.sh"
        "$REPO_DIR/tools/backup-pass.sh"
        "$REPO_DIR/.github/workflows/ci.yml"
    )

    local file
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            info "Removed: $file"
        fi
    done

    # Remove empty directories
    if [[ -d "$REPO_DIR/tools" ]] && [[ -z "$(ls -A "$REPO_DIR/tools" 2>/dev/null)" ]]; then
        rmdir "$REPO_DIR/tools" 2>/dev/null || true
    fi

    if [[ -d "$REPO_DIR/.github/workflows" ]] && [[ -z "$(ls -A "$REPO_DIR/.github/workflows" 2>/dev/null)" ]]; then
        rmdir "$REPO_DIR/.github/workflows" 2>/dev/null || true
    fi

    if [[ -d "$REPO_DIR/.github" ]] && [[ -z "$(ls -A "$REPO_DIR/.github" 2>/dev/null)" ]]; then
        rmdir "$REPO_DIR/.github" 2>/dev/null || true
    fi

    say "Developer tools rollback completed"
    return 0
}

# Internal function: _setup_starship_config
# Purpose: Set up Starship prompt configuration
_setup_starship_config() {
    local starship_config="$XDG_CONFIG_HOME/starship.toml"

    if [[ -f "$starship_config" ]]; then
        info "Starship configuration already exists: $starship_config"

        # Fix common issue with uppercase keys
        if grep -q '^STASHED' "$starship_config" 2>/dev/null; then
            sed -i 's/^STASHED/stashed/g' "$starship_config"
            info "Fixed uppercase STASHED key in starship.toml"
        fi
        return 0
    fi

    info "Creating Starship configuration"

    write_atomic "$starship_config" <<'STARSHIP'
format = "$all"
add_newline = false

[character]
success_symbol = "[➜](bold green) "
error_symbol = "[✗](bold red) "

[git_branch]
truncation_length = 32

[git_status]
conflicted = "!"
diverged = "⇕"
modified = "~"
staged = "+"
untracked = "?"
stashed = "≡"

[directory]
truncation_length = 3
truncate_to_repo = true

[python]
python_binary = ["python3", "python"]

[nodejs]
format = "via [⬢ $version](bold green) "

[rust]
format = "via [⚡ $version](red bold) "
STARSHIP

    STARSHIP_CONFIG_CREATED=1
    say "Starship configuration created: $starship_config"
}

# Internal function: _setup_gitleaks_config
# Purpose: Set up gitleaks security scanning configuration
_setup_gitleaks_config() {
    if [[ ! -d "$REPO_DIR" ]]; then
        warn "Repository directory not found, skipping gitleaks setup"
        return 0
    fi

    local gitleaks_config="$REPO_DIR/.gitleaks.toml"

    if [[ -f "$gitleaks_config" ]]; then
        info "Gitleaks configuration already exists"
        return 0
    fi

    info "Creating gitleaks configuration"

    write_atomic "$gitleaks_config" <<'GITLEAKS'
[extend]
useDefault = true

[[rules]]
id = "custom-api-key"
description = "Custom API Key Pattern"
regex = '''(?i)(api[_-]?key|apikey)['""]?\s*[:=]\s*['""]?([a-z0-9]{32,})'''

[[rules]]
id = "custom-secret-key"
description = "Custom Secret Key Pattern"
regex = '''(?i)(secret[_-]?key|secretkey)['""]?\s*[:=]\s*['""]?([a-z0-9]{32,})'''

[[rules]]
id = "custom-password"
description = "Custom Password Pattern"
regex = '''(?i)(password|passwd|pwd)['""]?\s*[:=]\s*['""]?([a-z0-9]{8,})'''

[allowlist]
paths = [
  '''vendor/''',
  '''node_modules/''',
  '''*.min.js''',
  '''*.min.css''',
]

regexes = [
  '''EXAMPLE_API_KEY''',
  '''test_password_123''',
  '''fake_secret_key''',
]
GITLEAKS

    GITLEAKS_CONFIG_CREATED=1
    say "Gitleaks configuration created: $gitleaks_config"
}

# Internal function: _setup_precommit_hooks
# Purpose: Set up pre-commit hooks
_setup_precommit_hooks() {
    if [[ ! -d "$REPO_DIR" ]]; then
        warn "Repository directory not found, skipping pre-commit setup"
        return 0
    fi

    local precommit_config="$REPO_DIR/.pre-commit-config.yaml"

    if [[ -f "$precommit_config" ]]; then
        info "Pre-commit configuration already exists"
    else
        info "Creating pre-commit configuration"

        write_atomic "$precommit_config" <<'PRECOMMIT'
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.4
    hooks:
      - id: gitleaks
        args: ["--no-banner", "--redact", "--staged"]

  - repo: https://github.com/shellcheck-py/shellcheck-py
    rev: v0.10.0.1
    hooks:
      - id: shellcheck
        args: ["--severity=warning"]
        exclude: ^(vendor/|node_modules/)

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-toml
      - id: check-json
      - id: check-merge-conflict
      - id: check-case-conflict
      - id: check-executables-have-shebangs
PRECOMMIT
    fi

    # Install pre-commit hooks
    if command -v pre-commit >/dev/null 2>&1; then
        info "Installing pre-commit hooks"
        (cd "$REPO_DIR" && pre-commit install >/dev/null 2>&1) || {
            warn "Pre-commit hook installation failed"
            return 1
        }
        PRECOMMIT_INSTALLED=1
        say "Pre-commit hooks installed successfully"
    else
        warn "pre-commit not available, hooks not installed"
    fi
}

# Internal function: _create_helper_scripts
# Purpose: Create helper scripts for maintenance
_create_helper_scripts() {
    if [[ ! -d "$REPO_DIR" ]]; then
        warn "Repository directory not found, skipping helper scripts"
        return 0
    fi

    local tools_dir="$REPO_DIR/tools"
    mkdir -p "$tools_dir"

    # Create doctor.sh script
    _create_doctor_script "$tools_dir"

    # Create update.sh script
    _create_update_script "$tools_dir"

    # Create backup-pass.sh script
    _create_backup_pass_script "$tools_dir"

    HELPER_SCRIPTS_CREATED=1
    say "Helper scripts created in: $tools_dir"
}

# Internal function: _create_doctor_script
# Purpose: Create system health check script
# Args: $1 - Tools directory
_create_doctor_script() {
    local tools_dir="$1"
    local doctor_script="$tools_dir/doctor.sh"

    write_atomic "$doctor_script" <<'DOCTOR'
#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

C_G="\033[1;32m"; C_Y="\033[1;33m"; C_R="\033[1;31m"; C_N="\033[0m"
ok(){ printf "${C_G}✓${C_N} %s\n" "$*"; }
warn(){ printf "${C_Y}⚠${C_N} %s\n" "$*"; }
fail(){ printf "${C_R}✗${C_N} %s\n" "$*"; }

echo "=== Dotfiles Health Check ==="

# System info
echo -e "\n[System]"
printf "  %-12s : " "OS"
if lsb_release -is 2>/dev/null | grep -q Ubuntu; then
  ok "Ubuntu $(lsb_release -rs 2>/dev/null)"
else
  warn "Not Ubuntu ($(lsb_release -is 2>/dev/null || echo 'Unknown'))"
fi

# Tools check
echo -e "\n[Tools]"
errors=0
for t in bash chezmoi pass gitleaks pre-commit git gpg age ssh starship; do
  printf "  %-12s : " "$t"
  if command -v "$t" >/dev/null 2>&1; then
    ver="$("$t" --version 2>/dev/null | head -1 || echo "installed")"
    ok "${ver:0:50}"
  else
    if [ "$t" = "starship" ]; then
      warn "Not installed (optional)"
    else
      fail "MISSING"
      ((errors++))
    fi
  fi
done

# GPG
echo -e "\n[GPG]"
if gpg --list-secret-keys 2>/dev/null | grep -q '^sec'; then
  keys=$(gpg --list-secret-keys --keyid-format SHORT 2>/dev/null | grep '^sec' | wc -l)
  ok "Secret keys: $keys"
else
  warn "No GPG secret keys (pass won't work)"
fi

# Pass
echo -e "\n[Pass Store]"
if pass ls >/dev/null 2>&1; then
  count=$(pass ls 2>/dev/null | grep -E -c '├──|└──' || echo "0")
  ok "Entries: $count"
else
  warn "Not initialized (run: pass init <GPG_KEY_ID>)"
fi

# SSH
echo -e "\n[SSH]"
found=0
for key in ~/.ssh/id_{rsa,ed25519,ecdsa}; do
  [[ -f "$key" ]] && { ok "Key: $(basename "$key")"; found=1; }
done
[[ "$found" -eq 0 ]] && warn "No SSH keys (run: ensure_ssh_key)"

printf "  %-12s : " "Agent"
if [[ -n "${SSH_AUTH_SOCK:-}" ]] && ssh-add -l >/dev/null 2>&1; then
  ok "Running ($(ssh-add -l 2>/dev/null | wc -l) keys)"
else
  warn "Not running or no keys"
fi

# Chezmoi
echo -e "\n[Chezmoi]"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if chezmoi status >/dev/null 2>&1; then
  changes=$(chezmoi status 2>/dev/null | wc -l)
  if [[ "$changes" -eq 0 ]]; then
    ok "Clean"
  else
    warn "$changes pending changes (run: chezmoi diff)"
  fi
else
  fail "Not configured"
fi

# Pre-commit
echo -e "\n[Pre-commit]"
if [[ -f "$REPO_DIR/.git/hooks/pre-commit" ]]; then
  ok "Hooks installed"
  echo "  Testing..."
  if (cd "$REPO_DIR" && pre-commit run --all-files >/dev/null 2>&1); then
    ok "  All checks pass"
  else
    warn "  Some checks failed"
  fi
else
  warn "Not installed (run: pre-commit install)"
fi

# Security
echo -e "\n[Security]"
if (cd "$REPO_DIR" && gitleaks detect --no-banner --exit-code 0 >/dev/null 2>&1); then
  ok "No secrets detected"
else
  fail "Secrets found! Run: gitleaks detect --verbose"
fi

# Summary
echo -e "\n[Summary]"
if [[ "$errors" -eq 0 ]]; then
  ok "All essential tools installed"
else
  fail "$errors essential tools missing"
fi

echo -e "\n=== End Health Check ==="
DOCTOR

    chmod 0755 "$doctor_script"
}

# Internal function: _create_update_script
# Purpose: Create system update script
# Args: $1 - Tools directory
_create_update_script() {
    local tools_dir="$1"
    local update_script="$tools_dir/update.sh"

    write_atomic "$update_script" <<'UPDATE'
#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

echo "=== Dotfiles Update ==="

echo "Pulling latest..."
if git pull --ff-only; then
  echo "  ✓ Updated to $(git rev-parse --short HEAD)"
else
  echo "  ⚠ Could not fast-forward"
fi

echo "Applying chezmoi..."
if chezmoi apply; then
  echo "  ✓ Applied"
else
  echo "  ✗ Failed"
fi

echo "Updating pre-commit..."
if pre-commit autoupdate >/dev/null 2>&1; then
  echo "  ✓ Updated"
else
  echo "  ⚠ Failed"
fi

echo "Running health check..."
./tools/doctor.sh

echo "=== Update Complete ==="
UPDATE

    chmod 0755 "$update_script"
}

# Internal function: _create_backup_pass_script
# Purpose: Create Pass backup script
# Args: $1 - Tools directory
_create_backup_pass_script() {
    local tools_dir="$1"
    local backup_script="$tools_dir/backup-pass.sh"

    write_atomic "$backup_script" <<'BACKUP'
#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="$REPO_DIR/backups/pass"
mkdir -p "$BACKUP_DIR"

pass_dir="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
if [[ ! -d "$pass_dir" ]]; then
  echo "Pass store not found at: $pass_dir"
  exit 1
fi

backup_file="$BACKUP_DIR/pass-$(date +%Y%m%d-%H%M%S).tar.gz.gpg"

echo "Backing up pass store..."
if tar czf - -C "$pass_dir" . | gpg --symmetric --cipher-algo AES256 --output "$backup_file"; then
  echo "  ✓ Saved: $backup_file"

  # Keep only last 5
  ls -t "$BACKUP_DIR"/*.gpg 2>/dev/null | tail -n +6 | xargs -r rm
  echo "  ✓ Cleaned old backups"
else
  echo "  ✗ Backup failed"
  exit 1
fi

echo "Restore: gpg -d $backup_file | tar xzf - -C ~/.password-store"
BACKUP

    chmod 0755 "$backup_script"
}

# Internal function: _setup_ci_workflow
# Purpose: Set up CI/CD workflow
_setup_ci_workflow() {
    if [[ ! -d "$REPO_DIR" ]]; then
        warn "Repository directory not found, skipping CI workflow setup"
        return 0
    fi

    local workflow_dir="$REPO_DIR/.github/workflows"
    local ci_workflow="$workflow_dir/ci.yml"

    if [[ -f "$ci_workflow" ]]; then
        info "CI workflow already exists"
        return 0
    fi

    info "Creating CI workflow"
    mkdir -p "$workflow_dir"

    write_atomic "$ci_workflow" <<'CI'
name: CI

on:
  push:
    branches: [ main, master ]
  pull_request:
    branches: [ main, master ]
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write

jobs:
  validate-dotfiles:
    name: Validate dotfiles
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install chezmoi
        run: |
          sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
          echo "$HOME/.local/bin" >> $GITHUB_PATH

      - name: Validate chezmoi
        run: |
          test -d ".chezmoi" || { echo "::error::.chezmoi source dir not found"; exit 1; }
          chezmoi --source ./.chezmoi apply --dry-run

      - name: ShellCheck
        uses: ludeeus/action-shellcheck@v2
        with:
          scandir: .
          check_together: "yes"
          severity: warning

      - name: Run pre-commit
        uses: pre-commit/action@v3.0.1
        with:
          extra_args: --all-files
        env:
          SKIP: no-commit-to-branch

  gitleaks:
    name: Security scan
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Gitleaks
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GITLEAKS_ENABLE_COMMENTS: true
        with:
          args: --no-banner --redact
CI

    CI_WORKFLOW_CREATED=1
    say "CI workflow created: $ci_workflow"
}

# Internal function: _setup_tool_completions
# Purpose: Set up tool-specific completions
_setup_tool_completions() {
    local completions_file="$HOME/.bashrc.d/41-completions.sh"

    if [[ -f "$completions_file" ]]; then
        info "Tool completions already configured"
        return 0
    fi

    info "Creating tool completions configuration"

    write_atomic "$completions_file" <<'COMPLETIONS'
#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1090,SC1091

# Ensure bash-completion is available (already sourced in 10-bash-completion.sh)

# git
for f in /usr/share/bash-completion/completions/git \
         /usr/share/doc/git/contrib/completion/git-completion.bash; do
  [[ -f $f ]] && . "$f" && break
done

# gh
if command -v gh >/dev/null 2>&1; then
  eval "$(gh completion -s bash 2>/dev/null)" || true
fi

# kubectl
command -v kubectl >/dev/null 2>&1 && eval "$(kubectl completion bash)" || true

# docker & compose (if distro provides them)
for f in /usr/share/bash-completion/completions/docker \
         /usr/share/bash-completion/completions/docker-compose; do
  [[ -f $f ]] && . "$f"
done

# terraform
if command -v terraform >/dev/null 2>&1; then
  terraform -install-autocomplete >/dev/null 2>&1 || true
fi

# aws
if command -v aws_completer >/dev/null 2>&1; then
  complete -C aws_completer aws
fi
COMPLETIONS
}

# Module execution guard
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    validate && execute && verify
fi