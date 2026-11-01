# Command-entry highlighting only. All command output is handled by the PTY
# display renderer, including aliases, functions, external commands and stderr.
if [[ -n ${ZSH_VERSION:-} ]]; then
  # Vendor a fixed upstream release, so Prism works offline without Homebrew.
  if (( ! $+functions[_zsh_highlight] )); then
    typeset -ga ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)
    source "$TMUX_STYLE_HOME/shell/vendor/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
    TMX_OWNS_ZSH_HIGHLIGHT=1
  fi
  tmx_prism_syntax() {
    [[ ${TMX_OWNS_ZSH_HIGHLIGHT:-0} == 1 ]] || return 0
    if [[ ${TMX_PROMPT_THEME:-} == prism ]]; then
      ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)
      ZSH_HIGHLIGHT_STYLES[default]='fg=#e5e9ff'
      ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#ff92ab,bold'
      local role
      for role in command builtin function alias suffix-alias precommand; do
        ZSH_HIGHLIGHT_STYLES[$role]='fg=#ffe08a,bold'
      done
      ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=#e4a4ff'
      ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=#7ddcfe'
      ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=#7ddcfe'
      ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#a6edb0'
      ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#a6edb0'
      ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]='fg=#e4a4ff'
      ZSH_HIGHLIGHT_STYLES[path]='fg=#7ddcfe,underline'
      ZSH_HIGHLIGHT_STYLES[comment]='fg=#a9b4d0'
      ZSH_HIGHLIGHT_STYLES[commandseparator]='fg=#e4a4ff'
      ZSH_HIGHLIGHT_STYLES[bracket-level-1]='fg=#e4a4ff'
      ZSH_HIGHLIGHT_STYLES[bracket-level-2]='fg=#7ddcfe'
      ZSH_HIGHLIGHT_STYLES[bracket-level-3]='fg=#a6edb0'
      ZSH_HIGHLIGHT_STYLES[bracket-level-4]='fg=#ffe08a'
      ZSH_HIGHLIGHT_STYLES[bracket-error]='fg=#ff92ab,bold'
    else
      # Disable only the highlighter owned by TMX, not a user's own plugin.
      ZSH_HIGHLIGHT_HIGHLIGHTERS=()
    fi
  }
  tmx_prism_syntax
fi
