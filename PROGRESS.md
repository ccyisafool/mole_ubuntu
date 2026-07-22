# mole_ubuntu — Build Progress

> **Rules for agents working in this repo:**
> 1. Read this file before starting any work.
> 2. Claim a task by setting its status to `IN PROGRESS (<agent/session note>)` before editing.
> 3. Set it to `DONE` only after `bash -n` passes and a dry-run smoke test ran.
> 4. Log anything surprising in the Notes section at the bottom — don't silently work around it.

## Project

Ubuntu port of [tw93/mole](https://github.com/tw93/mole) (macOS maintenance CLI).
Decisions confirmed by user: **full command parity, Bash implementation, apt + snap + flatpak support.**

Layout: `mo` (dispatcher) → sources `lib/core.sh` → sources `cmd/<command>.sh` → calls `run_<command> "$@"`.
Each `cmd/<name>.sh` must define exactly one entry function `run_<name>`.
All deletion MUST go through `safe_rm`/`clean_contents` (safety checks, dry-run, whitelist, logging) and
system commands through `run_root`/`run_user` (dry-run aware). Never call `rm`/`sudo` directly in cmd scripts.

## Task status

| # | Task | File | Status |
|---|------|------|--------|
| 1 | Dispatcher, arg parsing, usage | `mo` | DONE |
| 2 | Core library (colors, safe_rm, queue, dry-run, whitelist, log) | `lib/core.sh` | DONE |
| 3 | Installer script | `install.sh` | DONE |
| 4 | `mo clean` — user/system/snap/flatpak cache cleaning | `cmd/clean.sh` | DONE (agent, reviewed by main session) |
| 5 | `mo purge` — build artifact removal | `cmd/purge.sh` | DONE (agent, reviewed by main session) |
| 6 | `mo installer` — leftover installer file removal | `cmd/installer.sh` | DONE (agent, reviewed by main session) |
| 7 | `mo analyze` — disk usage explorer | `cmd/analyze.sh` | DONE (agent, reviewed by main session) |
| 8 | `mo status` — live system dashboard | `cmd/status.sh` | DONE (agent, reviewed by main session) |
| 9 | `mo optimize` — system refresh tasks | `cmd/optimize.sh` | DONE (agent, reviewed by main session) |
| 10 | `mo uninstall` — apt/snap/flatpak uninstall + leftover scan | `cmd/uninstall.sh` | DONE (agent, reviewed by main session) |
| 11 | README | `README.md` | DONE (agent, reviewed by main session) |
| 12 | Syntax check all files (`bash -n`, shellcheck if present) | — | DONE (bash -n clean on all 10 files; shellcheck not installed on this box) |
| 13 | Smoke tests: `--help`, `clean -n`, `purge -n` (fixture tree), `analyze` (non-tty), `status --once`, `installer -n`, `uninstall` (list mode) | — | DONE (all pass; see Notes) |
| 14 | Git repository init + baseline commit | — | DONE (main session) |

## Conventions

- Global flags `-n/--dry-run`, `-y/--yes` are parsed in `mo` and exported as `DRY_RUN`/`ASSUME_YES`.
- In dry-run, prompts auto-accept (`confirm_or_dry`) so the full preview prints non-interactively.
- `confirm` reads from `/dev/tty`; with no tty it returns "no" → safe default.
- Freed bytes accumulate in `TOTAL_FREED`; end user-facing commands with `freed_summary` where relevant.
- Only paths under `$HOME` may be deleted directly; system-side cleanup goes through `run_root` with explicit commands (`apt-get clean`, `journalctl --vacuum-time`, `find /var/log ... -delete`).

## Notes

- (2026-07-22) Git initialized at user's request. **Agents: commit your completed task with a
  scoped message (e.g. `clean: handle snap caches`) rather than piling into one commit; pull the
  latest state before editing — several files have been modified concurrently in this repo.**
- (2026-07-22) `is_protected` gained `_system_path` hard-blocks plus a `SAFE_RM_ROOT` escape hatch:
  deletion outside `$HOME` is allowed only strictly inside a tree the user explicitly passed
  (only `cmd/purge.sh` sets it). Keep it that way.
- (2026-07-22) Bar rendering must use `${BAR_FULL:0:n}`/`${BAR_EMPTY:0:n}` from core.sh — `tr` is
  byte-oriented and corrupts multi-byte block characters.
- (2026-07-22) `read ... 2>/dev/null </dev/tty` — the stderr redirect must come BEFORE `</dev/tty`
  or bash's open-failure message leaks in non-tty runs (redirections apply left to right).
- (2026-07-22) Smoke tests all passed on this box: version/help, `status --once` (CPU/mem/disk/net/top),
  `clean -n --user-only` (real caches listed, correct sizes), `purge -n` on a fixture tree
  (marker-file checks verified: `target` without `Cargo.toml` correctly skipped), `analyze --top 5`
  non-tty, `installer -n` (found real .debs in ~/Downloads), `optimize -n`, `uninstall firefox`
  non-tty (safe cancel). Not yet exercised for real: actual deletion paths, snap/flatpak removal,
  interactive pickers, live `status` loop.
