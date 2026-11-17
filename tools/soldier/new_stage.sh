#!/usr/bin/env bash
# Make a fresh soldier build folder from the repository's generator copy:
#   bash tools/soldier/new_stage.sh <empty_dir>
# Copies tools/soldier/generator/ (project.godot, src/) into <empty_dir> and fills <empty_dir>/ref/ with the game's
# generated inputs: clips.json (exported from godot/assets/anim/humanoid.res by gd/export_clips.gd), humanoid.res and the
# 23-bone rig template infantry.glb (both made by godot/tools/kits.sh; never committed). Then:
#   bash <empty_dir>/src/run_all.sh                     # build (about 25 min on 4 cores; SKIP_BUILD=1 reuses the build)
#   bash tools/soldier/import_stage.sh <empty_dir>      # into the game
# Build folders hold fields, renders and logs (hundreds of MB): keep them outside the repository.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
[ $# -eq 1 ] || { echo "usage: $0 <empty_dir>" >&2; exit 2; }
mkdir -p "$1"
DIR="$(cd "$1" && pwd)"
if [ -n "$(ls -A "$DIR")" ]; then echo "$DIR is not empty" >&2; exit 1; fi
case "$DIR" in "$REPO"|"$REPO"/*) echo "keep build folders outside the repository" >&2; exit 1 ;; esac
if [ -z "${GODOT:-}" ]; then
  for c in "$HOME/godot-bin/godot" "$(command -v godot 2>/dev/null || true)"; do
    if [ -n "$c" ] && [ -x "$c" ]; then GODOT="$c"; break; fi
  done
fi
ANIM="$REPO/godot/assets/anim"
for f in "$ANIM/humanoid.res" "$REPO/godot/assets/kits/infantry.glb"; do
  [ -f "$f" ] || { echo "missing $f: run bash godot/tools/kits.sh first" >&2; exit 1; }
done
cp -r "$HERE/generator/." "$DIR/"
mkdir -p "$DIR/ref" "$DIR/out" "$DIR/work"
cp "$ANIM/humanoid.res" "$REPO/godot/assets/kits/infantry.glb" "$DIR/ref/"
if [ -n "${GODOT:-}" ] && [ -x "$GODOT" ]; then
  "$GODOT" --headless --path "$REPO/godot" -s ../tools/soldier/gd/export_clips.gd -- "$DIR/ref/clips.json" 2>&1 | grep '^wrote' || true
fi
if [ ! -s "$DIR/ref/clips.json" ]; then
  [ -f "$ANIM/clips.json" ] || { echo "no Godot and no $ANIM/clips.json" >&2; exit 1; }
  cp "$ANIM/clips.json" "$DIR/ref/"
fi
echo "ready: $DIR (next: bash $DIR/src/run_all.sh)"
