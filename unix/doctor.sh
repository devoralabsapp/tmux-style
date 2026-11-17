#!/usr/bin/env bash

doctor_report() {
  local version engine platform sessions panes prefix clipboard ssh=no terminal=unknown context=outside
  local columns rows used limit
  version=$(cat "$root/VERSION")
  [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || version=unknown
  engine=$(tmux -V 2>/dev/null) || engine=unavailable
  [[ $engine =~ ^tmux\ [0-9]+\.[0-9]+[a-z]?$ || $engine == unavailable ]] || engine=unknown
  platform=$(uname -s)
  [[ $platform == Linux || $platform == Darwin ]] || platform=unknown
  case "${TERM_PROGRAM:-}" in
    Apple_Terminal|iTerm.app|WezTerm|vscode) terminal=$TERM_PROGRAM ;;
  esac
  [[ -z ${SSH_TTY:-}${SSH_CONNECTION:-} ]] || ssh=yes
  sessions=$(tm list-sessions -F 1 2>/dev/null | wc -l) || sessions=0
  panes=$(tm list-panes -a -F 1 2>/dev/null | wc -l) || panes=0
  printf 'TMX: %s\nOS: %s\nBackend: tmux\nEngine: %s\nTerminal hint: %s\nSSH: %s\nSessions: %d\nPanes: %d\n' \
    "$version" "$platform" "$engine" "$terminal" "$ssh" "$sessions" "$panes"
  if current_session >/dev/null; then
    context=owned-pane
    prefix=$(tm show-options -Avq -t "$TMUX_PANE" prefix 2>/dev/null) || prefix=unknown
    case "$prefix" in C-a|C-b|None|F24) ;; *) prefix=other ;; esac
    printf 'Prefix: %s\n' "$prefix"
    if read -r columns rows used limit < <(tm display-message -p -t "$TMUX_PANE" \
      '#{pane_width} #{pane_height} #{history_size} #{history_limit}'); then
      printf 'Pane grid: %dx%d\nScrollback: %d / %d lines\n' "$columns" "$rows" "$used" "$limit"
    fi
  fi
  clipboard=$(tm show-options -sqv set-clipboard 2>/dev/null) || clipboard=unavailable
  case "$clipboard" in on|off|external|unavailable) ;; *) clipboard=unknown ;; esac
  printf 'Context: %s\nOSC 52 clipboard setting: %s\n' "$context" "$clipboard"
}
