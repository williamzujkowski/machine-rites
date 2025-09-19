#!/usr/bin/env bash
# Test Fixtures and Data - machine-rites testing framework
# Provides common test data, configurations, and mock objects
set -euo pipefail

# Test data directory
readonly TEST_FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_ROOT="$(cd "$TEST_FIXTURES_DIR/.." && pwd)"

# Test Configuration Data
export TEST_USER_EMAIL="test@example.com"
export TEST_USER_NAME="Test User"
export TEST_USER_EDITOR="nano"
export TEST_GPG_KEY_ID="ABCDEF1234567890"
export TEST_HOSTNAME="test-machine"

# Mock System Information
mock_system_info() {
    cat << 'EOF'
{
    "os": "linux",
    "distribution": "ubuntu",
    "version": "24.04",
    "codename": "noble",
    "architecture": "x86_64",
    "kernel": "6.8.0-31-generic",
    "memory_gb": 8,
    "disk_gb": 256,
    "cpu_cores": 4
}
EOF
}

# Sample Configuration Files
create_sample_bashrc() {
    local output_file="$1"
    cat > "$output_file" << 'EOF'
# Sample .bashrc for testing
export PATH="$HOME/.local/bin:$PATH"
export EDITOR="nano"

# Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Functions
function mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Machine-rites configuration
export MACHINE_RITES_VERSION="1.0.0"
export DOTFILES_MANAGED=true

# Source bashrc.d files
if [ -d "$HOME/.bashrc.d" ]; then
    for rc in "$HOME/.bashrc.d"/*.sh; do
        if [ -r "$rc" ]; then
            source "$rc"
        fi
    done
fi
EOF
}

create_sample_gitconfig() {
    local output_file="$1"
    cat > "$output_file" << 'EOF'
[user]
    name = Test User
    email = test@example.com
    signingkey = ABCDEF1234567890

[core]
    editor = nano
    autocrlf = input
    quotepath = false

[init]
    defaultBranch = main

[pull]
    rebase = false

[push]
    default = simple
    autoSetupRemote = true

[commit]
    gpgsign = true

[tag]
    gpgsign = true

[alias]
    st = status
    co = checkout
    br = branch
    ci = commit
    lg = log --oneline --graph --decorate
    last = log -1 HEAD
    unstage = reset HEAD --

[color]
    ui = auto

[diff]
    tool = vimdiff

[merge]
    tool = vimdiff
EOF
}

create_sample_vimrc() {
    local output_file="$1"
    cat > "$output_file" << 'EOF'
" Sample .vimrc for testing
set nocompatible
set number
set relativenumber
set tabstop=4
set shiftwidth=4
set expandtab
set autoindent
set smartindent
set hlsearch
set incsearch
set ignorecase
set smartcase
set wildmenu
set wildmode=list:longest
set backspace=indent,eol,start
set ruler
set showcmd
set laststatus=2
set encoding=utf-8

" Enable syntax highlighting
syntax enable

" Color scheme
colorscheme default

" Enable file type detection
filetype plugin indent on

" Key mappings
let mapleader = ","
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>wq :wq<CR>

" Clear search highlighting
nnoremap <leader>/ :nohlsearch<CR>

" Window navigation
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l
EOF
}

create_sample_chezmoi_config() {
    local output_file="$1"
    cat > "$output_file" << 'EOF'
[data]
    email = "test@example.com"
    name = "Test User"
    editor = "nano"
    hostname = "test-machine"
    os = "linux"
    arch = "x86_64"

[edit]
    command = "nano"

[merge]
    command = "vimdiff"

[git]
    autoCommit = true
    autoPush = false

[cd]
    command = "cd"

[diff]
    pager = "less"

[status]
    exclude = ["scripts"]
EOF
}

create_sample_ssh_config() {
    local output_file="$1"
    cat > "$output_file" << 'EOF'
# Sample SSH config for testing
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
    Compression yes
    ControlMaster auto
    ControlPath ~/.ssh/controlmasters/%r@%h:%p
    ControlPersist 10m

Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host gitlab.com
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host test-server
    HostName test.example.com
    User testuser
    Port 2222
    IdentityFile ~/.ssh/id_rsa
EOF
}

# Mock Package Lists
get_essential_packages() {
    cat << 'EOF'
curl
wget
git
gnupg
pass
age
ssh
build-essential
software-properties-common
apt-transport-https
ca-certificates
lsb-release
EOF
}

get_development_packages() {
    cat << 'EOF'
nodejs
npm
python3
python3-pip
golang-go
rustc
docker.io
docker-compose
code
vim
neovim
tmux
zsh
fish
EOF
}

get_optional_packages() {
    cat << 'EOF'
tree
htop
btop
neofetch
bat
fd-find
ripgrep
exa
starship
fzf
jq
yq
tldr
thefuck
ncdu
EOF
}

# Mock Environment Configurations
create_test_environment() {
    local env_dir="$1"
    local env_type="${2:-basic}"

    mkdir -p "$env_dir"/{home,etc,usr/bin,tmp,var/lib}

    case "$env_type" in
        "basic")
            create_basic_test_environment "$env_dir"
            ;;
        "complex")
            create_complex_test_environment "$env_dir"
            ;;
        "minimal")
            create_minimal_test_environment "$env_dir"
            ;;
        *)
            create_basic_test_environment "$env_dir"
            ;;
    esac
}

create_basic_test_environment() {
    local env_dir="$1"

    # Create basic directory structure
    mkdir -p "$env_dir/home"/{.config,.local/bin,.bashrc.d,.ssh,.gnupg}

    # Create sample files
    create_sample_bashrc "$env_dir/home/.bashrc"
    create_sample_gitconfig "$env_dir/home/.gitconfig"
    create_sample_vimrc "$env_dir/home/.vimrc"

    # Create system files
    echo "ubuntu" > "$env_dir/etc/hostname"
    echo "test@example.com" > "$env_dir/etc/email"
}

create_complex_test_environment() {
    local env_dir="$1"

    # Start with basic environment
    create_basic_test_environment "$env_dir"

    # Add complex configurations
    mkdir -p "$env_dir/home"/{.config/chezmoi,.password-store,.cache}

    create_sample_chezmoi_config "$env_dir/home/.config/chezmoi/chezmoi.toml"
    create_sample_ssh_config "$env_dir/home/.ssh/config"

    # Create multiple bashrc.d files
    echo "export DEV_TOOLS=true" > "$env_dir/home/.bashrc.d/10-dev.sh"
    echo "export SSH_AGENT_PID=\$\$" > "$env_dir/home/.bashrc.d/20-ssh.sh"
    echo "alias gst='git status'" > "$env_dir/home/.bashrc.d/30-git.sh"

    # Create GPG files
    echo "mock gpg public key" > "$env_dir/home/.gnupg/pubring.kbx"
    echo "mock gpg private key" > "$env_dir/home/.gnupg/secring.gpg"

    # Create password store
    mkdir -p "$env_dir/home/.password-store/personal"
    echo "mock_token" > "$env_dir/home/.password-store/personal/github_token.gpg"
}

create_minimal_test_environment() {
    local env_dir="$1"

    # Minimal setup - just essential directories
    mkdir -p "$env_dir/home"
    echo "# Minimal bashrc" > "$env_dir/home/.bashrc"
}

# Test Data Generators
generate_large_file() {
    local output_file="$1"
    local size_mb="${2:-1}"

    dd if=/dev/zero of="$output_file" bs=1M count="$size_mb" 2>/dev/null
}

generate_test_users() {
    cat << 'EOF'
user1:test1@example.com:User One:vim
user2:test2@example.com:User Two:nano
user3:test3@example.com:User Three:code
user4:test4@example.com:User Four:emacs
user5:test5@example.com:User Five:micro
EOF
}

generate_git_history() {
    local repo_dir="$1"
    local commit_count="${2:-10}"

    mkdir -p "$repo_dir"
    cd "$repo_dir"

    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"

    for ((i=1; i<=commit_count; i++)); do
        echo "Commit $i content" > "file_$i.txt"
        git add "file_$i.txt"
        git commit -q -m "Commit $i: Add file_$i.txt"
    done

    cd - >/dev/null
}

# Mock Command Generators
create_mock_apt() {
    local bin_dir="$1"
    cat > "$bin_dir/apt" << 'EOF'
#!/bin/bash
case "$1" in
    "update")
        echo "Reading package lists... Done"
        ;;
    "install")
        shift
        for pkg in "$@"; do
            [[ "$pkg" == "-y" ]] && continue
            echo "Setting up $pkg..."
        done
        ;;
    "list")
        echo "Listing... Done"
        ;;
    *)
        echo "apt: $*"
        ;;
esac
EOF
    chmod +x "$bin_dir/apt"
}

create_mock_git() {
    local bin_dir="$1"
    cat > "$bin_dir/git" << 'EOF'
#!/bin/bash
case "$1" in
    "config")
        echo "git config: $*"
        ;;
    "--version")
        echo "git version 2.40.1"
        ;;
    *)
        echo "git: $*"
        ;;
esac
EOF
    chmod +x "$bin_dir/git"
}

create_mock_chezmoi() {
    local bin_dir="$1"
    cat > "$bin_dir/chezmoi" << 'EOF'
#!/bin/bash
case "$1" in
    "init")
        echo "chezmoi: initialized"
        ;;
    "apply")
        echo "chezmoi: applied"
        ;;
    "--version")
        echo "chezmoi version 2.46.1"
        ;;
    *)
        echo "chezmoi: $*"
        ;;
esac
EOF
    chmod +x "$bin_dir/chezmoi"
}

# Validation Functions
validate_test_environment() {
    local env_dir="$1"

    local required_dirs=(
        "$env_dir/home"
        "$env_dir/home/.config"
        "$env_dir/home/.local/bin"
    )

    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            echo "Missing required directory: $dir"
            return 1
        fi
    done

    local required_files=(
        "$env_dir/home/.bashrc"
        "$env_dir/home/.gitconfig"
    )

    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            echo "Missing required file: $file"
            return 1
        fi
    done

    return 0
}

validate_configuration_file() {
    local config_file="$1"
    local config_type="$2"

    case "$config_type" in
        "bashrc")
            grep -q "export PATH" "$config_file" || return 1
            ;;
        "gitconfig")
            grep -q "\[user\]" "$config_file" || return 1
            grep -q "email" "$config_file" || return 1
            ;;
        "chezmoi")
            grep -q "\[data\]" "$config_file" || return 1
            ;;
        *)
            return 1
            ;;
    esac

    return 0
}

# Cleanup Functions
cleanup_test_data() {
    local cleanup_dir="$1"

    if [[ -d "$cleanup_dir" ]] && [[ "$cleanup_dir" == *"/test"* ]]; then
        rm -rf "$cleanup_dir"
        echo "Cleaned up test data: $cleanup_dir"
    else
        echo "Safety check failed: will not clean $cleanup_dir"
        return 1
    fi
}

# Export functions for use in tests
export -f mock_system_info
export -f create_sample_bashrc create_sample_gitconfig create_sample_vimrc
export -f create_sample_chezmoi_config create_sample_ssh_config
export -f get_essential_packages get_development_packages get_optional_packages
export -f create_test_environment validate_test_environment
export -f create_mock_apt create_mock_git create_mock_chezmoi
export -f generate_large_file generate_test_users generate_git_history
export -f validate_configuration_file cleanup_test_data

# Main function for standalone usage
main() {
    local command="${1:-help}"

    case "$command" in
        "create-env")
            create_test_environment "${2:-/tmp/test_env}" "${3:-basic}"
            echo "Test environment created: ${2:-/tmp/test_env}"
            ;;
        "validate-env")
            validate_test_environment "${2:-/tmp/test_env}"
            echo "Test environment validation: OK"
            ;;
        "cleanup")
            cleanup_test_data "${2:-/tmp/test_env}"
            ;;
        "help"|*)
            cat << 'EOF'
Test Fixtures and Data Generator

Usage:
  create-env <dir> [type]    Create test environment (basic|complex|minimal)
  validate-env <dir>         Validate test environment
  cleanup <dir>              Clean up test data
  help                       Show this help

Available functions:
  - mock_system_info()
  - create_sample_*()
  - create_test_environment()
  - create_mock_*()
  - generate_*()
  - validate_*()
  - cleanup_test_data()
EOF
            ;;
    esac
}

# Run main if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi