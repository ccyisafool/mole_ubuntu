#!/usr/bin/env bash
# mo optimize — refresh package system, databases and caches

run_optimize() {
  printf '%s\n' "${C_BOLD}mo optimize${C_RESET} — refreshing system$( (( DRY_RUN )) && printf ' %s' "${C_YELLOW}(dry run)${C_RESET}")"

  section "Package system ${C_DIM}(sudo)${C_RESET}"
  if confirm_or_dry "Remove packages nothing depends on anymore (apt autoremove)?"; then
    run_root apt-get autoremove --purge -y && done_ok "autoremove done"
  fi
  if confirm_or_dry "Drop obsolete packages from APT cache (apt autoclean)?"; then
    run_root apt-get autoclean -y && done_ok "autoclean done"
  fi

  section "Journal ${C_DIM}(sudo)${C_RESET}"
  if confirm_or_dry "Trim systemd journal to the last 7 days?"; then
    run_root journalctl --vacuum-time=7d && done_ok "journal trimmed"
  fi

  section "SSD / storage ${C_DIM}(sudo)${C_RESET}"
  if confirm_or_dry "Run TRIM on mounted filesystems (fstrim)?"; then
    run_root fstrim -av && done_ok "trim done"
  fi

  section "Search & documentation databases"
  if have updatedb || have plocate-build; then
    if confirm_or_dry "Refresh file-search database (updatedb)?"; then
      run_root updatedb && done_ok "locate db updated"
    fi
  fi
  if have mandb; then
    if confirm_or_dry "Rebuild man-page index (mandb)?"; then
      run_root mandb -q && done_ok "man db updated"
    fi
  fi

  section "Desktop caches ${C_DIM}(user)${C_RESET}"
  if have fc-cache; then
    if confirm_or_dry "Rebuild font cache (fc-cache)?"; then
      run_user fc-cache -f && done_ok "font cache rebuilt"
    fi
  fi
  if have update-desktop-database && [[ -d $HOME/.local/share/applications ]]; then
    if confirm_or_dry "Refresh application launcher database?"; then
      run_user update-desktop-database "$HOME/.local/share/applications" && done_ok "desktop database refreshed"
    fi
  fi

  printf '\n%s\n' "${C_BOLD}${C_GREEN}Optimization pass complete.${C_RESET}"
}
