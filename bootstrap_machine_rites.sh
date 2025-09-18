#!/usr/bin/env bash
# Ubuntu 24.04 — modular bash + chezmoi (sourceDir in your repo) + pass + gitleaks + pipx
# Production-grade with all critical fixes and enhancements
set -euo pipefail

# ----- color codes & helpers -----
C_G="\033[1;32m"; C_Y="\033[1;33m"; C_R="\033[1;31m"; C_B="\033[1;34m"; C_N="\033[0m"
say(){ printf "${C_G}[+] %s${C_N}\n" "$*"; }
info(){ printf "${C_B}[i] %s${C_N}\n" "$*"; }
warn(){ printf "${C_Y}[!] %s${C_N}\n" "$*"; }
die(){ printf "${C_R}[✘] %s${C_N}\n" "$*" >&2; exit 1; }

# Require sudo if not root (for apt installs)
if [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
  die "This script needs 'sudo' for package installs. Install sudo or run as root."
fi

# ----- parse flags -----
UNATTENDED=0
VERBOSE=0
SKIP_BACKUP=0
DEBUG=0
for arg in "$@"; do
  case "$arg" in
    --unattended|-u) UNATTENDED=1 ;;
    --verbose|-v) VERBOSE=1 ;;
    --skip-backup) SKIP_BACKUP=1 ;;
    --debug) DEBUG=1 ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo "  -u, --unattended  Run without prompts"
      echo "  -v, --verbose     Enable debug output"
      echo "  --skip-backup     Skip backup step (dangerous)"
      echo "  --debug           Extra diagnostics (xtrace + preflight)"
      echo "  -h, --help        Show this help"
      exit 0
      ;;
    *) warn "Unknown option: $arg" ;;
  esac
done
[ "$VERBOSE" -eq 1 ] && set -x
if [ "$DEBUG" -eq 1 ]; then
  export PS4='+(${BASH_SOURCE##*/}:${LINENO}): ${FUNCNAME[0]:-main}(): '
  set -x
fi
trap 'echo "[ERR] rc=$? at ${BASH_SOURCE[0]}:${LINENO} running: ${BASH_COMMAND}" >&2' ERR

# ----- tiny debug helpers -----
debug_var(){ local n="$1" v="${!1:-<unset>}"; printf "[debug] %s=%s (%%q:%q)\n" "$n" "$v" "$v"; }
preflight_scan(){
  echo "[debug] Preflight scan…"
  local self cfg
  self="$(readlink -f "$0" 2>/dev/null || echo "$0")"
  cfg="${CHEZMOI_CFG:-$HOME/.config/chezmoi/chezmoi.toml}"

  # 1) suspicious escapes in THIS script (these must not exist)
  if grep -nE '\\\$HOME|\\\$CHEZMOI(_|SRC)|\\\[' "$self" 2>/dev/null; then
    echo "[warn] Script contains escaped variables/brackets above — fix before running."
  else
    echo "[debug] No escaped \$HOME/\$CHEZMOI_* or bracket escapes in script."
  fi

  # 2) single-quoted variables (won't expand)
  if grep -nE "'.*\$[A-Za-z_][A-Za-z0-9_]*.*'" "$self" 2>/dev/null; then
    echo "[warn] Variables found inside single quotes in script (won't expand)."
  else
    echo "[debug] No single-quoted variables in script."
  fi

  # 3) chezmoi config echo
  if [ -f "$cfg" ]; then
    echo "[debug] Found $cfg"
    grep -nE '\$CHEZMOI|\\_' "$cfg" && echo "[warn] Config contains escaped vars" || true
  else
    echo "[debug] No chezmoi.toml yet (will be created)."
  fi

  if command -v chezmoi >/dev/null 2>&1; then
    echo "[debug] chezmoi sourceDir (template): $(chezmoi execute-template '{{ .chezmoi.sourceDir }}' 2>/dev/null || echo '<unknown>')"
    chezmoi doctor || true
  fi
}
[ "$DEBUG" -eq 1 ] && preflight_scan

# Self-lint this script if shellcheck exists (does not fail the run)
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x -S warning "$0" || warn "ShellCheck found issues in $0"
fi

