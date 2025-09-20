# Machine-Rites Repository Structure

## 📁 Root Directory Structure

```
machine-rites/                                    # Enterprise-grade dotfiles management system
├── 📄 README.md                                  # Main project documentation and quick start guide
├── 📄 CLAUDE.md                                  # Claude Code configuration and SPARC development setup
├── 📄 project-plan.md                           # Comprehensive project roadmap and milestones
├── 📄 KNOWN-ISSUES.md                           # Documented issues and workarounds
├── 📄 standards.md                              # Coding standards and best practices
├── 📄 package.json                              # NPM configuration with test scripts and dependencies
├── 📄 package-lock.json                         # Locked dependency versions for reproducible builds
├── 📄 claude-flow.config.json                   # Claude-Flow orchestration configuration
├── 📄 .mcp.json                                 # MCP (Model Context Protocol) server configuration
├── 📄 docker-compose.test.yml                   # Docker Compose for testing environments
├── 📄 .pre-commit-config.yaml                   # Pre-commit hooks configuration
├── 📄 .gitignore                                # Git ignore patterns for sensitive/generated files
├── 🔧 bootstrap_machine_rites.sh                # Main installation and setup script
├── 🔧 devtools-installer.sh                     # Developer tools installation script
├── 🔧 devtools_versions.sh                      # Version management for development tools
├── 🔧 get_latest_versions.sh                    # Automated version checking and updates
├── 🔧 claude-flow-hooks-setup.sh                # Claude-Flow integration setup
│
├── 📁 bootstrap/                                 # Core bootstrap and installation modules
│   ├── 🔧 bootstrap.sh                          # Standard bootstrap process
│   ├── 🔧 bootstrap-optimized.sh                # Performance-optimized bootstrap variant
│   ├── 📁 modules/                              # Modular bootstrap components
│   ├── 📁 lazy/                                 # Lazy-loading bootstrap modules
│   └── 📁 lib/                                  # Bootstrap-specific library functions
│
├── 📁 lib/                                      # Core library and utility functions
│   ├── 🔧 common.sh                             # Common utility functions used across scripts
│   ├── 🔧 platform.sh                           # Platform detection and OS-specific logic
│   ├── 🔧 validation.sh                         # Input validation and error checking
│   ├── 🔧 atomic.sh                             # Atomic operations and rollback functionality
│   └── 🔧 testing.sh                            # Testing utilities and test helpers
│
├── 📁 tools/                                    # Administrative and maintenance tools
│   ├── 🔧 benchmark.sh                          # Performance benchmarking and metrics
│   ├── 🔧 performance-monitor.sh                # Real-time performance monitoring
│   ├── 🔧 doctor.sh                             # System health check and diagnostics
│   ├── 🔧 weekly-audit.sh                       # Automated weekly system audits
│   ├── 🔧 cache-manager.sh                      # Cache optimization and management
│   ├── 🔧 optimize-bootstrap.sh                 # Bootstrap process optimization
│   ├── 🔧 update.sh                             # System update and maintenance
│   ├── 🔧 update-claude-md.sh                   # Claude documentation updates
│   ├── 🔧 backup-pass.sh                        # Password/secrets backup utility
│   ├── 🔧 rotate-secrets.sh                     # Automated secret rotation
│   ├── 🔧 rollback.sh                           # System rollback and recovery
│   ├── 🔧 auto-update.sh                        # Automated update scheduling
│   ├── 🔧 check-vestigial.sh                    # Cleanup of obsolete files/configs
│   ├── 🔧 verify-docs.sh                        # Documentation validation
│   └── 🔧 setup-doc-hooks.sh                    # Documentation hooks setup
│
├── 📁 tests/                                    # Comprehensive testing framework
│   ├── 🔧 run_tests.sh                          # Main test runner and orchestrator
│   ├── 🔧 coverage_report.sh                    # Test coverage analysis and reporting
│   ├── 📁 unit/                                 # Unit tests for individual components
│   │   ├── 🔧 test_bootstrap.sh                 # Bootstrap process unit tests
│   │   ├── 📁 tests/                            # Individual unit test files
│   │   └── 📁 docker/                           # Docker-based testing environments
│   │       ├── 📁 ubuntu-22.04/                 # Ubuntu 22.04 test environment
│   │       ├── 📁 ubuntu-24.04/                 # Ubuntu 24.04 test environment
│   │       └── 📁 debian-12/                    # Debian 12 test environment
│   ├── 📁 integration/                          # Integration tests for component interactions
│   │   └── 🔧 test_chezmoi_apply.sh             # Chezmoi integration testing
│   ├── 📁 e2e/                                  # End-to-end complete workflow tests
│   │   └── 🔧 test_complete_bootstrap.sh        # Complete bootstrap E2E test
│   ├── 📁 lib/                                  # Testing library and shared utilities
│   │   └── 🔧 run_all_tests.sh                  # Library test runner
│   ├── 📁 performance/                          # Performance and load testing
│   ├── 📁 mocks/                                # Mock data and test fixtures
│   │   ├── 📁 bootstrap/                        # Bootstrap mock environments
│   │   ├── 📁 atomic_ops/                       # Atomic operations test mocks
│   │   ├── 📁 validation/                       # Validation test fixtures
│   │   └── 📁 chezmoi_integration/              # Chezmoi integration mocks
│   ├── 📁 fixtures/                             # Static test data and configurations
│   ├── 📁 results/                              # Test execution results and reports
│   ├── 📁 reports/                              # Detailed test analysis reports
│   ├── 📁 coverage/                             # Code coverage reports and metrics
│   └── 📁 .swarm/                               # Swarm testing coordination data
│
├── 📁 docs/                                     # Project documentation and guides
│   └── 📄 repository-structure.md               # This file - complete repo structure guide
│
├── 📁 security/                                 # Security tools and compliance frameworks
│   ├── 📄 security-findings.txt                 # Security audit findings and resolutions
│   ├── 📄 security-audit-exclusions.txt         # Security scan exclusions and justifications
│   ├── 🔧 security-checklist.sh                 # Interactive security compliance checker
│   ├── 🔧 gpg-backup-restore.sh                 # GPG key backup and restoration
│   ├── 📁 audit/                                # Security auditing tools
│   │   └── 🔧 audit-logger.sh                   # Comprehensive security audit logging
│   ├── 📁 compliance/                           # Compliance framework implementations
│   │   ├── 🔧 nist-csf-mapper.sh                # NIST Cybersecurity Framework mapping
│   │   └── 🔧 cis-benchmark.sh                  # CIS Benchmarks compliance checking
│   └── 📁 intrusion-detection/                  # IDS and monitoring tools
│       └── 🔧 ids-monitor.sh                    # Intrusion detection monitoring
│
├── 📁 memory/                                   # Session and state management
│   ├── 📄 memory-store.json                     # Main memory store for persistent data
│   ├── 📄 claude-flow-data.json                 # Claude-Flow specific memory data
│   ├── 📁 sessions/                             # Session-specific memory storage
│   │   └── 📄 README.md                         # Session management documentation
│   └── 📁 agents/                               # Agent-specific memory and state
│       └── 📄 README.md                         # Agent memory system documentation
│
├── 📁 backups/                                  # Automated backup storage
│   └── 📁 auto-update/                          # Automated update backup files
│       └── 📦 machine-rites-backup-*.tar.gz     # Timestamped backup archives
│
├── 📁 logs/                                     # System and application logs
│   └── 📄 *.log                                 # Various log files from operations
│
├── 📁 test-results/                             # Test execution results and artifacts
│   └── 📄 *.xml, *.json                         # Test result files in various formats
│
├── 📁 .performance/                             # Performance metrics and monitoring data
│   └── 📄 bootstrap_performance.json            # Bootstrap performance metrics
│
├── 📁 .claude/                                  # Claude Code and AI agent configurations
│   ├── 📄 settings.json                         # Main Claude settings and preferences
│   ├── 📄 settings.local.json                   # Local Claude configuration overrides
│   └── 📁 agents/                               # AI agent definitions and specializations
│       ├── 📄 README.md                         # Agent system overview and usage
│       ├── 📁 github/                           # GitHub-specific agents
│       │   ├── 📄 github-modes.md               # GitHub integration modes
│       │   ├── 📄 pr-manager.md                 # Pull request management agent
│       │   ├── 📄 issue-tracker.md              # Issue tracking and triage agent
│       │   ├── 📄 code-review-swarm.md          # Code review swarm coordination
│       │   ├── 📄 release-manager.md            # Release management automation
│       │   ├── 📄 workflow-automation.md        # GitHub Actions workflow automation
│       │   ├── 📄 project-board-sync.md         # Project board synchronization
│       │   ├── 📄 repo-architect.md             # Repository architecture management
│       │   ├── 📄 multi-repo-swarm.md           # Multi-repository coordination
│       │   └── 📄 sync-coordinator.md           # Cross-repository synchronization
│       ├── 📁 sparc/                            # SPARC methodology agents
│       │   ├── 📄 specification.md              # Requirements specification agent
│       │   ├── 📄 architecture.md               # System architecture design agent
│       │   └── 📄 refinement.md                 # Code refinement and optimization agent
│       ├── 📁 analysis/                         # Code analysis and review agents
│       │   ├── 📄 code-analyzer.md              # General code analysis agent
│       │   └── 📁 code-review/                  # Code review specializations
│       │       └── 📄 analyze-code-quality.md   # Code quality analysis agent
│       ├── 📁 optimization/                     # Performance optimization agents
│       │   ├── 📄 README.md                     # Optimization agents overview
│       │   ├── 📄 performance-monitor.md        # Performance monitoring agent
│       │   ├── 📄 benchmark-suite.md            # Benchmarking and testing agent
│       │   ├── 📄 resource-allocator.md         # Resource allocation optimization
│       │   ├── 📄 load-balancer.md              # Load balancing coordination
│       │   └── 📄 topology-optimizer.md         # Swarm topology optimization
│       ├── 📁 devops/                           # DevOps and infrastructure agents
│       │   └── 📁 ci-cd/                        # CI/CD pipeline agents
│       │       └── 📄 ops-cicd-github.md        # GitHub CI/CD operations agent
│       ├── 📁 architecture/                     # System architecture agents
│       │   └── 📁 system-design/                # System design specializations
│       │       └── 📄 arch-system-design.md     # System architecture design agent
│       ├── 📁 documentation/                    # Documentation generation agents
│       │   └── 📁 api-docs/                     # API documentation specializations
│       │       └── 📄 docs-api-openapi.md       # OpenAPI documentation generator
│       ├── 📁 specialized/                      # Specialized development agents
│       │   └── 📁 mobile/                       # Mobile development agents
│       │       └── 📄 spec-mobile-react-native.md # React Native development agent
│       ├── 📁 neural/                           # Neural network and AI agents
│       │   ├── 📄 README.md                     # Neural agents overview
│       │   └── 📄 safla-neural.md               # SAFLA neural optimization agent
│       └── 📁 goal/                             # Goal-oriented planning agents
│           └── 📄 goal-planner.md               # Strategic goal planning agent
│
├── 📁 .claude-flow/                             # Claude-Flow orchestration data
│   └── 📁 metrics/                              # Performance and system metrics
│       ├── 📄 performance.json                  # System performance metrics
│       ├── 📄 task-metrics.json                 # Task execution metrics
│       ├── 📄 system-metrics.json               # System resource metrics
│       ├── 📄 agent-metrics.json                # Agent performance data
│       ├── 📄 app-metrics.jsonl                 # Application metrics logs
│       ├── 📄 cache-metrics.jsonl               # Cache performance logs
│       └── 📄 docker-metrics.jsonl              # Docker container metrics
│
├── 📁 .hive-mind/                               # Hive-mind distributed coordination
│   ├── 📄 README.md                             # Hive-mind system documentation
│   ├── 📄 config.json                           # Hive-mind configuration
│   ├── 📄 memory.json                           # Hive-mind shared memory
│   ├── 📄 hive.db*                              # SQLite database files (with WAL/SHM)
│   ├── 📄 memory.db                             # Memory database for coordination
│   ├── 📁 sessions/                             # Hive-mind session data
│   └── 📁 config/                               # Hive-mind configuration files
│       ├── 📄 workers.json                      # Worker node configurations
│       └── 📄 queens.json                       # Queen node configurations
│
├── 📁 .swarm/                                   # Swarm coordination and state
│   └── 📄 memory.db*                            # Swarm memory database (with WAL/SHM)
│
├── 📁 .chezmoi/                                 # Chezmoi dotfiles management
│   ├── 📄 README.md                             # Chezmoi configuration documentation
│   ├── 📄 .chezmoiignore                        # Files to ignore during chezmoi operations
│   ├── 📄 dot_bashrc                            # Main bash configuration template
│   ├── 📄 dot_profile                           # Shell profile configuration
│   ├── 📁 dot_config/                           # Configuration file templates
│   │   └── 📄 starship.toml                     # Starship prompt configuration
│   └── 📁 dot_bashrc.d/                         # Modular bash configuration
│       ├── 🔧 00-hygiene.sh                     # Basic shell hygiene and cleanup
│       ├── 🔧 10-bash-completion.sh             # Bash completion setup
│       ├── 🔧 25-pyenv.sh                       # Python environment management
│       ├── 🔧 30-secrets.sh                     # Secret management integration
│       ├── 🔧 35-ssh.sh                         # SSH configuration and key management
│       ├── 🔧 40-tools.sh                       # Development tools configuration
│       ├── 🔧 41-completions.sh                 # Command completions setup
│       ├── 🔧 45-devtools.sh                    # Developer tools integration
│       ├── 🔧 50-prompt.sh                      # Custom prompt configuration
│       ├── 🔧 55-starship.sh                    # Starship prompt integration
│       ├── 🔧 60-aliases.sh                     # Custom aliases and shortcuts
│       └── 🔧 private_99-local.sh               # Local-only customizations
│
├── 📁 .github/                                  # GitHub Actions and CI/CD
│   ├── 📁 workflows/                            # GitHub Actions workflow definitions
│   │   ├── 📄 ci.yml                            # Main continuous integration pipeline
│   │   ├── 📄 docker-ci.yml                     # Docker-based CI pipeline
│   │   ├── 📄 claude-code-review.yml            # Claude-powered code review
│   │   ├── 📄 claude.yml                        # Claude integration workflow
│   │   └── 📄 documentation-check.yml           # Documentation validation
│   └── 📁 docker/                               # Docker configurations for CI
│       ├── 📄 README.md                         # Docker CI documentation
│       ├── 📄 docker-compose.test.yml           # Docker Compose for testing
│       ├── 🔧 local-test.sh                     # Local Docker testing script
│       ├── 🔧 test-runner.sh                    # Automated test execution
│       ├── 📄 Dockerfile.ubuntu-22.04           # Ubuntu 22.04 test environment
│       ├── 📄 Dockerfile.ubuntu-24.04           # Ubuntu 24.04 test environment
│       ├── 📄 Dockerfile.debian-12              # Debian 12 test environment
│       ├── 📄 Dockerfile.ubuntu-22.04.optimized # Optimized Ubuntu 22.04 image
│       ├── 📄 Dockerfile.ubuntu-24.04.optimized # Optimized Ubuntu 24.04 image
│       └── 📄 Dockerfile.debian-12.optimized    # Optimized Debian 12 image
│
└── 📁 node_modules/                             # NPM dependencies (gitignored)
    └── 🔒 [Various NPM packages]                # Jest and other development dependencies
```

