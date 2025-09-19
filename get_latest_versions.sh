#!/usr/bin/env bash
# Fetch and display latest stable versions of development tools - with error handling
set -euo pipefail

C_G="\033[1;32m"; C_Y="\033[1;33m"; C_B="\033[1;34m"; C_N="\033[0m"
info(){ printf "${C_B}[i] %s${C_N}\n" "$*"; }
say(){ printf "${C_G}[+] %s${C_N}\n" "$*"; }
warn(){ printf "${C_Y}[!] %s${C_N}\n" "$*"; }

# Helper to get latest GitHub release with error handling
get_github_latest() {
    local repo="$1"
    local version
    version=$(curl -s "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | \
        grep -Po '"tag_name": "\K[^"]*' 2>/dev/null || echo "")
    
    if [ -z "$version" ]; then
        echo "v0.0.0"  # fallback
    else
        echo "$version"
    fi
}

say "Fetching latest stable versions (with fallbacks)..."
echo ""

# Initialize variables with defaults
NVM_LATEST="v0.40.3"
NODE_LTS="v22.19.0"
PYENV_LATEST="v2.6.7"
PYTHON_LATEST="3.12.7"
GO_LATEST="1.23.2"
RUST_LATEST="1.82.0"

# Node.js / nvm
info "Node.js ecosystem:"
if NVM_TMP=$(get_github_latest "nvm-sh/nvm"); then
    [ "$NVM_TMP" != "v0.0.0" ] && NVM_LATEST="$NVM_TMP"
fi
echo "  nvm: $NVM_LATEST"

if NODE_TMP=$(curl -s https://nodejs.org/dist/index.json 2>/dev/null | \
    jq -r '.[] | select(.lts != false) | .version' 2>/dev/null | head -1); then
    [ -n "$NODE_TMP" ] && NODE_LTS="$NODE_TMP"
fi
echo "  Node.js LTS: $NODE_LTS"

# Python
info "Python ecosystem:"
if PYENV_TMP=$(get_github_latest "pyenv/pyenv"); then
    [ "$PYENV_TMP" != "v0.0.0" ] && PYENV_LATEST="$PYENV_TMP"
fi
echo "  pyenv: $PYENV_LATEST"

# Try to get Python version from pyenv if available, otherwise use default
if command -v pyenv >/dev/null 2>&1; then
    if PYTHON_TMP=$(pyenv install --list 2>/dev/null | grep -E '^\s*3\.\d+\.\d+$' | tail -1 | xargs); then
        [ -n "$PYTHON_TMP" ] && PYTHON_LATEST="$PYTHON_TMP"
    fi
else
    # Fallback: try from python.org
    if PYTHON_TMP=$(curl -s https://www.python.org/ftp/python/ 2>/dev/null | \
        grep -Po '3\.\d+\.\d+' | sort -V | tail -1); then
        [ -n "$PYTHON_TMP" ] && PYTHON_LATEST="$PYTHON_TMP"
    fi
fi
echo "  Python stable: $PYTHON_LATEST"

# Go
info "Go:"
if GO_TMP=$(curl -s https://go.dev/VERSION?m=text 2>/dev/null | head -1 | sed 's/go//'); then
    [ -n "$GO_TMP" ] && GO_LATEST="$GO_TMP"
fi
echo "  Go stable: $GO_LATEST"

# Rust
info "Rust:"
if command -v rustc >/dev/null 2>&1; then
    RUST_TMP=$(rustc --version | grep -Po '\d+\.\d+\.\d+' || echo "")
    [ -n "$RUST_TMP" ] && RUST_LATEST="$RUST_TMP"
fi
echo "  Rust stable: $RUST_LATEST"

# CLI Tools - these are optional, don't fail if they error
info "CLI Tools (best effort):"
echo "  lazygit: $(get_github_latest "jesseduffield/lazygit")"
echo "  fzf: $(get_github_latest "junegunn/fzf")"
echo "  zoxide: $(get_github_latest "ajeetdsouza/zoxide")"
echo "  gh CLI: $(get_github_latest "cli/cli")"
echo "  starship: $(get_github_latest "starship/starship")"

echo ""
say "Creating version file with fetched/default versions..."

# Generate the version file with what we got
cat > devtools_versions.sh << EOF
#!/usr/bin/env bash
# Auto-generated version file - $(date +%Y-%m-%d)
# Source this file to get latest versions

export NVM_VERSION="${NVM_LATEST}"
export NODE_LTS_VERSION="${NODE_LTS}"
export PYENV_VERSION="${PYENV_LATEST}"
export PYTHON_VERSION="${PYTHON_LATEST}"
export GO_VERSION="${GO_LATEST}"
export RUST_VERSION="${RUST_LATEST}"

# Function to dynamically get GitHub latest version
get_github_latest() {
    local repo="\$1"
    curl -s "https://api.github.com/repos/\$repo/releases/latest" 2>/dev/null | \\
        grep -Po '"tag_name": "\\K[^"]*' 2>/dev/null || echo "unknown"
}
EOF

info "Version file created: devtools_versions.sh"
echo ""
say "Summary:"
echo "  NVM: $NVM_LATEST"
echo "  Node LTS: $NODE_LTS"
echo "  Python: $PYTHON_LATEST"
echo "  Go: $GO_LATEST"
echo ""
echo "You can now:"
echo "  source ./devtools_versions.sh"
echo "  ./devtools-installer.sh"