export ZDOTDIR="$TMUX_STYLE_USER_ZDOTDIR"
if [[ -r $ZDOTDIR/.zshrc ]]; then source "$ZDOTDIR/.zshrc"; fi
source "$TMUX_STYLE_HOME/shell/commands.sh"
