#!/usr/bin/env bash
set -euo pipefail
if command -v pbcopy >/dev/null 2>&1; then
  pbcopy
elif [[ -n ${WAYLAND_DISPLAY:-} ]] && command -v wl-copy >/dev/null 2>&1; then
  wl-copy
elif [[ -n ${DISPLAY:-} ]] && command -v xclip >/dev/null 2>&1; then
  xclip -selection clipboard
elif [[ -n ${DISPLAY:-} ]] && command -v xsel >/dev/null 2>&1; then
  xsel --clipboard --input
else
  # tmux performs OSC 52 delivery to attached clients, also over SSH.
  tmux load-buffer -w -
fi
