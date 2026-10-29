#!/usr/bin/env bash
# Helpers shared by the CLI, native hooks and the scoped shell commands.
current_session() {
  [[ -n ${TMUX:-} && -n ${TMUX_PANE:-} ]] || return 1
  local actual expected
  actual=$(tmux display-message -p -t "$TMUX_PANE" '#{socket_path}' 2>/dev/null) || return 1
  expected=$(tm display-message -p '#{socket_path}' 2>/dev/null) || return 1
  [[ $actual == "$expected" ]] || return 1
  tm display-message -p -t "$TMUX_PANE" '#{session_id}'
}
session_target() {
  tm has-session -t "=$1" 2>/dev/null || { echo "Session not found: $1. Run tmx list." >&2; return 1; }
  tm display-message -p -t "=$1:" '#{session_id}'
}
check_attach_context() {
  if [[ -n ${TMUX:-} ]] && ! current_session >/dev/null; then
    echo 'Detach from the other tmux server first (Ctrl-a d or Ctrl-b d).' >&2; return 1
  fi
}
attach_to() {
  check_attach_context || return 1
  if [[ -n ${TMUX:-} ]]; then
    if [[ -n ${1:-} ]]; then tm switch-client -t "$1"; else tm choose-tree -s; fi
  else
    if [[ -n ${1:-} ]]; then exec tmux -L "$socket" attach-session -t "$1"
    else exec tmux -L "$socket" attach-session; fi
  fi
}
attach_command() {
  local name=''
  if [[ ${1:-} == -t ]]; then
    [[ $# == 2 ]] || { echo 'Usage: tmx attach -t NAME' >&2; return 1; }
    shift
  fi
  [[ $# -le 1 ]] || { echo 'Usage: tmx attach [NAME] (or attach -t NAME)' >&2; return 1; }
  name=${1:-}
  if ! tm has-session 2>/dev/null; then
    echo 'No TMX sessions. Create one: tmx new work' >&2; return 1
  fi
  if [[ -n $name ]]; then name=$(session_target "$name") || return 1; fi
  attach_to "$name"
}
list_sessions() {
  if ! tm has-session 2>/dev/null; then
    echo 'No TMX sessions. Create one: tmx new work'; return
  fi
  printf 'NAME\tWINDOWS\tSTATE\tTHEME\n'
  tm list-sessions -F $'#{session_name}\t#{session_windows}\t#{?session_attached,attached,detached}\t#{@tmux_style_theme}'
}
workspace_command() {
  local mode=$1 name='' selected='' detached=false sid
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--detach) detached=true; shift ;;
      --theme) [[ $# -ge 2 ]] || { echo '--theme needs a theme name.' >&2; return 1; }; selected=$2; shift 2 ;;
      -s|--session) [[ $# -ge 2 && -z $name ]] || { echo 'Specify one session name.' >&2; return 1; }; name=$2; shift 2 ;;
      -*) echo "Unknown option: $1" >&2; return 1 ;;
      *) [[ -z $name ]] || { echo 'Specify one session name.' >&2; return 1; }; name=$1; shift ;;
    esac
  done
  if [[ $mode == workspace ]]; then name=${name:-TMUX}; fi
  [[ $name =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Usage: tmx new NAME [--theme NAME] [-d]. Use letters, numbers, underscores or hyphens.' >&2; return 1; }
  [[ -z $selected ]] || valid_theme "$selected" || { echo 'Choose a theme from: tmx themes' >&2; return 1; }
  $detached || check_attach_context || return 1
  if tm has-session -t "=$name" 2>/dev/null; then
    [[ $mode != new ]] || { echo "Session already exists: $name. Use tmx attach $name." >&2; return 1; }
    sid=$(session_target "$name") || return 1
  else
    sid=$(tmux -L "$socket" -f "$root/entry.conf" new-session -d -P -F '#{session_id}' -s "$name" -n shell -c "$PWD" \; \
      split-window -h -l '35%' -t "$name:1.1" -c "$PWD" \; \
      split-window -v -l '50%' -t "$name:1.2" -c "$PWD" \; select-pane -t "$name:1.1") || return 1
    selected=${selected:-$(tm show-option -gqv '@tmux_style_theme')}
  fi
  if [[ -n $selected ]]; then apply_session_theme "$sid" "$selected" || return 1; fi
  if $detached; then echo "Session ready: $name. Attach: tmx attach $name"
  else attach_to "$sid"; fi
}
