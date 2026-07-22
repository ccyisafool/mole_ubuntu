#!/usr/bin/env bash
# Install mo by symlinking it into a bin directory (default: ~/.local/bin)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
target="${1:-$HOME/.local/bin}"

mkdir -p "$target"
ln -sf "$here/mo" "$target/mo"
chmod +x "$here/mo"

echo "Installed: $target/mo -> $here/mo"
case ":$PATH:" in
  *:"$target":*) ;;
  *) echo "NOTE: $target is not on your PATH. Add:  export PATH=\"$target:\$PATH\"" ;;
esac
echo "Try: mo --help"
