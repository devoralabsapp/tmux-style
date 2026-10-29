# Loaded only in Tmux Style panes, or explicitly sourced after an upgrade.
unalias theme tmux-style workspace 2>/dev/null || :
tmux-style() { bash "$TMUX_STYLE_HOME/cli.sh" "$@"; }
theme() { tmux-style theme "$@"; }
workspace() { tmux-style workspace "$@"; }
