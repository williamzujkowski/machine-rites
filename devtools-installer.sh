#!/usr/bin/env bash
# Developer Tools Installation Script for Ubuntu 24.04
# Installs: nvm, pyenv, poetry, uv, rust, go, docker, and more
set -euo pipefail

# ----- color codes & helpers -----
C_G="\033[1;32m"; C_Y="\033[1;33m"; C_R="\033[1;31m"; C_B="\033[1;34m"; C_N="\033[0m"
say(){ printf "${C_G}[+] %s${C_N}\n" "$*"; }
info(){ printf "${C_B}[i] %s${C_N}\n" "$*"; }
warn(){ printf "${C_Y}[!] %s${C_N}\n" "$*"; }
die(){ printf "${C_R}[✘] %s${C_N}\n" "$*" >&2; exit 1; }
ask(){ printf "${C_B}[?] %s${C_N}" "$*"; }

# ----- parse flags -----
UNATTENDED=0
VERBOSE=0
MINIMAL=0
SKIP_DOCKER=0
SKIP_RUST=0
SKIP_GO=0
SKIP_PYTHON=0
SKIP_NODE=0

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
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo "  -u, --unattended  Run without prompts"
      echo "  -v, --verbose     Enable verbose output"
      echo "  -m, --minimal     Install only essential tools (nvm, pyenv)"
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

# ----- XDG Base Directory support -----
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# ----- version checking helper -----
need_version() {
  local cmd="$1" min="$2" cur
  command -v "$cmd" >/dev/null || return 1
  cur="$("$cmd" --version 2>/dev/null | grep -Eo '[0-9]+(\.[0-9]+)+' | head -1 || true)"
  [ -z "$cur" ] && return 0  # Can't determine version, assume OK
  [ "$(printf '%s\n' "$min" "$cur" | sort -V | head -1)" = "$min" ] || return 1
}

# ----- confirmation helper -----
confirm() {
  [ "$UNATTENDED" -eq 1 ] && return 0
  local prompt="Continue?"
  read -rp "$prompt [y/N] " -n 1 -r
  echo
  [[ $REPLY =~ ^[Yy]$ ]]
}

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
# Node.js / nvm
# ============================================================
if [ "$SKIP_NODE" -eq 0 ]; then
  say "Setting up Node.js environment..."
  
  NVM_DIR="${NVM_DIR:-$XDG_DATA_HOME/nvm}"
  export NVM_DIR
  
  if [ ! -d "$NVM_DIR" ]; then
    say "Installing nvm..."
    # Create the directory first
    mkdir -p "$NVM_DIR"
    
    NVM_VERSION="v0.39.7"  # Update this as needed
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
    
    # Load nvm for this session (disable set -u temporarily)
    if [ -s "$NVM_DIR/nvm.sh" ]; then
      set +u
      \. "$NVM_DIR/nvm.sh"
      \. "$NVM_DIR/bash_completion" 2>/dev/null || true
      set -u
    fi
    
    # Install latest LTS Node
    say "Installing Node.js LTS..."
    nvm install --lts
    nvm use --lts
    nvm alias default 'lts/*'
    
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
    # Load nvm (disable set -u temporarily)
    if [ -s "$NVM_DIR/nvm.sh" ]; then
      set +u
      \. "$NVM_DIR/nvm.sh"
      set -u
      nvm use --lts >/dev/null 2>&1 || true
    fi
  fi
  
  # Verify installation
  if command -v node >/dev/null 2>&1; then
    info "Node.js: $(node --version)"
    info "npm: $(npm --version)"
  fi
fi

# ============================================================
# Python / pyenv
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
    
    # Install latest stable Python versions
    say "Installing Python versions..."
    PYTHON_VERSION="3.12.7"  # Update as needed
    pyenv install -s "$PYTHON_VERSION"
    pyenv global "$PYTHON_VERSION"
  else
    info "pyenv already installed at $PYENV_ROOT"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
  fi
  
  # Install Python tools via pipx
  if command -v pipx >/dev/null 2>&1; then
    say "Installing Python development tools..."
    
    # Core tools
    tools=(poetry uv ruff black mypy ipython httpie)
    [ "$MINIMAL" -eq 0 ] && tools+=(
      cookiecutter
      tox
      pre-commit
      pylint
      bandit
      virtualenv
      pipenv
      hatch
      pdm
    )
    
    for tool in "${tools[@]}"; do
      if ! command -v "$tool" >/dev/null 2>&1; then
        info "Installing $tool..."
        pipx install "$tool" || warn "Failed to install $tool"
      else
        info "$tool already installed"
      fi
    done
    
    # Ensure pipx path is in PATH
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

