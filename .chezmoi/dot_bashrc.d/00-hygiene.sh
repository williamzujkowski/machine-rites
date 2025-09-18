#!/usr/bin/env bash
# shellcheck shell=bash
shopt -s histappend checkwinsize cmdhist
shopt -s globstar extglob nullglob
HISTSIZE=100000
HISTFILESIZE=200000
HISTCONTROL=ignoredups:erasedups
HISTTIMEFORMAT='%F %T '
PROMPT_DIRTRIM=3
umask 027

# XDG Base Directory support
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# Path management
for p in "$HOME/.local/bin" "$HOME/bin"; do
  case ":$PATH:" in *":$p:"*) ;; *) [[ -d "$p" ]] && PATH="$p:$PATH";; esac
done
export PATH
