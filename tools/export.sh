#!/usr/bin/env bash
# Export the Godot project for one preset, using the flake-pinned engine and
# templates. Run inside `nix develop` (or via `nix develop -c`).
#
#   tools/export.sh web              -> export/web/index.html (+ .wasm, .pck, .js)
#   tools/export.sh linux-x86_64     -> export/linux-x86_64/pogo-pogo.x86_64 + .pck
#   tools/export.sh linux-arm64      -> export/linux-arm64/pogo-pogo.arm64 + .pck
#
# The Linux ARM64 export runs anywhere: Godot exports are cross-platform
# because the template is a prebuilt binary and the .pck is arch-neutral.
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
  web)          preset="Web";          out="export/web/index.html" ;;
  linux-x86_64) preset="Linux x86_64"; out="export/linux-x86_64/pogo-pogo.x86_64" ;;
  linux-arm64)  preset="Linux ARM64";  out="export/linux-arm64/pogo-pogo.arm64" ;;
  *) echo "usage: $0 web|linux-x86_64|linux-arm64" >&2; exit 2 ;;
esac

# Keep build output out of Godot's import scan.
mkdir -p build
touch build/.gdignore

# Godot looks for templates at $XDG_DATA_HOME/godot/export_templates/<ver>/.
# GODOT_EXPORT_TEMPLATES is set by the flake devShell to the pinned package.
: "${GODOT_EXPORT_TEMPLATES:?run inside nix develop}"
ver="$(godot --version | cut -d. -f1-3).stable"
export HOME="$PWD/build/godot-home"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
mkdir -p "$XDG_DATA_HOME/godot/export_templates"
ln -sfn "$GODOT_EXPORT_TEMPLATES/share/godot/export_templates/$ver" \
  "$XDG_DATA_HOME/godot/export_templates/$ver"

stamp="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)$(git diff --quiet 2>/dev/null || echo -dirty)-$(date -u +%Y%m%dT%H%MZ)"
echo "$stamp" > build-stamp.txt

# Two passes: Godot 4 UID resolution can cascade on a cold class registry.
# Retain first-pass diagnostics; only a clean second pass permits export.
first_log="$PWD/build/import-first-${1}.log"
second_log="$PWD/build/import-second-${1}.log"
if ! godot --headless --import >"$first_log" 2>&1 || grep -qE 'SCRIPT ERROR|ERROR:' "$first_log"; then
  echo "first import not clean; retrying UID resolution (see $first_log)" >&2
fi
if ! godot --headless --import >"$second_log" 2>&1; then
  echo "second import failed; see $second_log" >&2
  exit 1
fi
if grep -qE 'SCRIPT ERROR|ERROR:' "$second_log"; then
  echo "second import logged errors; see $second_log" >&2
  exit 1
fi

rm -rf "$(dirname "$out")"
mkdir -p "$(dirname "$out")"
log="$PWD/build/export-${1}.log"
if ! godot --headless --export-release "$preset" "$PWD/$out" >"$log" 2>&1; then
  echo "export failed; see $log" >&2
  exit 1
fi
if grep -qE 'SCRIPT ERROR|^ERROR:' "$log"; then
  echo "export logged errors; see $log" >&2
  exit 1
fi
if [ "$1" = web ]; then
  install -m 644 web/controller.js web/controller.css "$(dirname "$out")/"
fi
[ -f "$out" ] || { echo "export failed: $out missing" >&2; exit 1; }
echo "exported $preset -> $out ($stamp)"
ls -la "$(dirname "$out")"
