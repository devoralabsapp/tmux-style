#!/usr/bin/env bash
# Streaming plain text only. Existing ANSI/control sequences pass through.
exec awk '
BEGIN { esc=sprintf("%c",27); reset=esc "[0m" }
{
  if(index($0,esc) || index($0,sprintf("%c",13))){print;fflush();next}
  rest=$0; out=""
  while(match(rest,/(error|ERROR|failed|FAILED|failure|fatal|success|passed|running|warning|WARN|[0-9]+([.:\/%-][0-9]+)*|[A-Za-z0-9_.~\/-]+\/[A-Za-z0-9_.~\/-]+|--?[A-Za-z][A-Za-z_-]*)/)){
    token=substr(rest,RSTART,RLENGTH);color="255;224;138"
    if(token~/error|ERROR|failed|FAILED|failure|fatal/)color="255;146;171"
    else if(token~/success|passed|running/)color="166;237;176"
    else if(token~/\// || token~/^-/)color="125;220;254"
    out=out substr(rest,1,RSTART-1) esc "[38;2;" color "m" token reset
    rest=substr(rest,RSTART+RLENGTH)
  }
  print out rest;fflush()
}'