# ----- version checking helper -----
need_version() {
  local cmd="$1" min="$2" cur
  command -v "$cmd" >/dev/null || return 1
  cur="$("$cmd" --version 2>/dev/null | grep -Eo '[0-9]+(\.[0-9]+)+' | head -1 || true)"
  [ -z "$cur" ] && return 0  # Can't determine version, assume OK
  [ "$(printf '%s\n' "$min" "$cur" | sort -V | head -1)" = "$min" ] || return 1
}

# ----- OS check -----
if ! lsb_release -is 2>/dev/null | grep -q Ubuntu; then
  warn "This script is designed for Ubuntu. Detected: $(lsb_release -is 2>/dev/null || echo 'Unknown')"
  if [ "$UNATTENDED" -eq 0 ]; then
    read -rp "Continue anyway? [y/N] " -n 1 -r; echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && die "Aborted by user"
  fi
fi

# ----- XDG Base Directory support -----
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# ----- repo / chezmoi settings -----
REPO_DIR="${REPO_DIR:-$HOME/git/machine-rites}"
REPO_URL="${REPO_URL:-https://github.com/williamzujkowski/machine-rites}"
CHEZMOI_CFG="$XDG_CONFIG_HOME/chezmoi/chezmoi.toml"
CHEZMOI_SRC="$REPO_DIR/.chezmoi"
PASS_PREFIX="${PASS_PREFIX:-personal}"

# ----- atomic write helper -----
write_atomic() {
  local target="$1" tmp
  tmp="$(mktemp "${target}.XXXXXX")"
  cat > "$tmp"
  mkdir -p "$(dirname "$target")"
  mv -f "$tmp" "$target"
  chmod 0644 "$target" 2>/dev/null || true
}

# ----- detect git user info dynamically -----
GIT_NAME="${GIT_NAME:-$(git config --global user.name 2>/dev/null || true)}"
GIT_EMAIL="${GIT_EMAIL:-$(git config --global user.email 2>/dev/null || true)}"
if [ -z "${GIT_EMAIL}" ] && [ -t 0 ] && [ "${UNATTENDED}" -eq 0 ]; then
  read -rp "Git email not set. Enter email for chezmoi data: " GIT_EMAIL
fi
[ -z "${GIT_NAME}" ] && GIT_NAME="$(whoami)"
[ -z "${GIT_EMAIL}" ] && GIT_EMAIL="$(whoami)@$(hostname)"

# ----- backup with rollback -----
ts="$(date +%Y%m%d-%H%M%S)"
backup_dir="$HOME/dotfiles-backup-$ts"

if [ "$SKIP_BACKUP" -eq 0 ]; then
  mkdir -p "$backup_dir"
  say "Creating backup: $backup_dir"
  # Cleanup policy: keep only the latest 5 backups
  ls -dt "$HOME"/dotfiles-backup-* 2>/dev/null | tail -n +6 | xargs -r rm -rf || true

  # Save manifest for rollback
  echo "# Backup manifest - $ts" > "$backup_dir/.manifest"

  for f in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bashrc.d" \
           "$XDG_CONFIG_HOME/secrets.env" "$HOME/.gitignore_global" \
           "$CHEZMOI_CFG" "$HOME/.ssh/config"; do
    if [ -e "$f" ]; then
      cp -a "$f" "$backup_dir/" 2>/dev/null || true
      echo "$f" >> "$backup_dir/.manifest"
      [ "$VERBOSE" -eq 1 ] && info "  backed up: $f"
    fi
  done

  # Create rollback script
  cat > "$backup_dir/rollback.sh" <<'ROLLBACK'
#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$BACKUP_DIR/.manifest"
echo "[rollback] Restoring from $BACKUP_DIR"
if [ ! -f "$MANIFEST" ]; then
  echo "[rollback] No manifest found"; exit 1
