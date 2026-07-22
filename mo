#!/usr/bin/env bash
# mo — Mole for Ubuntu: system cleaning, app management, disk analysis & monitoring
set -o pipefail

MOLE_HOME="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib/core.sh
source "$MOLE_HOME/lib/core.sh"

usage() {
  cat <<EOF
${C_BOLD}mo${C_RESET} — Mole for Ubuntu v$MOLE_VERSION

${C_BOLD}Usage:${C_RESET} mo [command] [options]     (bare ${C_BOLD}mo${C_RESET} opens the interactive menu)

${C_BOLD}Commands:${C_RESET}
  clean       Remove caches, logs and temporary files (user, system, snap, flatpak)
  uninstall   Remove a package/app (apt, snap, flatpak) and its leftovers
  optimize    Refresh package system, databases and caches
  analyze     Explore disk usage, find large files and directories
  status      Live dashboard: CPU, memory, disk, network, battery
  purge       Delete build artifacts (node_modules, target, __pycache__, ...)
  installer   Find and remove leftover installer files (.deb, .iso, .run, ...)
  update      Update mole itself to the latest version (--check to only look)

${C_BOLD}Global options:${C_RESET}
  -n, --dry-run    Preview everything, delete nothing
  -y, --yes        Skip confirmation prompts
  -V, --version    Print version
  -h, --help       Show this help

${C_BOLD}Command options:${C_RESET}
  clean     [--deep] [--user-only]        --deep also sweeps all of ~/.cache & gradle
  uninstall [name]                        no name = pick from installed apps
  analyze   [path] [--top N]              default path: \$HOME
  status    [--once] [--interval N]
  purge     [path]                        default path: \$HOME
  installer [--all-home]                  also scan \$HOME top level

${C_BOLD}Safety:${C_RESET}
  Whitelist (never touched):  ~/.config/mole/whitelist  (one path per line, ~ ok)
  Operation log:              ~/.local/state/mole/operations.log
  Protected: everything outside \$HOME, ~/Documents, ~/Pictures, ~/.ssh, ~/.gnupg, ...
EOF
}

CMD=""
ARGS=()
while (($#)); do
  case "$1" in
    -n|--dry-run) DRY_RUN=1 ;;
    -y|--yes)     ASSUME_YES=1 ;;
    -V|--version) echo "mo (mole for ubuntu) v$MOLE_VERSION"; exit 0 ;;
    -h|--help)    usage; exit 0 ;;
    *) if [[ -z $CMD ]]; then CMD="$1"; else ARGS+=("$1"); fi ;;
  esac
  shift
done

if [[ -z $CMD ]]; then
  if [[ -t 0 && -t 1 ]]; then
    CMD="menu"          # bare `mo` in a terminal opens the launcher
  else
    usage
    exit 0
  fi
fi

case "$CMD" in
  clean|uninstall|optimize|analyze|status|purge|installer|update|menu)
    # shellcheck disable=SC1090
    source "$MOLE_HOME/cmd/$CMD.sh"
    "run_$CMD" "${ARGS[@]}"
    ;;
  *)
    err "unknown command: $CMD"
    usage
    exit 1
    ;;
esac
