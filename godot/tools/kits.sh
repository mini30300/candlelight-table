#!/usr/bin/env bash
# kits.sh — one command that regenerates everything derived from the old page's figure kits (CI job `kits`, or locally):
#   1. node godot/tools/export_kits.js   → godot/assets/kits/*.glb + kits.json   (Playwright + Chromium, ~45 s)
#   2. godot/tools/bake_impostors.gd     → godot/assets/impostors/              (under xvfb; lands with R0-D)
#   3. godot/tools/bake_anim.gd          → godot/assets/anim/                   (headless; lands with R1-V2)
# A bake tool that does not exist yet is skipped with a note, so the command already works before those tracks land.
#
#   bash godot/tools/kits.sh [options passed on to export_kits.js, e.g. --only heavy,archer]
# Env: CHROMIUM_PATH (Playwright's browser; found under /opt/pw-browsers when unset), GODOT (the editor binary for
#      the bakes; default ~/godot-bin/godot, then `godot` on PATH), KITS_SKIP_EXPORT=1 (run only the bakes).
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT"
say() { echo "kits.sh: $*"; }
die() { say "ERROR: $*"; exit 1; }

# 1. the kits
if [ "${KITS_SKIP_EXPORT:-0}" = 1 ]; then
  say "kit export skipped (KITS_SKIP_EXPORT=1)"
else
  [ -d tests/node_modules/playwright ] || die "tests/node_modules/playwright is missing: run 'cd tests && npm ci && npx playwright install chromium' first"
  if [ -z "${CHROMIUM_PATH:-}" ]; then
    found=$(ls -d /opt/pw-browsers/chromium-*/chrome-linux*/chrome 2> /dev/null | head -n 1 || true)
    [ -z "$found" ] || export CHROMIUM_PATH="$found"
  fi
  say "exporting the kits from app/src/main/assets/battle-table.html${CHROMIUM_PATH:+ with CHROMIUM_PATH=$CHROMIUM_PATH}"
  node godot/tools/export_kits.js "$@"
fi
[ -s godot/assets/kits/kits.json ] || die "godot/assets/kits/kits.json is missing or empty"
say "kits: $(ls godot/assets/kits/*.glb 2> /dev/null | wc -l) .glb, $(du -sh godot/assets/kits | cut -f1)"

# 2. + 3. the bakes need the editor binary and the kits imported once
bakes=()
[ -f godot/tools/bake_impostors.gd ] && bakes+=(impostors)
[ -f godot/tools/bake_anim.gd ] && bakes+=(anim)
if [ ${#bakes[@]} -eq 0 ]; then
  say "no godot/tools/bake_impostors.gd or bake_anim.gd yet: nothing to bake"
  say "done"
  exit 0
fi
G="${GODOT:-}"
if [ -z "$G" ] && [ -x "$HOME/godot-bin/godot" ]; then G="$HOME/godot-bin/godot"; fi
if [ -z "$G" ]; then G=$(command -v godot || true); fi
[ -n "$G" ] && [ -x "$G" ] || die "the bakes need Godot: run 'bash godot/tools/godot.sh' or set GODOT=<binary>"
log="${TMPDIR:-/tmp}/kits-import.log"
say "importing the kits with $G (log: $log)"
"$G" --headless --path godot --import > "$log" 2>&1 || { tail -n 30 "$log"; die "import failed"; }

if [ -f godot/tools/bake_impostors.gd ]; then
  command -v xvfb-run > /dev/null || die "bake_impostors.gd needs xvfb-run and Mesa (apt-get install xvfb libgl1-mesa-dri)"
  say "baking impostors under xvfb"
  timeout 1500 xvfb-run -a -s "-screen 0 1280x720x24" "$G" --path godot --rendering-driver opengl3 --audio-driver Dummy -s tools/bake_impostors.gd
  [ -n "$(ls -A godot/assets/impostors 2> /dev/null)" ] || die "bake_impostors.gd wrote nothing to godot/assets/impostors"
  say "impostors: $(ls godot/assets/impostors | wc -l) files"
fi
if [ -f godot/tools/bake_anim.gd ]; then
  say "baking animation clips"
  timeout 900 "$G" --headless --path godot -s tools/bake_anim.gd
  [ -n "$(ls -A godot/assets/anim 2> /dev/null)" ] || die "bake_anim.gd wrote nothing to godot/assets/anim"
  say "anim: $(ls godot/assets/anim | wc -l) files"
fi
say "done"
