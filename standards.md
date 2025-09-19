# standards.md - machine-rites Repository Assistant Guide

> **Purpose**: This document provides instructions for Claude Code and other LLM agents to maintain, document, and improve the machine-rites dotfiles repository with accuracy and consistency.

## 🎯 Core Principles

### Accuracy Over Enhancement
- **Document what exists**, not what could be
- **Verify before claiming** - test commands before suggesting them
- **Acknowledge limitations** - clearly state when unsure
- **Avoid feature creep** - maintain focus on working dotfiles

### Documentation Standards
- Every file must have a clear purpose statement
- Changes must be documented in commit messages
- Keep README.md synchronized with actual functionality
- Maintain this CLAUDE.md file as source of truth

## 📁 Repository Structure

```
machine-rites/
├── .chezmoi/                    # Chezmoi source directory
│   ├── dot_bashrc              # Main bash configuration loader
│   ├── dot_bashrc.d/           # Modular bash configs (00-99 ordered)
│   │   ├── 00-hygiene.sh       # Shell options, PATH, XDG setup
│   │   ├── 10-bash-completion.sh # Bash completion setup
│   │   ├── 30-secrets.sh       # Pass/GPG secrets management
│   │   ├── 35-ssh.sh           # SSH agent singleton management
│   │   ├── 40-tools.sh         # Development tools (nvm, pyenv, etc.)
│   │   ├── 41-completions.sh   # Tool-specific completions
│   │   ├── 50-prompt.sh        # Git-aware prompt fallback
│   │   ├── 55-starship.sh      # Starship prompt (if installed)
│   │   ├── 60-aliases.sh       # Shell aliases and shortcuts
│   │   └── private_99-local.sh # Local overrides (gitignored)
│   ├── dot_profile             # Login shell configuration
│   └── .chezmoiignore          # Files chezmoi should ignore
│
├── .github/                     # GitHub-specific files
│   └── workflows/              
│       └── ci.yml              # CI/CD pipeline configuration
│
├── tools/                       # Maintenance scripts
│   ├── backup-pass.sh          # GPG-encrypted pass backup
│   ├── doctor.sh               # System health check
│   └── update.sh               # Pull and apply updates
│
├── bootstrap_machine_rites.sh   # Main installation script
├── devtools-installer.sh        # Developer tools installer
├── devtools_versions.sh         # Version pinning configuration
├── get_latest_versions.sh       # Version update utility
├── Makefile                     # Task automation
├── README.md                    # User documentation
├── CLAUDE.md                    # THIS FILE - AI assistant guide
├── .gitignore                   # Git ignore patterns
├── .gitleaks.toml              # Secret scanning configuration
├── .pre-commit-config.yaml     # Pre-commit hooks
└── .shellcheckrc               # ShellCheck configuration
```

## 📋 File Purpose Documentation

### Core Bootstrap Files

#### `bootstrap_machine_rites.sh`
- **Purpose**: Main installation and configuration script
- **Key Features**:
  - Atomic file operations with rollback
  - XDG Base Directory compliance
  - Dynamic git config detection
  - Backup creation with timestamps
- **Dependencies**: bash, curl, git, chezmoi
- **Usage**: `./bootstrap_machine_rites.sh [--unattended] [--verbose]`

#### `devtools-installer.sh`
- **Purpose**: Install development tools (nvm, pyenv, rust, go)
- **Key Features**:
  - LTS version preferences
  - PATH management fixes
  - Verification mode
- **Dependencies**: Ubuntu 24.04, apt, curl
- **Usage**: `./devtools-installer.sh [--verify] [--minimal]`

### Chezmoi Source Files

#### `.chezmoi/dot_bashrc`
```bash
# Purpose: Main bash configuration loader
# Loads all modules from ~/.bashrc.d/ in order
# Handles non-interactive shell detection
```

#### `.chezmoi/dot_bashrc.d/` modules
- **Naming Convention**: `NN-purpose.sh` where NN is 00-99
- **Load Order**: Numeric ascending (00 loads before 99)
- **Each module must**:
  - Include shellcheck pragmas
  - Be idempotent (safe to source multiple times)
  - Document its purpose in header comment

### Tool Scripts

#### `tools/doctor.sh`
- **Purpose**: Comprehensive system health check
- **Checks**: Tools, GPG, SSH, Pass, Chezmoi status
- **Output**: Color-coded pass/warn/fail status

#### `tools/backup-pass.sh`
- **Purpose**: Create encrypted backups of password store
- **Features**: Rotation (keeps last 5), GPG encryption
- **Output**: `backups/pass/pass-YYYYMMDD-HHMMSS.tar.gz.gpg`

## 🤖 Claude Code Usage Guidelines

### When Making Changes

1. **Before modifying any file**:
   ```bash
   # Check current status
   git status
   chezmoi status
   
   # Run health check
   make doctor
   ```

2. **Document the change**:
   ```bash
   # Update this CLAUDE.md if structure changes
   # Update README.md if user-facing changes
   # Use clear commit messages:
   git commit -m "feat: add X for Y reason"
   ```

3. **Test thoroughly**:
   ```bash
   # Syntax check
   bash -n modified_script.sh
   
   # ShellCheck
   shellcheck modified_script.sh
   
   # Run tests
   make test
   ```

### Commit Message Format

Follow conventional commits:
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation only
- `style:` Formatting, no logic change
- `refactor:` Code restructure, no behavior change
- `test:` Test additions/changes
- `chore:` Maintenance tasks

### Code Standards

