#!/usr/bin/env bash
# bootstrap/modules/40-shell-config.sh - Shell configuration module
#
# Description: Creates modular bash configuration and shell setup
# Version: 1.0.0
# Dependencies: lib/common.sh, lib/atomic.sh, 30-chezmoi.sh
# Idempotent: Yes (overwrites existing configuration)
# Rollback: Yes (restores from backup)
#
# This module creates a comprehensive modular bash configuration including
# shell settings, completions, aliases, and tool integrations.

set -euo pipefail

# Module metadata
readonly MODULE_NAME="40-shell-config"
readonly MODULE_VERSION="1.0.0"
readonly MODULE_DESCRIPTION="Shell configuration"

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"
# shellcheck source=../../lib/atomic.sh
source "$SCRIPT_DIR/../../lib/atomic.sh" 2>/dev/null || true

# Module state
SHELL_CONFIG_CREATED=0
BASHRC_D_CREATED=0

# Function: validate
# Purpose: Validate shell configuration prerequisites
# Args: None
# Returns: 0 if valid, 1 if not
validate() {
    info "Validating shell configuration prerequisites for $MODULE_NAME"

    # Check required variables are set
    local required_vars=(
        "XDG_CONFIG_HOME"
        "XDG_DATA_HOME"
        "XDG_STATE_HOME"
        "XDG_CACHE_HOME"
    )

    local var
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            die "Required variable not set: $var (should be set by 00-prereqs)"
        fi
    done

    # Check HOME is writable
    if [[ ! -w "$HOME" ]]; then
        die "HOME directory is not writable: $HOME"
    fi

    return 0
}

# Function: execute
# Purpose: Execute shell configuration setup
# Args: None
# Returns: 0 if successful, 1 if failed
execute() {
    info "Executing shell configuration setup for $MODULE_NAME"

    # Create bashrc.d directory structure
    _create_bashrc_d_structure

    # Create main bashrc
    _create_main_bashrc

    # Create shell configuration modules
    _create_hygiene_config
    _create_completion_config
    _create_secrets_config
    _create_ssh_config
    _create_tools_config
    _create_prompt_config
    _create_starship_config
    _create_aliases_config
    _create_local_config

    # Create profile
    _create_profile

    # Apply configurations via chezmoi if available
    _apply_via_chezmoi

    say "Shell configuration setup completed"
    return 0
}

# Function: verify
# Purpose: Verify shell configuration was set up correctly
# Args: None
# Returns: 0 if verified, 1 if not
verify() {
    info "Verifying shell configuration for $MODULE_NAME"

    # Check main files exist
    local required_files=(
        "$HOME/.bashrc"
        "$HOME/.profile"
        "$HOME/.bashrc.d/00-hygiene.sh"
        "$HOME/.bashrc.d/10-bash-completion.sh"
        "$HOME/.bashrc.d/30-secrets.sh"
        "$HOME/.bashrc.d/35-ssh.sh"
        "$HOME/.bashrc.d/40-tools.sh"
        "$HOME/.bashrc.d/50-prompt.sh"
        "$HOME/.bashrc.d/60-aliases.sh"
        "$HOME/.bashrc.d/99-local.sh"
    )

    local file
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            warn "Required shell config file missing: $file"
            return 1
        fi
    done

    # Test shell syntax
    local config_file
    for config_file in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bashrc.d/"*.sh; do
        if [[ -f "$config_file" ]]; then
            if ! bash -n "$config_file" 2>/dev/null; then
                warn "Syntax error in shell config: $config_file"
                return 1
            fi
        fi
    done

    # Test that bashrc sources bashrc.d modules
    if ! grep -q "\.bashrc\.d" "$HOME/.bashrc"; then
        warn "Main bashrc does not source bashrc.d modules"
        return 1
    fi

    say "Shell configuration verification completed successfully"
    return 0
}

