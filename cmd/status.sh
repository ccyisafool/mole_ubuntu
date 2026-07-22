#!/usr/bin/env bash
# mo status — live system dashboard (CPU, memory, disk, network, battery)

_meter() { # $1=pct $2=width -> colored bar
  local pct=$1 width=${2:-24} color filled
  (( pct < 0 )) && pct=0
  (( pct > 100 )) && pct=100
  filled=$((pct * width / 100))
  if (( pct < 60 )); then color=$C_GREEN
  elif (( pct < 85 )); then color=$C_YELLOW
  else color=$C_RED; fi
  printf '%s%s%s%s' "$color" "${BAR_FULL:0:$filled}" "${BAR_EMPTY:0:$((width - filled))}" "$C_RESET"
}

_cpu_sample() { # -> "total idle"
  awk '/^cpu /{
    total = $2+$3+$4+$5+$6+$7+$8+$9
    idle  = $5+$6
    print total, idle
  }' /proc/stat
}

_net_sample() { # -> "rx tx" summed over non-lo interfaces
  awk -F'[: ]+' '/:/{ if ($2 != "lo") { rx += $3; tx += $11 } } END { print rx+0, tx+0 }' /proc/net/dev
}

_render_status() { # $1=cpu_pct $2=rx_rate $3=tx_rate
  local cpu_pct=$1 rx_rate=$2 tx_rate=$3

  # uptime & load
  local up load
  up=$(awk '{s=int($1); printf "%dd %dh %dm", s/86400, (s%86400)/3600, (s%3600)/60}' /proc/uptime)
  load=$(cut -d' ' -f1-3 /proc/loadavg)

  # memory
  local mt ma st sf mem_used mem_pct swap_used
  read -r mt ma st sf < <(awk '
    /^MemTotal:/{mt=$2} /^MemAvailable:/{ma=$2}
    /^SwapTotal:/{st=$2} /^SwapFree:/{sf=$2}
    END{print mt, ma, st, sf}' /proc/meminfo)
  mem_used=$(( (mt - ma) * 1024 ))
  mem_pct=$(( mt > 0 ? (mt - ma) * 100 / mt : 0 ))
  swap_used=$(( (st - sf) * 1024 ))

  # temperature (hottest thermal zone)
  local temp="" t z
  for z in /sys/class/thermal/thermal_zone*/temp; do
    [[ -r $z ]] || continue
    t=$(<"$z")
    (( t / 1000 > ${temp:-0} )) && temp=$((t / 1000))
  done

  # battery
  local bat="" b
  for b in /sys/class/power_supply/BAT*; do
    [[ -r $b/capacity ]] || continue
    bat="$(<"$b"/capacity)% ($(tr '[:upper:]' '[:lower:]' <"$b"/status 2>/dev/null))"
    break
  done

  printf '%s\n' "${C_BOLD}${C_MAGENTA}MOLE STATUS${C_RESET}  ${HOSTNAME:-$(hostname)}  ${C_DIM}up $up${C_RESET}"
  printf '\n'
  printf ' %-5s %s %3d%%   %s\n' "CPU" "$(_meter "$cpu_pct")" "$cpu_pct" \
    "${C_DIM}load $load$( [[ -n $temp ]] && printf '   %s°C' "$temp")${C_RESET}"
  printf ' %-5s %s %3d%%   %s\n' "MEM" "$(_meter "$mem_pct")" "$mem_pct" \
    "${C_DIM}$(human_size "$mem_used") / $(human_size "$((mt * 1024))")$( (( st > 0 )) && printf '   swap %s' "$(human_size "$swap_used")")${C_RESET}"

  # disks (unique mounts for / and /home)
  local line
  while IFS= read -r line; do
    local mnt=$(awk '{print $1}' <<<"$line")
    local size=$(awk '{print $2}' <<<"$line")
    local used=$(awk '{print $3}' <<<"$line")
    local pct=$(awk '{gsub("%",""); print $4}' <<<"$line")
    printf ' %-5s %s %3d%%   %s\n' "DISK" "$(_meter "$pct")" "$pct" \
      "${C_DIM}$mnt  $(human_size "$used") / $(human_size "$size")${C_RESET}"
  done < <(df -B1 --output=target,size,used,pcent / "$HOME" 2>/dev/null | tail -n +2 | sort -u)

  printf ' %-5s ↓ %-10s ↑ %-10s\n' "NET" "$(human_size "$rx_rate")/s" "$(human_size "$tx_rate")/s"
  [[ -n $bat ]] && printf ' %-5s %s\n' "BAT" "$bat"

  printf '\n %s\n' "${C_BOLD}top processes${C_RESET}"
  ps -eo pid:7,comm:22,pcpu:6,pmem:6 --sort=-pcpu 2>/dev/null | head -6 \
    | sed 's/^/ /'
}

run_status() {
  local once=0 interval=2 arg prev=""
  for arg in "$@"; do
    if [[ $prev == --interval ]]; then interval="$arg"; prev=""; continue; fi
    case "$arg" in
      --once) once=1 ;;
      --interval) prev="--interval" ;;
    esac
  done
  [[ -t 1 ]] || once=1

  local t1 i1 t2 i2 r1 x1 r2 x2 dt di cpu_pct rx_rate tx_rate
  read -r t1 i1 < <(_cpu_sample)
  read -r r1 x1 < <(_net_sample)

  if (( once )); then
    sleep 1
    read -r t2 i2 < <(_cpu_sample)
    read -r r2 x2 < <(_net_sample)
    dt=$((t2 - t1)); di=$((i2 - i1))
    cpu_pct=$(( dt > 0 ? (dt - di) * 100 / dt : 0 ))
    _render_status "$cpu_pct" "$((r2 - r1))" "$((x2 - x1))"
    return 0
  fi

  trap 'tput cnorm 2>/dev/null; printf "\n"; return 0' INT TERM
  tput civis 2>/dev/null
  local key
  while true; do
    read -rt "$interval" -n1 key </dev/tty 2>/dev/null && [[ $key == q ]] && break
    read -r t2 i2 < <(_cpu_sample)
    read -r r2 x2 < <(_net_sample)
    dt=$((t2 - t1)); di=$((i2 - i1))
    cpu_pct=$(( dt > 0 ? (dt - di) * 100 / dt : 0 ))
    rx_rate=$(( (r2 - r1) / interval ))
    tx_rate=$(( (x2 - x1) / interval ))
    t1=$t2; i1=$i2; r1=$r2; x1=$x2
    printf '\e[H\e[2J'
    _render_status "$cpu_pct" "$rx_rate" "$tx_rate"
    printf '\n %s\n' "${C_DIM}refreshing every ${interval}s — press q to quit${C_RESET}"
  done
  tput cnorm 2>/dev/null
  trap - INT TERM
}
