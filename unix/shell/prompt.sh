# Loaded only in TMX's interactive Bash/Zsh wrappers. No user dotfiles changed.
source "$TMUX_STYLE_HOME/shell/palettes.sh"
tmx_prompt_colors() {
  local selected
  selected=$(tmux show-option -qv -t "$TMUX_PANE" @tmux_style_theme 2>/dev/null)
  TMX_PROMPT_THEME=$selected
  tmx_prompt_palette "$selected"
}
if [[ -n ${BASH_VERSION:-} ]]; then
  tmx_bash_prompt() {
    local result=$?
    tmx_prompt_colors
    # \w is expanded by Bash, rather than evaluating arbitrary directory text.
    PS1="\[\e[0;48;2;${TMX_PROMPT_BG}m\e[38;2;${TMX_PROMPT_ACCENT}m\] TMX \[\e[38;2;${TMX_PROMPT_FG}m\] \w \[\e[0m\]\n\[\e[38;2;${TMX_PROMPT_ACCENT}m\]> \[\e[0m\]"
    return "$result"
  }
  if [[ $(declare -p PROMPT_COMMAND 2>/dev/null) == 'declare -a '* ]]; then
    [[ " ${PROMPT_COMMAND[*]} " == *' tmx_bash_prompt '* ]] || PROMPT_COMMAND+=(tmx_bash_prompt)
  elif [[ ${PROMPT_COMMAND:-} != *tmx_bash_prompt* ]]; then
    PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }tmx_bash_prompt"
  fi
  tmx_bash_prompt
elif [[ -n ${ZSH_VERSION:-} ]]; then
  tmx_zsh_prompt() {
    tmx_prompt_colors
    (( $+functions[tmx_prism_syntax] )) && tmx_prism_syntax
    # Zsh's %~ escape renders the cwd without evaluating its contents.
    PROMPT=$'%{\e[0;48;2;'"${TMX_PROMPT_BG}"$'m\e[38;2;'"${TMX_PROMPT_ACCENT}"$'m%} TMX %{\e[38;2;'"${TMX_PROMPT_FG}"$'m%} %~ %{\e[0m%}\n%{\e[38;2;'"${TMX_PROMPT_ACCENT}"$'m%}> %{\e[0m%}'
  }
  typeset -ga precmd_functions
  (( ${precmd_functions[(Ie)tmx_zsh_prompt]} )) || precmd_functions+=(tmx_zsh_prompt)
  tmx_zsh_prompt
fi
