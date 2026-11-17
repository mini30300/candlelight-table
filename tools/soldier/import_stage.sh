#!/usr/bin/env bash
# Import one soldier stage into the game in a single step:
#   bash tools/soldier/import_stage.sh <stage_dir>
# <stage_dir> is a generator folder (tools/soldier/README.md): project.godot, src/ (py, gd, run_all.sh) and its build in
# out/godot/ (rig.tscn, skin.res, body_hi/mid/lo/min.res, optional body_crowd.res and clips.res, soldier_skin.tres) and
# out/data/rig.json. Steps, and nothing in the repository changes unless the first two succeed:
#  1. Godot re-saves the stage's files in a scratch project, so every path inside them points at the game's copy:
#     godot/assets/figures/soldier/{rig.tscn, skin.res, body_<level>.res, body.gdshader, body_material.tres, clips.res};
#     rig.json's driver constants travel inside rig.tscn (metadata "soldier_rig"); existing UIDs are kept.
#  2. The stage's generator source is checked for the banned names of AGENTS.md rule 1.
#  3. Assets go to godot/assets/figures/soldier/ (files the stage no longer makes are removed) and the source to
#     tools/soldier/generator/ (the durable copy matches the assets), the game project is re-imported and IMPORTED.txt
#     records the stage, the levels and the hashes.
# Then run the tests listed in tools/soldier/README.md. Environment: GODOT (default ~/godot-bin/godot, then godot on PATH).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
[ $# -eq 1 ] || { echo "usage: $0 <stage_dir>" >&2; exit 2; }
STAGE="$(cd "$1" && pwd)"
if [ -z "${GODOT:-}" ]; then
  for c in "$HOME/godot-bin/godot" "$(command -v godot 2>/dev/null || true)"; do
    if [ -n "$c" ] && [ -x "$c" ]; then GODOT="$c"; break; fi
  done
fi
if [ -z "${GODOT:-}" ] || [ ! -x "$GODOT" ]; then echo "no Godot binary: set GODOT" >&2; exit 2; fi
PY=/usr/bin/python3
[ -x "$PY" ] || PY=python3
DEST="$REPO/godot/assets/figures/soldier"
GEN="$HERE/generator"
OUTG="$STAGE/out/godot"

for f in rig.tscn skin.res soldier_skin.tres body_hi.res body_mid.res body_lo.res body_min.res; do
  [ -f "$OUTG/$f" ] || { echo "missing $OUTG/$f" >&2; exit 1; }
done
for f in src/gd/soldier_skin.gdshader src/run_all.sh; do
  [ -f "$STAGE/$f" ] || { echo "missing $STAGE/$f" >&2; exit 1; }
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/soldier_import.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/out/godot" "$WORK/out/data" "$WORK/src/gd" "$WORK/old"
for f in rig.tscn skin.res soldier_skin.tres body_hi.res body_mid.res body_lo.res body_min.res body_crowd.res \
    clips.res soldier_clips.res humanoid_soldier.res; do
  if [ -f "$OUTG/$f" ]; then cp "$OUTG/$f" "$WORK/out/godot/"; fi
done
if [ -f "$STAGE/out/data/rig.json" ]; then cp "$STAGE/out/data/rig.json" "$WORK/out/data/"; fi
cp "$STAGE/src/gd/soldier_skin.gdshader" "$WORK/src/gd/"
# the game's current files: only their UIDs are read, so a re-import changes content, not identity
if [ -d "$DEST" ]; then
  for f in "$DEST"/*.res "$DEST"/*.tres "$DEST"/*.tscn; do
    if [ -f "$f" ]; then cp "$f" "$WORK/old/"; fi
  done
fi
cat > "$WORK/project.godot" <<'EOF'
config_version=5

[application]
config/name="soldier-import"

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
EOF
cp "$HERE/gd/import_stage.gd" "$WORK/import_stage.gd"

echo "== 1. re-save the stage's files with the game's paths =="
"$GODOT" --headless --path "$WORK" -s import_stage.gd 2>&1 | grep -v -e '^Godot Engine' -e '^$' || true
[ -f "$WORK/report.json" ] || { echo "the Godot step failed (no report): nothing was changed" >&2; exit 1; }

echo "== 2. generator source: banned-name check =="
NEWGEN="$WORK/generator"
mkdir -p "$NEWGEN/src/py" "$NEWGEN/src/gd"
cp "$STAGE"/src/py/*.py "$NEWGEN/src/py/"
for f in "$STAGE"/src/gd/*.gd "$STAGE"/src/gd/*.gdshader; do
  if [ -f "$f" ]; then cp "$f" "$NEWGEN/src/gd/"; fi
done
cp "$STAGE/src/run_all.sh" "$NEWGEN/src/"
if [ -f "$STAGE/project.godot" ]; then cp "$STAGE/project.godot" "$NEWGEN/"; fi
"$PY" "$HERE/check_names.py" --fix-math "$NEWGEN" || { echo "banned names in the stage's source: nothing was changed" >&2; exit 1; }

echo "== 3. copy into the repository =="
mkdir -p "$DEST"
NEW="$WORK/assets/figures/soldier"
# files the new stage no longer makes (a crowd level, a clip copy) go; .uid sidecars of kept files stay
for f in "$DEST"/*; do
  [ -f "$f" ] || continue
  base="$(basename "$f")"
  case "$base" in
    *.uid|IMPORTED.txt) continue ;;
  esac
  if [ ! -f "$NEW/$base" ]; then echo "remove $base"; rm -f "$f" "$f.uid"; fi
done
cp "$NEW"/* "$DEST/"
rm -rf "$GEN"
mkdir -p "$GEN"
cp -r "$NEWGEN"/. "$GEN"/
echo "assets -> $DEST"
echo "source -> $GEN"

echo "== import the game project =="
LOCK="$REPO/godot/.import.lock"
if command -v flock > /dev/null; then
  flock "$LOCK" "$GODOT" --headless --path "$REPO/godot" --import > "$WORK/import.log" 2>&1 || { tail -20 "$WORK/import.log"; exit 1; }
else
  "$GODOT" --headless --path "$REPO/godot" --import > "$WORK/import.log" 2>&1 || { tail -20 "$WORK/import.log"; exit 1; }
fi
if grep -q 'ERROR' "$WORK/import.log"; then grep 'ERROR' "$WORK/import.log" | head -10; fi

echo "== record =="
"$PY" - "$WORK/report.json" "$DEST" "$(basename "$STAGE")" <<'PY'
import hashlib, json, os, sys
rep = json.load(open(sys.argv[1]))
dest, stage = sys.argv[2], sys.argv[3]
lines = ["Soldier assets imported by tools/soldier/import_stage.sh from stage '%s'." % stage,
         "Do not edit these files by hand: change the generator (tools/soldier/generator) and import again.", "",
         "level  surfaces  verts   tris  blend_shapes    bytes"]
for lv in ["hi", "mid", "lo", "min", "crowd"]:
    if lv in rep["levels"]:
        r = rep["levels"][lv]
        lines.append("%-6s %8d %6d %6d %13d %8d" % (lv, r["surfaces"], r["verts"], r["tris"], r["shapes"], r["bytes"]))
lines += ["", "bones (%d): %s" % (len(rep["bones"]), " ".join(rep["bones"])), "motion_scale: %.4f" % rep["motion_scale"]]
lines.append("driver constants: %s" % ("from the stage's rig.json" if "drivers" in rep else "none (the figure's stage-1 defaults)"))
if "clips" in rep:
    lines.append("soldier clip copy: %d clips (from %s)" % (rep["clips"]["count"], rep["clips"]["from"]))
else:
    lines.append("soldier clip copy: none (the figure uses assets/anim/humanoid.res with its wrists eased)")
lines += ["", "sha256:"]
for name in sorted(os.listdir(dest)):
    p = os.path.join(dest, name)
    if name.endswith((".uid", ".txt")) or not os.path.isfile(p):
        continue
    lines.append("  %s  %s  %d bytes" % (hashlib.sha256(open(p, "rb").read()).hexdigest(), name, os.path.getsize(p)))
open(os.path.join(dest, "IMPORTED.txt"), "w").write("\n".join(lines) + "\n")
print("\n".join(lines))
PY
echo
echo "done. Next: the tests in tools/soldier/README.md (bash godot/tests/run.sh soldier, then the render suites)"
