#!/usr/bin/env bash
set -euo pipefail
root=${TMUX_STYLE_HOME:?Run the installed tmx launcher.}
[[ -f $root/install.id ]] || { echo 'Installation is incomplete; reinstall TMX.' >&2; exit 1; }
socket=tmux-style
tm() { tmux -L "$socket" "$@"; }
valid_theme() { case "$1" in aurora|midnight|ember|paper|neon|black|code|hacker|prism) return 0 ;; *) return 1 ;; esac; }
source "$root/session.sh"
source "$root/theme.sh"
source "$root/lifecycle.sh"
command_name=${1:-workspace}
if [[ $# -gt 0 ]]; then shift; fi
case "$command_name" in
  --version|version) cat "$root/VERSION" ;;
  --help|-h|help)
    echo 'tmx new NAME [--theme NAME] [-d] | attach [NAME] | list | detach | exit'
    echo 'tmx workspace [NAME] | theme [NAME] [--session NAME | --default]'
    echo 'tmx themes | metrics | update | restore | uninstall | version'
    echo 'Ctrl-a t selects a theme; Ctrl-a d detaches; F12 toggles SSH pass-through.' ;;
  themes) printf '%s\n' aurora midnight ember paper neon black code hacker prism ;;
  theme) theme_command "$@" ;;
  choose-theme) choose_theme "$@" ;;
  sync-theme) sid=$(pane_session "${1:-}") || exit 1; sync_session_theme "$sid" ;;
  sync-themes)
    if tm has-session 2>/dev/null; then
      while IFS= read -r sid; do sync_session_theme "$sid"; done < <(tm list-sessions -F '#{session_id}')
    fi ;;
  new|new-session) workspace_command new "$@" ;;
  workspace) workspace_command workspace "$@" ;;
  attach|attach-session|a) attach_command "$@" ;;
  list|ls|sessions) list_sessions ;;
  detach) current_session >/dev/null || { echo 'Run detach inside a Tmux Style session.' >&2; exit 1; }; tm detach-client ;;
  exit)
    [[ $# == 0 ]] || { echo 'Usage: tmx exit (inside the session to close)' >&2; exit 1; }
    sid=$(current_session) || { echo 'Run tmx exit inside the TMX session to close.' >&2; exit 1; }
    tm kill-session -t "$sid" ;;
  metrics) exec bash "$root/metrics.sh" ;;
  paint) exec bash "$root/paint.sh" "$@" ;;
  update)
    [[ $# == 0 ]] || { echo 'Usage: tmx update' >&2; exit 1; }
    exec "${TMX_PYTHON:-python3}" "$root/shell/update.py" "$root" ;;
  restore) restore_installation ;;
  uninstall|remove) uninstall_tool "$@" ;;
  *) echo 'Unknown command. Run tmx --help.' >&2; exit 1 ;;
esac
