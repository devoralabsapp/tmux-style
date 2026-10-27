#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [[ $# -gt 1 ]]; then
  echo 'Usage: bash install.sh [midnight|aurora|ember|paper|neon]' >&2; exit 1
fi
selected="${1:-midnight}"
case "$selected" in
  midnight) config="$repo_dir/tmux.conf"; theme_name='Midnight / Cyan' ;;
  aurora) config="$repo_dir/themes/aurora.conf"; theme_name='Aurora' ;;
  ember) config="$repo_dir/themes/ember.conf"; theme_name='Ember' ;;
  paper) config="$repo_dir/themes/paper.conf"; theme_name='Paper / Ink' ;;
  neon) config="$repo_dir/themes/neon.conf"; theme_name='Neon / Circuit' ;;
  *) echo 'Choose midnight, aurora, ember, paper or neon.' >&2; exit 1 ;;
esac
[[ -f "$config" ]] || { echo "Missing configuration: $config" >&2; exit 1; }
command -v tmux >/dev/null || { echo 'Please install tmux first.' >&2; exit 1; }
version="$(tmux -V | awk '{print $2}')"
if ! awk -v version="$version" 'BEGIN { split(version,v,"."); exit !(v[1]>3 || (v[1]==3 && v[2]+0>=2)) }'; then
  echo "These themes require tmux >= 3.2; found $version." >&2
  exit 1
fi
for helper in yank.sh renew_env.sh tmux.remote.conf plugins/tpm/tpm; do
  if [[ ! -f "$HOME/.tmux/$helper" ]]; then
    echo "Missing ~/.tmux/$helper. Install the samoshkin base configuration first." >&2
    exit 1
  fi
done
target="$HOME/.tmux.conf"
if [[ ! -f "$target" ]]; then
  echo 'No existing ~/.tmux.conf found. Install the samoshkin base configuration first.' >&2
  exit 1
fi
backup_dir="$HOME/.tmux/backups"
mkdir -p "$backup_dir"
backup="$(mktemp "$backup_dir/tmux.conf.before-$selected.XXXXXXXX")"
cp -p "$target" "$backup"
# Follow the existing ~/.tmux.conf symlink, preserving the samoshkin layout.
cat "$config" > "$target"
printf 'Installed %s. Backup: %s\n' "$theme_name" "$backup"
printf 'Apply in your existing tmux session: tmux source-file ~/.tmux.conf\n'
printf 'Restore: cat "%s" > ~/.tmux.conf && tmux source-file ~/.tmux.conf\n' "$backup"
