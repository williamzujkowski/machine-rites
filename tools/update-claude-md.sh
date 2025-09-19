#!/bin/bash

# tools/update-claude-md.sh
# Automated CLAUDE.md updater script
# Usage: ./tools/update-claude-md.sh [--dry-run] [--backup] [--verbose]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAUDE_MD_FILE="$PROJECT_ROOT/CLAUDE.md"
DRY_RUN=false
BACKUP=false
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_help() {
    cat << EOF
Automated CLAUDE.md Updater

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --dry-run           Show what would be updated without making changes
    --backup            Create backup before updating
    --verbose           Enable verbose output
    --help              Show this help message

EXAMPLES:
    $0                  # Update CLAUDE.md
    $0 --dry-run        # Preview changes
    $0 --backup         # Update with backup
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
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --backup)
            BACKUP=true
            shift
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

# Function to create backup
create_backup() {
    if [[ "$BACKUP" == "true" ]] && [[ -f "$CLAUDE_MD_FILE" ]]; then
        local backup_file="${CLAUDE_MD_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$CLAUDE_MD_FILE" "$backup_file"
        success "Backup created: $backup_file"
    fi
}

# Function to scan for available tools and scripts
scan_available_tools() {
    log "Scanning for available tools and scripts..."

    # Find script files
    local scripts=()
    while IFS= read -r -d '' script; do
        scripts+=("$(basename "$script")")
    done < <(find tools/ -type f -name "*.sh" -executable -print0 2>/dev/null || true)

    # Find package.json scripts
    local npm_scripts=()
    if [[ -f "package.json" ]]; then
        npm_scripts=($(grep -A 20 '"scripts"' package.json | grep -oE '"[^"]+":' | sed 's/"//g; s/://g' | tail -n +2 || true))
    fi

    # Find MCP servers
    local mcp_servers=()
    if command -v claude >/dev/null 2>&1; then
        mcp_servers=($(claude mcp list 2>/dev/null | grep -oE '[a-zA-Z0-9_-]+' || true))
    fi

    echo "scripts:${scripts[*]:-}"
    echo "npm_scripts:${npm_scripts[*]:-}"
    echo "mcp_servers:${mcp_servers[*]:-}"
}

# Function to scan for agents and modes
scan_agent_capabilities() {
    log "Scanning for agent capabilities..."

    # SPARC modes
    local sparc_modes=()
    if command -v npx >/dev/null 2>&1; then
        sparc_modes=($(npx claude-flow sparc modes 2>/dev/null | grep -oE '[a-zA-Z0-9_-]+' | head -20 || true))
    fi

    # Available agents (from documentation or config)
    local agents=()
    agents=(
        "coder" "reviewer" "tester" "planner" "researcher"
        "hierarchical-coordinator" "mesh-coordinator" "adaptive-coordinator"
        "collective-intelligence-coordinator" "swarm-memory-manager"
        "byzantine-coordinator" "raft-manager" "gossip-coordinator"
        "consensus-builder" "crdt-synchronizer" "quorum-manager"
        "security-manager" "perf-analyzer" "performance-benchmarker"
        "task-orchestrator" "memory-coordinator" "smart-agent"
        "github-modes" "pr-manager" "code-review-swarm"
        "issue-tracker" "release-manager" "workflow-automation"
        "project-board-sync" "repo-architect" "multi-repo-swarm"
        "sparc-coord" "sparc-coder" "specification" "pseudocode"
        "architecture" "refinement" "backend-dev" "mobile-dev"
        "ml-developer" "cicd-engineer" "api-docs" "system-architect"
        "code-analyzer" "base-template-generator" "tdd-london-swarm"
        "production-validator" "migration-planner" "swarm-init"
    )

    echo "sparc_modes:${sparc_modes[*]:-}"
    echo "agents:${agents[*]:-}"
}