#### Shell Scripts
```bash
#!/usr/bin/env bash
# Purpose: Clear one-line description
# Dependencies: list external commands needed
# shellcheck shell=bash
set -euo pipefail

# Use consistent formatting:
function_name() {
    local var="$1"
    # Function body
}

# Always quote variables
echo "${VAR}"

# Check command existence
command -v tool >/dev/null 2>&1 || die "tool not found"
```

#### Error Handling
```bash
# Define early
die() { echo "Error: $*" >&2; exit 1; }
warn() { echo "Warning: $*" >&2; }
info() { echo "Info: $*"; }

# Use consistently
[ -f "$file" ] || die "File not found: $file"
```

### Testing Requirements

Before committing:
1. **Syntax**: All scripts pass `bash -n`
2. **Linting**: ShellCheck warnings addressed
3. **Secrets**: Gitleaks scan passes
4. **Functionality**: Core features work

### Version Management

When updating tool versions:
1. Update `devtools_versions.sh`
2. Test installation with new versions
3. Document compatibility in commit message
4. Update CI if minimum versions change

## 📝 Maintenance Tasks

### Daily Maintenance Checklist
```bash
# 1. Check for updates
make update

# 2. Verify health
make doctor

# 3. Check for secrets
make security-scan

# 4. Review changes
chezmoi diff
```

### Weekly Tasks
```bash
# 1. Update tool versions
./get_latest_versions.sh

# 2. Backup secrets
make secrets-backup

# 3. Clean old backups
make clean

# 4. Update pre-commit hooks
pre-commit autoupdate
```

### Adding New Features

1. **Assess necessity** - Does it solve a real problem?
2. **Check compatibility** - Works on Ubuntu 24.04+?
3. **Module or standalone** - Can it be a bashrc.d module?
4. **Document purpose** - Clear description in file header
5. **Add tests** - At minimum, syntax validation
6. **Update documentation** - This file, README, inline comments

### Removing Features

1. **Check dependencies** - What might break?
2. **Deprecation notice** - Warn in README first
3. **Migration path** - How do users adapt?
4. **Clean removal** - Remove all references
5. **Update tests** - Remove related tests

## 🚨 Common Issues & Solutions

### SSH Agent Multiplication
**Problem**: Multiple SSH agents spawning
**Solution**: Check `~/.bashrc.d/35-ssh.sh` uses XDG state directory

### Slow Shell Startup
**Problem**: Bash takes >1s to start
**Solution**: Profile with `bash -x`, check tool lazy loading

### Chezmoi Conflicts
**Problem**: Chezmoi apply fails
**Solution**: `chezmoi merge-all` or reset with `chezmoi init --apply`

### Pass Not Working
**Problem**: Pass commands fail
**Solution**: Check GPG key exists: `gpg --list-secret-keys`

## 🎯 Quality Standards

### Code Quality Metrics
- **Shell scripts**: ShellCheck warning level or better
- **Performance**: Shell startup <500ms ideal, <1000ms acceptable
- **Security**: Zero secrets in repository
- **Documentation**: Every file has purpose comment
- **Tests**: Core functionality covered

### Review Checklist
Before approving changes:
- [ ] Syntax valid (`bash -n`)
- [ ] ShellCheck passes
- [ ] No hardcoded secrets
- [ ] Documentation updated
- [ ] Tests pass
- [ ] Commit message clear
- [ ] No breaking changes (or documented)

## 📚 Reference Documentation

### External Resources
- [Chezmoi Documentation](https://www.chezmoi.io/)
- [ShellCheck Wiki](https://www.shellcheck.net/wiki/)
- [XDG Base Directory](https://specifications.freedesktop.org/basedir-spec/latest/)
- [Conventional Commits](https://www.conventionalcommits.org/)

### Related Standards
From [standards repository](https://github.com/williamzujkowski/standards):
- **CS:bash** - Bash scripting standards
- **TS:shellcheck** - Shell testing standards
- **SEC:secrets** - Secret management patterns
- **DOP:github-actions** - CI/CD best practices

## 🔄 Keeping This Document Updated

### When to Update CLAUDE.md
- New files or directories added
- File purposes change significantly
- New maintenance procedures established
- Common issues discovered and solved
- Quality standards change

### Update Process
1. Make changes alongside code changes
2. Include in same commit when possible
3. Review quarterly for accuracy
4. Remove outdated information promptly

### Verification Commands
```bash
# Verify file tree is accurate
tree -I 'backups|.git|node_modules'

# Check all documented files exist
grep -E '^\│.*\.(sh|md|yaml|yml|toml)' CLAUDE.md | while read -r line; do
    file=$(echo "$line" | sed 's/.*── //' | sed 's/ .*//')
    [ -f "$file" ] || echo "Missing: $file"
done

# Ensure all scripts are documented
find . -name "*.sh" -type f | while read -r script; do
    grep -q "$script" CLAUDE.md || echo "Undocumented: $script"
done
```

## ⚠️ Important Warnings

### Never Do These
- ❌ Store secrets in files (use pass)
- ❌ Hardcode paths (use variables)
- ❌ Skip shellcheck warnings without pragma
- ❌ Commit without testing
- ❌ Remove backups without user consent
- ❌ Use `eval` without careful validation
- ❌ Source untrusted files

### Always Do These
- ✅ Test on clean Ubuntu 24.04 VM
- ✅ Keep backups before major changes
- ✅ Document breaking changes
- ✅ Use atomic file operations
- ✅ Check for existing functionality first
- ✅ Maintain backwards compatibility
- ✅ Follow XDG Base Directory spec

---

*Last Updated: 2024-01-15*
*Maintainer: @williamzujkowski*
*Version: 1.0.0*