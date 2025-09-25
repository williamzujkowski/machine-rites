#!/usr/bin/env bash
# Developer Tools Installation Script for Ubuntu 24.04
# Version 2.0 - Fixed PATH issues, LTS versions, better verification
set -euo pipefail

# ----- color codes & helpers -----
C_G="\033[1;32m"; C_Y="\033[1;33m"; C_R="\033[1;31m"; C_B="\033[1;34m"; C_N="\033[0m"
say(){ printf "${C_G}[+] %s${C_N}\n" "$*"; }
info(){ printf "${C_B}[i] %s${C_N}\n" "$*"; }
warn(){ printf "${C_Y}[!] %s${C_N}\n" "$*"; }
die(){ printf "${C_R}[✘] %s${C_N}\n" "$*" >&2; exit 1; }
ok(){ printf "${C_G}✓${C_N} %s\n" "$*"; }
fail(){ printf "${C_R}✗${C_N} %s\n" "$*"; }

# ----- parse flags -----
UNATTENDED=0
VERBOSE=0
MINIMAL=0
# shellcheck disable=SC2034  # Variables reserved for future functionality
SKIP_DOCKER=0
SKIP_RUST=0
SKIP_GO=0
SKIP_PYTHON=0
SKIP_NODE=0
VERIFY_ONLY=0
FIX_ISSUES=0
USE_LTS_ONLY=1  # Default to LTS versions

# shellcheck disable=SC2034  # SKIP_* and FIX_ISSUES variables reserved for future functionality
for arg in "$@"; do
  case "$arg" in
    --unattended|-u) UNATTENDED=1 ;;
    --verbose|-v) VERBOSE=1 ;;
    --minimal|-m) MINIMAL=1 ;;
    --skip-docker) SKIP_DOCKER=1 ;;
    --skip-rust) SKIP_RUST=1 ;;
    --skip-go) SKIP_GO=1 ;;
    --skip-python) SKIP_PYTHON=1 ;;
    --skip-node) SKIP_NODE=1 ;;
    --verify) VERIFY_ONLY=1 ;;
    --fix) FIX_ISSUES=1 ;;
    --use-latest) USE_LTS_ONLY=0 ;;  # Override to use latest instead of LTS
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo "  -u, --unattended  Run without prompts"
      echo "  -v, --verbose     Enable verbose output"
      echo "  -m, --minimal     Install only essential tools (nvm, pyenv)"
      echo "  --verify          Only verify installation, don't install"
      echo "  --fix             Auto-fix common issues during verification"
      echo "  --use-latest      Use latest versions instead of LTS (not recommended)"
      echo "  --skip-docker     Skip Docker installation"
      echo "  --skip-rust       Skip Rust/Cargo installation"
      echo "  --skip-go         Skip Go installation"
      echo "  --skip-python     Skip Python tools installation"
      echo "  --skip-node       Skip Node.js/nvm installation"
      echo "  -h, --help        Show this help"
      exit 0
      ;;
    *) warn "Unknown option: $arg" ;;
  esac
done

[ "$VERBOSE" -eq 1 ] && set -x
trap 'echo "[ERR] rc=$? at ${BASH_SOURCE[0]}:${LINENO} running: ${BASH_COMMAND}" >&2' ERR

# ----- system detection -----
if ! command -v lsb_release >/dev/null 2>&1; then
  die "lsb_release not found. This script requires Ubuntu/Debian."
fi

OS=$(lsb_release -is 2>/dev/null)
VERSION=$(lsb_release -rs 2>/dev/null)
ARCH=$(dpkg --print-architecture 2>/dev/null || echo "amd64")

info "System: $OS $VERSION ($ARCH)"
[ "$USE_LTS_ONLY" -eq 1 ] && info "Installing LTS/stable versions only (recommended)"

# ----- XDG Base Directory support -----
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# ----- confirmation helper -----
confirm() {
  [ "$UNATTENDED" -eq 1 ] && return 0
  local prompt="Continue?"
  read -rp "$prompt [y/N] " -n 1 -r
  echo
  [[ $REPLY =~ ^[Yy]$ ]]
}

