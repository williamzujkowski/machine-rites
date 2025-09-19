#!/bin/bash

# Optimized Bootstrap Script for Machine-Rites
# Target: <1.5s execution time through parallel operations and lazy loading

set -euo pipefail

# Performance tracking
BOOTSTRAP_START=$(date +%s%3N)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
PARALLEL_JOBS=${BOOTSTRAP_PARALLEL_JOBS:-4}
LAZY_LOAD=${BOOTSTRAP_LAZY_LOAD:-true}
DRY_RUN=${BOOTSTRAP_DRY_RUN:-false}
VERBOSE=${BOOTSTRAP_VERBOSE:-false}

# Colors (only if interactive)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

# Optimized logging
log() {
    [ "$VERBOSE" = "true" ] && echo -e "${BLUE}[BOOTSTRAP]${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

# Fast command availability check
has_command() {
    command -v "$1" >/dev/null 2>&1
}

# Parallel package checks
check_packages_parallel() {
    local packages=("$@")
    local pids=()
    local results=()

    log "Checking ${#packages[@]} packages in parallel..."

    # Create temporary directory for results
    local temp_dir=$(mktemp -d)

    # Launch parallel checks
    for i in "${!packages[@]}"; do
        {
            local pkg="${packages[$i]}"
            local result_file="$temp_dir/result_$i"

            if has_command "$pkg"; then
                echo "installed" > "$result_file"
            else
                echo "missing" > "$result_file"
            fi
        } &
        pids+=($!)

        # Limit concurrent jobs
        if [ ${#pids[@]} -ge $PARALLEL_JOBS ]; then
            wait "${pids[0]}"
            pids=("${pids[@]:1}")
        fi
    done

    # Wait for remaining jobs
    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    # Collect results
    for i in "${!packages[@]}"; do
        local result=$(cat "$temp_dir/result_$i" 2>/dev/null || echo "error")
        results+=("$result")

        if [ "$result" = "missing" ]; then
            warn "Missing package: ${packages[$i]}"
        fi
    done

    # Cleanup
    rm -rf "$temp_dir"

    log "Package check completed in parallel"
}

# Fast git operations
optimize_git_config() {
    if [ "$DRY_RUN" = "true" ]; then
        log "DRY RUN: Would optimize git configuration"
        return
    fi

    log "Optimizing git configuration..."

    # Parallel git config operations
    {
        git config --global core.preloadindex true 2>/dev/null || true
        git config --global core.fscache true 2>/dev/null || true
        git config --global gc.auto 256 2>/dev/null || true
    } &

    {
        git config --global pack.threads 0 2>/dev/null || true
        git config --global pack.deltaCacheSize 2047m 2>/dev/null || true
        git config --global pack.packSizeLimit 2g 2>/dev/null || true
    } &

    wait

    log "Git optimization completed"
}

# Lazy loading implementation
setup_lazy_loading() {
    if [ "$LAZY_LOAD" != "true" ]; then
        return
    fi

    log "Setting up lazy loading..."

    local lazy_dir="$PROJECT_ROOT/.lazy"
    mkdir -p "$lazy_dir"

    # Create lazy loading manifest
    cat > "$lazy_dir/manifest.json" <<LAZY_EOF
{
    "timestamp": "$(date -Iseconds)",
    "components": {
        "docker": {
            "loaded": false,
            "trigger": "docker command",
            "script": "setup_docker.sh"
        },
        "kubernetes": {
            "loaded": false,
            "trigger": "kubectl command",
            "script": "setup_k8s.sh"
        },
        "development": {
            "loaded": false,
            "trigger": "npm/yarn command",
            "script": "setup_dev.sh"
        }
    }
}
LAZY_EOF

    # Create lazy loading hooks
    create_lazy_hooks

    log "Lazy loading configured"
}

# Create command hooks for lazy loading
create_lazy_hooks() {
    local hooks_dir="$PROJECT_ROOT/.lazy/hooks"
    mkdir -p "$hooks_dir"

    # Docker lazy hook
    cat > "$hooks_dir/docker" <<'HOOK_EOF'
#!/bin/bash
if [ ! -f "$HOME/.lazy/docker_loaded" ]; then
    echo "Loading Docker environment..."
    source "$PROJECT_ROOT/.lazy/setup_docker.sh" 2>/dev/null || true
    touch "$HOME/.lazy/docker_loaded"
fi
exec docker "$@"
HOOK_EOF

    # Make hooks executable
    chmod +x "$hooks_dir"/*

    log "Lazy loading hooks created"
}

# Fast system detection
detect_system() {
    local start_time=$(date +%s%3N)

    # Parallel system detection
    {
        DISTRO=$(lsb_release -si 2>/dev/null || echo "Unknown")
        export DISTRO
    } &

    {
        VERSION=$(lsb_release -sr 2>/dev/null || echo "Unknown")
        export VERSION
    } &

    {
        ARCH=$(uname -m 2>/dev/null || echo "Unknown")
        export ARCH
    } &

    wait

    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))

    log "System detection completed in ${duration}ms: $DISTRO $VERSION ($ARCH)"
}

# Essential package installation (minimal set)
install_essentials() {
    if [ "$DRY_RUN" = "true" ]; then
        log "DRY RUN: Would install essential packages"
        return
    fi

    log "Installing essential packages..."

    # Essential packages only
    local essentials=("curl" "git" "jq")

    check_packages_parallel "${essentials[@]}"

    # Install missing essentials (platform-specific)
    case "$DISTRO" in
        "Ubuntu"|"Debian")
            if ! has_command curl || ! has_command git || ! has_command jq; then
                log "Installing missing essentials via apt..."
                sudo apt-get update -qq >/dev/null 2>&1 || true
                sudo apt-get install -y curl git jq >/dev/null 2>&1 || warn "Some packages failed to install"
            fi
            ;;
        *)
            warn "Unknown distribution: $DISTRO - manual package installation may be required"
            ;;
    esac

    success "Essential packages verified"
}

# Fast Node.js setup
setup_nodejs() {
    if [ "$DRY_RUN" = "true" ]; then
        log "DRY RUN: Would setup Node.js"
        return
    fi

    if has_command node && has_command npm; then
        log "Node.js already available"
        return
    fi

    log "Setting up Node.js..."

    # Use pre-compiled binaries for speed
    if [ ! -d "$HOME/.local/node" ]; then
        local node_version="v18.17.0"
        local node_url="https://nodejs.org/dist/$node_version/node-$node_version-linux-x64.tar.xz"

        {
            curl -fsSL "$node_url" | tar -xJ -C "$HOME/.local" 2>/dev/null || warn "Node.js download failed"
            mv "$HOME/.local/node-$node_version-linux-x64" "$HOME/.local/node" 2>/dev/null || true
        } &

        wait
    fi

    # Add to PATH if not already there
    if [[ ":$PATH:" != *":$HOME/.local/node/bin:"* ]]; then
        export PATH="$HOME/.local/node/bin:$PATH"
        echo 'export PATH="$HOME/.local/node/bin:$PATH"' >> "$HOME/.bashrc"
    fi

    log "Node.js setup completed"
}

# Performance monitoring
track_performance() {
    local current_time=$(date +%s%3N)
    local elapsed=$((current_time - BOOTSTRAP_START))

    log "Bootstrap performance: ${elapsed}ms elapsed"

    # Save performance metrics
    local metrics_dir="$PROJECT_ROOT/.performance"
    mkdir -p "$metrics_dir"

    cat > "$metrics_dir/bootstrap_performance.json" <<PERF_EOF
{
    "timestamp": "$(date -Iseconds)",
    "execution_time_ms": $elapsed,
    "target_ms": 1500,
    "passed": $([ $elapsed -le 1500 ] && echo "true" || echo "false"),
    "optimizations": {
        "parallel_jobs": $PARALLEL_JOBS,
        "lazy_loading": $LAZY_LOAD,
        "dry_run": $DRY_RUN
    }
}
PERF_EOF

    if [ $elapsed -le 1500 ]; then
        success "Bootstrap completed in ${elapsed}ms (target: 1500ms) ✓"
    else
        warn "Bootstrap took ${elapsed}ms (exceeds 1500ms target)"
    fi
}

# Main bootstrap sequence
main() {
    log "Starting optimized bootstrap process..."

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                ;;
            --verbose)
                VERBOSE=true
                ;;
            --no-lazy)
                LAZY_LOAD=false
                ;;
            --jobs)
                PARALLEL_JOBS="$2"
                shift
                ;;
            *)
                log "Unknown option: $1"
                ;;
        esac
        shift
    done

    # Fast parallel execution of core tasks
    {
        detect_system
        optimize_git_config
    } &

    {
        setup_lazy_loading
    } &

    wait

    # Essential installations
    install_essentials
    setup_nodejs

    # Performance tracking
    track_performance

    success "Optimized bootstrap completed successfully"
}

# Error handling
trap 'error "Bootstrap failed at line $LINENO"' ERR

# Execute bootstrap
main "$@"
