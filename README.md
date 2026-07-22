# Mole for Ubuntu

A terminal utility for Ubuntu inspired by [tw93/mole](https://github.com/tw93/mole) (macOS):
system cleaning, app uninstalling, disk analysis and live monitoring in one `mo` command.
Pure Bash — no dependencies beyond a stock Ubuntu install.

## Install

```bash
./install.sh            # symlinks mo into ~/.local/bin
mo --help
```

## Commands

| Command        | What it does                                                                 |
| -------------- | ---------------------------------------------------------------------------- |
| `mo clean`     | Trash, thumbnails, browser caches, dev-tool caches, APT cache, journal, rotated logs, old snap revisions, flatpak caches & unused runtimes |
| `mo uninstall` | Remove an app via apt / snap / flatpak, then hunt down leftover config, cache, autostart entries and systemd user units |
| `mo optimize`  | `apt autoremove`/`autoclean`, journal trim, `fstrim`, `updatedb`, `mandb`, font & launcher caches |
| `mo analyze`   | Interactive disk-usage explorer with size bars (drill down, go up)           |
| `mo status`    | Live dashboard: CPU, memory, disk, network rates, temperature, battery, top processes |
| `mo purge`     | Find & delete build artifacts: `node_modules`, Rust `target`, `__pycache__`, `.pytest_cache`, `.mypy_cache`, `.tox`, `.next`, Gradle `build` |
| `mo installer` | Find leftover installers (`.deb`, `.iso`, `.run`, `.AppImage`, …) in Downloads/Desktop and offer removal |

## Global options

```
-n, --dry-run    preview everything, delete nothing
-y, --yes        skip confirmation prompts
```

Examples:

```bash
mo clean --dry-run          # see what would be cleaned
mo clean --deep             # also sweep all of ~/.cache, gradle, maven
mo uninstall firefox        # search all three package sources
mo analyze ~/projects       # explore a specific tree
mo purge ~/dev              # scan a specific tree for build artifacts
mo status --once            # one snapshot instead of a live dashboard
```

## Safety model

- **Dry-run everywhere** — `-n/--dry-run` previews every command with sizes.
- **Protected paths** — `mo` refuses to delete anything outside `$HOME`, and never
  deletes `~/Documents`, `~/Pictures`, `~/.ssh`, `~/.gnupg`, top-level XDG dirs, etc.
  System-level cleaning goes through the proper tools (`apt-get clean`, `journalctl
  --vacuum-time`, `snap remove --revision`) rather than raw deletion.
- **Whitelist** — paths listed in `~/.config/mole/whitelist` (one per line, `~` allowed,
  `#` comments) are never touched.
- **Operation log** — every removal and system command is appended to
  `~/.local/state/mole/operations.log`.
- **Confirmations** — each category asks before deleting; `--yes` opts out.

## Layout

```
mo               entry point / dispatcher
lib/core.sh      colors, logging, sizes, confirmations, protected-path checks, safe_rm
cmd/<name>.sh    one file per command (clean, uninstall, optimize, analyze, status, purge, installer)
install.sh       symlink installer
```