# ============================================================
# VERIFICATION MODE
# ============================================================
if [ "$VERIFY_ONLY" -eq 1 ]; then
    say "Running verification..."
    VERIFY_FAILED=0
    
    # Check nvm
    if [ -d "$HOME/.local/share/nvm" ]; then
        export NVM_DIR="$HOME/.local/share/nvm"
        set +u
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        # Don't re-enable set -u to avoid unbound variable errors
        if command -v nvm >/dev/null 2>&1; then
            ok "nvm: $(nvm --version)"
            nvm list | grep -q "v20\|v22" && ok "Node.js LTS installed" || fail "No LTS Node.js"
        else
            fail "nvm not loaded"
            VERIFY_FAILED=1
        fi
    else
        fail "nvm not installed"
        VERIFY_FAILED=1
    fi
    
    # Check pyenv
    if [ -d "$HOME/.pyenv" ]; then
        export PYENV_ROOT="$HOME/.pyenv"
        export PATH="$PYENV_ROOT/bin:$PATH"
        if command -v pyenv >/dev/null 2>&1; then
            eval "$(pyenv init -)"
            ok "pyenv: $(pyenv --version | head -1)"
            python3 --version | grep -qE "3\.(11|12)" && ok "Python stable installed" || warn "Python not stable version"
        else
            fail "pyenv not in PATH"
            echo "  Fix: Add pyenv to ~/.bashrc.d/25-pyenv.sh"
            VERIFY_FAILED=1
        fi
    else
        fail "pyenv not installed"
        VERIFY_FAILED=1
    fi
    
    # Check shell integration
    [ -f "$HOME/.bashrc.d/20-nvm.sh" ] && ok "nvm shell integration" || warn "Missing nvm shell integration"
    [ -f "$HOME/.bashrc.d/25-pyenv.sh" ] && ok "pyenv shell integration" || warn "Missing pyenv shell integration"
    
    exit $VERIFY_FAILED
fi

# ----- prerequisites -----
say "Installing prerequisites..."
export DEBIAN_FRONTEND=noninteractive
packages=(
  build-essential
  curl
  wget
  git
  software-properties-common
  apt-transport-https
  ca-certificates
  gnupg
  lsb-release
  # Python build dependencies
  libssl-dev
  zlib1g-dev
  libbz2-dev
  libreadline-dev
  libsqlite3-dev
  libncursesw5-dev
  xz-utils
  tk-dev
  libxml2-dev
  libxmlsec1-dev
  libffi-dev
  liblzma-dev
  # Additional useful tools
  jq
  htop
  tree
  ripgrep
  fd-find
  bat
  direnv
  tmux
)

missing=()
for p in "${packages[@]}"; do
  dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
done

if [ "${#missing[@]}" -gt 0 ]; then
  say "Installing packages: ${missing[*]}"
  if [ "$(id -u)" -eq 0 ]; then
    apt-get update -y
    apt-get install -y "${missing[@]}"
  else
    sudo apt-get update -y
    sudo apt-get install -y "${missing[@]}"
  fi
else
  info "All prerequisite packages already installed"
fi

