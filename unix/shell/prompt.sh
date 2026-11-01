# Loaded only in TMX's interactive Bash/Zsh wrappers. No user dotfiles changed.
source "$TMUX_STYLE_HOME/shell/palettes.sh"
TMX_PROMPT_PLATFORM=$(uname -s)
tmx_prompt_colors() {
  local selected
  selected=$(tmux show-option -qv -t "$TMUX_PANE" @tmux_style_theme 2>/dev/null)
  TMX_PROMPT_THEME=$selected
  tmx_prompt_palette "$selected"
  TMX_PROMPT_CWD=$TMX_PROMPT_FG
  if [[ $TMX_PROMPT_PLATFORM == Darwin ]]; then TMX_PROMPT_CWD=$TMX_PROMPT_PATH_RED; fi
}
if [[ -n ${BASH_VERSION:-} ]]; then
  tmx_bash_prompt() {
    local result=$?
    tmx_prompt_colors
    tmx_render_signal prompt
    # \w is expanded by Bash, rather than evaluating arbitrary directory text.
    PS1="\[\e[0;48;2;${TMX_PROMPT_BG}m\e[38;2;${TMX_PROMPT_ACCENT}m\] TMX \[\e[38;2;${TMX_PROMPT_CWD}m\] \w \[\e[0m\]\n\[\e[38;2;${TMX_PROMPT_ACCENT}m\]> \[\e[0m\]"
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
    tmx_render_signal prompt
    (( $+functions[tmx_prism_syntax] )) && tmx_prism_syntax
    # Zsh's %~ escape renders the cwd without evaluating its contents.
    TMX_CANONICAL_PROMPT=$'%{\e[0;48;2;'"${TMX_PROMPT_BG}"$'m\e[38;2;'"${TMX_PROMPT_ACCENT}"$'m%} TMX %{\e[38;2;'"${TMX_PROMPT_CWD}"$'m%} %~ %{\e[0m%}\n%{\e[38;2;'"${TMX_PROMPT_ACCENT}"$'m%}> %{\e[0m%}'
    PROMPT=$TMX_CANONICAL_PROMPT
    RPROMPT=''
  }
  # Stop a prompt framework's async renderer within this owned shell. Startup
  # files, completions, environment and unrelated hooks still load normally.
  if (( $+functions[prompt_powerlevel9k_teardown] )); then prompt_powerlevel9k_teardown; fi
  tmx_zsh_prompt_guard() {
    if [[ $PROMPT != $TMX_CANONICAL_PROMPT || -n $RPROMPT ]]; then
      PROMPT=$TMX_CANONICAL_PROMPT
      RPROMPT=''
      zle .reset-prompt
    fi
  }
  autoload -Uz add-zle-hook-widget
  add-zle-hook-widget -d line-init tmx_zsh_prompt_guard 2>/dev/null || :
  add-zle-hook-widget -d line-pre-redraw tmx_zsh_prompt_guard 2>/dev/null || :
  add-zle-hook-widget line-init tmx_zsh_prompt_guard
  add-zle-hook-widget line-pre-redraw tmx_zsh_prompt_guard
  typeset -ga precmd_functions
  (( ${precmd_functions[(Ie)tmx_zsh_prompt]} )) || precmd_functions+=(tmx_zsh_prompt)
  tmx_zsh_prompt
fi
