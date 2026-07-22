#!/usr/bin/env bash
# mo clean — remove caches, logs and temporary files

run_clean() {
  local deep=0 user_only=0 arg
  for arg in "$@"; do
    case "$arg" in
      --deep) deep=1 ;;
      --user-only) user_only=1 ;;
    esac
  done

  printf '%s\n' "${C_BOLD}mo clean${C_RESET} — reclaiming disk space$( (( DRY_RUN )) && printf ' %s' "${C_YELLOW}(dry run)${C_RESET}")"

  # ---- Trash & thumbnails ---------------------------------------------------
  section "Trash & thumbnails"
  queue_reset
  queue_add "Trash"            "$HOME/.local/share/Trash/files"
  queue_add "Trash metadata"   "$HOME/.local/share/Trash/info"
  queue_add "Thumbnail cache"  "$HOME/.cache/thumbnails"
  queue_flush "Empty trash and thumbnails?"

  # ---- Browser caches -------------------------------------------------------
  section "Browser caches ${C_DIM}(close browsers first for best results)${C_RESET}"
  queue_reset
  local b
  for b in google-chrome chromium BraveSoftware microsoft-edge vivaldi opera; do
    queue_add "$b cache" "$HOME/.cache/$b"
  done
  queue_add "firefox cache" "$HOME/.cache/mozilla"
  for b in firefox chromium brave; do
    queue_add "$b (snap) cache" "$HOME/snap/$b/common/.cache"
  done
  queue_flush "Clean browser caches?"

  # ---- Developer tool caches ------------------------------------------------
  section "Developer tool caches"
  queue_reset
  queue_add "npm cache"           "$HOME/.npm/_cacache"
  queue_add "pip cache"           "$HOME/.cache/pip"
  queue_add "yarn cache"          "$HOME/.cache/yarn"
  queue_add "pnpm cache"          "$HOME/.cache/pnpm"
  queue_add "go build cache"      "$HOME/.cache/go-build"
  queue_add "node-gyp cache"      "$HOME/.cache/node-gyp"
  queue_add "uv cache"            "$HOME/.cache/uv"
  queue_add "poetry cache"        "$HOME/.cache/pypoetry/cache"
  queue_add "cargo registry cache" "$HOME/.cargo/registry/cache"
  if (( deep )); then
    queue_add "gradle caches"     "$HOME/.gradle/caches"
    queue_add "maven repository"  "$HOME/.m2/repository"
  fi
  queue_flush "Clean developer caches?"

  # ---- Deep sweep of ~/.cache ----------------------------------------------
  if (( deep )); then
    section "Deep sweep: everything left in ~/.cache"
    queue_reset
    local entry
    for entry in "$HOME"/.cache/* "$HOME"/.cache/.[!.]*; do
      [[ -e $entry ]] || continue
      queue_add "cache: $(basename "$entry")" "$entry"
    done
    queue_flush "Sweep all of ~/.cache?"
  fi

  # ---- System (sudo) --------------------------------------------------------
  if (( ! user_only )); then
    section "System caches & logs ${C_DIM}(sudo)${C_RESET}"
    local apt_sz journal_usage
    apt_sz=$(path_size /var/cache/apt/archives)
    journal_usage=$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[KMGTP]?i?B?' | tail -1)
    info "APT package cache:        $(human_size "$apt_sz")"
    info "systemd journal:          ${journal_usage:-unknown}"
    info "rotated logs in /var/log: *.gz, *.old, *.1 ..."
    if confirm_or_dry "Clean system caches, old journal entries (>7d) and rotated logs?"; then
      run_root apt-get clean
      run_root journalctl --vacuum-time=7d
      run_root find /var/log -xdev -type f \
        \( -name '*.gz' -o -name '*.old' -o -name '*.[0-9]' \) -delete
      TOTAL_FREED=$((TOTAL_FREED + apt_sz))
    else
      info "skipped"
    fi
  fi

  # ---- Snap -----------------------------------------------------------------
  if have snap; then
    section "Snap"
    local snap_old
    snap_old=$(snap list --all 2>/dev/null | awk '/disabled/{print $1"="$3}')
    if [[ -n $snap_old ]]; then
      info "old disabled revisions:"
      local line
      while IFS= read -r line; do info "  ${line%%=*} (rev ${line##*=})"; done <<<"$snap_old"
      if confirm_or_dry "Remove old snap revisions?"; then
        while IFS= read -r line; do
          run_root snap remove "${line%%=*}" --revision="${line##*=}"
        done <<<"$snap_old"
      fi
    else
      info "${C_DIM}no old snap revisions${C_RESET}"
    fi
    # data snapshots snapd quietly keeps for 31 days after `snap remove`
    local snaps_saved
    snaps_saved=$(snap saved 2>/dev/null | tail -n +2)
    if [[ -n $snaps_saved && $snaps_saved != *"No snapshots"* ]]; then
      local sset sname sage sver srev ssize snotes sbytes
      info "saved snapshots of removed snaps:"
      while read -r sset sname sage sver srev ssize snotes; do
        [[ $sset =~ ^[0-9]+$ ]] || continue
        info "  #$sset  $sname  $ssize ${C_DIM}(age $sage)${C_RESET}"
      done <<<"$snaps_saved"
      if confirm_or_dry "Forget these snapshots? (snapd auto-deletes them after 31 days)"; then
        while read -r sset sname sage sver srev ssize snotes; do
          [[ $sset =~ ^[0-9]+$ ]] || continue
          if run_root snap forget "$sset"; then
            sbytes=$(awk -v s="$ssize" 'BEGIN{n=s+0; u=s; gsub(/[0-9.]/,"",u)
              m=1; if(u=="KB")m=1024; else if(u=="MB")m=1024^2; else if(u=="GB")m=1024^3; else if(u=="TB")m=1024^4
              printf "%d", n*m}')
            TOTAL_FREED=$((TOTAL_FREED + sbytes))
          fi
        done <<<"$snaps_saved"
      fi
    else
      info "${C_DIM}no saved snap snapshots${C_RESET}"
    fi
    queue_reset
    local d
    for d in "$HOME"/snap/*/common/.cache; do
      [[ -d $d ]] || continue
      queue_add "snap cache: $(basename "$(dirname "$(dirname "$d")")")" "$d"
    done
    queue_flush "Clean snap app caches?"
  fi

  # ---- Flatpak --------------------------------------------------------------
  if have flatpak; then
    section "Flatpak"
    queue_reset
    local d app
    for d in "$HOME"/.var/app/*/cache; do
      [[ -d $d ]] || continue
      app=$(basename "$(dirname "$d")")
      queue_add "flatpak cache: $app" "$d"
    done
    queue_flush "Clean flatpak app caches?"
    if confirm_or_dry "Remove unused flatpak runtimes?"; then
      run_user flatpak uninstall --unused -y
    fi
  fi

  freed_summary
  info "${C_DIM}operation log: ${MOLE_LOG/#$HOME/\~}${C_RESET}"
}
