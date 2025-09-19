#!/usr/bin/env bash
# Auto-generated version file - 2025-09-18
# Source this file to get latest versions

export NVM_VERSION="v0.40.3"
export NODE_LTS_VERSION="v22.19.0"
export PYENV_VERSION="v2.6.7"
export PYTHON_VERSION="3.12.7"
export GO_VERSION="1.25.1"
export RUST_VERSION="1.87.0"

# Function to dynamically get GitHub latest version
get_github_latest() {
    local repo="$1"
    curl -s "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | \
        grep -Po '"tag_name": "\K[^"]*' 2>/dev/null || echo "unknown"
}
