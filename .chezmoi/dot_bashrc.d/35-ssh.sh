#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1090
# Reuse one ssh-agent across sessions using XDG state

XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="$XDG_STATE_HOME/ssh"
AGENT_ENV="$STATE_DIR/agent.env"

mkdir -p "$STATE_DIR"

write_env() {
  umask 077
  local tmp
  tmp="$(mktemp "$STATE_DIR/.agent.XXXXXX")"
  {
    echo "export SSH_AUTH_SOCK='$SSH_AUTH_SOCK'"
    [ -n "${SSH_AGENT_PID:-}" ] && echo "export SSH_AGENT_PID='$SSH_AGENT_PID'"
  } > "$tmp"
  mv -f "$tmp" "$AGENT_ENV"
}

agent_alive() {
  [ -S "${SSH_AUTH_SOCK:-}" ] && ssh-add -l >/dev/null 2>&1
}

start_agent() {
  eval "$(ssh-agent -s)" >/dev/null
  write_env
}

# Load previous agent if present
if [ -r "$AGENT_ENV" ]; then
  . "$AGENT_ENV"
fi

# Start once if not usable
if ! agent_alive; then
  start_agent
fi

# Auto-load key if none present
if ! ssh-add -l >/dev/null 2>&1; then
  for k in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa"; do
    [ -f "$k" ] && ssh-add "$k" >/dev/null 2>&1 && break
  done
fi

# Helper function (callable manually)
ensure_ssh_key() {
  local key_type="${1:-ed25519}"
  local key_file="$HOME/.ssh/id_${key_type}"
  if [ ! -f "$key_file" ]; then
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keygen -t "$key_type" -f "$key_file" -N "" -C "$(whoami)@$(hostname)"
    ssh-add "$key_file"
  fi
  echo "Your SSH public key:"
  cat "${key_file}.pub"
}
