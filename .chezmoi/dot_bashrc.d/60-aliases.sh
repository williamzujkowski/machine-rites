#!/usr/bin/env bash
# shellcheck shell=bash

# ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias lt='ls -alFtr'

# git aliases
alias gs='git status -sb'
alias gd='git diff'
alias gdc='git diff --cached'
alias gl='git log --oneline --graph --decorate'
alias gp='git pull'
alias gpu='git push'

# safety nets
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# shortcuts
alias h='history'
alias j='jobs -l'
alias path='echo -e ${PATH//:/\\n}'

# custom
alias homelab-status='cd "$HOME/git/homelab" && ./scripts/milestone-status.sh'
alias dotfiles-doctor='$HOME/git/machine-rites/tools/doctor.sh'
alias dotfiles-update='$HOME/git/machine-rites/tools/update.sh'
