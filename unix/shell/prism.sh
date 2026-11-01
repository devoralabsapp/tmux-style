# Scoped interactive helpers. Pipelines, redirection and other themes bypass
# coloring; no DEBUG trap, global stdout redirection or command evaluation.
tmx_prism_run() {
  if [[ ${TMX_PROMPT_THEME:-} != prism || ! -t 1 || ${TMX_PRISM_OUTPUT:-1} == 0 ]]; then
    command "$@"; return $?
  fi
  # Only read-only, plain-text Git commands. Interactive commands keep their TTY.
  if [[ $1 == git ]]; then
    case ${2:-} in status|log|show|diff|branch) ;; *) command "$@"; return $? ;; esac
  fi
  if [[ $1 == ls ]]; then
    shift
    case $(uname -s) in
      Darwin) CLICOLOR=1 CLICOLOR_FORCE=1 command ls -G "$@" ;;
      *) command ls --color=always "$@" ;;
    esac
    return $?
  fi
  if [[ $1 == git ]]; then
    shift
    command git -c color.ui=always "$@"
    return $?
  fi
  local -a results
  if [[ -n ${ZSH_VERSION:-} ]]; then
    command "$@" | bash "$TMUX_STYLE_HOME/paint-filter.sh"
    results=("${pipestatus[@]}")
    if [[ ${results[1]} != 0 ]]; then return "${results[1]}"; fi
    return "${results[2]}"
  else
    command "$@" | bash "$TMUX_STYLE_HOME/paint-filter.sh"
    results=("${PIPESTATUS[@]}")
    if [[ ${results[0]} != 0 ]]; then return "${results[0]}"; fi
    return "${results[1]}"
  fi
}
if [[ ${TMX_PRISM_WRAPPERS_LOADED:-0} == 0 ]]; then
  for _tmx_command in ls pwd echo printf head tail grep rg find du df ps stat wc git; do
    # A user's function takes precedence. Existing aliases are left in place.
    if ! typeset -f "$_tmx_command" >/dev/null 2>&1; then
      eval "function $_tmx_command() { tmx_prism_run $_tmx_command \"\$@\"; }"
    fi
  done
  unset _tmx_command
  TMX_PRISM_WRAPPERS_LOADED=1
fi

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
