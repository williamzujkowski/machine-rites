#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="$REPO_DIR/backups/pass"
mkdir -p "$BACKUP_DIR"

pass_dir="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
if [[ ! -d "$pass_dir" ]]; then
  echo "Pass store not found at: $pass_dir"
  exit 1
fi

backup_file="$BACKUP_DIR/pass-$(date +%Y%m%d-%H%M%S).tar.gz.gpg"

echo "Backing up pass store..."
if tar czf - -C "$pass_dir" . | gpg --symmetric --cipher-algo AES256 --output "$backup_file"; then
  echo "  ✓ Saved: $backup_file"
  
  # Keep only last 5
  ls -t "$BACKUP_DIR"/*.gpg 2>/dev/null | tail -n +6 | xargs -r rm
  echo "  ✓ Cleaned old backups"
else
  echo "  ✗ Backup failed"
  exit 1
fi

echo "Restore: gpg -d $backup_file | tar xzf - -C ~/.password-store"
