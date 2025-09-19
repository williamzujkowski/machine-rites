# Bootstrap Modular Architecture

## Overview

The bootstrap system has been refactored from a monolithic 1,161-line script into a modular architecture following Phase 2.1 of the project plan. This document outlines the architectural decisions, module interfaces, and system design.

## Architecture Principles

### Modular Design
- **Single Responsibility**: Each module handles one specific aspect of the bootstrap process
- **Dependency Management**: Clear dependency chains with automatic validation
- **Idempotency**: All modules can be run multiple times safely
- **Rollback Capability**: Each module implements rollback functionality where feasible

### Error Handling
- **Atomic Operations**: File operations use atomic writes to prevent corruption
- **Comprehensive Logging**: Detailed progress tracking and error reporting
- **Graceful Degradation**: Modules can continue after non-critical failures
- **Rollback on Failure**: Automatic rollback options when modules fail

## Directory Structure

```
bootstrap/
├── bootstrap.sh                 # Main orchestrator
├── lib/
│   └── bootstrap-common.sh      # Shared bootstrap functions
└── modules/
    ├── 00-prereqs.sh           # Prerequisites and validation
    ├── 10-backup.sh            # Backup creation and management
    ├── 20-system-packages.sh   # Package installation
    ├── 30-chezmoi.sh           # Chezmoi setup and configuration
    ├── 40-shell-config.sh      # Shell configuration
    ├── 50-secrets.sh           # GPG and Pass setup
    └── 60-devtools.sh          # Optional developer tools
```

## Module Interface

### Required Functions
Each module must implement these functions:

- `validate()`: Validate prerequisites before execution
- `execute()`: Perform the module's main functionality
- `verify()`: Verify the module completed successfully
- `rollback()`: Undo changes made by the module

### Module Metadata
Each module includes metadata headers:
```bash
# Description: Brief description of module purpose
# Version: 1.0.0
# Dependencies: List of required modules/libraries
# Idempotent: Yes/No
# Rollback: Yes/No/Partial
```

### State Management
- Modules track their execution state
- Progress is persisted for rollback and resume capabilities
- Dependency validation ensures proper execution order

## Module Specifications

### 00-prereqs.sh (Prerequisites)
- **Purpose**: System validation and environment setup
- **Dependencies**: lib/common.sh, lib/platform.sh, lib/validation.sh
- **Rollback**: No (validation only)
- **Key Functions**:
  - OS compatibility validation
  - Required variable setup (XDG, repository, git config)
  - Shell environment validation
  - Error handling setup

### 10-backup.sh (Backup Management)
- **Purpose**: Create backups of existing configurations
- **Dependencies**: lib/common.sh, lib/atomic.sh
- **Rollback**: Yes (full restore from backup)
- **Key Functions**:
  - Timestamped backup creation
  - Backup manifest generation
  - Rollback script creation
  - Cleanup policy (keep latest 5 backups)

### 20-system-packages.sh (Package Installation)
- **Purpose**: Install required system packages and tools
- **Dependencies**: lib/common.sh, 00-prereqs.sh
- **Rollback**: Partial (can remove installed packages)
- **Key Functions**:
  - Essential package installation (git, curl, gnupg, pass, etc.)
  - Development packages (build-essential, pipx, nodejs, etc.)
  - Security tools (gitleaks)
  - Chezmoi installation via official installer
  - Version validation

### 30-chezmoi.sh (Chezmoi Setup)
- **Purpose**: Configure chezmoi dotfiles management
- **Dependencies**: lib/common.sh, lib/atomic.sh, 00-prereqs.sh, 20-system-packages.sh
- **Rollback**: Yes (removes chezmoi configuration)
- **Key Functions**:
  - Repository cloning/updating
  - Chezmoi configuration creation
  - Source directory setup
  - .chezmoiignore creation
  - Dotfile import and application
  - Global gitignore setup

### 40-shell-config.sh (Shell Configuration)
- **Purpose**: Create modular bash configuration
- **Dependencies**: lib/common.sh, lib/atomic.sh, 30-chezmoi.sh
- **Rollback**: Yes (restores from backup)
- **Key Functions**:
  - Modular .bashrc.d structure creation
  - Shell hygiene and environment setup
  - SSH agent configuration
  - Tool integration (nvm, pyenv, etc.)
  - Completion systems
  - Aliases and customizations

### 50-secrets.sh (Secrets Management)
- **Purpose**: Set up GPG keys and Pass password manager
- **Dependencies**: lib/common.sh, 20-system-packages.sh
- **Rollback**: Partial (warns about manual cleanup)
- **Key Functions**:
  - GPG key generation or import
  - Pass initialization
  - Plaintext secrets migration
  - Secure cleanup of plaintext files

