#!/bin/bash

# tools/weekly-audit.sh
# Weekly accuracy audit automation script
# Usage: ./tools/weekly-audit.sh [--output-dir dir] [--email address] [--slack webhook] [--verbose]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/reports/weekly-audit-$(date +%Y%m%d)"
EMAIL_ADDRESS=""
SLACK_WEBHOOK=""
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_help() {
    cat << EOF
Weekly Documentation and Code Accuracy Audit

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --output-dir DIR    Directory for report output (default: reports/weekly-audit-YYYYMMDD)
    --email ADDRESS     Send report via email
    --slack WEBHOOK     Send summary to Slack webhook
    --verbose           Enable verbose output
    --help              Show this help message

EXAMPLES:
    $0                                      # Basic weekly audit
    $0 --output-dir /tmp/audit             # Custom output directory
    $0 --email admin@example.com           # Email report
    $0 --slack https://hooks.slack.com/... # Slack notification
    $0 --verbose --email admin@example.com # Verbose with email
EOF
}

log() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[INFO]${NC} $1" >&2
    fi
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --email)
            EMAIL_ADDRESS="$2"
            shift 2
            ;;
        --slack)
            SLACK_WEBHOOK="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

cd "$PROJECT_ROOT"

# Function to setup output directory
setup_output_dir() {
    log "Setting up output directory: $OUTPUT_DIR"

    mkdir -p "$OUTPUT_DIR"

    # Create subdirectories
    mkdir -p "$OUTPUT_DIR/reports"
    mkdir -p "$OUTPUT_DIR/logs"
    mkdir -p "$OUTPUT_DIR/assets"

    success "Output directory created: $OUTPUT_DIR"
}

# Function to run documentation verification
run_doc_verification() {
    log "Running documentation verification..."

    local doc_report="$OUTPUT_DIR/reports/documentation-issues.json"
    local doc_log="$OUTPUT_DIR/logs/doc-verification.log"

    if [[ -f "tools/verify-docs.sh" ]]; then
        log "Running verify-docs.sh..."
        if ./tools/verify-docs.sh --format json --output "$doc_report" > "$doc_log" 2>&1; then
            success "Documentation verification completed"
        else
            warn "Documentation verification completed with issues"
        fi
    else
        warn "verify-docs.sh not found, skipping documentation verification"
        echo '{"error": "verify-docs.sh not found"}' > "$doc_report"
    fi

    echo "$doc_report"
}

# Function to run vestigial code check
run_vestigial_check() {
    log "Running vestigial code check..."

    local vestigial_report="$OUTPUT_DIR/reports/vestigial-code.json"
    local vestigial_log="$OUTPUT_DIR/logs/vestigial-check.log"

    if [[ -f "tools/check-vestigial.sh" ]]; then
        log "Running check-vestigial.sh..."
        if ./tools/check-vestigial.sh --format json --output "$vestigial_report" > "$vestigial_log" 2>&1; then
            success "Vestigial code check completed"
        else
            warn "Vestigial code check completed with issues"
        fi
    else
        warn "check-vestigial.sh not found, skipping vestigial code check"
        echo '{"error": "check-vestigial.sh not found"}' > "$vestigial_report"
    fi

    echo "$vestigial_report"
}

# Function to analyze git changes
analyze_git_changes() {
    log "Analyzing git changes from the past week..."

    local git_report="$OUTPUT_DIR/reports/git-analysis.json"

    if ! command -v git >/dev/null 2>&1 || ! git rev-parse --git-dir >/dev/null 2>&1; then
        warn "Not a git repository or git not available"
        echo '{"error": "not a git repository"}' > "$git_report"
        echo "$git_report"
        return
    fi

    # Get commits from the last week
    local week_ago
    week_ago=$(date -d '7 days ago' '+%Y-%m-%d' 2>/dev/null || date -v-7d '+%Y-%m-%d' 2>/dev/null || echo "$(date '+%Y-%m-%d')")

    local commits_count
    commits_count=$(git rev-list --count --since="$week_ago" HEAD 2>/dev/null || echo 0)

    local changed_files_count
    changed_files_count=$(git diff --name-only --since="$week_ago" HEAD 2>/dev/null | wc -l || echo 0)

    local contributors
    contributors=$(git shortlog --since="$week_ago" -sn HEAD 2>/dev/null | wc -l || echo 0)

    # Get file type statistics
    local js_changes py_changes md_changes sh_changes
    js_changes=$(git diff --name-only --since="$week_ago" HEAD 2>/dev/null | grep -E '\.(js|jsx|ts|tsx)$' | wc -l || echo 0)
    py_changes=$(git diff --name-only --since="$week_ago" HEAD 2>/dev/null | grep -E '\.py$' | wc -l || echo 0)
    md_changes=$(git diff --name-only --since="$week_ago" HEAD 2>/dev/null | grep -E '\.md$' | wc -l || echo 0)
    sh_changes=$(git diff --name-only --since="$week_ago" HEAD 2>/dev/null | grep -E '\.(sh|bash)$' | wc -l || echo 0)

    # Generate JSON report
    cat > "$git_report" << EOF
{
    "period": "last_7_days",
    "start_date": "$week_ago",
    "end_date": "$(date '+%Y-%m-%d')",
    "commits": $commits_count,
    "changed_files": $changed_files_count,
    "contributors": $contributors,
    "file_changes": {
        "javascript": $js_changes,
        "python": $py_changes,
        "markdown": $md_changes,
        "shell": $sh_changes
    }
}
EOF

    success "Git analysis completed"
    echo "$git_report"
}