## 🔧 Script Categories

### 🚀 Main Entry Points
- `bootstrap_machine_rites.sh` - Primary installation script with full functionality
- `devtools-installer.sh` - Focused developer tools installation
- `claude-flow-hooks-setup.sh` - Claude-Flow integration setup

### 📚 Library Functions (`lib/`)
- `common.sh` - Shared utilities (logging, error handling, common operations)
- `platform.sh` - OS detection and platform-specific logic
- `validation.sh` - Input validation and safety checks
- `atomic.sh` - Atomic operations with rollback capabilities
- `testing.sh` - Testing framework and test utilities

### 🛠️ Tools and Utilities (`tools/`)
- **Performance**: `benchmark.sh`, `performance-monitor.sh`, `optimize-bootstrap.sh`
- **Maintenance**: `doctor.sh`, `weekly-audit.sh`, `update.sh`, `cache-manager.sh`
- **Security**: `backup-pass.sh`, `rotate-secrets.sh`, `rollback.sh`
- **Documentation**: `update-claude-md.sh`, `verify-docs.sh`, `setup-doc-hooks.sh`

### 🧪 Testing Framework (`tests/`)
- **Unit Tests**: Individual component testing with Docker environments
- **Integration Tests**: Component interaction testing
- **E2E Tests**: Complete workflow validation
- **Performance Tests**: Load and performance validation
- **Mocks & Fixtures**: Test data and mock environments

