#!/bin/bash

# Cache Management and Optimization Script
# Manages 25GB cache cleanup and implements size limits

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
MAX_CACHE_SIZE_GB=${CACHE_MAX_SIZE_GB:-10}
CLEANUP_THRESHOLD_GB=${CACHE_CLEANUP_THRESHOLD:-15}
AGGRESSIVE_CLEANUP=${CACHE_AGGRESSIVE:-false}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Convert size to GB
size_to_gb() {
    local size_kb=$1
    awk "BEGIN {printf \"%.2f\", $size_kb / 1024 / 1024}"
}

# Get directory size in KB
get_dir_size() {
    local dir=$1
    if [ -d "$dir" ]; then
        du -sk "$dir" 2>/dev/null | cut -f1 || echo "0"
    else
        echo "0"
    fi
}

# Analyze cache usage
analyze_cache() {
    log "Analyzing cache usage..."

    local cache_dirs=(
        "$HOME/.cache"
        "$HOME/.npm"
        "$HOME/.yarn"
        "$HOME/.pip"
        "$HOME/.composer"
        "$HOME/.gem"
        "$PROJECT_ROOT/node_modules"
        "$PROJECT_ROOT/.git"
        "/var/cache"
        "/tmp"
    )

    local total_size_kb=0
    local cache_data="[]"

    for cache_dir in "${cache_dirs[@]}"; do
        if [ -d "$cache_dir" ]; then
            local size_kb=$(get_dir_size "$cache_dir")
            local size_gb=$(size_to_gb "$size_kb")
            total_size_kb=$((total_size_kb + size_kb))

            # Get file count for additional context
            local file_count=$(find "$cache_dir" -type f 2>/dev/null | wc -l || echo "0")

            cache_data=$(echo "$cache_data" | jq --arg path "$cache_dir" --arg size_gb "$size_gb" \
                --argjson size_kb "$size_kb" --argjson file_count "$file_count" \
                '. += [{"path": $path, "size_gb": ($size_gb | tonumber), "size_kb": $size_kb, "file_count": $file_count}]')

            log "  $cache_dir: ${size_gb}GB (${file_count} files)"
        fi
    done

    local total_size_gb=$(size_to_gb "$total_size_kb")

    # Save analysis results
    local analysis_file="$PROJECT_ROOT/.performance/cache_analysis.json"
    mkdir -p "$(dirname "$analysis_file")"

    cat > "$analysis_file" <<EOF
{
    "timestamp": "$(date -Iseconds)",
    "total_size_gb": $total_size_gb,
    "max_size_gb": $MAX_CACHE_SIZE_GB,
    "cleanup_threshold_gb": $CLEANUP_THRESHOLD_GB,
    "needs_cleanup": $(awk "BEGIN {print ($total_size_gb > $CLEANUP_THRESHOLD_GB) ? \"true\" : \"false\"}"),
    "directories": $cache_data
}
EOF

    log "Total cache usage: ${total_size_gb}GB"

    if awk "BEGIN {exit !($total_size_gb > $CLEANUP_THRESHOLD_GB)}"; then
        warning "Cache usage exceeds ${CLEANUP_THRESHOLD_GB}GB threshold - cleanup recommended"
        return 1
    else
        success "Cache usage within acceptable limits"
        return 0
    fi
}

# Clean specific cache types
clean_npm_cache() {
    log "Cleaning npm cache..."

    if command -v npm >/dev/null 2>&1; then
        local before_size=$(get_dir_size "$HOME/.npm")

        npm cache clean --force >/dev/null 2>&1 || true

        local after_size=$(get_dir_size "$HOME/.npm")
        local saved_gb=$(size_to_gb $((before_size - after_size)))

        success "Cleaned npm cache - saved ${saved_gb}GB"
    fi
}