# Function to check project health
check_project_health() {
    log "Checking overall project health..."

    local health_report="$OUTPUT_DIR/reports/project-health.json"

    # Check for package.json and dependencies
    local has_package_json="false"
    local outdated_deps=0

    if [[ -f "package.json" ]]; then
        has_package_json="true"
        if command -v npm >/dev/null 2>&1; then
            outdated_deps=$(npm outdated --json 2>/dev/null | python3 -c "import json, sys; data=json.load(sys.stdin) if sys.stdin.read().strip() else {}; print(len(data))" 2>/dev/null || echo 0)
        fi
    fi

    # Check test coverage if available
    local test_coverage="unknown"
    if [[ -f "coverage/coverage-summary.json" ]]; then
        test_coverage=$(python3 -c "
import json
try:
    with open('coverage/coverage-summary.json') as f:
        data = json.load(f)
    print(f\"{data['total']['lines']['pct']:.1f}%\")
except:
    print('unknown')
" 2>/dev/null || echo "unknown")
    fi

    # Check for CI/CD files
    local has_ci="false"
    if [[ -f ".github/workflows/ci.yml" ]] || [[ -f ".github/workflows/test.yml" ]] || [[ -f ".gitlab-ci.yml" ]] || [[ -f "azure-pipelines.yml" ]]; then
        has_ci="true"
    fi

    # Check security files
    local has_security="false"
    if [[ -f "SECURITY.md" ]] || [[ -f ".github/SECURITY.md" ]]; then
        has_security="true"
    fi

    # Count total files and size
    local total_files
    total_files=$(find . -type f | grep -v -E '(\./)?(\.|node_modules|\.git|dist|build|coverage)/' | wc -l)

    local repo_size
    if command -v du >/dev/null 2>&1; then
        repo_size=$(du -sh . 2>/dev/null | cut -f1 || echo "unknown")
    else
        repo_size="unknown"
    fi

    # Generate health report
    cat > "$health_report" << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "project_name": "$(basename "$PROJECT_ROOT")",
    "total_files": $total_files,
    "repository_size": "$repo_size",
    "package_management": {
        "has_package_json": $has_package_json,
        "outdated_dependencies": $outdated_deps
    },
    "testing": {
        "coverage": "$test_coverage"
    },
    "ci_cd": {
        "has_ci": $has_ci
    },
    "security": {
        "has_security_policy": $has_security
    },
    "documentation": {
        "has_readme": $([ -f "README.md" ] && echo "true" || echo "false"),
        "has_changelog": $([ -f "CHANGELOG.md" ] && echo "true" || echo "false"),
        "has_contributing": $([ -f "CONTRIBUTING.md" ] && echo "true" || echo "false")
    }
}
EOF

    success "Project health check completed"
    echo "$health_report"
}

# Function to generate comprehensive report
generate_comprehensive_report() {
    log "Generating comprehensive weekly audit report..."

    local doc_report="$1"
    local vestigial_report="$2"
    local git_report="$3"
    local health_report="$4"

    local comprehensive_report="$OUTPUT_DIR/weekly-audit-report.md"

    # Generate markdown report
    cat > "$comprehensive_report" << EOF
# Weekly Audit Report

**Generated:** $(date)
**Project:** $(basename "$PROJECT_ROOT")
**Period:** $(date -d '7 days ago' '+%Y-%m-%d') to $(date '+%Y-%m-%d')

## Executive Summary

EOF

    # Add documentation summary
    if [[ -f "$doc_report" ]]; then
        local doc_issues
        doc_issues=$(python3 -c "
import json
try:
    with open('$doc_report') as f:
        data = json.load(f)
    if 'error' in data:
        print('Documentation verification tool not available')
    else:
        total = sum(data['summary'].values())
        print(f'Found {total} documentation issues')
except:
    print('Error reading documentation report')
" 2>/dev/null || echo "Error reading documentation report")

        echo "- **Documentation:** $doc_issues" >> "$comprehensive_report"
    fi

    # Add vestigial code summary
    if [[ -f "$vestigial_report" ]]; then
        local vestigial_issues
        vestigial_issues=$(python3 -c "
import json
try:
    with open('$vestigial_report') as f:
        data = json.load(f)
    if 'error' in data:
        print('Vestigial code tool not available')
    else:
        total = sum(data['summary'].values())
        print(f'Found {total} potentially unused code items')
except:
    print('Error reading vestigial code report')
" 2>/dev/null || echo "Error reading vestigial code report")

        echo "- **Code Quality:** $vestigial_issues" >> "$comprehensive_report"
    fi

    # Add git activity summary
    if [[ -f "$git_report" ]]; then
        local git_activity
        git_activity=$(python3 -c "
import json
try:
    with open('$git_report') as f:
        data = json.load(f)
    if 'error' in data:
        print('Git analysis not available')
    else:
        print(f'{data[\"commits\"]} commits, {data[\"changed_files\"]} files changed, {data[\"contributors\"]} contributors')
except:
    print('Error reading git report')
" 2>/dev/null || echo "Error reading git report")

        echo "- **Activity:** $git_activity" >> "$comprehensive_report"
    fi

    cat >> "$comprehensive_report" << EOF

## Detailed Reports

### 📚 Documentation Issues

EOF

    # Include detailed documentation issues
    if [[ -f "$doc_report" ]]; then
        python3 -c "
import json
try:
    with open('$doc_report') as f:
        data = json.load(f)

    if 'error' in data:
        print('Documentation verification tool not available.')
    else:
        for category, items in data.items():
            if category == 'summary':
                continue
            if isinstance(items, list) and items:
                print(f'**{category.replace(\"_\", \" \").title()}:**')
                for item in items[:10]:  # Limit to first 10 items
                    print(f'- {item}')
                if len(items) > 10:
                    print(f'- ... and {len(items) - 10} more')
                print()
except Exception as e:
    print(f'Error processing documentation report: {e}')
" >> "$comprehensive_report" 2>/dev/null || echo "Error processing documentation report" >> "$comprehensive_report"
    fi

    cat >> "$comprehensive_report" << EOF

### 🧹 Code Quality Issues

EOF

    # Include vestigial code issues
    if [[ -f "$vestigial_report" ]]; then
        python3 -c "
import json
try:
    with open('$vestigial_report') as f:
        data = json.load(f)

    if 'error' in data:
        print('Vestigial code check tool not available.')
    else:
        for category, items in data.items():
            if category == 'summary':
                continue
            if isinstance(items, list) and items:
                print(f'**{category.replace(\"_\", \" \").title()}:**')
                for item in items[:10]:  # Limit to first 10 items
                    print(f'- {item}')
                if len(items) > 10:
                    print(f'- ... and {len(items) - 10} more')
                print()
except Exception as e:
    print(f'Error processing vestigial code report: {e}')
" >> "$comprehensive_report" 2>/dev/null || echo "Error processing vestigial code report" >> "$comprehensive_report"
    fi

    cat >> "$comprehensive_report" << EOF

### 📊 Project Health

EOF

    # Include project health metrics
    if [[ -f "$health_report" ]]; then
        python3 -c "
import json
try:
    with open('$health_report') as f:
        data = json.load(f)

    print(f'- **Total Files:** {data[\"total_files\"]}')
    print(f'- **Repository Size:** {data[\"repository_size\"]}')
    print(f'- **Test Coverage:** {data[\"testing\"][\"coverage\"]}')
    print(f'- **Outdated Dependencies:** {data[\"package_management\"][\"outdated_dependencies\"]}')
    print(f'- **CI/CD:** {\"Yes\" if data[\"ci_cd\"][\"has_ci\"] else \"No\"}')
    print(f'- **Security Policy:** {\"Yes\" if data[\"security\"][\"has_security_policy\"] else \"No\"}')

    print()
    print('**Documentation Status:**')
    for doc_type, has_doc in data['documentation'].items():
        status = \"✅\" if has_doc else \"❌\"
        print(f'- {doc_type.replace(\"_\", \" \").title()}: {status}')

except Exception as e:
    print(f'Error processing health report: {e}')
" >> "$comprehensive_report" 2>/dev/null || echo "Error processing health report" >> "$comprehensive_report"
    fi

    cat >> "$comprehensive_report" << EOF

## Recommendations

### High Priority
1. **Fix critical documentation issues** - Broken links and missing files impact user experience
2. **Review unused code** - Remove dead code to improve maintainability
3. **Update outdated dependencies** - Security and performance improvements

### Medium Priority
1. **Improve test coverage** - Aim for >80% coverage
2. **Add missing documentation** - Ensure all modules are documented
3. **Setup automated checks** - Prevent future issues with CI/CD

### Low Priority
1. **Optimize repository size** - Consider cleaning up large files
2. **Standardize documentation format** - Consistent structure across all docs
3. **Add security policy** - Clear guidelines for reporting issues

## Next Steps

- [ ] Review and address high-priority issues
- [ ] Schedule team review of recommendations
- [ ] Update CI/CD pipeline with new checks
- [ ] Plan next week's audit improvements

---

*This report was generated automatically by the weekly audit system.*
*For questions or issues, please review the audit tools in the \`tools/\` directory.*
EOF

    success "Comprehensive report generated: $comprehensive_report"
    echo "$comprehensive_report"
}

# Function to send email notification
send_email_notification() {
    local report_file="$1"

    if [[ -z "$EMAIL_ADDRESS" ]]; then
        return 0
    fi

    log "Sending email notification to $EMAIL_ADDRESS..."

    # Check if mail command is available
    if ! command -v mail >/dev/null 2>&1 && ! command -v sendmail >/dev/null 2>&1; then
        warn "No mail command available, skipping email notification"
        return 0
    fi

    local subject="Weekly Audit Report - $(basename "$PROJECT_ROOT") - $(date +%Y-%m-%d)"

    if command -v mail >/dev/null 2>&1; then
        mail -s "$subject" "$EMAIL_ADDRESS" < "$report_file"
        success "Email sent to $EMAIL_ADDRESS"
    else
        warn "Unable to send email - mail command not configured"
    fi
}

# Function to send Slack notification
send_slack_notification() {
    local report_file="$1"

    if [[ -z "$SLACK_WEBHOOK" ]]; then
        return 0
    fi

    log "Sending Slack notification..."

    # Extract summary for Slack
    local summary
    summary=$(head -20 "$report_file" | tail -10 | sed 's/^//' | tr '\n' ' ')

    local payload
    payload=$(cat << EOF
{
    "text": "Weekly Audit Report for $(basename "$PROJECT_ROOT")",
    "attachments": [
        {
            "color": "good",
            "fields": [
                {
                    "title": "Report Generated",
                    "value": "$(date)",
                    "short": true
                },
                {
                    "title": "Summary",
                    "value": "Weekly audit completed. Full report available in repository.",
                    "short": false
                }
            ]
        }
    ]
}
EOF
)

    if command -v curl >/dev/null 2>&1; then
        if curl -s -X POST -H 'Content-type: application/json' --data "$payload" "$SLACK_WEBHOOK" >/dev/null; then
            success "Slack notification sent"
        else
            warn "Failed to send Slack notification"
        fi
    else
        warn "curl not available, skipping Slack notification"
    fi
}

# Function to archive old reports
archive_old_reports() {
    log "Archiving old reports..."

    local reports_dir="$PROJECT_ROOT/reports"

    if [[ ! -d "$reports_dir" ]]; then
        return 0
    fi

    # Move reports older than 30 days to archive
    local archive_dir="$reports_dir/archive"
    mkdir -p "$archive_dir"

    find "$reports_dir" -maxdepth 1 -type d -name "weekly-audit-*" -mtime +30 2>/dev/null | while read -r old_report; do
        local report_name
        report_name=$(basename "$old_report")
        log "Archiving old report: $report_name"
        mv "$old_report" "$archive_dir/"
    done

    success "Old reports archived"
}

# Main execution
main() {
    log "Starting weekly audit process..."
    log "Project root: $PROJECT_ROOT"
    log "Output directory: $OUTPUT_DIR"

    # Setup
    setup_output_dir

    # Run all checks
    local doc_report
    doc_report=$(run_doc_verification)

    local vestigial_report
    vestigial_report=$(run_vestigial_check)

    local git_report
    git_report=$(analyze_git_changes)

    local health_report
    health_report=$(check_project_health)

    # Generate comprehensive report
    local comprehensive_report
    comprehensive_report=$(generate_comprehensive_report "$doc_report" "$vestigial_report" "$git_report" "$health_report")

    # Send notifications
    send_email_notification "$comprehensive_report"
    send_slack_notification "$comprehensive_report"

    # Cleanup
    archive_old_reports

    success "Weekly audit completed successfully!"
    echo ""
    echo "📋 Reports generated in: $OUTPUT_DIR"
    echo "📄 Main report: $comprehensive_report"
    echo ""
    echo "Next steps:"
    echo "1. Review the comprehensive report"
    echo "2. Address high-priority issues"
    echo "3. Schedule team discussion of findings"
}

# Run main function
main "$@"