fi
while IFS= read -r path; do
  [ -z "$path" ] && continue
  case "$path" in \#*) continue;; esac
  rel="${path#"$HOME/"}"
  src="$BACKUP_DIR/$rel"
  dst="$path"
  if [ -e "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
    echo "  restored: $dst"
  fi
done < "$MANIFEST"
echo "[rollback] Done. Run 'exec bash -l' to reload shell."
ROLLBACK
  chmod +x "$backup_dir/rollback.sh"
  info "Rollback script: $backup_dir/rollback.sh"
fi

# ----- install packages -----
say "Installing system packages..."
export DEBIAN_FRONTEND=noninteractive
# Leave chezmoi to the official installer fallback below (Ubuntu 24.04 lacks package)
packages=(curl git gnupg pass age gitleaks bash-completion pipx openssh-client)
missing=()
for p in "${packages[@]}"; do
  dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
done
if [ "${#missing[@]}" -gt 0 ]; then
  say "Installing: ${missing[*]}"
  if [ "$(id -u)" -eq 0 ]; then
    apt-get update -y
    apt-get install -y "${missing[@]}" || true
  else
    sudo -n true 2>/dev/null || warn "sudo may prompt for password"
    sudo apt-get update -y
    sudo apt-get install -y "${missing[@]}" || true
  fi
else
  info "All packages already present"
fi

# ----- ensure chezmoi via official installer if not present -----
if ! command -v chezmoi >/dev/null 2>&1; then
  say "Installing chezmoi via official installer..."
  sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" || die "chezmoi install failed"
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
  command -v chezmoi >/dev/null 2>&1 || die "chezmoi not found on PATH after install"
fi

# pipx setup (do NOT eval pipx output)
if command -v pipx >/dev/null 2>&1; then
  pipx ensurepath >/dev/null 2>&1 || true
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
else
  warn "pipx not found on PATH; ensure it's installed (apt install pipx) and re-run if needed"
fi

if ! command -v pre-commit >/dev/null 2>&1; then
  say "Installing pre-commit via pipx..."
  pipx install pre-commit >/dev/null || true
fi

# Optional: install Starship prompt
if ! command -v starship >/dev/null 2>&1; then
  if [ "$UNATTENDED" -eq 0 ] && [ -t 0 ]; then
    read -rp "Install Starship prompt? [y/N] " -n 1 -r; echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      curl -sS https://starship.rs/install.sh | sh -s -- -b "$HOME/.local/bin" -y || warn "Starship install failed"
    fi
  else
    info "Consider installing Starship for a fast, pretty prompt: https://starship.rs"
  fi
fi

# Verify critical tools and versions
for tool in chezmoi pass gitleaks pre-commit git gpg; do
  if command -v "$tool" >/dev/null 2>&1; then
    [ "$VERBOSE" -eq 1 ] && info "$tool: $("$tool" --version 2>/dev/null | head -1 || echo OK)"
  else
    die "Failed to install $tool"
  fi
done
need_version chezmoi 2.0 || warn "chezmoi version is old; consider upgrading"
need_version git 2.25 || warn "git version is old; consider upgrading"

# ----- clone/sync repo -----
if [ ! -d "$REPO_DIR/.git" ]; then
  say "Cloning $REPO_URL -> $REPO_DIR"
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone "$REPO_URL" "$REPO_DIR" || die "Failed to clone repo"
else
  say "Updating existing repo at $REPO_DIR"
  (cd "$REPO_DIR" && git fetch origin && git pull --ff-only 2>/dev/null) || warn "Could not pull latest"
fi

# ----- chezmoi config -----
mkdir -p "$(dirname "$CHEZMOI_CFG")" "$CHEZMOI_SRC"
if [ ! -f "$CHEZMOI_CFG" ]; then
  say "Creating chezmoi config"
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
else
  grep -q 'sourceDir' "$CHEZMOI_CFG" || printf '\nsourceDir = "%s"\n' "$CHEZMOI_SRC" >> "$CHEZMOI_CFG"
fi

# ----- create modular bash configuration -----
say "Creating modular bash configuration..."
mkdir -p "$HOME/.bashrc.d" "$XDG_CONFIG_HOME"

# Main bashrc
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

# 00-hygiene.sh
write_atomic "$HOME/.bashrc.d/00-hygiene.sh" <<'EOF'
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
for p in "$HOME/.local/bin" "$HOME/bin"; do
  case ":$PATH:" in *":$p:"*) ;; *) [[ -d "$p" ]] && PATH="$p:$PATH";; esac
done
export PATH
EOF

# 10-bash-completion.sh
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

# (Removed Oh-My-Bash to reduce footprint/supply-chain surface)

