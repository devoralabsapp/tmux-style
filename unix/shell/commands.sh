# Loaded only in Tmux Style panes, or explicitly sourced after an upgrade.
unalias theme tmx tmux-style workspace 2>/dev/null || :
tmx() { bash "$TMUX_STYLE_HOME/cli.sh" "$@"; }
tmux-style() { tmx "$@"; }
theme() { tmx theme "$@"; }
workspace() { tmx workspace "$@"; }
