#!/usr/bin/env bash
# mo installer — find and remove leftover installer files

run_installer() {
  local all_home=0 arg
  for arg in "$@"; do
    [[ $arg == --all-home ]] && all_home=1
  done

  printf '%s\n' "${C_BOLD}mo installer${C_RESET} — leftover installer files$( (( DRY_RUN )) && printf ' %s' "${C_YELLOW}(dry run)${C_RESET}")"

  local -a name_tests=(
    -iname '*.deb' -o -iname '*.rpm' -o -iname '*.run' -o -iname '*.iso'
    -o -iname '*.img' -o -iname '*.snap' -o -iname '*.flatpak'
    -o -iname '*.flatpakref' -o -iname '*.appimage'
  )

  local files=() f
  while IFS= read -r f; do files+=("$f"); done < <(
    { find "$HOME/Downloads" "$HOME/Desktop" -maxdepth 3 -type f \( "${name_tests[@]}" \) 2>/dev/null
      (( all_home )) && find "$HOME" -maxdepth 1 -type f \( "${name_tests[@]}" \) 2>/dev/null
    } | sort -u)

  if (( ${#files[@]} == 0 )); then
    info "no installer files found in ~/Downloads or ~/Desktop"
  else
    section "Found ${#files[@]} installer file(s)"
    local i sz date tag total=0
    for i in "${!files[@]}"; do
      f="${files[$i]}"
      sz=$(path_size "$f")
      total=$((total + sz))
      date=$(date -r "$f" '+%Y-%m-%d' 2>/dev/null || echo '?')
      tag=""
      [[ ${f,,} == *.appimage ]] && tag=" ${C_YELLOW}(AppImage — may be an app you still use!)${C_RESET}"
      printf '  %3d) %8s  %s  %s%s\n' "$((i + 1))" "$(human_size "$sz")" "$date" "${f/#$HOME/\~}" "$tag"
    done
    printf '  %s\n' "${C_BOLD}total: $(human_size "$total")${C_RESET}"

    local selection
    if (( DRY_RUN )); then
      info "${C_DIM}[dry-run] nothing will be deleted${C_RESET}"
    elif (( ASSUME_YES )); then
      selection="a"
    else
      printf '  %s ' "${C_BOLD}Delete which? (numbers, 'a' for all, 'q' to skip)${C_RESET}"
      read -r selection 2>/dev/null </dev/tty || { printf '\n'; selection="q"; }
    fi

    if (( ! DRY_RUN )); then
      case "$selection" in
        q|Q|"") info "skipped" ;;
        a|A) for f in "${files[@]}"; do safe_rm "$f"; done ;;
        *)
          local n
          for n in $selection; do
            if [[ $n =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#files[@]} )); then
              safe_rm "${files[$((n - 1))]}"
            else
              warn "invalid selection: $n"
            fi
          done
          ;;
      esac
    fi
  fi

  # APT downloaded package archives
  section "APT downloaded packages ${C_DIM}(sudo)${C_RESET}"
  local apt_sz
  apt_sz=$(path_size /var/cache/apt/archives)
  if (( apt_sz > 100 * 1024 )); then
    info "cached .deb archives: $(human_size "$apt_sz")"
    if confirm_or_dry "Clear APT package cache?"; then
      run_root apt-get clean
      TOTAL_FREED=$((TOTAL_FREED + apt_sz))
    fi
  else
    info "${C_DIM}APT cache already clean${C_RESET}"
  fi

  freed_summary
}
