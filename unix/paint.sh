#!/usr/bin/env bash
# Explicit plain-text output highlighter. Does not change normal command pipes.
set -uo pipefail
[[ $# -gt 0 ]] || { echo 'Usage: tmx paint COMMAND [ARG ...]' >&2; exit 1; }
"$@" | awk '
BEGIN { esc=sprintf("%c",27); reset=esc "[0m" }
{
  if(index($0,esc)){print;next}
  rest=$0; out=""
  while(match(rest,/(error|ERROR|failed|FAILED|success|passed|warning|WARN|[0-9]+([.:\/%-][0-9]+)*|[A-Za-z0-9_.~\/-]+\/[A-Za-z0-9_.~\/-]+)/)){
    token=substr(rest,RSTART,RLENGTH);color="255;224;138"
    if(token~/error|ERROR|failed|FAILED/)color="255;146;171"
    else if(token~/success|passed/)color="166;237;176"
    else if(token~/\//)color="125;220;254"
    out=out substr(rest,1,RSTART-1) esc "[38;2;" color "m" token reset
    rest=substr(rest,RSTART+RLENGTH)
  }
  print out rest
}'
results=("${PIPESTATUS[@]}")
if [[ ${results[0]} != 0 ]]; then exit "${results[0]}"; fi
exit "${results[1]}"
