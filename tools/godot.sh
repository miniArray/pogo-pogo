#!/usr/bin/env bash
# Run the pinned Godot with an isolated home under build/, so checks never read
# or write the developer's own user:// data. Run inside `nix develop`.
#   tools/godot.sh --headless --script tests/course_test.gd
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
touch build/.gdignore
export HOME="$PWD/build/godot-home"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
if [ ! -f .godot/global_script_class_cache.cfg ]; then
  godot --headless --import >/dev/null 2>&1 || true
fi
exec godot "$@"
