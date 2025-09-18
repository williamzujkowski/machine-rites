#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1090,SC1091

# Git-aware prompt (Ubuntu path)
if [[ -f /usr/lib/git-core/git-sh-prompt ]]; then
  . /usr/lib/git-core/git-sh-prompt
  export GIT_PS1_SHOWDIRTYSTATE=1
  export GIT_PS1_SHOWSTASHSTATE=1
  export GIT_PS1_SHOWUNTRACKEDFILES=1
  export GIT_PS1_SHOWUPSTREAM="auto"
  export GIT_PS1_SHOWCOLORHINTS=1

  # Color prompt with git
  if [[ -x /usr/bin/tput ]] && tput setaf 1 >&/dev/null; then
    PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$(__git_ps1 " (\[\033[01;31m\]%s\[\033[00m\])")\$ '
  else
    PS1='[\u@\h \W$(__git_ps1 " (%s)")]\$ '
  fi
fi
