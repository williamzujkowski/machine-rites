#!/bin/bash
set -euo pipefail

echo "Fixing ShellCheck issues..."

# Fix 1: Update 30-secrets.sh to remove the unused parameter reference
cat > "$HOME/.bashrc.d/30-secrets.sh" <<'EOF'
#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1090,SC1091
PASS_PREFIX="${PASS_PREFIX:-personal}"

pass_env() {
  command -v pass >/dev/null 2>&1 || return 0
  local prefix="${PASS_PREFIX}" item var val  # Fixed: removed parameter reference
  while IFS= read -r item; do
    [[ "$item" == "Search Terms:"* ]] && continue
    [[ -z "$item" ]] && continue
    val="$(pass show "$item" 2>/dev/null | head -n1)"
    var="${item##*/}"
    var="$(printf '%s' "$var" | tr '[:lower:]-' '[:upper:]_' | sed 's/[^A-Z0-9_]/_/g')"
    [[ -n "$var" && -n "$val" ]] && export "$var=$val"
  done < <(pass find "$prefix" 2>/dev/null || true)
}
pass_env

# Legacy plaintext fallback
_plain="${XDG_CONFIG_HOME:-$HOME/.config}/secrets.env"
if [[ -f "$_plain" ]]; then
  chmod 600 "$_plain" 2>/dev/null || true
  set -a
  while IFS= read -r line; do
    # skip comments/blank
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue

    # split on first '=' only
    key="${line%%=*}"
    val="${line#*=}"

    # trim whitespace around key/val
    key="${key#"${key%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"
    val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"

    # strip matching surrounding quotes
    if [[ "$val" == \"*\" && "$val" == *\" ]]; then
      val="${val%\"}"; val="${val#\"}"
    elif [[ "$val" == \'*\' && "$val" == *\' ]]; then
      val="${val%\'}"; val="${val#\'}"
    fi

    # only export valid shell identifiers
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && export "$key=$val"
  done < "$_plain"
  set +a
fi
unset _plain
EOF
echo "✓ Fixed 30-secrets.sh"

# Fix 2: Restore the correct trap line in bootstrap_machine_rites.sh
# First, let's check if the file was corrupted and fix it properly
if grep -q 'trap.*>trap.*ERR2' bootstrap_machine_rites.sh 2>/dev/null; then
    echo "Fixing corrupted trap line..."
    # Create a temporary file with the fix
    awk '
    /^trap.*>trap.*ERR2/ {
        print "trap '\''echo \"[ERR] rc=$? at ${BASH_SOURCE[0]}:${LINENO} running: ${BASH_COMMAND}\" >&2'\'' ERR"
        next
    }
    {print}
    ' bootstrap_machine_rites.sh > bootstrap_machine_rites.sh.tmp
    mv bootstrap_machine_rites.sh.tmp bootstrap_machine_rites.sh
    chmod +x bootstrap_machine_rites.sh
else
    echo "Trap line appears correct, skipping..."
fi

# Re-add the fixed files to chezmoi
if command -v chezmoi >/dev/null 2>&1; then
    chezmoi -S "$HOME/git/machine-rites/.chezmoi" add "$HOME/.bashrc.d/30-secrets.sh" 2>/dev/null || true
    echo "✓ Updated chezmoi"
fi

# Update the corresponding file in the chezmoi source directory
if [ -f "$HOME/git/machine-rites/.chezmoi/dot_bashrc.d/30-secrets.sh" ]; then
    cp "$HOME/.bashrc.d/30-secrets.sh" "$HOME/git/machine-rites/.chezmoi/dot_bashrc.d/30-secrets.sh"
    echo "✓ Updated chezmoi source"
fi

# Now try to commit
cd "$HOME/git/machine-rites" || exit 1
echo ""
echo "Adding files to git..."
git add -A

echo ""
echo "Attempting commit..."
if git commit -m "fix: resolve ShellCheck warnings

* Remove unused parameter reference in pass_env function
* Fix trap command to avoid unassigned variable reference
* All ShellCheck warnings resolved"; then
    echo ""
    echo "✅ Successfully committed!"
else
    echo ""
    echo "⚠️  Commit failed. Running pre-commit manually to see issues:"
    pre-commit run --all-files || true
fi

echo ""
echo "Current git status:"
git status --short