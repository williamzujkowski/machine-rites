#!/bin/bash

# tools/check-vestigial.sh
# Detects unused code, functions, and files in the codebase
# Usage: ./tools/check-vestigial.sh [--format json|markdown] [--output file]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_FORMAT="markdown"
OUTPUT_FILE=""
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Arrays to store results
declare -a unused_files=()
declare -a unused_functions=()
declare -a unused_variables=()
declare -a dead_imports=()

show_help() {
    cat << EOF
Vestigial Code Detection Tool

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --format FORMAT     Output format: json or markdown (default: markdown)
    --output FILE       Write output to file instead of stdout
    --verbose           Enable verbose output
    --help              Show this help message

EXAMPLES:
    $0                                    # Basic scan with markdown output
    $0 --format json --output report.json # JSON output to file
    $0 --verbose                          # Verbose markdown output
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
        --format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
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

# Validate format
if [[ "$OUTPUT_FORMAT" != "json" && "$OUTPUT_FORMAT" != "markdown" ]]; then
    error "Invalid format: $OUTPUT_FORMAT. Must be 'json' or 'markdown'"
    exit 1
fi

cd "$PROJECT_ROOT"

# Function to check if file is in gitignore or should be excluded
should_exclude_file() {
    local file="$1"

    # Exclude common directories and files
    if [[ "$file" =~ ^(\./)?(\.|node_modules|\.git|dist|build|coverage|\.swarm|\.claude-flow)/ ]]; then
        return 0
    fi

    # Exclude binary files and common non-source files
    if [[ "$file" =~ \.(png|jpg|jpeg|gif|ico|pdf|zip|tar|gz|exe|dll|so|dylib|a|o)$ ]]; then
        return 0
    fi

    # Check if file is in .gitignore
    if command -v git >/dev/null 2>&1 && git check-ignore "$file" >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

# Function to get all source files
get_source_files() {
    find . -type f \( \
        -name "*.js" -o \
        -name "*.jsx" -o \
        -name "*.ts" -o \
        -name "*.tsx" -o \
        -name "*.py" -o \
        -name "*.rb" -o \
        -name "*.go" -o \
        -name "*.rs" -o \
        -name "*.java" -o \
        -name "*.c" -o \
        -name "*.cpp" -o \
        -name "*.h" -o \
        -name "*.hpp" -o \
        -name "*.php" -o \
        -name "*.sh" -o \
        -name "*.bash" -o \
        -name "*.zsh" \
    \) | grep -v -E "^(\./)?(\.|node_modules|\.git|dist|build|coverage|\.swarm|\.claude-flow)/" | sort
}

# Function to detect unused files
detect_unused_files() {
    log "Detecting unused files..."

    local all_files
    mapfile -t all_files < <(get_source_files)

    for file in "${all_files[@]}"; do
        if should_exclude_file "$file"; then
            continue
        fi

        local file_basename
        file_basename=$(basename "$file")
        local file_noext="${file_basename%.*}"

        # Skip certain important files
        if [[ "$file_basename" =~ ^(index|main|app|server|entry|webpack|babel|jest|eslint|prettier|package|README|CHANGELOG|LICENSE)\..*$ ]]; then
            continue
        fi

        # Check if file is referenced anywhere
        local references=0

        # Search for imports/requires
        if command -v rg >/dev/null 2>&1; then
            # Use ripgrep if available (faster)
            references=$(rg -l --type-not=binary "import.*['\"]\.?\.?/?${file_noext}['\"]|require\(['\"]\.?\.?/?${file_noext}['\"]|from ['\"]\.?\.?/?${file_noext}['\"]" . 2>/dev/null | wc -l || echo 0)
        else
            # Fallback to grep
            references=$(grep -r -l "import.*['\"]\.\..*${file_noext}['\"]|require(['\"]\.\..*${file_noext}['\"]|from ['\"]\.\..*${file_noext}['\"]" . 2>/dev/null | wc -l || echo 0)
        fi

        if [[ $references -eq 0 ]]; then
            unused_files+=("$file")
        fi
    done
}

# Function to detect unused functions in JavaScript/TypeScript files
detect_unused_functions() {
    log "Detecting unused functions..."

    local js_files
    mapfile -t js_files < <(find . -name "*.js" -o -name "*.jsx" -o -name "*.ts" -o -name "*.tsx" | grep -v -E "^(\./)?(\.|node_modules|\.git|dist|build|coverage)/" | sort)

    for file in "${js_files[@]}"; do
        if should_exclude_file "$file"; then
            continue
        fi

        # Extract function declarations
        local functions
        if command -v rg >/dev/null 2>&1; then
            mapfile -t functions < <(rg "^(export\s+)?(async\s+)?function\s+([a-zA-Z_$][a-zA-Z0-9_$]*)" "$file" -o -r '$3' 2>/dev/null || true)
        else
            mapfile -t functions < <(grep -o "^(export\s\+)\?(async\s\+)\?function\s\+[a-zA-Z_$][a-zA-Z0-9_$]*" "$file" | sed 's/.*function\s\+//' 2>/dev/null || true)
        fi

        for func in "${functions[@]}"; do
            if [[ -z "$func" ]]; then
                continue
            fi

            # Skip common function names that might be used dynamically
            if [[ "$func" =~ ^(main|init|setup|teardown|beforeEach|afterEach|test|describe|it)$ ]]; then
                continue
            fi

            # Check if function is used anywhere else
            local usage_count=0
            if command -v rg >/dev/null 2>&1; then
                usage_count=$(rg "\b${func}\s*\(" . --type-not=binary -c 2>/dev/null | awk -F: '{sum += $2} END {print sum+0}')
            else
                usage_count=$(grep -r "\b${func}\s*(" . 2>/dev/null | wc -l || echo 0)
            fi

            # If only found once (the declaration), it's unused
            if [[ $usage_count -le 1 ]]; then
                unused_functions+=("${file}:${func}")
            fi
        done
    done
}

# Function to detect dead imports
detect_dead_imports() {
    log "Detecting dead imports..."

    local js_files
    mapfile -t js_files < <(find . -name "*.js" -o -name "*.jsx" -o -name "*.ts" -o -name "*.tsx" | grep -v -E "^(\./)?(\.|node_modules|\.git|dist|build|coverage)/" | sort)

    for file in "${js_files[@]}"; do
        if should_exclude_file "$file"; then
            continue
        fi

        # Extract imports
        local imports
        if command -v rg >/dev/null 2>&1; then
            mapfile -t imports < <(rg "^import\s+.*\s+from|^import\s+['\"]" "$file" 2>/dev/null || true)
        else
            mapfile -t imports < <(grep "^import.*from\|^import.*['\"]" "$file" 2>/dev/null || true)
        fi

        for import_line in "${imports[@]}"; do
            if [[ -z "$import_line" ]]; then
                continue
            fi

            # Extract imported names
            local imported_names
            if [[ "$import_line" =~ import[[:space:]]*\{([^}]+)\} ]]; then
                imported_names="${BASH_REMATCH[1]}"
                # Clean up and split by comma
                imported_names=$(echo "$imported_names" | sed 's/[[:space:]]//g' | tr ',' '\n')

                for name in $imported_names; do
                    if [[ -n "$name" ]] && [[ ! "$name" =~ ^[[:space:]]*$ ]]; then
                        # Check if imported name is used in the file
                        local usage_count=0
                        if command -v rg >/dev/null 2>&1; then
                            usage_count=$(rg "\b${name}\b" "$file" -c 2>/dev/null || echo 0)
                        else
                            usage_count=$(grep -c "\b${name}\b" "$file" 2>/dev/null || echo 0)
                        fi

                        # If only found once (the import), it's dead
                        if [[ $usage_count -le 1 ]]; then
                            dead_imports+=("${file}:${name}")
                        fi
                    fi
                done
            fi
        done
    done
}

# Function to generate markdown report
generate_markdown_report() {
    cat << EOF
# Vestigial Code Detection Report

Generated on: $(date)
Project: $(basename "$PROJECT_ROOT")

## Summary

- **Unused Files**: ${#unused_files[@]}
- **Unused Functions**: ${#unused_functions[@]}
- **Dead Imports**: ${#dead_imports[@]}

EOF

    if [[ ${#unused_files[@]} -gt 0 ]]; then
        cat << EOF
## Unused Files

The following files appear to be unused and could potentially be removed:

EOF
        for file in "${unused_files[@]}"; do
            echo "- \`$file\`"
        done
        echo ""
    fi

    if [[ ${#unused_functions[@]} -gt 0 ]]; then
        cat << EOF
## Unused Functions

The following functions appear to be unused:

EOF
        for func in "${unused_functions[@]}"; do
            echo "- \`$func\`"
        done
        echo ""
    fi

    if [[ ${#dead_imports[@]} -gt 0 ]]; then
        cat << EOF
## Dead Imports

The following imports appear to be unused:

EOF
        for import in "${dead_imports[@]}"; do
            echo "- \`$import\`"
        done
        echo ""
    fi

    cat << EOF
## Recommendations

1. **Before removing any files**: Ensure they are not used dynamically or referenced in non-code files
2. **For unused functions**: Consider if they are part of a public API or used in tests
3. **For dead imports**: Safe to remove, but verify in development environment first
4. **Always**: Run your test suite after making changes

## Notes

- This analysis may have false positives for dynamically referenced code
- Review each item manually before removal
- Consider the impact on public APIs and external dependencies
EOF
}

# Function to generate JSON report
generate_json_report() {
    local json_output=""

    # Start JSON
    json_output='{'
    json_output+='"generated_on":"'$(date)'",'
    json_output+='"project":"'$(basename "$PROJECT_ROOT")'",'
    json_output+='"summary":{'
    json_output+='"unused_files":'${#unused_files[@]}','
    json_output+='"unused_functions":'${#unused_functions[@]}','
    json_output+='"dead_imports":'${#dead_imports[@]}
    json_output+='},'

    # Unused files
    json_output+='"unused_files":['
    for i in "${!unused_files[@]}"; do
        json_output+='"'${unused_files[$i]}'"'
        if [[ $i -lt $((${#unused_files[@]} - 1)) ]]; then
            json_output+=','
        fi
    done
    json_output+='],'

    # Unused functions
    json_output+='"unused_functions":['
    for i in "${!unused_functions[@]}"; do
        json_output+='"'${unused_functions[$i]}'"'
        if [[ $i -lt $((${#unused_functions[@]} - 1)) ]]; then
            json_output+=','
        fi
    done
    json_output+='],'

    # Dead imports
    json_output+='"dead_imports":['
    for i in "${!dead_imports[@]}"; do
        json_output+='"'${dead_imports[$i]}'"'
        if [[ $i -lt $((${#dead_imports[@]} - 1)) ]]; then
            json_output+=','
        fi
    done
    json_output+=']'

    # End JSON
    json_output+='}'

    echo "$json_output" | python3 -m json.tool 2>/dev/null || echo "$json_output"
}

# Main execution
main() {
    log "Starting vestigial code detection..."
    log "Project root: $PROJECT_ROOT"
    log "Output format: $OUTPUT_FORMAT"

    # Run detection functions
    detect_unused_files
    detect_unused_functions
    detect_dead_imports

    # Generate report
    local report_content=""
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        report_content=$(generate_json_report)
    else
        report_content=$(generate_markdown_report)
    fi

    # Output report
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$report_content" > "$OUTPUT_FILE"
        success "Report written to: $OUTPUT_FILE"
    else
        echo "$report_content"
    fi

    # Summary
    local total_issues=$((${#unused_files[@]} + ${#unused_functions[@]} + ${#dead_imports[@]}))
    if [[ $total_issues -eq 0 ]]; then
        success "No vestigial code detected!"
    else
        warn "Found $total_issues potential issues"
    fi
}

# Run main function
main "$@"