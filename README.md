# Mole for Ubuntu (and friends)

A terminal utility for Linux inspired by [tw93/mole](https://github.com/tw93/mole) (macOS):
system cleaning, app uninstalling, disk analysis and live monitoring in one `mo` command.
Pure Bash — no dependencies beyond a stock install. Born on Ubuntu (hence the name),
now speaking every major package family.

## Supported systems

| Family  | Distros                             | Package backend | Tested on                              |
| ------- | ----------------------------------- | --------------- | -------------------------------------- |
| deb     | Ubuntu, Debian, Mint, Pop!_OS, ...  | apt             | Ubuntu 26.04 (daily use), Debian 13 VM |
| rpm     | Fedora, RHEL, Rocky, Alma, ...      | dnf             | Fedora 44 container                    |
| arch    | Arch, Manjaro, EndeavourOS, ...     | pacman          | Arch container                         |
| OpenWrt | OpenWrt, iStoreOS (routers/NAS)     | — (`mo-lite`)   | iStoreOS 24.10 VM                      |

Snap and flatpak are handled wherever present. Systems without systemd skip the
journal steps automatically.

### mo-lite (OpenWrt-class devices)

Routers don't have bash, so `lite/mo-lite` is a self-contained POSIX-sh subset
(BusyBox-compatible): `clean` (opkg lists, LuCI caches, stray .ipk, rotated logs),
`analyze`, `status`. It's one file, so installing is one line — on the router:

```bash
wget -O /usr/bin/mo https://raw.githubusercontent.com/ccyisafool/mole-for-ubuntu-and-friends/main/lite/mo-lite && chmod +x /usr/bin/mo
```

(Needs HTTPS-capable wget — stock on modern OpenWrt/iStoreOS; minimal builds may
need `opkg install libustream-openssl ca-bundle` first.) The script presents
itself under whatever name you install it as — `mo` gives you the same muscle
memory as the desktop version; bare `mo` shows the status dashboard. Update
later with `mo update` — it downloads to a temp file, sanity-checks it, and
replaces itself atomically; on failure the current install is untouched.

If the router can't reach GitHub, push it over SSH from any machine with a clone —
works even when the router has no scp/sftp installed:

```bash
cat lite/mo-lite | ssh root@<router-ip> 'cat > /usr/bin/mo && chmod +x /usr/bin/mo'
```

![mo in action: launcher menu and live status dashboard](demo.gif)

## Install

One-liner (downloads to `~/.local/share/mole-ubuntu`, links `mo` into `~/.local/bin`):

```bash
curl -fsSL https://raw.githubusercontent.com/ccyisafool/mole-for-ubuntu-and-friends/main/install.sh | bash
```

Or from a clone (symlinks the checkout, so edits take effect immediately):

```bash
git clone https://github.com/ccyisafool/mole-for-ubuntu-and-friends.git && cd mole-for-ubuntu-and-friends
./install.sh
```

Update any time with `mo update`. Uninstall: `install.sh --uninstall`. Then:

```bash
mo --help
```

## Commands

| Command        | What it does                                                                 |
| -------------- | ---------------------------------------------------------------------------- |
| `mo clean`     | Trash, thumbnails, browser caches, dev-tool caches, APT cache, journal, rotated logs, old snap revisions & saved snapshots, flatpak caches & unused runtimes |
| `mo uninstall` | Remove an app via apt / snap / flatpak, then hunt down leftover config, cache, autostart entries and systemd user units |
| `mo optimize`  | `apt autoremove`/`autoclean`, journal trim, `fstrim`, `updatedb`, `mandb`, font & launcher caches |
| `mo analyze`   | Interactive disk-usage explorer with size bars (drill down, go up)           |
| `mo status`    | Live dashboard: CPU, memory, disk, network rates, temperature, battery, top processes |
| `mo purge`     | Find & delete build artifacts: `node_modules`, Rust `target`, `__pycache__`, `.pytest_cache`, `.mypy_cache`, `.tox`, `.next`, Gradle `build` |
| `mo installer` | Find leftover installers (`.deb`, `.iso`, `.run`, `.AppImage`, …) in Downloads/Desktop and offer removal |
| `mo update`    | Update mole itself (`--check` to only compare versions)                      |

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

## Credits

This project is a tribute to **[Mole](https://github.com/tw93/mole)** by
**[Tw93](https://github.com/tw93)** — the excellent macOS system-maintenance CLI
that defined the `mo` command set (clean / uninstall / optimize / analyze /
status / purge / installer) and the philosophy this port follows: one small
tool, visible before destructive, safe by default.

Mole for Ubuntu is an independent clean-room reimplementation for Linux: it
shares the original's command design and spirit but none of its code (the
original is GPL-3.0; this codebase is written from scratch for Ubuntu and
released under MIT). If you're on macOS, use the original — it's more mature.

## Layout

```
mo               entry point / dispatcher
lib/core.sh      colors, logging, sizes, confirmations, protected-path checks, safe_rm
cmd/<name>.sh    one file per command (clean, uninstall, optimize, analyze, status, purge, installer)
install.sh       symlink installer
```
