#!/usr/bin/env bash
set -euo pipefail
[[ $(uname -s) == Darwin ]] || { echo 'Use the Linux installer on Linux.' >&2; exit 1; }
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bash "$root/unix/install.sh" "$@"
# Keep Finder's terminal open long enough to read the launch command.
if [[ $# == 0 && -t 0 ]]; then read -r -p 'Press Enter to close. ' _; fi
