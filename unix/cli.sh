#!/usr/bin/env bash
set -euo pipefail
root=${TMUX_STYLE_HOME:?Run the installed tmux-style launcher.}
[[ -f $root/install.id ]] || { echo 'Installation is incomplete; reinstall Tmux Style.' >&2; exit 1; }
socket=tmux-style
tm() { tmux -L "$socket" "$@"; }
valid_theme() { case "$1" in aurora|midnight|ember|paper|neon|black|code|hacker) return 0 ;; *) return 1 ;; esac; }
case "${1:-workspace}" in
  --version|version) cat "$root/VERSION" ;;
  --help|-h|help)
    echo 'tmux-style [workspace [name] | theme NAME | themes | metrics | restore | version]'
    echo 'Ctrl-a t selects a theme; Ctrl-a d detaches; F12 toggles SSH pass-through.' ;;
  themes) printf '%s\n' aurora midnight ember paper neon black code hacker ;;
  theme)
    [[ $# == 2 ]] && valid_theme "$2" || { echo 'Choose a name from: tmux-style themes' >&2; exit 1; }
    staged=$(mktemp "$root/theme.XXXXXXXX")
    cp "$root/themes/$2.conf" "$staged"
    mv "$staged" "$root/theme.conf"
    if tm has-session 2>/dev/null; then
      tm source-file "$root/entry.conf"
      tm refresh-client -S 2>/dev/null || true
    fi
    echo "Theme: $2 (current Tmux Style server and future sessions)." ;;
  choose-theme)
    # Only predefined names are used in these tmux command strings.
    menu=()
    for name in aurora midnight ember paper neon black code hacker; do
      menu+=("$name" "" "run-shell 'bash \"\$TMUX_STYLE_HOME/cli.sh\" theme $name'")
    done
    tm display-menu -T 'Choose a theme' "${menu[@]}" ;;
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
  workspace)
    [[ $# -le 2 ]] || { echo 'Usage: tmux-style workspace [name]' >&2; exit 1; }
    name=${2:-TMUX}
    [[ $name =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Session name: letters, numbers, underscores or hyphens only.' >&2; exit 1; }
    if [[ -n ${TMUX:-} ]]; then
      current=$(tmux display-message -p '#{socket_path}')
      expected=$(tm display-message -p '#{socket_path}' 2>/dev/null || true)
      [[ $current == "$expected" ]] || { echo 'Detach from the other tmux server first (Ctrl-a d or Ctrl-b d).' >&2; exit 1; }
    fi
    if ! tm has-session -t "=$name" 2>/dev/null; then
      # One command queue keeps layout creation ordered and avoids shell races.
      tmux -L "$socket" -f "$root/entry.conf" new-session -d -s "$name" -n shell -c "$PWD" \; \
        split-window -h -l '35%' -t "$name:1.1" -c "$PWD" \; \
        split-window -v -l '50%' -t "$name:1.2" -c "$PWD" \; select-pane -t "$name:1.1"
    fi
    if [[ -n ${TMUX:-} ]]; then tm switch-client -t "=$name"; else exec tmux -L "$socket" attach-session -t "=$name"; fi ;;
  *) echo 'Unknown command. Run tmux-style --help.' >&2; exit 1 ;;
esac