### 60-devtools.sh (Developer Tools)
- **Purpose**: Install optional development tools
- **Dependencies**: lib/common.sh, 20-system-packages.sh, 30-chezmoi.sh
- **Rollback**: Partial (removes created configurations)
- **Key Functions**:
  - Starship prompt configuration
  - Gitleaks security scanning setup
  - Pre-commit hooks installation
  - Helper scripts creation (doctor.sh, update.sh, backup-pass.sh)
  - CI/CD workflow setup
  - Tool-specific completions

## Main Orchestrator (bootstrap.sh)

### Key Features
- **Module Validation**: Validates all modules before execution
- **Dependency Management**: Ensures modules run in correct order
- **Progress Tracking**: Persists execution state for rollback/resume
- **Error Recovery**: Comprehensive error handling with rollback options
- **Skip Flags**: Supports `--skip-MODULE` flags for selective execution
- **Dry Run Mode**: `--dry-run` shows what would be executed
- **Interactive Mode**: Prompts for decisions in non-unattended mode

### Command Line Interface
```bash
# Full bootstrap
./bootstrap/bootstrap.sh

# Skip specific modules
./bootstrap/bootstrap.sh --skip-devtools

# Run specific modules only
./bootstrap/bootstrap.sh 00-prereqs 20-system-packages

# Dry run
./bootstrap/bootstrap.sh --dry-run

# Rollback
./bootstrap/bootstrap.sh --rollback

# List available modules
./bootstrap/bootstrap.sh --list-modules
```

## Backwards Compatibility

The original `bootstrap_machine_rites.sh` script has been converted to a compatibility wrapper that:

1. Detects if the new modular system is available
2. Maps old command-line flags to new system
3. Redirects execution to `bootstrap/bootstrap.sh`
4. Falls back to legacy implementation if modular system unavailable

This ensures existing scripts and documentation continue to work while encouraging migration to the new system.

## Benefits of Modular Architecture

### Maintainability
- **Smaller Files**: Each module is focused and manageable
- **Clear Separation**: Distinct responsibilities reduce complexity
- **Easier Testing**: Individual modules can be tested in isolation
- **Better Documentation**: Each module is self-documenting

### Reliability
- **Atomic Operations**: File operations are transaction-safe
- **Rollback Capability**: Failed bootstraps can be reverted
- **Progress Tracking**: Resume from failure points
- **Dependency Validation**: Prevents execution with missing prerequisites

### Flexibility
- **Selective Execution**: Skip unnecessary modules
- **Custom Workflows**: Run specific module combinations
- **Environment Adaptation**: Modules adapt to different environments
- **Extension Points**: New modules can be added easily

### Debugging
- **Granular Logging**: Per-module execution tracking
- **Isolated Testing**: Test individual components
- **Clear Error Reporting**: Module-specific error handling
- **Debug Mode**: Enhanced tracing and validation

## Testing and Validation

### Syntax Validation
All modules pass `bash -n` syntax validation:
```bash
✓ 00-prereqs.sh - OK
✓ 10-backup.sh - OK
✓ 20-system-packages.sh - OK
✓ 30-chezmoi.sh - OK
✓ 40-shell-config.sh - OK
✓ 50-secrets.sh - OK
✓ 60-devtools.sh - OK
✓ bootstrap.sh - OK
```

### Functional Testing
- **Dry Run Mode**: Validates execution flow without making changes
- **Module Independence**: Each module can run independently
- **Idempotency**: Multiple executions produce consistent results
- **Rollback Testing**: Rollback functionality verified per module

## Future Enhancements

### Planned Improvements
- **Module Versioning**: Support for module version constraints
- **Parallel Execution**: Independent modules could run in parallel
- **Plugin System**: External modules could be registered
- **Configuration Files**: Module settings via configuration files
- **Remote Modules**: Modules could be downloaded from repositories

### Integration Points
- **CI/CD Integration**: Modules designed for automated environments
- **Container Support**: Docker-based testing and execution
- **Cloud Integration**: Support for cloud-based configurations
- **Monitoring**: Integration with system monitoring tools

## Migration Guide

### For Existing Users
1. **No Action Required**: Existing script automatically redirects
2. **Recommended**: Update scripts to use `bootstrap/bootstrap.sh`
3. **Optional**: Explore new flags like `--skip-MODULE` and `--dry-run`

### For Developers
1. **Module Extension**: Follow module interface for new functionality
2. **Testing**: Use `--dry-run` and individual module testing
3. **Integration**: Modules integrate with existing lib/ functions
4. **Documentation**: Update module metadata headers

This modular architecture provides a robust, maintainable, and extensible foundation for system bootstrap operations while maintaining full backwards compatibility with existing implementations.