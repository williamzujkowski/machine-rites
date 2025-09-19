# Architecture Decision Records (ADRs)

## ADR-001: Modular Shell Library System

**Date**: 2025-09-19
**Status**: Accepted
**Context**: Need for reusable, testable shell utilities across the project

### Decision
Implement a modular shell library system in `lib/` directory with:
- Self-contained libraries with clear responsibilities
- Comprehensive documentation and testing
- Idempotent sourcing with guards
- Shellcheck compliance

### Consequences
- **Positive**: Code reuse, easier testing, better maintainability
- **Negative**: Slight overhead for sourcing multiple files
- **Mitigation**: Libraries are lightweight and sourcing is fast

### Implementation
```bash
# Standard import pattern
source "${BASH_SOURCE[0]%/*}/lib/common.sh"

# Each library follows pattern:
# 1. Guards against multiple sourcing
# 2. Clear function documentation
# 3. Proper error handling
# 4. Return codes (0=success, 1=failure)
```

## ADR-002: Atomic File Operations

**Date**: 2025-09-19
**Status**: Accepted
**Context**: Need to prevent file corruption during writes

### Decision
All critical file operations use atomic write pattern:
1. Write to temporary file
2. Validate content
3. Atomic rename to final location
4. Cleanup on failure

### Consequences
- **Positive**: No partial writes, safe interruption
- **Negative**: Requires additional disk space temporarily
- **Mitigation**: Cleanup temporary files on exit

### Implementation
```bash
# Via lib/atomic.sh
echo "content" | write_atomic "/path/to/file"
# Handles temp file creation, validation, and atomic rename
```

## ADR-003: XDG Base Directory Compliance

**Date**: 2025-09-19
**Status**: Accepted
**Context**: Modern filesystem organization standards

### Decision
Follow XDG Base Directory Specification:
- `$XDG_CONFIG_HOME` (~/.config) for configuration
- `$XDG_DATA_HOME` (~/.local/share) for data
- `$XDG_STATE_HOME` (~/.local/state) for state
- `$XDG_CACHE_HOME` (~/.cache) for cache

### Consequences
- **Positive**: Standard compliance, cleaner home directory
- **Negative**: Some tools don't support XDG
- **Mitigation**: Provide fallbacks and symlinks where needed

## ADR-004: SSH Agent Persistence

**Date**: 2025-09-19
**Status**: Accepted
**Context**: Multiple SSH agents being spawned per session

### Decision
Single persistent SSH agent using XDG state directory:
- Store agent info in `~/.local/state/ssh/agent.env`
- Reuse existing agent across sessions
- Automatic cleanup of stale agents

### Consequences
- **Positive**: No agent multiplication, consistent key availability
- **Negative**: Slightly more complex startup logic
- **Mitigation**: Robust error handling and fallbacks

## ADR-005: GPG-Encrypted Secret Management

**Date**: 2025-09-19
**Status**: Accepted
**Context**: Need secure storage for sensitive configuration

### Decision
Use `pass` (passwordstore.org) for secret management:
- GPG-encrypted storage
- Automatic migration from plaintext files
- Environment variable export
- Backup and restore capabilities

### Consequences
- **Positive**: Strong encryption, audit trail, version control
- **Negative**: Requires GPG setup and key management
- **Mitigation**: Automated setup and comprehensive documentation

## ADR-006: Chezmoi for Dotfiles Management

**Date**: 2025-09-19
**Status**: Accepted
**Context**: Need declarative dotfiles management with templating

### Decision
Use Chezmoi as primary dotfiles manager:
- Template-based configuration
- Cross-machine differences handled via data
- Git integration for version control
- Dry-run capabilities for safety

### Consequences
- **Positive**: Declarative, templatable, version controlled
- **Negative**: Learning curve, additional tool dependency
- **Mitigation**: Comprehensive examples and fallback mechanisms

## ADR-007: CI/CD with GitHub Actions

**Date**: 2025-09-19
**Status**: Accepted
**Context**: Need automated testing and security scanning

### Decision
GitHub Actions workflow with:
- ShellCheck for all shell scripts
- Gitleaks for secret detection
- Pre-commit hook validation
- PR comment permissions for feedback

### Consequences
- **Positive**: Automated quality control, security scanning
- **Negative**: CI dependency, potential false positives
- **Mitigation**: Proper configuration files and manual override capabilities

## ADR-008: Bootstrap Modularity

**Date**: 2025-09-19
**Status**: Accepted
**Context**: Bootstrap script becoming monolithic and hard to maintain

### Decision
Modular bootstrap system with:
- Separate functions for each component
- Dependency checking and ordering
- Configurable component selection
- Comprehensive logging and error handling

### Consequences
- **Positive**: Maintainable, testable, flexible
- **Negative**: More complex than monolithic approach
- **Mitigation**: Clear documentation and testing

## ADR-009: Comprehensive Testing Strategy

**Date**: 2025-09-19
**Status**: Accepted
**Context**: Need reliable testing for shell code

### Decision
Multi-level testing approach:
- Unit tests for library functions
- Integration tests for workflows
- Performance benchmarks
- CI validation

### Consequences
- **Positive**: High confidence in changes, regression prevention
- **Negative**: Additional maintenance overhead
- **Mitigation**: Automated test execution and clear test organization

## ADR-010: Documentation-First Development

**Date**: 2025-09-19
**Status**: Accepted
**Context**: Complex system requiring clear documentation

### Decision
Maintain comprehensive documentation:
- README for quick start and overview
- Architecture decisions (this document)
- User guide with examples
- Troubleshooting guide
- Code comments and function documentation

### Consequences
- **Positive**: Easier onboarding, maintenance, and debugging
- **Negative**: Documentation maintenance overhead
- **Mitigation**: Documentation verification tools and automated checks