# Function: rollback
# Purpose: Rollback shell configuration changes
# Args: None
# Returns: 0 if successful, 1 if failed
rollback() {
    info "Rolling back shell configuration for $MODULE_NAME"

    # If backup module ran, there should be a rollback script
    if [[ -n "${BACKUP_DIR:-}" ]] && [[ -x "$BACKUP_DIR/rollback.sh" ]]; then
        info "Using backup module rollback script"
        "$BACKUP_DIR/rollback.sh"
        return $?
    fi

    warn "No backup available, manual rollback required"
    warn "Configuration files that were created/modified:"
    warn "  $HOME/.bashrc"
    warn "  $HOME/.profile"
    warn "  $HOME/.bashrc.d/"

    return 1
}

# Internal function: _create_bashrc_d_structure
# Purpose: Create modular bashrc.d directory structure
_create_bashrc_d_structure() {
    info "Creating bashrc.d directory structure"

    mkdir -p "$HOME/.bashrc.d" "${XDG_CONFIG_HOME}"
    BASHRC_D_CREATED=1
}

# Internal function: _create_main_bashrc
# Purpose: Create main .bashrc file
_create_main_bashrc() {
    info "Creating main .bashrc file"

    write_atomic "$HOME/.bashrc" <<'RC'
#!/usr/bin/env bash
# ~/.bashrc — modular personal setup
# shellcheck shell=bash
case $- in *i*) ;; *) return ;; esac
for snip in "$HOME/.bashrc.d/"*.sh; do
  # shellcheck source=/dev/null
  [[ -r "$snip" ]] && . "$snip"
done
unset snip
RC

    SHELL_CONFIG_CREATED=1
}

# Internal function: _create_hygiene_config
# Purpose: Create shell hygiene and environment configuration
_create_hygiene_config() {
    write_atomic "$HOME/.bashrc.d/00-hygiene.sh" <<EOF
#!/usr/bin/env bash
# shellcheck shell=bash
shopt -s histappend checkwinsize cmdhist
shopt -s globstar extglob nullglob
HISTSIZE=100000
HISTFILESIZE=200000
HISTCONTROL=ignoredups:erasedups
HISTTIMEFORMAT='%F %T '
PROMPT_DIRTRIM=3
umask 027

# XDG Base Directory support
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# Path management
for p in "\$HOME/.local/bin" "\$HOME/bin"; do
  case ":\$PATH:" in *":\$p:"*) ;; *) [[ -d "\$p" ]] && PATH="\$p:\$PATH";; esac
done
export PATH
EOF
}

# Internal function: _create_completion_config
# Purpose: Create bash completion configuration
_create_completion_config() {
    write_atomic "$HOME/.bashrc.d/10-bash-completion.sh" <<'EOF'
#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1090,SC1091
if ! shopt -oq posix; then
  if [[ -f /usr/share/bash-completion/bash_completion ]]; then
    . /usr/share/bash-completion/bash_completion
  elif [[ -f /etc/bash_completion ]]; then
    . /etc/bash_completion
  fi
fi
EOF
}

