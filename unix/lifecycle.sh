#!/usr/bin/env bash
# Deactivate owned files with a recoverable move; never terminate sessions.
check_owned_installation() {
  local resolved home_resolved
  [[ $root == /* && ! -L $root && ${root##*/} == tmux-style ]] || { echo 'Invalid owned installation directory.' >&2; return 1; }
  [[ $(cat "$root/install.id") == tmux-style-unix-v1 && -O $root/install.id ]] || return 1
  resolved=$(CDPATH= cd -P -- "$root" && pwd)
  home_resolved=$(CDPATH= cd -P -- "$HOME" && pwd)
  [[ $resolved != / && $resolved != "$home_resolved" ]] || return 1
  if tm has-session 2>/dev/null; then
    echo 'Exit all TMX sessions first, then run this command from an outer terminal. Use tmx list to see them.' >&2; return 1
  fi
  [[ ! -L $root-backups ]] || { echo 'The backup directory must not be a symlink.' >&2; return 1; }
  local name path
  for name in tmx tmux-style; do
    path="$HOME/.local/bin/$name"
    if [[ -e $path || -L $path ]]; then
      [[ ! -d $path ]] && cmp -s "$path" "$root/launcher" || {
        echo "Command was changed after installation: $path. No files removed." >&2; return 1;
      }
    fi
  done
  mkdir -p "$root-backups"
}
checked_backup() {
  local candidate=$1 base resolved
  [[ -d $candidate && ! -L $candidate ]] || return 1
  base=$(CDPATH= cd -P -- "$root-backups" && pwd)
  resolved=$(CDPATH= cd -P -- "$candidate" && pwd)
  [[ ${resolved%/*} == "$base" && ${resolved##*/} == install.* ]] || return 1
  printf '%s\n' "$resolved"
}
save_owned_installation() {
  local operation=$1 name path
  saved=$(mktemp -d "$root-backups/$operation.XXXXXXXX")
  # Every path below is either the checked installation or one exact launcher.
  mv "$root" "$saved/data" || return 1
  for name in tmx tmux-style; do
    path="$HOME/.local/bin/$name"
    if [[ -e $path || -L $path ]]; then
      if ! mv "$path" "$saved/$name"; then
        for name in tmx tmux-style; do
          [[ ! -e $saved/$name ]] || mv "$saved/$name" "$HOME/.local/bin/$name"
        done
        mv "$saved/data" "$root"
        return 1
      fi
    fi
  done
}
restore_installation() {
  check_owned_installation || return 1
  local backup saved
  backup=$(checked_backup "$(cat "$root/previous-backup")") || { echo 'Backup is missing or outside the owned backup directory.' >&2; return 1; }
  if [[ -d $backup/data ]]; then
    [[ ! -L $backup/data && $(cat "$backup/data/install.id") == tmux-style-unix-v1 ]] || return 1
  fi
  save_owned_installation before-restore || return 1
  if [[ -d $backup/data ]]; then cp -pR "$backup/data" "$root"; fi
  if [[ -e $backup/launcher || -L $backup/launcher ]]; then cp -pP "$backup/launcher" "$HOME/.local/bin/tmux-style"; fi
  if [[ -e $backup/launcher-tmx || -L $backup/launcher-tmx ]]; then cp -pP "$backup/launcher-tmx" "$HOME/.local/bin/tmx"; fi
  echo "Previous installation restored. Recovery copy: $saved"
}
uninstall_tool() {
  [[ $# == 0 ]] || { echo 'Usage: tmx uninstall' >&2; return 1; }
  check_owned_installation || return 1
  local pointer checked original='' saved count=0
  pointer=$(cat "$root/previous-backup")
  # Recover a command that predated the tool, rather than reinstalling an old
  # TMX version. Missing historical snapshots do not prevent deactivation.
  while [[ -n $pointer && -d $pointer && $count -lt 100 ]]; do
    checked=$(checked_backup "$pointer") || { echo 'Invalid historical backup; no files removed.' >&2; return 1; }
    if [[ -e $checked/launcher || -L $checked/launcher ]]; then
      if ! cmp -s "$checked/launcher" "$root/launcher"; then original="$checked/launcher"; fi
    fi
    [[ -f $checked/data/previous-backup && ! -L $checked/data ]] || break
    pointer=$(cat "$checked/data/previous-backup")
    count=$((count+1))
  done
  [[ $count -lt 100 ]] || { echo 'Backup chain contains a loop; no files removed.' >&2; return 1; }
  save_owned_installation uninstall || return 1
  if [[ -n $original ]]; then cp -pP "$original" "$HOME/.local/bin/tmux-style"; fi
  echo "TMX uninstalled. Backups and recovery files kept at: $saved"
}
