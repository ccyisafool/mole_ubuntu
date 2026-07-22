#!/usr/bin/env bash
# mo analyze — disk usage explorer

_analyze_list() { # $1=path $2=top-n : prints "size<TAB>path" biggest first
  local path=$1 top=$2
  du -sx --block-size=1 -- "$path"/* "$path"/.[!.]* "$path"/..?* 2>/dev/null \
    | sort -rn | head -n "$top"
}

_analyze_render() { # $1=path $2=top-n : sets ENTRY_PATHS[]
  local path=$1 top=$2 line sz p max=0 filled bar i=0 kind color
  ENTRY_PATHS=()

  printf '%s\n' "${C_BOLD}${C_BLUE}▸ ${path/#$HOME/\~}${C_RESET}  ${C_DIM}($(df -h --output=avail -- "$path" 2>/dev/null | tail -1 | tr -d ' ') free on this filesystem)${C_RESET}"

  local rows=()
  while IFS= read -r line; do rows+=("$line"); done < <(_analyze_list "$path" "$top")
  if (( ${#rows[@]} == 0 )); then
    info "${C_DIM}empty or unreadable${C_RESET}"
    return 0
  fi

  max=${rows[0]%%$'\t'*}
  (( max > 0 )) || max=1
  for line in "${rows[@]}"; do
    sz=${line%%$'\t'*}
    p=${line#*$'\t'}
    i=$((i + 1))
    ENTRY_PATHS+=("$p")
    filled=$((sz * 24 / max))
    bar="${BAR_FULL:0:$filled}${BAR_EMPTY:0:$((24 - filled))}"
    if [[ -d $p && ! -L $p ]]; then kind="/"; color=$C_CYAN; else kind=""; color=""; fi
    printf '  %2d) %s %8s  %s%s%s%s\n' "$i" "$bar" "$(human_size "$sz")" \
      "$color" "$(basename "$p")" "$kind" "$C_RESET"
  done
}

run_analyze() {
  local target="$HOME" top=15 once=0 arg prev=""
  for arg in "$@"; do
    if [[ $prev == --top ]]; then top="$arg"; prev=""; continue; fi
    case "$arg" in
      --top) prev="--top" ;;
      --once) once=1 ;;
      -*) ;;
      *) target="$arg" ;;
    esac
  done
  target=$(realpath -m -- "$target" 2>/dev/null || echo "$target")
  [[ -d $target ]] || { err "not a directory: $target"; return 1; }

  local ENTRY_PATHS=()

  # non-interactive: print once
  if (( once )) || [[ ! -t 0 || ! -t 1 ]]; then
    _analyze_render "$target" "$top"
    return 0
  fi

  # interactive drill-down
  local ans idx chosen
  while true; do
    clear
    printf '%s\n\n' "${C_BOLD}mo analyze${C_RESET} — disk explorer"
    _analyze_render "$target" "$top"
    printf '\n'
    read -rp "  ${C_BOLD}[1-${#ENTRY_PATHS[@]}]${C_RESET} open  ${C_BOLD}[u]${C_RESET}p  ${C_BOLD}[q]${C_RESET}uit > " ans </dev/tty || break
    case "$ans" in
      q|Q) break ;;
      u|U) target=$(dirname "$target") ;;
      ''|*[!0-9]*) ;;
      *)
        idx=$((ans - 1))
        if (( idx >= 0 && idx < ${#ENTRY_PATHS[@]} )); then
          chosen="${ENTRY_PATHS[$idx]}"
          if [[ -d $chosen && ! -L $chosen ]]; then
            target="$chosen"
          else
            printf '  %s\n' "${C_DIM}$(ls -lh -- "$chosen" 2>/dev/null)${C_RESET}"
            read -rp "  (enter to continue) " _ </dev/tty || true
          fi
        fi
        ;;
    esac
  done
  printf '\n'
}
