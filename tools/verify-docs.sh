#!/bin/bash

# tools/verify-docs.sh
# Verifies documentation freshness and accuracy
# Usage: ./tools/verify-docs.sh [--format json|markdown] [--output file] [--fix]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_FORMAT="markdown"
OUTPUT_FILE=""
FIX_MODE=false
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Arrays to store results
declare -a missing_files=()
declare -a outdated_docs=()
declare -a broken_links=()
declare -a missing_docs=()
declare -a inconsistent_info=()

show_help() {
    cat << EOF
Documentation Verification Tool

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --format FORMAT     Output format: json or markdown (default: markdown)
    --output FILE       Write output to file instead of stdout
    --fix               Attempt to fix issues automatically
    --verbose           Enable verbose output
    --help              Show this help message

EXAMPLES:
    $0                                    # Basic verification with markdown output
    $0 --format json --output report.json # JSON output to file
    $0 --fix                              # Verify and fix issues
    $0 --verbose --fix                    # Verbose verification with fixes
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
        --fix)
            FIX_MODE=true
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

# Validate format
if [[ "$OUTPUT_FORMAT" != "json" && "$OUTPUT_FORMAT" != "markdown" ]]; then
    error "Invalid format: $OUTPUT_FORMAT. Must be 'json' or 'markdown'"
    exit 1
fi

cd "$PROJECT_ROOT"

# Function to get all documentation files
get_doc_files() {
    find . -type f \( \
        -name "*.md" -o \
        -name "*.rst" -o \
        -name "*.txt" -o \
        -name "*.adoc" \
    \) | grep -v -E "^(\./)?(\.|node_modules|\.git|dist|build|coverage|\.swarm|\.claude-flow)/" | sort
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
        -name "*.zsh" -o \
        -name "package.json" -o \
        -name "*.yml" -o \
        -name "*.yaml" -o \
        -name "*.toml" -o \
        -name "Dockerfile*" -o \
        -name "*.env*" \
    \) | grep -v -E "^(\./)?(\.|node_modules|\.git|dist|build|coverage|\.swarm|\.claude-flow)/" | sort
}

