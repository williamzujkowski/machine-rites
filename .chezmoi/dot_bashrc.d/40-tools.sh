#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1090,SC1091

# nvm lazy loading
export NVM_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvm"
nvm() {
  unset -f nvm
  [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
  nvm "$@"
}
[[ -s "$NVM_DIR/bash_completion" ]] && . "$NVM_DIR/bash_completion"

# pyenv
if command -v pyenv >/dev/null 2>&1; then
  export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
  eval "$(pyenv init - bash)"
fi

# uv
if command -v uv >/dev/null 2>&1; then
  eval "$(uv generate-shell-completion bash 2>/dev/null || true)"
fi

# Rust/Cargo
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# Deno
[[ -f "$HOME/.deno/env" ]] && . "$HOME/.deno/env"

# Better manpages
if command -v batcat >/dev/null 2>&1; then
  export MANPAGER="sh -c 'col -bx | batcat -l man -p'"
  export MANROFFOPT="-c"
fi
