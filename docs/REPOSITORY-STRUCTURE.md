# 📁 Machine-Rites Repository Structure

## Complete File/Folder Tree with Descriptions

```
machine-rites/
│
├── 📄 bootstrap_machine_rites.sh      # Main installation script - deploys dotfiles and configures system
├── 📄 devtools-installer.sh           # Developer tools installer (nvm, pyenv, rust, go, etc.)
├── 📄 devtools_versions.sh            # Version pinning for development tools
├── 📄 get_latest_versions.sh          # Script to update tool versions
├── 📄 claude-flow-hooks-setup.sh      # Sets up Claude Flow AI integration hooks
├── 📄 Makefile                        # Build automation and Docker testing infrastructure
├── 📄 docker-compose.test.yml         # Docker compose configuration for multi-distro testing
├── 📄 package.json                    # Node.js dependencies and scripts
├── 📄 package-lock.json               # Locked dependency versions
│
├── 📁 .chezmoi/                        # Chezmoi dotfiles source directory
│   ├── 📄 dot_bashrc                   # Main bash configuration loader
│   ├── 📄 dot_profile                  # Login shell configuration
│   ├── 📄 .chezmoiignore              # Files chezmoi should ignore
│   │
│   ├── 📁 dot_bashrc.d/                # Modular bash configurations (00-99 ordered)
│   │   ├── 📄 00-hygiene.sh           # Shell options, PATH, XDG setup
│   │   ├── 📄 10-bash-completion.sh    # Bash completion configuration
│   │   ├── 📄 30-secrets.sh            # Pass/GPG secrets management
│   │   ├── 📄 35-ssh.sh               # SSH agent singleton management
│   │   ├── 📄 40-tools.sh              # Development tools (nvm, pyenv, etc.)
│   │   ├── 📄 41-completions.sh        # Tool-specific completions
│   │   ├── 📄 50-prompt.sh             # Git-aware prompt fallback
│   │   ├── 📄 55-starship.sh           # Starship prompt configuration
│   │   ├── 📄 60-aliases.sh            # Shell aliases and shortcuts
│   │   └── 📄 private_99-local.sh      # Local overrides (gitignored)
│   │
│   └── 📁 dot_config/
│       └── 📄 starship.toml            # Starship prompt theme configuration
│
├── 📁 lib/                             # Shell library functions
│   ├── 📄 common.sh                   # Core logging and utility functions
│   ├── 📄 atomic.sh                   # Atomic file operations with rollback
│   ├── 📄 validation.sh               # Input validation and sanitization
│   ├── 📄 platform.sh                 # OS/platform detection utilities
│   └── 📄 testing.sh                  # Test framework utilities
│
├── 📁 tools/                           # Administrative and maintenance scripts
│   ├── 📄 doctor.sh                   # System health check and diagnostics
│   ├── 📄 update.sh                   # Update dotfiles from repository
│   ├── 📄 backup-pass.sh              # GPG-encrypted password store backup
│   ├── 📄 rollback.sh                 # Rollback to previous configuration
│   ├── 📄 performance-monitor.sh       # Real-time performance monitoring
│   ├── 📄 benchmark.sh                # Performance benchmarking suite
│   ├── 📄 weekly-audit.sh             # Automated weekly maintenance
│   ├── 📄 check-vestigial.sh          # Find and report unused files
│   └── 📄 rotate-secrets.sh           # Automated secret rotation
│
├── 📁 bootstrap/                       # Modular bootstrap system
│   ├── 📄 bootstrap.sh                # Main bootstrap orchestrator
│   │
│   ├── 📁 lib/                        # Bootstrap-specific libraries
│   │   └── 📄 bootstrap-common.sh     # Bootstrap utilities and helpers
│   │
│   └── 📁 modules/                    # Bootstrap modules (00-99 ordered)
│       ├── 📄 00-prereqs.sh           # Prerequisites and validation
│       ├── 📄 10-backup.sh            # Backup creation and management
│       ├── 📄 20-system-packages.sh   # System package installation
│       ├── 📄 30-chezmoi.sh           # Chezmoi setup and configuration
│       ├── 📄 40-shell-config.sh      # Shell configuration setup
│       └── 📄 50-secrets.sh           # GPG and Pass setup
│
├── 📁 docker/                          # Docker testing infrastructure
│   ├── 📄 test-harness.sh            # Docker test orchestration script
│   ├── 📄 validate-environment.sh     # Environment validation script
│   │
│   ├── 📁 ubuntu-24.04/               # Ubuntu 24.04 test environment
│   │   └── 📄 Dockerfile              # Ubuntu 24.04 test container
│   │
│   ├── 📁 ubuntu-22.04/               # Ubuntu 22.04 test environment
│   │   └── 📄 Dockerfile              # Ubuntu 22.04 test container
│   │
│   └── 📁 debian-12/                  # Debian 12 test environment
│       └── 📄 Dockerfile              # Debian 12 test container
│
├── 📁 tests/                           # Comprehensive test suite
│   ├── 📄 run_tests.sh               # Main test runner orchestrator
│   ├── 📄 test-framework.sh          # Core testing framework
│   │
│   ├── 📁 unit/                       # Unit tests for components
│   │   ├── 📄 test_bootstrap.sh      # Bootstrap functionality tests
│   │   ├── 📄 test_atomic_operations.sh # Atomic operations tests
│   │   ├── 📄 test_platform_detection.sh # Platform detection tests
│   │   └── 📄 test_validation.sh     # Input validation tests
│   │
│   ├── 📁 integration/                # Integration tests
│   │   ├── 📄 test_full_bootstrap.sh # End-to-end bootstrap test
│   │   └── 📄 test_rollback.sh       # Rollback functionality test
│   │
│   ├── 📁 e2e/                        # End-to-end tests
│   │   └── 📄 test_deployment.sh     # Full deployment test
│   │
│   ├── 📁 performance/                # Performance tests
│   │   ├── 📄 test_shell_startup.sh  # Shell startup time test
│   │   └── 📄 test_bootstrap_speed.sh # Bootstrap performance test
│   │
│   ├── 📁 lib/                        # Test utilities
│   │   └── 📄 test_helpers.sh        # Test helper functions
│   │
│   ├── 📁 mocks/                      # Mock data for testing
│   │   └── [various mock directories]
│   │
│   └── 📁 fixtures/                   # Test fixtures and data
│       └── [test fixture files]
│
├── 📁 security/                        # Security tools and compliance
│   ├── 📁 audit/                      # Security auditing tools
│   │   ├── 📄 audit-logger.sh        # Security event logging
│   │   └── 📄 vulnerability-scanner.sh # Vulnerability scanning
│   │
│   └── 📁 compliance/                 # Compliance frameworks
│       ├── 📄 nist-csf-mapper.sh     # NIST framework mapping
│       └── 📄 soc2-validator.sh      # SOC2 compliance validation
│
├── 📁 docs/                            # Documentation
│   ├── 📄 README.md                  # Main project documentation
│   ├── 📄 CONTRIBUTING.md            # Contribution guidelines
│   ├── 📄 DEPLOYMENT-CHECKLIST.md    # Deployment procedures
│   └── 📄 REPOSITORY-STRUCTURE.md    # This file
│
├── 📁 .github/                         # GitHub specific files
│   ├── 📁 workflows/                  # GitHub Actions workflows
│   │   ├── 📄 ci.yml                 # Main CI/CD pipeline
│   │   └── 📄 docker-ci.yml          # Docker-based testing
│   │
│   └── 📁 docker/                     # Additional Docker configs
│       ├── 📄 local-test.sh          # Local testing script
│       └── 📄 test-runner.sh         # Test execution script
│
├── 📁 .claude/                         # Claude AI integration
│   ├── 📁 agents/                     # Specialized AI agents
│   │   ├── 📁 github/                # GitHub workflow agents
│   │   ├── 📁 sparc/                 # SPARC methodology agents
│   │   ├── 📁 analysis/              # Code analysis agents
│   │   ├── 📁 optimization/          # Performance optimization agents
│   │   ├── 📁 devops/                # DevOps automation agents
│   │   └── 📁 architecture/          # System architecture agents
│   │
│   └── 📁 helpers/                    # AI helper scripts
│       ├── 📄 checkpoint-manager.sh   # Checkpoint management
│       └── 📄 standard-checkpoint-hooks.sh # Standard hooks
│
├── 📁 .claude-flow/                    # Claude Flow orchestration
│   ├── 📄 config.json                # Configuration settings
│   │
│   └── 📁 metrics/                    # Performance metrics
│       ├── 📄 agent-metrics.json     # Agent performance data
│       ├── 📄 performance.json       # System performance metrics
│       ├── 📄 task-metrics.json      # Task execution metrics
│       └── 📄 system-metrics.json    # System resource metrics
│
├── 📁 .hive-mind/                      # Hive-mind coordination
│   ├── 📄 hive.db                    # Coordination database
│   ├── 📄 hive.db-shm                # Shared memory
│   └── 📁 sessions/                  # Session data
│
├── 📁 .swarm/                          # Swarm intelligence
│   ├── 📄 memory.db                  # Persistent memory storage
│   └── 📄 memory.db-shm              # Shared memory
│
├── 📁 .performance/                    # Performance monitoring data
│   └── [performance metrics files]
│
├── 📁 backups/                         # Backup storage
│   ├── 📁 pass/                      # Password store backups
│   └── 📁 auto-update/               # Auto-update backups
│
├── 📁 .git/                           # Git version control
│   └── [standard git structure]
│
├── 📁 logs/                           # Application logs
│   └── [log files]
│
└── 📄 Configuration Files (Root)
    ├── 📄 .gitignore                 # Git ignore patterns
    ├── 📄 .gitleaks.toml            # Gitleaks configuration
    ├── 📄 .pre-commit-config.yaml    # Pre-commit hooks
    ├── 📄 .shellcheckrc             # ShellCheck configuration
    ├── 📄 CLAUDE.md                 # AI assistant instructions
    ├── 📄 standards.md              # Coding standards
    ├── 📄 project-plan.md           # Project planning document
    └── 📄 README.md                 # Main documentation
```

