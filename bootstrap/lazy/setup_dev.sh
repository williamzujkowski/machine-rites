#!/bin/bash
# Lazy development tools setup

log() { echo "[LAZY-DEV] $*" >&2; }

log "Setting up development environment..."

# Install development packages
if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get install -y build-essential python3-dev >/dev/null 2>&1 || true
fi

# Setup npm global packages
npm config set prefix "$HOME/.local/npm" 2>/dev/null || true

log "Development environment ready"