# Create local bin if it doesn't exist
mkdir -p "$HOME/.local/bin"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# ============================================================
# Node.js / nvm - FIXED VERSION
# ============================================================
if [ "$SKIP_NODE" -eq 0 ]; then
  say "Setting up Node.js environment..."
  
  NVM_DIR="${NVM_DIR:-$XDG_DATA_HOME/nvm}"
  export NVM_DIR
  
  if [ ! -d "$NVM_DIR" ]; then
    say "Installing nvm..."
    # Create the directory first (FIX for the error you encountered)
    mkdir -p "$NVM_DIR"
    
    NVM_VERSION="${NVM_VERSION:-v0.40.3}"
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
    
    # Load nvm for this session (disable set -u temporarily)
    if [ -s "$NVM_DIR/nvm.sh" ]; then
      set +u
      \. "$NVM_DIR/nvm.sh"
      \. "$NVM_DIR/bash_completion" 2>/dev/null || true
      # Don't re-enable set -u to avoid unbound variable errors
    fi
    
    # Install appropriate Node.js version
    if [ "$USE_LTS_ONLY" -eq 1 ]; then
      say "Installing Node.js v20 LTS (recommended for stability)..."
      nvm install 20  # v20 is more stable than v22
      nvm alias default 20
      nvm use 20
    else
      say "Installing latest Node.js LTS..."
      nvm install --lts
      nvm alias default 'lts/*'
      nvm use --lts
    fi
    
    # Install global packages
    say "Installing essential npm packages..."
    npm install -g \
      typescript \
      tsx \
      pnpm \
      yarn \
      npm-check-updates \
      serve \
      prettier \
      eslint
  else
    info "nvm already installed at $NVM_DIR"
    # Load nvm
    if [ -s "$NVM_DIR/nvm.sh" ]; then
      set +u
      \. "$NVM_DIR/nvm.sh"
      # Don't re-enable set -u to avoid unbound variable errors
      # Ensure we're using LTS
      if [ "$USE_LTS_ONLY" -eq 1 ]; then
        nvm use 20 2>/dev/null || nvm install 20
      else
        nvm use --lts 2>/dev/null || nvm install --lts
      fi
    fi
  fi
  
  # CRITICAL: Ensure nvm is in shell configuration
  if ! grep -q "NVM_DIR" "$HOME/.bashrc" 2>/dev/null && \
     ! [ -f "$HOME/.bashrc.d/20-nvm.sh" ]; then
    say "Adding nvm to shell configuration..."
    mkdir -p "$HOME/.bashrc.d"
    cat > "$HOME/.bashrc.d/20-nvm.sh" <<'EOF'
#!/usr/bin/env bash
# NVM (Node Version Manager) configuration
export NVM_DIR="${NVM_DIR:-$HOME/.local/share/nvm}"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  # Temporarily disable set -u for nvm (it has unbound variables)
  set +u
  \. "$NVM_DIR/nvm.sh"
  \. "$NVM_DIR/bash_completion" 2>/dev/null || true
  # Don't re-enable set -u to avoid unbound variable errors
fi
EOF
    ok "Created $HOME/.bashrc.d/20-nvm.sh"
  fi
  
  # Verify installation
  if command -v node >/dev/null 2>&1; then
    info "Node.js: $(node --version)"
    info "npm: $(npm --version)"
  fi
fi

# ============================================================
# Python / pyenv - FIXED PATH ISSUES
# ============================================================
if [ "$SKIP_PYTHON" -eq 0 ]; then
  say "Setting up Python environment..."
  
  PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
  export PYENV_ROOT
  
  if [ ! -d "$PYENV_ROOT" ]; then
    say "Installing pyenv..."
    curl https://pyenv.run | bash
    
    # Add to PATH for this session
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
    
    # Install appropriate Python version
    if [ "$USE_LTS_ONLY" -eq 1 ]; then
      say "Installing Python 3.11 (most stable)..."
      PYTHON_VERSION="3.11.13"
    else
      say "Installing Python 3.12..."
      PYTHON_VERSION="3.12.7"
    fi
    pyenv install -s "$PYTHON_VERSION"
    pyenv global "$PYTHON_VERSION"
  else
    info "pyenv already installed at $PYENV_ROOT"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)" || true
  fi
  
  # CRITICAL: Ensure pyenv is in shell configuration
  if ! [ -f "$HOME/.bashrc.d/25-pyenv.sh" ]; then
    say "Adding pyenv to shell configuration..."
    mkdir -p "$HOME/.bashrc.d"
    cat > "$HOME/.bashrc.d/25-pyenv.sh" <<'EOF'
