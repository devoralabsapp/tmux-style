#!/usr/bin/env bash
# Shell-local helpers; user startup files are read, never edited.
set -euo pipefail
root=${TMUX_STYLE_HOME:?}
user_shell=$(tmux show-option -gqv default-shell)
case "${user_shell##*/}" in
  bash) exec "$user_shell" --rcfile "$root/shell/bashrc" -i ;;
  zsh)
    export TMUX_STYLE_USER_ZDOTDIR=${ZDOTDIR:-$HOME}
    export ZDOTDIR="$root/shell/zsh"
    exec "$user_shell" -i ;;
  *) exec "$user_shell" -l ;;
esac