# ============================================================
# Rust / Cargo
# ============================================================
if [ "$SKIP_RUST" -eq 0 ] && [ "$MINIMAL" -eq 0 ]; then
  if ! command -v cargo >/dev/null 2>&1; then
    ask "Install Rust? "
    if confirm; then
      say "Installing Rust..."
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
      # shellcheck disable=SC1091
      . "$HOME/.cargo/env"
      
      # Install useful Rust tools
      say "Installing Rust tools..."
      cargo install \
        sccache \
        cargo-edit \
        cargo-watch \
        cargo-outdated \
        bacon || true
    fi
  else
    info "Rust already installed: $(rustc --version)"
  fi
fi

# ============================================================
# Go
# ============================================================
if [ "$SKIP_GO" -eq 0 ] && [ "$MINIMAL" -eq 0 ]; then
  if ! command -v go >/dev/null 2>&1; then
    ask "Install Go? "
    if confirm; then
      say "Installing Go..."
      GO_VERSION="1.23.2"  # Update as needed
      GO_TAR="go${GO_VERSION}.linux-${ARCH}.tar.gz"
      
      wget -q "https://go.dev/dl/${GO_TAR}" -O "/tmp/${GO_TAR}"
      sudo rm -rf /usr/local/go
      sudo tar -C /usr/local -xzf "/tmp/${GO_TAR}"
      rm "/tmp/${GO_TAR}"
      
      export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"
      
      # Install Go tools
      say "Installing Go tools..."
      go install golang.org/x/tools/gopls@latest
      go install github.com/go-delve/delve/cmd/dlv@latest
      go install golang.org/x/tools/cmd/goimports@latest
      go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
    fi
  else
    info "Go already installed: $(go version)"
  fi
fi

# ============================================================
# Docker
# ============================================================
if [ "$SKIP_DOCKER" -eq 0 ] && [ "$MINIMAL" -eq 0 ]; then
  if ! command -v docker >/dev/null 2>&1; then
    ask "Install Docker? "
    if confirm; then
      say "Installing Docker..."
      
      # Remove old versions
      for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        sudo apt-get remove -y "$pkg" 2>/dev/null || true
      done
      
      # Add Docker's official GPG key
      sudo install -m 0755 -d /etc/apt/keyrings
      sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
      sudo chmod a+r /etc/apt/keyrings/docker.asc
      
      # Add the repository
      echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      
      # Install Docker
      sudo apt-get update
      sudo apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
      
      # Add user to docker group
      sudo usermod -aG docker "$USER"
      info "You'll need to log out and back in for docker group membership to take effect"
      
      # Install lazydocker
      if command -v go >/dev/null 2>&1; then
        go install github.com/jesseduffield/lazydocker@latest
      fi
    fi
  else
    info "Docker already installed: $(docker --version)"
  fi
fi

# ============================================================
# Additional Developer Tools
# ============================================================
if [ "$MINIMAL" -eq 0 ]; then
  say "Installing additional developer tools..."
  
  # GitHub CLI
  if ! command -v gh >/dev/null 2>&1; then
    info "Installing GitHub CLI..."
    (type -p wget >/dev/null || (sudo apt-get update && sudo apt-get install wget -y)) \
      && sudo mkdir -p -m 755 /etc/apt/keyrings \
      && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
      && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
      && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
      && sudo apt-get update \
      && sudo apt-get install gh -y
  fi
  
  # lazygit
  if ! command -v lazygit >/dev/null 2>&1; then
    info "Installing lazygit..."
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | jq -r '.tag_name')
    curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION#v}_Linux_x86_64.tar.gz"
    tar xf /tmp/lazygit.tar.gz -C /tmp lazygit
    sudo install /tmp/lazygit /usr/local/bin
    rm -f /tmp/lazygit /tmp/lazygit.tar.gz
  fi
  
  # fzf
  if ! command -v fzf >/dev/null 2>&1; then
    info "Installing fzf..."
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --all --no-bash --no-zsh --no-fish || true
  fi
  
  # zoxide (better cd)
  if ! command -v zoxide >/dev/null 2>&1; then
    info "Installing zoxide..."
    curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
  fi
  
  # eza (better ls)
  if ! command -v eza >/dev/null 2>&1; then
    info "Installing eza..."
    sudo mkdir -p /etc/apt/keyrings
    wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
    sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
    sudo apt-get update
    sudo apt-get install -y eza
  fi
fi

# ============================================================
# Shell Integration
# ============================================================
say "Setting up shell integrations..."

# Create a devtools source file for bashrc.d
cat > "$HOME/.bashrc.d/45-devtools.sh" <<'DEVTOOLS'
#!/usr/bin/env bash
# Development tools configuration
# Generated by install_devtools.sh

# direnv
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook bash)"
fi

# zoxide
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init bash)"
fi

