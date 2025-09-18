#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

C_G="\033[1;32m"; C_Y="\033[1;33m"; C_R="\033[1;31m"; C_N="\033[0m"
ok(){ printf "${C_G}✓${C_N} %s\n" "$*"; }
warn(){ printf "${C_Y}⚠${C_N} %s\n" "$*"; }
fail(){ printf "${C_R}✗${C_N} %s\n" "$*"; }

echo "=== Dotfiles Health Check ==="

# System info
echo -e "\n[System]"
printf "  %-12s : " "OS"
if lsb_release -is 2>/dev/null | grep -q Ubuntu; then
  ok "Ubuntu $(lsb_release -rs 2>/dev/null)"
else
  warn "Not Ubuntu ($(lsb_release -is 2>/dev/null || echo 'Unknown'))"
fi

# Tools check
echo -e "\n[Tools]"
errors=0
for t in bash chezmoi pass gitleaks pre-commit git gpg age ssh starship; do
  printf "  %-12s : " "$t"
  if command -v "$t" >/dev/null 2>&1; then
    ver="$("$t" --version 2>/dev/null | head -1 || echo "installed")"
    ok "${ver:0:50}"
  else
    if [ "$t" = "starship" ]; then
      warn "Not installed (optional)"
    else
      fail "MISSING"
      ((errors++))
    fi
  fi
done

# GPG
echo -e "\n[GPG]"
if gpg --list-secret-keys 2>/dev/null | grep -q '^sec'; then
  keys=$(gpg --list-secret-keys --keyid-format SHORT 2>/dev/null | grep '^sec' | wc -l)
  ok "Secret keys: $keys"
else
  warn "No GPG secret keys (pass won't work)"
fi

# Pass
echo -e "\n[Pass Store]"
if pass ls >/dev/null 2>&1; then
  count=$(pass ls 2>/dev/null | grep -E -c '├──|└──' || echo "0")
  ok "Entries: $count"
else
  warn "Not initialized (run: pass init <GPG_KEY_ID>)"
fi

# SSH
echo -e "\n[SSH]"
found=0
for key in ~/.ssh/id_{rsa,ed25519,ecdsa}; do
  [[ -f "$key" ]] && { ok "Key: $(basename "$key")"; found=1; }
done
[[ "$found" -eq 0 ]] && warn "No SSH keys (run: ensure_ssh_key)"

printf "  %-12s : " "Agent"
if [[ -n "${SSH_AUTH_SOCK:-}" ]] && ssh-add -l >/dev/null 2>&1; then
  ok "Running ($(ssh-add -l 2>/dev/null | wc -l) keys)"
else
  warn "Not running or no keys"
fi

# Chezmoi
echo -e "\n[Chezmoi]"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if chezmoi status >/dev/null 2>&1; then
  changes=$(chezmoi status 2>/dev/null | wc -l)
  if [[ "$changes" -eq 0 ]]; then
    ok "Clean"
  else
    warn "$changes pending changes (run: chezmoi diff)"
  fi
else
  fail "Not configured"
fi

# Pre-commit
echo -e "\n[Pre-commit]"
if [[ -f "$REPO_DIR/.git/hooks/pre-commit" ]]; then
  ok "Hooks installed"
  echo "  Testing..."
  if (cd "$REPO_DIR" && pre-commit run --all-files >/dev/null 2>&1); then
    ok "  All checks pass"
  else
    warn "  Some checks failed"
  fi
else
  warn "Not installed (run: pre-commit install)"
fi

# Security
echo -e "\n[Security]"
if (cd "$REPO_DIR" && gitleaks detect --no-banner --exit-code 0 >/dev/null 2>&1); then
  ok "No secrets detected"
else
  fail "Secrets found! Run: gitleaks detect --verbose"
fi

# Summary
echo -e "\n[Summary]"
if [[ "$errors" -eq 0 ]]; then
  ok "All essential tools installed"
else
  fail "$errors essential tools missing"
fi

echo -e "\n=== End Health Check ==="
