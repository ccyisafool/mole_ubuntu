#!/usr/bin/env bash
# lib/core.sh — shared helpers: colors, logging, sizes, confirmations, safe removal

MOLE_VERSION="0.3.0"

DRY_RUN=${DRY_RUN:-0}
ASSUME_YES=${ASSUME_YES:-0}
TOTAL_FREED=0

if [[ -t 1 ]]; then
  C_RESET=$'\e[0m'  C_BOLD=$'\e[1m'   C_DIM=$'\e[2m'
  C_RED=$'\e[31m'   C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m'
  C_BLUE=$'\e[34m'  C_MAGENTA=$'\e[35m' C_CYAN=$'\e[36m'
else
  C_RESET='' C_BOLD='' C_DIM=''
  C_RED='' C_GREEN='' C_YELLOW=''
  C_BLUE='' C_MAGENTA='' C_CYAN=''
fi

MOLE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mole"
MOLE_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mole"
MOLE_LOG="$MOLE_STATE_DIR/operations.log"
MOLE_WHITELIST="$MOLE_CONFIG_DIR/whitelist"
mkdir -p "$MOLE_CONFIG_DIR" "$MOLE_STATE_DIR"

section() { printf '\n%s\n' "${C_BOLD}${C_BLUE}▸ $*${C_RESET}"; }
info()    { printf '  %s\n' "$*"; }
ok()      { printf '  %s %s\n' "${C_GREEN}✓${C_RESET}" "$*"; }
warn()    { printf '  %s %s\n' "${C_YELLOW}!${C_RESET}" "$*"; }
err()     { printf '%s\n' "${C_RED}✗ $*${C_RESET}" >&2; }
done_ok() { (( DRY_RUN )) || ok "$*"; }   # success message that stays quiet in dry-run
have()    { command -v "$1" >/dev/null 2>&1; }

log_op() { printf '%s | %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$MOLE_LOG"; }

# fixed-width bar segments (sliced with ${VAR:0:n}; tr can't repeat multi-byte chars)
BAR_FULL='████████████████████████████████████████'
BAR_EMPTY='░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░'

# bytes -> human readable
human_size() {
  awk -v b="${1:-0}" 'BEGIN{
    split("B KB MB GB TB", u); s = 1
    while (b >= 1024 && s < 5) { b /= 1024; s++ }
    printf (s == 1 ? "%d%s" : "%.1f%s"), b, u[s]
  }'
}

# disk usage of a path in bytes (0 if missing)
path_size() {
  local s
  [[ -e $1 || -L $1 ]] || { echo 0; return; }
  s=$(du -sx --block-size=1 -- "$1" 2>/dev/null | cut -f1)
  echo "${s:-0}"
}

confirm() {
  (( ASSUME_YES )) && return 0
  local reply
  # prompt via printf: `read -p` writes to stderr, so pairing it with 2>/dev/null hides it
  printf '  %s [y/N] ' "${C_BOLD}$1${C_RESET}"
  read -r reply 2>/dev/null </dev/tty || { printf '\n'; return 1; }
  [[ $reply == [yY]* ]]
}

# auto-yes when previewing: dry-run shows everything without prompting
confirm_or_dry() {
  (( DRY_RUN )) && return 0
  confirm "$1"
}

# commands that operate on a user-supplied tree (e.g. `mo purge ~/dev`) set this
# to that tree; safe_rm then also accepts paths under it (system paths still refused)
SAFE_RM_ROOT=""