# fzf
if [ -f "$HOME/.fzf/bin/fzf" ]; then
  export PATH="$HOME/.fzf/bin:$PATH"
  # shellcheck disable=SC1091
  [ -f "$HOME/.fzf/shell/key-bindings.bash" ] && . "$HOME/.fzf/shell/key-bindings.bash"
  # shellcheck disable=SC1091
  [ -f "$HOME/.fzf/shell/completion.bash" ] && . "$HOME/.fzf/shell/completion.bash"
fi

# eza aliases (if installed)
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --icons'
  alias ll='eza -l --icons'
  alias la='eza -la --icons'
  alias lt='eza --tree --icons'
fi

# bat aliases (if installed)
if command -v batcat >/dev/null 2>&1; then
  alias cat='batcat'
  alias less='batcat --paging=always'
elif command -v bat >/dev/null 2>&1; then
  alias cat='bat'
  alias less='bat --paging=always'
fi

# fd alias (Ubuntu packages it as fdfind)
if command -v fdfind >/dev/null 2>&1; then
  alias fd='fdfind'
fi

# Docker aliases
if command -v docker >/dev/null 2>&1; then
  alias d='docker'
  alias dc='docker compose'
  alias dps='docker ps'
  alias dex='docker exec -it'
  alias dlog='docker logs -f'
  alias dprune='docker system prune -af'
fi

# Python aliases
alias py='python3'
alias ipy='ipython'
alias venv='python3 -m venv'
alias activate='source venv/bin/activate 2>/dev/null || source .venv/bin/activate'

# Git aliases (additional)
alias gcm='git checkout main 2>/dev/null || git checkout master'
alias gfo='git fetch origin'
alias grom='git rebase origin/main 2>/dev/null || git rebase origin/master'
alias grh='git reset --hard'
alias gclean='git clean -fd'

# Kubernetes aliases (if kubectl is installed)
if command -v kubectl >/dev/null 2>&1; then
  alias k='kubectl'
  alias kgp='kubectl get pods'
  alias kgs='kubectl get services'
  alias kgd='kubectl get deployments'
  alias kaf='kubectl apply -f'
  alias kdel='kubectl delete'
  alias klog='kubectl logs -f'
  alias kex='kubectl exec -it'
fi

# Go path
if [ -d "/usr/local/go/bin" ]; then
  export PATH="/usr/local/go/bin:$PATH"
fi
if [ -d "$HOME/go/bin" ]; then
  export PATH="$HOME/go/bin:$PATH"
fi

# Cargo/Rust
if [ -f "$HOME/.cargo/env" ]; then
  # shellcheck disable=SC1091
  . "$HOME/.cargo/env"
fi

# Set default editors
export EDITOR="${EDITOR:-vim}"
export VISUAL="${VISUAL:-$EDITOR}"

# Better history for development
export HISTIGNORE="ls:ll:cd:pwd:exit:date:* --help"
DEVTOOLS

chmod 0644 "$HOME/.bashrc.d/45-devtools.sh"

# ============================================================
# Verification
# ============================================================
say "Installation Summary:"
echo "===================="

# Check what got installed
tools=(
  "Node.js:node:--version"
  "npm:npm:--version" 
  "Python:python3:--version"
  "pip:pip3:--version"
  "Poetry:poetry:--version"
  "uv:uv:--version"
  "Rust:rustc:--version"
  "Go:go:version"
  "Docker:docker:--version"
  "GitHub CLI:gh:--version"
  "lazygit:lazygit:--version"
  "fzf:fzf:--version"
  "zoxide:zoxide:--version"
  "eza:eza:--version"
)

for tool_spec in "${tools[@]}"; do
  IFS=: read -r name cmd flag <<< "$tool_spec"
  if command -v "$cmd" >/dev/null 2>&1; then
    version=$($cmd $flag 2>&1 | head -1 || echo "installed")
    printf "✓ %-12s : %s\n" "$name" "${version:0:50}"
  else
    printf "✗ %-12s : not installed\n" "$name"
  fi
done

echo ""
say "Development tools installation complete!"
echo ""
echo "Next steps:"
echo "  1. Reload shell: exec bash -l"
echo "  2. Test Node: nvm list && node --version"
echo "  3. Test Python: pyenv versions && python3 --version"
echo "  4. Configure GitHub CLI: gh auth login"
[ "$SKIP_DOCKER" -eq 0 ] && echo "  5. Docker requires logout/login for group membership"
echo ""
echo "Optional configurations:"
echo "  - Set EDITOR environment variable in ~/.bashrc.d/99-local.sh"
echo "  - Configure git: git config --global init.defaultBranch main"
echo "  - Set up SSH keys: ensure_ssh_key (from bootstrap script)"
echo ""
info "Shell integrations added to: ~/.bashrc.d/45-devtools.sh"