# Function to check for missing files referenced in documentation
check_missing_files() {
    log "Checking for missing files referenced in documentation..."

    local doc_files
    mapfile -t doc_files < <(get_doc_files)

    for doc_file in "${doc_files[@]}"; do
        log "Checking references in $doc_file"

        # Find file references in markdown format [text](path) or `path`
        local file_refs
        if command -v rg >/dev/null 2>&1; then
            mapfile -t file_refs < <(rg '\]\([^)]+\)|`[^`/]*\.[a-zA-Z]+`|`\./[^`]+`' "$doc_file" -o 2>/dev/null || true)
        else
            mapfile -t file_refs < <(grep -o '\]\([^)]*\)\|`[^`/]*\.[a-zA-Z]\+`\|`\./[^`]\+`' "$doc_file" 2>/dev/null || true)
        fi

        for ref in "${file_refs[@]}"; do
            # Clean up the reference
            local clean_ref
            clean_ref=$(echo "$ref" | sed 's/.*(\([^)]*\)).*/\1/' | sed 's/`//g')

            # Skip URLs and external references
            if [[ "$clean_ref" =~ ^(https?://|mailto:|#) ]]; then
                continue
            fi

            # Skip if it's just a file extension or doesn't look like a path
            if [[ ! "$clean_ref" =~ / ]] && [[ ! "$clean_ref" =~ \. ]]; then
                continue
            fi

            # Convert relative path to absolute
            local abs_path
            if [[ "$clean_ref" =~ ^\./ ]]; then
                abs_path="$(dirname "$doc_file")/${clean_ref#./}"
            elif [[ "$clean_ref" =~ ^/ ]]; then
                abs_path="${clean_ref#/}"
            else
                abs_path="$clean_ref"
            fi

            # Check if file exists
            if [[ ! -f "$abs_path" ]] && [[ ! -d "$abs_path" ]]; then
                missing_files+=("${doc_file}: ${clean_ref}")
            fi
        done
    done
}

# Function to check for outdated documentation
check_outdated_docs() {
    log "Checking for outdated documentation..."

    local doc_files
    mapfile -t doc_files < <(get_doc_files)

    for doc_file in "${doc_files[@]}"; do
        if [[ ! -f "$doc_file" ]]; then
            continue
        fi

        local doc_mtime
        doc_mtime=$(stat -c %Y "$doc_file" 2>/dev/null || stat -f %m "$doc_file" 2>/dev/null || echo 0)

        # Find related source files (same directory or mentioned in doc)
        local related_files=()
        local doc_dir
        doc_dir=$(dirname "$doc_file")

        # Add source files from same directory
        while IFS= read -r -d '' file; do
            related_files+=("$file")
        done < <(find "$doc_dir" -maxdepth 1 -type f \( \
            -name "*.js" -o -name "*.jsx" -o -name "*.ts" -o -name "*.tsx" -o \
            -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" \
        \) -print0 2>/dev/null || true)

        # Check if any related files are newer than the documentation
        for source_file in "${related_files[@]}"; do
            local source_mtime
            source_mtime=$(stat -c %Y "$source_file" 2>/dev/null || stat -f %m "$source_file" 2>/dev/null || echo 0)

            if [[ $source_mtime -gt $doc_mtime ]]; then
                local days_diff=$(( (source_mtime - doc_mtime) / 86400 ))
                if [[ $days_diff -gt 7 ]]; then  # Only report if more than a week old
                    outdated_docs+=("${doc_file}: ${days_diff} days behind ${source_file}")
                fi
            fi
        done
    done
}

# Function to check for broken internal links
check_broken_links() {
    log "Checking for broken internal links..."

    local doc_files
    mapfile -t doc_files < <(get_doc_files)

    for doc_file in "${doc_files[@]}"; do
        log "Checking links in $doc_file"

        # Find markdown links
        local links
        if command -v rg >/dev/null 2>&1; then
            mapfile -t links < <(rg '\[([^\]]*)\]\(([^)]+)\)' "$doc_file" -o -r '$2' 2>/dev/null || true)
        else
            mapfile -t links < <(grep -o '\[[^\]]*\]([^)]*)' "$doc_file" | sed 's/.*(\([^)]*\)).*/\1/' 2>/dev/null || true)
        fi

        for link in "${links[@]}"; do
            # Skip external URLs
            if [[ "$link" =~ ^(https?://|mailto:|ftp://) ]]; then
                continue
            fi

            # Skip anchors for now (would need HTML parsing)
            if [[ "$link" =~ ^# ]]; then
                continue
            fi

            # Convert relative links to absolute paths
            local abs_link
            if [[ "$link" =~ ^\./ ]]; then
                abs_link="$(dirname "$doc_file")/${link#./}"
            elif [[ "$link" =~ ^/ ]]; then
                abs_link="${link#/}"
            else
                abs_link="$(dirname "$doc_file")/$link"
            fi

            # Check if target exists
            if [[ ! -f "$abs_link" ]] && [[ ! -d "$abs_link" ]]; then
                broken_links+=("${doc_file}: ${link}")
            fi
        done
    done
}

# Function to check for missing documentation
check_missing_docs() {
    log "Checking for missing documentation..."

    local source_files
    mapfile -t source_files < <(get_source_files)

    for source_file in "${source_files[@]}"; do
        local file_dir
        file_dir=$(dirname "$source_file")
        local file_base
        file_base=$(basename "$source_file" | sed 's/\.[^.]*$//')

        # Skip certain files that don't need documentation
        if [[ "$file_base" =~ ^(index|main|test|spec|config|webpack|babel|jest|eslint|prettier).*$ ]]; then
            continue
        fi

        # Check for corresponding documentation
        local has_docs=false

        # Look for README in same directory
        if [[ -f "${file_dir}/README.md" ]] || [[ -f "${file_dir}/readme.md" ]]; then
            has_docs=true
        fi

        # Look for file-specific documentation
        if [[ -f "${file_dir}/${file_base}.md" ]] || [[ -f "${file_dir}/${file_base}.rst" ]]; then
            has_docs=true
        fi

        # Look for docs directory
        if [[ -d "${file_dir}/docs" ]] || [[ -d "./docs" ]]; then
            has_docs=true
        fi

        # Check if file is mentioned in any documentation
        local doc_files
        mapfile -t doc_files < <(get_doc_files)
        for doc_file in "${doc_files[@]}"; do
            if grep -q "$file_base\|$(basename "$source_file")" "$doc_file" 2>/dev/null; then
                has_docs=true
                break
            fi
        done

        if [[ "$has_docs" == "false" ]]; then
            missing_docs+=("$source_file")
        fi
    done
}

# Function to check for inconsistent information
check_inconsistent_info() {
    log "Checking for inconsistent information..."

    # Check package.json vs README version
    if [[ -f "package.json" ]] && [[ -f "README.md" ]]; then
        local pkg_version
        pkg_version=$(grep '"version"' package.json | sed 's/.*"version".*"\([^"]*\)".*/\1/' 2>/dev/null || echo "")

        if [[ -n "$pkg_version" ]]; then
            if ! grep -q "$pkg_version" README.md 2>/dev/null; then
                inconsistent_info+=("README.md: Version mismatch with package.json ($pkg_version)")
            fi
        fi
    fi

    # Check for outdated URLs or references
    local doc_files
    mapfile -t doc_files < <(get_doc_files)

    for doc_file in "${doc_files[@]}"; do
        # Check for common outdated patterns
        if grep -q "http://github.com" "$doc_file" 2>/dev/null; then
            inconsistent_info+=("${doc_file}: Uses http:// instead of https:// for GitHub URLs")
        fi

        # Check for outdated Node.js versions in documentation
        if grep -qE "node.*[0-9]+\.[0-9]+" "$doc_file" 2>/dev/null; then
            local mentioned_versions
            mapfile -t mentioned_versions < <(grep -oE "node.*([0-9]+\.[0-9]+)" "$doc_file" | grep -oE "[0-9]+\.[0-9]+" || true)

            for version in "${mentioned_versions[@]}"; do
                local major_version
                major_version=$(echo "$version" | cut -d. -f1)
                if [[ $major_version -lt 16 ]]; then
                    inconsistent_info+=("${doc_file}: References outdated Node.js version $version")
                fi
            done
        fi
    done
}

# Function to fix issues automatically
fix_issues() {
    if [[ "$FIX_MODE" != "true" ]]; then
        return
    fi

    log "Attempting to fix issues automatically..."

    # Fix broken links where possible
    for broken_link in "${broken_links[@]}"; do
        local doc_file="${broken_link%%:*}"
        local link="${broken_link#*: }"

        # Try to find the file in a different location
        local basename_link
        basename_link=$(basename "$link")

        local found_file
        found_file=$(find . -name "$basename_link" -type f | head -1 2>/dev/null || echo "")

        if [[ -n "$found_file" ]]; then
            log "Attempting to fix broken link in $doc_file: $link -> $found_file"
            # This would require more sophisticated text replacement
            # For now, just log what could be fixed
            warn "Could fix: $doc_file - replace '$link' with '$found_file'"
        fi
    done

    # Generate missing README files
    for missing_doc in "${missing_docs[@]}"; do
        local doc_dir
        doc_dir=$(dirname "$missing_doc")

        if [[ ! -f "${doc_dir}/README.md" ]]; then
            log "Creating basic README.md for $doc_dir"

            local module_name
            module_name=$(basename "$doc_dir")

            cat > "${doc_dir}/README.md" << EOF
# $module_name

## Overview

This module contains:

$(find "$doc_dir" -maxdepth 1 -type f -name "*.js" -o -name "*.ts" -o -name "*.py" | sed 's|.*/|-|' | head -10)

## Usage

TODO: Add usage instructions

## API

TODO: Document public API

Last updated: $(date)
EOF
            success "Created ${doc_dir}/README.md"
        fi
    done
}

# Function to generate markdown report
generate_markdown_report() {
    cat << EOF
# Documentation Verification Report

Generated on: $(date)
Project: $(basename "$PROJECT_ROOT")

## Summary

- **Missing Files**: ${#missing_files[@]}
- **Outdated Docs**: ${#outdated_docs[@]}
- **Broken Links**: ${#broken_links[@]}
- **Missing Docs**: ${#missing_docs[@]}
- **Inconsistent Info**: ${#inconsistent_info[@]}

EOF

    if [[ ${#missing_files[@]} -gt 0 ]]; then
        cat << EOF
## Missing Files

The following files are referenced in documentation but do not exist:

EOF
        for file in "${missing_files[@]}"; do
            echo "- \`$file\`"
        done
        echo ""
    fi

    if [[ ${#outdated_docs[@]} -gt 0 ]]; then
        cat << EOF
## Outdated Documentation

The following documentation appears to be outdated:

EOF
        for doc in "${outdated_docs[@]}"; do
            echo "- \`$doc\`"
        done
        echo ""
    fi

    if [[ ${#broken_links[@]} -gt 0 ]]; then
        cat << EOF
## Broken Links

The following internal links are broken:

EOF
        for link in "${broken_links[@]}"; do
            echo "- \`$link\`"
        done
        echo ""
    fi

    if [[ ${#missing_docs[@]} -gt 0 ]]; then
        cat << EOF
## Missing Documentation

The following files lack documentation:

EOF
        for missing in "${missing_docs[@]}"; do
            echo "- \`$missing\`"
        done
        echo ""
    fi

    if [[ ${#inconsistent_info[@]} -gt 0 ]]; then
        cat << EOF
## Inconsistent Information

The following inconsistencies were found:

EOF
        for inconsistency in "${inconsistent_info[@]}"; do
            echo "- \`$inconsistency\`"
        done
        echo ""
    fi

    cat << EOF
## Recommendations

1. **Missing Files**: Update documentation to remove references or create missing files
2. **Outdated Docs**: Review and update documentation to match current code
3. **Broken Links**: Fix or remove broken internal links
4. **Missing Docs**: Add README files or documentation for undocumented modules
5. **Inconsistencies**: Update documentation to reflect current project state

## Next Steps

- Run with \`--fix\` flag to auto-generate basic documentation
- Review each issue manually for context
- Set up automated documentation updates
- Consider using documentation generation tools
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
    json_output+='"missing_files":'${#missing_files[@]}','
    json_output+='"outdated_docs":'${#outdated_docs[@]}','
    json_output+='"broken_links":'${#broken_links[@]}','
    json_output+='"missing_docs":'${#missing_docs[@]}','
    json_output+='"inconsistent_info":'${#inconsistent_info[@]}
    json_output+='},'

    # Helper function to add JSON array
    add_json_array() {
        local array_name="$1"
        shift
        local -n arr_ref=$array_name

        json_output+='"'$array_name'":['
        for i in "${!arr_ref[@]}"; do
            json_output+='"'${arr_ref[$i]}'"'
            if [[ $i -lt $((${#arr_ref[@]} - 1)) ]]; then
                json_output+=','
            fi
        done
        json_output+=']'
    }

    add_json_array "missing_files" "${missing_files[@]}"
    json_output+=','
    add_json_array "outdated_docs" "${outdated_docs[@]}"
    json_output+=','
    add_json_array "broken_links" "${broken_links[@]}"
    json_output+=','
    add_json_array "missing_docs" "${missing_docs[@]}"
    json_output+=','
    add_json_array "inconsistent_info" "${inconsistent_info[@]}"

    # End JSON
    json_output+='}'

    echo "$json_output" | python3 -m json.tool 2>/dev/null || echo "$json_output"
}

# Main execution
main() {
    log "Starting documentation verification..."
    log "Project root: $PROJECT_ROOT"
    log "Output format: $OUTPUT_FORMAT"
    log "Fix mode: $FIX_MODE"

    # Run verification functions
    check_missing_files
    check_outdated_docs
    check_broken_links
    check_missing_docs
    check_inconsistent_info

    # Fix issues if requested
    fix_issues

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
    local total_issues=$((${#missing_files[@]} + ${#outdated_docs[@]} + ${#broken_links[@]} + ${#missing_docs[@]} + ${#inconsistent_info[@]}))
    if [[ $total_issues -eq 0 ]]; then
        success "All documentation appears to be accurate and up-to-date!"
    else
        warn "Found $total_issues documentation issues"
    fi
}

# Run main function
main "$@"