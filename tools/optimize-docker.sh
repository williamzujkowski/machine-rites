#!/bin/bash

# Docker Image Optimization Script
# Reduces image sizes using Alpine base images and multi-stage builds

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$PROJECT_ROOT/.github/docker"

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

# Optimize existing Dockerfiles
optimize_dockerfiles() {
    log "Optimizing Docker images for size reduction..."

    # Create optimized Ubuntu 24.04 Dockerfile
    cat > "$DOCKER_DIR/Dockerfile.ubuntu-24.04.optimized" <<'EOF'
# Multi-stage build for Ubuntu 24.04 optimization
FROM ubuntu:24.04-slim as base

# Install minimal required packages in single layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gnupg \
    lsb-release \
    software-properties-common \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/* \
    && rm -rf /var/tmp/*

# Development stage
FROM base as development

# Install development tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    python3 \
    python3-pip \
    nodejs \
    npm \
    jq \
    unzip \
    zip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/* \
    && rm -rf /var/tmp/*

# Install Node.js LTS efficiently
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs \
    && npm cache clean --force

# Production stage
FROM base as production

# Copy only necessary runtime files
COPY --from=development /usr/bin/node /usr/bin/
COPY --from=development /usr/bin/npm /usr/bin/
COPY --from=development /usr/lib/node_modules /usr/lib/node_modules

# Create non-root user
RUN useradd -m -s /bin/bash claude \
    && mkdir -p /home/claude/workspace \
    && chown -R claude:claude /home/claude

USER claude
WORKDIR /home/claude/workspace

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node --version || exit 1

CMD ["/bin/bash"]
EOF

    # Create optimized Ubuntu 22.04 Dockerfile
    cat > "$DOCKER_DIR/Dockerfile.ubuntu-22.04.optimized" <<'EOF'
# Alpine-based Ubuntu 22.04 optimization
FROM alpine:3.18 as alpine-base

# Install Alpine packages for Ubuntu 22.04 compatibility
RUN apk add --no-cache \
    bash \
    curl \
    git \
    nodejs \
    npm \
    python3 \
    py3-pip \
    jq \
    ca-certificates \
    && npm cache clean --force

# Ubuntu compatibility layer
FROM ubuntu:22.04-slim as ubuntu-compat

# Copy optimized tools from Alpine
COPY --from=alpine-base /usr/bin/node /usr/bin/
COPY --from=alpine-base /usr/bin/npm /usr/bin/
COPY --from=alpine-base /usr/bin/jq /usr/bin/

# Install minimal Ubuntu packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/* \
    && rm -rf /var/tmp/*

# Create user and workspace
RUN useradd -m -s /bin/bash claude \
    && mkdir -p /home/claude/workspace \
    && chown -R claude:claude /home/claude

USER claude
WORKDIR /home/claude/workspace

CMD ["/bin/bash"]
EOF

    # Create optimized Debian 12 Dockerfile
    cat > "$DOCKER_DIR/Dockerfile.debian-12.optimized" <<'EOF'
# Debian 12 slim optimization
FROM debian:12-slim

# Single layer installation with cleanup
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gnupg \
    lsb-release \
    nodejs \
    npm \
    python3 \
    python3-pip \
    jq \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/* \
    && rm -rf /var/tmp/* \
    && npm cache clean --force \
    && python3 -m pip cache purge

# Create non-root user
RUN useradd -m -s /bin/bash claude \
    && mkdir -p /home/claude/workspace \
    && chown -R claude:claude /home/claude

USER claude
WORKDIR /home/claude/workspace

# Minimal health check
HEALTHCHECK --interval=60s --timeout=5s --start-period=10s --retries=2 \
    CMD node --version && python3 --version || exit 1

CMD ["/bin/bash"]
EOF

    success "Created optimized Dockerfiles in $DOCKER_DIR"
}

# Build and compare image sizes
build_and_compare() {
    log "Building optimized Docker images..."

    if ! command -v docker >/dev/null 2>&1; then
        warning "Docker not available, skipping image builds"
        return
    fi

    # Build optimized images
    local images=(
        "ubuntu-24.04.optimized"
        "ubuntu-22.04.optimized"
        "debian-12.optimized"
    )

    for image in "${images[@]}"; do
        if [ -f "$DOCKER_DIR/Dockerfile.$image" ]; then
            log "Building $image..."

            if docker build -t "oscalize:$image" -f "$DOCKER_DIR/Dockerfile.$image" "$PROJECT_ROOT" >/dev/null 2>&1; then
                local size=$(docker images "oscalize:$image" --format "{{.Size}}")
                success "Built oscalize:$image - Size: $size"
            else
                error "Failed to build oscalize:$image"
            fi
        fi
    done

    # Compare sizes
    log "Image size comparison:"
    docker images oscalize --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | head -10
}

# Clean up unused Docker resources
cleanup_docker() {
    log "Cleaning up Docker resources..."

    if ! command -v docker >/dev/null 2>&1; then
        warning "Docker not available, skipping cleanup"
        return
    fi

    # Remove dangling images
    local dangling=$(docker images -f "dangling=true" -q)
    if [ -n "$dangling" ]; then
        log "Removing dangling images..."
        docker rmi $dangling >/dev/null 2>&1 || true
    fi

    # Remove unused containers
    docker container prune -f >/dev/null 2>&1 || true

    # Remove unused volumes
    docker volume prune -f >/dev/null 2>&1 || true

    # Remove unused networks
    docker network prune -f >/dev/null 2>&1 || true

    success "Docker cleanup completed"
}

# Generate Docker optimization report
generate_report() {
    log "Generating Docker optimization report..."

    local report_file="$PROJECT_ROOT/.performance/docker_optimization.json"
    mkdir -p "$(dirname "$report_file")"

    local images_data="[]"

    if command -v docker >/dev/null 2>&1; then
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                local repo=$(echo "$line" | awk '{print $1}')
                local tag=$(echo "$line" | awk '{print $2}')
                local size=$(echo "$line" | awk '{print $3}')
                local created=$(echo "$line" | awk '{print $4" "$5}')

                # Convert size to MB
                local size_mb=0
                if [[ $size == *"GB"* ]]; then
                    size_mb=$(echo "$size" | sed 's/GB//' | awk '{print $1 * 1024}')
                elif [[ $size == *"MB"* ]]; then
                    size_mb=$(echo "$size" | sed 's/MB//' | awk '{print $1}')
                fi

                local optimized=$(echo "$tag" | grep -q "optimized" && echo "true" || echo "false")

                images_data=$(echo "$images_data" | jq --arg repo "$repo" --arg tag "$tag" --arg size "$size" \
                    --argjson size_mb "$size_mb" --arg created "$created" --argjson optimized "$optimized" \
                    '. += [{"repository": $repo, "tag": $tag, "size": $size, "size_mb": $size_mb, "created": $created, "optimized": $optimized}]')
            fi
        done < <(docker images oscalize --format "{{.Repository}} {{.Tag}} {{.Size}} {{.CreatedAt}}" 2>/dev/null || true)
    fi

    # Calculate optimization metrics
    local total_original=0
    local total_optimized=0
    local savings_mb=0
    local savings_percent=0

    if [ "$images_data" != "[]" ]; then
        total_original=$(echo "$images_data" | jq '[.[] | select(.optimized == false) | .size_mb] | add // 0')
        total_optimized=$(echo "$images_data" | jq '[.[] | select(.optimized == true) | .size_mb] | add // 0')

        if [ "$total_original" -gt 0 ]; then
            savings_mb=$(awk "BEGIN {printf \"%.1f\", $total_original - $total_optimized}")
            savings_percent=$(awk "BEGIN {printf \"%.1f\", (($total_original - $total_optimized) / $total_original) * 100}")
        fi
    fi

    cat > "$report_file" <<EOF
{
    "timestamp": "$(date -Iseconds)",
    "optimization": {
        "total_original_mb": $total_original,
        "total_optimized_mb": $total_optimized,
        "savings_mb": $savings_mb,
        "savings_percent": $savings_percent,
        "target_mb": 500
    },
    "images": $images_data,
    "recommendations": [
        "Use Alpine Linux base images for minimal size",
        "Implement multi-stage builds to exclude build dependencies",
        "Clean package caches in same RUN command",
        "Use .dockerignore to exclude unnecessary files",
        "Combine RUN commands to reduce layers"
    ]
}
EOF

    success "Docker optimization report saved to $report_file"

    # Display summary
    if [ "$total_original" -gt 0 ]; then
        log "Optimization Summary:"
        log "  Original size: ${total_original}MB"
        log "  Optimized size: ${total_optimized}MB"
        log "  Savings: ${savings_mb}MB (${savings_percent}%)"
    fi
}

# Main execution
main() {
    case "${1:-all}" in
        "optimize")
            optimize_dockerfiles
            ;;
        "build")
            build_and_compare
            ;;
        "cleanup")
            cleanup_docker
            ;;
        "report")
            generate_report
            ;;
        "all"|*)
            optimize_dockerfiles
            build_and_compare
            cleanup_docker
            generate_report
            ;;
    esac
}

# Execute with error handling
if ! main "$@"; then
    error "Docker optimization failed"
    exit 1
fi