#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

echo "=== Dotfiles Update ==="

echo "Pulling latest..."
if git pull --ff-only; then
  echo "  ✓ Updated to $(git rev-parse --short HEAD)"
else
  echo "  ⚠ Could not fast-forward"
fi

echo "Applying chezmoi..."
if chezmoi apply; then
  echo "  ✓ Applied"
else
  echo "  ✗ Failed"
fi

echo "Updating pre-commit..."
if pre-commit autoupdate >/dev/null 2>&1; then
  echo "  ✓ Updated"
else
  echo "  ⚠ Failed"
fi

echo "Running health check..."
./tools/doctor.sh

echo "=== Update Complete ==="
