#!/usr/bin/env bash
set -euo pipefail
root=${TMUX_STYLE_HOME:?Run the installed tmux-style launcher.}
[[ -f $root/install.id ]] || { echo 'Installation is incomplete; reinstall Tmux Style.' >&2; exit 1; }
socket=tmux-style
tm() { tmux -L "$socket" "$@"; }
valid_theme() { case "$1" in aurora|midnight|ember|paper|neon|black|code|hacker) return 0 ;; *) return 1 ;; esac; }
source "$root/session.sh"
source "$root/theme.sh"
command_name=${1:-workspace}
if [[ $# -gt 0 ]]; then shift; fi
case "$command_name" in
  --version|version) cat "$root/VERSION" ;;
  --help|-h|help)
    echo 'tmux-style new NAME [--theme NAME] [-d] | attach [NAME] | list | detach'
    echo 'tmux-style workspace [NAME] | theme [NAME] [--session NAME | --default]'
    echo 'tmux-style themes | metrics | restore | version'
    echo 'Ctrl-a t selects a theme; Ctrl-a d detaches; F12 toggles SSH pass-through.' ;;
  themes) printf '%s\n' aurora midnight ember paper neon black code hacker ;;
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
  metrics) exec bash "$root/metrics.sh" ;;
  restore)
    if tm has-session 2>/dev/null; then
      echo 'Close your Tmux Style sessions before restoring. Other tmux servers are unaffected.' >&2; exit 1
    fi
    backup=$(cat "$root/previous-backup")
    case "$backup" in "$root-backups/"*) ;; *) echo 'Invalid backup location.' >&2; exit 1 ;; esac
    [[ -d $backup ]] || { echo 'Backup is missing.' >&2; exit 1; }
    launcher="$HOME/.local/bin/tmux-style"
    if [[ -e $launcher || -L $launcher ]]; then
      cmp -s "$launcher" "$root/launcher" || { echo 'Launcher was edited; restore manually using the backup.' >&2; exit 1; }
    fi
    # Preserve the current installation for manual recovery before replacing it.
    saved=$(mktemp -d "$root-backups/before-restore.XXXXXXXX")
    mv "$root" "$saved/data"
    if [[ -d $backup/data ]]; then cp -pR "$backup/data" "$root"; fi
    rm -f -- "$launcher"
    if [[ -e $backup/launcher || -L $backup/launcher ]]; then cp -pP "$backup/launcher" "$launcher"; fi
    echo "Previous installation restored. Recovery copy: $saved" ;;
  *) echo 'Unknown command. Run tmux-style --help.' >&2; exit 1 ;;
esac
