#!/usr/bin/env bash
apply_session_theme() {
  local sid=$1 selected=$2 windows staged result=0
  [[ $sid =~ ^\$[0-9]+$ ]] && valid_theme "$selected" || return 1
  # BSD awk rejects literal newlines in a -v assignment; IDs contain no spaces.
  windows=$(tm list-windows -t "$sid" -F '#{window_id}' | tr '\n' ' ') || return 1
  staged=$(mktemp "${TMPDIR:-/tmp}/tmux-style-theme.XXXXXXXX")
  # Each session owns its status and each of its windows owns pane/tab colors.
  # Use stable tmux IDs so renamed sessions and shell metacharacters stay safe.
  if ! awk -v sid="$sid" -v windows="$windows" '
    BEGIN { q=sprintf("%c",39); n=split(windows,ids," ") }
    /^set -g / { sub(/^set -g /,"set -t " q sid q " "); print; next }
    /^setw -g / {
      for(i=1;i<=n;i++) { line=$0; sub(/^setw -g /,"setw -t " q ids[i] q " ",line); print line }
      next
    }
    { print }
  ' "$root/themes/$selected.conf" > "$staged"; then
    rm -f -- "$staged"; return 1
  fi
  tm source-file "$staged" || result=$?
  rm -f -- "$staged"
  return "$result"
}
pane_session() {
  [[ ${1:-} =~ ^%[0-9]+$ ]] || return 1
  tm display-message -p -t "$1" '#{session_id}'
}
sync_session_theme() {
  local sid=$1 selected
  selected=$(tm show-option -qv -t "$sid" '@tmux_style_theme') || return 1
  if ! valid_theme "$selected"; then selected=$(tm show-option -gqv '@tmux_style_theme'); fi
  apply_session_theme "$sid" "$selected"
}
theme_session() {
  local sessions
  if [[ -n ${TMUX:-} ]]; then
    current_session || { echo 'Run theme inside a Tmux Style session, or specify --session NAME.' >&2; return 1; }
  else
    sessions=$(tm list-sessions -F '#{session_id}') || return 1
    [[ $sessions != *$'\n'* ]] || { echo 'Several sessions are running. Use tmux-style theme NAME --session SESSION.' >&2; return 1; }
    printf '%s\n' "$sessions"
  fi
}
theme_command() {
  local selected='' target='' pane='' default=false sid staged
  if [[ $# == 0 ]]; then
    if current_session >/dev/null; then choose_theme; else printf '%s\n' aurora midnight ember paper neon black code hacker; fi
    return
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session|-t) [[ $# -ge 2 && -z $target && -z $pane ]] || return 1; target=$2; shift 2 ;;
      --pane) [[ $# -ge 2 && -z $target && -z $pane ]] || return 1; pane=$2; shift 2 ;;
      --default) default=true; shift ;;
      *) [[ -z $selected ]] || { echo 'Specify one theme name.' >&2; return 1; }; selected=$1; shift ;;
    esac
  done
  valid_theme "$selected" || { echo 'Choose a name from: tmux-style themes' >&2; return 1; }
  if $default || { [[ -z $target && -z $pane ]] && ! tm has-session 2>/dev/null; }; then
    [[ -z $target && -z $pane ]] || { echo '--default cannot target a session.' >&2; return 1; }
    staged=$(mktemp "$root/theme.XXXXXXXX")
    cp "$root/themes/$selected.conf" "$staged"; mv "$staged" "$root/theme.conf"
    if tm has-session 2>/dev/null; then
      # Freeze inherited colors before changing defaults for future sessions.
      while IFS= read -r sid; do sync_session_theme "$sid"; done < <(tm list-sessions -F '#{session_id}')
      tm source-file "$root/theme.conf"
    fi
    echo "Default theme for new sessions: $selected"; return
  fi
  if [[ -n $pane ]]; then sid=$(pane_session "$pane") || return 1
  elif [[ -n $target ]]; then sid=$(session_target "$target") || return 1
  else sid=$(theme_session) || return 1; fi
  apply_session_theme "$sid" "$selected" || return 1
  echo "Theme: $selected (current session; existing panes keep running)."
}
choose_theme() {
  local pane=${TMUX_PANE:-} sid selected key=1
  if [[ $# -gt 0 ]]; then [[ $# == 2 && $1 == --pane ]] || return 1; pane=$2; fi
  sid=$(pane_session "$pane") || { echo 'Attach to a Tmux Style session to open the theme menu.' >&2; return 1; }
  local menu=()
  for selected in aurora midnight ember paper neon black code hacker; do
    menu+=("$selected" "$key" "run-shell 'bash \"\$TMUX_STYLE_HOME/cli.sh\" theme $selected --pane $pane >/dev/null'")
    key=$((key+1))
  done
  tm display-menu -t "$pane" -T 'Choose a theme for this session' "${menu[@]}"
}
