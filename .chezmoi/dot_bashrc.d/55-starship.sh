#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1090,SC1091
# If starship is installed, enable it
if command -v starship >/dev/null 2>&1; then
  export STARSHIP_CONFIG="${STARSHIP_CONFIG:-$HOME/.config/starship.toml}"
  eval "$(starship init bash)"
fi