# Function to check project status
check_project_status() {
    log "Checking project status..."

    # Git status
    local git_status=""
    if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
        git_status="true"
        local branch_name
        branch_name=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        echo "git_status:$git_status"
        echo "git_branch:$branch_name"
    else
        echo "git_status:false"
    fi

    # Package.json info
    if [[ -f "package.json" ]]; then
        local pkg_name
        pkg_name=$(grep '"name"' package.json | sed 's/.*"name".*"\([^"]*\)".*/\1/' 2>/dev/null || echo "unknown")
        local pkg_version
        pkg_version=$(grep '"version"' package.json | sed 's/.*"version".*"\([^"]*\)".*/\1/' 2>/dev/null || echo "unknown")
        echo "package_name:$pkg_name"
        echo "package_version:$pkg_version"
    fi

    # Directory structure
    local has_src="false"
    local has_tests="false"
    local has_docs="false"
    local has_tools="false"

    [[ -d "src" ]] && has_src="true"
    [[ -d "tests" ]] || [[ -d "test" ]] && has_tests="true"
    [[ -d "docs" ]] && has_docs="true"
    [[ -d "tools" ]] && has_tools="true"

    echo "has_src:$has_src"
    echo "has_tests:$has_tests"
    echo "has_docs:$has_docs"
    echo "has_tools:$has_tools"
}

# Function to get file counts and stats
get_project_stats() {
    log "Gathering project statistics..."

    # Count source files
    local js_files
    js_files=$(find . -name "*.js" -o -name "*.jsx" -o -name "*.ts" -o -name "*.tsx" | grep -v node_modules | wc -l)
    local py_files
    py_files=$(find . -name "*.py" | grep -v node_modules | wc -l)
    local sh_files
    sh_files=$(find . -name "*.sh" -o -name "*.bash" | grep -v node_modules | wc -l)

    echo "js_files:$js_files"
    echo "py_files:$py_files"
    echo "sh_files:$sh_files"

    # Get last update
    local last_update
    if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
        last_update=$(git log -1 --format="%ai" 2>/dev/null | cut -d' ' -f1 || date +%Y-%m-%d)
    else
        last_update=$(date +%Y-%m-%d)
    fi
    echo "last_update:$last_update"
}

