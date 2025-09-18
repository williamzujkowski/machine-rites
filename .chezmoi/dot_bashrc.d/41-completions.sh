#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1090,SC1091

# Ensure bash-completion is available (already sourced in 10-bash-completion.sh)

# git
for f in /usr/share/bash-completion/completions/git \
         /usr/share/doc/git/contrib/completion/git-completion.bash; do
  [[ -f $f ]] && . "$f" && break
done

# gh
if command -v gh >/dev/null 2>&1; then
  eval "$(gh completion -s bash 2>/dev/null)" || true
fi

# kubectl
command -v kubectl >/dev/null 2>&1 && eval "$(kubectl completion bash)" || true

# docker & compose (if distro provides them)
for f in /usr/share/bash-completion/completions/docker \
         /usr/share/bash-completion/completions/docker-compose; do
  [[ -f $f ]] && . "$f"
done

# terraform
if command -v terraform >/dev/null 2>&1; then
  terraform -install-autocomplete >/dev/null 2>&1 || true
fi

# aws
if command -v aws_completer >/dev/null 2>&1; then
  complete -C aws_completer aws
fi