## Directory Purpose Summary

| Directory | Purpose | Status |
|-----------|---------|--------|
| `.chezmoi/` | Dotfiles source templates | ✅ Active |
| `lib/` | Shared shell libraries | ✅ Active |
| `tools/` | Admin & maintenance scripts | ✅ Active |
| `bootstrap/` | Modular bootstrap system | ✅ Active |
| `docker/` | Multi-distro testing | ✅ Active |
| `tests/` | Comprehensive test suite | ✅ Active |
| `security/` | Security & compliance | ✅ Active |
| `docs/` | Project documentation | ✅ Active |
| `.github/` | GitHub Actions CI/CD | ✅ Active |
| `.claude/` | AI agent integration | ✅ Active |
| `.claude-flow/` | AI orchestration | ✅ Active |
| `.hive-mind/` | Distributed coordination | ✅ Active |
| `.swarm/` | Swarm intelligence | ✅ Active |
| `backups/` | Backup storage | ✅ Active |

## Key Features

- **🔄 Atomic Operations**: Safe file operations with automatic rollback
- **🧪 Comprehensive Testing**: Unit, integration, E2E, and performance tests
- **🐳 Multi-Platform Support**: Docker-based testing for Ubuntu/Debian
- **🤖 AI Integration**: Claude agents for automated development workflows
- **🔒 Security Framework**: Enterprise-grade security and compliance tools
- **📊 Performance Monitoring**: Real-time metrics and benchmarking
- **🎨 Starship Prompt**: Beautiful, functional cross-shell prompt
- **🔐 Secrets Management**: GPG/Pass integration for secure credentials
- **📦 Package Management**: Automated tool installation and versioning
- **🔧 Modular Architecture**: Everything is modular and DRY-compliant