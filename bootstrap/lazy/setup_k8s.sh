#!/bin/bash
# Lazy Kubernetes setup

log() { echo "[LAZY-K8S] $*" >&2; }

log "Setting up Kubernetes tools..."

# Install kubectl if not present
if ! command -v kubectl >/dev/null 2>&1; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" >/dev/null 2>&1
    chmod +x kubectl
    mv kubectl "$HOME/.local/bin/" 2>/dev/null || sudo mv kubectl /usr/local/bin/
fi

log "Kubernetes tools ready"