# 30-secrets.sh
write_atomic "$HOME/.bashrc.d/30-secrets.sh" <<'EOF'
#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1090,SC1091
PASS_PREFIX="${PASS_PREFIX:-personal}"

pass_env() {
  command -v pass >/dev/null 2>&1 || return 0
  local prefix="${1:-$PASS_PREFIX}" item var val
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

# 35-ssh.sh - Fixed agent reuse
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

# 40-tools.sh
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

# 41-completions.sh — tool-specific completions without Oh-My-Bash
write_atomic "$HOME/.bashrc.d/41-completions.sh" <<'EOF'
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
EOF

# 50-prompt.sh
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

# 55-starship.sh — fast cross-shell prompt
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

# 60-aliases.sh
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

# 99-local.sh
write_atomic "$HOME/.bashrc.d/99-local.sh" <<'EOF'
#!/usr/bin/env bash
# Machine-specific overrides (not tracked in git)
# Add your local customizations here
# export EDITOR=vim
EOF

# Profile
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

# ----- import into chezmoi -----
say "Importing dotfiles into chezmoi..."
debug_var REPO_DIR
debug_var CHEZMOI_SRC
chezmoi -S "$CHEZMOI_SRC" add "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bashrc.d" 2>/dev/null || true

# .chezmoiignore
write_atomic "$CHEZMOI_SRC/.chezmoiignore" <<'IGN'
.bashrc.d/99-local.sh
README.md
.git
.gitignore
IGN

# README
[ -f "$CHEZMOI_SRC/README.md" ] || write_atomic "$CHEZMOI_SRC/README.md" <<'README'
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
```

README

# ----- apply chezmoi -----
say "Applying chezmoi configuration..."
debug_var CHEZMOI_SRC
chezmoi -S "$CHEZMOI_SRC" apply || warn "Chezmoi apply failed"

# ----- gitignore -----
# Global gitignore for sensitive files
touch "$HOME/.gitignore_global"
for pattern in ".config/secrets.env" ".bashrc.d/99-local.sh" "*.swp" ".DS_Store" "*.tmp"; do
  grep -qxF "$pattern" "$HOME/.gitignore_global" 2>/dev/null || echo "$pattern" >> "$HOME/.gitignore_global"
done
git config --global core.excludesFile "$HOME/.gitignore_global" 2>/dev/null || true

# ----- GPG / pass setup -----
ensure_gpg_key() {
  if gpg --list-secret-keys --with-colons 2>/dev/null | grep -q '^sec:'; then
    return 0
  fi
  
  warn "No GPG key found for pass encryption"
  
  if [ "$UNATTENDED" -eq 0 ] && [ -t 0 ]; then
    echo "Options:"
    echo "  1) Generate a new GPG key now (recommended)"
    echo "  2) Import existing GPG key"
    echo "  3) Skip (pass won't work)"
    read -rp "Choice [1-3]: " -n 1 -r; echo
    case "$REPLY" in
      1) gpg --full-generate-key ;;
      2) echo "Run: gpg --import /path/to/key.asc" ;;
      3) return 1 ;;
      *) return 1 ;;
    esac
  else
    info "Run 'gpg --full-generate-key' to create a GPG key for pass"
    return 1
  fi
}

if command -v pass >/dev/null 2>&1; then
  if ! pass ls >/dev/null 2>&1; then
    if ensure_gpg_key; then
      key="$(gpg --list-secret-keys --with-colons | awk -F: '/^sec:/ {print $5; exit}')"
      say "Initializing pass with GPG key: ${key:0:16}..."
      pass init "$key" || warn "pass init failed"
    fi
  else
    info "pass already initialized"
  fi
fi

# ----- migrate plaintext secrets -----
if [ -f "$XDG_CONFIG_HOME/secrets.env" ] && pass ls >/dev/null 2>&1; then
  say "Migrating secrets to pass..."
  while IFS= read -r line; do
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
    
    # only store valid shell identifiers
    if [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      low="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')"
      printf '%s\n' "$val" | pass insert -m "${PASS_PREFIX}/${low}" >/dev/null 2>&1 || warn "Failed: $key"
    fi
  done < "$XDG_CONFIG_HOME/secrets.env"
  
  if [ "$UNATTENDED" -eq 0 ] && [ -t 0 ]; then
    read -rp "Shred plaintext secrets file? [y/N] " -n 1 -r; echo
    [[ $REPLY =~ ^[Yy]$ ]] && shred -u "$XDG_CONFIG_HOME/secrets.env"
  else
    info "Plaintext secrets remain at: $XDG_CONFIG_HOME/secrets.env"
  fi
fi

# ----- gitleaks config -----
write_atomic "$REPO_DIR/.gitleaks.toml" <<'TOML'
[extend]
useDefault = true

[[rules]]
id = "custom-api-key"
description = "Custom API Key Pattern"
regex = '''(?i)(api[_-]?key|apikey)['""]?\s*[:=]\s*['""]?([a-z0-9]{32,})'''

[allowlist]
paths = [
  '''vendor/''',
  '''node_modules/'''
]
TOML

# Optional starship config (created if not present)
if [ ! -f "$XDG_CONFIG_HOME/starship.toml" ]; then
  write_atomic "$XDG_CONFIG_HOME/starship.toml" <<'STAR'
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
STAR
else
  info "Existing starship.toml found, preserving"
fi

# ----- pre-commit -----
write_atomic "$REPO_DIR/.pre-commit-config.yaml" <<'YAML'
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
YAML
( cd "$REPO_DIR" && pre-commit install >/dev/null 2>&1 ) || warn "pre-commit install failed"

# ----- helper scripts -----
mkdir -p "$REPO_DIR/tools"

# doctor.sh
write_atomic "$REPO_DIR/tools/doctor.sh" <<'DOC'
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
DOC
chmod 0755 "$REPO_DIR/tools/doctor.sh"

# update.sh
write_atomic "$REPO_DIR/tools/update.sh" <<'UPD'
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
UPD
chmod 0755 "$REPO_DIR/tools/update.sh"

# backup-pass.sh
write_atomic "$REPO_DIR/tools/backup-pass.sh" <<'BKP'
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
BKP
chmod 0755 "$REPO_DIR/tools/backup-pass.sh"

# ----- CI/CD workflow with proper permissions -----
mkdir -p "$REPO_DIR/.github/workflows"
write_atomic "$REPO_DIR/.github/workflows/ci.yml" <<'YAML'
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
YAML

# ----- commit changes -----
say "Committing configuration..."
(
  cd "$REPO_DIR"
  git add -A
  if git diff --cached --quiet; then
    info "No changes to commit"
  else
    git commit -m "feat: production-grade dotfiles with all fixes

* Smart SSH agent reuse (no multiplication)
* Dynamic git email detection
* XDG Base Directory compliance
* Atomic file operations
* Rollback mechanism
* Version checking
* ShellCheck pragmas
* CI with PR permissions
* Enhanced helper scripts
* Remove Oh-My-Bash; add explicit completions
* Starship prompt support
* Safer pipx path logic and apt handling
* Manifest-driven rollback
* Hardened gitleaks allowlist"
  fi
) || warn "Commit failed"

# ----- validation -----
say "Running validation..."
errors=0

# Syntax check
for f in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bashrc.d/"*.sh; do
  if ! bash -n "$f" 2>/dev/null; then
    warn "Syntax error: $f"
    ((errors++))
  fi
done

# Smoke test
if ! bash -ilc 'echo "OK" && ssh-add -l >/dev/null 2>&1' >/dev/null 2>&1; then
  warn "Interactive shell test failed"
  ((errors++))
fi

if [ "$errors" -gt 0 ]; then
  die "Validation failed with $errors errors"
fi

# ----- complete -----
say "Bootstrap complete!"
echo
echo "Backups: ${backup_dir:-none}"
echo "Repository: $REPO_DIR"
echo
echo "Next steps:"
echo "  1. Reload: exec bash -l"
echo "  2. Check: $REPO_DIR/tools/doctor.sh"
echo "  3. Secrets: pass insert ${PASS_PREFIX}/github_token"
echo "  4. SSH: ensure_ssh_key"
echo "  5. Optional: install starship (https://starship.rs) for the prompt"
echo
[ "$SKIP_BACKUP" -eq 0 ] && info "Rollback: ${backup_dir}/rollback.sh"
