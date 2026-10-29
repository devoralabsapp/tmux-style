typeset _tmux_style_user_dir="$TMUX_STYLE_USER_ZDOTDIR"
if [[ -r $_tmux_style_user_dir/.zshenv ]]; then
  ZDOTDIR="$_tmux_style_user_dir"
  source "$_tmux_style_user_dir/.zshenv"
  TMUX_STYLE_USER_ZDOTDIR="${ZDOTDIR:-$HOME}"
fi
export ZDOTDIR="$TMUX_STYLE_HOME/shell/zsh"
unset _tmux_style_user_dir
