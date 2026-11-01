# Private OSC markers delimit command display from shell editing/prompt text.
# They are consumed by render.py and never sent to the outside terminal.
tmx_render_signal() {
  [[ ${TMX_RENDER_ACTIVE:-0} == 1 ]] || return 0
  local mode=$1
  if [[ $mode == command && ${TMX_OUTPUT_HIGHLIGHT:-1} == 0 ]]; then mode=command-off; fi
  builtin printf '\033]777;tmx;%s;%s;%s\007' "$TMX_RENDER_TOKEN" "$mode" "${TMX_PROMPT_THEME:-midnight}"
}
if [[ -n ${ZSH_VERSION:-} ]]; then
  tmx_render_preexec() { tmx_render_signal command; }
  typeset -ga preexec_functions
  (( ${preexec_functions[(Ie)tmx_render_preexec]} )) || preexec_functions+=(tmx_render_preexec)
elif [[ -n ${BASH_VERSION:-} && ${TMX_RENDER_ACTIVE:-0} == 1 && ${TMX_RENDER_DEBUG_LOADED:-0} == 0 ]]; then
  # DEBUG executes before a top-level command, including compound commands.
  # Preserve an existing user's DEBUG action in the same trap rather than
  # replacing its behavior. Bash does not recurse into a DEBUG trap by default.
  _tmx_debug=$(trap -p DEBUG)
  if [[ -n $_tmx_debug ]]; then
    # trap -p shell-quotes its action. Decode that quoted argument, rather
    # than stripping quotes and breaking a hook containing apostrophes.
    _tmx_capture_debug() { TMX_PRIOR_DEBUG=$1; }
    eval "${_tmx_debug/trap -- /_tmx_capture_debug }"
    unset -f _tmx_capture_debug
    trap "$TMX_PRIOR_DEBUG; tmx_render_signal command" DEBUG
  else
    trap 'tmx_render_signal command' DEBUG
  fi
  unset _tmx_debug
  TMX_RENDER_DEBUG_LOADED=1
fi
