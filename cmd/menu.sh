#!/usr/bin/env bash
# mo (no command) — interactive launcher menu

MENU_REPO="ccyisafool/mole_ubuntu"

# print cached latest-version instantly; refresh the cache in the background
# so the menu never waits on the network (notice shows from the next launch on)
_menu_latest() {
  local f="$MOLE_STATE_DIR/latest-version"
  cat "$f" 2>/dev/null
  ( curl -fsSL -m 3 "https://raw.githubusercontent.com/$MENU_REPO/main/lib/core.sh" 2>/dev/null \
      | grep -m1 '^MOLE_VERSION=' | cut -d'"' -f2 > "$f.tmp" \
      && [[ -s "$f.tmp" ]] && mv "$f.tmp" "$f" || rm -f "$f.tmp" ) >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

run_menu() {
  local names=(clean uninstall optimize analyze status)
  local descs=("Free up disk space" "Remove apps completely" "Refresh caches and services" "Explore disk usage" "Monitor system health")
  local xnames=(purge installer update)
  local xdescs=("Delete build artifacts" "Remove leftover installer files" "Update mole itself")

  local latest notice=""
  latest=$(_menu_latest)
  if [[ -n $latest && $latest != "$MOLE_VERSION" ]] \
     && [[ $(printf '%s\n%s\n' "$MOLE_VERSION" "$latest" | sort -V | tail -1) == "$latest" ]]; then
    notice="Update $latest available, run mo update"
  fi

  local sel=0 more=0 msg="" ch rest i
  trap 'printf "\e[?25h\e[0m"' EXIT
  trap 'printf "\e[?25h\e[0m\n"; trap - INT TERM EXIT; return 0' INT TERM
  printf '\e[?25l'

  while true; do
    local -a n=("${names[@]}") d=("${descs[@]}")
    if (( more )); then n+=("${xnames[@]}"); d+=("${xdescs[@]}"); fi
    (( sel >= ${#n[@]} )) && sel=$(( ${#n[@]} - 1 ))

    printf '\e[H\e[2J'
    printf '%s\n' \
      "${C_BOLD}${C_MAGENTA} __  __   ___  _     _____ ${C_RESET}" \
      "${C_BOLD}${C_MAGENTA}|  \/  | / _ \| |   | ____|${C_RESET}" \
      "${C_BOLD}${C_MAGENTA}| |\/| || | | | |   |  _|  ${C_RESET}  ${C_DIM}https://github.com/$MENU_REPO${C_RESET}" \
      "${C_BOLD}${C_MAGENTA}| |  | || |_| | |___| |___ ${C_RESET}  Deep clean and optimize your Ubuntu." \
      "${C_BOLD}${C_MAGENTA}|_|  |_| \___/|_____|_____|${C_RESET}"
    printf '\n'
    [[ -n $notice ]] && printf '%s\n\n' "${C_YELLOW}$notice${C_RESET}"

    for i in "${!n[@]}"; do
      if (( i == sel )); then
        printf '%s\n' "${C_BOLD}${C_CYAN}➤ $((i + 1)). $(printf '%-12s' "${n[$i]^}")${C_RESET} ${d[$i]}"
      else
        printf '%s\n' "  $((i + 1)). $(printf '%-12s' "${n[$i]^}") ${C_DIM}${d[$i]}${C_RESET}"
      fi
    done
    printf '\n%s\n' "${C_DIM}↑↓ move  |  Enter run  |  1-${#n[@]} jump  |  M $( (( more )) && echo less || echo more )  |  V version  |  Q quit${C_RESET}"
    [[ -n $msg ]] && printf '%s\n' "$msg"
    msg=""

    IFS= read -rsn1 ch </dev/tty || break
    case "$ch" in
      $'\e')
        rest=""
        IFS= read -rsn2 -t 0.05 rest </dev/tty
        case "$rest" in
          '[A') (( sel > 0 )) && sel=$(( sel - 1 )) ;;
          '[B') (( sel < ${#n[@]} - 1 )) && sel=$(( sel + 1 )) ;;
          '') break ;;                       # bare Esc quits
        esac ;;
      k) (( sel > 0 )) && sel=$(( sel - 1 )) ;;
      j) (( sel < ${#n[@]} - 1 )) && sel=$(( sel + 1 )) ;;
      [1-9]) (( ch <= ${#n[@]} )) && sel=$(( ch - 1 )) ;;
      m|M) more=$(( 1 - more )) ;;
      v|V) msg="mo (mole for ubuntu) v$MOLE_VERSION" ;;
      q|Q) break ;;
      '')                                    # Enter: run the selected command
        printf '\e[?25h\e[0m\e[H\e[2J'
        "$MOLE_HOME/mo" "${n[$sel]}"
        printf '\n'
        printf '%s ' "${C_DIM}Press Enter to return to the menu (q to quit)${C_RESET}"
        read -r ch </dev/tty || break
        [[ $ch == q || $ch == Q ]] && break
        printf '\e[?25l'
        ;;
    esac
  done

  printf '\e[?25h\e[0m\n'
  trap - INT TERM EXIT
}
