#!/usr/bin/env bash
# Installs only owned assets and a launcher; leaves shell profiles/dotfiles alone.
set -euo pipefail
theme=midnight
usage() { echo 'Usage: bash unix/install.sh [--theme aurora|midnight|ember|paper|neon|black|code|hacker]'; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --theme) [[ $# -ge 2 ]] || { usage >&2; exit 1; }; theme=$2; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
done
case "$theme" in aurora|midnight|ember|paper|neon|black|code|hacker) ;; *) usage >&2; exit 1 ;; esac
case "$(uname -s)" in Linux|Darwin) ;; *) echo 'This installer requires Linux or macOS.' >&2; exit 1 ;; esac
if ! command -v tmux >/dev/null 2>&1; then
  echo 'Install tmux >= 3.2 first, then run this installer again:' >&2
  case "$(uname -s)" in
    Darwin) echo '  brew install tmux' >&2 ;;
    Linux) echo '  Ubuntu/Debian: sudo apt install tmux' >&2
           echo '  Fedora: sudo dnf install tmux | Arch: sudo pacman -S tmux | Alpine: apk add tmux bash' >&2 ;;
  esac
  exit 1
fi
version=$(tmux -V | awk '{print $2}')
if ! awk -v v="$version" 'BEGIN {split(v,n,"."); exit !(n[1]>3 || (n[1]==3 && n[2]+0>=2))}'; then
  echo "tmux >= 3.2 is required; found $version. No files changed." >&2; exit 1
fi
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
data="${XDG_DATA_HOME:-$HOME/.local/share}/tmux-style"
launcher="$HOME/.local/bin/tmx"
legacy_launcher="$HOME/.local/bin/tmux-style"
case "$data$HOME" in *$'\n'*|*$'\r'*) echo 'Paths must not contain line breaks.' >&2; exit 1 ;; esac
[[ $data == /* && $HOME == /* ]] || { echo 'HOME and XDG_DATA_HOME must be absolute.' >&2; exit 1; }
# Avoid destructive replacement of an unrelated directory or launcher.
if [[ -e $data && ! -f $data/install.id ]]; then
  echo "Refusing to replace an unrecognized directory: $data" >&2; exit 1
fi
if [[ -L $data ]]; then echo 'The owned asset directory must not be a symlink.' >&2; exit 1; fi
if [[ -d $launcher ]]; then echo "Launcher path is a directory: $launcher" >&2; exit 1; fi
if [[ -d $legacy_launcher ]]; then echo "Launcher path is a directory: $legacy_launcher" >&2; exit 1; fi
if [[ -e $launcher || -L $launcher ]]; then
  if [[ ! -f $data/launcher ]] || ! cmp -s "$launcher" "$data/launcher"; then
    echo "tmx already exists and belongs to another tool: $launcher. No files changed." >&2; exit 1
  fi
fi
mkdir -p "$(dirname "$data")" "$(dirname "$launcher")" "$data-backups"
backup=$(mktemp -d "$data-backups/install.XXXXXXXX")
stage=$(mktemp -d "$data.stage.XXXXXXXX")
cleanup() { [[ ! -d $stage ]] || rm -rf -- "$stage"; }
trap cleanup EXIT
if [[ -d $data ]]; then cp -pR "$data" "$backup/data"; fi
if [[ -e $legacy_launcher || -L $legacy_launcher ]]; then cp -pP "$legacy_launcher" "$backup/launcher"; fi
if [[ -e $launcher || -L $launcher ]]; then cp -pP "$launcher" "$backup/launcher-tmx"; fi
cp "$source_dir/"*.sh "$source_dir/tmux.conf" "$stage/"
cp -R "$source_dir/themes" "$stage/themes"
cp -R "$source_dir/shell" "$stage/shell"
cp "$source_dir/themes/$theme.conf" "$stage/theme.conf"
cp "$source_dir/../VERSION" "$stage/VERSION"
printf 'tmux-style-unix-v1\n' > "$stage/install.id"
printf '%s\n' "$backup" > "$stage/previous-backup"
# Quote tmux string syntax, including paths with spaces, quotes and dollar signs.
escaped=${data//\\/\\\\}; escaped=${escaped//\$/\\\$}; escaped=${escaped//\"/\\\"}
printf 'TMUX_STYLE_HOME="%s"\nsource-file "$TMUX_STYLE_HOME/tmux.conf"\n' "$escaped" > "$stage/entry.conf"
printf '#!/usr/bin/env bash\nexport TMUX_STYLE_HOME=%q\nexec bash "$TMUX_STYLE_HOME/cli.sh" "$@"\n' "$data" > "$stage/launcher"
chmod 755 "$stage/"*.sh "$stage/launcher"
if [[ -d $data ]]; then mv "$data" "$backup/replaced"; fi
if ! mv "$stage" "$data"; then
  [[ ! -d $backup/replaced ]] || mv "$backup/replaced" "$data"
  exit 1
fi
for command_path in "$launcher" "$legacy_launcher"; do
  launcher_stage=$(mktemp "$HOME/.local/bin/.tmx.XXXXXXXX")
  if ! cp "$data/launcher" "$launcher_stage" || ! chmod 755 "$launcher_stage" || ! mv -f "$launcher_stage" "$command_path"; then
    rm -f -- "$launcher_stage"
    rm -rf -- "$data"
    [[ ! -d $backup/replaced ]] || mv "$backup/replaced" "$data"
    for command_path in "$launcher" "$legacy_launcher"; do
      rm -f -- "$command_path"
      if [[ $command_path == "$launcher" ]]; then prior="$backup/launcher-tmx"; else prior="$backup/launcher"; fi
      [[ ! -e $prior && ! -L $prior ]] || cp -pP "$prior" "$command_path"
    done
    echo 'Could not install commands; restored previous assets and launchers.' >&2; exit 1
  fi
done
printf '\nInstalled TMX %s for %s (%s).\n' "$(cat "$data/VERSION")" "$(uname -s)" "$theme"
printf 'Start: %s\nNew: %s new work\nAttach: %s attach work\nUninstall: %s uninstall\nBackup: %s\n' "$launcher" "$launcher" "$launcher" "$launcher" "$backup"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo 'Use the full command above, or add ~/.local/bin to PATH yourself.' ;; esac
echo 'Existing tmux sessions and ~/.tmux.conf were left in place.'
