# Loaded only in Tmux Style panes, or explicitly sourced after an upgrade.
unalias theme tmx tmux-style workspace 2>/dev/null || :
tmx() {
  if [[ ${1:-} == refresh && $# == 1 ]]; then
    source "$TMUX_STYLE_HOME/shell/commands.sh"
    return
  fi
  bash "$TMUX_STYLE_HOME/cli.sh" "$@"
}
tmux-style() { tmx "$@"; }
theme() { tmx theme "$@"; }
workspace() { tmx workspace "$@"; }
source "$TMUX_STYLE_HOME/shell/prompt.sh"
source "$TMUX_STYLE_HOME/shell/prism.sh"
