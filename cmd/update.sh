#!/usr/bin/env bash
# mo update — update mole itself (git pull for checkouts, tarball refresh otherwise)

MOLE_REPO="ccyisafool/mole_ubuntu"

_remote_version() {
  curl -fsSL -m 10 "https://raw.githubusercontent.com/$MOLE_REPO/main/lib/core.sh" 2>/dev/null \
    | grep -m1 '^MOLE_VERSION=' | cut -d'"' -f2
}

run_update() {
  local check=0 arg
  for arg in "$@"; do
    [[ $arg == --check ]] && check=1
  done

  printf '%s\n' "${C_BOLD}mo update${C_RESET} — installed: v$MOLE_VERSION"

  local remote
  remote=$(_remote_version)
  if [[ -z $remote ]]; then
    err "could not reach GitHub to check the latest version"
    return 1
  fi

  if [[ $remote == "$MOLE_VERSION" ]]; then
    ok "already up to date (v$MOLE_VERSION)"
    return 0
  fi
  # order-aware compare: highest of the two versions, per version-sort
  if [[ $(printf '%s\n%s\n' "$MOLE_VERSION" "$remote" | sort -V | tail -1) == "$MOLE_VERSION" ]]; then
    ok "local v$MOLE_VERSION is newer than published v$remote (dev checkout?) — nothing to do"
    return 0
  fi
  info "latest is ${C_BOLD}v$remote${C_RESET}"

  if (( check )); then
    info "run ${C_BOLD}mo update${C_RESET} to install it"
    return 0
  fi

  if [[ -d $MOLE_HOME/.git ]]; then
    section "Updating git checkout at $MOLE_HOME"
    if run_user git -C "$MOLE_HOME" pull --ff-only; then
      ok "updated"
    else
      err "git pull failed — the checkout has local changes or diverged; update it manually"
      return 1
    fi
  elif [[ -f $MOLE_HOME/mo && -f $MOLE_HOME/lib/core.sh && -d $MOLE_HOME/cmd ]]; then
    section "Refreshing tarball install at $MOLE_HOME"
    if (( DRY_RUN )); then
      info "${C_DIM}[dry-run]${C_RESET} would re-download $MOLE_REPO into $MOLE_HOME"
    else
      local tmp="$MOLE_HOME.tmp"
      rm -rf "$tmp"
      mkdir -p "$tmp"
      if curl -fsSL "https://github.com/$MOLE_REPO/archive/refs/heads/main.tar.gz" \
          | tar -xz -C "$tmp" --strip-components=1; then
        rm -rf "$MOLE_HOME"
        mv "$tmp" "$MOLE_HOME"
        chmod +x "$MOLE_HOME/mo"
        log_op "updated mole v$MOLE_VERSION -> v$remote"
        ok "updated"
      else
        rm -rf "$tmp"
        err "download failed; nothing was changed"
        return 1
      fi
    fi
  else
    err "cannot tell how mole was installed at $MOLE_HOME"
    info "re-run the installer instead:"
    info "  curl -fsSL https://raw.githubusercontent.com/$MOLE_REPO/main/install.sh | bash"
    return 1
  fi

  local now
  now=$(grep -m1 '^MOLE_VERSION=' "$MOLE_HOME/lib/core.sh" | cut -d'"' -f2)
  printf '\n%s\n' "${C_BOLD}${C_GREEN}v$MOLE_VERSION → v${now:-?}${C_RESET}"
}
