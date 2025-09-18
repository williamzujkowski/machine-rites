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
