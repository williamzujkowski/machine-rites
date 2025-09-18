# machine-rites

![CI](https://github.com/williamzujkowski/machine-rites/actions/workflows/ci.yml/badge.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-orange.svg)
![Bash](https://img.shields.io/badge/Bash-5.0+-green.svg)

Production-grade dotfiles management with intelligent SSH agent handling, atomic operations, and comprehensive rollback support.

## ✨ Key Features

- **🔧 Modular bash configuration** - Organized `~/.bashrc.d/` modules with proper shellcheck pragmas
- **🔒 GPG-encrypted secrets** - Pass integration with automatic migration from plaintext
- **🔑 Smart SSH agent** - Single agent reused across sessions (no multiplication)
- **📦 Chezmoi-powered** - Declarative dotfiles with dynamic templating
- **⚡ Atomic operations** - Safe file writes with automatic rollback on failure
- **🚫 Secret scanning** - Pre-commit hooks with gitleaks + shellcheck
- **✅ CI/CD pipeline** - GitHub Actions with proper PR comment permissions
- **🔄 One-command rollback** - Time-stamped backups with restore scripts
- **📊 Health monitoring** - Comprehensive doctor script with actionable output
- **🎯 XDG compliance** - Full Base Directory specification support
- **🚀 Version checking** - Minimum version requirements for critical tools

## 🚀 Quick Start

### Bootstrap (First Time)

```bash
# Clone and bootstrap
git clone https://github.com/williamzujkowski/machine-rites.git ~/git/machine-rites
cd ~/git/machine-rites
chmod +x bootstrap_machine_rites.sh

# Interactive mode (default)
./bootstrap_machine_rites.sh

# OR unattended mode
./bootstrap_machine_rites.sh --unattended

# OR with verbose debugging
./bootstrap_machine_rites.sh --verbose

# Reload shell
exec bash -l
```

### Daily Usage

```bash
# Check system health
make doctor

# Update to latest
make update

# Show all commands
make help
```

## 📋 Bootstrap Options

```bash
./bootstrap_machine_rites.sh [OPTIONS]

Options:
  -u, --unattended    Run without prompts (CI/CD friendly)
  -v, --verbose       Enable debug output
  --skip-backup       Skip backup step (dangerous!)
  -h, --help          Show help message
```

## 🏗️ Architecture

```
~/
├── .bashrc                       # Main loader with shellcheck pragmas
├── .bashrc.d/                    # Modular configs (numbered for order)
│   ├── 00-hygiene.sh            # Shell options, PATH, XDG setup
│   ├── 10-bash-completion.sh    # Completions
│   ├── 20-oh-my-bash.sh         # Optional OMB integration
│   ├── 30-secrets.sh            # Pass/GPG secrets management
│   ├── 35-ssh.sh                # Smart SSH agent (single instance)
│   ├── 40-tools.sh              # Tool configs (nvm, pyenv, cargo)
│   ├── 50-prompt.sh             # Git-aware prompt (Ubuntu paths)
│   ├── 60-aliases.sh            # Aliases and shortcuts
│   └── 99-local.sh              # Local overrides (gitignored)
│
├── .config/
│   ├── chezmoi/
│   │   └── chezmoi.toml         # Dynamic config with git detection
│   └── secrets.env              # Legacy secrets (auto-migrated)
│
├── .local/
│   ├── state/ssh/               # SSH agent persistence (XDG)
│   └── share/nvm/               # NVM with XDG support
│
└── git/machine-rites/
    ├── .chezmoi/                # Chezmoi source directory
    ├── .github/workflows/       # CI with proper permissions
    ├── .shellcheckrc            # ShellCheck configuration
    ├── .gitleaks.toml           # Custom secret patterns
    ├── .pre-commit-config.yaml  # Gitleaks + shellcheck hooks
    ├── Makefile                 # Task automation
    ├── bootstrap_machine_rites.sh
    ├── tools/
    │   ├── doctor.sh           # Health checks
    │   ├── update.sh           # Pull and apply
    │   └── backup-pass.sh      # GPG-encrypted backups
    └── backups/
        └── pass/               # Encrypted pass backups
```

## 🔑 Critical Fixes Included

### SSH Agent Management
- **Problem**: Multiple agents spawned per session
- **Solution**: Single persistent agent via XDG state directory
- **Result**: No more orphaned processes, consistent key availability

### Dynamic Configuration
- **Problem**: Hardcoded email addresses
- **Solution**: Auto-detection from git config with fallback prompts
- **Result**: Works correctly for any user

### ShellCheck Compliance
- **Problem**: SC1090/SC1091 warnings for dynamic sources
- **Solution**: Proper pragma directives in all shell files
- **Result**: Clean CI runs without false positives

### CI/CD Permissions
- **Problem**: Gitleaks couldn't comment on PRs
- **Solution**: Added `pull-requests: write` permission
- **Result**: Security feedback directly in PR comments

### Atomic File Operations
- **Problem**: Partial writes during failures
- **Solution**: Write to temp file, then atomic rename
- **Result**: No corrupted configs on interrupt

## 🛠️ Make Commands

```bash
make help                 # Show all commands
make install              # Run bootstrap
make install-unattended   # Unattended bootstrap
make update               # Pull and apply changes
make doctor               # Health check
make test                 # Run all tests
make lint                 # ShellCheck all scripts
make backup               # Backup pass store

# Secrets management
make secrets-add KEY=github_token  # Add secret
make secrets-list                   # List all secrets
make secrets-backup                 # Encrypted backup

# Development
make diff                 # Show pending changes
make status               # Chezmoi status
make apply                # Apply changes
make push                 # Test and push to git

# Maintenance
make clean                # Remove old backups
make rollback             # Show rollback options
make check-versions       # Verify tool versions
make ssh-setup            # Generate SSH key
make gpg-setup            # Setup GPG for pass
```

## 🔐 Security Features

### Secret Management
```bash
# Automatic migration from plaintext
# ~/.config/secrets.env → pass (GPG-encrypted)

# Add new secret
pass insert personal/github_token

# Use in scripts (auto-exported as GITHUB_TOKEN)
echo $GITHUB_TOKEN
```

### Pre-commit Hooks
- **Gitleaks**: Scans for secrets before commit
- **ShellCheck**: Static analysis for shell scripts
- Custom patterns in `.gitleaks.toml`

### Rollback Mechanism
```bash
# Every bootstrap creates timestamped backup
~/dotfiles-backup-20240115-143022/

# One-command restore
~/dotfiles-backup-20240115-143022/rollback.sh
```

## 🚦 CI/CD Pipeline

GitHub Actions workflow includes:

1. **Chezmoi validation** - Dry-run apply
2. **ShellCheck** - All shell scripts
3. **Pre-commit hooks** - Local and CI consistency
4. **Gitleaks scanning** - With PR comments
5. **Proper permissions** - Can comment on PRs

## 📝 Customization

### Local Overrides

Add machine-specific settings to `~/.bashrc.d/99-local.sh`:

```bash
# This file is gitignored
export EDITOR=nvim
export BROWSER=firefox
alias myproject='cd ~/projects/myproject'

# Machine-specific PATH
export PATH="$HOME/custom/bin:$PATH"
```

### Chezmoi Data

Edit `~/.config/chezmoi/chezmoi.toml`:

```toml
[data]
  name = "Your Name"
  email = "detected@from.git"  # Auto-detected
  editor = "vim"

[data.machine]
  hostname = "detected"         # Auto-detected
  os = "Ubuntu"                 # Auto-detected
  version = "24.04"             # Auto-detected
```

### Adding Modules

```bash
# Create new module
cat > ~/.bashrc.d/70-custom.sh <<'EOF'
#!/usr/bin/env bash
# shellcheck shell=bash
# Your configuration
EOF

# Add to chezmoi
chezmoi add ~/.bashrc.d/70-custom.sh
```

## 🔧 Troubleshooting

### SSH Agent Issues

```bash
# Check agent status (should show single agent)
ssh-add -l

# Agent state stored in
ls -la ~/.local/state/ssh/

# Force restart if needed
rm ~/.local/state/ssh/agent.env
exec bash -l
```

### GPG/Pass Issues

```bash
# Check GPG keys
gpg --list-secret-keys

# Generate if missing
gpg --full-generate-key

# Initialize pass
pass init <KEY_ID>

# Test pass
pass insert test/example
pass show test/example
```

### Chezmoi Issues

```bash
# Check for pending changes
chezmoi status

# See exact differences
chezmoi diff

# Force re-apply
chezmoi apply --force

# Verify source directory
ls -la ~/git/machine-rites/.chezmoi/
```

### Rollback

```bash
# List available backups
ls -dt ~/dotfiles-backup-* | head -5

# Run rollback
~/dotfiles-backup-TIMESTAMP/rollback.sh
```

## 🏥 Health Check Output

```bash
$ make doctor

=== Dotfiles Health Check ===

[System]
  OS           : ✓ Ubuntu 24.04

[Tools]
  bash         : ✓ GNU bash, version 5.2.21
  chezmoi      : ✓ chezmoi version 2.47.0
  pass         : ✓ pass version 1.7.4
  gitleaks     : ✓ v8.18.4
  pre-commit   : ✓ pre-commit 3.6.0
  git          : ✓ git version 2.43.0
  gpg          : ✓ gpg (GnuPG) 2.4.4
  age          : ✓ v1.1.1
  ssh          : ✓ OpenSSH_9.6p1

[GPG]
  ✓ Secret keys: 1

[Pass Store]
  ✓ Entries: 12

[SSH]
  ✓ Key: id_ed25519
  Agent        : ✓ Running (1 keys)

[Chezmoi]
  ✓ Clean

[Pre-commit]
  ✓ Hooks installed
  ✓ All checks pass

[Security]
  ✓ No secrets detected

[Summary]
  ✓ All essential tools installed

=== End Health Check ===
```

## 📚 References

- [Chezmoi Documentation](https://chezmoi.io)
- [Pass: The Standard Unix Password Manager](https://passwordstore.org)
- [Gitleaks: Secret Detection](https://github.com/gitleaks/gitleaks)
- [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/latest/)
- [SSH Agent Best Practices](https://valerioviperino.me/reusing-an-existing-ssh-agent/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/improvement`)
3. Make your changes
4. Run tests: `make test`
5. Commit with conventional commits
6. Push and create a PR

## 📄 License

MIT - See [LICENSE](LICENSE) file for details

## 🙏 Acknowledgments

- Ubuntu/Debian teams for excellent package management
- Chezmoi for declarative dotfiles
- Pass community for simple, secure secrets
- ShellCheck for saving us from bash gotchas

---

**Version**: 2.0.0 | **Tested on**: Ubuntu 24.04 LTS | **Last Updated**: 2024