### 🔐 Security Framework (`security/`)
- **Audit Tools**: Comprehensive security scanning and logging
- **Compliance**: NIST CSF and CIS Benchmarks implementation
- **Monitoring**: Intrusion detection and security monitoring

## 📊 Data and State Management

### 💾 Memory Systems
- `memory/` - Persistent session and agent state
- `.hive-mind/` - Distributed coordination database
- `.swarm/` - Swarm coordination state
- `.claude-flow/metrics/` - Performance and system metrics

### ⚙️ Configuration Management
- `claude-flow.config.json` - Main orchestration configuration
- `.mcp.json` - Model Context Protocol server setup
- `.claude/` - AI agent configurations and specializations
- `.chezmoi/` - Dotfiles templates and configurations

## 🎯 Key Features

### 🔄 Atomic Operations
- Rollback capabilities for safe system modifications
- Transaction-like operations with validation
- Error recovery and state restoration

### 📈 Performance Monitoring
- Real-time performance metrics collection
- Automated benchmarking and optimization
- Cache management and optimization

### 🤖 AI Integration
- Claude Code agent specializations
- SPARC methodology implementation
- Distributed AI coordination with swarm intelligence

### 🏢 Enterprise Features
- Comprehensive security scanning and compliance
- Automated auditing and reporting
- Multi-platform support with Docker testing
- Professional documentation and standards

This structure supports enterprise-grade dotfiles management with comprehensive testing, security, performance optimization, and AI-powered development workflows.