# Function to update CLAUDE.md sections
update_claude_md() {
    log "Updating CLAUDE.md..."

    if [[ ! -f "$CLAUDE_MD_FILE" ]]; then
        error "CLAUDE.md not found at $CLAUDE_MD_FILE"
        return 1
    fi

    # Get current project info
    local project_info
    project_info=$(
        scan_available_tools
        scan_agent_capabilities
        check_project_status
        get_project_stats
    )

    local temp_file=$(mktemp)
    local in_section=""
    local updated_sections=()

    # Read CLAUDE.md and update relevant sections
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            "## 🚀 Available Agents"*)
                in_section="agents"
                echo "$line" >> "$temp_file"
                echo "" >> "$temp_file"

                # Update agent list
                local agents
                agents=$(echo "$project_info" | grep "^agents:" | cut -d: -f2-)
                if [[ -n "$agents" ]]; then
                    echo "### Core Development" >> "$temp_file"
                    echo "\`coder\`, \`reviewer\`, \`tester\`, \`planner\`, \`researcher\`" >> "$temp_file"
                    echo "" >> "$temp_file"
                    echo "### Swarm Coordination" >> "$temp_file"
                    echo "\`hierarchical-coordinator\`, \`mesh-coordinator\`, \`adaptive-coordinator\`, \`collective-intelligence-coordinator\`, \`swarm-memory-manager\`" >> "$temp_file"
                    echo "" >> "$temp_file"
                    echo "Total agents available: $(echo "$agents" | wc -w)" >> "$temp_file"
                    echo "" >> "$temp_file"
                fi
                updated_sections+=("agents")
                ;;
            "## SPARC Commands"*)
                in_section="sparc"
                echo "$line" >> "$temp_file"
                echo "" >> "$temp_file"

                # Update SPARC commands
                local sparc_modes
                sparc_modes=$(echo "$project_info" | grep "^sparc_modes:" | cut -d: -f2-)
                if [[ -n "$sparc_modes" ]]; then
                    echo "### Available Modes" >> "$temp_file"
                    for mode in $sparc_modes; do
                        echo "- \`$mode\`" >> "$temp_file"
                    done
                    echo "" >> "$temp_file"
                fi
                updated_sections+=("sparc")
                ;;
            "## 🚀 Quick Setup"*)
                in_section="setup"
                echo "$line" >> "$temp_file"
                echo "" >> "$temp_file"

                # Update setup section with current MCP servers
                local mcp_servers
                mcp_servers=$(echo "$project_info" | grep "^mcp_servers:" | cut -d: -f2-)

                echo "\`\`\`bash" >> "$temp_file"
                echo "# Add MCP servers (Claude Flow required, others optional)" >> "$temp_file"
                echo "claude mcp add claude-flow npx claude-flow@alpha mcp start" >> "$temp_file"
                if [[ -n "$mcp_servers" ]]; then
                    for server in $mcp_servers; do
                        if [[ "$server" != "claude-flow" ]]; then
                            echo "claude mcp add $server npx $server mcp start  # Optional: Enhanced features" >> "$temp_file"
                        fi
                    done
                fi
                echo "\`\`\`" >> "$temp_file"
                echo "" >> "$temp_file"
                updated_sections+=("setup")
                ;;
            "### Build Commands"*)
                in_section="build"
                echo "$line" >> "$temp_file"

                # Update build commands
                local npm_scripts
                npm_scripts=$(echo "$project_info" | grep "^npm_scripts:" | cut -d: -f2-)
                if [[ -n "$npm_scripts" ]]; then
                    for script in $npm_scripts; do
                        echo "- \`npm run $script\` - Run $script" >> "$temp_file"
                    done
                else
                    echo "- \`npm run build\` - Build project" >> "$temp_file"
                    echo "- \`npm run test\` - Run tests" >> "$temp_file"
                    echo "- \`npm run lint\` - Linting" >> "$temp_file"
                fi
                echo "" >> "$temp_file"
                updated_sections+=("build")
                ;;
            "Last updated:"*)
                # Update timestamp
                echo "Last updated: $(date)" >> "$temp_file"
                ;;
            "## "*)
                # End current section when we hit a new one
                in_section=""
                echo "$line" >> "$temp_file"
                ;;
            *)
                # For lines not in special sections, just copy them
                if [[ -z "$in_section" ]] || [[ ! " ${updated_sections[*]} " =~ " ${in_section} " ]]; then
                    echo "$line" >> "$temp_file"
                fi
                ;;
        esac
    done < "$CLAUDE_MD_FILE"

    # Show changes if dry run
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN - Changes that would be made:"
        diff "$CLAUDE_MD_FILE" "$temp_file" || true
        rm "$temp_file"
        return 0
    fi

    # Apply changes
    mv "$temp_file" "$CLAUDE_MD_FILE"
    success "CLAUDE.md updated successfully"

    # Show what was updated
    if [[ ${#updated_sections[@]} -gt 0 ]]; then
        log "Updated sections: ${updated_sections[*]}"
    fi
}

# Function to validate the updated file
validate_claude_md() {
    log "Validating updated CLAUDE.md..."

    if [[ ! -f "$CLAUDE_MD_FILE" ]]; then
        error "CLAUDE.md not found"
        return 1
    fi

    # Check for required sections
    local required_sections=(
        "Claude Code Configuration"
        "CRITICAL: CONCURRENT EXECUTION"
        "SPARC Commands"
        "Available Agents"
        "Quick Setup"
    )

    local missing_sections=()
    for section in "${required_sections[@]}"; do
        if ! grep -q "$section" "$CLAUDE_MD_FILE"; then
            missing_sections+=("$section")
        fi
    done

    if [[ ${#missing_sections[@]} -gt 0 ]]; then
        error "Missing required sections: ${missing_sections[*]}"
        return 1
    fi

    # Check for valid markdown syntax
    if command -v markdownlint >/dev/null 2>&1; then
        if ! markdownlint "$CLAUDE_MD_FILE" 2>/dev/null; then
            warn "Markdown syntax issues detected"
        fi
    fi

    success "CLAUDE.md validation passed"
}

# Main execution
main() {
    log "Starting CLAUDE.md update process..."
    log "Project root: $PROJECT_ROOT"
    log "Dry run: $DRY_RUN"
    log "Backup: $BACKUP"

    # Create backup if requested
    create_backup

    # Update the file
    if update_claude_md; then
        # Validate the result
        validate_claude_md

        if [[ "$DRY_RUN" != "true" ]]; then
            success "CLAUDE.md update completed successfully"

            # Offer to commit changes
            if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
                if git diff --quiet "$CLAUDE_MD_FILE"; then
                    log "No changes to commit"
                else
                    warn "CLAUDE.md has uncommitted changes. Consider running:"
                    echo "git add CLAUDE.md && git commit -m 'chore: update CLAUDE.md with current project state'"
                fi
            fi
        fi
    else
        error "Failed to update CLAUDE.md"
        exit 1
    fi
}

# Run main function
main "$@"