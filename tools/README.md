# Documentation Accuracy and Code Quality Tools

This directory contains automated tools for maintaining documentation accuracy and detecting vestigial code in the project.

## 🛠️ Available Tools

### 1. Vestigial Code Detection (`check-vestigial.sh`)

Detects unused code, functions, and files that may be safely removed from the codebase.

**Features:**
- Scans for unused files not referenced by imports/requires
- Identifies unused function declarations
- Detects dead imports in JavaScript/TypeScript files
- Supports JSON and Markdown output formats
- Configurable verbosity and output options

**Usage:**
```bash
# Basic scan with markdown output
./tools/check-vestigial.sh

# JSON output to file
./tools/check-vestigial.sh --format json --output vestigial-report.json

# Verbose output
./tools/check-vestigial.sh --verbose
```

**Detection Algorithm:**
- **Unused Files**: Searches for import/require statements across the codebase
- **Unused Functions**: Uses regex patterns to find function declarations and usage
- **Dead Imports**: Analyzes import statements and checks for variable usage

### 2. Documentation Verification (`verify-docs.sh`)

Verifies documentation freshness and accuracy across the project.

**Features:**
- Checks for missing files referenced in documentation
- Identifies outdated documentation (compared to source file modification times)
- Detects broken internal links in markdown files
- Finds source files lacking documentation
- Identifies inconsistent information (versions, URLs, etc.)
- Auto-fix capability for common issues

**Usage:**
```bash
# Basic verification
./tools/verify-docs.sh

# Auto-fix issues
./tools/verify-docs.sh --fix

# JSON output for CI/CD
./tools/verify-docs.sh --format json --output doc-report.json
```

**Verification Checks:**
- **Missing Files**: Validates file paths in markdown links and code blocks
- **Outdated Docs**: Compares modification times between docs and related source files
- **Broken Links**: Tests internal markdown links for target existence
- **Missing Docs**: Identifies source files without corresponding documentation
- **Inconsistencies**: Checks for outdated version numbers, HTTP vs HTTPS URLs

### 3. CLAUDE.md Updater (`update-claude-md.sh`)

Automatically updates CLAUDE.md with current project state and available tools.

**Features:**
- Scans for available tools and scripts
- Updates agent capability lists
- Refreshes SPARC command documentation
- Updates project statistics and metadata
- Backup support and dry-run mode

**Usage:**
```bash
# Update CLAUDE.md
./tools/update-claude-md.sh

# Preview changes without applying
./tools/update-claude-md.sh --dry-run

# Create backup before updating
./tools/update-claude-md.sh --backup
```

**Update Sections:**
- Available agents and their counts
- SPARC modes and commands
- MCP server configurations
- Build commands from package.json
- Project statistics and last update timestamp

### 4. Pre-commit Hooks Setup (`setup-doc-hooks.sh`)

Installs Git hooks to automatically maintain documentation quality.

**Features:**
- Pre-commit: Runs documentation verification before commits
- Commit-msg: Suggests documentation updates for significant changes
- Post-commit: Background documentation health checks
- Pre-push: Comprehensive verification before pushing
- Configurable behavior and emergency bypass options

**Usage:**
```bash
# Install hooks
./tools/setup-doc-hooks.sh

# Remove hooks
./tools/setup-doc-hooks.sh --uninstall

# Check status
./tools/setup-doc-hooks.sh --status
```

**Hook Behavior:**
- **Pre-commit**: Fails if >5 critical documentation issues found
- **Commit-msg**: Suggests doc updates for large file changes (>50 lines)
- **Post-commit**: Runs background checks and logs results
- **Pre-push**: Prevents pushes with critical documentation issues

### 5. Weekly Audit Automation (`weekly-audit.sh`)

Comprehensive weekly analysis of documentation and code quality.

**Features:**
- Combines all verification tools into a single report
- Git activity analysis (commits, contributors, file changes)
- Project health metrics (dependencies, test coverage, CI/CD)
- Automated report generation with recommendations
- Email and Slack notification support
- Report archiving and cleanup

**Usage:**
```bash
# Basic weekly audit
./tools/weekly-audit.sh

# Custom output directory
./tools/weekly-audit.sh --output-dir /path/to/reports

# With email notification
./tools/weekly-audit.sh --email admin@example.com

# With Slack webhook
./tools/weekly-audit.sh --slack https://hooks.slack.com/...
```

**Report Sections:**
- Executive summary with key metrics
- Detailed documentation issues
- Code quality findings
- Git activity analysis
- Project health assessment
- Prioritized recommendations

## 🔄 CI/CD Integration

### GitHub Actions Workflow

The `documentation-check.yml` workflow provides automated verification:

**Triggers:**
- Push to main/develop branches
- Pull requests
- Weekly schedule (Sundays at 2 AM UTC)
- Manual dispatch with options

**Features:**
- Runs all verification tools
- Posts results as PR comments
- Creates weekly audit issues
- Auto-commits fixes on schedule
- Uploads reports as artifacts
- Fails on critical issues (>5 doc problems)

**Configuration:**
```yaml
# Manual trigger options
check_type: all|docs-only|vestigial-only|audit
fix_issues: true|false
```

## 📊 Output Formats

### JSON Format
All tools support structured JSON output for automation:

```json
{
  "generated_on": "2025-09-19T03:45:00Z",
  "project": "machine-rites",
  "summary": {
    "missing_files": 0,
    "outdated_docs": 2,
    "broken_links": 1
  },
  "missing_files": [],
  "outdated_docs": [
    "docs/api.md: 5 days behind src/api.js"
  ],
  "broken_links": [
    "README.md: docs/missing.md"
  ]
}
```

### Markdown Format
Human-readable reports with recommendations:

```markdown
# Documentation Verification Report

## Summary
- **Missing Files**: 0
- **Outdated Docs**: 2
- **Broken Links**: 1

## Outdated Documentation
- `docs/api.md: 5 days behind src/api.js`

## Recommendations
1. Review and update documentation to match current code
2. Fix or remove broken internal links
```

## 🔧 Configuration

### Git Hooks Configuration
Edit `.git/hooks/doc-hooks.conf`:

```bash
# Enable vestigial code checking in pre-commit hook
DOC_HOOK_CHECK_VESTIGIAL=false

# Minimum file change threshold for doc update suggestions
DOC_HOOK_CHANGE_THRESHOLD=50

# Skip hooks for emergency commits
DOC_HOOK_EMERGENCY_BYPASS=false
```

### Environment Variables

```bash
# For weekly audit notifications
EMAIL_ADDRESS="team@example.com"
SLACK_WEBHOOK_URL="https://hooks.slack.com/..."

# For CI/CD integration
DOC_CHECK_FAIL_THRESHOLD=5
VESTIGIAL_WARN_THRESHOLD=20
```

## 🎯 Best Practices

### Development Workflow
1. **Before Committing**: Run `./tools/verify-docs.sh --fix`
2. **Weekly**: Review audit reports and address high-priority issues
3. **Before Releases**: Run full audit with `./tools/weekly-audit.sh`
4. **Refactoring**: Use `./tools/check-vestigial.sh` to identify cleanup opportunities

### Maintenance Schedule
- **Daily**: Automated checks via pre-commit hooks
- **Weekly**: Scheduled audit via GitHub Actions
- **Monthly**: Review and update tool configurations
- **Quarterly**: Evaluate tool effectiveness and add new checks

### Integration Tips
1. **CI/CD**: Use JSON output for automated processing
2. **Code Reviews**: Include documentation checks in PR templates
3. **Team Adoption**: Start with warnings before enforcing failures
4. **Customization**: Modify detection patterns for project-specific needs

## 🚀 Advanced Usage

### Custom Detection Patterns

Modify regex patterns in scripts for project-specific needs:

```bash
# In check-vestigial.sh - customize function detection
functions=$(rg "^(export\s+)?(async\s+)?function\s+([a-zA-Z_$][a-zA-Z0-9_$]*)" "$file" -o -r '$3')

# In verify-docs.sh - customize link detection
links=$(rg '\[([^\]]*)\]\(([^)]+)\)' "$doc_file" -o -r '$2')
```

### Batch Operations

Process multiple projects:

```bash
# Run checks across multiple repositories
for repo in repo1 repo2 repo3; do
  cd "$repo"
  ./tools/verify-docs.sh --format json --output "../reports/${repo}-docs.json"
  cd ..
done
```

### Integration with Other Tools

```bash
# Combine with linting
./tools/check-vestigial.sh && npm run lint

# Integrate with testing
./tools/verify-docs.sh --fix && npm test

# Chain with deployment
./tools/weekly-audit.sh --email team@example.com && deploy.sh
```

## 📈 Metrics and Reporting

### Key Metrics Tracked
- Documentation coverage percentage
- Average documentation age vs code age
- Number of broken links over time
- Vestigial code reduction progress
- Team adoption of tools

### Dashboard Integration
Tools output JSON suitable for:
- Grafana dashboards
- GitHub issue tracking
- Slack/Teams notifications
- Custom reporting systems

## 🛡️ Error Handling

### Common Issues and Solutions

**Permission Errors:**
```bash
chmod +x tools/*.sh
```

**Missing Dependencies:**
```bash
# Install ripgrep for faster searching
sudo apt-get install ripgrep

# Install markdownlint for validation
npm install -g markdownlint-cli
```

**Git Hook Conflicts:**
```bash
# Backup existing hooks before installation
./tools/setup-doc-hooks.sh --install
```

### Emergency Bypass

Skip checks when needed:
```bash
# Skip pre-commit checks
git commit --no-verify -m "Emergency fix"

# Skip pre-push checks
git push --no-verify

# Disable hooks temporarily
mv .git/hooks .git/hooks.backup
```

## 🔮 Future Enhancements

### Planned Features
- AI-powered documentation suggestions
- Integration with documentation generators
- Real-time documentation health monitoring
- Advanced semantic analysis for outdated content
- Multi-language support beyond JavaScript/TypeScript

### Contributing

To improve these tools:

1. **Fork the repository**
2. **Add new detection patterns**
3. **Enhance reporting formats**
4. **Improve error handling**
5. **Add tests for edge cases**

### Tool Versioning

Current version: 1.0.0

Version history:
- 1.0.0: Initial release with core functionality
- Future: Enhanced detection algorithms and integrations

---

**Last Updated:** September 19, 2025
**Maintainer:** Documentation Accuracy System
**License:** Same as project license