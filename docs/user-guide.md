# Machine Rites User Guide

## Table of Contents

1. [Getting Started](#getting-started)
2. [Basic Usage](#basic-usage)
3. [Advanced Configuration](#advanced-configuration)
4. [Secret Management](#secret-management)
5. [SSH Management](#ssh-management)
6. [Customization](#customization)
7. [Troubleshooting](#troubleshooting)
8. [Development](#development)

## Getting Started

### Prerequisites

- Ubuntu 18.04+ or macOS 10.15+
- Bash 4.0+
- Git 2.0+
- Internet connection for initial setup

### Installation

#### Method 1: Quick Install (Recommended)

```bash
# Clone repository
git clone https://github.com/williamzujkowski/machine-rites.git ~/git/machine-rites
cd ~/git/machine-rites

# Run interactive bootstrap
./bootstrap_machine_rites.sh

# Reload shell
exec bash -l
```

#### Method 2: Unattended Install (CI/Automation)

```bash
# For automated deployment
./bootstrap_machine_rites.sh --unattended

# With verbose output for debugging
./bootstrap_machine_rites.sh --unattended --verbose
```

#### Method 3: Custom Install

```bash
# Skip backup (not recommended)
./bootstrap_machine_rites.sh --skip-backup

# Get help
./bootstrap_machine_rites.sh --help
```

### Post-Installation Verification

```bash
# Check system health
make doctor

# Should show all green checkmarks
# [System] ✓ Ubuntu 24.04
# [Tools] ✓ All required tools installed
# [SSH] ✓ Agent running
# [GPG] ✓ Keys available
```

## Basic Usage

### Daily Commands

```bash
# System health check
make doctor

# Update to latest version
make update

# Show all available commands
make help

# Check what would be changed
make diff

# Apply pending changes
make apply
```

### Directory Structure

After installation, your home directory will have:

```
~/
├── .bashrc                    # Main bash configuration
├── .bashrc.d/                 # Modular configuration files
├── .config/chezmoi/           # Chezmoi configuration
├── .local/state/ssh/          # SSH agent state
└── git/machine-rites/         # Source repository
```

## Advanced Configuration

### Bashrc Modules

The modular bashrc system loads files in order:

```bash
~/.bashrc.d/
├── 00-hygiene.sh          # Shell options, PATH setup
├── 10-bash-completion.sh  # Bash completion
├── 30-secrets.sh          # Secret management
├── 35-ssh.sh              # SSH agent management
├── 40-tools.sh            # Development tools
├── 41-completions.sh      # Tool completions
├── 50-prompt.sh           # Default prompt
├── 55-starship.sh         # Starship prompt (if installed)
├── 60-aliases.sh          # Aliases and shortcuts
└── 99-local.sh            # Local overrides (gitignored)
```

### Adding Custom Modules

Create a new module:

```bash
# Create custom module
cat > ~/.bashrc.d/70-custom.sh <<'EOF'
#!/usr/bin/env bash
# shellcheck shell=bash
# Custom configuration

# Example: Custom aliases
alias myproject='cd ~/projects/myproject'
alias ll='ls -la'

# Example: Custom environment variables
export CUSTOM_VAR="value"

# Example: Custom function
my_function() {
    echo "Custom function called with: $*"
}
EOF

# Add to chezmoi for tracking
chezmoi add ~/.bashrc.d/70-custom.sh

# Reload shell to test
exec bash -l
```

### Chezmoi Templates

Customize templates in the source directory:

```bash
cd ~/git/machine-rites/.chezmoi

# Example: Conditional configuration
cat > dot_bashrc.d/70-work.sh.tmpl <<'EOF'
{{- if eq .chezmoi.hostname "work-laptop" }}
#!/usr/bin/env bash
# shellcheck shell=bash
# Work-specific configuration

export WORK_PROXY="http://proxy.company.com:8080"
alias vpn='sudo openvpn /etc/openvpn/work.conf'
{{- end }}
EOF

# Apply changes
chezmoi apply
```

## Secret Management

### Initial Setup

```bash
# Generate GPG key (if needed)
make gpg-setup

# Initialize pass store
pass init <your-email@domain.com>

# Verify setup
pass ls
```

### Adding Secrets

```bash
# Method 1: Interactive entry
pass insert personal/github_token

# Method 2: From file
echo "ghp_xxxxxxxxxxxx" | pass insert -m personal/github_token

# Method 3: Using make target
make secrets-add KEY=github_token
```

### Using Secrets

Secrets are automatically exported as environment variables:

```bash
# Secret: personal/github_token
# Becomes: GITHUB_TOKEN environment variable

echo $GITHUB_TOKEN  # Access in scripts
curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user
```

### Secret Organization

Organize secrets hierarchically:

```bash
personal/
├── github_token
├── aws_access_key
└── aws_secret_key

work/
├── gitlab_token
├── jira_token
└── vpn_password

shared/
├── wifi_password
└── database_url
```

### Backup and Restore

```bash
# Create encrypted backup
make secrets-backup

# Backup is stored in backups/pass/
ls -la backups/pass/

# Restore from backup (if needed)
pass git init
pass git remote add origin <backup-repo>
pass git pull origin main
```

## SSH Management

### Key Generation

```bash
# Generate new SSH key
make ssh-setup

# Or manually
ssh-keygen -t ed25519 -C "your-email@domain.com"
```

### Agent Management

The SSH agent is automatically managed:

```bash
# Check agent status
ssh-add -l

# Should show your keys loaded
# 256 SHA256:... your-email@domain.com (ED25519)

# Agent state persisted in
ls -la ~/.local/state/ssh/agent.env
```

### Multiple Keys

```bash
# Add additional keys
ssh-add ~/.ssh/id_rsa_work
ssh-add ~/.ssh/id_ed25519_personal

# List all loaded keys
ssh-add -l

# Remove specific key
ssh-add -d ~/.ssh/id_rsa_work

# Remove all keys
ssh-add -D
```

### SSH Config

Create `~/.ssh/config` for host-specific settings:

```bash
# Personal GitHub
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

# Work GitLab
Host gitlab.company.com
    HostName gitlab.company.com
    User git
    IdentityFile ~/.ssh/id_rsa_work
    IdentitiesOnly yes

# Work server
Host work-server
    HostName server.company.com
    User myusername
    IdentityFile ~/.ssh/id_rsa_work
    ProxyJump bastion.company.com
```

## Customization

### Local Overrides

Use `~/.bashrc.d/99-local.sh` for machine-specific settings:

```bash
# This file is gitignored - won't be tracked
cat > ~/.bashrc.d/99-local.sh <<'EOF'
#!/usr/bin/env bash
# shellcheck shell=bash
# Local machine overrides

# Machine-specific environment
export EDITOR=nvim
export BROWSER=firefox
export TERMINAL=alacritty

# Local aliases
alias myvm='ssh user@192.168.1.100'
alias backup='rsync -av ~/Documents/ /mnt/backup/'

# Local PATH additions
export PATH="$HOME/custom/bin:$PATH"
export PATH="/opt/local/bin:$PATH"

# Function for this machine
local_function() {
    echo "This function only exists on this machine"
}
EOF

# Reload to test
exec bash -l
```

### Prompt Customization

#### Option 1: Starship (Recommended)

```bash
# Install Starship
curl -sS https://starship.rs/install.sh | sh

# Customize prompt
$EDITOR ~/.config/starship.toml

# Example customization
cat > ~/.config/starship.toml <<'EOF'
[character]
success_symbol = "[➜](bold green)"
error_symbol = "[➜](bold red)"

[git_branch]
symbol = "🌱 "

[nodejs]
symbol = "⬢ "
EOF
```

#### Option 2: Custom PS1

```bash
# Add to ~/.bashrc.d/99-local.sh
export PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
```

### Tool Integration

#### Node.js/NVM

```bash
# NVM is automatically configured
# Use specific Node version
nvm install 18
nvm use 18

# Set default
nvm alias default 18
```

#### Python/Pyenv

```bash
# Pyenv is automatically configured
# Install Python version
pyenv install 3.11.0
pyenv global 3.11.0

# Create virtual environment
python -m venv myproject
source myproject/bin/activate
```

#### Docker

```bash
# Docker completion is automatic
# Add useful aliases to ~/.bashrc.d/99-local.sh
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dclean='docker system prune -f'
alias dlog='docker logs -f'
```

## Troubleshooting

### Common Issues

#### SSH Agent Not Working

```bash
# Check if agent is running
ssh-add -l

# If "Could not open a connection":
rm -f ~/.local/state/ssh/agent.env
exec bash -l

# Verify keys are loaded
ssh-add -l
```

#### GPG Issues

```bash
# Check GPG keys
gpg --list-secret-keys

# If no keys found:
make gpg-setup

# Test GPG functionality
echo "test" | gpg --encrypt -r your-email@domain.com | gpg --decrypt
```

#### Pass Store Issues

```bash
# Check pass status
pass ls

# If "password store is empty":
pass init your-email@domain.com

# Test pass functionality
pass insert test/example
pass show test/example
pass rm test/example
```

#### Chezmoi Issues

```bash
# Check chezmoi status
chezmoi status

# See what would change
chezmoi diff

# Force re-apply
chezmoi apply --force

# Re-initialize if needed
chezmoi init --apply ~/git/machine-rites
```

### Debug Mode

Enable debug output for troubleshooting:

```bash
# Debug bootstrap
./bootstrap_machine_rites.sh --verbose

# Debug specific module
bash -x ~/.bashrc.d/35-ssh.sh

# Debug chezmoi
chezmoi apply --verbose
```

### Health Check Details

```bash
# Run comprehensive health check
make doctor

# Check specific tool versions
make check-versions

# Verify all pre-commit hooks
pre-commit run --all-files
```

## Development

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes following the guidelines
4. Test thoroughly
5. Submit a pull request

### Testing

```bash
# Run all tests
make test

# Run specific test suite
cd tests/lib && ./run_all_tests.sh

# Run individual test
cd tests/lib && ./test_common.sh

# Check shell syntax
make lint
```

### Code Standards

#### Shell Scripts

- Use shellcheck pragmas
- Follow bash best practices
- Include comprehensive error handling
- Document all functions

```bash
#!/usr/bin/env bash
# shellcheck shell=bash
# Description of script purpose

set -euo pipefail

# Function documentation
# Usage: my_function <arg1> <arg2>
# Description: What this function does
# Returns: 0 on success, 1 on failure
my_function() {
    local arg1="${1:-}"
    local arg2="${2:-}"

    if [[ -z "$arg1" ]]; then
        echo "Error: arg1 required" >&2
        return 1
    fi

    # Implementation
    echo "Processing $arg1 and $arg2"
}
```

#### Library Functions

- Return proper exit codes
- Handle edge cases
- Include validation
- Use consistent naming

```bash
# Example from lib/validation.sh
validate_email() {
    local email="${1:-}"

    if [[ -z "$email" ]]; then
        return 1
    fi

    if [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}
```

### Release Process

1. Update version in README.md
2. Update CHANGELOG.md
3. Test on clean system
4. Tag release
5. Update documentation

### Getting Help

- Read documentation in `docs/`
- Check troubleshooting section
- Run `make doctor` for health check
- Open an issue on GitHub
- Check existing issues for solutions

---

For more detailed information, see:
- [Architecture Decisions](architecture-decisions.md)
- [Troubleshooting Guide](troubleshooting.md)
- [API Documentation](../lib/README.md)