# Internal function: _create_secrets_config
# Purpose: Create secrets management configuration
_create_secrets_config() {
    write_atomic "$HOME/.bashrc.d/30-secrets.sh" <<'EOF'
#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1090,SC1091
PASS_PREFIX="${PASS_PREFIX:-personal}"

pass_env() {
  command -v pass >/dev/null 2>&1 || return 0
  local prefix="${PASS_PREFIX}" item var val
  while IFS= read -r item; do
    [[ "$item" == "Search Terms:"* ]] && continue
    [[ -z "$item" ]] && continue
    val="$(pass show "$item" 2>/dev/null | head -n1)"
    var="${item##*/}"
    var="$(printf '%s' "$var" | tr '[:lower:]-' '[:upper:]_' | sed 's/[^A-Z0-9_]/_/g')"
    [[ -n "$var" && -n "$val" ]] && export "$var=$val"
  done < <(pass find "$prefix" 2>/dev/null || true)
}
pass_env

# Legacy plaintext fallback
_plain="${XDG_CONFIG_HOME:-$HOME/.config}/secrets.env"
if [[ -f "$_plain" ]]; then
  chmod 600 "$_plain" 2>/dev/null || true
  set -a
  while IFS= read -r line; do
    # skip comments/blank
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue

    # split on first '=' only
    key="${line%%=*}"
    val="${line#*=}"

    # trim whitespace around key/val
    key="${key#"${key%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"
    val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"

    # strip matching surrounding quotes
    if [[ "$val" == \"*\" && "$val" == *\" ]]; then
      val="${val%\"}"; val="${val#\"}"
    elif [[ "$val" == \'*\' && "$val" == *\' ]]; then
      val="${val%\'}"; val="${val#\'}"
    fi

    # only export valid shell identifiers
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && export "$key=$val"
  done < "$_plain"
  set +a
fi
unset _plain
EOF
}

# Internal function: _create_ssh_config
# Purpose: Create SSH agent configuration
_create_ssh_config() {
    write_atomic "$HOME/.bashrc.d/35-ssh.sh" <<'EOF'
#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1090
# Reuse one ssh-agent across sessions using XDG state

XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="$XDG_STATE_HOME/ssh"
AGENT_ENV="$STATE_DIR/agent.env"

mkdir -p "$STATE_DIR"

write_env() {
  umask 077
  local tmp
  tmp="$(mktemp "$STATE_DIR/.agent.XXXXXX")"
  {
    echo "export SSH_AUTH_SOCK='$SSH_AUTH_SOCK'"
    [ -n "${SSH_AGENT_PID:-}" ] && echo "export SSH_AGENT_PID='$SSH_AGENT_PID'"
  } > "$tmp"
  mv -f "$tmp" "$AGENT_ENV"
}

agent_alive() {
  [ -S "${SSH_AUTH_SOCK:-}" ] && ssh-add -l >/dev/null 2>&1
}

start_agent() {
  eval "$(ssh-agent -s)" >/dev/null
  write_env
}

# Load previous agent if present
if [ -r "$AGENT_ENV" ]; then
  . "$AGENT_ENV"
fi

# Start once if not usable
if ! agent_alive; then
  start_agent
fi

# Auto-load key if none present
if ! ssh-add -l >/dev/null 2>&1; then
  for k in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa"; do
    [ -f "$k" ] && ssh-add "$k" >/dev/null 2>&1 && break
  done
fi

# Helper function (callable manually)
ensure_ssh_key() {
  local key_type="${1:-ed25519}"
  local key_file="$HOME/.ssh/id_${key_type}"
  if [ ! -f "$key_file" ]; then
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keygen -t "$key_type" -f "$key_file" -N "" -C "$(whoami)@$(hostname)"
    ssh-add "$key_file"
  fi
  echo "Your SSH public key:"
  cat "${key_file}.pub"
}
EOF
}

# Internal function: _create_tools_config
# Purpose: Create development tools configuration
_create_tools_config() {
    write_atomic "$HOME/.bashrc.d/40-tools.sh" <<'EOF'
#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1090,SC1091

# nvm lazy loading
export NVM_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvm"
nvm() {
  unset -f nvm
  [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
  nvm "$@"
}
[[ -s "$NVM_DIR/bash_completion" ]] && . "$NVM_DIR/bash_completion"

# pyenv
if command -v pyenv >/dev/null 2>&1; then
  export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
  eval "$(pyenv init - bash)"
fi

# uv
if command -v uv >/dev/null 2>&1; then
  eval "$(uv generate-shell-completion bash 2>/dev/null || true)"
fi

# Rust/Cargo
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# Deno
[[ -f "$HOME/.deno/env" ]] && . "$HOME/.deno/env"

# Better manpages
if command -v batcat >/dev/null 2>&1; then
  export MANPAGER="sh -c 'col -bx | batcat -l man -p'"
  export MANROFFOPT="-c"
fi
EOF
}

# Internal function: _create_prompt_config
# Purpose: Create shell prompt configuration
_create_prompt_config() {
    write_atomic "$HOME/.bashrc.d/50-prompt.sh" <<'EOF'
#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1090,SC1091

# Git-aware prompt (Ubuntu path)
if [[ -f /usr/lib/git-core/git-sh-prompt ]]; then
  . /usr/lib/git-core/git-sh-prompt
  export GIT_PS1_SHOWDIRTYSTATE=1
  export GIT_PS1_SHOWSTASHSTATE=1
  export GIT_PS1_SHOWUNTRACKEDFILES=1
  export GIT_PS1_SHOWUPSTREAM="auto"
  export GIT_PS1_SHOWCOLORHINTS=1

  # Color prompt with git
  if [[ -x /usr/bin/tput ]] && tput setaf 1 >&/dev/null; then
    PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$(__git_ps1 " (\[\033[01;31m\]%s\[\033[00m\])")\$ '
  else
    PS1='[\u@\h \W$(__git_ps1 " (%s)")]\$ '
  fi
fi
EOF
}

# Internal function: _create_starship_config
# Purpose: Create Starship prompt configuration
_create_starship_config() {
    write_atomic "$HOME/.bashrc.d/55-starship.sh" <<'EOF'
#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1090,SC1091
# If starship is installed, enable it
if command -v starship >/dev/null 2>&1; then
  export STARSHIP_CONFIG="${STARSHIP_CONFIG:-$HOME/.config/starship.toml}"
  eval "$(starship init bash)"
fi
EOF
}

# Internal function: _create_aliases_config
# Purpose: Create aliases configuration
_create_aliases_config() {
    write_atomic "$HOME/.bashrc.d/60-aliases.sh" <<'EOF'
#!/usr/bin/env bash
# shellcheck shell=bash

# ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias lt='ls -alFtr'

# git aliases
alias gs='git status -sb'
alias gd='git diff'
alias gdc='git diff --cached'
alias gl='git log --oneline --graph --decorate'
alias gp='git pull'
alias gpu='git push'

# safety nets
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# shortcuts
alias h='history'
alias j='jobs -l'
alias path='echo -e ${PATH//:/\\n}'

# custom
alias homelab-status='cd "$HOME/git/homelab" && ./scripts/milestone-status.sh'
alias dotfiles-doctor='$HOME/git/machine-rites/tools/doctor.sh'
alias dotfiles-update='$HOME/git/machine-rites/tools/update.sh'
EOF
}

# Internal function: _create_local_config
# Purpose: Create local customization file
_create_local_config() {
    write_atomic "$HOME/.bashrc.d/99-local.sh" <<'EOF'
#!/usr/bin/env bash
# Machine-specific overrides (not tracked in git)
# Add your local customizations here
# export EDITOR=vim
EOF
}

# Internal function: _create_profile
# Purpose: Create .profile file
_create_profile() {
    info "Creating .profile file"

    write_atomic "$HOME/.profile" <<'PROF'
#!/usr/bin/env bash
# ~/.profile
# shellcheck shell=sh
[ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"

# Set PATH
for p in "$HOME/bin" "$HOME/.local/bin"; do
  case ":$PATH:" in *":$p:"*) ;; *) [ -d "$p" ] && PATH="$p:$PATH";; esac
done
export PATH
PROF
}

# Internal function: _apply_via_chezmoi
# Purpose: Apply configurations via chezmoi if available
_apply_via_chezmoi() {
    if ! command -v chezmoi >/dev/null 2>&1; then
        info "chezmoi not available, skipping chezmoi integration"
        return 0
    fi

    if [[ -z "${CHEZMOI_SRC:-}" ]] || [[ ! -d "${CHEZMOI_SRC}" ]]; then
        info "chezmoi source directory not available, skipping chezmoi integration"
        return 0
    fi

    info "Importing shell configuration into chezmoi"

    # Import shell configuration files
    local files_to_import=(
        "$HOME/.bashrc"
        "$HOME/.profile"
        "$HOME/.bashrc.d"
    )

    local file
    for file in "${files_to_import[@]}"; do
        if [[ -e "$file" ]]; then
            if chezmoi -S "$CHEZMOI_SRC" add "$file" 2>/dev/null; then
                info "Imported into chezmoi: $file"
            else
                warn "Failed to import into chezmoi: $file"
            fi
        fi
    done
}

# Module execution guard
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    validate && execute && verify
fi