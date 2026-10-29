#!/usr/bin/env bash
# Local host statistics; no network requests or persistent background process.
set -eu
cpu='--'; mem='--'
case "$(uname -s)" in
  Linux)
    if [[ -r /proc/stat ]]; then
      first=$(head -n 1 /proc/stat)
      sleep 0.1
      second=$(head -n 1 /proc/stat)
      cpu=$(printf '%s\n%s\n' "$first" "$second" | awk '
        { total=0; for(i=2;i<=9;i++) total+=$i; idle=$5+$6 }
        NR==1 { oldtotal=total; oldidle=idle; next }
        { d=total-oldtotal; if(d>0) printf "%.0f",100*(d-idle+oldidle)/d; else printf "0" }')
    fi
    if [[ -r /proc/meminfo ]]; then
      mem=$(awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2; found=1}
        END {if(t>0 && found) printf "%.0f",100*(t-a)/t; else printf "--"}' /proc/meminfo)
    fi ;;
  Darwin)
    cpu=$(LC_ALL=C top -l 1 -n 0 2>/dev/null | awk '/CPU usage:/ {
      for(i=1;i<=NF;i++) if($i=="idle") {gsub(/%/,"",$(i-1)); printf "%.0f",100-$(i-1); found=1; exit}}
      END {if(!found) printf "--"}') || cpu='--'
    total=$(sysctl -n hw.memsize 2>/dev/null) || total=0
    mem=$(vm_stat 2>/dev/null | awk -v total="$total" '
      /page size of/ {for(i=1;i<=NF;i++) if($i=="bytes)") page=$(i-1)}
      /^Pages (free|inactive|speculative|purgeable):/ {gsub(/\./,"",$NF); available+=$NF}
      END {if(total>0 && page>0) {used=100*(total-available*page)/total;
        if(used<0) used=0; if(used>100) used=100; printf "%.0f",used} else printf "--"}') || mem='--' ;;
esac
printf 'CPU %s%%  RAM %s%%\n' "$cpu" "$mem"
