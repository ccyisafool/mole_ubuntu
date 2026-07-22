#!/usr/bin/env bash
# mo uninstall — remove a package/app (apt, snap, flatpak) plus its leftovers

_scan_leftovers() { # names... -> prints candidate leftover paths, deduped
  local n d hit
  {
    for n in "$@"; do
      [[ ${#n} -ge 3 ]] || continue
      for d in "$HOME/.config" "$HOME/.cache" "$HOME/.local/share" "$HOME/.local/state"; do
        find "$d" -maxdepth 1 -iname "*$n*" 2>/dev/null
      done
      find "$HOME/.config/autostart" "$HOME/.config/systemd/user" \
           "$HOME/.local/share/applications" -maxdepth 1 -type f -iname "*$n*" 2>/dev/null
    done
  } | sort -u
}

run_uninstall() {
  local query="${1:-}"

  printf '%s\n' "${C_BOLD}mo uninstall${C_RESET} — remove apps and their remnants$( (( DRY_RUN )) && printf ' %s' "${C_YELLOW}(dry run)${C_RESET}")"

  # ---- collect installed apps: "source<TAB>id<TAB>display" ------------------
  local entries=() name rest
  if have snap; then
    while read -r name rest; do
      [[ -z $name || $name == Name ]] && continue
      entries+=("snap"$'\t'"$name"$'\t'"$name")
    done < <(snap list 2>/dev/null)
  fi
  if have flatpak; then
    local app disp
    while IFS=$'\t' read -r app disp; do
      [[ -n $app ]] && entries+=("flatpak"$'\t'"$app"$'\t'"${disp:-$app}")
    done < <(flatpak list --app --columns=application,name 2>/dev/null)
  fi
  while read -r name; do
    [[ -n $name ]] && entries+=("apt"$'\t'"$name"$'\t'"$name")
  done < <(apt-mark showmanual 2>/dev/null | sort)

  (( ${#entries[@]} )) || { err "no installed packages found"; return 1; }

  # ---- filter by query ------------------------------------------------------
  local matches=() e
  if [[ -n $query ]]; then
    for e in "${entries[@]}"; do
      [[ ${e,,} == *"${query,,}"* ]] && matches+=("$e")
    done
    (( ${#matches[@]} )) || { err "nothing installed matches '$query'"; return 1; }
  else
    matches=("${entries[@]}")
  fi

  # ---- pick one -------------------------------------------------------------
  local chosen=""
  if (( ${#matches[@]} == 1 )); then
    chosen="${matches[0]}"
  elif [[ ! -t 0 || ! -t 1 ]]; then
    section "Installed (${#matches[@]})"
    for e in "${matches[@]}"; do
      printf '  %-8s %s\n' "$(cut -f1 <<<"$e")" "$(cut -f2 <<<"$e")"
    done
    info "${C_DIM}re-run with a name: mo uninstall <name>${C_RESET}"
    return 0
  elif have fzf; then
    chosen=$(printf '%s\n' "${matches[@]}" \
      | awk -F'\t' '{printf "%-8s %-40s %s\n", $1, $2, $3}' \
      | fzf --height=60% --prompt="uninstall > " --header="source   id" ) || return 0
    local cid csrc
    csrc=$(awk '{print $1}' <<<"$chosen")
    cid=$(awk '{print $2}' <<<"$chosen")
    for e in "${matches[@]}"; do
      [[ $e == "$csrc"$'\t'"$cid"$'\t'* ]] && { chosen="$e"; break; }
    done
  else
    section "Matches (${#matches[@]})"
    if (( ${#matches[@]} > 60 && ${#query} == 0 )); then
      info "${C_DIM}long list — tip: mo uninstall <name> to filter${C_RESET}"
    fi
    local i
    for i in "${!matches[@]}"; do
      printf '  %3d) %-8s %-40s %s\n' "$((i + 1))" \
        "$(cut -f1 <<<"${matches[$i]}")" "$(cut -f2 <<<"${matches[$i]}")" \
        "${C_DIM}$(cut -f3 <<<"${matches[$i]}")${C_RESET}"
    done
    local pick
    read -rp "  ${C_BOLD}Which one? (number, q to cancel)${C_RESET} " pick 2>/dev/null </dev/tty || return 0
    [[ $pick =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= ${#matches[@]} )) || { info "cancelled"; return 0; }
    chosen="${matches[$((pick - 1))]}"
  fi
  [[ -n $chosen ]] || return 0

  local src id
  src=$(cut -f1 <<<"$chosen")
  id=$(cut -f2 <<<"$chosen")

  section "Uninstalling ${C_BOLD}$id${C_RESET} ${C_DIM}($src)${C_RESET}"
  confirm_or_dry "Remove $id via $src?" || { info "cancelled"; return 0; }

  case "$src" in
    apt)
      run_root apt-get remove --purge -y "$id"
      run_root apt-get autoremove --purge -y
      ;;
    snap)
      run_root snap remove "$id"
      ;;
    flatpak)
      run_user flatpak uninstall -y "$id"
      ;;
  esac

  # ---- leftovers ------------------------------------------------------------
  local names=("$id")
  case "$src" in
    apt)
      local stripped="${id%-stable}"; stripped="${stripped%-bin}"; stripped="${stripped%-app}"
      [[ $stripped != "$id" ]] && names+=("$stripped")
      ;;
    flatpak)
      names+=("${id##*.}")   # org.gimp.GIMP -> GIMP
      ;;
    snap)
      names+=()
      ;;
  esac

  section "Leftover files"
  local leftovers=() hit
  while IFS= read -r hit; do
    [[ -n $hit ]] && leftovers+=("$hit")
  done < <(_scan_leftovers "${names[@]}")
  case "$src" in
    snap)    [[ -d "$HOME/snap/$id"      ]] && leftovers+=("$HOME/snap/$id") ;;
    flatpak) [[ -d "$HOME/.var/app/$id"  ]] && leftovers+=("$HOME/.var/app/$id") ;;
  esac

  if (( ${#leftovers[@]} == 0 )); then
    info "no user-level leftovers found"
  else
    queue_reset
    local l
    for l in "${leftovers[@]}"; do
      queue_add "$(basename "$l")" "$l"
    done
    if (( ${#QUEUE_PATHS[@]} == 0 )); then
      info "no user-level leftovers found"
    else
      warn "review carefully — matched by name, could belong to something else:"
      queue_flush "Remove these leftovers?"
    fi
  fi

  freed_summary
}
