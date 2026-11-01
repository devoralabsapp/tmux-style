#!/usr/bin/env bash
# Explicit plain-text output highlighter. Does not change normal command pipes.
set -uo pipefail
[[ $# -gt 0 ]] || { echo 'Usage: tmx paint COMMAND [ARG ...]' >&2; exit 1; }
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$@" | bash "$root/paint-filter.sh"
results=("${PIPESTATUS[@]}")
if [[ ${results[0]} != 0 ]]; then exit "${results[0]}"; fi
exit "${results[1]}"