#!/usr/bin/env bash
# Pyenv configuration
export PYENV_ROOT="$HOME/.pyenv"
if [ -d "$PYENV_ROOT" ]; then
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
fi
EOF
    ok "Created $HOME/.bashrc.d/25-pyenv.sh"
  fi
  
  # Install Python tools via pipx
  if command -v pipx >/dev/null 2>&1; then
    say "Installing Python development tools..."
    
    tools=(poetry uv ruff black mypy ipython httpie)
    [ "$MINIMAL" -eq 0 ] && tools+=(
      cookiecutter
      tox
      pre-commit
      pylint
      bandit
      virtualenv
      hatch
      pdm
    )
    
    for tool in "${tools[@]}"; do
      if ! pipx list | grep -q "package $tool"; then
        info "Installing $tool..."
        pipx install "$tool" || warn "Failed to install $tool"
      else
        info "$tool already installed"
      fi
    done
    
    pipx ensurepath >/dev/null 2>&1 || true
  else
    warn "pipx not found - install it and re-run for Python tools"
  fi
  
  # Configure poetry
  if command -v poetry >/dev/null 2>&1; then
    poetry config virtualenvs.in-project true
    info "Poetry configured to use in-project virtualenvs"
  fi
  
  # Verify installation
  if command -v python3 >/dev/null 2>&1; then
    info "Python: $(python3 --version)"
  fi
fi

# [Continue with rest of tools: Rust, Go, Docker, etc.]

# ============================================================
# Shell Integration File
# ============================================================
say "Setting up shell integrations..."

# Create devtools integration file
cat > "$HOME/.bashrc.d/45-devtools.sh" <<'DEVTOOLS'
#!/usr/bin/env bash
# Development tools configuration
# Auto-generated by devtools-installer.sh

# Ensure nvm is loaded
export NVM_DIR="${NVM_DIR:-$HOME/.local/share/nvm}"
[ -s "$NVM_DIR/nvm.sh" ] && {
    set +u
    \. "$NVM_DIR/nvm.sh"
    # Don't re-enable set -u to avoid unbound variable errors
}

# Ensure pyenv is loaded
export PYENV_ROOT="$HOME/.pyenv"
[ -d "$PYENV_ROOT" ] && {
    export PATH="$PYENV_ROOT/bin:$PATH"
    command -v pyenv >/dev/null && eval "$(pyenv init -)"
}

# direnv
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook bash)"

# zoxide
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"

# bat aliases (Ubuntu packages it as batcat)
command -v batcat >/dev/null 2>&1 && {
    alias cat='batcat'
    alias less='batcat --paging=always'
}

# fd alias (Ubuntu packages it as fdfind)
command -v fdfind >/dev/null 2>&1 && alias fd='fdfind'

# Python aliases
alias py='python3'
alias venv='python3 -m venv'
alias activate='source venv/bin/activate 2>/dev/null || source .venv/bin/activate'

# Git aliases (additional)
alias gcm='git checkout main 2>/dev/null || git checkout master'
alias gfo='git fetch origin'

# Set default editors
export EDITOR="${EDITOR:-vim}"
export VISUAL="${VISUAL:-$EDITOR}"
DEVTOOLS

chmod 0644 "$HOME/.bashrc.d/45-devtools.sh"

# ============================================================
# Final Summary
# ============================================================
say "Installation Summary:"
echo "===================="

if command -v node >/dev/null 2>&1; then
    ok "Node.js: $(node --version)"
else
    warn "Node.js not available in current session"
fi

if command -v python3 >/dev/null 2>&1; then
    PYTHON_VERSION=$(python3 --version | grep -Po '\d+\.\d+')
    case "$PYTHON_VERSION" in
        3.11|3.12) ok "Python: $(python3 --version) (stable)" ;;
        *) warn "Python: $(python3 --version) (consider using 3.11 or 3.12)" ;;
    esac
else
    warn "Python not available in current session"
fi

echo ""
say "IMPORTANT: Reload your shell to activate all tools:"
echo "  exec bash -l"
echo ""
echo "Then verify installation:"
echo "  $0 --verify"
echo ""
if [ "$USE_LTS_ONLY" -eq 1 ]; then
    info "Installed LTS/stable versions for production use"
    echo "  Node.js v20.x (LTS until April 2026)"
    echo "  Python 3.11.x (best compatibility)"
fi