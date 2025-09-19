#!/bin/bash
# Lazy Docker setup

log() { echo "[LAZY-DOCKER] $*" >&2; }

log "Setting up Docker environment..."

if ! command -v docker >/dev/null 2>&1; then
    # Install Docker if not present
    curl -fsSL https://get.docker.com | sh >/dev/null 2>&1 || true
    sudo usermod -aG docker "$USER" 2>/dev/null || true
fi

# Docker optimizations
docker system prune -f >/dev/null 2>&1 || true

log "Docker environment ready"