# critical system locations — never deletable, regardless of SAFE_RM_ROOT
_system_path() {
  case "$1" in
    /|/usr|/usr/*|/etc|/etc/*|/var|/var/*|/boot|/boot/*|/bin|/bin/*|/sbin|/sbin/*|\
/lib|/lib/*|/lib64|/lib64/*|/proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/run|/run/*|\
/root|/root/*|/srv|/srv/*|/opt|/opt/*|/snap|/snap/*|/lost+found|/lost+found/*)
      return 0 ;;
  esac
  return 1
}

# paths mo must never delete, even when asked
is_protected() {
  local rp p
  rp=$(realpath -m -- "$1" 2>/dev/null) || return 0
  _system_path "$rp" && return 0
  if [[ $rp != "$HOME"/* ]]; then
    # outside $HOME: only allowed strictly inside an explicitly requested tree
    if [[ -n $SAFE_RM_ROOT && $rp == "$SAFE_RM_ROOT"/* ]]; then
      return 1
    fi
    return 0
  fi
  for p in "$HOME/Documents" "$HOME/Desktop" "$HOME/Pictures" "$HOME/Music" \
           "$HOME/Videos" "$HOME/Downloads" "$HOME/.config" "$HOME/.local" \
           "$HOME/.local/share" "$HOME/.local/state" "$HOME/.cache" \
           "$HOME/snap" "$HOME/.var"; do
    [[ $rp == "$p" ]] && return 0               # the directory itself; children are fine
  done
  for p in "$HOME/.ssh" "$HOME/.gnupg"; do
    [[ $rp == "$p" || $rp == "$p"/* ]] && return 0
  done
  return 1
}

is_whitelisted() {
  [[ -f $MOLE_WHITELIST ]] || return 1
  local rp line
  rp=$(realpath -m -- "$1" 2>/dev/null) || return 1
  while IFS= read -r line; do
    [[ -z $line || $line == \#* ]] && continue
    line="${line/#\~/$HOME}"
    [[ $rp == "$line" || $rp == "$line"/* ]] && return 0
  done <"$MOLE_WHITELIST"
  return 1
}

# remove one path (rm -rf) after safety checks; tracks freed bytes, honors dry-run
safe_rm() {
  local target=$1 sz
  [[ -e $target || -L $target ]] || return 0
  if is_protected "$target"; then
    warn "skip (protected): $target"
    return 1
  fi
  if is_whitelisted "$target"; then
    warn "skip (whitelisted): $target"
    return 1
  fi
  sz=$(path_size "$target")
  if (( DRY_RUN )); then
    info "${C_DIM}[dry-run]${C_RESET} would remove $target ${C_DIM}($(human_size "$sz"))${C_RESET}"
  else
    rm -rf -- "$target" 2>/dev/null || { warn "could not remove: $target"; return 1; }
    ok "removed $target ${C_DIM}($(human_size "$sz"))${C_RESET}"
    log_op "removed $target ($(human_size "$sz"))"
  fi
  TOTAL_FREED=$((TOTAL_FREED + sz))
  return 0
}

# remove the contents of a directory but keep the directory
clean_contents() {
  local dir=$1 entry
  [[ -d $dir ]] || return 0
  for entry in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    [[ -e $entry || -L $entry ]] && safe_rm "$entry"
  done
  return 0
}

# run a system-level command with sudo, honoring dry-run
run_root() {
  if (( DRY_RUN )); then
    info "${C_DIM}[dry-run]${C_RESET} would run: sudo $*"
    return 0
  fi
  if (( EUID == 0 )); then "$@"; else sudo "$@"; fi
  local rc=$?
  (( rc == 0 )) && log_op "ran: $*"
  return $rc
}

# run a user-level command, honoring dry-run
run_user() {
  if (( DRY_RUN )); then
    info "${C_DIM}[dry-run]${C_RESET} would run: $*"
    return 0
  fi
  "$@"
  local rc=$?
  (( rc == 0 )) && log_op "ran: $*"
  return $rc
}

freed_summary() {
  local verb="Freed"
  (( DRY_RUN )) && verb="Would free"
  printf '\n%s\n' "${C_BOLD}${C_GREEN}$verb $(human_size "$TOTAL_FREED")${C_RESET}"
}

# ---- queue: build a list of paths with sizes, show it, then clean it --------
QUEUE_LABELS=()
QUEUE_PATHS=()
QUEUE_SIZES=()
QUEUE_TOTAL=0

queue_reset() { QUEUE_LABELS=(); QUEUE_PATHS=(); QUEUE_SIZES=(); QUEUE_TOTAL=0; }

queue_add() {
  local label=$1 path=$2 sz
  [[ -e $path || -L $path ]] || return 0
  sz=$(path_size "$path")
  (( sz > 0 )) || return 0
  QUEUE_LABELS+=("$label")
  QUEUE_PATHS+=("$path")
  QUEUE_SIZES+=("$sz")
  QUEUE_TOTAL=$((QUEUE_TOTAL + sz))
  return 0
}

queue_show() {
  local i short
  for i in "${!QUEUE_PATHS[@]}"; do
    short="${QUEUE_PATHS[$i]/#$HOME/\~}"
    printf '  %-32s %10s  %s\n' "${QUEUE_LABELS[$i]}" \
      "$(human_size "${QUEUE_SIZES[$i]}")" "${C_DIM}${short}${C_RESET}"
  done
  printf '  %-32s %s\n' "total" "${C_BOLD}$(human_size "$QUEUE_TOTAL")${C_RESET}"
}

queue_clean() {
  local p
  for p in "${QUEUE_PATHS[@]}"; do
    safe_rm "$p"
  done
}

# show queue + confirm + clean; skips silently-ish when queue is empty
queue_flush() {
  local prompt=${1:-"Clean these?"}
  if (( ${#QUEUE_PATHS[@]} == 0 )); then
    info "${C_DIM}nothing to clean${C_RESET}"
    return 0
  fi
  queue_show
  if confirm_or_dry "$prompt"; then
    queue_clean
  else
    info "skipped"
  fi
  queue_reset
}