clean_yarn_cache() {
    log "Cleaning yarn cache..."

    if command -v yarn >/dev/null 2>&1; then
        local before_size=$(get_dir_size "$HOME/.yarn")

        yarn cache clean >/dev/null 2>&1 || true

        local after_size=$(get_dir_size "$HOME/.yarn")
        local saved_gb=$(size_to_gb $((before_size - after_size)))

        success "Cleaned yarn cache - saved ${saved_gb}GB"
    fi
}

clean_pip_cache() {
    log "Cleaning pip cache..."

    if command -v pip >/dev/null 2>&1 || command -v pip3 >/dev/null 2>&1; then
        local before_size=$(get_dir_size "$HOME/.pip")

        pip cache purge >/dev/null 2>&1 || true
        pip3 cache purge >/dev/null 2>&1 || true

        local after_size=$(get_dir_size "$HOME/.pip")
        local saved_gb=$(size_to_gb $((before_size - after_size)))

        success "Cleaned pip cache - saved ${saved_gb}GB"
    fi
}

clean_system_cache() {
    log "Cleaning system cache..."

    local before_size=$(get_dir_size "$HOME/.cache")

    # Clean user cache (safe items only)
    if [ -d "$HOME/.cache" ]; then
        # Clean thumbnails
        rm -rf "$HOME/.cache/thumbnails"/* 2>/dev/null || true

        # Clean temporary files older than 7 days
        find "$HOME/.cache" -type f -atime +7 -delete 2>/dev/null || true

        # Clean browser caches (if safe)
        for browser_cache in "$HOME/.cache/google-chrome" "$HOME/.cache/firefox" "$HOME/.cache/chromium"; do
            if [ -d "$browser_cache" ]; then
                find "$browser_cache" -name "Cache*" -type d -exec rm -rf {} + 2>/dev/null || true
            fi
        done
    fi

    local after_size=$(get_dir_size "$HOME/.cache")
    local saved_gb=$(size_to_gb $((before_size - after_size)))

    success "Cleaned system cache - saved ${saved_gb}GB"
}

clean_git_cache() {
    log "Cleaning git cache..."

    if [ -d "$PROJECT_ROOT/.git" ]; then
        local before_size=$(get_dir_size "$PROJECT_ROOT/.git")

        # Git cleanup operations
        git -C "$PROJECT_ROOT" gc --aggressive --prune=now >/dev/null 2>&1 || true
        git -C "$PROJECT_ROOT" remote prune origin >/dev/null 2>&1 || true

        local after_size=$(get_dir_size "$PROJECT_ROOT/.git")
        local saved_gb=$(size_to_gb $((before_size - after_size)))

        success "Cleaned git cache - saved ${saved_gb}GB"
    fi
}

clean_docker_cache() {
    log "Cleaning Docker cache..."

    if command -v docker >/dev/null 2>&1; then
        local before_info=$(docker system df --format "{{.Size}}" 2>/dev/null || echo "0B")

        # Clean Docker system
        docker system prune -f >/dev/null 2>&1 || true
        docker image prune -f >/dev/null 2>&1 || true
        docker container prune -f >/dev/null 2>&1 || true
        docker volume prune -f >/dev/null 2>&1 || true
        docker network prune -f >/dev/null 2>&1 || true

        success "Cleaned Docker cache"
    fi
}

# Aggressive cleanup for emergency situations
aggressive_cleanup() {
    warning "Performing aggressive cache cleanup..."

    # Remove older cached files aggressively
    local cache_dirs=(
        "$HOME/.cache"
        "$HOME/.npm"
        "$HOME/.yarn"
        "$HOME/.pip"
    )

    for cache_dir in "${cache_dirs[@]}"; do
        if [ -d "$cache_dir" ]; then
            log "Aggressively cleaning $cache_dir..."

            # Remove files older than 3 days
            find "$cache_dir" -type f -atime +3 -delete 2>/dev/null || true

            # Remove large files (>100MB)
            find "$cache_dir" -type f -size +100M -delete 2>/dev/null || true

            # Remove empty directories
            find "$cache_dir" -type d -empty -delete 2>/dev/null || true
        fi
    done

    warning "Aggressive cleanup completed"
}

# Set up cache size limits
setup_cache_limits() {
    log "Setting up cache size limits..."

    # Create cache monitoring script
    local monitor_script="$PROJECT_ROOT/tools/cache-monitor.sh"

    cat > "$monitor_script" <<'EOF'
#!/bin/bash

# Cache Size Monitor
# Automatically cleans cache when limits are exceeded

CACHE_MAX_SIZE_GB=${CACHE_MAX_SIZE_GB:-10}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check cache size
check_and_clean() {
    local total_size_gb=0
    local cache_dirs=("$HOME/.cache" "$HOME/.npm" "$HOME/.yarn")

    for cache_dir in "${cache_dirs[@]}"; do
        if [ -d "$cache_dir" ]; then
            local size_kb=$(du -sk "$cache_dir" 2>/dev/null | cut -f1 || echo "0")
            local size_gb=$(awk "BEGIN {printf \"%.2f\", $size_kb / 1024 / 1024}")
            total_size_gb=$(awk "BEGIN {printf \"%.2f\", $total_size_gb + $size_gb}")
        fi
    done

    if awk "BEGIN {exit !($total_size_gb > $CACHE_MAX_SIZE_GB)}"; then
        echo "Cache size ${total_size_gb}GB exceeds limit ${CACHE_MAX_SIZE_GB}GB - cleaning..."
        "$SCRIPT_DIR/cache-manager.sh" cleanup
    fi
}

check_and_clean
EOF

    chmod +x "$monitor_script"

    # Create systemd user service for automatic monitoring
    local service_dir="$HOME/.config/systemd/user"
    mkdir -p "$service_dir"

    cat > "$service_dir/cache-monitor.service" <<EOF
[Unit]
Description=Cache Size Monitor
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=$monitor_script
Environment=HOME=$HOME

[Install]
WantedBy=default.target
EOF

    cat > "$service_dir/cache-monitor.timer" <<EOF
[Unit]
Description=Run cache monitor every hour
Requires=cache-monitor.service

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Enable timer if systemd is available
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user enable cache-monitor.timer 2>/dev/null || true
        systemctl --user start cache-monitor.timer 2>/dev/null || true
        success "Cache monitoring timer enabled"
    fi

    success "Cache size limits configured"
}

# Cleanup operation
cleanup_caches() {
    log "Starting cache cleanup process..."

    local start_size_kb=0
    local cache_dirs=("$HOME/.cache" "$HOME/.npm" "$HOME/.yarn" "$HOME/.pip")

    # Calculate initial size
    for cache_dir in "${cache_dirs[@]}"; do
        start_size_kb=$((start_size_kb + $(get_dir_size "$cache_dir")))
    done

    local start_size_gb=$(size_to_gb "$start_size_kb")
    log "Initial cache size: ${start_size_gb}GB"

    # Perform cleanup operations
    clean_npm_cache
    clean_yarn_cache
    clean_pip_cache
    clean_system_cache
    clean_git_cache
    clean_docker_cache

    # Aggressive cleanup if still over threshold
    if [ "$AGGRESSIVE_CLEANUP" = "true" ]; then
        aggressive_cleanup
    fi

    # Calculate final size
    local end_size_kb=0
    for cache_dir in "${cache_dirs[@]}"; do
        end_size_kb=$((end_size_kb + $(get_dir_size "$cache_dir")))
    done

    local end_size_gb=$(size_to_gb "$end_size_kb")
    local saved_gb=$(size_to_gb $((start_size_kb - end_size_kb)))

    # Save cleanup results
    local cleanup_file="$PROJECT_ROOT/.performance/cache_cleanup.json"
    mkdir -p "$(dirname "$cleanup_file")"

    cat > "$cleanup_file" <<EOF
{
    "timestamp": "$(date -Iseconds)",
    "cleanup": {
        "start_size_gb": $start_size_gb,
        "end_size_gb": $end_size_gb,
        "saved_gb": $saved_gb,
        "target_gb": $MAX_CACHE_SIZE_GB,
        "success": $(awk "BEGIN {print ($end_size_gb <= $MAX_CACHE_SIZE_GB) ? \"true\" : \"false\"}")
    },
    "operations": [
        "npm cache clean",
        "yarn cache clean",
        "pip cache purge",
        "system cache cleanup",
        "git garbage collection",
        "docker system prune"
    ]
}
EOF

    success "Cache cleanup completed: ${start_size_gb}GB → ${end_size_gb}GB (saved ${saved_gb}GB)"

    if awk "BEGIN {exit !($end_size_gb <= $MAX_CACHE_SIZE_GB)}"; then
        success "Cache size now within ${MAX_CACHE_SIZE_GB}GB target ✓"
    else
        warning "Cache size still exceeds ${MAX_CACHE_SIZE_GB}GB target"
    fi
}

# Generate cache management report
generate_report() {
    log "Generating cache management report..."

    # Run analysis first
    analyze_cache >/dev/null 2>&1 || true

    local report_file="$PROJECT_ROOT/.performance/cache_management.json"
    mkdir -p "$(dirname "$report_file")"

    local analysis_data="{}"
    local cleanup_data="{}"

    if [ -f "$PROJECT_ROOT/.performance/cache_analysis.json" ]; then
        analysis_data=$(cat "$PROJECT_ROOT/.performance/cache_analysis.json")
    fi

    if [ -f "$PROJECT_ROOT/.performance/cache_cleanup.json" ]; then
        cleanup_data=$(cat "$PROJECT_ROOT/.performance/cache_cleanup.json")
    fi

    cat > "$report_file" <<EOF
{
    "timestamp": "$(date -Iseconds)",
    "configuration": {
        "max_cache_size_gb": $MAX_CACHE_SIZE_GB,
        "cleanup_threshold_gb": $CLEANUP_THRESHOLD_GB,
        "aggressive_cleanup": $AGGRESSIVE_CLEANUP
    },
    "analysis": $analysis_data,
    "cleanup": $cleanup_data,
    "recommendations": [
        "Set up automatic cache monitoring",
        "Implement size-based cleanup policies",
        "Use cache-efficient package managers",
        "Regular maintenance scheduling",
        "Monitor cache growth trends"
    ],
    "tools_created": [
        "tools/cache-monitor.sh",
        "systemd cache monitoring service"
    ]
}
EOF

    success "Cache management report saved to $report_file"

    # Display summary
    local current_size=$(echo "$analysis_data" | jq -r '.total_size_gb // "N/A"')
    local saved_size=$(echo "$cleanup_data" | jq -r '.cleanup.saved_gb // "0"')

    log "Cache Management Summary:"
    log "  Current size: ${current_size}GB"
    log "  Target size: ${MAX_CACHE_SIZE_GB}GB"
    log "  Last cleanup saved: ${saved_size}GB"
}

# Main execution
main() {
    case "${1:-analyze}" in
        "analyze")
            analyze_cache
            ;;
        "cleanup")
            cleanup_caches
            ;;
        "setup")
            setup_cache_limits
            ;;
        "aggressive")
            AGGRESSIVE_CLEANUP=true
            cleanup_caches
            ;;
        "report")
            generate_report
            ;;
        "full")
            analyze_cache || true
            cleanup_caches
            setup_cache_limits
            generate_report
            ;;
        *)
            error "Unknown command: $1"
            echo "Usage: $0 {analyze|cleanup|setup|aggressive|report|full}"
            exit 1
            ;;
    esac
}

# Execute with error handling
if ! main "$@"; then
    error "Cache management operation failed"
    exit 1
fi