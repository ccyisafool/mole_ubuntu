#!/usr/bin/env bash
# mo status — flicker-free system dashboard: CPU, memory, disk, network, GPU, processes

shopt -s extglob

SPARKS=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
COLW=46

# visible length: character count minus ANSI color sequences
_vlen() { local s=${1//$'\e'\[*([0-9;])m/}; echo "${#s}"; }

_pad() { # string width
  local s=$1 w=$2 n
  n=$(_vlen "$s")
  if (( n >= w )); then printf '%s' "$s"; else printf '%s%*s' "$s" "$((w - n))" ''; fi
}

_rule() { # icon title -> COLW-wide section header
  local head="${C_BOLD}$1 $2${C_RESET} " fill="" n
  n=$(_vlen "$head")
  while (( n + ${#fill} < COLW )); do fill+="╌"; done
  printf '%s%s' "$head" "${C_DIM}${fill}${C_RESET}"
}

_hbar() { # pct [width]
  local pct=$1 w=${2:-16} color f
  (( pct < 0 )) && pct=0
  (( pct > 100 )) && pct=100
  f=$(( pct * w / 100 ))
  if (( pct < 60 )); then color=$C_GREEN; elif (( pct < 85 )); then color=$C_YELLOW; else color=$C_RED; fi
  printf '%s%s%s%s%s' "$color" "${BAR_FULL:0:f}" "$C_DIM" "${BAR_EMPTY:0:$((w - f))}" "$C_RESET"
}

_minibar() { # pct (may have decimals / exceed 100)
  local pct=${1%%.*} f full="▮▮▮▮▮" empty="▯▯▯▯▯"
  f=$(( pct / 20 )); (( f > 5 )) && f=5
  printf '%s%s' "${full:0:f}" "${empty:0:$((5 - f))}"
}

_spark() { # values...
  local max=1 v out=""
  for v in "$@"; do (( v > max )) && max=$v; done
  for v in "$@"; do out+="${SPARKS[$(( v * 7 / max ))]}"; done
  printf '%s' "$out"
}

_rate() { printf '%s/s' "$(human_size "$1")"; }

# ---- samplers ---------------------------------------------------------------

_sample_cpu() { # fills CUR_TOT[] CUR_IDLE[]: index 0 = aggregate, 1..N = cores
  CUR_TOT=(); CUR_IDLE=()
  local line
  while read -r line; do
    [[ $line == cpu* ]] || break
    set -- $line
    CUR_TOT+=( "$(( $2 + $3 + $4 + $5 + $6 + $7 + $8 + ${9:-0} ))" )
    CUR_IDLE+=( "$(( $5 + $6 ))" )
  done < /proc/stat
}

_sample_net() { # -> "rx tx"
  awk -F'[: ]+' '/:/{ if ($2 != "lo") { rx += $3; tx += $11 } } END { print rx+0, tx+0 }' /proc/net/dev
}

_sample_disk_io() { # -> "read_bytes write_bytes" (whole physical disks only)
  awk '$3 ~ /^(sd[a-z]+|nvme[0-9]+n[0-9]+|vd[a-z]+|mmcblk[0-9]+)$/ { r += $6; w += $10 }
       END { print r * 512, w * 512 }' /proc/diskstats
}

_hottest_temp() {
  local t z best=""
  for z in /sys/class/thermal/thermal_zone*/temp; do
    [[ -r $z ]] || continue
    t=$(<"$z")
    (( t / 1000 > ${best:-0} )) && best=$(( t / 1000 ))
  done
  echo "$best"
}

# ---- the mole ---------------------------------------------------------------

_mole_pose() { # anim-tick header-width -> sets MOLE_X, MOLE_L1..L3
  local anim=$1 width=$2 w=14 range p dir step eyes
  range=$(( width - w )); (( range < 1 )) && range=1
  p=$(( anim % (2 * range) ))
  dir=1
  (( p >= range )) && { p=$(( 2 * range - p - 1 )); dir=0; }   # ping-pong walk
  MOLE_X=$p
  step=$(( anim % 2 ))
  eyes="o o"; (( anim % 24 < 2 )) && eyes="- -"                # occasional blink
  if (( dir )); then   # waddling right
    MOLE_L1='     ___      '
    MOLE_L2="  __($eyes)     "
    if (( step )); then MOLE_L3='.~/(  mm )    '; else MOLE_L3=' ~\(  mm )    '; fi
  else                 # waddling left
    MOLE_L1='      ___     '
    MOLE_L2="     ($eyes)__  "
    if (( step )); then MOLE_L3='    ( mm  )\~.'; else MOLE_L3='    ( mm  )/~ '; fi
  fi
}

# ---- dashboard --------------------------------------------------------------

run_status() {
  local once=0 interval=2 arg prev=""
  for arg in "$@"; do
    if [[ $prev == --interval ]]; then interval="$arg"; prev=""; continue; fi
    case "$arg" in
      --once) once=1 ;;
      --interval) prev="--interval" ;;
    esac
  done
  [[ -t 0 && -t 1 ]] || once=1
  (( interval >= 1 )) || interval=1

  # ---- static facts
  local host=${HOSTNAME:-$(hostname)}
  local cpu_model
  cpu_model=$(awk -F': ' '/model name/{print $2; exit}' /proc/cpuinfo)
  cpu_model=${cpu_model%% with*}; cpu_model=${cpu_model:0:30}
  local nthreads; nthreads=$(nproc 2>/dev/null || echo "?")
  local ram_total_kb; ram_total_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
  local gpu_name=""
  have nvidia-smi && gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)

  local RX_HIST=() TX_HIST=()
  local CUR_TOT=() CUR_IDLE=() PRV_TOT=() PRV_IDLE=()
  local prv_rx prv_tx prv_dr prv_dw first=1 last_cols=0

  _sample_cpu; PRV_TOT=("${CUR_TOT[@]}"); PRV_IDLE=("${CUR_IDLE[@]}")
  read -r prv_rx prv_tx < <(_sample_net)
  read -r prv_dr prv_dw < <(_sample_disk_io)

  local ERASE=""
  if (( ! once )); then
    ERASE=$'\e[K'
    # alternate screen buffer (like top/htop): no scrollback pollution, no scroll-jump,
    # and quitting restores exactly what was on the terminal before
    trap 'printf "\e[?1049l\e[?25h\e[0m"; trap - INT TERM EXIT; return 0' INT TERM
    trap 'printf "\e[?1049l\e[?25h\e[0m"' EXIT
    printf '\e[?1049h\e[2J\e[?25l'
  fi

  # two clocks: mole animates every subtick (~5 fps), data refreshes every interval
  local subtick="0.2" data_every=$(( interval * 5 )) anim=0 header_w=$COLW key
  (( data_every < 1 )) && data_every=5

  while true; do
    if (( once )); then
      sleep 1
    elif (( anim % data_every != 0 )); then
      # fast tick: redraw only the 3 mole lines (rows 2-4), leave the panels alone
      _mole_pose "$anim" "$header_w"
      printf '\e[2;1H%s\e[K\n%s\e[K\n%s\e[K' \
        "$(printf '%*s' "$MOLE_X" '')${C_YELLOW}$MOLE_L1${C_RESET}" \
        "$(printf '%*s' "$MOLE_X" '')${C_YELLOW}$MOLE_L2${C_RESET}" \
        "$(printf '%*s' "$MOLE_X" '')${C_YELLOW}$MOLE_L3${C_RESET}"
      key=""
      read -rst "$subtick" -n1 key </dev/tty 2>/dev/null && [[ $key == q ]] && break
      anim=$(( anim + 1 ))
      continue
    fi

    # ---- deltas
    _sample_cpu
    local dt di cpu_pct=0 i
    dt=$(( CUR_TOT[0] - PRV_TOT[0] )); di=$(( CUR_IDLE[0] - PRV_IDLE[0] ))
    (( dt > 0 )) && cpu_pct=$(( (dt - di) * 100 / dt ))
    local strip="" cores=$(( ${#CUR_TOT[@]} - 1 )) step=1 p
    (( cores > 36 )) && step=2
    for (( i = 1; i <= cores; i += step )); do
      dt=$(( CUR_TOT[i] - PRV_TOT[i] )); di=$(( CUR_IDLE[i] - PRV_IDLE[i] ))
      p=0; (( dt > 0 )) && p=$(( (dt - di) * 100 / dt ))
      (( p > 100 )) && p=100
      strip+="${SPARKS[$(( p * 7 / 100 ))]}"
    done
    PRV_TOT=("${CUR_TOT[@]}"); PRV_IDLE=("${CUR_IDLE[@]}")

    local rx tx rx_rate tx_rate
    read -r rx tx < <(_sample_net)
    rx_rate=$(( (rx - prv_rx) / interval )); tx_rate=$(( (tx - prv_tx) / interval ))
    (( rx_rate < 0 )) && rx_rate=0; (( tx_rate < 0 )) && tx_rate=0
    prv_rx=$rx; prv_tx=$tx
    RX_HIST+=("$rx_rate"); TX_HIST+=("$tx_rate")
    (( ${#RX_HIST[@]} > 16 )) && RX_HIST=("${RX_HIST[@]:1}") && TX_HIST=("${TX_HIST[@]:1}")

    local dr dw dr_rate dw_rate
    read -r dr dw < <(_sample_disk_io)
    dr_rate=$(( (dr - prv_dr) / interval )); dw_rate=$(( (dw - prv_dw) / interval ))
    (( dr_rate < 0 )) && dr_rate=0; (( dw_rate < 0 )) && dw_rate=0
    prv_dr=$dr; prv_dw=$dw

    # ---- memory
    local mt ma st sf
    read -r mt ma st sf < <(awk '/^MemTotal:/{mt=$2} /^MemAvailable:/{ma=$2}
      /^SwapTotal:/{st=$2} /^SwapFree:/{sf=$2} END{print mt, ma, st, sf}' /proc/meminfo)
    local mem_pct=0 swap_pct=0
    (( mt > 0 )) && mem_pct=$(( (mt - ma) * 100 / mt ))
    (( st > 0 )) && swap_pct=$(( (st - sf) * 100 / st ))

    # ---- misc
    local temp load up
    temp=$(_hottest_temp)
    load=$(cut -d' ' -f1-3 /proc/loadavg)
    up=$(awk '{s=int($1); printf "%dd %dh %dm", s/86400, (s%86400)/3600, (s%3600)/60}' /proc/uptime)

    local bat=""
    local b
    for b in /sys/class/power_supply/BAT*; do
      [[ -r $b/capacity ]] || continue
      bat="$(<"$b"/capacity)% ($(tr '[:upper:]' '[:lower:]' <"$b"/status 2>/dev/null))"
      break
    done

    local gpu_line=""
    if [[ -n $gpu_name ]]; then
      local gu gm gt gtot
      IFS=', ' read -r gu gm gtot gt < <(nvidia-smi \
        --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu \
        --format=csv,noheader,nounits 2>/dev/null | head -1)
      [[ $gu =~ ^[0-9]+$ ]] && gpu_line="$(_hbar "$gu" 8) ${gu}% · $(human_size $((gm * 1024 * 1024)))/$(human_size $((gtot * 1024 * 1024))) · ${gt}°C"
    fi

    # ---- health score
    local score=100 label dot
    (( cpu_pct  > 80 )) && score=$(( score - (cpu_pct - 80) / 2 ))
    (( mem_pct  > 80 )) && score=$(( score - (mem_pct - 80) ))
    (( swap_pct > 50 )) && score=$(( score - (swap_pct - 50) / 5 ))
    [[ -n $temp ]] && (( temp > 75 )) && score=$(( score - (temp - 75) ))
    local root_pct
    root_pct=$(df --output=pcent / 2>/dev/null | tail -1 | tr -dc '0-9')
    (( ${root_pct:-0} > 85 )) && score=$(( score - (root_pct - 85) ))
    (( score < 0 )) && score=0
    if   (( score >= 90 )); then dot="${C_GREEN}●${C_RESET}"; label="All clear"
    elif (( score >= 70 )); then dot="${C_YELLOW}◐${C_RESET}"; label="Fine"
    elif (( score >= 50 )); then dot="${C_YELLOW}◐${C_RESET}"; label="Under load"
    else                         dot="${C_RED}○${C_RESET}";   label="Stressed"; fi

    # ---- panels
    local P_CPU=() P_MEM=() P_DISK=() P_PWR=() P_PROC=() P_NET=()

    P_CPU+=("$(_rule "◉" "CPU")")
    P_CPU+=("Total  $(_hbar "$cpu_pct") $(printf '%5s%%' "$cpu_pct")")
    P_CPU+=("Cores  ${C_CYAN}${strip}${C_RESET}")
    P_CPU+=("Load   ${load// / \/ } ${C_DIM}· ${nthreads} threads${C_RESET}")

    P_MEM+=("$(_rule "◫" "Memory")")
    P_MEM+=("Used   $(_hbar "$mem_pct") $(printf '%5s%%' "$mem_pct")")
    if (( st > 0 )); then
      P_MEM+=("Swap   $(_hbar "$swap_pct") $(printf '%5s%%' "$swap_pct") ${C_DIM}$(human_size $(( (st - sf) * 1024 )))/$(human_size $(( st * 1024 )))${C_RESET}")
    else
      P_MEM+=("Swap   ${C_DIM}none${C_RESET}")
    fi
    P_MEM+=("Total  $(human_size $(( (mt - ma) * 1024 ))) / $(human_size $(( mt * 1024 ))) ${C_DIM}· avail $(human_size $(( ma * 1024 )))${C_RESET}")

    P_DISK+=("$(_rule "▥" "Disk")")
    local line mnt fstype size used pcent shown=0
    while read -r mnt fstype size used pcent; do
      [[ $mnt == Mounted* || -z $mnt ]] && continue
      pcent=${pcent%\%}
      P_DISK+=("$(_pad "${mnt:0:6}" 7)$(_hbar "$pcent" 10) $(printf '%3s%%' "$pcent") ${C_DIM}$(human_size "$used")/$(human_size "$size") ${fstype}${C_RESET}")
      shown=$((shown + 1))
    done < <(df -B1 --output=target,fstype,size,used,pcent / "$HOME" 2>/dev/null | tail -n +2 | sort -u)
    P_DISK+=("I/O    ${C_DIM}R${C_RESET} $(_rate "$dr_rate") ${C_DIM}· W${C_RESET} $(_rate "$dw_rate")")

    P_PWR+=("$(_rule "◪" "Power")")
    P_PWR+=("Batt   ${bat:-${C_DIM}No battery${C_RESET}}")
    [[ -n $gpu_line ]] && P_PWR+=("GPU    $gpu_line")
    P_PWR+=("Temp   ${temp:-?}°C ${C_DIM}· up ${up}${C_RESET}")

    P_PROC+=("$(_rule "❊" "Processes")")
    local rank=1 pcpu rss comm
    while read -r pcpu rss comm; do
      [[ $comm == ps ]] && continue   # ps measures its own brief lifetime as ~100%
      P_PROC+=("#$rank $(_minibar "$pcpu") $(printf '%5s%%' "$pcpu") $(printf '%7s' "$(human_size $(( rss * 1024 )))") ${comm:0:16}")
      rank=$((rank + 1))
      (( rank > 3 )) && break
    done < <(ps -eo pcpu,rss,comm --sort=-pcpu --no-headers 2>/dev/null | head -5)

    P_NET+=("$(_rule "⇅" "Network")")
    P_NET+=("Down   ${C_CYAN}$(_pad "$(_spark "${RX_HIST[@]}")" 16)${C_RESET} $(_rate "$rx_rate")")
    P_NET+=("Up     ${C_CYAN}$(_pad "$(_spark "${TX_HIST[@]}")" 16)${C_RESET} $(_rate "$tx_rate")")
    local ifc ip vpn="" v
    read -r ifc ip < <(ip -o -4 route get 1.1.1.1 2>/dev/null \
      | awk '{for(i=1;i<NF;i++){if($i=="dev")d=$(i+1); if($i=="src")s=$(i+1)} print d, s}')
    for v in /sys/class/net/wg* /sys/class/net/tun* /sys/class/net/tailscale*; do
      [[ -e $v ]] || continue
      v=$(basename "$v")
      vpn=" ${C_DIM}·${C_RESET} $v $(ip -o -4 addr show dev "$v" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)"
      break
    done
    P_NET+=("${ifc:-?} ${C_DIM}·${C_RESET} ${ip:-?}${vpn}")

    # ---- equalize panel pair heights
    local pair r
    for pair in "P_CPU P_MEM" "P_DISK P_PWR" "P_PROC P_NET"; do
      set -- $pair
      local -n _a=$1 _b=$2
      while (( ${#_a[@]} < ${#_b[@]} )); do _a+=(""); done
      while (( ${#_b[@]} < ${#_a[@]} )); do _b+=(""); done
    done

    # ---- compose frame
    local cols; cols=$(tput cols 2>/dev/null || echo 100)
    local two_col=1; (( cols < COLW * 2 + 2 )) && two_col=0
    if (( ! once && ( first || cols != last_cols ) )); then printf '\e[2J'; fi
    last_cols=$cols

    header_w=$(( two_col ? COLW * 2 + 2 : COLW ))
    _mole_pose "$anim" "$header_w"
    local mole_x=$MOLE_X

    local -a FL=()
    FL+=("${C_BOLD}${C_MAGENTA}Mole${C_RESET}  Health $dot ${C_BOLD}$score${C_RESET} $label  ${C_DIM}$host · $cpu_model · $(human_size $(( ram_total_kb * 1024 ))) RAM${gpu_name:+ · ${gpu_name#NVIDIA }}${C_RESET}")
    FL+=("$(printf '%*s' "$mole_x" '')${C_YELLOW}$MOLE_L1${C_RESET}")
    FL+=("$(printf '%*s' "$mole_x" '')${C_YELLOW}$MOLE_L2${C_RESET}")
    FL+=("$(printf '%*s' "$mole_x" '')${C_YELLOW}$MOLE_L3${C_RESET}")

    if (( two_col )); then
      for pair in "P_CPU P_MEM" "P_DISK P_PWR" "P_PROC P_NET"; do
        set -- $pair
        local -n _l=$1 _r2=$2
        for (( r = 0; r < ${#_l[@]}; r++ )); do
          FL+=("$(_pad "${_l[$r]}" $COLW)  ${_r2[$r]}")
        done
        FL+=("")
      done
    else
      FL+=("${P_CPU[@]}" "" "${P_MEM[@]}" "" "${P_DISK[@]}" "" "${P_PWR[@]}" "" "${P_PROC[@]}" "" "${P_NET[@]}")
    fi

    if (( once )); then
      printf '%s\n' "${FL[@]}"
      break
    fi
    FL+=("${C_DIM}live · data every ${interval}s · q quits${C_RESET}")

    # never print more lines than the window has, or every frame scrolls (= visible "refresh")
    local rows; rows=$(tput lines 2>/dev/null || echo 24)
    (( ${#FL[@]} > rows - 1 )) && FL=("${FL[@]:0:rows-1}")
    local FRAME
    printf -v FRAME "%s$ERASE\n" "${FL[@]}"
    printf '\e[H%s\e[0J' "$FRAME"
    first=0
    key=""
    read -rst "$subtick" -n1 key </dev/tty 2>/dev/null && [[ $key == q ]] && break
    anim=$(( anim + 1 ))
  done

  if (( ! once )); then
    printf '\e[?1049l\e[?25h\e[0m'
    trap - INT TERM EXIT
  fi
}
